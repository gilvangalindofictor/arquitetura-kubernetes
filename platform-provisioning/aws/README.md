# Platform Provisioning - AWS

> **Cloud**: Amazon Web Services (AWS)  
> **Status**: 🔄 Refatoração em andamento  
> **Custo Estimado**: $599.30/mês ($7,191.60/ano on-demand)  
> **Origem**: Refatorado de `/domains/observability/infra/terraform/`

---

## 📋 Visão Geral

Este diretório contém **IaC para provisionar infraestrutura AWS** da Plataforma Corporativa Kubernetes.

**Serviços Provisionados**:
- Elastic Kubernetes Service (EKS) - cluster gerenciado
- VPC + Subnets (3 AZs, public + private)
- Application Load Balancer
- S3 buckets para storage (métricas, logs, traces, backups)
- IAM Roles for Service Accounts (IRSA)

**Origem dos Módulos**: Migrados de `/domains/observability/infra/terraform/modules/`

---

## 🏗️ Estrutura

```
aws/
├── kubernetes/
│   ├── terraform/
│   │   ├── main.tf              # Configuração principal
│   │   ├── variables.tf         # Variáveis parametrizadas
│   │   ├── outputs.tf           # Outputs padronizados
│   │   ├── terraform.tfvars.example  # Valores de exemplo
│   │   └── modules/
│   │       ├── vpc/             # VPC, Subnets, NAT Gateway
│   │       ├── eks/             # EKS cluster, node groups
│   │       ├── s3/              # S3 buckets com lifecycle
│   │       └── iam/             # IRSA roles por namespace
│   └── docs/
│       ├── architecture.md      # ⏳ A criar
│       └── runbook.md           # ⏳ A criar
└── README.md
```

---

## 🚀 Quick Start

### Pré-requisitos

1. **AWS CLI** instalado e autenticado:
```bash
aws configure
aws sts get-caller-identity
```

2. **Terraform** >= 1.5.0:
```bash
terraform version
```

3. **kubectl** instalado (para validação):
```bash
kubectl version --client
```

### Provisionamento

```bash
# 1. Navegar para diretório Terraform
cd platform-provisioning/aws/kubernetes/terraform/

# 2. Copiar e editar variáveis
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars com valores reais

# 3. Inicializar Terraform
terraform init

# 4. Planejar (revisar mudanças)
terraform plan

# 5. Aplicar (provisionar infraestrutura)
terraform apply

# 6. Capturar outputs
terraform output -json > outputs.json

# 7. Configurar kubeconfig
aws eks update-kubeconfig --name kubernetes-platform --region us-east-1

# 8. Validar cluster
kubectl get nodes
kubectl get storageclasses
```

---

## 💰 Custo Detalhado

### Por Domínio (Estimativa)

| Domínio | Custo Mensal (USD) | Componentes Principais |
|---------|-------------------|------------------------|
| Platform-Core | $218.50 | EKS control plane, ALB, Route53 |
| CI/CD Platform | $95.00 | EBS volumes (500 GB) |
| Observability | $53.00 | S3 (metrics, logs, traces) |
| Data Services | $196.00 | RDS PostgreSQL, ElastiCache |
| Secrets Management | $2.80 | Secrets Manager |
| Security | $34.00 | GuardDuty, Config, CloudTrail |
| **TOTAL** | **$599.30** | |

**Anual**: $7,191.60 (on-demand)

**Referência**: [Cloud Architect AWS](../../../../docs/agents/cloud-architect-aws.md)

---

## 🔌 Outputs Fornecidos

Conforme ADR-020, este provisionamento fornece outputs padronizados:

```hcl
output "cluster_endpoint"        # EKS Kubernetes API endpoint
output "cluster_ca_certificate"  # CA certificate (base64)
output "cluster_name"            # Cluster name
output "storage_class_name"      # Default: "gp3"
output "storage_class_fast"      # Fast: "io2"
output "object_storage_buckets"  # S3 buckets por propósito
output "object_storage_endpoint" # S3 endpoint
output "iam_role_arns"           # IRSA roles por namespace
```

