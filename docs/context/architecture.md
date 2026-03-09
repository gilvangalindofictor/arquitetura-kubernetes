# 🏗️ Arquitetura da Plataforma Kubernetes AWS

**Última Atualização:** 2026-02-27
**Versão:** 3.5 (Loki 3.6.5 Fix + Loki→Tempo Correlation)
**Status:** 🚀 FinOps ATIVA | ✅ SSO 39/39 Passed | ✅ Loki Operational | ✅ Loki→Tempo Correlation | ✅ RDS Monitoring | ✅ Sprint 3: 97% Complete

---

## ⚠️ IMPORTANTE: Escopo Quickstart vs Produção

**🎯 QUICKSTART (MVP - STAGING APENAS):**

- **Escopo:** Marcos 0, 1, 2, 3 focados em **ambiente STAGING**
- **Objetivo:** Plataforma funcional para desenvolvimento/testes
- **Componentes:** GitLab staging, Keycloak, ArgoCD, Harbor, PostgreSQL RDS, Redis, RabbitMQ
- **Timeline:** 6 semanas (completo)
- **Custo:** ~R$ 2.500/mês (staging otimizado)

**🏭 PRODUÇÃO (Expansão Posterior):**

- **Escopo:** Componentes adicionados APÓS quickstart
- **Namespace:** `data-services-prod`, network policies prod
- **Timeline:** Implementação gradual pós-Marco 3
- **Custo:** Adicional conforme demanda

**Este documento descreve AMBOS os escopos.** Para foco exclusivo no quickstart staging, consulte: [aws-eks-gitlab-quickstart.md](../plan/quickstart/aws-eks-gitlab-quickstart.md)

---

## 📊 Visão Geral

Plataforma Kubernetes completa na AWS, estruturada em marcos evolutivos, com foco em observabilidade, segurança e custos otimizados.

### Marcos de Evolução

```
Marco 0: Baseline (✅)  →  Marco 1: EKS (✅)  →  Marco 2: Platform (✅ 8/8)  →  🚀 FinOps ATIVA (STAGING)  →  📋 Marco 3: Workloads (PRÓXIMO)
```

**✅ MARCO 2 COMPLETO:** Todas as 8 fases implementadas. 🚀 **FinOps Automation ATIVA** em STAGING desde 2026-02-02 (economia **R$ 4.320/ano** gerando). **SSO Smoke Tests 39/39 PASSED** (2026-02-13). Redis migrado SpotaHome → OT-Container-Kit.

---

## 📋 Multi-Marco Infrastructure Split

**ADR:** [ADR-059: Multi-Marco Infrastructure Split Strategy](../adr/adr-059-multi-marco-infrastructure-split.md)
**Data:** 2026-02-12
**Status:** ✅ **Formalizado**

### Estratégia de Separação de Responsabilidades

A infraestrutura está dividida em **3 Marcos Terraform** com ownership explícito:

1. **Marco 0: VPC Foundation** (Legacy/Deprecated) - Rede base compartilhada
2. **Marco 1: EKS Cluster Foundation** - Cluster Kubernetes compartilhado (prod + staging)
3. **Marco 3 Staging: Workloads & Data Services** - Aplicações staging environment

**Padrão Chave:** **Shared Cluster Strategy**
- Cluster único para prod + staging
- Isolamento via namespaces + RBAC + NetworkPolicies
- Cost efficiency: -$139/mês = **R$ 1.002/ano** savings

### 📊 Resource Ownership Matrix

| Recurso                     | Marco 0    | Marco 1       | Marco 3 Staging | Justificativa                             |
| --------------------------- | ---------- | ------------- | --------------- | ----------------------------------------- |
| **🌐 Networking**            |            |               |                 |                                           |
| VPC                         | ✅ Gerencia | 📖 Data source | 📖 Data source   | Shared foundation                         |
| Subnets                     | ✅ Gerencia | 📖 Data source | 📖 Data source   | Shared foundation                         |
| NAT Gateways                | ✅ Gerencia | 📖 Data source | 📖 Data source   | Shared foundation, $66/mês                |
| Internet Gateway            | ✅ Gerencia | 📖 Data source | 📖 Data source   | Shared foundation                         |
| Route Tables                | ✅ Gerencia | 📖 Data source | 📖 Data source   | Shared foundation                         |
| VPC Endpoints (S3)          | ✅ Gerencia | 📖 Data source | 📖 Data source   | Cost optimization (NAT bypass)            |
| VPC Endpoints (STS)         | ❌          | ✅ Gerencia    | 📖 Data source   | IRSA authentication                       |
| VPC Endpoints (EC2)         | ❌          | ✅ Gerencia    | 📖 Data source   | Node registration                         |
| VPC Endpoints (ELB)         | ❌          | ✅ Gerencia    | 📖 Data source   | ALB Controller TLS fix                    |
| VPC Endpoints (KMS)         | ❌          | ✅ Gerencia    | 📖 Data source   | Vault auto-unseal                         |
| **💻 Compute**               |            |               |                 |                                           |
| EKS Cluster                 | ❌          | ✅ Gerencia    | 📖 Data source   | Shared cluster strategy                   |
| EKS Node Groups             | ❌          | ✅ Gerencia    | 📖 Data source   | Shared cluster strategy                   |
| EKS Addons                  | ❌          | ✅ Gerencia    | 📖 Data source   | Cluster-level config                      |
| **👤 IAM**                   |            |               |                 |                                           |
| OIDC Provider (IRSA)        | ❌          | ✅ Gerencia    | 📖 Data source   | Cluster-level config                      |
| IRSA Roles (workload)       | ❌          | ❌             | ✅ Gerencia      | Workload-specific (Vault, Harbor, GitLab) |
| **🔐 Encryption**            |            |               |                 |                                           |
| KMS (EKS secrets)           | ❌          | ✅ Gerencia    | 📖 Data source   | Cluster-level encryption                  |
| KMS (Vault unseal)          | ❌          | ❌             | ✅ Gerencia      | Workload-specific                         |
| **💾 Data Services**         |            |               |                 |                                           |
| PostgreSQL RDS              | ❌          | ❌             | ✅ Gerencia      | Environment-specific                      |
| Redis Operator              | ❌          | ❌             | ✅ Gerencia      | Environment-specific                      |
| RabbitMQ Operator           | ❌          | ❌             | ✅ Gerencia      | Environment-specific                      |
| **📦 Application Workloads** |            |               |                 |                                           |
| Vault HA                    | ❌          | ❌             | ✅ Gerencia      | Secrets management                        |
| External Secrets            | ❌          | ❌             | ✅ Gerencia      | Secrets sync                              |
| Harbor Registry             | ❌          | ❌             | ✅ Gerencia      | Container images                          |
| GitLab CE                   | ❌          | ❌             | ✅ Gerencia      | CI/CD platform                            |
| Keycloak SSO                | ❌          | ❌             | ✅ Gerencia      | Authentication                            |
| ArgoCD GitOps               | ❌          | ❌             | ✅ Gerencia      | Continuous deployment                     |
| SonarQube                   | ❌          | ❌             | ✅ Gerencia      | Code quality                              |
| Observability Stack         | ❌          | ❌             | ✅ Gerencia      | Monitoring/logging                        |

**Legenda:**
- ✅ Gerencia: Terraform gerencia o recurso (create/update/delete)
- 📖 Data source: Terraform consome via data source (read-only)
- ❌ Não gerenciado: Fora do escopo deste Marco

### 🔄 Implicações Operacionais

**✅ Benefícios:**
- Clareza de ownership (quem gerencia o quê)
- Cost efficiency validada (R$ 1.002/ano savings)
- Isolamento adequado via namespaces + RBAC
- Simplicidade operacional (1 cluster para manter)

**⚠️ Challenges:**
- Drift detection complexo (3 states separados)
- Upgrade coordination required (Marco 1 → Marco 3 validation)
- State file dependency (Marco 3 depende de Marco 1 remote state)
- Blast radius compartilhado (cluster-level issues afetam prod + staging)

**🛡️ Mitigações:**
- Validation script para 3 states: `./scripts/validate-all-marcos.sh`
- Runbook de upgrade EKS documentado: [MULTI-MARCO-GUIDE.md](../operations/MULTI-MARCO-GUIDE.md)
- S3 bucket versioning + DynamoDB locking habilitados
- Node groups separados + tolerations + taints

---

## 🎯 Marco 0: Baseline Terraform

**Status:** ✅ Completo

