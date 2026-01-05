# Platform Provisioning

> **Propósito**: Provisionamento de clusters Kubernetes em clouds públicas (Azure, AWS, GCP) ou on-premises  
> **Escopo**: Cloud-specific infrastructure (clusters, networking, storage)  
> **Referência**: [ADR-020 - Provisionamento de Clusters](../SAD/docs/adrs/adr-020-provisionamento-clusters.md)

---

## 📋 Visão Geral

Este diretório contém **IaC cloud-specific** para provisionar a **infraestrutura base** da plataforma:
- Clusters Kubernetes (EKS, AKS, GKE)
- Networking (VPC, VNet, Subnets)
- Storage Classes
- IAM/RBAC cloud-specific
- DNS, Load Balancers, Firewalls

**Separação de Responsabilidades** (ADR-020):
- **`/platform-provisioning/{cloud}/`**: Provisiona cluster (**cloud-specific**)
- **`/domains/{domain}/`**: Deploy aplicações no cluster (**cloud-agnostic**)

---

## 🌍 Clouds Suportadas

### 1. Azure (Recomendada pelo CTO)

**Diretório**: [`azure/`](azure/)

**Serviços Provisionados**:
- Azure Kubernetes Service (AKS)
- Azure VNet + Subnets
- Azure Load Balancer
- Azure DNS
- Managed Disks (storage classes)
- Azure Blob Storage (S3-compatible)

**Custo Estimado**: $615.12/mês ($7,381.44/ano on-demand, $4,428.86/ano RI 3-year)

**Status**: 🔄 Em construção

---

### 2. AWS

**Diretório**: `aws/` (futuro)

**Serviços Provisionados**:
- Elastic Kubernetes Service (EKS)
- VPC + Subnets
- Application Load Balancer (ALB)
- Route53
- EBS volumes (gp3 storage classes)
- S3 buckets

**Custo Estimado**: $599.30/mês ($7,191.60/ano)

**Status**: ⏸️ Planejado (não prioritário)

---

### 3. GCP

**Diretório**: `gcp/` (futuro)

**Serviços Provisionados**:
- Google Kubernetes Engine (GKE)
- VPC + Subnets
- Cloud Load Balancing
- Cloud DNS
- Persistent Disks (pd-ssd storage classes)
- Cloud Storage buckets

**Custo Estimado**: $837.11/mês ($10,045.32/ano)

**Status**: ⏸️ Planejado (não prioritário)

---

## 🏗️ Estrutura por Cloud

Cada cloud segue estrutura padrão:

```
/{cloud}/
├── kubernetes/
│   ├── terraform/
│   │   ├── provider.tf       # Provider cloud-specific
│   │   ├── cluster.tf        # Cluster K8s (EKS, AKS, GKE)
│   │   ├── networking.tf     # VPC, VNet, Subnets
│   │   ├── storage.tf        # Storage classes, object storage
│   │   ├── iam.tf            # IAM roles, policies
│   │   ├── outputs.tf        # Outputs para domínios
│   │   ├── variables.tf      # Variáveis parametrizadas
│   │   └── terraform.tfvars  # Valores específicos
│   └── docs/
│       ├── architecture.md   # Arquitetura da cloud
│       └── runbook.md        # Procedimentos operacionais
└── README.md
```

---

## 🔌 Outputs para Domínios

Cada cloud DEVE fornecer outputs padronizados:

```hcl
output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = <cloud_specific_cluster_endpoint>
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate"
  value       = <cloud_specific_ca_cert>
}

output "cluster_name" {
  description = "Cluster name"
  value       = <cloud_specific_cluster_name>
}

output "storage_class_name" {
  description = "Default storage class (gp3, managed-premium, pd-ssd)"
  value       = <cloud_specific_storage_class>
}

output "storage_class_fast" {
  description = "Fast storage class (io2, premium-ssd, pd-ssd)"
  value       = <cloud_specific_fast_storage>
}

output "object_storage_bucket" {
  description = "S3-compatible object storage bucket"
  value       = <cloud_specific_bucket_name>
}

output "object_storage_endpoint" {
  description = "S3-compatible endpoint"
  value       = <cloud_specific_endpoint>
}
```

---

## 🚀 Workflow de Provisionamento

### 1. Escolher Cloud

Baseado em análise CTO ([docs/agents/cto.md](../docs/agents/cto.md)):
- **Azure**: Recomendado (custo competitivo, AKS control plane gratuito)
- **AWS**: Menor custo absoluto, ecossistema maduro
- **GCP**: Mais caro, Kubernetes-native

### 2. Provisionar Cluster

```bash
cd platform-provisioning/azure/kubernetes/terraform/
terraform init
terraform plan
terraform apply
```

### 3. Capturar Outputs

```bash
terraform output -json > outputs.json
```

### 4. Configurar Domínios

Usar outputs como variáveis de entrada para domínios:

```hcl
# /domains/cicd-platform/terraform/variables.tf
variable "cluster_endpoint" {
  description = "Kubernetes API endpoint from platform-provisioning"
}

variable "storage_class_name" {
  description = "Storage class from platform-provisioning"
}
```

---

## 🔐 Conformidade com ADRs

### ADR-003: Cloud-Agnostic
- ✅ Domínios permanecem cloud-agnostic
- ✅ Apenas `/platform-provisioning/` é cloud-specific
- ✅ Migração entre clouds: trocar apenas esta pasta

### ADR-004: IaC e GitOps
- ✅ Terraform para provisionamento
- ✅ Remote state obrigatório (S3-compatible + locking)
- ✅ Versionamento via Git

### ADR-020: Provisionamento de Clusters e Escopo
- ✅ Clusters provisionados EXTERNAMENTE aos domínios
- ✅ Domínios assumem cluster existente
- ✅ Outputs padronizados

### ADR-021: Escolha do Orquestrador
- ✅ Kubernetes escolhido vs Swarm, Nomad, ECS, Cloud Run
- ✅ Provisionamento via managed services (EKS, AKS, GKE)

---

## 📚 Referências

- [SAD v1.2](../SAD/docs/sad.md)
- [ADR-003: Cloud-Agnostic](../SAD/docs/adrs/adr-003-cloud-agnostic.md)
- [ADR-004: IaC e GitOps](../SAD/docs/adrs/adr-004-iac-gitops.md)
- [ADR-020: Provisionamento de Clusters](../SAD/docs/adrs/adr-020-provisionamento-clusters.md)
- [ADR-021: Escolha do Orquestrador](../SAD/docs/adrs/adr-021-orquestrador-containers.md)
- [Cloud Architect Azure](../docs/agents/cloud-architect-azure.md)
- [Cloud Architect AWS](../docs/agents/cloud-architect-aws.md)
- [Cloud Architect GCP](../docs/agents/cloud-architect-gcp.md)
- [CTO Analysis](../docs/agents/cto.md)

---

## 🎯 Status Atual

| Cloud | Status | Prioridade | Custo Mensal |
|-------|--------|-----------|--------------|
| **Azure** | 🔄 Em construção | 🔴 Alta (recomendado CTO) | $615.12 |
| **AWS** | ⏸️ Planejado | 🟡 Média (alternativa) | $599.30 |
| **GCP** | ⏸️ Planejado | 🟢 Baixa | $837.11 |

**Próximo Passo**: Implementar `/platform-provisioning/azure/kubernetes/terraform/`
