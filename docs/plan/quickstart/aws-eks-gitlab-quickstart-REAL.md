# AWS EKS Quickstart — Implementacao Real (Staging)

**Ultima Atualizacao:** 2026-02-12
**Versao:** 3.0 (Dados Reais AWS CLI — reconciliacao pos-upgrade v1.34)
**Status:** Quickstart MVP Staging — Operacional

---

## Executive Summary

| Metrica            | Planejado | Real (2026-02-12)                           | Status            |
| ------------------ | --------- | ------------------------------------------- | ----------------- |
| **Timeline**       | 33 dias   | **14 dias**                                 | -57%              |
| **EKS Version**    | 1.28-1.30 | **1.34 Standard**                           | Atualizado        |
| **Nodes**          | 6-8       | **8** (system:2 + workloads:4 + critical:2) | Otimizado         |
| **Load Balancers** | 3-4       | **6**                                       | Aceitavel         |
| **Custo Mensal**   | ~$438     | **~$835**                                   | Otimizado vs v2.0 |

---

## Inventario AWS Real (Validado 2026-02-12)

### Infraestrutura Base

```yaml
VPC:              vpc-0b1396a59c417c1f0 (10.0.0.0/16, 2 AZs)
EKS Cluster:      k8s-platform-prod
EKS Version:      1.34 (Standard Support — $73/mes)
Platform:         eks.18
AMI:              AL2023_x86_64_STANDARD
Created:          2026-01-28
```

### Compute Layer (8 Nodes EKS)

| Node Group    | Type      | Desired | Min | Max | Disk      | Labels              | Taints                       |
| ------------- | --------- | ------- | --- | --- | --------- | ------------------- | ---------------------------- |
| **system**    | t3.medium | 2       | 2   | 4   | 30GB gp3  | node-type=system    | —                            |
| **workloads** | t3.large  | 4       | 2   | 7   | 50GB gp3  | node-type=workloads | —                            |
| **critical**  | t3.xlarge | 2       | 2   | 4   | 100GB gp3 | node-type=critical  | workload=critical:NoSchedule |

**Non-EKS:** 1x t3.micro (fictor-tools) — fora do escopo

### EKS Managed Addons

| Addon              | Versao             | Status                                 |
| ------------------ | ------------------ | -------------------------------------- |
| aws-ebs-csi-driver | v1.37.0-eksbuild.1 | ACTIVE                                 |
| coredns            | v1.11.3-eksbuild.2 | ACTIVE                                 |
| kube-proxy         | v1.31.2-eksbuild.3 | ACTIVE — **drift: deveria ser 1.34.x** |
| vpc-cni            | v1.18.5-eksbuild.1 | ACTIVE                                 |

### Storage Layer

```yaml
RDS PostgreSQL:
  Instance:         k8s-platform-prod-postgresql
  Class:            db.t3.medium (2vCPU, 4GB RAM)
  Engine:           PostgreSQL 16.4
  Storage:          100GB gp3 (max 500GB auto-scaling)
  Multi-AZ:         False (staging)
  Backup:           7 dias retention
  Encrypted:        True
  Status:           available

EBS Volumes:
  Total:            14 volumes / 555 GB
  gp3:              11 volumes (540 GB) — 97% do storage
  gp2:              3 volumes (15 GB) — Redis/RabbitMQ PVCs

S3 Buckets (11):
  Platform:
    - terraform-state-marco0-891377105802
    - k8s-platform-gitlab-artifacts-891377105802
    - k8s-platform-harbor-images-891377105802
    - k8s-platform-prod-vault-snapshots-891377105802
    - k8s-platform-loki-891377105802
    - k8s-platform-tempo-891377105802
  Legacy (fora do escopo):
    - fct-0001, fct-0002, fct-0003, fct-public, ref-0005
```

### Networking Layer