### Componentes
- **VPC Existente:** `vpc-0b1396a59c417c1f0` (10.0.0.0/16, 2 AZs: us-east-1a, us-east-1b)
- **Backend S3:** `terraform-state-marco0-891377105802`
- **DynamoDB Lock:** `terraform-state-lock`
- **Engenharia Reversa:** Scripts para importar recursos AWS existentes

### Decisões Arquiteturais
- Reaproveitamento de VPC existente (economia $96/mês em NAT Gateways)
- Multi-AZ com 2 zonas (suficiente para DevOps tools, não critical workloads)
- State management centralizado em S3 com versioning

---

## ⚙️ Marco 1: Infraestrutura Base EKS

**Status:** ✅ Completo

### Cluster EKS
- **Nome:** k8s-platform-prod
- **Versão:** 1.31.x
- **Região:** us-east-1
- **OIDC Provider:** Habilitado para IRSA

### Node Groups (9 nodes total - scaled 2026-02-20)

| Node Group | Tipo      | Quantidade | vCPU | RAM  | Disco | Workload                   | Autoscaling |
| ---------- | --------- | ---------- | ---- | ---- | ----- | -------------------------- | ----------- |
| system     | t3.medium | 3          | 12   | 24GB | 150GB | Platform services críticos | ✅ Enabled  |
| workloads  | t3.large  | 3          | 18   | 72GB | 150GB | Aplicações usuário         | ✅ Enabled  |
| critical   | t3.xlarge | 3          | 36   | 144GB| 150GB | Vault HA, databases HA     | ✅ Enabled  |

**Scaling History:**

- **2026-02-06:** NodeGroup "critical" scaled 2→3 (CPU saturation >90%)
- **2026-02-20:** NodeGroup "system" scaled 2→3 (pod capacity 17/17 — Grafana Pending 18h)
  - Trigger: Grafana pod Pending 18h, node @ 100% pod capacity (t3.medium limit)
  - Root cause: Volume affinity conflict + node capacity + Cluster Autoscaler disabled
  - Fix: ASG tags `k8s.io/cluster-autoscaler/*` = "owned" (autoscaling habilitado)
  - Impact: +R$ 432/ano (1 node adicional), +R$ 768/ano ROI (evita intervenção manual)
- **New Node:** ip-10-0-148-70.ec2.internal (t3.xlarge, us-east-1b)
- **Cost Impact:** +$121.47/mês ($1,457.64/ano) - temporary
- **Rationale:** Vault StatefulSet não conseguia agendar vault-0 (FailedScheduling)
- **Future:** Optimize workloads + consider downscaling após resource tuning

**Taints e Labels:**
- `system`: `node-type=system:NoSchedule` + label `node-type=system`
- `workloads`: label `node-type=workloads` (sem taint, general purpose)
- `critical`: `node-type=critical:NoSchedule` + label `node-type=critical`

### Add-ons EKS (4 total)
1. **vpc-cni** - Networking plugin (ENI-based pod IPs)
2. **kube-proxy** - Network proxy
3. **coredns** - DNS resolution
4. **ebs-csi-driver** - Persistent volumes (IRSA configurado)

### IAM & IRSA
- **OIDC Provider:** `EC913B145BF356481CBE823532F09150`
- **Padrão IRSA:** Todos platform services usam IAM Roles (sem Access Keys)
- **Roles criados:** 4 (EBS CSI, ALB Controller, Loki S3, Cluster Autoscaler)

### VPC Endpoints (AWS PrivateLink)

**Status:** ✅ Implementado (2026-02-06) + ELB (2026-02-10) + KMS (2026-02-10)
**ADR:** ADR-044 VPC Endpoints for EKS, ADR-053 VPC Endpoint ELB, ADR-055 VPC Endpoint KMS
**Logbook:** [2026-02-06-vault-recovery-vpc-endpoints.md](../logbook/2026-02-06-vault-recovery-vpc-endpoints.md), [2026-02-10-lb-controller-fix.md](../logbook/2026-02-10-lb-controller-fix.md), [2026-02-10-vault-kms-recovery.md](../logbook/2026-02-10-vault-kms-recovery.md)

**Interface Endpoints criados:**

| Service | Endpoint ID            | AZs                    | Private DNS | Status    |
| ------- | ---------------------- | ---------------------- | ----------- | --------- |
| **STS** | vpce-0c3a498a73742aa21 | us-east-1a, us-east-1b | ✅ Enabled   | available |
| **EC2** | vpce-0b52639b29be0559e | us-east-1a, us-east-1b | ✅ Enabled   | available |
| **ELB** | vpce-01ac1aa08881b1977 | us-east-1a, us-east-1b | ✅ Enabled   | available |
| **KMS** | vpce-0ea3c1103ca34af51 | us-east-1a, us-east-1b | ✅ Enabled   | available |

**Configuração:**
- **Tipo:** Interface (ENI-based, 2 ENIs por endpoint)
- **Security Group:** sg-0ed52abadabebb8d3 (cluster SG, egress 0.0.0.0/0)
- **Subnets:** subnet-0288a67cd352effa7 (1b), subnet-0472ab28726cdf745 (1a)
- **Private DNS:** Habilitado (`sts.us-east-1.amazonaws.com`, `ec2.us-east-1.amazonaws.com`)

**Motivação:**
- **Root Cause:** CSI driver TLS timeout (NAT Gateway → public internet instável)
- **Performance:** AWS API latency 50-200ms (NAT) → <5ms (VPC endpoint) = **10-40x faster**
- **Reliability:** Elimina dependency em NAT Gateway availability para critical infra
- **Security:** Tráfego não sai da AWS private network (compliance requirement)

**Impacto:**
- ✅ EBS CSI Driver: 100% error rate → 0% (PVC provisioning funcional)
- ✅ IRSA calls: AssumeRoleWithWebIdentity latency reduzida
- ✅ Vault HA: Recovery de 15h downtime → operational em 2h32min
- ✅ AWS LB Controller: TLS timeout intermitente → 0% error rate (IngressGroup consolidation habilitado)
- ✅ Vault KMS auto-unseal: Quorum loss (1/3) → 3/3 healthy (<15s recovery após VPCE KMS)

**Custo:** $43.35/mês ($520.20/ano)
- Base: $0.01/hour/AZ × 2 AZ × 3 endpoints = $43.20/mês
- Data processing: ~$0.15/mês (15 GB API calls)
- **Trade-off:** +$43/mês líquido vs NAT data transfer savings
- **ROI FinOps:** Endpoint ELB habilitou consolidação IngressGroup (economia R$ 1.949/ano = $325/ano)

**Próximos Endpoints (roadmap):**
- ECR API/DKR (container image pull latency)
- S3 Gateway (free, zero cost improvement)

---

## 🛠️ Marco 2: Platform Services

**Status:** ✅ 8/8 Fases Completas | Módulo Terraform FinOps implementado e validado

### Fase 1: AWS Load Balancer Controller
- **Versão:** v1.11.0
- **Namespace:** kube-system
- **IRSA Role:** AWSLoadBalancerControllerRole-k8s-platform-prod
- **Função:** Provisiona ALBs para Kubernetes Ingresses
- **WAF/Shield:** Desabilitados (economia)
- **Custo:** $0 (usa nodes existentes)

### Fase 2: Cert-Manager
- **Versão:** v1.16.3
- **Namespace:** cert-manager
- **CRDs:** 6 instalados (Certificate, Issuer, ClusterIssuer, etc.)
- **Função:** Gerenciamento automático de certificados TLS
- **ClusterIssuers:** 3 criados (letsencrypt-staging, letsencrypt-prod, selfsigned)
- **Custo:** $0 (usa nodes existentes)

### Fase 3: Monitoring (Kube-Prometheus-Stack)
- **Versão:** v69.4.0 (Helm chart)
- **Namespace:** monitoring
- **Componentes:** Prometheus, Grafana, Alertmanager, Node Exporter, Kube State Metrics
- **Pods:** 13 Running
- **Dashboards:** 30+ pré-configurados
- **PVCs:** 3 volumes (27Gi total)
  - Prometheus: 20Gi (gp3)
  - Grafana: 5Gi (gp3)
  - Alertmanager: 2Gi (gp3)
- **Secrets:** Grafana OIDC → Vault `secret/grafana/oidc` → ESO → K8s Secret `grafana-oidc-credentials` (migrado DEC-065, 2026-02-19)
- **Custo:** $2.56/mês (EBS)

**Scheduling Strategy (Atualizado 2026-02-05):**
- **Tolerations:**
  - `node-type=system:NoSchedule` (system nodes)
  - `workload=critical:NoSchedule` (critical nodes) ← **ADICIONADO**
