# AWS EKS Quickstart — Implementação Real (Staging)

**Última Atualização:** 2026-03-04
**Versão:** 4.0 (Estado Real Auditado — pós Marco 4 + CI/CD Enhancement + INFRA upgrades)
**Status:** Staging Operacional | Production: Projeção documentada

---

## Executive Summary

| Métrica                    | Planejado (Quickstart v1) | Staging Real (2026-03-04)           | Status     |
| -------------------------- | ------------------------- | ----------------------------------- | ---------- |
| **Timeline Staging**       | 33 dias                   | **14 dias** (Marco 0-3)             | -57%       |
| **EKS Version**            | 1.28–1.30                 | **1.34 Standard**                   | ✅          |
| **GitLab Version**         | 17.x                      | **18.9.1** (chart 9.9.1)            | ✅ Upgraded |
| **PostgreSQL**             | 14.x                      | **16.4** (RDS INFRA-002)            | ✅ Upgraded |
| **Nodes**                  | 6–8                       | **7–8** (FinOps auto-scale)         | ✅          |
| **Custo Mensal (bruto)**   | ~$438                     | **~$835**                           | Otimizado  |
| **Custo Líquido (FinOps)** | —                         | **~$716** (~R$ 3.601/mês)           | -14%       |
| **Enterprise Maturity**    | —                         | **4.0/5.0** (85% prod-ready)        | Advanced+  |
| **Marco Atual**            | Marco 3                   | **Marco 4 ✅ 100% + Marco 5 início** | On track   |

---

## Segregação: Staging vs Production

```
┌───────────────────────────────────────────────────────────────────────┐
│  STAGING (Atual)                        PRODUCTION (Projeção)        │
│  ─────────────────                      ──────────────────────        │
│  k8s-platform-prod [naming histórico]   k8s-platform-production      │
│  EKS 1.34 · Single-AZ · 7-8 nodes      EKS 1.34+ · Multi-AZ · 12+ nodes │
│  FinOps: auto-shutdown 70% do tempo     24/7 SLA 99.9%               │
│  Custo: ~$716/mês líquido               Custo projetado: ~$2.500-3.500/mês │
│  Status: ✅ OPERACIONAL                 Status: ⏳ AGUARDANDO GATES  │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 1. STAGING — Estado Real (2026-03-04)

### 1.1 Infraestrutura Base

```yaml
VPC:              vpc-0b1396a59c417c1f0 (10.0.0.0/16, us-east-1a + us-east-1b)
EKS Cluster:      k8s-platform-prod (naming histórico — staging)
EKS Version:      1.34 Standard Support — $73/mês
Platform:         eks.18
AMI:              AL2023_x86_64_STANDARD
Created:          2026-01-28
```

### 1.2 Compute Layer

| Node Group    | Tipo      | Atual | Min | Max | Disco     | Labels              | Taints                       |
| ------------- | --------- | ----- | --- | --- | --------- | ------------------- | ---------------------------- |
| **system**    | t3.medium | 2–3   | 2   | 4   | 30GB gp3  | node-type=system    | —                            |
| **workloads** | t3.large  | 2–4   | 2   | 7   | 50GB gp3  | node-type=workloads | —                            |
| **critical**  | t3.xlarge | 2     | 2   | 4   | 100GB gp3 | node-type=critical  | workload=critical:NoSchedule |

> **FinOps**: EventBridge auto-stop às 20:00 BRT (Seg–Sex) + stop sábado 00:00 BRT. Custo diário estabilizado em ~$13/dia (-73% vs semana 1).

### 1.3 EKS Managed Addons

| Addon              | Versão             | Status                          |
| ------------------ | ------------------ | ------------------------------- |
| aws-ebs-csi-driver | v1.37.0-eksbuild.1 | ACTIVE                          |
| coredns            | v1.11.3-eksbuild.2 | ACTIVE                          |
| kube-proxy         | v1.31.2-eksbuild.3 | ACTIVE ⚠️ drift (deveria 1.34.x) |
| vpc-cni            | v1.18.5-eksbuild.1 | ACTIVE                          |

### 1.4 Storage Layer

```yaml
RDS PostgreSQL:
  Instance:      k8s-platform-staging-postgresql
  Engine:        PostgreSQL 16.4 (INFRA-002 — upgraded 2026-03-03)
  Class:         db.t3.medium (2 vCPU, 4 GB RAM)
  Storage:       100 GB gp3 (auto-scaling 500 GB)
  Multi-AZ:      false (staging — aceitável)
  Backup:        7 dias retention
  Encrypted:     true
  Status:        available
  Deletion Prot: false (staging)