```yaml
NAT Gateways:       2 (us-east-1a, us-east-1b)

VPC Endpoints (5):
  Interface:
    - STS           (vpce-0c3a...) — IRSA/Pod Identity
    - EC2           (vpce-0b52...) — Node management
    - ELB           (vpce-01ac...) — ALB Controller TLS fix
    - KMS           (vpce-0ea3...) — Vault auto-unseal (ADR-055)
  Gateway:
    - S3            (vpce-0a7e...) — Zero cost, Vault snapshots + Harbor

Load Balancers (8):
  ALB (6):
    - k8s-gitlabst-gitlabwe  (GitLab Webservice staging)
    - k8s-gitlabst-gitlabre  (GitLab Registry staging)
    - k8s-gitlabst-gitlabka  (GitLab KAS staging)
    - k8s-platformstaging     (Platform staging: ArgoCD, Keycloak, SonarQube, Vault, Harbor)
    - k8s-observabilitystaging (Observability staging: Grafana)
    - k8s-datastaging          (Data staging: RabbitMQ Management)
  NLB (2):
    - k8s-dataserv-rabbitmq   (RabbitMQ data-services)
    - k8s-default-rabbitmq    (RabbitMQ default — cleanup candidato)

Local Access (/etc/hosts):
  # GitLab Services (ALB: gitlab-staging group)
  <GITLAB_ALB_IP>   gitlab.staging.internal
  <GITLAB_ALB_IP>   registry.staging.internal
  <GITLAB_ALB_IP>   kas.staging.internal

  # Platform Services (ALB: platform-staging group)
  <PLATFORM_ALB_IP> argocd.staging.internal
  <PLATFORM_ALB_IP> keycloak.staging.internal
  <PLATFORM_ALB_IP> sonarqube.staging.internal
  <PLATFORM_ALB_IP> vault.staging.internal
  <PLATFORM_ALB_IP> harbor.staging.internal

  # Observability (ALB: observability-staging group)
  <OBS_ALB_IP>      grafana.staging.internal

  # Data Services (ALB: data-staging group)
  <DATA_ALB_IP>     rabbitmq.staging.internal
```

### FinOps Automation (ATIVO)

```yaml
Lambda Functions:
  - finops-scheduler-start-staging  (python3.11, 512MB)
  - finops-scheduler-stop-staging   (python3.11, 512MB)

EventBridge Rules:
  - finops-startup-staging:          cron(30 10 ? * MON-FRI *)  # 07h30 BRT
  - finops-shutdown-staging:         cron(0 23 ? * MON-FRI *)   # 20h00 BRT
  - weekend-shutdown-staging:        cron(0 3 ? * SAT *)        # Sabado 00h BRT

Economia estimada: ~$177/mes (25.9% reducao)
```

---

## Componentes Deployados (Staging)

### Quickstart Core

```
EKS 1.34 Standard + 8 nodes (3 node groups)
PostgreSQL RDS 16.4 (db.t3.medium, gp3, single-AZ)
Redis Operator HA (Spotahome — master + 1 replica + 3 sentinels)
RabbitMQ Operator (Official — 1 replica)
GitLab CE (1 webservice + 1 sidekiq + 1 runner)
S3 IRSA (artifacts + images)
FinOps Automation (Lambda + EventBridge)
```

### Extras (fora do quickstart original)

```
Vault HA (3 replicas, KMS auto-unseal)
Harbor Registry (S3 IRSA)
Keycloak SSO (2 replicas, OIDC provider)
ArgoCD GitOps (2 replicas HA)
External Secrets Operator (Vault backend)
OpenTelemetry Collector (Gateway, 2 replicas, HPA 2-5)
Kube-Prometheus-Stack (Prometheus + Grafana + Loki + Tempo)
```

---

## Custos Reais Estimados (2026-02-12)

| Categoria                   | Custo/mes     | Nota                                   |
| --------------------------- | ------------- | -------------------------------------- |
| EKS Control Plane           | $73           | Standard Support v1.34                 |
| EC2 Compute (8 nodes)       | ~$487         | 2x t3.med + 4x t3.large + 2x t3.xlarge |
| EBS Storage                 | ~$45          | 555GB (97% gp3)                        |
| RDS PostgreSQL              | $29           | db.t3.medium single-AZ                 |
| Load Balancers (6)          | ~$97          | 4 ALB + 2 NLB                          |
| NAT Gateways (2)            | $66           | Reuso Marco 0                          |
| VPC Endpoints (4 Interface) | ~$58          | STS + EC2 + ELB + KMS                  |
| S3 Storage                  | ~$17          | 6 buckets ativos                       |
| CloudWatch/Outros           | ~$21          | Logs + metrics                         |
| **SUBTOTAL**                | **~$893/mes** |                                        |
| **FinOps Economy**          | **-$177/mes** | Auto-shutdown 70% offline              |
| **TOTAL EFETIVO**           | **~$716/mes** | **~R$ 3.601/mes** (R$ 5.03)            |

### Comparativo com versao anterior do documento (v2.0)