- **NodeSelector:** Removido (anteriormente restrito a `node-type=system`)
- **Rationale:** Permitir observability em critical nodes para proximidade com databases
- **Recovery:** 5+ dias Pending resolvidos em 7min31s via Helm upgrade
- **Nodes Atuais:** Schedulados em `ip-10-0-134-10` e `ip-10-0-151-94` (node-type=critical)
- **Reference:** [Logbook 2026-02-05](../logbook/2026-02-05-execution-observability-recovery.md)

### Fase 4: Logging (Loki + Fluent Bit)
- **Loki Versão:** Chart v5.42.0 (SimpleScalable mode)
- **Fluent Bit Versão:** Chart v0.43.0
- **Namespace:** monitoring
- **Pods:** 15 total (8 Loki + 7 Fluent Bit DaemonSet)
- **Backend:** S3 bucket `k8s-platform-loki-891377105802`
- **Retenção:** 30 dias (S3), 7 dias (in-memory cache)
- **IRSA:** Role LokiS3Role-k8s-platform-prod
- **Integração:** Grafana datasource pré-configurado
- **Custo:** $19.70/mês (S3 500GB ~$11.50 + EBS 40Gi ~$3.20 + requests ~$5)

### Fase 5: Network Policies
- **CNI:** Calico policy-only mode (overlay AWS VPC CNI)
- **Políticas:** 11 aplicadas
  - 3 default-deny (por namespace: kube-system, monitoring, cert-manager)
  - 3 allow-dns (todos pods → CoreDNS UDP/53)
  - 3 allow-api-server (todos pods → API Server TCP/443)
  - 1 allow-prometheus-scraping (Prometheus → targets variados)
  - 1 allow-fluent-bit-to-loki (Fluent Bit → Loki Gateway TCP/3100)
- **Zero Trust:** Default deny, explicit allow
- **Custo:** $0 (Calico policy-only não requer nodes adicionais)

### Fase 6: Cluster Autoscaler
- **Versão:** Chart v9.43.2
- **Namespace:** kube-system
- **IRSA Role:** ClusterAutoscalerRole-k8s-platform-prod
- **Configuração:** Scale-up/down habilitado (5 min unneeded)
- **ASG Tags:** `k8s.io/cluster-autoscaler/k8s-platform-prod` = "owned" (✅ enabled 2026-02-20)
- **Node Groups Managed:** system (2-4), workloads (2-6), critical (2-4)
- **ServiceMonitor:** Integrado Prometheus
- **Status:** ✅ Functional (zero AccessDenied errors pós-fix 2026-02-20)
- **Custo:** $0 (usa nodes existentes)
- **Fix 2026-02-20:** ASG tags `disabled` → `owned` habilitou autoscaling automático

### Fase 7: Test Applications
- **Namespace:** test-apps
- **Apps:** 2 (nginx-test, echo-server)
- **Pods:** 4 (2 réplicas cada)
- **Ingresses:** 2 (ALB internet-facing HTTP-only)
- **ALBs Ativos:** 2
  - nginx-test: k8s-testapps-nginxtes-bf6521357f
  - echo-server: k8s-testapps-echoserv-d5229efc2b
- **ServiceMonitors:** 2 (integração Prometheus)
- **Network Policy:** 1 (allow ALB Controller + monitoring)
- **TLS:** Desabilitado (aguardando domínio registrado)
- **Custo:** $32.40/mês (2 ALBs × $16.20)

### Fase 8: Distributed Tracing (OpenTelemetry + Tempo)
**Status:** ⚠️ **70% Completo** (OTel deployado, integração Tempo BLOQUEADA)
**Data:** 2026-02-09
**ADR-020:** ✅ Aprovado | **ADR-052:** ⚠️ GAP-7 Implementation

**Componentes:**
- **Grafana Tempo:** Backend de traces distribuídos ✅ OPERACIONAL
  - **Versão:** Chart v1.10.x (SimpleScalable mode)
  - **Namespace:** monitoring
  - **Pods:** 11 Running (distributor, ingester, querier, compactor, query-frontend)
  - **Storage:** S3 bucket `k8s-platform-tempo-891377105802`
  - **Retenção:** 30 dias (S3)
  - **IRSA:** Role TempoS3Role-k8s-platform-prod
  - **⚠️ Limitação:** OTLP receiver não exposto externamente (localhost:4317 only)

- **OpenTelemetry Collector:** Gateway de ingestão ✅ DEPLOYADO (GAP-7)
  - **Versão:** otel/opentelemetry-collector-contrib:0.145.0
  - **Namespace:** monitoring
  - **Pods:** 2/2 Running (Gateway mode, HA)
  - **Resources:** requests 100m CPU/256Mi RAM, limits 500m/1Gi
  - **Receivers:** OTLP gRPC (4317), OTLP HTTP (4318)
  - **Exporters:**
    - ⚠️ **Tempo:** otlphttp/tempo → BLOQUEADO (HTTP 404 /v1/traces)
    - ✅ **Prometheus:** prometheusremotewrite → OPERACIONAL
    - ✅ **Debug:** verbosity normal → OPERACIONAL
  - **ServiceMonitor:** Integrado Prometheus (porta 8888)
  - **PodDisruptionBudget:** minAvailable=1
  - **Anti-affinity:** preferredDuringScheduling (kubernetes.io/hostname)
  - **Terraform Module:** [`modules/opentelemetry-collector/`](../../../platform-provisioning/aws/kubernetes/terraform/modules/opentelemetry-collector/)

**Trace Generator (Testing):** ✅ FUNCIONAL
  - **Namespace:** otel-test
  - **Pods:** 1/1 Running
  - **Image:** curlimages/curl
  - **Método:** OTLP JSON via HTTP POST
  - **Status:** Gerando 3 traces a cada 20s, OTel recebendo HTTP 200

**Integração:**
- ✅ Grafana datasource Tempo configurado
- ⚠️ Correlação traces ↔ logs (PENDENTE: aguarda integração Tempo funcional)
- ⚠️ Correlação metrics ↔ traces (PENDENTE: aguarda traces no Tempo)
- ✅ Grafana Explore: TraceQL queries configurado

**Bloqueio Identificado (2026-02-09):**
- **Problema:** Tempo ConfigMap sem receiver OTLP externo (porta 4317 localhost only)
- **Impacto:** OTel Collector recebe traces mas não consegue exportar para Tempo
- **Tentativas:** 3 protocolos testados (OTLP gRPC 9095, Jaeger 14250, OTLP HTTP 3200) - todas falharam
- **Soluções propostas:**
  1. **Opção 1 (Recomendado):** Helm upgrade Tempo + OTLP receiver (45min, médio impacto)
  2. **Opção 2 (Quick):** OTel Zipkin exporter → Tempo porta 9411 (15min, baixo impacto)
  3. **Opção 3 (Completo):** Re-deploy Tempo via Helm oficial (2h, alto impacto)
- **Referência:** [Logbook GAP-7](../logbook/2026-02-09-gaps-7-1-5-implementation.md)

**Network Policies:**
- 2 novas políticas (total Marco 2: 13)
  - allow-otel-collector-ingress (apps → collector:4317/4318)
  - allow-prometheus-otel (prometheus → otel-collector:8888)

**Decisão Arquitetural (ADR-020 + ADR-052):**
- **ADR-020:** Tempo escolhido vs Jaeger (economia $205.55/mês)
- **ADR-052:** OTel Collector Gateway pattern (centraliza ingestão, reduz acoplamento apps)
- **Padrão IRSA reutilizável:** Consistente com Loki S3 (mesmo padrão IAM)
- **Grafana-native:** Integração zero-config com Prometheus + Loki

**Benefícios Projetados:**
- Observabilidade completa: **Métricas (Prometheus) + Logs (Loki) + Traces (Tempo)**
- Troubleshooting distribuído: rastrear requests entre microserviços
- Performance profiling: identificar latências por span
- Root cause analysis: correlacionar erros com traces + logs
- Gateway pattern: apps enviam para endpoint único (reduz config por app)

**Custo:** $25.70/mês ($19.70 Tempo + $6.00 OTel Collector)

### Fase 9: FinOps Automation Multi-Ambiente (STAGING + PRODUCTION)
**Status:** 🚀 **ATIVA EM STAGING** (desde 2026-02-02)
**ADR-024:** ✅ Aprovado (Multi-Agent) | **Módulo:** `terraform/modules/finops-automation/` | **Framework:** [executor-terraform.md](../prompts/executor-terraform.md)

