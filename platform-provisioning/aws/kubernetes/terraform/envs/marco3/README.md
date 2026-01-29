# Marco 3 - Data Services Infrastructure

**Status:** 🟡 Fase 1 Parcial (67% - PostgreSQL + S3 OK, Redis Bloqueado)
**Data:** 2026-01-29
**Documentação:** [Plano Completo](~/.claude/plans/wild-wiggling-treasure.md)

---

## 📊 Progresso Atual

### ✅ DEPLOYADO EM PRODUÇÃO (Fase 1 Parcial)

#### **PostgreSQL RDS - 100% OPERACIONAL** (Deploy: 10min 13s)
- ✅ **Instance:** k8s-platform-prod-postgresql (db-VBBRPNR4TI3JRZ26YQLROUY4BQ)
- ✅ **Engine:** PostgreSQL 16.4
- ✅ **Compute:** db.t3.medium (2 vCPU, 4GB RAM)
- ✅ **Storage:** 100GB gp3 → 500GB auto-scaling
- ✅ **Status:** **available** (us-east-1a)
- ✅ **Endpoint:** `k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432`
- ✅ **Acesso Interno:** `postgresql-external.default.svc.cluster.local:5432` (ExternalName Service)
- ✅ **Security:** Enhanced Monitoring (60s), Performance Insights, CloudWatch Logs
- ✅ **Backups:** 7 dias, janela 03:00-04:00 UTC
- ✅ **Password:** AWS Secrets Manager (`k8s-platform-prod/postgresql-master-*`)
- ✅ **Terraform State:** 13 resources
- ✅ **Economia:** $16.20/mês (NLB removido, acesso direto via RDS endpoint)

#### **S3 Buckets - 100% OPERACIONAL** (Deploy: 57s)
- ✅ **GitLab Artifacts:** `k8s-platform-gitlab-artifacts-891377105802`
  - Versioning habilitado
  - Encryption: AES256
  - Lifecycle: Expira após 90 dias
  - Public Access: BLOQUEADO
- ✅ **Harbor Images:** `k8s-platform-harbor-images-891377105802`
  - Versioning habilitado
  - Encryption: AES256
  - Lifecycle: STANDARD → IA (90d) → GLACIER (180d)
  - Public Access: BLOQUEADO
- ✅ **IAM IRSA Policies:** gitlab-s3, harbor-s3
- ✅ **Terraform State:** 10 resources

### ⚠️ BLOQUEADO - Aguardando Resolução

#### **Redis (bitnami Helm) - PROBLEMA TERRAFORM HELM PROVIDER**
- 📁 **Código:** 100% completo (`modules/redis/`, 200 linhas)
- 🔴 **Status:** Terraform Helm provider erro `invalid_reference: invalid tag`
- ✅ **Secrets:** redis-password criado (Kubernetes Secret)
- ❌ **Helm Release:** Falhou 4× (v18.19.4, v20.5.0, v24.1.2, sem versão)
- ✅ **Diagnóstico:** Helm CLI funciona (`helm install --dry-run` OK)
- 🔍 **Root Cause:** Bug Terraform Helm provider v2.17.0 com repo HTTP bitnami
- 💡 **Solução Proposta:** Helm CLI install + `terraform import` OU investigar provider
- ⏸️ **Decisão:** Usuário analisando workaround

### 🟡 PRONTO PARA DEPLOY (Fase 2)

#### **RabbitMQ Operator**
- 📁 **Código:** 100% completo (`modules/rabbitmq/`, 349 linhas)
- ✅ **Arquitetura:** Operator pattern (não usa Helm, sem conflito)
- 📦 **Componentes:** RabbitMQ Cluster Operator + CRD RabbitmqCluster
- 🎯 **Deployment:** 2 fases (Operator → Cluster CR)
- ⏸️ **Status:** Aguardando comando (pronto para `terraform apply`)

---

## 🏗️ Arquitetura Marco 3