EBS Volumes:     ~14 volumes / 555 GB (97% gp3)

S3 Buckets (13):
  Platform:
    - terraform-state-marco0-891377105802
    - k8s-platform-gitlab-artifacts-891377105802
    - k8s-platform-harbor-images-891377105802
    - k8s-platform-prod-vault-snapshots-891377105802
    - k8s-platform-loki-891377105802
    - k8s-platform-tempo-891377105802
    - aws-waf-logs-k8s-platform-prod-staging (GAP-010)
  DR (GAP-012 Phase 1):
    - velero-backups-staging-891377105802-us-east-1 (primary)
    - velero-backups-staging-891377105802-us-west-2 (replica — S3 CRR 15-min RTC)
  Legacy (fora escopo): fct-0001, fct-0002, fct-0003, fct-public, ref-0005
```

### 1.5 Networking Layer

```yaml
NAT Gateways:    2 (us-east-1a, us-east-1b)

VPC Endpoints (5):
  Interface:
    - STS  (vpce-0c3a…) — IRSA/Pod Identity
    - EC2  (vpce-0b52…) — Node management
    - ELB  (vpce-01ac…) — ALB Controller TLS
    - KMS  (vpce-0ea3…) — Vault auto-unseal (ADR-055)
  Gateway:
    - S3   (vpce-0a7e…) — zero custo, Vault snapshots + Harbor

Load Balancers (8):
  ALB (6):
    - k8s-gitlabst-gitlabwe   (GitLab Webservice — staging-platform-gitlab)
    - k8s-gitlabst-gitlabre   (GitLab Registry)
    - k8s-gitlabst-gitlabka   (GitLab KAS)
    - k8s-platformstaging      (ArgoCD, Keycloak, SonarQube, Vault, Harbor)
    - k8s-observabilitystaging (Grafana)
    - k8s-datastaging           (RabbitMQ Management)
  NLB (2):
    - k8s-dataserv-rabbitmq   (RabbitMQ AMQP)
    - k8s-default-rabbitmq    (cleanup candidato)

AWS WAF v2 (GAP-010):
  WebACL:        bb9d4557-ca28-4539-b493-b62b2f0d602c
  WCUs:          1,103 (5 managed rules)
  ALB:           k8s-platformstaging-00e0ecf3b4
  Rules:         Rate Limit + Geo Block + OWASP + SQLi + Bad Inputs
  Logging:       S3 aws-waf-logs-* (90 dias retention)