**Objetivo:** Automação start/stop de ambientes com estratégia evolutiva 3-fases

**🚀 IMPLEMENTAÇÃO ATIVA (STAGING):**
- **Data Ativação:** 2026-02-02
- **EventBridge Rules:** ENABLED (startup 08:00 BRT, shutdown 18:00 BRT Mon-Fri)
- **Validação Manual:** 5/5 testes completos (100% sucesso)
- **SNS Notifications:** Ativo (gilvan.galindo@fctconsig.com.br)
- **CloudWatch Alarms:** 3 alarms ativos
- **Circuit Breaker:** DynamoDB threshold=3
- **Lambda Performance:** Média 1.5s (target <3s)
- **Economia Ativa:** R$ 4.320/ano (STAGING apenas)
- **Primeira Execução Automática:** 2026-02-03 08:00 BRT

---

#### 📋 Estratégia Evolutiva

**Fase 1 (Pré-PROD): STAGING 8h-18h Mon-Fri**
```
STAGING (Dev+Homolog):  Ligado 8h-18h Mon-Fri (desenvolvimento ativo)
PROD:                   Não existe
────────────────────────────────────
Economia:               R$ 4.320/ano (STAGING apenas)
```

**Fase 2 (Go-Live): STAGING + PROD operando**
```
STAGING (Dev+Homolog):  Ligado 8h-18h Mon-Fri (testes + homologação)
PROD:                   Ligado 7h-0h 7 dias/semana (operação)
────────────────────────────────────
Economia STAGING:       R$ 4.320/ano
Economia PROD:          R$ 9.360/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 13.680/ano ✅
```

**Fase 3 (Estável): STAGING on-demand + PROD**
```
STAGING:                DESLIGADO permanentemente (liga SOB DEMANDA)
PROD:                   Ligado 7h-0h 7 dias/semana (operação)
────────────────────────────────────
Economia STAGING:       R$ 12.744/ano ✅ (95% economia, uptime ~5%)
Economia PROD:          R$ 9.360/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 22.104/ano ✅✅
NPV 3 anos:             R$ 50.479 (ROI 1.121%)
```

**Gatilhos para Fase 3:**
- [ ] PROD estável > 3 meses sem incidentes críticos
- [ ] Cobertura testes automatizados > 80%
- [ ] Equipe confortável com CI/CD production-first
- [ ] STAGING usado < 2×/mês (validar necessidade real)

---

#### 🏗️ Componentes

**Infraestrutura Compartilhada:**
- **EventBridge Scheduler:** 4 rules (2 STAGING, 2 PRODUCTION)
- **Lambda Functions:** 2 (staging, production) - Python 3.12, 512MB, 300s timeout
- **DynamoDB Table:** `finops-scheduler-state` (circuit breaker multi-ambiente)
- **BrasilAPI Integration:** Verificação de feriados nacionais brasileiros
- **IAM Roles:** 2 (least privilege, environment-specific)

**Arquitetura:**

```
EventBridge Rules (cron UTC)
  ├─ STAGING
  │   ├─ STARTUP: cron(0 11 ? * MON-FRI *)  # 8:00 AM BRT
  │   └─ SHUTDOWN: cron(0 21 ? * MON-FRI *) # 6:00 PM BRT
  │
  └─ PRODUCTION
      ├─ STARTUP: cron(0 10 ? * * *)        # 7:00 AM BRT
      └─ SHUTDOWN: cron(0 3 ? * * *)        # 0:00 (meia-noite) BRT
         ↓
Lambda finops-scheduler-{environment}
  ├─ 1. Verificar feriados (BrasilAPI) [PROD: liga em feriados, STAGING: não liga]
  ├─ 2. Health checks (STAGING: GitLab jobs | PROD: Transações DB rigorosas)
  ├─ 3. STOP: ASG min=0, RDS stop/pause, scale operators to 0
  ├─ 4. START: RDS resume, ASG restore, wait for Ready
  ├─ 5. Circuit breaker (DynamoDB state, PROD: 2 falhas, STAGING: 3 falhas)
  ├─ 6. Snapshot RDS (PROD: pré-shutdown, STAGING: não)
  └─ 7. Métricas CloudWatch + notificações Teams/PagerDuty
         ↓
AWS Resources (environment-specific)
  ├─ Auto Scaling Groups (node groups regular/production)
  ├─ RDS Instances (marco2-{env}-rds)
  └─ Kubernetes Operators (Redis, RabbitMQ scaled to 0)
```

---

#### 📊 Comparação STAGING vs PRODUCTION

| Aspecto               | STAGING (Dev+Homolog) | PRODUCTION                                 |
| --------------------- | --------------------- | ------------------------------------------ |
| **Schedule**          | 8h-18h Mon-Fri        | 7h-0h 7 dias/semana                        |
| **Uptime**            | 50h/semana (30%)      | 119h/semana (71%)                          |
| **Feriados**          | SKIP (não liga)       | LIGA (clientes ativos)                     |
| **Health Checks**     | GitLab jobs (básico)  | Transações ativas + Conexões DB (rigoroso) |
| **Rollback**          | Manual (30 min)       | Automático (< 5 min)                       |
| **SLA**               | 99.5% (8h-18h)        | 99.9% (7h-0h)                              |
| **Circuit Breaker**   | 3 falhas              | 2 falhas (mais sensível)                   |
| **Snapshot RDS**      | Não                   | Sim (pré-shutdown, RPO < 1h)               |
| **Notificação Falha** | Teams                 | PagerDuty + Teams                          |

---

#### 🎯 Node Groups Strategy

**STAGING:**

| Node Group             | Behavior             | Workloads                                  | Uptime     |
| ---------------------- | -------------------- | ------------------------------------------ | ---------- |
| **critical-always-on** | Nunca desliga        | GitLab, Harbor, ArgoCD, Prometheus/Grafana | 24/7       |
| **regular**            | Automação start/stop | Keycloak, SonarQube, Kong, Redis, RabbitMQ | 50h/semana |

**PRODUCTION:**

| Node Group             | Behavior             | Workloads                                      | Uptime      |
| ---------------------- | -------------------- | ---------------------------------------------- | ----------- |
| **critical-always-on** | Nunca desliga        | Prometheus/Grafana, GitLab CI/CD, AlertManager | 24/7        |
| **production**         | Automação start/stop | Apps cliente, APIs, Kong, Redis, RabbitMQ      | 119h/semana |

**Justificativa Node Groups:**
- **STAGING:** GitLab precisa jobs noturnos (backups, security scans), ArgoCD reconciliação contínua
- **PRODUCTION:** Observabilidade 24/7 essencial, CI/CD jobs noturnos (backups 2 AM, scans 4 AM)

---

#### 💰 Economia Consolidada

**STAGING:**

| Recurso                           | 24/7     | Com Automação | Economia    |
| --------------------------------- | -------- | ------------- | ----------- |
| EKS Control Plane                 | $37      | $37           | $0          |
| EC2 nodes regular (2x t3.medium)  | $60      | $18           | **$42** ✅   |
| EC2 nodes critical (1x t3.medium) | -        | $30           | $0 (novo)   |
| RDS db.t3.small auto-pause        | $70      | $30           | **$40** ✅   |
| Redis scaled to 0                 | $10      | $5            | **$5** ✅    |
| RabbitMQ scaled to 0              | $10      | $5            | **$5** ✅    |
| Lambda + EventBridge              | -        | $2            | -$2         |
| **TOTAL STAGING**                 | **$187** | **$127**      | **$60/mês** |

**Economia STAGING:** $60/mês × 12 = **$720/ano (USD)** = **R$ 4.320/ano (BRL, taxa 6.0)**

**PRODUCTION:**

| Recurso                               | 24/7     | Com Automação | Economia     |
| ------------------------------------- | -------- | ------------- | ------------ |
| EKS Control Plane                     | $37      | $37           | $0           |
| EC2 critical-always-on (1x t3.medium) | -        | $30           | $0 (novo)    |
| EC2 production (4x t3.large)          | $240     | $170          | **$70** ✅    |
| RDS db.t3.large Multi-AZ              | $280     | $199          | **$81** ✅    |
| Redis scaled to 0                     | $20      | $14           | **$6** ✅     |
| RabbitMQ scaled to 0                  | $20      | $14           | **$6** ✅     |
| Lambda + EventBridge                  | -        | $3            | -$3          |
| **TOTAL PRODUCTION**                  | **$652** | **$522**      | **$130/mês** |