```
┌─────────────────────────────────────────────────────────────────┐
│                       Marco 3 - Data Services                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────┐  ┌──────────────┐  ┌────────────────┐ │
│  │  PostgreSQL RDS    │  │    Redis     │  │   RabbitMQ     │ │
│  │  db.t3.medium      │  │  3 pods      │  │   3 nodes      │ │
│  │  Single-AZ         │  │  (1M + 2R)   │  │   Cluster      │ │
│  │  100GB → 500GB     │  │  PVC 8Gi     │  │   PVC 10Gi     │ │
│  │  ✅ COMPLETO       │  │  🟡 TODO     │  │   🟡 TODO      │ │
│  └────────┬───────────┘  └──────┬───────┘  └───────┬────────┘ │
│           │                     │                   │           │
│  ┌────────▼─────────────────────▼───────────────────▼────────┐ │
│  │                    VPC Marco 0                            │ │
│  │  CIDR: 10.0.0.0/16 | 2 AZs | Private Subnets             │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────┐  ┌────────────────────────────────────┐│
│  │   S3 Buckets       │  │   Acesso Externo (LoadBalancers)   ││
│  │  gitlab-artifacts  │  │   PostgreSQL: NLB port 5432         ││
│  │  harbor-images     │  │   Redis: NLB port 6379              ││
│  │  🟡 TODO           │  │   RabbitMQ: NLB port 15672          ││
│  └────────────────────┘  └────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Próximos Passos

### Passo 1: Completar Módulos Restantes

**Módulo Redis** (`modules/redis/main.tf`):
```hcl
# Helm release bitnami/redis v18.x
# Architecture: replication (1 master + 2 replicas)
# PVCs: 8Gi gp2 per pod
# Kubernetes Service LoadBalancer (NLB)
# Metrics: ServiceMonitor para Prometheus
```

**Módulo RabbitMQ** (`modules/rabbitmq/main.tf`):
```hcl
# Helm release rabbitmq-cluster-operator v4.x
# RabbitmqCluster CRD: 3 replicas
# Image: rabbitmq:3.13-management
# PVCs: 10Gi gp2 per node
# Plugins: management, prometheus, shovel, federation
# Kubernetes Service LoadBalancer (NLB) port 15672
```

**Módulo S3 Buckets** (`modules/s3-buckets/main.tf`):
```hcl
# Bucket 1: k8s-platform-gitlab-artifacts-891377105802
#   - Versioning enabled
#   - Lifecycle: expire 90 days
#   - Server-side encryption (AES256)
#   - IAM policy IRSA para GitLab

# Bucket 2: k8s-platform-harbor-images-891377105802
#   - Versioning enabled
#   - Lifecycle: 90d → STANDARD_IA, 180d → GLACIER
#   - Server-side encryption (AES256)
#   - IAM policy IRSA para Harbor
```

### Passo 2: Terraform Init & Plan

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/envs/marco3

# Initialize Terraform (download providers, configure backend)
terraform init

# Review plan (PostgreSQL module only, for now)
terraform plan -target=module.postgresql

# Expected output:
# Plan: ~15 to add (RDS, SG, Secrets, IAM, K8s Service)
```

### Passo 3: Deploy PostgreSQL (Fase 1)

```bash
# Apply PostgreSQL module
terraform apply -target=module.postgresql

# Wait for RDS to become available (10-15 min)
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text
# Expected: "available"

# Get master password
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw postgresql_password_secret_arn) \
  --query SecretString \
  --output text

# Get RDS endpoint
terraform output postgresql_endpoint
# Example: k8s-platform-prod-postgresql.c9xyz.us-east-1.rds.amazonaws.com:5432

# Get NLB hostname for external access
terraform output postgresql_nlb_hostname
# Example: k8s-platform-prod-postgresql-nlb-abc123.elb.us-east-1.amazonaws.com
```

### Passo 4: Criar Databases

```bash
# Connect via psql (usando NLB)
export PGPASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw postgresql_password_secret_arn) \
  --query SecretString --output text)

export RDS_ENDPOINT=$(terraform output -raw postgresql_endpoint | cut -d: -f1)

psql -h $RDS_ENDPOINT -U postgres_admin -d platform <<EOF
CREATE DATABASE gitlab;
CREATE DATABASE keycloak;
CREATE DATABASE harbor;
\l
\q
EOF

# Expected: 4 databases (platform, gitlab, keycloak, harbor)
```

### Passo 5: Validar Acesso Externo

**Via DBeaver/PgAdmin:**
- Host: `<NLB hostname from output>`
- Port: `5432`
- Database: `platform`
- Username: `postgres_admin`
- Password: `<from Secrets Manager>`

**Via kubectl (interno):**
```bash
kubectl run psql-test --rm -it --image postgres:16 -- \
  psql -h postgresql-external -U postgres_admin -d platform
```

### Passo 6: Deploy Redis + RabbitMQ (Fase 2)

```bash
# After completing modules
terraform apply -target=module.redis -target=module.rabbitmq

# Validate Redis
kubectl get pods -l app.kubernetes.io/name=redis
# Expected: 3 pods Running

kubectl exec -it redis-master-0 -- redis-cli PING
# Expected: PONG

# Validate RabbitMQ
kubectl get rabbitmqclusters
# Expected: k8s-platform-prod-rabbitmq READY

# Access Management UI: http://<NLB hostname>:15672
# User: admin, Password: kubectl get secret <name> -o jsonpath='{.data.password}' | base64 -d
```

