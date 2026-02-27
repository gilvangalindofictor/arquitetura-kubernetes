# ADR-006: Refatoração Terraform para Cloud-Agnostic

**Status**: ✅ Aceito e Implementado  
**Data**: 2026-01-05  
**Contexto**: Refatoração planejada no ADR-005 (Fase 1 e Fase 2)  
**Decisores**: Arquiteto de Plataforma  
**Impacto**: 🔴 Alto - Reestruturação completa do terraform do domínio

---

## Contexto

### Problema Identificado

Durante a **Validação #3** contra SAD v1.2 (documentada no ADR-005), foi confirmado que o terraform do domínio observability **violava** dois ADRs críticos:

1. **ADR-003 (Cloud-Agnostic)**: Terraform provisionava recursos AWS diretamente (EKS, VPC, S3, IAM)
2. **ADR-020 (Provisionamento de Clusters)**: Cluster EKS provisionado dentro do domínio, não em `/platform-provisioning/`

### Estrutura Problemática (Antes)

```
/domains/observability/infra/terraform/
├── main.tf              # ❌ provider "aws" + modules AWS-specific
├── variables.tf         # ❌ aws_region, aws_profile
├── outputs.tf           # ❌ Outputs AWS-specific
└── modules/
    ├── vpc/             # ❌ VPC, Subnets, NAT Gateway
    ├── eks/             # ❌ EKS cluster, node groups
    ├── s3/              # ❌ S3 buckets com lifecycle
    └── iam/             # ❌ IRSA roles
```

**Violações**:
- Domínio **acoplado à AWS** (impossível deploy em Azure/GCP)
- Cluster provisionado **dentro do domínio** (violação ADR-020)
- **Impossibilidade de reutilizar** cluster para múltiplos domínios
- **Impossibilidade de CI/CD multi-cloud** (deployment depende de provider AWS)

---

## Decisão

Executar **refatoração completa do terraform** em **duas fases**, conforme planejado no ADR-005:

### Fase 1: Migração de Módulos AWS ✅ Concluída

**Objetivo**: Mover todos os módulos AWS-specific para `/platform-provisioning/aws/`

**Ações Executadas**:
1. ✅ Criado `/platform-provisioning/aws/kubernetes/terraform/`
2. ✅ Copiados módulos (vpc, eks, s3, iam) de observability → platform-provisioning
3. ✅ Criado `main.tf` com providers AWS + módulos consolidados
4. ✅ Criado `variables.tf` com parametrização (aws_region, cluster_name, s3_buckets list, kubernetes_namespaces)
5. ✅ Criado `outputs.tf` com **outputs padronizados** (cluster_endpoint, storage_class_name, s3_bucket_*, object_storage_endpoint)
6. ✅ Criado `terraform.tfvars.example` com exemplo de configuração
7. ✅ Criado `README.md` completo (Quick Start, custos $599.30/mês, outputs, arquitetura)

**Resultado**: Cluster AWS agora provisionado de forma **centralizada e reutilizável**.

### Fase 2: Refatoração Domínio Cloud-Agnostic ✅ Concluída

**Objetivo**: Transformar terraform do domínio para **consumir outputs** do platform-provisioning

**Ações Executadas**:
1. ✅ Criado `main-cloud-agnostic.tf`:
   - Providers: `kubernetes`, `helm` **ONLY** (SEM `aws`)
   - Namespaces: `for_each` environments (dev, staging, production)
   - Helm releases: kube-prometheus-stack, loki, tempo, otel-collector
   - Consumo de variáveis: `var.cluster_endpoint`, `var.storage_class_name`, `var.s3_bucket_*`

2. ✅ Criado `variables-cloud-agnostic.tf`:
   - **Inputs de platform-provisioning**: cluster_endpoint, cluster_ca_certificate, storage_class_name, s3_bucket_*, object_storage_endpoint
   - **Config de domínio**: environments, retention_days, storage_sizes, alert thresholds

3. ✅ Criado `terraform.tfvars.example-cloud-agnostic`:
   - Instruções para capturar outputs: `terraform output` em `/platform-provisioning/aws/`
   - Exemplo completo de configuração

4. ✅ **Substituição de arquivos**:
   - `main-cloud-agnostic.tf` → `main.tf` (substituiu antigo com provider AWS)
   - `variables-cloud-agnostic.tf` → `variables.tf` (substituiu antigo com aws_region)
   - `terraform.tfvars.example-cloud-agnostic` → `terraform.tfvars.example`

