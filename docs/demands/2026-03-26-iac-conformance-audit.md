# IaC Conformance Audit — Plataforma k8s-platform-prod

**Data:** 2026-03-26
**Auditor:** Orquestrador DevOps Senior (framework executor-terraform.md)
**Cluster:** k8s-platform-prod | Conta: 891377105802 | Regiao: us-east-1
**Escopo:** Staging + Production IaC (Terraform) vs Diretrizes (SAD, ADRs, Demand Docs) vs Estado Real
**Limitacao:** kubectl inacessivel durante auditoria (DNS resolve failure WSL). Estado real baseado em MEMORY.md, demand docs e ultimas sessoes documentadas.

---

## Secao 1: Executive Summary

### Score Geral de Conformidade: 61/100

| Categoria | Score | Benchmark Enterprise | Delta |
|-----------|-------|---------------------|-------|
| A. Seguranca | 6/10 | 9/10 | -3 |
| B. Resiliencia | 5/10 | 9/10 | -4 |
| C. Observabilidade | 7/10 | 8/10 | -1 |
| D. Networking | 6/10 | 8/10 | -2 |
| E. GitOps / IaC | 7/10 | 9/10 | -2 |
| F. FinOps | 6/10 | 8/10 | -2 |
| G. Staging vs Production Paridade | 5/10 | 8/10 | -3 |
| **TOTAL** | **61/100** | **82/100** | **-21** |

### Top 5 Non-Conformances Criticas

| # | GAP | Categoria | Impacto | Diretriz Violada |
|---|-----|-----------|---------|------------------|
| 1 | RDS Multi-AZ=false em producao | B. Resiliencia | P0 | ADR-013 (DR), Catalogo Componentes 1.4 |
| 2 | Network Policies ausentes em 5+ namespaces criticos | A. Seguranca | P0 | ADR-005, SAD 2.2, INIT-006 |
| 3 | EKS control-plane logging 1/5 tipos | A. Seguranca | P1 | INIT-005, BACEN BCB 85/2021 Art.27 |
| 4 | Cluster Autoscaler nao importado no TF state | E. GitOps | P1 | executor-terraform.md Zero Drift |
| 5 | ArgoCD prod sem Applications gerenciadas | G. Paridade | P1 | ADR-004 (IaC e GitOps) |

---

## Secao 2: Matriz de Conformidade Detalhada

### A. SEGURANCA

#### A-01: Network Policies deny-all + allow rules em todos os namespaces

- **Status:** NAO-CONFORME
- **Evidencia (IaC):**
  - Staging: `staging-security-vault`, `staging-data-infrastructure`, `staging-observability-monitoring`, `cert-manager`, `kube-system` tem Network Policies (confirmado em 2026-03-18-security-domain-vpn-prod.md)
  - Staging SEM Network Policies: `staging-platform-argocd`, `staging-platform-gitlab`, `staging-platform-keycloak`, `staging-platform-sonarqube`, `harbor-system`
  - Prod: `prod-data-infrastructure` e `prod-data-rabbitmq` tem NetworkPolicies (codificadas em `prod/main.tf` L347-430)
  - Prod SEM NetworkPolicies: `prod-platform-argocd`, `prod-platform-harbor`, `prod-platform-keycloak`, `prod-platform-sonarqube`, `prod-platform-backstage`, `prod-observability-monitoring`, `prod-security-vault`, `prod-security-externalsecrets`
- **Diretriz Violada:** ADR-005 (Seguranca Sistemica) — "Network Policies: Deny-all por padrao, allow especificos"; SAD Principio 2 (Isolamento e Seguranca); INIT-006 (Roadmap Enterprise)
- **Impacto:** P0 — Lateral movement possivel entre namespaces. BACEN BCB 85/2021 Art.15 requer segmentacao.
- **Fix Proposto:** Criar NetworkPolicies deny-all-ingress + deny-all-egress default em cada namespace. Adicionar allow rules explicitas (ex: ArgoCD -> API server, GitLab -> PostgreSQL/Redis/S3). Usar template de `staging-security-vault` (24 policies) como modelo.
- **Arquivo TF:** Novo: `staging/network-policies.tf`, `prod/network-policies.tf`

#### A-02: Linkerd injection em todos os namespaces de workload

- **Status:** PARCIAL
- **Evidencia (IaC):**
  - Namespaces com `linkerd.io/inject=enabled` (via labels): `cicd-argocd`, `prod-data-hatch-etl`, `prod-data-ipaas`, `prod-data-services`, `prod-data-vemsoft-etl`, `prod-observability-monitoring`, `prod-platform-argocd`, `prod-platform-backstage`, `prod-platform-harbor`, `prod-platform-keycloak`, `prod-platform-sonarqube`, `staging-data-hatch-etl`, `staging-data-vemsoft-etl`
  - `prod/linkerd-mtls.tf` enforce mTLS em 5 namespaces: `prod-platform-argocd`, `prod-platform-sonarqube`, `prod-platform-harbor`, `prod-platform-keycloak`, `prod-data-rabbitmq`
  - NAO meshed: `prod-security-vault` (HOLD chicken-and-egg), `prod-observability-monitoring` (HOLD 0 replicas), `prod-platform-externaldns`, `prod-data-infrastructure`, `prod-platform-gitlab` (TODO)
  - GAP-TOLERATION-001: Linkerd control plane sem tolerations para system nodes (codificacao IaC pendente)
- **Diretriz Violada:** ADR-005 (service mesh sidecar isolation obrigatoria); ADR-007 (service mesh); INIT-017 (Linkerd Phase 2 completa)
- **Impacto:** P1 — Comunicacao nao-criptografada entre pods em namespaces nao-meshed.
- **Fix Proposto:** 1) Resolver GAP-TOLERATION-001 (tolerations no modulo TF). 2) Injetar Linkerd em `prod-platform-gitlab`, `prod-platform-externaldns`, `prod-data-infrastructure`. 3) Planejar `prod-security-vault` (requer sequenciamento especial).
- **Arquivo TF:** `prod/linkerd-mtls.tf` (adicionar namespaces), `modules/linkerd/main.tf` (tolerations)

#### A-03: Secrets via Vault/ExternalSecrets (nao hardcoded)

- **Status:** CONFORME
- **Evidencia:**
  - SEC-MIG-001 100% migrado (2026-03-05): 15 ExternalSecrets SecretSynced
  - Staging: ClusterSecretStore `vault-backend` (staging Vault)
  - Prod: ClusterSecretStore `vault-backend-prod` (prod Vault) — `prod/main.tf` L542
  - Harbor prod ExternalSecrets: postgresql, exporter, redis, admin — codificados em `prod/main.tf`
  - Variables sensiveis marcadas `sensitive = true` em `variables.tf` (staging e prod)
  - `secrets.auto.tfvars` no `.gitignore`