### Passo 7: Deploy S3 Buckets (Fase 3)

```bash
terraform apply -target=module.s3_buckets

# Validate buckets
aws s3 ls | grep k8s-platform
# Expected: gitlab-artifacts, harbor-images

# Test upload
echo "test" | aws s3 cp - s3://k8s-platform-gitlab-artifacts-891377105802/test.txt
```

---

## 💰 Custo Estimado Marco 3

| Componente | Custo/Mês | Tipo | Status |
|------------|-----------|------|--------|
| **PostgreSQL RDS** | $50.00 | Fixo | ✅ Código pronto |
| **NLB PostgreSQL** | $16.20 | Fixo | ✅ Código pronto |
| **NLB Redis** | $16.20 | Fixo | 🟡 Pendente |
| **NLB RabbitMQ** | $16.20 | Fixo | 🟡 Pendente |
| **S3 GitLab Artifacts (500GB)** | $11.50 | Variável | 🟡 Pendente |
| **S3 Harbor Images (200GB)** | $4.60 | Variável | 🟡 Pendente |
| **Secrets Manager (3 secrets)** | $1.20 | Fixo | ✅ Incluído PostgreSQL |
| **EBS PVCs (Redis + RabbitMQ)** | $3.20 | Variável | 🟡 Pendente |
| **TOTAL Marco 3** | **$119.10/mês** | | |
| **Marco 2 Base** | $666.00 | | |
| **TOTAL INFRA** | **$785.10/mês** | | |

**Impacto Startup/Shutdown:**
- **Custos Fixos:** $200.75 (Marco 2) + $100.70 (Marco 3 RDS+NLBs) = **$301.45/mês** (38.4%)
- **Custos Variáveis:** $484.95 (Marco 2) + $18.50 (Marco 3 S3+PVCs) = **$503.45/mês** (61.6%)
- **Economia 8h/dia:** $503.45 × 67% shutdown = **$337.31/mês** ($4,047.72/ano)

---

## 📋 Definition of Done - Marco 3

### PostgreSQL ✅
- [x] RDS instance status `available`
- [x] Security group allow VPC
- [x] Master password em Secrets Manager
- [x] Enhanced Monitoring ativo
- [x] Backup 7 days configurado
- [x] NLB LoadBalancer criado (pending deployment)
- [ ] 3 databases criados (gitlab, keycloak, harbor) - **após terraform apply**
- [ ] Acesso via DBeaver validado - **após NLB deployment**

### Redis 🟡
- [ ] 3 pods Running (1 master + 2 replicas)
- [ ] PVCs 8Gi Bound
- [ ] NLB LoadBalancer ativo
- [ ] Teste `redis-cli PING` → `PONG`
- [ ] ServiceMonitor criado (Prometheus)

### RabbitMQ 🟡
- [ ] RabbitmqCluster CR status `READY`
- [ ] 3 nodes Running
- [ ] PVCs 10Gi Bound (3×)
- [ ] Management UI acessível via NLB
- [ ] Default user secret criado

### S3 Buckets 🟡
- [ ] 2 buckets criados com encryption
- [ ] Lifecycle policies configuradas
- [ ] IAM IRSA policies criadas
- [ ] Upload test successful

### Observabilidade
- [ ] Prometheus scraping metrics (Redis, RabbitMQ)
- [ ] Grafana dashboards (PostgreSQL RDS, Redis, RabbitMQ)
- [ ] CloudWatch alarms (RDS CPU, Storage)

---

## 🔗 Referências

### Documentação
- **Plano Executivo:** `~/.claude/plans/wild-wiggling-treasure.md`
- **ADR-021:** No-Domain Phase 1 Strategy (LoadBalancer pattern)
- **ADR-022:** Startup/Shutdown Automation (FinOps)
- **Diary:** [00-diario-de-bordo.md](../../docs/plan/aws-execution/00-diario-de-bordo.md)

### Terraform State
- **Backend:** S3 `terraform-state-marco0-891377105802`
- **Key:** `marco3/terraform.tfstate`
- **Remote States:**
  - Marco 0: VPC outputs (vpc_id, subnets, CIDR)
  - Marco 1: EKS cluster info

### Helm Charts
- Redis: `bitnami/redis` v18.x
- RabbitMQ: `bitnami/rabbitmq-cluster-operator` v4.x

---

**Última Atualização:** 2026-01-29
**Próxima Revisão:** Após deployment PostgreSQL (terraform apply)
**Mantenedor:** DevOps Team + Claude Sonnet 4.5

---

## 🎓 Lições Aprendidas - Marco 3 Fase 1

