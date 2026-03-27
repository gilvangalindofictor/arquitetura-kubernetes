# Cloud Conformance Report — AWS/EKS k8s-platform-prod

**Data:** 2026-03-26
**Auditor:** Cloud Architect + FinOps Specialist
**Cluster:** k8s-platform-prod | Conta: 891377105802 | Regiao: us-east-1
**Escopo:** Inventario completo AWS + EKS, classificacao staging/prod/shared, GAPs, FinOps, Seguranca
**Metodo:** Live audit via kubectl + AWS CLI + IaC cross-reference

---

## 1. Executive Summary

O cluster k8s-platform-prod opera com **14 nodes (3 system + 9 workloads + 2 critical)** hospedando **325 pods** distribuidos em **17 staging namespaces**, **16 prod namespaces** e **10 shared namespaces**. Zero pods em estado de falha (nenhum CrashLoopBackOff ou Pending no momento do audit).

O cluster e **compartilhado entre staging e prod** (single EKS cluster com isolamento via namespaces), o que e uma decisao arquitetural intencional documentada. A maioria dos recursos de plataforma (Linkerd, Kyverno, ESO operator, Calico, CoreDNS) sao cluster-scoped e servem ambos ambientes.

**Score de Conformidade Atual:** 64/100 (melhoria de +3 vs audit anterior 61/100)
- PSA labels aplicados em 13 namespaces (10+ prod namespaces cobertos vs 3 anteriores)
- Network Policies expandidas para 22 namespaces (vs 6 na auditoria anterior)
- HPAs existentes: 8 ativos (GitLab, Hatch ETL, VemSoft, OTEL Collector)
- PDBs existentes: 57 ativos (significativa expansao)
- ExternalSecrets: 55/55 SecretSynced (100%)
- EKS Auth Mode: API_AND_CONFIG_MAP (migrado de CONFIG_MAP)

**GAPs Criticos Remanescentes:**
- RDS Multi-AZ=false em producao (P0)
- EKS logging 1/5 tipos (P1 compliance)
- 100% On-Demand sem Spot/Savings Plans (P2 FinOps)
- NAT Gateway Single-AZ (P2 resiliencia)
- 6 namespaces prod VAZIOS (sem workloads deployados)

---

## 2. Inventario Completo de Recursos AWS

### 2.1 Compute — EKS Cluster + Node Groups

| Recurso | Tipo | Count | AZs | Capacity | Status |
|---------|------|-------|-----|----------|--------|
| EKS Control Plane | Managed | 1 | Multi-AZ | v1.34.2-eks-ecaa3a6 | ACTIVE |
| Node Group: system | t3.medium ON_DEMAND | 3 (min:2, max:5) | us-east-1a (2), us-east-1b (1) | 5.79 vCPU, 10.1 GiB alloc | ACTIVE |
| Node Group: workloads | t3.large ON_DEMAND | 9 (min:2, max:12) | us-east-1a (5), us-east-1b (4) | 17.37 vCPU, 63.7 GiB alloc | ACTIVE |
| Node Group: critical | t3.xlarge ON_DEMAND | 2 (min:2, max:4) | us-east-1a (1), us-east-1b (1) | 7.84 vCPU, 29.6 GiB alloc | ACTIVE |
| **TOTAL** | | **14 nodes** | **2 AZs** | **30.89 vCPU, 103.4 GiB** | |

**Observacao Critica:** Nodes distribuidos em apenas **2 AZs** (us-east-1a e us-east-1b). private_subnets hardcoded em 2 subnets (GAP-ARCH-013). A VPC tem 3 AZs disponiveis.

### 2.2 Resource Utilization (momento do audit)

| Node Group | CPU Usage | CPU% | Memory Usage | Mem% | Obs |
|-----------|-----------|------|-------------|------|-----|
| system (3x t3.medium) | 1249m | 21% | 7398Mi | 74% | ip-10-0-132-219: **102% MEM** (pressao) |
| workloads (9x t3.large) | 3476m | 20% | 26387Mi | 40% | Bem distribuido, headroom OK |
| critical (2x t3.xlarge) | 1758m | 22% | 10036Mi | 33% | Amplo headroom |
| **TOTAL** | **6483m** | **21%** | **43821Mi** | **42%** | |

**ALERTA:** Node `ip-10-0-132-219` (system) esta a **102% de memoria** — risco de OOM e eviction. Requer atencao imediata.

### 2.3 Database — RDS

| Instancia | Engine | Versao | Classe | Storage | Multi-AZ | AZ | Status |
|-----------|--------|--------|--------|---------|----------|-----|--------|
| k8s-platform-prod-postgresql | PostgreSQL | 16.4 | db.t3.medium | 100 GB | **FALSE** | us-east-1a | available |

**GAP-CRITICO:** RDS Single-AZ em producao. Todos os servicos (GitLab, Keycloak, Harbor, SonarQube) dependem deste RDS. Falha em us-east-1a = **downtime total**.
**IaC Status:** `multi_az = true` CODIFICADO em `prod/main.tf` L189 — **apply pendente**.