```

### 1.6 Namespaces (DEC-074 — 100% Migrado 2026-02-25)

Padrão: `{env}-{domain}-{product}` — 17 namespaces migrados, enforcement Kyverno ativo.

| Namespace                        | Domínio       | Componente                          |
| -------------------------------- | ------------- | ----------------------------------- |
| staging-platform-gitlab          | platform      | GitLab v18.9.1                      |
| staging-platform-argocd          | platform      | ArgoCD v2.10.0                      |
| staging-platform-keycloak        | platform      | Keycloak 26.5.1                     |
| staging-platform-sonarqube       | platform      | SonarQube 10.3.0                    |
| staging-platform-harbor          | platform      | Harbor 2.10.0                       |
| staging-security-vault           | security      | Vault 1.15.0 HA                     |
| staging-security-externalsecrets | security      | ESO 0.12.1                          |
| staging-security-cert-manager    | security      | cert-manager                        |
| staging-data-infrastructure      | data          | PostgreSQL clients, Redis, RabbitMQ |
| staging-data-redis-operator      | data          | OT-Container-Kit operator           |
| staging-data-rabbitmq            | data          | RabbitMQ Operator                   |
| staging-observability-monitoring | observability | Prometheus, Grafana, Loki, Tempo    |
| staging-governance-kyverno       | governance    | Kyverno 3.x HA                      |
| staging-governance-test          | governance    | test                                |
| staging-observability-otel-test  | observability | OpenTelemetry test                  |
| staging-platform-argocd-test     | platform      | ArgoCD test                         |
| linkerd                          | service-mesh  | Linkerd control plane               |

---

## 2. COMPONENTES DEPLOYADOS — Status Completo

### 2.1 Infraestrutura Platform (Marcos 0–3) ✅

| Componente                   | Status        | Versão       | Namespace                   | Notas                           |
| ---------------------------- | ------------- | ------------ | --------------------------- | ------------------------------- |
| AWS VPC                      | ✅ Operacional | —            | —                           | 10.0.0.0/16, 2 AZs              |
| EKS Cluster                  | ✅ Operacional | 1.34         | kube-system                 | 3 node groups, Standard Support |
| EBS CSI Driver               | ✅ Operacional | v1.37.0      | kube-system                 | PVCs gp3                        |
| AWS Load Balancer Controller | ✅ Operacional | 2.7.0        | kube-system                 | IngressGroup (4 ALBs)           |
| Cluster Autoscaler           | ✅ Operacional | 1.28.x       | kube-system                 | ASG tags corretas (owned)       |
| Metrics Server               | ✅ Operacional | 0.6.4        | kube-system                 | HPA support                     |
| CoreDNS                      | ✅ Operacional | v1.11.3      | kube-system                 | Rewrite rules ativas            |
| PostgreSQL RDS               | ✅ Operacional | **16.4**     | —                           | INFRA-002 ✅ Single-AZ staging   |
| Redis Standalone             | ✅ Operacional | OT-Kit v0.23 | staging-data-infrastructure | AUTH, PSS restricted            |
| RabbitMQ                     | ✅ Operacional | Operator     | staging-data-rabbitmq       | Official operator               |

### 2.2 CI/CD Platform (Marco 4) ✅ 100%

| Componente | Status        | Versão                   | Namespace                  | Notas                                                                    |
| ---------- | ------------- | ------------------------ | -------------------------- | ------------------------------------------------------------------------ |
| **GitLab** | ✅ Operacional | **18.9.1** (chart 9.9.1) | staging-platform-gitlab    | INFRA-001 ✅ 9 breaking changes resolvidos. Rev 36. Runner id=115 online. |
| ArgoCD     | ✅ Operacional | v2.10.0 (PKCE)           | staging-platform-argocd    | GitOps ativo, ApplicationSets 7 apps                                     |
| SonarQube  | ✅ Operacional | 10.3.0-community         | staging-platform-sonarqube | Quality Gate "Production" ativo default                                  |
| Keycloak   | ✅ Operacional | 26.5.1 (Quarkus)         | staging-platform-keycloak  | OIDC: 6 clients (gitlab/argocd/sonar/grafana/harbor/vault)               |
| Harbor     | ✅ Operacional | 2.10.0                   | harbor-system              | S3 IRSA, imutabilidade tags ativa                                        |

### 2.3 Security & Governance ✅

| Componente                | Status        | Versão | Notas                                                                    |
| ------------------------- | ------------- | ------ | ------------------------------------------------------------------------ |
| Vault HA                  | ✅ Operacional | 1.15.0 | 3 replicas, KMS auto-unseal, OIDC SSO ativo                              |
| External Secrets Operator | ✅ Operacional | 0.12.1 | 16/16 ExternalSecrets SecretSynced (staging-security-externalsecrets)    |
| Kyverno                   | ✅ **ENFORCE** | 3.x HA | 80/80 PASS (100% compliance). 3 políticas enforce + 2 audit              |
| **Linkerd Service Mesh**  | ✅ Operacional | 2.16.x | **GAP-011** ✅. 7/7 pods Running. mTLS automático. 4 dashboards Grafana.  |
| Network Policies          | ✅ Operacional | K8s    | 22 policies em 5 namespaces (argocd, keycloak, sonarqube, gitlab, vault) |
| cert-manager              | ✅ Operacional | —      | staging-security-cert-manager                                            |
| AWS WAF v2                | ✅ Operacional | —      | **GAP-010** ✅. WebACL bb9d4557. 5 regras gerenciadas. S3 logging.        |
| 8/8 Vulnerabilidades      | ✅ Remediadas  | —      | V-001 a V-008 todos RESOLVIDOS (2026-02-25)                              |

### 2.4 Observabilidade ✅

| Componente                 | Status        | Versão | Namespace                        | Notas                                        |
| -------------------------- | ------------- | ------ | -------------------------------- | -------------------------------------------- |
| Prometheus                 | ✅ Operacional | 2.48.0 | staging-observability-monitoring | 88 targets, 34 alertas PrometheusRule ativos |
| Grafana                    | ✅ Operacional | 10.2.0 | staging-observability-monitoring | Dashboards: platform + WAF + Linkerd + DR    |
| Loki                       | ✅ Operacional | 3.6.5  | staging-observability-monitoring | 18 pods SimpleScalable, Kyverno 100%         |
| Tempo                      | ✅ Operacional | 2.9.0  | staging-observability-monitoring | Loki→Tempo correlation ativo                 |
| Alertmanager               | ✅ Operacional | —      | staging-observability-monitoring | 4 canais Slack (webhooks placeholders)       |
| OpenTelemetry Collector    | ✅ Operacional | —      | staging-observability-monitoring | Gateway, 2 replicas, HPA 2–5                 |
| CloudWatch Exporter (YACE) | ⏳ Pendente    | —      | —                                | Necessário para métricas WAF/RDS no Grafana  |

### 2.5 Backup & DR ✅ Phase 1

| Componente          | Status             | Notas                                                              |
| ------------------- | ------------------ | ------------------------------------------------------------------ |
| Velero              | ✅ Operacional      | Single-region backup (us-east-1), pod Running 18h+                 |
| Velero DR S3 CRR    | ✅ Phase 1 Deployed | **GAP-012** ✅. S3 CRR us-east-1→us-west-2 (15-min RTC SLA)         |
| Velero Backup Sched | ✅ Configurado      | Daily full (02:00 UTC, 7d) + Weekly (30d) — S3 Intelligent-Tiering |
| RDS DR Replica      | ⏳ Gate pendente    | Phase 2 — aguarda VPC us-west-2                                    |
| Snapshot DLM        | ✅ Operacional      | 3 policies ENABLED, R$ 5.052/ano savings                           |
| IRSA Velero         | ✅ Migrado          | V-008 ✅ zero static credentials                                    |

### 2.6 CI/CD Enhancement ✅ 5/5

| Item                           | Status      | Deploy     | Notas                                                       |
| ------------------------------ | ----------- | ---------- | ----------------------------------------------------------- |
| CICD-001: SAST/DAST Enforce    | ✅ 100%      | 2026-03-03 | SonarQube QG + Harbor Trivy ENFORCING (HIGH+CRITICAL block) |
| CICD-002: Quality Gate         | ✅ 100%      | 2026-03-02 | Gate "Production" default — Coverage ≥80%, Bugs=0, Vuln=0   |
| CICD-003: Secret Rotation      | ✅ Deployado | 2026-02-26 | CronJob quarterly rotation (PostreSQL + Keycloak + OIDC)    |
| CICD-004: Immutable Image Tags | ✅ Deployado | 2026-03-02 | 12 immutability rules em 3 projetos Harbor                  |
| CICD-005: Argo Rollouts        | ✅ Deployado | 2026-02-26 | Canary + Blue-Green, 4 AnalysisTemplates, 2 dashboards      |

---

## 3. FINOPS — Custos Reais (Staging)

### 3.1 Custo Mensal Estimado (referência AWS Cost Explorer Fev/2026)

| Categoria                     | Custo Bruto/mês | Com FinOps          | % do Total |
| ----------------------------- | --------------- | ------------------- | ---------- |
| Amazon EKS (Control Plane)    | $245            | $245 (sempre ativo) | 34%        |
| Amazon EC2 Compute (Nodes)    | $236            | ~$94 (70% off-time) | 13%        |
| EC2 Other (EBS, NAT, IPs)     | $117            | $117                | 16%        |
| Amazon ELB (6 ALBs + 2 NLBs)  | $76             | $76                 | 11%        |
| Amazon VPC (Endpoints + NAT)  | $73             | $73                 | 10%        |
| Amazon RDS PostgreSQL         | $28             | ~$11 (60% off-time) | 2%         |
| Amazon CloudWatch             | $26             | $26                 | 4%         |
| AWS WAF v2 (GAP-010)          | ~$10            | $10                 | 1%         |
| Outros (KMS, S3, SM, ECR, DR) | ~$24            | $24                 | 3%         |
| **SUBTOTAL**                  | **~$835**       | **~$676**           |            |
| Tax (~13.5%)                  | ~$113           | ~$91                |            |
| **TOTAL**                     | **~$948**       | **~$767/mês**       |            |

> **FinOps Automação**: Lambda start/stop + EventBridge. Economia observada: $177/mês (-21%). Custo diário estabilizado: ~$13/dia (vs ~$50/dia semana 1 = -73%).

### 3.2 Savings Realizados

| Item                             | Economia Anual    |
| -------------------------------- | ----------------- |
| FinOps auto-shutdown             | R$ 10.692/ano     |
| Sprint 2 (ALBs + EBS gp2→gp3)    | R$ 8.208/ano      |
| Sprint 3 (VPC Endpoints KMS)     | R$ 6.240/ano      |
| Snapshot DLM (ADR-087)           | R$ 5.052/ano      |
| PDB Optimization (FinOps CA)     | R$ 4.405/ano      |
| KMS Standard Support (-$305/mês) | R$ 18.432/ano     |
| Outros (Spot prep, gp3, PDB)     | R$ 9.396/ano      |
| **TOTAL REALIZADO**              | **R$ 62.425/ano** |

---

## 4. TERRAFORM — Estado de Conformidade

### 4.1 Gaps Resolvidos Since v3.0

| #   | Gap                     | Estado v3.0 (2026-02-12) | Estado Atual (2026-03-04)              |
| --- | ----------------------- | ------------------------ | -------------------------------------- |
| T1  | EKS version no módulo   | default="1.28"           | ✅ Atualizado 1.34                      |
| T2  | Node groups no módulo   | 1 grupo "observability"  | ✅ 3 grupos (system/workloads/critical) |
| T4  | VPC Endpoints STS + EC2 | ausentes                 | ✅ 5 VPC Endpoints (ADR-055)            |
| T5  | Orphan Security Groups  | 10 SGs órfãos            | ✅ Cleanup completo (2026-02-13)        |
| T6  | NLB RabbitMQ default NS | nao declarado            | ✅ Cleanup ou importado                 |

### 4.2 Gaps Ativos / Atenção

| #   | Gap                           | Estado Atual                | Ação                            |
| --- | ----------------------------- | --------------------------- | ------------------------------- |
| T3  | kube-proxy addon v1.31.2      | drift: deveria ser v1.34.x  | `aws_eks_addon` upgrade         |
| T7  | Redis/RabbitMQ gp2→gp3        | 3 PVCs gp2 (15 GB)          | Migrar para gp3                 |
| T9  | Terraform state drift parcial | Helm releases fora do state | `terraform import` seletivo     |
| T10 | CloudWatch Exporter YACE      | Não deployado               | Necessário para WAF/RDS metrics |

---

## 5. MARCOS — Status Atual

```
Marco 0: Baseline Terraform + State S3            ✅ 100%  (2026-01-28)
Marco 1: EKS Base Infrastructure                  ✅ 100%  (2026-01-30)
Marco 2: Platform Services (Observability)        ✅ 100%  (2026-02-03)
Marco 3: Workloads (GitLab + Data Services)       ✅ 100%  (2026-02-09)
Marco 4: CI/CD Platform (8/8 GAPs)               ✅ 100%  (2026-02-25)
  ├─ GAP-001: Keycloak SSO                       ✅ DEPLOYED
  ├─ GAP-002: GitLab Components Fix              ✅ DEPLOYED
  ├─ GAP-003: ArgoCD GitOps v2.10.0             ✅ DEPLOYED
  ├─ GAP-004: SonarQube Quality                 ✅ DEPLOYED
  ├─ GAP-005: GitLab CI/CD Integration          ✅ DEPLOYED
  ├─ GAP-006: ApplicationSets                   ✅ DEPLOYED (7 apps auto-gerados)
  ├─ GAP-007: Network Policies (22 policies)    ✅ DEPLOYED
  └─ GAP-008: SonarQube Monitoring              ✅ DEPLOYED (endpoint nativo)