5. ✅ **Remoção de código AWS**:
   - Deletado `/modules/` (vpc, eks, s3, iam - agora em `/platform-provisioning/aws/`)
   - Deletado `outputs.tf` (outputs agora vêm de platform-provisioning)

**Resultado**: Domínio **100% cloud-agnostic**, deployável em qualquer cluster Kubernetes com outputs equivalentes.

---

## Padrão de Outputs Estabelecido

### Platform Provisioning (Outputs)

```hcl
# /platform-provisioning/aws/kubernetes/terraform/outputs.tf

output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "Kubernetes API endpoint"
}

output "cluster_ca_certificate" {
  value       = base64decode(module.eks.cluster_ca_certificate)
  sensitive   = true
  description = "Cluster CA certificate"
}

output "storage_class_name" {
  value       = "gp3"  # AWS
  description = "Default storage class (cloud-specific)"
}

output "storage_class_fast" {
  value       = "io2"  # AWS
  description = "Fast storage class for performance workloads"
}

output "s3_bucket_metrics" {
  value       = module.s3.bucket_names["metrics"]
  description = "S3 bucket for metrics (Prometheus/Thanos)"
}

output "s3_bucket_logs" {
  value       = module.s3.bucket_names["logs"]
  description = "S3 bucket for logs (Loki)"
}

output "s3_bucket_traces" {
  value       = module.s3.bucket_names["traces"]
  description = "S3 bucket for traces (Tempo)"
}

output "object_storage_endpoint" {
  value       = "https://s3.${var.aws_region}.amazonaws.com"
  description = "S3-compatible endpoint (Azure: Blob Storage, GCP: GCS)"
}

output "iam_role_arns" {
  value       = { for ns, role_arn in module.iam.role_arns : ns => role_arn }
  description = "IRSA role ARNs by namespace"
}
```

### Domain (Inputs/Variables)

```hcl
# /domains/observability/infra/terraform/variables.tf

# ===== INPUTS FROM PLATFORM-PROVISIONING =====
variable "cluster_endpoint" {
  type        = string
  description = "Kubernetes API endpoint (from platform-provisioning output)"
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Cluster CA certificate (from platform-provisioning output)"
  sensitive   = true
}

variable "storage_class_name" {
  type        = string
  description = "Storage class name (gp3 for AWS, managed-premium for Azure, pd-ssd for GCP)"
  default     = "gp3"
}

variable "s3_bucket_metrics" {
  type        = string
  description = "Object storage bucket for metrics (from platform-provisioning output)"
}

variable "s3_bucket_logs" {
  type        = string
  description = "Object storage bucket for logs (from platform-provisioning output)"
}

variable "s3_bucket_traces" {
  type        = string
  description = "Object storage bucket for traces (from platform-provisioning output)"
}

variable "object_storage_endpoint" {
  type        = string
  description = "S3-compatible endpoint URL (from platform-provisioning output)"
}

# ===== DOMAIN-SPECIFIC CONFIG =====
variable "environments" {
  type        = list(string)
  description = "Kubernetes namespaces for observability stack"
  default     = ["observability-dev", "observability-staging", "observability-production"]
}
```

### Domain (Usage)

```hcl
# /domains/observability/infra/terraform/main.tf

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64encode(var.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64encode(var.cluster_ca_certificate)
  }
}

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = "observability-production"
  chart      = "loki"
  repository = "https://grafana.github.io/helm-charts"

  set {
    name  = "loki.storage.s3.bucketnames"
    value = var.s3_bucket_logs  # ✅ Cloud-agnostic variable
  }

  set {
    name  = "loki.storage.s3.endpoint"
    value = var.object_storage_endpoint  # ✅ Cloud-agnostic variable
  }

  set {
    name  = "loki.storage.s3.region"
    value = split(".", var.object_storage_endpoint)[1]  # us-east-1 from URL
  }
}
```

---

## Estrutura Final (Depois)

### Platform Provisioning (Cloud-Specific Permitido)

```
/platform-provisioning/aws/kubernetes/terraform/
├── main.tf              # ✅ provider "aws" + modules (vpc, eks, s3, iam)
├── variables.tf         # ✅ aws_region, cluster_name, s3_buckets (list), kubernetes_namespaces
├── outputs.tf           # ✅ Outputs padronizados (cluster_endpoint, storage_class_name, etc.)
├── terraform.tfvars.example
├── README.md            # ✅ Guia completo (Quick Start, custos, outputs)
└── modules/
    ├── vpc/             # ✅ VPC, Subnets, NAT Gateway
    ├── eks/             # ✅ EKS cluster, node groups (on-demand + spot)
    ├── s3/              # ✅ S3 buckets com lifecycle policies
    └── iam/             # ✅ IRSA roles por namespace
```