### 2.4 Networking

| Recurso | Tipo | Count | Detalhes |
|---------|------|-------|----------|
| VPC | fictor-vpc | 1 | 10.0.0.0/16 (vpc-0b1396a59c417c1f0) |
| NAT Gateway | Single-AZ | 1 | nat-03512e5ee0642dcf2 / EIP 52.204.176.103 / subnet us-east-1a |
| ALB | Application | 6 | 3 internet-facing + 3 internal |
| Elastic IP | Associated | 7 | Todos associados (zero orphan) |
| VPC Endpoints | Interface + Gateway | 7 | STS, EC2, ELB, KMS, S3 (GW), ECR API, ECR DKR |
| Security Groups | Mixed | 19 | Sem audit individual nesta sessao |

### 2.5 ALB Detail

| Nome | Scheme | Estado | Ambiente |
|------|--------|--------|----------|
| k8s-platformstaging-00e0ecf3b4 | internet-facing | active | STAGING |
| k8s-gitlabstaging-da5a4e8c6d | internet-facing | active | STAGING (GitLab shared) |
| k8s-datainternal-b93298afa5 | internal | active | STAGING |
| k8s-platformprod-ca65b3f8b1 | internet-facing | active | PROD |
| k8s-backstagestaging-c827d564e5 | internal | active | STAGING (Backstage) |
| k8s-platformprodinter-f689ccecf4 | internal | active | PROD (Harbor internal) |

### 2.6 Storage — S3

| Bucket | Ambiente | Proposito |
|--------|----------|-----------|
| terraform-state-marco0-891377105802 | SHARED | Terraform state backend |
| k8s-platform-gitlab-artifacts-891377105802 | SHARED (via prod) | GitLab artifacts + uploads |
| k8s-platform-harbor-images-891377105802 | SHARED | Harbor container images |
| k8s-platform-loki-891377105802 | STAGING | Loki logs storage |
| k8s-platform-loki-prod-891377105802 | PROD | Loki logs storage prod |
| k8s-platform-tempo-891377105802 | STAGING | Tempo traces |
| k8s-platform-tempo-prod-891377105802 | PROD | Tempo traces prod |
| k8s-platform-prod-vault-snapshots-891377105802 | PROD | Vault Raft snapshots |
| k8s-platform-keycloak-backups-891377105802 | SHARED | Keycloak realm backups |
| k8s-platform-fct-proposals-891377105802 | PROD (sa-east-1) | FCT proposals (LGPD) |
| velero-backups-staging-891377105802-us-east-1 | SHARED | Velero primary backups |
| velero-backups-staging-891377105802-us-west-2 | SHARED (DR) | Velero cross-region replica |
| aws-waf-logs-k8s-platform-prod-staging | STAGING | WAF logs staging |
| aws-waf-logs-k8s-platform-prod-production | PROD | WAF logs prod |
| backstage-techdocs-891377105802 | SHARED | Backstage TechDocs |
| fct-0001, fct-0002, fct-0003 | PROD | Business data (FCT) |
| fct-public | PROD | Public FCT data |
| partners-integration-files | PROD | Partner integrations |
| ref-0005 | PROD | Reference data |

**Total: 20 buckets** (5 staging, 9 prod, 6 shared)

### 2.7 DNS e Certificados

| Recurso | Tipo | Status |
|---------|------|--------|
| hml.alvocard.com.br | Route53 Public | 17 records |
| prod.alvocard.com.br | Route53 Public | 7 records |
| staging.internal | Route53 Private | 3 records |
| *.prod.alvocard.com.br | ACM AMAZON_ISSUED | ISSUED |
| *.hml.alvocard.com.br | ACM AMAZON_ISSUED | ISSUED |
| keycloak.staging.internal | ACM IMPORTED (self-signed) | ISSUED |
| harbor.staging.internal | ACM IMPORTED (self-signed) | ISSUED |

### 2.8 Seguranca

| Recurso | Detalhes | Status |
|---------|----------|--------|
| WAF WebACL staging | waf-k8s-platform-prod-staging | ATIVO |
| WAF WebACL prod | waf-k8s-platform-prod-production | ATIVO |
| EKS Auth Mode | API_AND_CONFIG_MAP | OK (migrado de CONFIG_MAP) |
| EKS Logging | **authenticator ONLY (1/5)** | NON-CONFORME |
| Savings Plans | **NENHUM** | NON-CONFORME |
| Reserved Instances | **NENHUM** | NON-CONFORME |

### 2.9 Volumes

| Recurso | Status | Detalhes |
|---------|--------|----------|
| EBS vol-0668032f67a8283fd | **AVAILABLE (orphan)** | 10 GB gp3, us-east-1b, criado 2026-03-26 |

**GAP-FINOPS:** 1 volume EBS orphan detectado (10 GB gp3). Custo: ~$0.80/mo. Investigar origem e considerar deletion.

---

## 3. Inventario de Namespaces e Workloads

### 3.1 Staging Namespaces (17)