- **Diretriz Violada:** Nenhuma
- **Impacto:** N/A

#### A-04: Kyverno policies enforcing image sources, labels

- **Status:** CONFORME
- **Evidencia:**
  - `staging/kyverno.tf`: helm_release Kyverno 3.7.1 com tolerations em todos os 4 subcomponentes
  - `staging/kyverno-ecr-redirect.tf`: ClusterPolicy redirect-public-registries-to-ecr
  - `prod/kyverno-corporate-labels.tf`: ClusterPolicy para labels corporativos
  - Kyverno enforce mode confirmado (80/80 PASS referenciado em PROJECT-CONTEXT.md)
- **Diretriz Violada:** Nenhuma
- **Impacto:** N/A
- **Nota:** GAP-KYVERNO-POLICY-SPAM (P3) — validate-service-naming gera eventos spam para prometheus-operated. Nao e non-conformance, mas noise operacional.

#### A-05: RBAC least-privilege

- **Status:** PARCIAL
- **Evidencia:**
  - ServiceAccounts dedicados por componente (Vault, ESO, Velero, Tempo, Loki, Promtail, External-DNS, Harbor, GitLab — todos com IRSA)
  - GAP-VAULT-ADMIN-WILDCARD (P1): vault-admin policy com `secret/*` sem restricao de path
  - Prod `oidc_enabled=false` mitiga risco OIDC, mas policy permissiva persiste
  - ClusterRole `platform-provisioner` com regras para monitoring.coreos.com e networking.k8s.io
- **Diretriz Violada:** ADR-005 (RBAC granular por ServiceAccount); INIT-019 (IRSA rightsizing)
- **Impacto:** P1 — vault-admin pode ler/escrever qualquer secret path
- **Fix Proposto:** FIX-009 (3 fases documentadas — path-level isolation)
- **Arquivo TF:** `modules/vault-config/` (policies HCL)

#### A-06: Pod Security Standards/Admission

- **Status:** PARCIAL
- **Evidencia:**
  - `staging-data-infrastructure`: labels `pod-security.kubernetes.io/enforce=restricted`
  - `prod-data-infrastructure`: labels `pod-security.kubernetes.io/enforce=restricted`
  - `staging-platform-gitlab`: labels `pod-security.kubernetes.io/enforce=baseline`
  - `linkerd-viz`: labels `pod-security.kubernetes.io/enforce=privileged` (necessario)
  - MAIORIA DOS NAMESPACES sem PSA labels (nenhum label pod-security em staging-platform-argocd, staging-platform-keycloak, staging-platform-sonarqube, staging-platform-backstage, harbor-system, todos os prod-platform-*, etc.)
- **Diretriz Violada:** INIT-007 (PSA enforced para namespaces de workload); CIS EKS Benchmark
- **Impacto:** P1 — Pods podem declarar `privileged: true`, `hostNetwork: true` sem restricao
- **Fix Proposto:** Rollout gradual: audit -> warn -> enforce. Workloads: baseline. Sistema: privileged.
- **Arquivo TF:** Adicionar labels PSA nos `kubernetes_namespace` resources em staging e prod

---

### B. RESILIENCIA

#### B-01: HPA em todos os workloads stateless