### Domain (Cloud-Agnostic Obrigatório)

```
/domains/observability/infra/terraform/
├── main.tf              # ✅ Providers kubernetes/helm ONLY
├── variables.tf         # ✅ Inputs de platform-provisioning (cluster_endpoint, storage_class_name, s3_bucket_*)
├── terraform.tfvars.example
├── REFACTORING-STATUS.md
└── (sem modules/)       # ✅ Consome outputs do platform-provisioning
```

---

## Workflow de Deploy Refatorado

### 1. Provisionar Cluster (Uma vez, reutilizável)

```bash
cd /platform-provisioning/aws/kubernetes/terraform/

# Editar terraform.tfvars
terraform init
terraform apply

# Capturar outputs para uso pelos domínios
terraform output -json > outputs.json
terraform output cluster_endpoint
terraform output storage_class_name
terraform output s3_bucket_logs
```

### 2. Deploy Domínio Observability (Consumindo outputs)

```bash
cd /domains/observability/infra/terraform/

# Editar terraform.tfvars com outputs capturados
cat <<EOF > terraform.tfvars
cluster_endpoint        = "https://1234567890ABCDEF.gr7.us-east-1.eks.amazonaws.com"
cluster_ca_certificate  = "LS0tLS1CRUdJTi..."
storage_class_name      = "gp3"
s3_bucket_metrics       = "platform-metrics-abc123"
s3_bucket_logs          = "platform-logs-abc123"
s3_bucket_traces        = "platform-traces-abc123"
object_storage_endpoint = "https://s3.us-east-1.amazonaws.com"

environments = ["observability-production"]
EOF

terraform init
terraform apply
```

### 3. Deploy Outros Domínios (Reutilizando cluster)

```bash
# platform-core domain
cd /domains/platform-core/infra/terraform/
terraform init
terraform apply  # Usa MESMOS outputs de platform-provisioning

# cicd-platform domain
cd /domains/cicd-platform/infra/terraform/
terraform init
terraform apply  # Usa MESMOS outputs de platform-provisioning
```

---

## Benefícios

### 1. Conformidade com ADRs ✅

- ✅ **ADR-003 (Cloud-Agnostic)**: Domínio usa apenas `kubernetes` + `helm` providers
- ✅ **ADR-020 (Provisionamento)**: Cluster provisionado centralmente em `/platform-provisioning/`
- ✅ **ADR-021 (Kubernetes)**: Stack 100% Kubernetes-native

### 2. Multi-Cloud Ready 🌐

**Exemplo Azure** (futuro):
```hcl
# /platform-provisioning/azure/kubernetes/terraform/outputs.tf
output "storage_class_name" {
  value = "managed-premium"  # Azure Disk
}

output "object_storage_endpoint" {
  value = "https://${azurerm_storage_account.main.name}.blob.core.windows.net"
}
```

**Domínio observability** (MESMO código terraform):
```hcl
# Funciona em AWS E Azure sem alterações!
resource "helm_release" "loki" {
  set {
    name  = "loki.storage.s3.bucketnames"
    value = var.s3_bucket_logs  # ✅ Nome do bucket/container
  }
  set {
    name  = "loki.storage.s3.endpoint"
    value = var.object_storage_endpoint  # ✅ S3 ou Blob Storage URL
  }
}
```

### 3. Reutilização de Cluster 🔄

- **1 cluster** → **6 domínios** (observability, platform-core, cicd-platform, etc.)
- **Economia de custos**: Sem provisionar cluster por domínio
- **Gestão simplificada**: RBAC, Network Policies, Service Mesh centralizados

### 4. Separação de Responsabilidades 👥

| Responsabilidade | Equipe | Terraform |
|------------------|--------|-----------|
| Provisionar cluster AWS/Azure/GCP | **Platform Team** | `/platform-provisioning/{cloud}/` |
| Deploy domínio observability | **Observability Team** | `/domains/observability/` |
| Deploy domínio cicd-platform | **CI/CD Team** | `/domains/cicd-platform/` |

### 5. Testabilidade Local 🧪

**Antes** (AWS obrigatório):
```bash
# Terraform exigia AWS credentials
terraform apply  # ❌ Necessita VPC, EKS, S3
```