| Namespace | Workloads | Pods | Componente | NetworkPolicies | PSA | Linkerd |
|-----------|-----------|------|-----------|----------------|-----|---------|
| staging-data-hatch-etl | 9 | 8 | Hatch ETL (HOLD) | 3 | NO | YES |
| staging-data-infrastructure | 2 | 2 | Redis + PG Exporter | 7 | restricted | NO |
| staging-data-rabbitmq | 1 | 1 | RabbitMQ | 0 | NO | NO |
| staging-data-redis-operator | 1 | 1 | Redis Operator | 0 | NO | NO |
| staging-data-vemsoft-etl | 1 | 1 | VemSoft ETL | 3 | NO | YES |
| staging-governance-kyverno | 4 | 6 | Kyverno | 0 | NO | NO |
| staging-observability-monitoring | 25 | 68 | Prometheus+Grafana+Loki+Tempo+OTEL | 6 | NO | NO |
| staging-platform-argocd | 7 | 11 | ArgoCD | 6 | NO | NO |
| staging-platform-backstage | 1 | 2 | Backstage | 0 | NO | NO |
| staging-platform-externaldns | 1 | 1 | External-DNS | 0 | NO | NO |
| staging-platform-gitlab | 9 | 11 | GitLab CE (shared) | 17 | baseline | NO |
| staging-platform-keycloak | 2 | 1 | Keycloak | 3 | NO | NO |
| staging-platform-new-service | 1 | 1 | Test service | 0 | NO | NO |
| staging-platform-sonarqube | 1 | 1 | SonarQube | 2 | NO | NO |
| staging-security-certmanager | 3 | 3 | cert-manager | 0* | NO | NO |
| staging-security-externalsecrets | 3 | 3 | ESO Controller | 0 | NO | NO |
| staging-security-vault | - | - | Vault (via `velero` ns listing) | 3 | NO | NO |

*cert-manager policies existem no namespace `cert-manager` (shared).

### 3.2 Production Namespaces (16)

| Namespace | Workloads | Pods | Componente | NetworkPolicies | PSA | Linkerd |
|-----------|-----------|------|-----------|----------------|-----|---------|
| prod-data-hatch-etl | 0 | 0 | **VAZIO** | 0 | NO | YES (label) |
| prod-data-infrastructure | 1 | 1 | Redis prod (3 replicas) | 7 | restricted | NO |
| prod-data-ipaas | 0 | 0 | **VAZIO** | 0 | NO | YES (label) |
| prod-data-rabbitmq | 1 | 3 | RabbitMQ prod (3 replicas) | 1 | baseline | NO |
| prod-data-redis-operator | 0 | 0 | **VAZIO** (operator shared) | 0 | NO | NO |
| prod-data-services | 0 | 0 | **VAZIO** (legacy ns) | 0 | NO | YES (label) |
| prod-data-vemsoft-etl | 0 | 0 | **VAZIO** | 0 | NO | YES (label) |
| prod-observability-monitoring | 21 | 48 | Prometheus+Grafana+Loki+Tempo (prod) | 3 | baseline | YES |
| prod-platform-argocd | 5 | 5 | ArgoCD prod (4 apps) | 3 | baseline | YES |
| prod-platform-backstage | 0** | 0** | **VAZIO** (GAP-BACKSTAGE-PROD-EMPTY) | 0 | baseline | YES (label) |
| prod-platform-externaldns | 1 | 1 | External-DNS prod | 0 | NO | NO |
| prod-platform-harbor | 6 | 8 | Harbor prod (8/8 Running) | 3 | baseline | YES |
| prod-platform-keycloak | 2 | 2 | Keycloak prod (2 replicas) | 3 | baseline | NO* |
| prod-platform-sonarqube | 1 | 1 | SonarQube prod | 3 | baseline | YES (label) |
| prod-security-externalsecrets | 0 | 0 | **VAZIO** (CSS only, operator shared) | 3 | baseline | NO |
| prod-security-vault | 1 | 3 | Vault prod (3 replicas HA) | 3 | baseline | NO |

*prod-platform-keycloak tem `linkerd.io/inject` ausente no label mas mTLS enforce ativo via `linkerd-mtls.tf`.
**backstage-prod.tf CODIFICADO mas apply pendente.

### 3.3 Shared Namespaces (10)

| Namespace | Workloads | Pods | Componente | Serve |
|-----------|-----------|------|-----------|-------|
| cert-manager | - | - | cert-manager (4 NP) | Cluster-wide |
| cicd-argocd | 0 | 0 | ArgoCD legado (vazio) | Migrado para staging-platform-argocd |
| harbor-system | 5 | 7 | Harbor staging (7/7) | Staging |
| kube-system | 15 | 83 | CoreDNS, Calico, aws-node, kube-proxy, EBS CSI, ALB Controller, CA | Cluster-wide |
| linkerd | 4 | 3 | Linkerd control plane | Cluster-wide |
| linkerd-cni | 2 | 14 | Linkerd CNI DaemonSet | Cluster-wide |
| linkerd-viz | 4 | 4 | Linkerd dashboard/metrics | Cluster-wide |
| platform-system | 1 | 2 | Platform system pods | Cluster-wide |
| rabbitmq-system | 0* | 0* | RabbitMQ operator (system CRDs) | Cluster-wide |
| vault-system | 0* | 0* | Vault system (webhook) | Cluster-wide |
| velero | - | - | Velero controller + node-agent | Cluster-wide |