| Item            | Doc v2.0 (2026-02-10) | Real (2026-02-12)  | Delta                |
| --------------- | --------------------- | ------------------ | -------------------- |
| EKS Support     | Extended ($378)       | **Standard ($73)** | **-$305/mes**        |
| Nodes           | 10 ($614)             | **8 (~$487)**      | **-$127/mes**        |
| LBs             | 10 ($172)             | **6 (~$97)**       | **-$75/mes**         |
| EBS             | 887GB ($71)           | **555GB (~$45)**   | **-$26/mes**         |
| VPC Endpoints   | 2 ($29)               | **5 (~$58)**       | +$29/mes             |
| **Total bruto** | **$1.397/mes**        | **~$893/mes**      | **-$504/mes (-36%)** |

---

## Terraform — Gaps de Conformidade

### CRITICO

| #   | Gap                   | Estado Atual TF                      | AWS Real                             | Acao                           |
| --- | --------------------- | ------------------------------------ | ------------------------------------ | ------------------------------ |
| T1  | EKS version no modulo | `modules/eks/main.tf` default="1.28" | 1.34                                 | Atualizar default              |
| T2  | Node groups no modulo | 1 grupo "observability"              | 3 grupos (system/workloads/critical) | Reconciliar com Marco1 state   |
| T3  | kube-proxy addon      | nao gerenciado                       | v1.31.2 (deveria ser 1.34.x)         | `aws_eks_addon` ou CLI upgrade |

### ALTO

| #   | Gap                     | Estado Atual TF             | AWS Real                     | Acao                          |
| --- | ----------------------- | --------------------------- | ---------------------------- | ----------------------------- |
| T4  | VPC Endpoints STS + EC2 | ausentes do staging main.tf | existem no AWS               | Importar ou confirmar Marco1  |
| T5  | Orphan Security Groups  | 3 SGs PostgreSQL antigos    | sg-06f.., sg-098.., sg-025.. | Cleanup — manter apenas atual |
| T6  | NLB RabbitMQ default NS | nao declarado               | k8s-default-rabbitmq ativo   | Cleanup ou importar           |

### MEDIO

| #   | Gap                          | Estado Atual TF   | AWS Real                  | Acao                |
| --- | ---------------------------- | ----------------- | ------------------------- | ------------------- |
| T7  | Redis/RabbitMQ storage_class | `"gp2"` hardcoded | 3 PVCs gp2 (15GB)         | Migrar para gp3     |
| T8  | Comentario PostgreSQL        | `# db.t3.micro`   | db.t3.medium (via tfvars) | Corrigir comentario |

---

## Status dos Marcos

```
Marco 0: Baseline Terraform               100%
Marco 1: EKS Base Infrastructure           100%
Marco 2: Platform Services (8/8 fases)     100%
Marco 3: Workloads (GitLab + Operators)    100%
Marco 4: CI/CD Pipeline + OIDC             ~80%
  - GitLab OIDC Keycloak                   Operacional (PKCE S256)
  - ArgoCD OIDC Keycloak                   Operacional (PKCE disabled)
  - Node Groups v1.34                      Completo
  - E2E Smoke Test App                     Pendente
  - FinOps Dashboards Grafana              Pendente
```

---

## Proximos Passos

### Terraform Conformidade (prioritario)

1. **kube-proxy upgrade** → 1.34.x (mismatch atual)
2. **Reconciliar modulo EKS** com estado real (version + node groups)
3. **Cleanup orphan SGs** (3 PostgreSQL antigos)
4. **NLB RabbitMQ default NS** — avaliar se necessario ou cleanup

### Operacional

1. **E2E Smoke Test App** — FastAPI via GitLab CI/CD
2. **FinOps Grafana Dashboards** — 3 dashboards (costs, utilization, alerts)
3. **Redis/RabbitMQ gp2 → gp3** — migrar 3 PVCs restantes (15GB)

---

## Referencias

- [Architecture](../../context/architecture.md) — Arquitetura completa
- [Decisions](../../context/decisions.md) — ADRs 001-056
- [Costs](../../context/costs.md) — Breakdown custos
- [Quickstart Original](./aws-eks-gitlab-quickstart.md) — Plano original (historico)
- [Logbook Node Upgrade](../../logbook/2026-02-12-quickstart-mvp-completion.md) — Task#2 v1.34
- [Logbook OIDC Fix](../../logbook/2026-02-12-keycloak-oidc-resolution.md) — Keycloak fix

---

**Mantenedor:** DevOps Team
**Ultima Revisao:** 2026-02-12
**Proxima Revisao:** 2026-02-26