Marco 4+: CI/CD Enhancement (5/5)                ✅ 100%  (2026-03-03)
Marco 4+: Security Remediation (8/8 vulns)       ✅ 100%  (2026-02-25)
Marco 4+: Debt Sprint (5/5 DT items)             ✅ 100%  (2026-02-25)
Marco 4+: Namespace Migration DEC-074 (17/17)    ✅ 100%  (2026-02-25)
Marco 4+: iPaaS Public Readiness (3/3 GAPs)      ✅ 100%  (2026-03-03)
  ├─ GAP-010: AWS WAF + DDoS Protection         ✅ DEPLOYED
  ├─ GAP-011: Linkerd Service Mesh mTLS         ✅ DEPLOYED (7/7 pods)
  └─ GAP-012: DR Multi-Region (Phase 1)         ✅ DEPLOYED (S3 CRR)
INFRA Upgrades                                   ✅ 100%  (2026-03-03)
  ├─ INFRA-001: GitLab v17.7 → v18.9.1         ✅ COMPLETO (9 steps, 9 breaking changes)
  └─ INFRA-002: PostgreSQL 14.8 → 16.4         ✅ COMPLETO
Marco 5: Production Readiness                    🚧 10%  (planejamento início)
Marco 6: Multi-Cluster Production                ⏸️  0%
```

---

## 6. PROJEÇÃO PRODUCTION

### 6.1 Pré-requisitos (Gating Criteria)

Antes de provisionar produção, os seguintes gates devem ser validados:

| Gate                         | Status                             | Critério                             |
| ---------------------------- | ---------------------------------- | ------------------------------------ |
| Staging estável 3+ meses     | 🟡 Em contagem (início: 2026-01-28) | Zero downtime não planejado          |
| DR drill validado            | ⏳ Pendente                         | Velero restore + RTO < 1h medido     |
| Kyverno 100% enforce         | ✅ 2026-03-02                       | 3 políticas enforce ativas           |
| Linkerd estável 2+ meses     | 🟡 Início: 2026-03-03               | Zero issues por 60 dias              |
| SAST/DAST Pipeline enforcing | ✅ 2026-03-03                       | Harbor Trivy + SonarQube QG blocking |
| Terraform IaC 100%           | 🟡 ~95%                             | Zero drift em plan                   |
| CloudWatch Exporter Deploy   | ⏳ Pendente                         | WAF + RDS metrics no Grafana         |
| VPC us-west-2 provisionada   | ⏳ Pendente                         | Desbloqueador GAP-012 Phase 2        |

### 6.2 Arquitetura Produção Planejada

```
┌─────────────────────────────────────────────────────────────────────┐
│  EKS Cluster PRODUCTION (us-east-1 + us-east-2 Multi-AZ)           │
│                                                                      │
│  Node Groups:                                                        │
│    system:    t3.large     × 3 (Multi-AZ)                           │
│    workloads: t3.xlarge    × 4–8 (Auto-scale, possível Spot)        │
│    critical:  t3.2xlarge   × 3 (HA crítico)                         │
│                                                                      │
│  RDS PostgreSQL:    db.t3.medium, Multi-AZ=true, deletion_prot=true │
│  Redis:             HA Sentinel 3+ nodes                            │
│  RabbitMQ:          Cluster 3 nodes                                 │
│                                                                      │
│  AlL Helm releases: 2 réplicas mínimo (HA)                         │
│  GitLab:            HA (webservice×3, sidekiq×2, shell×2)          │
│  Keycloak:          2 réplicas (já parametrizado no TF)             │
│  Vault:             3 réplicas HA (igual staging)                   │
│  ArgoCD:            2 réplicas (igual staging)                      │
│                                                                      │
│  WAF:               Mesma configuração staging + fine-tuned         │
│  Linkerd:           HA mode (3 replicas control plane)              │
│  Velero DR:         Phase 2 ativa (RDS cross-region replica)        │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.3 Custo Projetado Production (24/7)