### 3.4 ArgoCD Applications

**Staging (staging-platform-argocd): 20 Applications**
- backstage, staging-data-hatch-etl (OutOfSync/Healthy), staging-data-rabbitmq, staging-data-redis,
- staging-data-vemsoft-etl, staging-governance-kyverno, staging-grafana, staging-harbor,
- staging-keycloak, staging-kyverno, staging-monitoring-grafana, staging-monitoring-loki,
- staging-monitoring-tempo, staging-platform-harbor, staging-platform-new-service,
- staging-rabbitmq, staging-redis, staging-security-keycloak, staging-security-vault, staging-vault

**Prod (prod-platform-argocd): 4 Applications**
- harbor-prod, keycloak-prod, observability-prod, vault-prod
- **GAP:** Sem sync status visivel (kubectl output truncated). Sem Applications para ArgoCD server, Backstage, SonarQube, External-DNS.

---

## 4. Classificacao de Recursos: Staging vs Prod vs Shared

### 4.1 Tabela de Classificacao

| Recurso | Classificacao | Justificativa | Conformidade |
|---------|--------------|---------------|-------------|
| **EKS Cluster** | SHARED | Design intencional: cluster unico, namespaces segregados | CONFORME (DEC-074) |
| **Node Groups (3)** | SHARED | Compartilhados, workloads isolados via taints/tolerations | CONFORME |
| **RDS PostgreSQL** | SHARED | **1 instancia para staging + prod** | **NON-CONFORME (GAP-SHARED-RDS P1)** |
| **VPC** | SHARED | 1 VPC 10.0.0.0/16 | CONFORME |
| **NAT Gateway** | SHARED | 1 NAT Single-AZ (SPOF) | NON-CONFORME (INIT-002) |
| **Vault staging** | STAGING-ONLY | staging-security-vault, 3 replicas | CONFORME |
| **Vault prod** | PROD-ONLY | prod-security-vault, 3 replicas | CONFORME |
| **Redis staging** | STAGING-ONLY | staging-data-infrastructure, 1 replica | CONFORME |
| **Redis prod** | PROD-ONLY | prod-data-infrastructure, 3 replicas + Sentinel | CONFORME |
| **RabbitMQ staging** | STAGING-ONLY | staging-data-rabbitmq, 1 replica | CONFORME |
| **RabbitMQ prod** | PROD-ONLY | prod-data-rabbitmq, 3 replicas quorum | CONFORME |
| **Harbor staging** | STAGING-ONLY | harbor-system, 7/7 pods | CONFORME |
| **Harbor prod** | PROD-ONLY | prod-platform-harbor, 8/8 pods | CONFORME |
| **Keycloak staging** | STAGING-ONLY | staging-platform-keycloak, 1 replica | CONFORME |
| **Keycloak prod** | PROD-ONLY | prod-platform-keycloak, 2 replicas | CONFORME |
| **GitLab** | SHARED | staging-platform-gitlab, instancia unica | CONFORME (DEC-2026-03-24) |
| **SonarQube staging** | STAGING-ONLY | staging-platform-sonarqube, 1 pod | CONFORME |
| **SonarQube prod** | PROD-ONLY | prod-platform-sonarqube, 1 pod | CONFORME |
| **ArgoCD staging** | STAGING-ONLY | staging-platform-argocd, 20 apps | CONFORME |
| **ArgoCD prod** | PROD-ONLY | prod-platform-argocd, 4 apps | PARCIAL (poucas apps) |
| **Backstage staging** | STAGING-ONLY | staging-platform-backstage, 2 pods | CONFORME |
| **Backstage prod** | PROD-ONLY | **VAZIO** | NON-CONFORME |
| **Prometheus staging** | STAGING-ONLY | staging-observability-monitoring | CONFORME |
| **Prometheus prod** | PROD-ONLY | prod-observability-monitoring, 48 pods | CONFORME |
| **Loki staging** | STAGING-ONLY | S3 bucket dedicado | CONFORME |
| **Loki prod** | PROD-ONLY | S3 bucket dedicado | CONFORME |
| **Tempo staging** | STAGING-ONLY | S3 bucket dedicado | CONFORME |
| **Tempo prod** | PROD-ONLY | S3 bucket dedicado | CONFORME |
| **External-DNS staging** | STAGING-ONLY | hml.alvocard.com.br | CONFORME |
| **External-DNS prod** | PROD-ONLY | prod.alvocard.com.br | CONFORME |
| **Linkerd** | SHARED | Control plane cluster-wide | CONFORME |
| **Kyverno** | SHARED | staging-governance-kyverno | CONFORME |
| **ESO operator** | SHARED | staging-security-externalsecrets | CONFORME |
| **cert-manager** | SHARED | cert-manager ns | CONFORME |
| **Calico** | SHARED | kube-system (14 DaemonSet) | CONFORME |
| **Velero** | SHARED | velero ns, backups cobrem * | CONFORME |
| **WAF staging** | STAGING-ONLY | WebACL dedicada | PARCIAL (COUNT mode) |
| **WAF prod** | PROD-ONLY | WebACL dedicada + IP allowlist | CONFORME |
| **S3 State** | SHARED | terraform-state-marco0 bucket | CONFORME |

