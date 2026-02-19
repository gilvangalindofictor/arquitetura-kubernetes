# current_state.md

> **Responsabilidade**: AI (atualizado automaticamente após cada task)
> **Quando atualizar**: Após CADA task que modifica código/infra
> **Prioridade de leitura**: 4

---

## Status Geral

**Última Atualização**: 2026-02-19 (GAP-005 concluído — ESO credentials, runner envFrom, RBAC, namespace fix, templates)

**Estado do Projeto**: Desenvolvimento Ativo - SSO + CI/CD Integration Complete (ArgoCD + Vault + SonarQube + Grafana + Harbor + GitLab CI)

**Marco Atual**: Marco 4 - CI/CD Platform (98% completo)

**Progresso Geral**: 55% ████████████████░░░░░░░░░░░ (Marco 0-3 completo, Marco 4 98% / 0-6)

---

## Marcos

| Marco              | Status         | Progresso | Duração | Custo/Mês | Completado em |
| ------------------ | -------------- | --------- | ------- | --------- | ------------- |
| Marco 0            | ✅ Completo     | 100%      | 2 dias  | ~$0.01    | ✅             |
| Marco 1            | ✅ Completo     | 100%      | 1 dia   | $547      | ✅             |
| Marco 2            | ✅ Completo     | 100%      | 3 dias  | +$66      | ✅             |
| Marco 3 Fase 1a/1b | ✅ Completo     | 100%      | 5 dias  | +$58      | ✅             |
| Marco 3 Fase 1c    | ✅ Completo     | 100%      | < 1h    | $0        | ✅             |
| Marco 3 Fase 1d    | ✅ Completo     | 100%      | 3 dias  | +$0.50    | ✅             |
| Marco 3 Fase 1e    | ✅ Completo     | 100%      | 2h32min | +$28.90   | ✅ 2026-02-06  |
| Marco 4            | 🚧 Em andamento | 98%       | ~12h    | +$100     | —             |
| Marco 5            | ⏸️ Pendente     | 0%        | TBD     | TBD       | —             |
| Marco 6            | ⏸️ Pendente     | 0%        | TBD     | TBD       | —             |

**Legenda**: ✅ Completo | 🚧 Em andamento | ⏸️ Pendente | ⚠️ Bloqueado

**Total até Marco 3**: ~14 dias de trabalho efetivo | ~$700/mês staging
**Marco 4 Atual**: 5/8 GAPs completos (98% core features) | +$100/mês | ~$800/mês total

---

## Tasks Recentes

**ArgoCD SSO via Keycloak OIDC — 5 Fixes Cascata (2026-02-18)**:

- ✅ Fix 1: DNS service name `keycloak-http` -> `keycloak-keycloakx-http` (staging/main.tf + keycloak/outputs.tf)
- ✅ Fix 2: Redirect URL protocol `https://` -> `http://` (argocd/values.yaml.tpl:58)
- ✅ Fix 3: Split-horizon DNS — issuer URL `svc.cluster.local` -> `keycloak.staging.internal/auth` (staging/main.tf:501)
- ✅ Fix 4: Invalid scopes — removed `groups` from requestedScopes (argocd/values.yaml.tpl:66)
- ✅ Fix 5: Client secret syntax `${argocd-oidc-credentials:client-secret}` -> `$oidc.keycloak.clientSecret` (argocd/values.yaml.tpl:65)
- ✅ ArgoCD SSO login via Keycloak: **FUNCIONAL** (2/2 pods Running, 0 errors)
- Pattern documentado: ArgoCD secret resolution syntax + split-horizon DNS

**Vault SSO via Keycloak OIDC (2026-02-18)**:

- ✅ Keycloak client `vault` criado (realm: platform, uuid: f676f69f, confidential)
- ✅ Grupos Keycloak: `vault-admins` + `vault-readers` criados
- ✅ Mapper `groups` (oidc-group-membership-mapper) adicionado ao client vault
- ✅ Vault OIDC auth method ativo em `auth/oidc/` — discovery_url: `http://keycloak.staging.internal/auth/realms/platform`
- ✅ Roles: `admin` (vault-admins, TTL 8h) + `reader` (any user, TTL 4h)
- ✅ Policies: `vault-admin` (secret/*, sys/policies/*) + `vault-reader` (secret/data/* read-only)
- ✅ TF files: vault_policies/vault-admin.hcl, vault_policies/vault-reader.hcl, +4 OIDC vars, jwt_auth_backend + 2 roles + 2 policies
- ✅ TF commit: `5dcf56a` — `feat(vault): SSO via Keycloak OIDC auth method`

**STOP-AND-FIX Completo + Terraform Apply (2026-02-18)**:

- ✅ Tempo ingester: migrado para critical nodegroup (us-east-1b), S3 TLS fix
- ✅ kube-prometheus-stack nodeSelectors removidos (--values file approach)
- ✅ alertmanager-0: 2/2 Running, prometheus-0: 2/2 Running, operator: 1/1 Running
- ✅ SonarQube: password reset via ALTER USER (RDS mismatch fix)
- ✅ GitLab runner: CI_SERVER_URL fix (:8080), scaled to 0 (token inválido pendente)
- ✅ EBS Multi-Attach recovery: force-detach + kubectl delete volumeattachment
- ✅ Node ip-10-0-135-130 terminado (i-03ff24910ba442563) — ASG provisionando substituto
- ✅ R-047 + R-048 adicionados ao risks.md
- ✅ Logbook: 2026-02-18-cluster-recovery-afternoon.md criado
- **Cluster estado**: 7 nodes Ready, ZERO pods unhealthy

**SSO Smoke Tests + Infrastructure Recovery (2026-02-13)**:

- ✅ SSO Smoke Test Suite: 39 PASSED / 0 FAILED / 5 SKIPPED
  - Script criado: `scripts/sso-smoke-test.sh` (9 secoes, 44+ checks)
  - Correcao: `wget` → `curl` para GitLab container compatibility
- ✅ FIX 1: CoreDNS DNS Rewrite
  - `keycloak.staging.internal` → `keycloak-keycloakx-http.keycloak.svc.cluster.local`
- ✅ FIX 2: Redis AUTH (cadeia de 7 fixes)
  - SpotaHome → OT-Container-Kit operator migration
  - Image: `redis:alpine` → `quay.io/opstree/redis:v8.4.0`
  - RBAC, PSS restricted, UID 1000, redisSecret
  - TF module reescrito: `modules/redis/main.tf` + `outputs.tf`
- ✅ FIX 3: Vault/ExternalSecret Recovery
  - 3/3 EBS volumes lost → reinit com KMS auto-unseal
  - KV v2, K8s auth, eso-reader policy/role configurados
  - Keycloak secrets seeded from cached K8s secret
- ✅ ExternalSecrets: ClusterSecretStore Ready, ExternalSecret Synced

**Harbor Redeploy + Redis TF Fix (2026-02-13)**:

- ✅ Harbor redeployado: 7 pods Running, Ingress ativo no ALB platform-staging
  - Causa: recursos K8s ausentes do TF state (apenas AWS resources existiam)
  - Chart harbor v1.14.0 / image v2.10.0
  - 5 recursos K8s criados (namespace, SA, secret, configmap, helm_release)
- ✅ STOP-AND-FIX: Redis module `depends_on` corrigido
  - `network-policies.tf` + `prometheus-rules.tf`: `redis_failover` → `redis`
  - Bug da migracao SpotaHome → OT-Container-Kit

**Próximos Passos**:

- ✅ GitLab runner: id=115 online (authentication token GitLab 17.x, 2026-02-18)
- ✅ Persist Tempo fix: nodeSelector=critical + affinity NotIn us-east-1a (commit 0c5729b)
- ✅ Lambda weekend shutdown: comportamento já correto — EKS scale=0 termina instâncias via ASG; RDS STOP preserva dados (não requer TERMINATE)
- ✅ ASG node substituto: cluster normalizado (7 nodes Ready confirmado)
- [ ] Persist monitoring fixes: `nodeSelector: {}` no Terraform Helm values para prometheus/alertmanager/operator
- [ ] Savings Plans 1yr (P1): R$ 6.984/ano, ROI 2.340%

---

## Componentes

### Infraestrutura Base

| Componente     | Status        | Versão  | Config      | Notas                                       |
| -------------- | ------------- | ------- | ----------- | ------------------------------------------- |
| AWS VPC        | ✅ Operacional | —       | 10.0.0.0/16 | 2 subnets públicas, 2 privadas              |
| VPC Endpoints  | ✅ Operacional | —       | STS + EC2   | ADR-046, custo +$28.90/mês                  |
| EKS Cluster    | ✅ Operacional | 1.28    | 7 nodes     | 3 node groups (critical, system, workloads) |
| EBS CSI Driver | ✅ Operacional | v1.26.1 | —           | Para persistent volumes                     |
| VPC CNI        | ✅ Operacional | v1.16.0 | —           | Networking                                  |
| CoreDNS        | ✅ Operacional | v1.10.1 | —           | DNS interno                                 |
| kube-proxy     | ✅ Operacional | v1.28.2 | —           | Network rules                               |

---

### Platform Services (Marco 2)

| Componente                   | Status        | Versão | Réplicas | Namespace               | Notas                    |
| ---------------------------- | ------------- | ------ | -------- | ----------------------- | ------------------------ |
| Prometheus                   | ✅ Operacional | 2.48.0 | 1        | monitoring              | Metrics collection ok    |
| Grafana                      | ✅ Operacional | 10.2.0 | 1        | monitoring              | Dashboards principais ok |
| Loki                         | ✅ Operacional | 2.9.3  | 1        | monitoring              | Logs agregados           |
| Tempo                        | ✅ Operacional | 2.3.1  | 1        | monitoring              | Traces distribuídos      |
| Cluster Autoscaler           | ✅ Operacional | 1.28.x | 1        | kube-system             | Auto-scaling nodes       |
| Metrics Server               | ✅ Operacional | 0.6.4  | 1        | kube-system             | HPA support              |
| AWS Load Balancer Controller | ✅ Operacional | 2.7.0  | 2        | kube-system             | Ingress ALB              |
| External Secrets Operator    | ✅ Operacional | 0.9.11 | 1        | external-secrets-system | Vault integration        |

---

### Workloads (Marco 3)

| Aplicação        | Status        | Versão       | Réplicas                                  | Namespace      | Database                  | Notas                                                     |
| ---------------- | ------------- | ------------ | ----------------------------------------- | -------------- | ------------------------- | --------------------------------------------------------- |
| PostgreSQL RDS   | ✅ Operacional | 15.4         | —                                         | —              | db.t3.medium Single-AZ    | Temporariamente em subnet pública (ADR-046)               |
| Redis Standalone | ✅ Operacional | OT-Kit v0.23 | 1 (standalone)                            | data-services  | —                         | OT-Container-Kit operator, AUTH enabled, PSS restricted   |
| RabbitMQ         | ✅ Operacional | Operator     | 1                                         | data-services  | —                         | Official operator                                         |
| GitLab           | ✅ Operacional | 17.7.0       | Vários                                    | gitlab-staging | PostgreSQL RDS            | Webservice Running, Runner id=115 online (2026-02-18)     |
| Harbor           | ✅ Operacional | 2.10.0       | 2 core + 2 portal + 1 reg + 1 job + 1 exp | harbor-system  | PostgreSQL RDS, S3 (IRSA) | Redeployado 2026-02-13, ALB platform-staging              |
| Vault            | ✅ Operacional | 1.15.0       | 3 (HA)                                    | vault-system   | Raft (EBS)                | KMS auto-unseal, OIDC SSO ativo (2026-02-18), 3/3 Running |

---

### CI/CD Platform (Marco 4) - 🚧 75% Completo

| Aplicação | Status        | Versão           | Réplicas | Namespace      | Database       | Notas                                                                                                                                             |
| --------- | ------------- | ---------------- | -------- | -------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Keycloak  | ✅ Operacional | 26.5.1 (Quarkus) | 1        | keycloak       | PostgreSQL RDS | SSO centralizado, OIDC clients: argocd, sonarqube, gitlab, grafana, harbor, vault. initContainer wait-for-db + startupProbe + toleration critical |
| ArgoCD    | ✅ Operacional | 2.9.3            | 2/2      | argocd         | PostgreSQL RDS | GitOps platform, OIDC Keycloak SSO ✅ (5 fixes cascata), 8/8 pods running                                                                          |
| SonarQube | ✅ Operacional | 10.3.0-community | 1        | sonarqube      | PostgreSQL RDS | Code quality, OIDC Keycloak, PVC 20Gi                                                                                                             |
| GitLab    | ✅ Operacional | 17.7.0           | Vários   | gitlab-staging | PostgreSQL RDS | Core OK, runner id=115 online, CI/CD variables + templates ✅ GAP-005 completo (2026-02-19) |

**GAPs Marco 4**:

- ✅ GAP-001: Keycloak SSO (100% - deployed 2026-02-06)
- ✅ GAP-002: GitLab Fix (100% - core operacional, runner id=115 online)
- ✅ GAP-003: ArgoCD GitOps (100% - deployed 2026-02-06)
- ✅ GAP-004: SonarQube (100% - deployed 2026-02-06)
- ✅ GAP-005: GitLab CI/CD Integration (100% - ESO credentials, runner envFrom, RBAC, templates — 2026-02-19)
- ⏸️ GAP-006: ApplicationSets GitOps Patterns (0%)
- ⏸️ GAP-007: Network Policies Marco 4 (0%)
- ⏸️ GAP-008: Monitoring & Dashboards Marco 4 (0%)

**Known Issues Marco 4**:

- ✅ GitLab runner: id=115 online, envFrom gitlab-ci-credentials, executor namespace=gitlab-staging (2026-02-19)
- ⚠️ SonarQube Prometheus exporter: Disabled (Maven Central timeout)
- ✅ SSO completo: SonarQube SAML ✅, ArgoCD OIDC ✅, Vault OIDC ✅, Grafana OIDC ✅, Harbor OIDC ✅, GitLab OIDC ✅
- ✅ GAP-005 completo: ESO ExternalSecret gitlab-ci-credentials, runner envFrom, executor namespace fix, RBAC least-privilege, templates
- ⏸️ Keycloak grupo `grafana-admins`: não provisionado (TF + Keycloak)
- ⏸️ GAP-006/007: ApplicationSets + Network Policies (pendente)

---

## Observabilidade

**Stack de Monitoring**:
- ✅ Prometheus: metrics coleta operacional
- ✅ Grafana: dashboards principais disponíveis
- ✅ Loki: logs centralizados funcionando
- ✅ Tempo: traces distribuídos habilitados
- ⏸️ Alertmanager: configuração básica, alertas críticos pendentes

**Dashboards Disponíveis**:
- Cluster Overview (nodes, pods, resources)
- Application Metrics (GitLab, Harbor, Keycloak)
- PostgreSQL Metrics
- Cost Analysis (via logs de FinOps Lambda)

**Logs**:
- Centralizados no Loki
- Retenção: 7 dias (configuração atual)
- Query via Grafana Explore

**Metrics**:
- Scrape interval: 15s
- Retention: 15 dias (Prometheus)
- Exporters: node-exporter, kube-state-metrics

**Alertas Configurados**: Básicos (pod restarts, node not ready)

**Alertas Pendentes**:
- [ ] Disk space critical
- [ ] Memory pressure
- [ ] Certificate expiration
- [ ] Database connection pool exhaustion

---

## Secrets Management

**Estratégia**: Vault + External Secrets Operator

**Vault Status (2026-02-13)**: Reinicializado (EBS volumes perdidos). 1/3 replicas por capacity.

**Status Migração para Vault**:
| Aplicação | Status     | External Secret | Detalhes                                                                            |
| --------- | ---------- | --------------- | ----------------------------------------------------------------------------------- |
| Keycloak  | ✅ Migrado  | ✅ Configurado   | Admin password, DB credentials via Vault                                            |
| Harbor    | ✅ Migrado  | ✅ Configurado   | OIDC credentials via ESO (secret/harbor/oidc → harbor-oidc-credentials, 2026-02-18) |
| GitLab    | ⏸️ Pendente | ⏸️ Pendente      | Usando secrets manuais                                                              |

**Vault Configuration (2026-02-18)**:
- KV v2 engine at `secret/`
- Kubernetes auth method configured (ESO service account)
- Policy `eso-reader` with `read` on `secret/data/*`
- Role `eso-reader` bound to `external-secrets-system` namespace
- ClusterSecretStore: `vault-backend` (Ready: True)
- ExternalSecret: `keycloak-postgresql` (SecretSynced: True)
- OIDC auth method at `auth/oidc/` — Keycloak realm platform, client `vault` (2026-02-18)
- Roles: `admin` (vault-admins group, TTL 8h) + `reader` (any user, TTL 4h)
- Policies: `vault-admin` + `vault-reader` (TF: modules/vault-config/vault_policies/)

---

## FinOps

**Última Análise**: 2026-02-19 (dados reais AWS Cost Explorer)

**Custo Atual Staging — AWS Cost Explorer (Fev 2026 MTD: 18 dias)**:

| Categoria                     | Custo MTD (18d) | Projeção Mensal        | Percentual |
| ----------------------------- | --------------- | ---------------------- | ---------- |
| Amazon EKS (Control Plane)    | $157.52         | $245.04                | 30.0%      |
| Amazon EC2 Compute (Nodes)    | $151.63         | $235.87                | 28.9%      |
| EC2 Other (EBS, NAT GW, IPs)  | $74.91          | $116.56                | 14.3%      |
| Amazon Elastic Load Balancing | $48.76          | $75.85                 | 9.3%       |
| Amazon VPC (Endpoints + NAT)  | $46.72          | $72.68                 | 8.9%       |
| Amazon RDS PostgreSQL         | $18.05          | $28.08                 | 3.4%       |
| Amazon CloudWatch             | $16.52          | $25.70                 | 3.2%       |
| Outros (KMS, S3, SM, ECR)     | $10.53          | $16.38                 | 2.0%       |
| **Subtotal (excl. Tax)**      | **$524.33**     | **$815.64**            | **100%**   |
| Tax                           | $72.55          | $112.86                |            |
| **TOTAL**                     | **$596.88**     | **$745.62** (forecast) |            |

**AWS Forecast Fev 2026:** **$745.62/mês** (vs documentado $752.80 = -0.95%)
**Custo diário estabilizado (Semana 3):** **~$13/dia** (redução de 73% vs Semana 1)

**Automação FinOps (ADR-024)**:
- ✅ Lambda start/stop para RDS + ASGs
- ✅ EventBridge schedules:
  - Start: Segunda-Sexta 07:30 BRT (10:30 UTC)
  - Stop: Segunda-Sexta 20:00 BRT (23:00 UTC)
- ✅ Economia observada: custos diários caíram de ~$50/dia para ~$13/dia

**Otimizações Implementadas**:
- ✅ Auto-shutdown ambiente staging (ADR-024)
- ✅ Single-AZ RDS (staging only)
- ✅ Tolerations para node groups (evitar over-provisioning)
- ✅ Sprint 2 FinOps Wave: ALBs deletados, EBS gp2→gp3, IngressGroup
- ✅ Sprint 3: VPC Endpoint KMS + Vault recovery

**Próximas Otimizações**:
- [ ] Spot instances para workloads node group
- [ ] Karpenter para auto-scaling mais eficiente
- [ ] Revisão de tamanhos de volumes EBS
- [ ] CloudWatch Logs retention review ($25/mês projetado — investigar)

---

## Testes

**Última Execução**: Não aplicável (infra não tem tests

 automatizados ainda)

| Tipo                    | Total | Passed | Failed | Cobertura |
| ----------------------- | ----- | ------ | ------ | --------- |
| Unit                    | 0     | 0      | 0      | —         |
| Integration (Terratest) | 0     | 0      | 0      | —         |
| E2E                     | 0     | 0      | 0      | —         |
| Performance             | 0     | 0      | 0      | —         |

**Status**: ⚠️ Sem testes automatizados

**Ação**: Implementar Terratest para módulos Terraform (Marco 4+)

---

## Segurança

**Última Audit**: Não realizado formalmente ainda

**Security Posture**:
- ✅ Secrets via Vault + ESO (parcial, migração em andamento)
- ✅ Network Policies: básicas implementadas (Marco 2)
- ✅ RBAC: configurado por namespace
- ✅ Security Groups: least privilege (ADR-040)
- ⏸️ Service Mesh (Linkerd): planejado para Marco 5
- ⏸️ API Gateway (Kong): planejado para Marco 5
- ⏸️ Policy Engine (Kyverno): planejado para Marco 5
- ⏸️ Runtime Security (Falco): planejado para Marco 5

**Vulnerabilities Scan**: Não executado ainda

**Pendências Críticas**:
- [ ] PostgreSQL em subnet pública temporário - migrar após estabilização (ADR-046)
- [ ] Completar migração de secrets para Vault (Harbor, GitLab)
- [ ] Implementar security audit completo (checklist OWASP Top 10)
- [ ] Configurar TLS para todos os endpoints

---

## Bloqueadores Conhecidos

| #   | Bloqueador                                                                                                                                                                                                                                                                                                                                                                                                    | Status                     | Severidade    | Resolução                                                                                                                                          | Ref                                                                                                                                           |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | ~~**Security Groups Dependencies (T5)**~~ — 10 orphan SGs deletados (3 GitLab ALB + 7 EKS node/cluster). Cross-references resolvidas via remoção de rules primeiro.                                                                                                                                                                                                                                           | **RESOLVIDO** (2026-02-13) | ~~🟡 Médio~~   | Estratégia 3 fases: (1) delete SGs sem deps, (2) remover rules cross-ref, (3) delete SGs. 1 fix residual em cluster-sg ativo. Total: 1m49s.        | [ADR-059](../adr/adr-059-multi-marco-infrastructure-split.md), [Logbook Cleanup](../logbook/2026-02-13-security-groups-cleanup-completion.md) |
| 2   | **Keycloak replica e restarts** — 1 replica (aceito staging). 118 restarts resolvidos: (1) initContainer wait-for-db adicionado (race condition RDS/FinOps), (2) `--health-enabled=true` adicionado (health 404), (3) startupProbe configurada (60×5s=300s tolerancia), (4) toleration `workload=critical` adicionada (scheduling nos t3.xlarge). CPU nao e mais bloqueador (t3.xlarge com 2.5+ vCPU livres). | **RESOLVIDO** (2026-02-13) | ~~🟢 Baixo~~   | Patches aplicados no StatefulSet via kubectl. Para 2a replica em PROD: alterar `replicas: 2` (Terraform ja tem default=2).                         | [ADR-046](../adr/adr-046-keycloak-sso-strategy.md), [Logbook Keycloak](../logbook/2026-02-11-keycloak-26-deployment-final.md)                 |
| 3   | ~~**Prometheus Operator stuck em Pending (system nodes)**~~ — Prometheus, Grafana, Alertmanager Pending 5+ dias por saturação system nodes + tolerations ausentes.                                                                                                                                                                                                                                            | **RESOLVIDO** (2026-02-09) | ~~🔴 Crítico~~ | ADR-042: dual tolerations (`node-type=system` + `workload=critical`) aplicadas a todos 7 módulos. System nodes escalados 2→3. Recovery em 7min31s. | [ADR-042](../context/decisions.md#adr-042), [Cluster Remediation](../operations/2026-02-09-cluster-remediation.md)                            |

---

## Dívida Técnica

**Top 5 Items**:

1. **PostgreSQL em Subnet Pública (Temporário)** - Severidade: HIGH
   - **Impacto**: Exposição de banco (mitigado por SG restritivo)
   - **Esforço**: M (depende de VPC endpoints funcionais)
   - **Plano**: Migrar para subnet privada quando Vault estável (Marco 4)
   - **Relacionado**: ADR-046

2. **Secrets Hardcoded (Harbor, GitLab)** - Severidade: HIGH
   - **Impacto**: Secrets em Kubernetes Secrets não criptografados em rest
   - **Esforço**: S (migração via ESO)
   - **Plano**: Marco 4, após Vault 100% estável

3. **Sem Testes Automatizados (IaC)** - Severidade: MEDIUM
   - **Impacto**: Risco de regressão em mudanças Terraform
   - **Esforço**: M (setup Terratest + CI)
   - **Plano**: Marco 4

4. **RDS Single-AZ (Staging)** - Severidade: LOW (staging only)
   - **Impacto**: Sem HA em staging (aceitável)
   - **Esforço**: S (flag Multi-AZ)
   - **Plano**: Production será Multi-AZ desde o início

5. **Alertas Básicos (Observability)** - Severidade: MEDIUM
   - **Impacto**: Possível falha sem notificação rápida
   - **Esforço**: M (definir alertas + routing)
   - **Plano**: Marco 5 (observability completa)

---

## Próximos Passos

**Marco 4 - CI/CD Completa** (Planejado):
- [ ] GitLab Runners configurados
- [ ] SonarQube para análise de código
- [ ] ArgoCD para GitOps
- [ ] Backstage para catálogo de serviços
- [ ] Templates Backstage para novos projetos

**Dependências Críticas**:
- Vault 100% estável (unseal confiável)
- PostgreSQL migrado para subnet privada (ou aceitar temporário)

**Riscos Identificados**:
- ⚠️ Vault unsealing após restarts (mitigado com HA + VPC endpoints)
- ⚠️ Custo crescente com adição de serviços (monitorar via FinOps)
- ⚠️ Complexidade aumentando (documentar bem, manter ADRs atualizados)

---

## Mudanças Recentes

### [2026-02-06]
- ✅ VPC Endpoints STS + EC2 criados (ADR-046)
- ✅ Vault recovery após issue de unsealing
- ✅ PostgreSQL SG atualizado para permitir Lambda
- ✅ Keycloak + GitLab + Harbor reconectados
- 🐛 Identificado: Vault precisa de PostgreSQL acessível antes de seal

### [2026-02-05]
- ✅ Vault HA migration de 1→3 replicas (ADR-041)
- ✅ FinOps Lambda completamente funcional (ADR-024)
- ✅ Harbor robot accounts configurados
- ✅ Observability stack recovery pós-taint

### [2026-02-04]
- ✅ PostgreSQL RDS security group fix (ADR-040)
- ✅ Harbor deployment completo
- ✅ FinOps Lambda Python downgrade (3.13→3.12)

### [2026-02-03]
- ✅ GitLab migration (envs→environments) fix
- ✅ Terraform drift cleanup (GitLab, RabbitMQ)
- ✅ Redis Sentinel user:1000 filesystem fix

---

## Metrics de Qualidade

**Commits com Co-Authorship AI**: ~80% (estimado)

**ADRs Criados**: 46 (ADR-001 a ADR-046)

**Logbooks Escritos**: 48 arquivos

**Documentation Coverage**: Alta (PROJECT-CONTEXT.md, README.md, ADRs, logbooks extensos)

**Code Review**: Manual (não automatizado ainda)

---

## Notas

### Hierarquia de Ambientes

- **Atual**: staging only (`k8s-platform-prod` - naming histórico)
- **Futuro**: Multi-environment (ADR-026)
  - staging: `k8s-platform-staging`
  - production: `k8s-platform-production`

### Estratégia Cloud

- **MVP (Atual)**: AWS-First, 75-80% cloud-agnostic by design
- **Futuro**: 100% cloud-agnostic via operators (RDS → CloudNativePG, etc.)

### AI-First Development

- Sistema de aprendizagem ativo (scaffold kit bootstrap em 2026-02-06)
- Hooks Git obrigatórios
- Rastreabilidade total via logbooks

---

_Auto-atualizado pelo sistema de scaffold | Última task: Bootstrap Scaffold Kit em 2026-02-06_