| Categoria                 | Prod Estimado/mês      |
| ------------------------- | ---------------------- |
| EKS Control Plane         | $245                   |
| EC2 (12–15 nodes, 24/7)   | $900–$1.200            |
| RDS Multi-AZ db.t3.medium | $56                    |
| ELB (4–6 ALBs)            | $76                    |
| VPC + Endpoints           | $120                   |
| S3 + EBS + KMS            | $100                   |
| DR (S3 CRR + RDS replica) | $80                    |
| WAF + CloudWatch          | $30                    |
| **TOTAL ESTIMADO**        | **~$1.607–$1.907/mês** |

> Nota: Savings Plans 1yr podem reduzir -30% nos EC2 (~R$ 6.984/ano ROI 2.340%).

### 6.4 Plano de Execução para Production

**Fase preparatória (Marco 5)**:
1. Provisionar VPC us-west-2 (desbloqueador DR Phase 2)
2. Executar primeiro DR drill completo (Velero restore + RTO medido)
3. Deployar CloudWatch Exporter (YACE) — métricas WAF/RDS no Grafana
4. Corrigir drift kube-proxy (addon upgrade v1.34.x)
5. Entra ID Federation INFRA-003 (ADR-095/096/097) — identidade corporativa

**Fase provisioning (Marco 6)**:
1. Novo cluster EKS `k8s-platform-production` via Terraform `environments/prod/`
2. `deletion_protection = true` no RDS (já parametrizado — DT-004)
3. `multi_az = true` no RDS (já parametrizado — DT-004)
4. Velero Phase 2: `dr_enable_rds_replica = true`
5. Kyverno, Linkerd, WAF migrados 1:1 do staging (IaC reutilizável)
6. GitLab ApplicationSets promovem apps staging → prod via ArgoCD multi-cluster