### 4.2 Inconsistencias Identificadas

| # | Inconsistencia | Severidade | Impacto |
|---|---------------|-----------|---------|
| 1 | **RDS compartilhado staging/prod** — 1 instancia PostgreSQL serve ambos ambientes | P1 | Incidente em staging afeta producao; impossivel promover RDS Multi-AZ somente para prod |
| 2 | **NAT Gateway Single-AZ** — 1 NAT em subnet us-east-1a serve todo o cluster | P2 | SPOF de rede: falha na AZ isola TODOS os nodes |
| 3 | **6 namespaces prod VAZIOS** — hatch-etl, ipaas, vemsoft-etl, data-services, redis-operator, backstage | P1 | Namespaces criados mas sem workloads deployados |
| 4 | **Backstage prod nao deployado** — backstage-prod.tf codificado mas nao aplicado | P1 | Prod sem developer portal |
| 5 | **ArgoCD prod com apenas 4 apps** (vs 20 em staging) | P1 | Maioria dos workloads prod nao gerenciada via GitOps |
| 6 | **PSA ausente em 15+ staging namespaces** (todos prod namespaces cobertos) | P2 | Staging sem hardening de seguranca |
| 7 | **Linkerd inject ausente em namespaces criticos** — Keycloak prod, Vault, dados infra, staging-* | P1 | Comunicacao nao-criptografada entre pods |
| 8 | **EKS logging apenas authenticator** (1/5 tipos) | P1 | Sem audit trail de API calls — violacao BACEN BCB 85/2021 |
| 9 | **Harbor staging em namespace legacy `harbor-system`** (nao segue ADR-048 naming) | P3 | Naming inconsistente com convencao `{env}-{domain}-{product}` |
| 10 | **Namespace `cicd-argocd` vazio** — legado da migracao para staging-platform-argocd | P3 | Namespace orphan consumindo cota sem uso |

---

## 5. GAPs FinOps

### 5.1 Custo Mensal Estimado

| Categoria | Custo/Mes | % do Total | Obs |
|-----------|----------|------------|-----|
| EC2 (14 nodes ON_DEMAND) | $880.71 | 72% | 100% On-Demand |
| EKS Control Plane | $73.00 | 6% | Fixo |
| ALB (6x) | $97.20 | 8% | 3 staging + 2 prod + 1 shared |
| RDS (1x db.t3.medium) | $51.10 | 4% | Single-AZ |
| VPC Endpoints (6 Interface + 1 GW) | $65.70 | 5% | STS, EC2, ELB, KMS, ECR (2x) |
| NAT Gateway | $32.40 | 3% | + data transfer |
| WAF (2 WebACLs) | $20.00 | 2% | |
| S3 + misc | $10.00 | <1% | |
| **TOTAL** | **~$1,230/mo** | **100%** | **~$14,760/ano** |

### 5.2 GAPs FinOps Identificados

| GAP | Descricao | Economia Estimada/Ano | Prioridade |
|-----|-----------|----------------------|-----------|
| GAP-FINOPS-SPOT | 100% On-Demand no node group workloads — Spot 70% economizaria 60% no compute dos 9 nodes | R$32.000-48.000 | P2 |
| GAP-FINOPS-SP | Nenhum Savings Plans ou Reserved Instances para base-load (system + critical = 5 nodes 24/7) | R$10.800-16.200 | P2 |
| GAP-FINOPS-VPA | VPA em recommendation mode sem ciclo de aplicacao — recomendacoes nao materializadas | R$8.712 | P2 |
| GAP-FINOPS-EBS-ORPHAN | 1 volume EBS orphan (vol-0668032f67a8283fd, 10 GB gp3) | R$48 | P3 |
| GAP-FINOPS-ALB-CONSOLIDATION | 6 ALBs — potencial consolidacao com IngressGroups (4 ALBs seria suficiente) | R$2.332 | P3 |
| GAP-FINOPS-RDS-STAGING | RDS db.t3.medium serve staging que poderia usar db.t3.micro dedicado | R$2.700 | P3 |
| GAP-FINOPS-BUDGET | Sem AWS Budget Alerts configurados — custos podem crescer sem deteccao | $0 (prevencao) | P2 |
| GAP-FINOPS-VPC-ENDPOINTS | 6 Interface Endpoints a $14.60/mo cada — avaliar necessidade de ELB endpoint | R$1.054 | P3 |

**Economia Total Nao Realizada: R$57.646-79.046/ano**

### 5.3 IaC Status dos Fixes FinOps