**Economia PRODUCTION:** $130/mês × 12 = **$1.560/ano (USD)** = **R$ 9.360/ano (BRL, taxa 6.0)**

**STAGING Fase 3 (On-Demand):**
- Custo 24/7: R$ 13.464/ano
- Uptime estimado: 5% (ligando ~1×/semana, 10h/mês)
- Custo otimizado: R$ 720/ano
- **Economia Fase 3: R$ 12.744/ano** (vs R$ 4.320/ano Fase 2)

---

#### 📈 ROI Consolidado

| Fase                          | Economia Anual | Investimento Acumulado | ROI Year 1 | Payback   |
| ----------------------------- | -------------- | ---------------------- | ---------- | --------- |
| **Fase 1 (STAGING apenas)**   | R$ 4.320       | R$ 3.000               | 44%        | 6.7 meses |
| **Fase 2 (STAGING + PROD)**   | R$ 13.680      | R$ 4.500               | 204%       | 3.9 meses |
| **Fase 3 (On-demand + PROD)** | R$ 22.104      | R$ 4.500               | 391%       | 2.4 meses |

**Investimento Total:**
- STAGING: R$ 3.000 (10h desenvolvimento)
- PRODUCTION: R$ 1.500 (5h incremental)
- **Total: R$ 4.500**

**NPV 3 Anos (Fase 3):**
```
Year 1: R$ 22.104 / 1.10 = R$ 20.095
Year 2: R$ 22.104 / 1.21 = R$ 18.268
Year 3: R$ 22.104 / 1.33 = R$ 16.616
────────────────────────────────────
NPV 3 anos: R$ 54.979
Investimento: R$ 4.500
────────────────────────────────────
NPV líquido: R$ 50.479 (ROI cumulativo 1.121%) ✅✅✅
```

---

#### 🔐 Health Checks Diferenciados

**STAGING (Básico):**
```python
def staging_health_checks():
    # Bloqueia shutdown se jobs GitLab ativos
    running_jobs = check_gitlab_running_jobs()
    if running_jobs > 0:
        return False  # BLOQUEIA

    # ArgoCD healthy (aguarda sync)
    argocd_healthy = check_argocd_applications()
    return argocd_healthy
```

**PRODUCTION (Rigoroso):**
```python
def production_health_checks():
    # 1. Transações DB ativas (commits pendentes)
    if check_rds_active_transactions() > 0:
        return False  # BLOQUEIA

    # 2. Conexões idle recentes (< 5 min)
    if check_rds_idle_connections(threshold_minutes=5) > 10:
        return False

    # 3. Mensagens RabbitMQ não processadas
    if check_rabbitmq_queue_depth() > 100:
        return False

    # 4. Manutenção agendada (AlertManager)
    if not check_alertmanager_maintenance_window():
        return False

    # 5. Snapshot RDS pré-shutdown (RPO < 1h)
    create_rds_snapshot()

    return True  # AUTORIZA shutdown
```

---

#### 📊 Observabilidade

**CloudWatch Metrics:**

| Métrica                              | STAGING | PRODUCTION | Threshold           |
| ------------------------------------ | ------- | ---------- | ------------------- |
| `finops.{env}.startup.duration`      | 8 min   | 8 min      | > 10 min (warning)  |
| `finops.{env}.sla.availability`      | 99.5%   | 99.9%      | < target (critical) |
| `finops.{env}.cost_savings_daily`    | $2      | $4.33      | < $1 (investigar)   |
| `finops.{env}.circuit_breaker_state` | 0/1     | 0/1        | 1 (PagerDuty)       |
| `finops.{env}.transactions.blocked`  | -       | count      | > 0 (alerta)        |

**Grafana Dashboards:**
1. **FinOps STAGING Automation:** Uptime, economia, falhas, circuit breaker
2. **FinOps PROD Critical:** SLA 99.9%, revenue impact, startup duration, rollback automático

**Alertas:**
- STAGING: Startup > 15min (warning), 3 falhas consecutivas (critical + Teams)
- PROD: Startup > 10min (PagerDuty), 2 falhas (rollback automático + PagerDuty P1)

---

#### ⏱️ Timeline

| Fase                           | Prazo      | Pré-requisito           | Status       |
| ------------------------------ | ---------- | ----------------------- | ------------ |
| **STAGING deploy**             | 2026-02-17 | Aprovação stakeholders  | 📝 Planejado  |
| **STAGING validação 1 mês**    | 2026-03-17 | 30 dias operação        | ⏳ Aguardando |
| **PROD environment ready**     | 2026-04-01 | Marco 3 deployado       | ⏳ Aguardando |
| **PROD automation dev**        | 2026-04-08 | STAGING learnings       | ⏳ Aguardando |
| **PROD automation deploy**     | 2026-04-15 | Testes carga + runbooks | ⏳ Aguardando |
| **PROD validação 2 meses**     | 2026-06-15 | SLA 99.9% confirmado    | ⏳ Aguardando |
| **Fase 3 (STAGING on-demand)** | 2026-09-15 | PROD estável 3 meses    | ⏳ Aguardando |

**Milestone Crítico:** PROD automation SOMENTE após STAGING 1 mês operação SEM falhas

---

#### 🔗 Referências