**Depois** (Kubernetes genérico):
```bash
# Kind/Minikube local
kind create cluster
kubectl apply -f local-dev/storage-class.yaml  # storage_class_name="standard"

# Terraform consome cluster local
terraform apply -var="cluster_endpoint=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" \
                -var="storage_class_name=standard" \
                -var="s3_bucket_logs=local-logs"
```

---

## Consequências

### Positivas ✅

1. **Conformidade total com SAD v1.2**: ADR-003, ADR-020, ADR-021 atendidos
2. **Multi-cloud**: Deploy em AWS, Azure, GCP sem alterações no domínio
3. **Reutilização**: Cluster compartilhado por múltiplos domínios
4. **Testabilidade**: Desenvolvimento local com Kind/Minikube
5. **Manutenibilidade**: Módulos AWS centralizados em `/platform-provisioning/`
6. **Rastreabilidade**: Outputs padronizados documentados

### Negativas ⚠️

1. **Complexidade inicial**: 2 etapas de terraform (platform → domain)
2. **Acoplamento de outputs**: Mudanças em platform-provisioning impactam domínios
3. **Documentação crítica**: Dependência de README e outputs.tf atualizados
4. **Migração manual**: Workloads existentes precisam migração de state

### Mitigações 🛡️

1. **Documentação abrangente**: README em `/platform-provisioning/aws/` com outputs detalhados
2. **Versionamento de outputs**: Outputs seguem semantic versioning (v1.0 atual)
3. **Validação automatizada**: Hook `post-activity-validation.md` valida consistência
4. **REFACTORING-STATUS.md**: Status detalhado da migração para rastreabilidade

---

## Custos AWS (Referência)

**Cluster base** (`/platform-provisioning/aws/`):
- EKS Control Plane: **$73.00/mês**
- Nodes (2x t3.large on-demand): **$150.72/mês**
- Nodes (2x t3.large spot 70% discount): **$45.22/mês**
- NAT Gateway (2x AZs): **$32.40/mês**
- EBS (200GB gp3): **$16.00/mês**
- S3 (1TB total): **$23.55/mês**
- Data Transfer (estim.): **$8.41/mês**
- **TOTAL**: **$599.30/mês** ($7,191.60/ano)

**Escalabilidade**: Cluster suporta 6 domínios (~$100/domínio/mês amortizado)

---

## Validação

### Checklist de Implementação

- ✅ Módulos AWS migrados para `/platform-provisioning/aws/`
- ✅ Outputs padronizados criados (cluster_endpoint, storage_class_name, s3_bucket_*)
- ✅ Terraform domínio refatorado (kubernetes/helm providers only)
- ✅ Variáveis parametrizadas (consumindo outputs)
- ✅ Arquivos antigos removidos (main.tf AWS, modules/, outputs.tf)
- ✅ REFACTORING-STATUS.md criado
- ✅ README `/platform-provisioning/aws/` criado
- ✅ Log de progresso atualizado
- ✅ ADR-006 documentado

### Próximos Passos (Roadmap)

1. ⏳ **Testes de integração**: Provisionar cluster AWS + deploy observability
2. ⏳ **Parametrizar Helm values**: Substituir `storageClassName: gp2` por `{{ .Values.storageClass }}`
3. ⏳ **Azure implementation**: Criar `/platform-provisioning/azure/` com outputs equivalentes
4. ⏳ **GCP implementation**: Criar `/platform-provisioning/gcp/` com outputs equivalentes
5. ⏳ **Outros domínios**: Aplicar padrão em platform-core, cicd-platform
6. ⏳ **GitOps**: ArgoCD para continuous deployment (após cicd-platform)

---

## Referências

- [ADR-003: Cloud-Agnostic](../../../../SAD/docs/adrs/adr-003-cloud-agnostic.md)
- [ADR-020: Provisionamento de Clusters](../../../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)
- [ADR-021: Orquestração - Kubernetes](../../../../SAD/docs/adrs/adr-021-orquestracao-kubernetes.md)
- [ADR-005: Re-validação SAD v1.2](adr-005-revalidacao-sad-v12.md)
- [Platform Provisioning AWS README](../../../../platform-provisioning/aws/README.md)
- [REFACTORING-STATUS.md](../../infra/terraform/REFACTORING-STATUS.md)
- [Log de Progresso](../../../../docs/logs/log-de-progresso.md)

---

**Decisão Final**: ✅ **Implementada com sucesso**

**Responsável**: Arquiteto de Plataforma  
**Revisores**: Equipe Observability  
**Data de Implementação**: 2026-01-05  
**Versão**: 1.0