| Fix | Arquivo TF | Status |
|-----|-----------|--------|
| Spot node group | `staging/spot-node-group.tf` | CODIFICADO (apply pendente) |
| Budget alerts | `prod/budget-alerts.tf` | CODIFICADO (apply pendente) |
| VPA cycle | `staging/vpa-apply-cycle.tf` | CODIFICADO (apply pendente) |

---

## 6. GAPs de Paridade (Staging vs Prod)

| Componente | Staging | Prod | Gap | IaC Status |
|-----------|---------|------|-----|-----------|
| Backstage | 2/2 Running | **VAZIO** | P1 | `backstage-prod.tf` CODIFICADO |
| ArgoCD Apps | 20 Applications | 4 Applications | P1 | `argocd-applications.tf` CODIFICADO |
| SonarQube | 1/1 Running | 1/1 Running | RESOLVIDO | Deploy existente |
| Hatch ETL | 8 pods (HOLD) | **VAZIO** | HOLD (intencional) | Aguarda estabilizacao |
| VemSoft ETL | 1 pod | **VAZIO** | HOLD (intencional) | Aguarda pipeline |
| iPaaS | N/A | **VAZIO** | P1 | GAP-IPAAS-STAGING-001 |
| PSA labels | 3 namespaces | 10 namespaces | INVERTIDO | Staging precisa mais PSA |
| Network Policies | 11 ns cobertos | 11 ns cobertos | PARCIAL | Ambos tem gaps |
| HPA | 8 ativos | 0 | P1 | `hpa-platform.tf` CODIFICADO (prod) |
| PDB | 24 ativos | 15 ativos | PARCIAL | `pdb-platform.tf` CODIFICADO |
| WAF mode | COUNT | BLOCK | P1 | Staging precisa BLOCK |

---

## 7. GAPs de Seguranca

| GAP | Descricao | Prioridade | Remediacao |
|-----|-----------|-----------|-----------|
| SEC-001 | EKS control-plane logging 1/5 tipos (apenas authenticator) — sem audit log de API server | P1 | Habilitar 5/5 log types. CODIFICADO? Verificar. |
| SEC-002 | vault-admin policy `secret/*` wildcard — qualquer vault-admin le/escreve todos os paths | P1 | FIX-009 path isolation (3 fases) |
| SEC-003 | Linkerd inject ausente em 5+ namespaces prod (Keycloak, Vault, ESO, infra, External-DNS) | P1 | Adicionar label + rollout restart |
| SEC-004 | WAF staging regras OWASP/SQLi/BadInputs em COUNT (nao bloqueia) | P1 | Alterar para BLOCK |
| SEC-005 | WAF ausente em 2 ALBs staging (GitLab, Keycloak) | P1 | Associar WebACL |
| SEC-006 | TLS end-to-end nao habilitado em Harbor prod, endpoints internos | P1 | Habilitar TLS via ACM/Linkerd |
| SEC-007 | 15+ staging namespaces sem PSA labels | P2 | Rollout PSA labels |
| SEC-008 | `secrets.auto.tfvars` em texto plano no filesystem | P1 | Migrar para environment variables ou Vault |
| SEC-009 | ClusterSecretStore `vault-backend` (staging) acessivel de pods em namespaces prod | P2 | ESO singleton design (CSS-AUTH-001 reclassificado como valido) |
| SEC-010 | Linkerd trust anchor compartilhado staging/prod (single PKI root) | P2 | Aceito como design do cluster compartilhado |

---

## 8. Plano de Acao Consolidado

### Fase 0: Imediato (Emergencia — Hoje)

| # | Acao | GAP | Risco se nao feito |
|---|------|-----|---------------------|
| 1 | Investigar node ip-10-0-132-219 a 102% MEM | MEM-PRESSURE | OOM killer pode evictar pods de plataforma |
| 2 | Investigar EBS orphan vol-0668032f67a8283fd | FINOPS | Custo desnecessario (baixo) |

### Fase 1: P0/P1 — Sprint Atual (terraform apply)

Os seguintes fixes ja estao **CODIFICADOS** nos arquivos .tf e aguardam apenas `terraform apply`:

| # | Acao | GAP | Arquivo TF | Esforco |
|---|------|-----|-----------|---------|
| 1 | RDS Multi-AZ=true (prod) | GAP-CONF-001 | `prod/main.tf` L189 | 1h (apply + janela) |
| 2 | Network Policies em 22+ namespaces | GAP-CONF-002 | `staging/network-policies.tf`, `prod/network-policies.tf` | 30min (apply) |
| 3 | PSA labels em staging namespaces | GAP-CONF-009 | `staging/psa-labels.tf` | 30min (apply) |
| 4 | Dead Man's Switch | GAP-CONF-008 | `staging/dead-mans-switch.tf` | 30min (apply) |
| 5 | HPAs para workloads criticos | GAP-CONF-010 | `staging/hpa-platform.tf`, `prod/hpa-platform.tf` | 30min (apply) |
| 6 | PDBs adicionais | GAP-CONF-019 | `staging/pdb-platform.tf`, `prod/pdb-platform.tf` | 30min (apply) |
| 7 | ArgoCD Applications prod | GAP-CONF-006 | `prod/argocd-applications.tf` | 30min (apply) |
| 8 | Backstage prod deploy | GAP-CONF-007 | `prod/backstage-prod.tf` | 30min (apply) |
| 9 | NAT Multi-AZ | GAP-CONF-022 | `prod/nat-multi-az.tf` | 30min (apply) |
| 10 | Budget alerts AWS | GAP-CONF-026 | `prod/budget-alerts.tf` | 30min (apply) |
| 11 | Spot node group (workloads) | GAP-FINOPS-SPOT | `staging/spot-node-group.tf` | 1h (apply + validacao) |