**Domínios devem consumir via variables**:

```hcl
# /domains/<domain>/infra/terraform/variables.tf
variable "storage_class_name" {
  description = "Storage class from platform-provisioning"
  type        = string
}

variable "s3_bucket_metrics" {
  description = "S3 bucket for metrics from platform-provisioning"
  type        = string
}
```

---

## 🛡️ Segurança

### IAM Roles (IRSA)
- Cada namespace tem IAM role dedicado
- Permissions mínimos (least privilege)
- Sem credentials em pods

### Network Security
- VPC isolada
- Security Groups configurados
- Private subnets para nodes
- Public subnets apenas para ALB

### Secrets Management
- AWS Secrets Manager
- External Secrets Operator para injeção
- Rotation automática habilitada

---

## 📊 Arquitetura

```
┌─────────────────────────────────────────────────┐
│           AWS Account                           │
│  ┌───────────────────────────────────────────┐ │
│  │  VPC: platform-vpc (10.0.0.0/16)          │ │
│  │                                           │ │
│  │  ┌──────────────────────────────────┐    │ │
│  │  │ Public Subnets (3 AZs)          │    │ │
│  │  │                                  │    │ │
│  │  │  [Application Load Balancer]    │    │ │
│  │  └──────────────────────────────────┘    │ │
│  │                                           │ │
│  │  ┌──────────────────────────────────┐    │ │
│  │  │ Private Subnets (3 AZs)         │    │ │
│  │  │                                  │    │ │
│  │  │  [EKS Cluster]                  │    │ │
│  │  │  - Control Plane (managed)      │    │ │
│  │  │  - Node Group (3x t3.medium)    │    │ │
│  │  └──────────────────────────────────┘    │ │
│  │                                           │ │
│  │  [NAT Gateway] → [Internet Gateway]      │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  [S3 Buckets] ◄──> [EKS Pods via IRSA]         │
│  [IAM Roles] → [Service Accounts]              │
└─────────────────────────────────────────────────┘
```

---

## 🔄 Migração de Observability

Este diretório foi criado a partir da refatoração do domínio **observability**:

**Antes**:
```
/domains/observability/infra/terraform/
├── main.tf              # ← Provisionava cluster
└── modules/
    ├── vpc/             # ← AWS-specific
    ├── eks/             # ← AWS-specific
    ├── s3/              # ← AWS-specific
    └── iam/             # ← AWS-specific
```

**Depois**:
```
/platform-provisioning/aws/kubernetes/terraform/
├── main.tf              # ← Cluster provisioning
└── modules/             # ← Migrado
    ├── vpc/
    ├── eks/
    ├── s3/
    └── iam/
```

**Domínio Observability** agora consome outputs via variables:
```
/domains/observability/infra/terraform/
├── main.tf              # ← Apenas kubernetes/helm providers
├── variables.tf         # ← var.storage_class_name, var.s3_bucket_*
└── namespaces.tf        # ← Namespaces, RBAC
```

**Referência**: [ADR-005 Observability](../../../../domains/observability/docs/adr/adr-005-revalidacao-sad-v12.md)

---

## 📚 Referências

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [AWS Pricing Calculator](https://calculator.aws/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Cloud Architect AWS](../../../../docs/agents/cloud-architect-aws.md)
- [ADR-020: Provisionamento de Clusters](../../../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)
- [ADR-021: Escolha do Orquestrador](../../../../SAD/docs/adrs/adr-021-orquestrador-containers.md)

---

## 🎯 Status

- ✅ **Módulos migrados**: vpc, eks, s3, iam
- ✅ **Terraform estruturado**: main, variables, outputs
- ⏳ **Docs**: architecture.md, runbook.md (pendentes)
- ⏳ **Validação**: Provisionar cluster dev/hml
- ⏳ **Domínio observability**: Refatorar para consumir outputs

**Próximo Passo**: Refatorar `/domains/observability/infra/terraform/`