---

## 7. DÍVIDA TÉCNICA PENDENTE

| Item                                 | Severidade | Estado Atual             | Ação Próxima                       |
| ------------------------------------ | ---------- | ------------------------ | ---------------------------------- |
| kube-proxy drift (v1.31.2 ≠ v1.34.x) | MEDIUM     | Ativo                    | `aws_eks_addon` TF resource        |
| Redis/RabbitMQ gp2→gp3 (15 GB)       | LOW        | Ativo                    | PVC migration (janela manutenção)  |
| Slack webhooks reais (Alertmanager)  | MEDIUM     | Placeholders             | Configurar #alerts-* 4 canais      |
| E2E pipeline validation (GAP-005)    | MEDIUM     | Pendente                 | First real pipeline job no browser |
| V-010: Velero restore testing        | LOW        | Pendente                 | Namespace isolado `dr-test`        |
| CloudWatch Exporter YACE             | MEDIUM     | Não deployado            | metrics WAF + RDS → Grafana        |
| Terraform import drift parcial       | LOW        | Helm releases fora state | `terraform import` seletivo        |

---

## 8. ACESSO LOCAL — DNS /etc/hosts

```
# GitLab Services (ALB: gitlab-staging group)
<GITLAB_ALB_IP>    gitlab.staging.internal
<GITLAB_ALB_IP>    registry.staging.internal
<GITLAB_ALB_IP>    kas.staging.internal

# Platform Services (ALB: platform-staging group)
<PLATFORM_ALB_IP>  argocd.staging.internal
<PLATFORM_ALB_IP>  keycloak.staging.internal
<PLATFORM_ALB_IP>  sonarqube.staging.internal
<PLATFORM_ALB_IP>  vault.staging.internal
<PLATFORM_ALB_IP>  harbor.staging.internal

# Observability (ALB: observability-staging group)
<OBS_ALB_IP>       grafana.staging.internal

# Data Services
<DATA_ALB_IP>      rabbitmq.staging.internal
```

---

## 9. REFERÊNCIAS

- [current_state.md](../../context/current_state.md) — Estado técnico detalhado (componentes + versões)
- [demands-backlog.md](../../demands-backlog.md) — Backlog de demandas e GAPs
- [evolution-strategy.md](evolution-strategy.md) — Roadmap de fases (cloud-agnóstico)
- [CHANGELOG.md](CHANGELOG.md) — Histórico de versões do quickstart
- [ADR-086](../../adr/adr-086-linkerd-service-mesh-mtls.md) — Service Mesh mTLS
- [ADR-090](../../adr/adr-090-dr-multi-region-strategy.md) — DR Multi-Region
- [ADR-092](../../adr/adr-092-gitlab-version-upgrade-strategy.md) — GitLab upgrade strategy
- [ADR-093](../../adr/adr-093-rds-postgresql-14-to-16-upgrade.md) — PostgreSQL 14→16
- [ADR-099](../../adr/adr-099-waf-strategy-ipaas-public.md) — WAF Strategy

---

**Mantenedor:** DevOps Team (AI-assisted)
**Última Revisão:** 2026-03-04
**Próxima Revisão:** Ao iniciar Marco 5 ou provisionamento de produção