- [Demanda STAGING](../demands/2026-01-30-automacao-finops-staging.md)
- [Demanda PRODUCTION](../demands/2026-01-30-automacao-finops-production.md)
- [ADR-024: FinOps Automation Multi-Ambiente](./decisions.md#adr-024)
- [Costs Analysis](./costs.md#automacao-finops-multi-ambiente)
- [Risks STAGING](./risks.md#r-019-riscos-automação-finops-staging)
- [Risks PRODUCTION](./risks.md#r-020-riscos-automação-finops-production)
- [Plano Executável Multi-Ambiente](../plan/aws-execution/fase-8-finops-multi-ambiente-automation.md)

---

## 📐 Diagrama de Rede

```
Internet
    ↓
[ALB] (Application Load Balancer - Fase 7)
    ↓
[Kubernetes Ingress] (test-apps namespace)
    ↓
[Services] (nginx-test, echo-server)
    ↓
[Pods] (4 total, nodes workloads)
    ↓
[VPC CNI] (AWS ENI-based networking)
    ↓
[Private Subnets] (10.0.0.0/16)
    ↓
[NAT Gateway] → Internet (egress only)
```

---

## 🔐 Segurança

### IAM IRSA Pattern (5 implementações)
1. **EBS CSI Driver:** AmazonEBSCSIDriverRole
2. **ALB Controller:** AWSLoadBalancerControllerRole
3. **Loki:** LokiS3Role (acesso bucket logs)
4. **Tempo:** TempoS3Role (acesso bucket traces) - *Fase 8 planejada*
5. **Cluster Autoscaler:** ClusterAutoscalerRole (modify ASGs)

### Network Isolation
- **Default Deny:** 3 namespaces com políticas default-deny-all
- **Explicit Allow:** 15 políticas específicas (11 deployed + 4 Fase 8 planejadas)
- **Calico:** Policy engine sem overhead de overlay network

### Secrets Management
- **AWS Secrets Manager:** RDS postgres_admin password (KMS encrypted)
- **Vault KV v2:** Todos os secrets de aplicação (grafana/oidc, sonarqube/postgresql, harbor/postgresql, harbor/oidc, keycloak/postgresql, sonarqube/saml, gitlab/ci-variables)
- **External Secrets Operator:** 7 ExternalSecrets sincronizados (SecretSynced: True) — ZERO DRIFT (DEC-065, 2026-02-19)
- **Kubernetes Secrets:** Service account tokens (automático)

---

## 📊 Observabilidade

### Métricas (Prometheus)
- **Targets:** 50+ (nodes, pods, services, kube-state-metrics)
- **Retention:** 15 dias (PVC 20Gi)
- **Dashboards:** 30+ no Grafana
- **Alerting:** Alertmanager (rules básicas configuradas)

### Logs (Loki)
- **Ingestão:** 7 Fluent Bit agents (1 por node)
- **Storage:** S3 (30 dias), in-memory cache (7 dias)
- **Query:** Grafana Explore (LogQL)
- **Parsers:** JSON, multiline (stack traces)

### Traces (Tempo - Fase 8 Planejada)
- **Backend:** Grafana Tempo SimpleScalable mode (6 pods)
- **Collector:** OpenTelemetry Collector Gateway (2 pods)
- **Storage:** S3 bucket `k8s-platform-tempo-891377105802` (30 dias retenção)
- **Query:** Grafana Explore (TraceQL)
- **Protocolos:** OTLP gRPC (4317), OTLP HTTP (4318)
- **Correlação:** Traces → Logs (via trace_id), Metrics → Traces (via exemplars)
- **Decisão:** ADR-020 (Tempo vs Jaeger, economia $205.55/mês)

---

## 💰 Custos Consolidados

### Marco 0 + Marco 1 + Marco 2

| Categoria                       | Componente                         | Custo/Mês                       |
| ------------------------------- | ---------------------------------- | ------------------------------- |
| **Compute**                     | EKS Control Plane                  | $73.00                          |
|                                 | EC2 Nodes (7 × t3.medium)          | ~$477.00                        |
| **Storage**                     | EBS gp3 (107Gi total)              | $8.56                           |
|                                 | S3 Terraform State                 | $0.07                           |
|                                 | S3 Loki Logs (500GB)               | $11.50                          |
|                                 | S3 Tempo Traces (500GB) - *Fase 8* | $11.50                          |
| **Networking**                  | ALBs (2 test-apps)                 | $32.40                          |
|                                 | NAT Gateways (2)                   | ~$66.00 (reaproveitado Marco 0) |
| **Secrets**                     | AWS Secrets Manager (1 secret)     | $0.40                           |
| **Database**                    | DynamoDB Lock Table                | $0.25                           |
| **API Requests**                | S3 API (Tempo PUT/GET) - *Fase 8*  | $5.00                           |
| **TOTAL Marco 0+1+2 (7 Fases)** |                                    | **~$666/mês**                   |
| **TOTAL Marco 0+1+2 (8 Fases)** |                                    | **~$685.70/mês**                |

**Economia vs Baseline:**
- Loki vs CloudWatch: $423/ano saved
- VPC reaproveitada: $1.152/ano saved
- Tempo vs Jaeger: $2.467/ano saved (Fase 8)
- Total Economia: ~$4.042/ano

---

## 🚀 Marco 3: Workloads

**Status:** 🚧 Em Progresso (GitLab Staging deployed 2026-02-04)
**Estratégia:** 2 Fases - Fase 1 sem domínio (LoadBalancer), Fase 2 com TLS/SSO

**⚠️ Nota de Escopo:**

- **STAGING (gitlab-staging):** Parte do **Quickstart MVP** (6 semanas, completo)
- **GitLab:** **Instância ÚNICA compartilhada** (Momento A: usa recursos staging, Momento B: migrará para recursos prod)
- **PRODUCTION (data-services-prod):** Data services prod criados **posterior ao quickstart** (2026-02-09) para futura migração GitLab
- **Outros componentes (Keycloak, ArgoCD, Harbor):** Terão instâncias **separadas** por ambiente (não compartilhados)

---

### ✅ IMPLEMENTADO (STAGING) - Quickstart MVP

#### GitLab CE - CI/CD Platform (Instância Única Compartilhada)

**Status:** ✅ Deployed (2026-02-04)
**Namespace:** gitlab-staging (Momento A - usando recursos staging)
**Versão:** 8.7.0 (Helm chart gitlab/gitlab)
**ADR:** ADR-021 Fase 1 (HTTP-only, sem custom domain)
**Estratégia:** Instância ÚNICA compartilhada - futuramente migrará para recursos prod (Momento B) conforme [gitlab-shared-architecture.md](../plan/quickstart/gitlab-shared-architecture.md)

**Componentes:**

| Componente          | Pods          | Status                              | Node      |
| ------------------- | ------------- | ----------------------------------- | --------- |
| **webservice**      | 2 replicas    | Running                             | workloads |
| **sidekiq**         | 1 replica     | Running                             | workloads |
| **gitaly**          | 1 StatefulSet | Running                             | workloads |
| **shell**           | 2 replicas    | Running                             | workloads |
| **registry**        | 2 replicas    | Running                             | workloads |
| **kas**             | 2 replicas    | Running                             | workloads |
| **gitlab-exporter** | 1 replica     | Running                             | workloads |
| **runner**          | ⚠️ CrashLoop   | DNS issue (esperado ADR-021 Fase 1) | -         |

**Dependências:**
- PostgreSQL RDS: `k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432`
- Redis: `rfrm-redis.data-services.svc.cluster.local:6379` (Spotahome Operator)
- S3 Buckets:
  - Artifacts: `k8s-platform-gitlab-artifacts-891377105802`
  - Uploads: `k8s-platform-gitlab-artifacts-891377105802` (shared)
- IRSA: `k8s-platform-prod-gitlab-sa-role` (S3 access)

**Ingress (ALB):**

| Service    | Host                      | ALB                                                                 | Status |
| ---------- | ------------------------- | ------------------------------------------------------------------- | ------ |
| webservice | gitlab.staging.internal   | k8s-gitlabstaging-da5a4e8c6d-1143600047.us-east-1.elb.amazonaws.com | ✅      |
| registry   | registry.staging.internal | k8s-gitlabstaging-da5a4e8c6d-1143600047.us-east-1.elb.amazonaws.com | ✅      |
| kas        | kas.staging.internal      | k8s-gitlabstaging-da5a4e8c6d-1143600047.us-east-1.elb.amazonaws.com | ✅      |

> ALB IPs (2026-02-13, dinâmicos): 54.209.81.173 / 34.202.111.35 — re-resolver se falhar conectividade

**Secrets:**
- `gitlab-root-password`: Initial root password (Opaque)
- `gitlab-object-storage`: IRSA S3 config (provider=AWS, use_iam_profile=true)

**Network Policies:** 9 policies aplicadas (default-deny + allow specific traffic)

**Observabilidade:** ServiceMonitor criado (Prometheus scraping /-/metrics)

**⚠️ Limitações Conhecidas (ADR-021 Fase 1):**
- Webhooks HTTPS externos: Não funcionam (sem TLS — Fase 2)
- SSO: Keycloak OIDC pendente (client harbor/oidc ainda placeholder no Vault)

**Resolvido (2026-02-18):**
- ~~`gitlab.example.com` placeholder~~ → domínio corrigido para `staging.internal` (Ingress + Helm values)

**Validações Completas:**
- ✅ Terraform idempotency (plan → "No changes")
- ✅ Core services Running
- ✅ PostgreSQL + Redis connectivity
- ✅ S3 IRSA working
- ✅ ALB health checks passing

**Custo:** ~$0 adicional (usa RDS/Redis/S3 já existentes + 3 ALBs $48.60/mês)

**Referências:**
- Logbook: [2026-02-04-execucao-pendente-staging.md](../logbook/2026-02-04-execucao-pendente-staging.md)
- Deploy duration: 7m18s (438s)

---

---

### ✅ IMPLEMENTADO (PRODUCTION) - Pós-Quickstart

**⚠️ IMPORTANTE:** Componentes abaixo foram adicionados **APÓS** conclusão do Quickstart MVP (staging).

#### Production Environment - Data Services
**Status:** ✅ Deployed (2026-02-09)
**Namespace:** data-services-prod
**Logbook:** [2026-02-09-cluster-remediation.md](../logbook/2026-02-09-cluster-remediation.md)
**Escopo:** Expansão para produção, **NÃO faz parte do quickstart**

**Componentes:**

| Componente             | Tipo           | Status    | Função                                 |
| ---------------------- | -------------- | --------- | -------------------------------------- |
| **data-services-prod** | Namespace      | ✅ Created | Isolated prod data services            |
| **postgresql-prod**    | ServiceMonitor | ✅ Active  | Prometheus scraping PostgreSQL metrics |
| **gitlab**             | ServiceMonitor | ✅ Active  | Prometheus scraping GitLab metrics     |

**Network Policies (10 total):**

**Production Namespace Isolation:**
- ✅ `deny-from-staging` - Blocks staging → prod traffic (zero-trust boundary)

**GitLab Production Security (9 policies):**
- ✅ `deny-default` - Default deny all ingress/egress
- ✅ `allow-alb` - ALB Controller → GitLab pods (HTTP/HTTPS)
- ✅ `allow-postgres` - GitLab → PostgreSQL RDS (port 5432)
- ✅ `allow-redis` - GitLab → Redis Operator (port 6379)
- ✅ `allow-monitoring` - Prometheus → GitLab metrics (port 8080)
- ✅ `allow-internal` - GitLab pods inter-communication
- ✅ `allow-dns` - All pods → CoreDNS (UDP 53)
- ✅ `allow-api-server` - All pods → K8s API (TCP 443)
- ✅ `allow-egress-s3` - GitLab → S3 IRSA (artifacts/uploads)

**Deployment Details:**

| Aspecto              | Valor                                                                        |
| -------------------- | ---------------------------------------------------------------------------- |
| **Adicionado em**    | 2026-02-09 14:00 UTC                                                         |
| **Demanda**          | [Cluster Remediation](../logbook/2026-02-09-cluster-remediation.md#sessão-3) |
| **Terraform State**  | 57 → 68 recursos (+19%)                                                      |
| **Drift Correction** | 13 add, 1 change → 0 (idempotente)                                           |
| **Apply Duration**   | ~1h30min (3 attempts, AML monitoring)                                        |
| **GitLab Helm**      | Revision 4 → 5 (network policies added)                                      |

**Observabilidade:**
- ✅ ServiceMonitor postgresql-prod: scraping `/metrics` endpoint
- ✅ ServiceMonitor gitlab: scraping `/-/metrics` endpoint
- ✅ Grafana dashboards: PostgreSQL queries, GitLab CI/CD metrics
- ✅ Network flow visibility: Calico policies + Prometheus metrics

**Validações:**
- ✅ Terraform idempotency: `terraform plan` → "No changes"
- ✅ GitLab pods: sidekiq 1/1, webservice 2/2 Running
- ✅ PostgreSQL connectivity: Verified via ServiceMonitor scrape success
- ⚠️ GitLab runners: CrashLoopBackOff (known issue ADR-021 Fase 1)

**Custo:** $0 adicional (ServiceMonitors + NetworkPolicies = infrastructure-only)

---

### 📋 PLANEJADO: CI/CD Pipeline Completo (ADR-030 a 035)

**Status:** 📝 Planejado (2026-02-05)
**Timeline:** 22h desenvolvimento (3-4 dias úteis)
**Logbook:** [2026-02-05-cicd-pipeline-completo](../logbook/2026-02-05-cicd-pipeline-completo-sonarqube-painel-central.md)

---

#### FASE 1: CI/CD Foundation (16h)

**1. GitLab Runner DNS Fix (ADR-021 Fase 2) — 4h**
- **Domain:** Route53 `k8s-platform.example.com` ($0.50/mês)
- **TLS:** ACM wildcard certificate (free)
- **Fix:** Runner registration functional (resolve R-019)
- **Custo:** +$0.50/mês ($6/ano)

**2. Vault HA + KMS Auto-Unseal (ADR-030) — ✅ IMPLEMENTADO (2026-02-06)**

**Status:** ✅ Operational (3/3 replicas Running, unsealed)
**Namespace:** vault-system
**Versão:** Helm hashicorp/vault v0.27.0 (Raft HA backend)
**Deployment Time:** 2h32min (incluindo troubleshooting infra)
**Logbook:** [2026-02-06-vault-recovery-vpc-endpoints.md](../logbook/2026-02-06-vault-recovery-vpc-endpoints.md)

**Componentes:**

| Component            | Replicas      | Status      | Storage                     | Node Type |
| -------------------- | ------------- | ----------- | --------------------------- | --------- |
| vault                | 3 StatefulSet | 1/1 Running | 10Gi data + 5Gi audit (gp2) | workloads |
| vault-agent-injector | 1 Deployment  | 1/1 Running | -                           | workloads |

**Auto-Unseal:** AWS KMS
- **KMS Key:** `alias/vault-unseal-k8s-platform-prod`
- **Benefit:** Zero manual intervention após restart (auto-recovery)
- **Recovery Keys:** 5 keys B64-encoded (disaster recovery only)
- **Root Token:** Stored in K8s Secret `vault-root-token` (vault-system NS)

**Storage Backend:** Raft (Integrated Storage)
- **Data:** 3× 10Gi PVCs (pvc-1f4e6089, pvc-83f182b0, pvc-aff26d41)
- **Audit:** 3× 5Gi PVCs (pvc-2fa86f1f, pvc-9cd23503, pvc-4f77fc2b)
- **Total:** 45Gi EBS gp2 ($3.60/mês)
- **Backups:** S3 Raft snapshots 30d retention ($0.20/mês)

**Kubernetes Auth:**
- **Mount Path:** `kubernetes`
- **Policy:** `eso-reader` (read-only `secret/data/*`)
- **Role:** `eso-reader` (bound to SA `external-secrets/external-secrets-operator`)
- **JWT Reviewer:** K8s API server token validation

**OIDC Auth (2026-02-18):**
- **Mount Path:** `auth/oidc/`
- **Discovery URL:** `http://keycloak.staging.internal/auth/realms/platform`
- **Client:** `vault` (uuid: f676f69f, confidential, client_secret in Vault)
- **Keycloak Groups:** `vault-admins` + `vault-readers` (realm: platform)
- **Roles:** `admin` (bound vault-admins, TTL 8h) + `reader` (any user, TTL 4h)
- **Policies:** `vault-admin` (secret/*, sys/policies/*) + `vault-reader` (secret/data/* read-only)
- **Redirect URIs:** UI `http://vault.staging.internal/ui/vault/auth/oidc/oidc/callback` + CLI `localhost:8250`
- **TF commit:** `5dcf56a` — `feat(vault): SSO via Keycloak OIDC auth method`

**Secrets Managed:**
- `secret/data/keycloak/postgresql` (username, password, host, database)
- Pattern: KV v2 engine (versioned, rotatable)
- Sync: ExternalSecret 1h refresh → K8s Secret auto-update

**High Availability:**
- **Raft Consensus:** 3 voting members (quorum = 2)
- **Leader Election:** Automatic (current leader: vault-2)
- **Failover:** < 30s (Raft re-election)
- **Cluster Name:** `vault-cluster-aecd4662`

**Recovery Incident (2026-02-06):**
- **Downtime:** 15h (pods ContainerCreating/Pending)
- **Root Cause:** VPC Endpoints (STS/EC2) ausentes → CSI driver timeout
- **Resolution:** Created VPC Endpoints + NodeGroup scale → operational
- **MTTR:** 2h32min (deep troubleshooting multi-layer)

**Custo:** $4.80/mês ($57.60/ano)
- KMS: $1/mês
- S3 backups: $0.20/mês
- EBS volumes: $3.60/mês (45Gi gp2)

**3. External Secrets Operator (ADR-031) — 1.5h**
- **Versão:** Helm external-secrets/external-secrets v0.9.11
- **CRDs:** 6 instalados (ExternalSecret, SecretStore, ClusterSecretStore)
- **Backend:** ClusterSecretStore `vault-backend` → Vault K8s auth
- **Sync:** Keycloak (✅), SonarQube SAML SP (✅ 2026-02-18), GitLab (pending), Harbor (pending)
- **Pattern:** ExternalSecret → Vault KV v2 `secret/data/<service>/<resource>`
- **Refresh:** 1h (configurable per ExternalSecret)
- **Custo:** $0 (pods nodes existentes)

**4. Harbor Container Registry (ADR-032) — 4h**
- **Versão:** Helm goharbor/harbor v1.14.0
- **Backend:** S3 `k8s-platform-harbor-images-*` IRSA ($11.50/mês)
- **Database:** PostgreSQL RDS shared DB `harbor` ($0)
- **Cache:** Redis Operator shared ($0)
- **Scanner:** Trivy integrated (scan-on-push)
- **Auth:** Robot accounts via ESO (gitlab-ci push/pull)
- **imagePullSecrets:** ClusterExternalSecret all namespaces
- **Custo:** +$27.70/mês (S3 $11.50 + ALB $16.20)

**5. ArgoCD ApplicationSets (ADR-033) — 2h**
- **AppProject:** `data-engineering` (3 apps)
- **ApplicationSet:** Hatch, VemSoft, BucketConnector
- **Sync:** Auto-sync enabled (prune + self-heal)
- **RBAC:** No secret enumeration (CI role)
- **OIDC SSO (2026-02-18):** ✅ Keycloak OIDC funcional (5 fixes cascata)
  - **issuer:** `http://keycloak.staging.internal/auth/realms/platform`
  - **clientID:** `argocd`
  - **clientSecret:** `$oidc.keycloak.clientSecret` (key no `argocd-secret`)
  - **requestedScopes:** `["openid", "profile", "email"]`
  - **Split-horizon:** issuer usa hostname externo, CoreDNS resolve internamente
  - **Fixes:** DNS service name, redirect URL protocol, split-horizon, invalid scopes, secret syntax
  - **Logbook:** [2026-02-18-keycloak-service-name-fix.md](../logbook/2026-02-18-keycloak-service-name-fix.md)
- **Custo:** $0 (ArgoCD já deployed Marco 2)

**6. Keycloak SSO Platform (GAP-001) — 2h**
- **Adicionado em:** 2026-02-06 | **Upgraded:** 2026-02-11 (17.0.1 WildFly → 26.5.1 Quarkus)
- **Versão:** Helm codecentric/keycloakx v7.1.7 (Keycloak 26.5.1 Quarkus)
- **Namespace:** keycloak
- **Replicas:** 1 (staging accepted, PROD: 2)
- **Database:** PostgreSQL RDS shared DB `keycloak` ($0)
- **Secrets:** ExternalSecret → Vault `secret/data/keycloak/postgresql`

  - Pattern: R-029 RESOLVED (Vault backend desde inception, sem AWS SM)
  - Auto-sync 1h, credentials rotacionáveis via Vault KV v2

- **Admin Password:** Terraform random_password (24 chars, managed)
- **OIDC Providers:** ArgoCD (✅ SSO validated), SonarQube (✅ SAML validated), GitLab, Grafana, Harbor, Vault (✅ OIDC validated)
- **Startup Resilience (2026-02-13):**
  - initContainer `wait-for-db` (busybox nc -z) — resolve race condition FinOps/RDS
  - `--health-enabled=true` — habilita smallrye-health para probes
  - startupProbe: 330s tolerancia (60×5s) — protege contra liveness kill durante cold start
  - Toleration `workload=critical:NoSchedule` — scheduling nos t3.xlarge com CPU livre
- **Custo:** $0 (usa RDS shared + nodes existentes)
- **Logbook:** [2026-02-06-vault-eso-keycloak-integration.md](../logbook/2026-02-06-vault-eso-keycloak-integration.md), [2026-02-11-keycloak-26-deployment-final.md](../logbook/2026-02-11-keycloak-26-deployment-final.md)

**7. E2E Pipeline Test — 1.5h**
- **Flow:** GitLab → Kaniko + Vault creds → Harbor push → Trivy scan → ArgoCD sync
- **Target:** < 15min commit-to-deploy
- **Validation:** Pods Running, health checks pass

**SUBTOTAL FASE 1:** 16h | **$29.90/mês** ($358.80/ano)

---

#### FASE 2: Code Quality + Security (3h)

##### 8. SonarQube Community Edition (ADR-034/DEC-062/DEC-065) — ✅ SAML SSO OK (2026-02-18)
- **Versão:** Helm sonarqube/sonarqube v10.7.0
- **Database:** PostgreSQL RDS shared DB `sonarqube` ($0)
- **DB Secrets:** Vault `secret/sonarqube/postgresql` → ESO → `sonarqube-postgresql` (DEC-065, 2026-02-19)
- **ALB:** `sonarqube.staging.internal` (platform-staging group)
- **Auth:** SAML 2.0 via Keycloak realm `platform` (client: sonarqube)
- **SP cert/key:** Vault KV `secret/sonarqube/saml` → ESO → `sonarqube-sp-saml` (secret.properties)
- **sonarSecretProperties:** `sonarqube-sp-saml` (concat-properties init container)
- **serverBaseURL:** `http://sonarqube.staging.internal` (ACS URL correta no SAMLRequest)
- **Keycloak:** `saml.client.signature=true`, SP cert carregado, `saml_name_id_format=email`
- **Resources:** 500m/2Gi requests, 2000m/4Gi limits
- **Custo:** $0 adicional (ALB compartilhado platform-staging group)

**SUBTOTAL FASE 2:** 3h | **$26.20/mês** ($314.40/ano)

---

#### FASE 3: Painel Central Observabilidade (3h)

**8. Grafana Multi-Cluster Dashboard (ADR-035) — 3h**
- **Datasources:**
  - Prometheus Production (local)
  - Prometheus Staging (NLB $16.20/mês)
  - Loki Production/Staging (S3 shared)
  - Tempo Production/Staging (Fase 8 Marco 2)
  - ArgoCD Metrics (exporter enabled)
  - SonarQube Metrics (webhook → Pushgateway)
- **Dashboards:**
  - 🏠 Home: Multi-Cluster Overview
  - 📊 Cluster Health (staging vs prod)
  - 📦 Applications Status (per environment)
  - 🚀 GitOps Status (ArgoCD sync)
  - 🔍 Code Quality (SonarQube gates)
  - 💰 FinOps Cost Dashboard
  - 🔥 Alerts Overview (AlertManager)
- **Complementos:**
  - ArgoCD UI: GitOps drill-down
  - OpenLens: Troubleshooting desktop (devs individuais)
- **Custo:** +$16.20/mês ($194.40/ano)

**SUBTOTAL FASE 3:** 3h | **$16.20/mês** ($194.40/ano)

---

### 💰 Custos Consolidados Marco 3 Completo

| Componente                   | Detalhes              | Custo/Mês       | Anual             |
| ---------------------------- | --------------------- | --------------- | ----------------- |
| **GitLab (deployed)**        | 3 ALBs + S3 artifacts | $48.60          | $583.20           |
| **Data Services (deployed)** | PostgreSQL RDS shared | $50.00          | $600.00           |
| **GitLab Runner DNS**        | Route53 Hosted Zone   | $0.50           | $6.00             |
| **Vault HA**                 | KMS + S3 + Lambda     | $1.70           | $20.40            |
| **ESO**                      | Pods                  | $0              | $0                |
| **Harbor**                   | S3 + ALB              | $27.70          | $332.40           |
| **ArgoCD Apps**              | ApplicationSets       | $0              | $0                |
| **SonarQube**                | ALB + S3              | $26.20          | $314.40           |
| **Painel Central**           | NLB Prometheus        | $16.20          | $194.40           |
| **TOTAL MARCO 3**            |                       | **$170.90/mês** | **$2.050,80/ano** |

**Economia vs Quickstart Baseline ($737.10/mês):** -$566.20/mês (-76.8%) ✅✅✅

---

### 🎯 Drivers de Economia

1. **Operators vs Bitnami:** Redis + RabbitMQ $0 vs $32.40/mês = **$388.80/ano**
2. **PostgreSQL RDS Shared:** 1 RDS $50/mês vs 3× $150/mês = **$1.200/ano**
3. **S3 Consolidated:** Harbor reusa buckets = **$84/ano**
4. **Vault vs Secrets Manager:** $1.70/mês vs $5/mês = **$39.60/ano**
5. **SonarQube Community:** $0 vs Developer $150/ano = **$150/ano**
6. **Reserved Instances:** -$124/mês = **$1.488/ano**
7. **IngressGroup Consolidation:** -$16.20/mês = **$194.40/ano**
8. **FinOps Automation (staging ativo):** **$720/ano** (R$ 4.320 @ taxa 6.0)

**Total Economia Anual:** **$6.794,40/ano** ✅

---

## 📚 Referências

- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kube-Prometheus-Stack Docs](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Calico Network Policies](https://docs.tigera.io/calico/latest/network-policy/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

---

**Mantenedor:** DevOps Team
**Última Revisão:** 2026-01-29
**Próxima Revisão:** Marco 3 Planning

---

## Fase 8: Distributed Tracing (Parcialmente Deployado)

### OpenTelemetry Collector

| Atributo              | Valor                                                                            |
| --------------------- | -------------------------------------------------------------------------------- |
| **Status**            | ✅ Deployado (2026-02-09, antecipado para Semana 3 FinOps)                        |
| **Namespace**         | monitoring                                                                       |
| **Replicas**          | 2/2 Running (HA)                                                                 |
| **Resources**         | 100m CPU, 256Mi RAM requests / 500m, 512Mi limits (por pod)                      |
| **OTLP Endpoints**    | gRPC :4317, HTTP :4318                                                           |
| **Exporters**         | Tempo (traces), Prometheus (metrics), Loki (logs)                                |
| **Custo**             | $0/mês (usa nodes existentes)                                                    |
| **Integração FinOps** | Habilita trace validation para rightsizing decisions (VPA + latency correlation) |

**Pendente:**
- HPA deployment (manifest criado, aguarda import TF state)
- PDB deployment (manifest criado, aguarda import TF state)
- App instrumentation (Phase 2B — Dia 3-5 Semana 3)

**Referências:**
- [GAP-007](../plan/GAP-007-opentelemetry-collector.md)
- [Roadmap FinOps 90d](../finops/optimization-roadmap-90days.md#semana-3-8-medium-wins--observability)
- [Logbook 2026-02-10](../logbook/2026-02-10-otel-collector-deployment.md)