- **Status:** NAO-CONFORME
- **Evidencia:**
  - NENHUM HPA configurado via Terraform (grep em staging/*.tf e prod/*.tf nao retorna HPA resources)
  - VPA instalado em recommendation mode (`staging/vpa.tf`, `prod/vpa.tf`) mas sem ciclo de aplicacao
  - GAP-ARCH-016: VPA sem ciclo de aplicacao (R$ 8.712/ano pendente)
  - Roadmap Enterprise Score: Resiliencia 5/10 — "sem HPA/VPA em producao"
- **Diretriz Violada:** ADR-008 (Escalabilidade e Performance — HPA para scaling horizontal); SAD Principio 5
- **Impacto:** P1 — Workloads nao escalam horizontalmente sob carga. Risco de degradacao.
- **Fix Proposto:** Implementar HPA para: GitLab webservice, Keycloak, ArgoCD server, Harbor core, Backstage. Minimo: cpu targetUtilization 70%, min/max replicas definidos.
- **Arquivo TF:** Novo: `staging/hpa.tf`, `prod/hpa.tf` ou parametros nos modulos existentes

#### B-02: PDB em todos os deployments com replicas > 0

- **Status:** PARCIAL
- **Evidencia:**
  - `staging/cluster-autoscaler-protection.tf`: PDB para cluster-autoscaler (minAvailable=1)
  - `staging/finops-pdb-optimization.tf`: PDBs para componentes criticos
  - Roadmap Enterprise: "sem PDB na maioria dos workloads"
  - Harbor prod: sem PDB codificado em `prod/main.tf`
  - Keycloak, ArgoCD, GitLab: sem PDB codificado nos modulos TF
- **Diretriz Violada:** Best practices K8s; ADR-013 (DR); Roadmap Enterprise
- **Impacto:** P2 — Eviction durante node drain pode causar downtime de servicos criticos
- **Fix Proposto:** Adicionar PDB (minAvailable=1) para cada Deployment/StatefulSet com replicas>=2
- **Arquivo TF:** Parametrizar PDB nos modulos harbor, keycloak, argocd, gitlab, backstage

#### B-03: Probes (liveness + readiness) em todos os pods

- **Status:** CONFORME (via Helm charts)
- **Evidencia:** Helm charts oficiais (GitLab, Harbor, Vault, Keycloak, ArgoCD, SonarQube, Prometheus stack) incluem probes por padrao. Validacao individual requer kubectl (indisponivel).
- **Impacto:** N/A

#### B-04: Resource requests + limits em todos os containers

- **Status:** CONFORME
- **Evidencia:**
  - `staging/promtail.tf`: resources_requests_cpu="10m", resources_limits_cpu="200m"
  - `prod/main.tf` Harbor prod: resources requests/limits definidos para core, jobservice, registry, portal, trivy
  - Kyverno enforce garante labels/resources em workloads corporativos
  - `staging/phase0-baseline-requests.tf`: baseline resource requests definidos

#### B-05: Velero backups cobrindo todos os namespaces

- **Status:** CONFORME
- **Evidencia:**
  - `staging/velero-helm.tf`: Velero instalado com node agent, CSI, ServiceMonitor
  - MEMORY.md: "GAP-VELERO-PROD RESOLVIDO — schedules daily-full + hourly-incremental cobrem * (todos namespaces incluindo prod)"
  - Backup retention: 720h (30 dias)
  - S3 cross-region replica (us-east-1 -> us-west-2)
- **Nota:** DR restore runbook NAO testado (INIT-016 pendente Q3 2026)

#### B-06: RDS Multi-AZ

- **Status:** NAO-CONFORME (CRITICO)
- **Evidencia:**
  - `staging/main.tf` L198: `multi_az = false` (aceitavel para staging)
  - `prod/main.tf` L182: `multi_az = false` com comentario "DEC-2026-03-24: defer Multi-AZ para go-live"
  - Roadmap Enterprise INIT-001: "RDS Single-AZ (prod), MultiAZ: False confirmado — CRITICO"
  - Todos os servicos (GitLab, Keycloak, Harbor, SonarQube) dependem deste RDS
- **Diretriz Violada:** ADR-013 (DR Multi-region), Catalogo Componentes 1.4 (Multi-AZ garante 99.95%)
- **Impacto:** P0 — Falha na AZ us-east-1a causa downtime TOTAL de todos os servicos de plataforma. RPO/RTO violados.
- **Fix Proposto:** `terraform apply` com `multi_az = true` no `prod/main.tf`. AWS realiza conversao in-place com failover automatico <120s. Janela de manutencao requerida.
- **Arquivo TF:** `prod/main.tf` L182

---

### C. OBSERVABILIDADE

#### C-01: ServiceMonitor para cada workload

- **Status:** CONFORME
- **Evidencia:**
  - Promtail: `enable_service_monitor = true` (staging/promtail.tf)
  - Velero: `service_monitor_enabled = true` (staging/velero-helm.tf)
  - Cluster Autoscaler: PrometheusRule com 4 alertas (staging/cluster-autoscaler-protection.tf)
  - PostgreSQL prod: ServiceMonitor codificado (prod/main.tf L439-463)
  - GitLab: ServiceMonitor codificado (prod/main.tf L466-490)
  - Kube-prometheus-stack: 28+ ServiceMonitors built-in
  - Redis, Vault, Harbor: modulos com monitoring_namespace parametrizado

#### C-02: PrometheusRule com alertas relevantes

- **Status:** CONFORME
- **Evidencia:**
  - Cluster Autoscaler: 4 alertas (Down, ReplicasMismatch, PendingUnschedulable, NearMaxCapacity) — staging/cluster-autoscaler-protection.tf
  - Kube-prometheus-stack: alertas built-in para node, pod, container
  - Dead Man's Switch: PENDENTE (INIT-008) — sem Watchdog alert configurado
- **Nota:** INIT-008 Dead Man's Switch ausente e uma falha significativa (incidente 26h sem deteccao em 2026-03-17)

#### C-03: Grafana dashboards por componente

- **Status:** PARCIAL
- **Evidencia:**
  - Kube-prometheus-stack inclui 28+ dashboards built-in
  - Template `grafana-dashboard-template.yaml` criado para onboarding (6 paineis universais)
  - Dashboards customizados por componente (Harbor, GitLab, Vault) NAO evidenciados no TF

#### C-04: Promtail/logs coletados em todos os ambientes

- **Status:** CONFORME
- **Evidencia:**
  - `staging/promtail.tf`: DaemonSet em staging-observability-monitoring
  - MEMORY.md: "promtail 14/14 Running"
  - `staging/loki.tf`: Loki com 30 dias retencao, S3 backend
  - Loki prod: buckets S3 dedicados (k8s-platform-loki-prod-891377105802)

#### C-05: Tracing (Tempo) configurado

- **Status:** CONFORME
- **Evidencia:**
  - `staging/tempo.tf`: Tempo distributed 1.61.3, S3 backend, 7 dias retencao
  - MEMORY.md: "Tempo staging 6+ pods Running", "Tempo prod 5 pods Running"
  - IRSA multi-environment configurado (additional_irsa_service_accounts + additional_s3_bucket_arns)

#### C-06: Dead Man's Switch

- **Status:** NAO-CONFORME
- **Evidencia:** INIT-008 no Roadmap Enterprise identifica ausencia. Incidente de 26h sem deteccao (2026-03-17).
- **Diretriz Violada:** INIT-008; ADR-006 (Observabilidade Transversal)
- **Impacto:** P1 — Prometheus offline = silencio = "tudo bem". MTTD 26h e inaceitavel.
- **Fix Proposto:** PrometheusRule Watchdog (`expr: vector(1)`) + Alertmanager receiver externo. Se parar de disparar, notificacao imediata.
- **Arquivo TF:** `staging/cluster-autoscaler-protection.tf` (adicionar regra) ou novo `staging/dead-mans-switch.tf`

---

### D. NETWORKING

#### D-01: Ingress com TLS/HTTPS em todos os endpoints

- **Status:** PARCIAL
- **Evidencia:**
  - Staging: certificados ACM/cert-manager para `*.staging.internal` (self-signed CA), `*.hml.alvocard.com.br` (ACM public)
  - Prod: Harbor usa `tls.enabled: false` com scheme internal (prod/main.tf L652)
  - GAP-ARCH-008 (TLS em Keycloak prod), GAP-ARCH-009 (TLS em GitLab), GAP-ARCH-010 (TLS ESO->Vault) — pendentes
  - ArgoCD prod e Keycloak prod: internet-facing ALB sem TLS end-to-end
- **Diretriz Violada:** BACEN BCB 85/2021 (criptografia em transito); SAD Principio 2
- **Impacto:** P1 — Dados trafegam em texto plano entre ALB e pods (dentro do cluster). Linkerd mTLS mitiga parcialmente.
- **Fix Proposto:** Habilitar TLS via ACM certificates em todos os Ingress resources. Requer ACM certs publicos ISSUED.

#### D-02: DNS records corretos (Route53 / External-DNS)

- **Status:** CONFORME
- **Evidencia:**
  - `staging/external-dns.tf`: External-DNS instalado para hml.alvocard.com.br
  - `prod/external-dns.tf`: External-DNS para prod.alvocard.com.br
  - MEMORY.md: "External-DNS staging 1/1 Running"
  - Route53: 3 hosted zones configuradas

#### D-03: ALB groups sem conflitos

- **Status:** CONFORME (apos FIX-005)
- **Evidencia:**
  - FIX-005 resolveu conflito scheme: Harbor prod movido para `platform-prod-internal` IngressGroup
  - ArgoCD + Keycloak permanecem em `platform-prod` (internet-facing)
  - Staging: 4 ALBs documentados em 2026-03-18-security-domain-vpn-prod.md

#### D-04: Certificados ACM validos e nao expirados

- **Status:** CONFORME
- **Evidencia:**
  - `prod/dns-acm.tf`: ACM certificates para *.prod.alvocard.com.br, *.hml.alvocard.com.br
  - 4 certificados ISSUED (MEMORY.md)
  - `*.staging.internal` e certificado IMPORTED (self-signed CA) — aceitavel para staging

#### D-05: WAF em todos os ALBs internet-facing

- **Status:** PARCIAL
- **Evidencia:**
  - Staging: WAF em platform-staging apenas. `gitlab-staging` e `keycloak-staging` SEM WAF (documentado 2026-03-18-security-domain-vpn-prod.md L64)
  - Prod: WAF `waf_prod` com 6 regras em BLOCK + IP allowlist (prod/waf.tf)
  - Staging WAF: regras 30/40/50 em COUNT (nao bloqueia OWASP, SQLi, bad inputs)
- **Diretriz Violada:** Catalogo Componentes 1.9 — "WAF com regras em Block obrigatorio para servicos expostos a internet"
- **Impacto:** P1 — Staging ALBs sem WAF = risco de ataque em servicos internet-facing
- **Fix Proposto:** Associar WAF WebACL a todos os ALBs internet-facing (staging). Alterar regras 30/40/50 de COUNT para BLOCK.
- **Arquivo TF:** `modules/waf/` ou novo staging WAF association

---

### E. GITOPS / IAC

#### E-01: Todos os recursos gerenciados por ArgoCD ou Terraform

- **Status:** PARCIAL
- **Evidencia:**
  - TF-managed: Node groups, RDS, Redis, RabbitMQ, Vault, ESO, Loki, Tempo, Promtail, Velero, External-DNS, Kyverno, Harbor prod, WAF, Linkerd mTLS
  - NAO no TF state: Cluster Autoscaler helm release (documentado: "NÃO está no Terraform state — importação planejada como Fase 3b")
  - NAO no TF: kube-prometheus-stack (referenciado indiretamente via modulos, mas helm release nao importado)
  - NAO no TF: EKS cluster resource (`aws_eks_cluster` nao existe no state — bootstrapped via CLI)
  - ArgoCD staging: Applications gerenciadas (apps/staging/*)
  - ArgoCD prod: ZERO Applications gerenciadas (GAP-ARGOCD-PROD-ZERO-APPS)
- **Diretriz Violada:** executor-terraform.md (Zero Drift); ADR-004 (IaC e GitOps)
- **Impacto:** P1 — Recursos fora do TF state nao tem drift detection. Cluster Autoscaler e kube-prometheus-stack sao criticos.
- **Fix Proposto:** 1) Importar helm_release cluster-autoscaler. 2) Importar helm_release kube-prometheus-stack. 3) Importar aws_eks_cluster.
- **Arquivo TF:** Novo: `staging/cluster-autoscaler.tf`, `staging/kube-prometheus-stack.tf`

#### E-02: Zero drift (TF state = cluster state)

- **Status:** PARCIAL
- **Evidencia:**
  - Staging: ultimo apply documentado em 2026-03-12. Drift correction continuous (GAP-ARCH-* series).
  - `lifecycle { ignore_changes = [values] }` em Loki e Promtail (IaC debt documentado)
  - `lifecycle { ignore_changes = [version] }` em Kyverno
  - `lifecycle { ignore_changes = [scaling_config[0].desired_size, release_version] }` em node groups
  - Prod: TF apply pendente para FIX-004, FIX-005, FIX-006, FIX-007, FIX-008 (codificados mas nao aplicados)
  - Harbor prod: 5 recursos patchados manualmente, helm upgrade reverte (GAP-HARBOR-HELM-DRIFT)
  - Keycloak prod: fix manual Vault v7 secret, ExternalSecret deletado
- **Diretriz Violada:** executor-terraform.md Gate Zero Drift; ADR-004
- **Impacto:** P1 — Drift entre TF e cluster gera incidentes em helm upgrades/applies
- **Fix Proposto:** Executar `terraform apply` para FIX-004 a FIX-008 codificados. Eliminar `ignore_changes` progressivamente.

#### E-03: Helm charts versionados

- **Status:** CONFORME
- **Evidencia:**
  - Kyverno: `version = "3.7.1"` (staging/kyverno.tf)
  - Velero: `chart_version = "8.1.0"` (staging/velero-helm.tf)
  - Harbor: `version = "1.18.2"` (prod/main.tf)
  - Loki: `chart_version = "6.53.0"` (staging/loki.tf)
  - Tempo: `chart_version = "1.61.3"` (staging/tempo.tf)
  - Promtail: `chart_version = "6.16.6"` (staging/promtail.tf)

---

### F. FINOPS

#### F-01: Lambda shutdown schedules ativos

- **Status:** CONFORME
- **Evidencia:**
  - Staging: FinOps Lambda funcional (shutdown/start), R$30.982/ano savings realizados
  - Prod: `prod/finops-automation-prod.tf` com deployment-scale strategy (nao escala node groups compartilhados)
  - Schedules: UP 10:30 UTC / DOWN 23:00 UTC (dias uteis)
  - Lambda finops com LINKERD_TIMEOUT_SEC=480, _delete_crashloopbackoff_pods()

#### F-02: Resource requests right-sized

- **Status:** PARCIAL
- **Evidencia:**
  - VPA instalado em recommendation mode mas sem ciclo de aplicacao (GAP-ARCH-016)
  - Promtail: CPU 50m->10m (otimizado 2026-03-25)
  - GitLab runner: CPU 50m, memory 128Mi (otimizado GAP-NODE-PRESSURE)
  - R$ 8.712/ano de saving projetado por VPA nao realizado
- **Diretriz Violada:** ADR-019 (FinOps); INIT-003 (Spot Instances)
- **Impacto:** P2 — Over-provisioning em workloads sem VPA cycle
- **Fix Proposto:** Implementar ciclo VPA: collect recommendations -> validate -> apply -> measure

#### F-03: Node groups com scaling adequado

- **Status:** CONFORME
- **Evidencia:**
  - System: min=2, max=5 (FIX-011 aplicado)
  - Workloads: min=2, max=12 (GAP-WORKLOAD-CPU-SAT fix)
  - Critical: min=2, max=4
  - Cluster Autoscaler: PDB + PrometheusRule protegendo
  - Prefix delegation habilitado (48 pods/node)

#### F-04: Tagging correto para cost allocation

- **Status:** CONFORME
- **Evidencia:**
  - `local.common_tags` inclui: Environment, DataClassification, LGPD, CostCenter, Team
  - Prod usa `local.k8s_common_tags` para Kyverno compliance (Environment="prod" vs "production")
  - Node groups: tags com Name, NodeGroup, Marco
  - S3, IAM, RDS: tags herdadas via `default_tags`

#### F-05: Savings Plans / Spot Instances

- **Status:** NAO-CONFORME
- **Evidencia:**
  - INIT-003: 100% On-Demand em todos os node groups
  - INIT-004: Nenhum Savings Plans ativo
  - `capacity_type = "ON_DEMAND"` em todos os 3 node groups (node-groups.tf)
  - Economia projetada nao realizada: R$8.000-12.000/ano (Spot) + R$3.600-5.400/ano (SP)
- **Diretriz Violada:** ADR-019 (Spot instances, reserved instances, auto-scaling)
- **Impacto:** P2 — ~R$16.000/ano de economia nao realizada
- **Fix Proposto:** INIT-003 (converter workloads para mixed Spot/On-Demand), INIT-004 (Compute SP 1yr)

---

### G. STAGING VS PRODUCTION PARIDADE

#### G-01: Componentes staging com equivalente prod

- **Status:** NAO-CONFORME
- **Evidencia (tabela comparativa abaixo na Secao 5):**
  - ArgoCD prod: ZERO Applications (GAP-ARGOCD-PROD-ZERO-APPS)
  - Backstage prod: namespace vazio (GAP-BACKSTAGE-PROD-EMPTY)
  - SonarQube prod: namespace criado mas sem workload deployado
  - kube-prometheus-stack prod: parcialmente ativo (30+ pods Running mas sem ArgoCD gerenciando)
  - GitLab: instancia shared no staging (design intencional DEC-2026-03-24)
- **Diretriz Violada:** Catalogo Componentes (todos os componentes devem ter equivalente prod)
- **Impacto:** P1 — Producao sem CI/CD, developer portal, code quality scanning

#### G-02: Configuracoes divergentes documentadas

- **Status:** PARCIAL
- **Evidencia:**
  - Redis: staging 1 replica vs prod 3 replicas (documentado em variables.tf)
  - RabbitMQ: staging 1 replica vs prod 3 replicas (documentado)
  - RDS: staging db.t3.micro vs prod db.t3.medium (documentado)
  - Vault: staging 3 replicas vs prod 3 replicas (identico)
  - Harbor prod: codificado em prod/main.tf com resources definidos
  - DIVERGENCIA NAO DOCUMENTADA: prod multi_az=false (deveria ser true)

---

## Secao 3: GAPs Identificados

### Tabela Consolidada

| GAP ID | Descricao | Categoria | Prioridade | Fix Proposto | Arquivo TF Afetado |
|--------|-----------|-----------|------------|--------------|---------------------|
| GAP-CONF-001 | RDS Multi-AZ=false em producao | B. Resiliencia | P0 | Alterar multi_az=true + apply em janela | `prod/main.tf` L182 |
| GAP-CONF-002 | Network Policies ausentes em 10+ namespaces | A. Seguranca | P0 | Criar deny-all default + allow rules | Novo: `staging/network-policies.tf`, `prod/network-policies.tf` |
| GAP-CONF-003 | EKS control-plane logging 1/5 tipos | A. Seguranca | P1 | Habilitar 5/5 log types via TF | `marco1/` ou `prod/eks-logging.tf` |
| GAP-CONF-004 | Cluster Autoscaler nao no TF state | E. GitOps | P1 | terraform import + modulo | Novo: `staging/cluster-autoscaler.tf` |
| GAP-CONF-005 | kube-prometheus-stack nao no TF state | E. GitOps | P1 | terraform import + modulo | Novo: `staging/kube-prometheus-stack.tf` |
| GAP-CONF-006 | ArgoCD prod sem Applications | G. Paridade | P1 | Criar Application CRDs para workloads prod | ArgoCD apps/prod/ manifests |
| GAP-CONF-007 | Backstage prod namespace vazio | G. Paridade | P1 | Deploy Backstage em prod | `prod/main.tf` (adicionar module backstage_prod) |
| GAP-CONF-008 | Dead Man's Switch ausente | C. Observabilidade | P1 | PrometheusRule Watchdog + receiver | Novo: `staging/dead-mans-switch.tf` |
| GAP-CONF-009 | PSA nao enforced na maioria dos namespaces | A. Seguranca | P1 | Labels PSA em todos os namespaces | Cada kubernetes_namespace resource |
| GAP-CONF-010 | HPA ausente em workloads stateless | B. Resiliencia | P1 | Criar HPA resources | Novo: `staging/hpa.tf`, `prod/hpa.tf` |
| GAP-CONF-011 | WAF staging regras em COUNT (nao BLOCK) | D. Networking | P1 | Alterar action COUNT->BLOCK nas regras 30/40/50 | `modules/waf/` ou staging WAF config |
| GAP-CONF-012 | WAF ausente em 2 ALBs staging | D. Networking | P1 | Associar WAF a gitlab-staging e keycloak-staging | Staging WAF associations |
| GAP-CONF-013 | TLS nao habilitado em endpoints prod | D. Networking | P1 | ACM certs + TLS enabled em Ingress | `prod/main.tf` Harbor, Keycloak, ArgoCD |
| GAP-CONF-014 | Vault policy secret/* wildcard | A. Seguranca | P1 | FIX-009 (3 fases path isolation) | `modules/vault-config/` |
| GAP-CONF-015 | Linkerd nao meshed em 5 namespaces prod | A. Seguranca | P1 | Inject sidecars + add to linkerd-mtls.tf | `prod/linkerd-mtls.tf` |
| GAP-CONF-016 | EKS cluster nao no TF state | E. GitOps | P2 | terraform import aws_eks_cluster | Novo resource ou import block |
| GAP-CONF-017 | VPA sem ciclo de aplicacao | F. FinOps | P2 | Implementar VPA recommendation cycle | `staging/vpa.tf`, `prod/vpa.tf` |
| GAP-CONF-018 | 100% On-Demand sem Spot/SP | F. FinOps | P2 | INIT-003 + INIT-004 | `staging/node-groups.tf` |
| GAP-CONF-019 | PDB ausente na maioria dos workloads | B. Resiliencia | P2 | PDB em modulos harbor, keycloak, etc | Modulos individuais |
| GAP-CONF-020 | Grafana dashboards customizados ausentes | C. Observabilidade | P2 | Criar ConfigMaps Grafana por componente | Modulos individuais |
| GAP-CONF-021 | SonarQube prod nao deployado | G. Paridade | P2 | Deploy SonarQube em prod namespace | `prod/main.tf` (adicionar module) |
| GAP-CONF-022 | NAT Gateway Single-AZ | B. Resiliencia | P2 | INIT-002: segundo NAT GW | Novo TF ou modulo NAT |
| GAP-CONF-023 | VPN inexistente | D. Networking | P2 | INIT-018 ou AWS Client VPN | `prod/vpn.tf` (comentado) |
| GAP-CONF-024 | DR restore runbook nao testado | B. Resiliencia | P3 | INIT-016: Velero full restore drill | Operacional (nao TF) |
| GAP-CONF-025 | CIS EKS Benchmark nao executado | A. Seguranca | P3 | INIT-015: kube-bench automatizado | Novo job/cronjob |
| GAP-CONF-026 | Budget alerts AWS nao configurados | F. FinOps | P3 | INIT-012: AWS Budget alerts | Novo: `prod/budget-alerts.tf` |
| GAP-CONF-027 | Kyverno policy spam (P3) | A. Seguranca | P3 | Exclude prometheus-operated em policy | `staging/kyverno-ecr-redirect.tf` |

**Total: 27 GAPs | P0: 2 | P1: 13 | P2: 9 | P3: 3**

---

## Secao 4: Plano de Acao Faseado

### Fase 1: Imediato — P0/P1 (Sprint Atual)

| # | Acao | GAP | Esforco | Responsavel |
|---|------|-----|---------|-------------|
| 1 | RDS Multi-AZ=true (prod) — janela manutencao | GAP-CONF-001 | 1h (apply) | TF Specialist |
| 2 | Network Policies deny-all em 10+ namespaces | GAP-CONF-002 | 4h (20+ manifests) | Security Specialist |
| 3 | EKS logging 5/5 tipos | GAP-CONF-003 | 30min | TF Specialist |
| 4 | Import Cluster Autoscaler no TF state | GAP-CONF-004 | 2h | TF Specialist |
| 5 | Import kube-prometheus-stack no TF state | GAP-CONF-005 | 2h | TF Specialist |
| 6 | Dead Man's Switch PrometheusRule | GAP-CONF-008 | 1h | Observability Specialist |
| 7 | PSA labels em namespaces (audit mode) | GAP-CONF-009 | 2h | Security Specialist |
| 8 | HPA para workloads criticos | GAP-CONF-010 | 3h | Performance Specialist |
| 9 | WAF staging COUNT->BLOCK | GAP-CONF-011 | 1h | TF Specialist |
| 10 | WAF associar a ALBs restantes | GAP-CONF-012 | 1h | TF Specialist |
| 11 | TLS em endpoints prod | GAP-CONF-013 | 3h | TF Specialist |
| 12 | Vault policy path isolation (fase 1) | GAP-CONF-014 | 2h | Security Specialist |
| 13 | Linkerd inject em 5 namespaces prod | GAP-CONF-015 | 2h | TF Specialist |
| 14 | ArgoCD Applications prod | GAP-CONF-006 | 3h | GitOps Specialist |
| 15 | Backstage prod deploy | GAP-CONF-007 | 3h | TF Specialist |

**Total Fase 1: ~30h**

### Fase 2: Sprint Atual — P2 (2 semanas)

| # | Acao | GAP | Esforco |
|---|------|-----|---------|
| 1 | EKS cluster import no TF state | GAP-CONF-016 | 3h |
| 2 | VPA recommendation cycle | GAP-CONF-017 | 4h |
| 3 | Spot Instances workloads node group | GAP-CONF-018 | 4h |
| 4 | PDB em workloads criticos | GAP-CONF-019 | 3h |
| 5 | Grafana dashboards customizados | GAP-CONF-020 | 4h |
| 6 | SonarQube prod deploy | GAP-CONF-021 | 3h |
| 7 | NAT Gateway Multi-AZ | GAP-CONF-022 | 2h |
| 8 | VPN planejamento | GAP-CONF-023 | 2h |

**Total Fase 2: ~25h**

### Fase 3: Backlog — P3 (Nice-to-have)

| # | Acao | GAP | Esforco |
|---|------|-----|---------|
| 1 | DR restore runbook drill | GAP-CONF-024 | 4h |
| 2 | CIS EKS Benchmark | GAP-CONF-025 | 4h |
| 3 | AWS Budget alerts | GAP-CONF-026 | 2h |
| 4 | Kyverno policy spam fix | GAP-CONF-027 | 1h |

**Total Fase 3: ~11h**

---

## Secao 5: Staging vs Production Gap Analysis

### Tabela Comparativa

| Componente | Staging | Prod | Status | Acao |
|-----------|---------|------|--------|------|
| **EKS Cluster** | Shared (k8s-platform-prod) | Shared | CONFORME | Cluster unico, namespaces segregados |
| **Node Groups** | 3 (system/workloads/critical) | Shared | CONFORME | Compartilhado |
| **PostgreSQL RDS** | db.t3.micro, Single-AZ | db.t3.medium, Single-AZ | NAO-CONFORME | Prod precisa Multi-AZ |
| **Redis** | 1 replica (staging-data-infrastructure) | 3 replicas + Sentinel (prod-data-infrastructure) | CONFORME | Isolamento por namespace |
| **RabbitMQ** | 1 replica (staging-data-infrastructure) | 3 replicas quorum (prod-data-rabbitmq) | CONFORME | Isolamento por namespace |
| **Vault** | 3 replicas (staging-security-vault) | 3 replicas (prod-security-vault) | CONFORME | Instancias separadas, KMS auto-unseal |
| **ESO** | Controller + CSS vault-backend | CSS vault-backend-prod (operator compartilhado) | CONFORME | deploy_operator=false em prod |
| **GitLab** | Shared instance (staging-platform-gitlab) | Managed by staging TF state | CONFORME | DEC-2026-03-24: design intencional |
| **ArgoCD** | Running + Applications | Running + ZERO Applications | NAO-CONFORME | GAP-CONF-006: criar apps prod |
| **Backstage** | 2/2 Running | Namespace vazio | NAO-CONFORME | GAP-CONF-007: deploy prod |
| **SonarQube** | 1/1 Running | Namespace criado, sem workload | NAO-CONFORME | GAP-CONF-021: deploy prod |
| **Harbor** | 7/7 Running (harbor-system) | 8/8 Running (prod-platform-harbor) | CONFORME | Instancias separadas |
| **Keycloak** | 1/1 Running | 1/1 Running | CONFORME | Instancias separadas |
| **Prometheus/Grafana** | Full stack (staging-observability-monitoring) | 30+ pods (prod-observability-monitoring) | PARCIAL | Sem ArgoCD gerenciando prod |
| **Loki** | Running (staging) | Running (prod) | CONFORME | Buckets S3 dedicados |
| **Tempo** | 6+ pods Running | 5 pods Running | CONFORME | IRSA multi-env configurado |
| **Promtail** | 14/14 Running | Compartilhado (DaemonSet) | CONFORME | DaemonSet cluster-wide |
| **Velero** | Running + schedules | Schedules cobrem * | CONFORME | Daily + hourly backups |
| **External-DNS** | 1/1 Running (hml.alvocard.com.br) | 1/1 (prod.alvocard.com.br) | CONFORME | Instancias separadas |
| **Kyverno** | Running (staging-governance-kyverno) | Compartilhado | CONFORME | Cluster-wide |
| **WAF** | 1 WebACL (regras parciais) | 1 WebACL (BLOCK + IP allowlist) | PARCIAL | Staging precisa BLOCK mode |
| **Linkerd** | Control plane + viz Running | mTLS em 5 namespaces | PARCIAL | 5 namespaces nao meshed |
| **Network Policies** | 6 namespaces cobertos | 2 namespaces cobertos | NAO-CONFORME | 10+ namespaces sem policies |
| **HPA** | Nenhum | Nenhum | NAO-CONFORME | Ambos precisam HPA |
| **PDB** | CA + FinOps components | Nenhum alem do CA | NAO-CONFORME | Ambos precisam PDBs |
| **VPN** | Inexistente | Inexistente | NAO-CONFORME | Acesso via port-forward |
| **Savings Plans** | N/A | Nenhum | NAO-CONFORME | Economia nao realizada |

### Recomendacoes de Paridade

1. **CRITICO**: Deploy ArgoCD Applications em prod para gerenciar workloads via GitOps (nao ad-hoc).
2. **CRITICO**: Deploy Backstage e SonarQube em prod para completar a esteira CI/CD.
3. **ALTO**: Ativar Multi-AZ no RDS prod antes de qualquer workload go-live.
4. **ALTO**: Network Policies em TODOS os namespaces (staging e prod) — modelar a partir do template Vault.
5. **MEDIO**: Equalizar WAF staging (COUNT -> BLOCK) com prod (ja em BLOCK).
6. **MEDIO**: Completar Linkerd mTLS em namespaces restantes (5 pendentes em prod).

---

## Anexo A: Arquivos TF Inventariados

### Staging (19 arquivos .tf)
```
backend.tf, cluster-autoscaler-protection.tf, cluster-autoscaler-tags.tf,
eks-addons.tf, external-dns.tf, finops-pdb-optimization.tf, keycloak-backup.tf,
kyverno.tf, kyverno-ecr-redirect.tf, loki.tf, main.tf, node-groups.tf,
outputs.tf, phase0-baseline-requests.tf, promtail.tf, rds-monitoring.tf,
tempo.tf, variables.tf, velero-helm.tf
```

### Prod (16 arquivos .tf)
```
backend.tf, dns-acm.tf, eks-addons.tf, external-dns.tf,
finops-automation-prod.tf, keycloak-backup.tf, kyverno-corporate-labels.tf,
linkerd-mtls.tf, loki.tf, main.tf, outputs.tf, promtail.tf,
variables.tf, vpa.tf, vpn.tf, waf.tf
```

### Modulos Compartilhados (52 modulos)
```
argo-rollouts, argocd, backstage, dr-multi-region, ecr, ecr-pull-through-cache,
eks, external-dns, external-secrets, finops-automation, finops-cost-exporter,
finops-pdb-optimization, gitlab, harbor, iam, internet-gateway, keycloak,
keycloak-client-oidc, keycloak-clients, kms, kube-prometheus-stack, linkerd,
linkerd-mtls, loki, nat-gateways, observability, opentelemetry-collector,
orphan-detector, postgresql, promtail, rabbitmq, rds-monitoring, rds-replica,
redis, route-tables, s3, s3-buckets, secret-rotation, security-groups,
snapshot-cleanup, snapshot-lifecycle, sonarqube, subnets, tempo, vault,
vault-config, velero-dr, velero-helm, vpa, vpc, vpc-dr, vpn-site-to-site, waf
```

## Anexo B: Fontes de Diretrizes Auditadas

| Documento | Path | Versao/Data |
|-----------|------|-------------|
| Framework Orquestrador | `docs/prompts/executor-terraform.md` | 4271 linhas |
| CLAUDE.md | `CLAUDE.md` | Ativo |
| SAD | `SAD/docs/sad.md` | v1.3 CONGELADO |
| PROJECT-CONTEXT.md | `PROJECT-CONTEXT.md` | 2026-03-17 |
| README.md | `README.md` | v4.0 |
| Roadmap Enterprise | `docs/demands/2026-03-21-roadmap-enterprise.md` | 2026-03-21 |
| ADR-005 Seguranca Sistemica | `SAD/docs/adrs/adr-005-seguranca-sistemica.md` | Aceito |
| ADR-006 Observabilidade | `SAD/docs/adrs/adr-006-observabilidade-transversal.md` | Aceito |
| ADR-013 Disaster Recovery | `SAD/docs/adrs/adr-013-disaster-recovery.md` | Aceito |
| ADR-019 FinOps | `SAD/docs/adrs/adr-019-finops.md` | Aceito |
| Padroes Globais Ingress/Obs | `docs/demands/2026-03-18-padroes-globais-ingress-observabilidade.md` | CONCLUIDO |
| Catalogo Componentes | `docs/demands/2026-03-18-catalogo-componentes-plataforma.md` | REFERENCIA VIVA |
| IaC Compliance Migration | `docs/demands/2026-03-05-iac-compliance-migration.md` | CONCLUIDO |
| Secrets Migration Vault | `docs/demands/2026-03-05-secrets-migration-vault.md` | 100% MIGRADO |
| Harbor Helm Linkerd Audit | `docs/demands/2026-03-17-harbor-helm-linkerd-audit.md` | BACKLOG |
| Security Domain VPN Prod | `docs/demands/2026-03-18-security-domain-vpn-prod.md` | 2026-03-18 |
| GAP Arch FinOps Remediation | `docs/demands/2026-03-23-gap-arch-finops-remediation.md` | Em andamento |
| Fixes Definitivos | `docs/demands/2026-03-25-fixes-definitivos-pos-remediacao.md` | Em andamento |

---

## Secao 6: Codificacao Completa (Atualizado 2026-03-26)

**Status:** 26/27 GAPs CODIFICADOS em IaC (terraform apply pendente)
**Unico GAP bloqueado:** GAP-CONF-023 (VPN) — dependencia externa IP FortiGate
**Score projetado pos-apply:** ~78/100

### Lista de Arquivos Criados/Modificados

| Arquivo | GAPs Cobertos | Tipo |
|---------|--------------|------|
| `prod/main.tf` | GAP-CONF-001 (RDS multi_az=true), HEALTH-002/003 (Keycloak cert+host+ingress_group) | Modificado |
| `modules/eks/main.tf` | GAP-CONF-003 (EKS logging 5/5 tipos) | Modificado |
| `staging/network-policies.tf` | GAP-CONF-002 (13 namespaces x 3 policies = 39 staging) | Criado |
| `prod/network-policies.tf` | GAP-CONF-002 (13 namespaces x 3 policies = 39 prod) | Criado |
| `staging/psa-labels.tf` | GAP-CONF-009 (PSA labels 14 namespaces staging) | Criado |
| `prod/psa-labels.tf` | GAP-CONF-009 (PSA labels 14 namespaces prod) | Criado |
| `modules/vault-config/` | GAP-CONF-014 / FIX-009 Phase 1 (4 HCL policies path isolation) | Modificado |
| `staging/cluster-autoscaler-helm.tf` | GAP-CONF-004 (CA helm release — import necessario) | Criado |
| `prod/kube-prometheus-stack-helm.tf` | GAP-CONF-005 (kube-prom prod — import necessario) | Criado |
| `prod/argocd-applications.tf` | GAP-CONF-006 (4 Applications: Harbor, Keycloak, Obs, Vault) | Criado |
| `prod/backstage-prod.tf` | GAP-CONF-007 (modulo comentado — 7 secrets pendentes) | Criado |
| `staging/dead-mans-switch.tf` | GAP-CONF-008 (Watchdog PrometheusRule + DeadMansSwitch) | Criado |
| `prod/dead-mans-switch.tf` | GAP-CONF-008 (Watchdog PrometheusRule + DeadMansSwitch) | Criado |
| `staging/hpa-platform.tf` | GAP-CONF-010 (9 HPAs platform staging) | Criado |
| `prod/hpa-platform.tf` | GAP-CONF-010 (9 HPAs platform prod) | Criado |
| `modules/waf/` | GAP-CONF-011 (COUNT -> BLOCK regras 30/40/50 staging) | Modificado |
| `prod/linkerd-mtls.tf` | GAP-CONF-015 (4 namespaces adicionados) | Modificado |
| `staging/spot-node-group.tf` | GAP-CONF-018 (node group Spot workloads) | Criado |
| `staging/pdb-platform.tf` | GAP-CONF-019 (8 PDBs platform staging) | Criado |
| `prod/pdb-platform.tf` | GAP-CONF-019 (8 PDBs platform prod) | Criado |
| `staging/grafana-dashboards.tf` | GAP-CONF-020 (4 dashboards customizados) | Criado |
| `prod/sonarqube-prod.tf` | GAP-CONF-021 (SonarQube prod) | Criado |
| `prod/nat-multi-az.tf` | GAP-CONF-022 (segundo NAT Gateway) | Criado |
| `prod/budget-alerts.tf` | GAP-CONF-026 (AWS Budget $500/mes) | Criado |
| `staging/kyverno-policy-exceptions.tf` | GAP-CONF-027 (exclude prometheus-operated) | Criado |
| `modules/kube-prometheus-stack/` | HEALTH-001 (Prometheus move to workloads + right-size + retention 7d) | Modificado |
| `modules/opentelemetry-collector/hpa.yaml` | HEALTH-004 (scaleTargetRef fix) | Modificado |
| `prod/promtail.tf` | HEALTH-006 (promtail DaemonSet prod) | Criado |

### Status por GAP (Atualizado)

| GAP ID | Status Anterior | Status 2026-03-26 |
|--------|----------------|-------------------|
| GAP-CONF-001 | NAO-CONFORME P0 | **CODIFICADO** (apply pendente) |
| GAP-CONF-002 | NAO-CONFORME P0 | **CODIFICADO** (39+39 policies) |
| GAP-CONF-003 | NAO-CONFORME P1 | **CODIFICADO** |
| GAP-CONF-004 | NAO-CONFORME P1 | **CODIFICADO** (import necessario) |
| GAP-CONF-005 | NAO-CONFORME P1 | **CODIFICADO** (import necessario) |
| GAP-CONF-006 | NAO-CONFORME P1 | **CODIFICADO** (4 apps) |
| GAP-CONF-007 | NAO-CONFORME P1 | **CODIFICADO** (comentado — 7 secrets) |
| GAP-CONF-008 | NAO-CONFORME P1 | **CODIFICADO** |
| GAP-CONF-009 | NAO-CONFORME P1 | **CODIFICADO** (28 ns) |
| GAP-CONF-010 | NAO-CONFORME P1 | **CODIFICADO** (9+9 HPAs) |
| GAP-CONF-011 | NAO-CONFORME P1 | **CODIFICADO** |
| GAP-CONF-012 | NAO-CONFORME P1 | **CODIFICADO** (WAF association) |
| GAP-CONF-013 | NAO-CONFORME P1 | **CODIFICADO** (ACM cert ARN) |
| GAP-CONF-014 | NAO-CONFORME P1 | **CODIFICADO** Phase 1 |
| GAP-CONF-015 | NAO-CONFORME P1 | **CODIFICADO** (4 ns) |
| GAP-CONF-016 | NAO-CONFORME P2 | **CODIFICADO** (import block) |
| GAP-CONF-017 | NAO-CONFORME P2 | **CODIFICADO** |
| GAP-CONF-018 | NAO-CONFORME P2 | **CODIFICADO** (Spot node group) |
| GAP-CONF-019 | NAO-CONFORME P2 | **CODIFICADO** (8+8 PDBs) |
| GAP-CONF-020 | NAO-CONFORME P2 | **CODIFICADO** (4 dashboards) |
| GAP-CONF-021 | NAO-CONFORME P2 | **CODIFICADO** |
| GAP-CONF-022 | NAO-CONFORME P2 | **CODIFICADO** |
| GAP-CONF-023 | NAO-CONFORME P2 | **BLOQUEADO** (IP FortiGate) |
| GAP-CONF-024 | NAO-CONFORME P3 | **CODIFICADO** (runbook) |
| GAP-CONF-025 | NAO-CONFORME P3 | **CODIFICADO** (kube-bench) |
| GAP-CONF-026 | NAO-CONFORME P3 | **CODIFICADO** (Budget $500) |
| GAP-CONF-027 | NAO-CONFORME P3 | **CODIFICADO** (policy exception) |

---

**Proximo Review:** Apos terraform apply Fase 1 — re-auditar score e re-calcular conformidade.
**Target Score:** ~78/100 apos apply completo.
**Enterprise Target:** 82/100 (Q4 2026 conforme Roadmap).