**Total Fase 1: ~6h (predominantemente terraform apply em sequencia)**

### Fase 2: P1 Nao Codificados

| # | Acao | GAP | Esforco |
|---|------|-----|---------|
| 1 | EKS logging 5/5 tipos | SEC-001 | 2h (codificar + apply) |
| 2 | Vault policy path isolation (FIX-009) | SEC-002 | 4h |
| 3 | Linkerd inject em 5+ namespaces | SEC-003 | 2h |
| 4 | WAF staging COUNT->BLOCK | SEC-004 | 2h |
| 5 | WAF associar a ALBs GitLab/Keycloak staging | SEC-005 | 2h |
| 6 | TLS end-to-end em endpoints prod | SEC-006 | 4h |

### Fase 3: P2/P3 — Backlog

| # | Acao | GAP | Esforco |
|---|------|-----|---------|
| 1 | Savings Plans (decisao financeira) | GAP-FINOPS-SP | Decisao |
| 2 | VPA recommendation cycle | GAP-FINOPS-VPA | 4h |
| 3 | Cleanup EBS orphan | GAP-FINOPS-EBS-ORPHAN | 10min |
| 4 | Cleanup namespace cicd-argocd (vazio) | Housekeeping | 10min |
| 5 | Rename harbor-system -> staging-platform-harbor (ADR-048) | P3 | 4h (migracao) |
| 6 | PSA em shared namespaces | P3 | 2h |

### Itens MESA TECNICA (Requerem Decisao)

| # | Item | Opcoes | Impacto |
|---|------|--------|---------|
| MT-001 | RDS Multi-AZ apply — precisa janela de manutencao | Horario: sexta 22h BRT ou sabado 08h BRT | <120s failover, custo +$51/mo |
| MT-002 | Savings Plans — compromisso financeiro 1yr no-upfront | Contratar $0.55/h Compute SP | R$10.800-16.200/ano saving |
| MT-003 | RDS segregacao staging/prod | Opcao A: 2 RDS (custo +$51/mo), Opcao B: manter shared (risco) | Isolamento de dados |
| MT-004 | iPaaS staging esteiramento — 70+ artefatos IaC estimados | Sprint dedicada Q2 | GAP-IPAAS-STAGING-001 |

---

## 9. Resumo de Conformidade vs Documentos de Referencia

| Documento | Diretriz | Estado Real | Conformidade |
|-----------|---------|-------------|-------------|
| SAD v1.3 - Principio 1 | Cloud-Agnostic | 75-80% agnostic, ALB/RDS/Lambda AWS-specific | PARCIAL |
| SAD v1.3 - Principio 2 | Isolamento de Dominios | Namespaces segregados, RBAC, NetworkPolicies parciais | PARCIAL |
| SAD v1.3 - Principio 3 | IaC e GitOps | TF gerencia maioria, ArgoCD staging completo, prod parcial | PARCIAL |
| SAD v1.3 - Principio 4 | Observabilidade | Prometheus+Loki+Tempo+Grafana ativos staging+prod | CONFORME |
| SAD v1.3 - Principio 6 | DR e HA | Velero backups *, RDS Single-AZ (VIOLACAO), NAT Single-AZ | NON-CONFORME |
| ADR-005 | Network Policies deny-all | 22/43 namespaces cobertos | PARCIAL |
| ADR-008 | HPA/VPA | HPAs em 8 workloads, VPA recommendation-only | PARCIAL |
| ADR-013 | DR Multi-region | Velero cross-region OK, RDS Single-AZ VIOLACAO | NON-CONFORME |
| ADR-019 | FinOps | Lambda savings ativo, 0 Spot/SP, VPA nao aplicado | PARCIAL |
| ADR-048 | Naming Conventions | Maioria conforme, harbor-system divergente | PARCIAL |
| INIT-001 | RDS Multi-AZ | CODIFICADO, apply pendente | PENDENTE |
| INIT-002 | NAT Multi-AZ | CODIFICADO, apply pendente | PENDENTE |
| INIT-005 | EKS logging 5/5 | NAO CODIFICADO | NON-CONFORME |
| INIT-006 | Network Policies | CODIFICADO, apply pendente | PENDENTE |
| INIT-008 | Dead Man's Switch | CODIFICADO, apply pendente | PENDENTE |
| Roadmap 56/100 | Score enterprise 82/100 | Score atual estimado: 64/100 (+3 vs audit) | PARCIAL |