### 1. **VPC Data Sources > Remote State**
**Problema:** `terraform_remote_state.marco0` falhava (não existe)  
**Causa:** VPC "fictor-vpc" foi criada manualmente, não via Terraform Marco 0  
**Solução:** Usar `data "aws_vpc"` + `data "aws_subnets"` com filtros  
**Aprendizado:** Sempre verificar se remote state existe antes de referenciá-lo

### 2. **S3 Lifecycle Requires Filter**
**Problema:** `lifecycle_configuration` validation error  
**Causa:** AWS provider exige `filter {}` ou `prefix`, não aceita omissão  
**Solução:** Adicionar `filter {}` vazio em rules sem filtros específicos  
**Aprendizado:** Terraform AWS provider v5.x mais restritivo em validações

### 3. **Kubernetes Endpoints Não Aceita Hostnames**
**Problema:** `kubernetes_endpoints` erro "must be a valid IP address"  
**Causa:** RDS retorna hostname DNS, mas Endpoints exige IP address  
**Solução:** Usar `kubernetes_service` tipo **ExternalName** (DNS CNAME)  
**Benefício:** Acesso interno via DNS cluster + economia $16.20/mês (sem NLB)  
**Pattern:** `postgresql-external.default.svc.cluster.local` → RDS endpoint

### 4. **Terraform Helm Provider Instabilidade**
**Problema:** Erro `invalid_reference: invalid tag` (4 tentativas falhadas)  
**Causa:** Bug no Terraform Helm provider v2.17.0 com charts HTTP bitnami  
**Diagnóstico:** Helm CLI funciona, apenas Terraform provider falha  
**Workaround:** Instalar via Helm CLI + `terraform import` OU usar Operator pattern  
**Recomendação:** Preferir Operators (CRDs) para workloads stateful complexos

### 5. **Phased Deployment Strategy**
**Decisão:** 3 fases para evitar dependências circulares  
- **Fase 1:** PostgreSQL + Redis + S3 (sem CRDs)  
- **Fase 2:** RabbitMQ Operator (instala CRDs)  
- **Fase 3:** RabbitMQ Cluster (usa CRDs)  
**Motivo:** `kubernetes_manifest` valida CRDs no plan, mas CRDs só existem após Operator deploy

---

## 💰 Custo Atual Marco 3 (Parcial)

| Componente | Custo/Mês | Status |
|------------|-----------|--------|
| PostgreSQL RDS (db.t3.medium) | $50.00 | ✅ Ativo |
| S3 GitLab Artifacts (500GB) | $11.50 | ✅ Ativo |
| S3 Harbor Images (200GB) | $4.60 | ✅ Ativo |
| Secrets Manager (1 secret) | $0.40 | ✅ Ativo |
| **Redis NLB** | ~~$16.20~~ | ❌ Não criado |
| **Redis Cluster** | ~~$0~~ | ❌ Pendente |
| **RabbitMQ NLB** | $16.20 | ⏸️ Fase 2 |
| **RabbitMQ Cluster** | $0 | ⏸️ Fase 2 |
| **SUBTOTAL ATUAL** | **$66.50/mês** | Parcial (67%) |
| **TOTAL PROJETADO** | **$82.70/mês** | Com Redis+RabbitMQ |

**Economia vs Plano Original:** -$16.20/mês (PostgreSQL NLB removido)

---

## 📝 Status Terraform State

```bash
# Total resources: 29
terraform state list | wc -l
# 29

# Breakdown:
# - Data sources: 4 (aws_vpc, aws_subnets, aws_eks_cluster, aws_eks_cluster_auth)
# - PostgreSQL: 13 (RDS, SG, Subnet Group, IAM, Secrets, Service)
# - S3 Buckets: 10 (2 buckets + configs + IAM policies)
# - Redis: 2 (kubernetes_secret, random_password - Helm falhou)
```

**Backend S3:** `terraform-state-marco0-891377105802/marco3/terraform.tfstate`

---

## 🚀 Próximos Passos

### Imediato (Fase 2)
1. ✅ **Deploy RabbitMQ Operator** - Instala CRDs necessários
2. ⏸️ **Deploy RabbitMQ Cluster** - Cria cluster 3 nodes via CR
3. ⏸️ **Validar RabbitMQ** - Management UI, NLB externo

### Bloqueado (Aguardando Decisão)
- ⚠️ **Resolver Redis** - Helm CLI workaround OU investigar Terraform Helm provider

### Futuro (Marco 3 Tier 2)
- 📅 **GitLab CE** - Requer PostgreSQL + Redis + S3 (Semanas 6-8)
- 📅 **ArgoCD** - GitOps platform
- 📅 **Harbor** - Container registry + Trivy scan

---

**Última Atualização:** 2026-01-29 16:25 UTC  
**Próxima Ação:** Deploy RabbitMQ Operator (Fase 2)