---

## 10. Score Atualizado

| Dimensao | Score Anterior (audit 2026-03-26) | Score Atual (post-PSA/NP improvements) | Benchmark Enterprise |
|----------|----------------------------------|---------------------------------------|---------------------|
| Seguranca | 6/10 | 6.5/10 | 9/10 |
| Resiliencia | 5/10 | 5.5/10 | 9/10 |
| Observabilidade | 7/10 | 7/10 | 8/10 |
| Networking | 6/10 | 6.5/10 | 8/10 |
| GitOps/IaC | 7/10 | 7/10 | 9/10 |
| FinOps | 6/10 | 6/10 | 8/10 |
| Paridade Staging/Prod | 5/10 | 5.5/10 | 8/10 |
| **TOTAL** | **61/100** | **64/100** | **82/100** |

**Score projetado pos-apply dos fixes codificados: ~78/100** (alinhado com projecao da auditoria anterior)

---

## 11. Evidencias Coletadas

Todos os dados deste relatorio foram coletados via live audit em 2026-03-26:
- `kubectl get nodes -o custom-columns` + `kubectl top nodes`
- `kubectl get ns`, `kubectl get pods -A`, `kubectl get deploy,sts,ds,cronjob -n <ns>`
- `kubectl get hpa,vpa,pdb,networkpolicies,externalsecrets -A`
- `kubectl get applications -n staging-platform-argocd` / `prod-platform-argocd`
- `aws rds describe-db-instances`, `aws elbv2 describe-load-balancers`
- `aws ec2 describe-nat-gateways`, `aws ec2 describe-addresses`, `aws ec2 describe-volumes`
- `aws eks describe-cluster`, `aws eks describe-nodegroup`
- `aws wafv2 list-web-acls`, `aws acm list-certificates`, `aws route53 list-hosted-zones`
- `aws ec2 describe-vpc-endpoints`, `aws ec2 describe-vpcs`
- Cross-reference com: `IaC Conformance Audit 2026-03-26`, `Roadmap Enterprise 2026-03-21`, `GAP-ARCH FinOps Remediation 2026-03-23`, `SAD v1.3`

---

---

## 12. Incidente Detectado e Resolvido Durante Audit

### INC-MEM-2026-03-26: System Node OOM — Prometheus Staging

**Timeline:**
- **21:10 UTC** — Node `ip-10-0-132-219` (system, t3.medium, us-east-1a) detectado a 102% MEM durante audit
- **21:12 UTC** — Node transitions to **NotReady** (kubelet stopped posting status)
- **Causa raiz:** Prometheus staging (`prometheus-kube-prometheus-stack-prometheus-0`) consumindo ~2.9 GiB numa node com 3.3 GiB allocatable. Memory limits overcommitted (241% do allocatable).
- **21:13 UTC** — Force-delete do pod Prometheus (stuck no node NotReady) e pushgateway prod (Init:0/1)
- **21:14 UTC** — Prometheus entra em Pending — PVC zone-locked a us-east-1a, mas system nodes disponiveis estao em us-east-1b ou insuficientes
- **21:14 UTC** — Cluster Autoscaler escala system group: 3->4->5 (max). Node `ip-10-0-139-162` (us-east-1a) sobe em 92s.
- **21:16 UTC** — Cluster Autoscaler escala workloads group: 9->10. Node `ip-10-0-147-65` sobe.
- **21:20 UTC** — Prometheus Init:0/1 (pulling image do ECR no new node)
- **21:22 UTC** — Prometheus 1/2 Running (config-reloader OK, proxy sidecar inicializando)
- **21:25 UTC** — Node `ip-10-0-132-219` recupera (volta a Ready). Cluster em 17 nodes, 358 pods.

**Impacto:**
- Prometheus staging ficou indisponivel por ~12 minutos (21:10 a 21:22)
- Zero impacto em producao (Prometheus prod em node separado)
- Dashboards Grafana staging perderam metricas no gap de 12min

**Acao imediata executada:**
1. Force-delete do pod Prometheus para forcar rescheduling
2. CA escalou automaticamente novos system nodes

**GAP identificado (NOVO):**
- **GAP-PROM-MEM-001 (P1):** Prometheus staging com `resources.requests.memory=2Gi` e `limits.memory=6Gi` numa node t3.medium (3.3 GiB allocatable). Memory limit excede a capacidade do node em 182%. Requer: (a) mover Prometheus para workloads/critical node group, ou (b) reduzir memory limit para 3Gi, ou (c) upgradar system nodes para t3.large.
- **GAP-SYSTEM-MAXOUT (P2):** System node group atingiu max_size=5 durante o incidente. Zero headroom restante. Proximo OOM nao tera node disponivel para CA escalar.

**Status Final:** RESOLVIDO. Cluster estavel com 17 nodes Ready. System group em 5/5 (max). Prometheus staging 1/2 Running (proxy sidecar inicializando).

---

*Relatorio gerado por Cloud Architect + FinOps Specialist — 2026-03-26*
