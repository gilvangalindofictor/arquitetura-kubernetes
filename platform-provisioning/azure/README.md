# Platform Provisioning - Azure

> **Cloud**: Microsoft Azure  
> **Status**: 🔄 Em construção  
> **Custo Estimado**: $615.12/mês ($7,381.44/ano on-demand)  
> **Recomendação CTO**: ✅ Aprovado (balanced - custo competitivo + AKS control plane gratuito)

---

## 📋 Visão Geral

Este diretório contém **IaC para provisionar infraestrutura Azure** da Plataforma Corporativa Kubernetes.

**Serviços Provisionados**:
- Azure Kubernetes Service (AKS) - cluster gerenciado
- Azure VNet + Subnets (nodes, data services)
- Azure Load Balancer (Standard SKU)
- Azure DNS
- Azure Managed Disks (Premium SSD, Standard SSD)
- Azure Blob Storage (S3-compatible via HMAC)
- Azure Key Vault
- Azure Container Registry (ACR)

---

## 🏗️ Estrutura

```
azure/
├── kubernetes/
│   ├── terraform/
│   │   ├── provider.tf       # Provider azurerm
│   │   ├── aks.tf            # AKS cluster
│   │   ├── vnet.tf           # VNet, Subnets, NSGs
│   │   ├── storage.tf        # Storage classes, Blob Storage
│   │   ├── acr.tf            # Azure Container Registry
│   │   ├── keyvault.tf       # Key Vault
│   │   ├── outputs.tf        # Outputs para domínios
│   │   ├── variables.tf      # Variáveis
│   │   └── terraform.tfvars  # Valores (dev, hml, prd)
│   └── docs/
│       ├── architecture.md   # Arquitetura Azure
│       └── runbook.md        # Procedimentos operacionais
└── README.md
```

---

## 🚀 Quick Start

### Pré-requisitos

1. **Azure CLI** instalado e autenticado:
```bash
az login
az account set --subscription <subscription_id>
```

2. **Terraform** >= 1.6.0:
```bash
terraform version
```

3. **Kubectl** instalado (para validação):
```bash
kubectl version --client
```

### Provisionamento

```bash
# 1. Navegar para diretório Terraform
cd platform-provisioning/azure/kubernetes/terraform/

# 2. Inicializar Terraform
terraform init

# 3. Planejar (revisar mudanças)
terraform plan

# 4. Aplicar (provisionar infraestrutura)
terraform apply

# 5. Capturar outputs
terraform output -json > outputs.json

# 6. Configurar kubeconfig
az aks get-credentials --resource-group platform-rg --name platform-aks

# 7. Validar cluster
kubectl get nodes
kubectl get storageclasses
```

---

## 💰 Custo Detalhado

### Por Domínio

| Domínio | Custo Mensal (USD) | Componentes Principais |
|---------|-------------------|------------------------|
| Platform-Core | $63.53 | AKS (control plane $0), VMs, Load Balancer |
| CI/CD Platform | $145.00 | Managed Disks (750 GB), Azure Files, ACR |
| Observability | $87.00 | Blob Storage (Hot + Cool), Managed Disks |
| Data Services | $152.00 | PostgreSQL Flexible, Redis, Service Bus |
| Secrets Management | $0.59 | Key Vault |
| Security | $167.00 | Defender, Sentinel, Monitor Logs |
| **TOTAL** | **$615.12** | |

**Anual**: $7,381.44 (on-demand), $4,428.86 (Reserved Instances 3-year, -40%)

**Referência**: [Cloud Architect Azure](../../docs/agents/cloud-architect-azure.md)

---

## 🔌 Outputs Fornecidos

```hcl
output "cluster_endpoint" {
  description = "AKS Kubernetes API endpoint"
  value       = azurerm_kubernetes_cluster.aks.kube_config.0.host
}

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "cluster_ca_certificate" {
  description = "AKS cluster CA certificate"
  value       = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  sensitive   = true
}

output "storage_class_name" {
  description = "Default storage class (managed-premium)"
  value       = "managed-premium"
}

output "storage_class_standard" {
  description = "Standard storage class (managed)"
  value       = "managed"
}

output "blob_storage_account_name" {
  description = "Azure Blob Storage account name"
  value       = azurerm_storage_account.platform.name
}

output "blob_storage_endpoint" {
  description = "S3-compatible endpoint"
  value       = "https://${azurerm_storage_account.platform.name}.blob.core.windows.net"
}

output "acr_login_server" {
  description = "Azure Container Registry login server"
  value       = azurerm_container_registry.platform.login_server
}

output "key_vault_uri" {
  description = "Azure Key Vault URI"
  value       = azurerm_key_vault.platform.vault_uri
}
```

---

## 🛡️ Segurança

### Managed Identity
- AKS usa **System Assigned Managed Identity**
- Workload Identity habilitado para pods
- Sem credentials hardcoded

### Network Security
- NSGs configurados (allow 443, deny all by default)
- Private endpoints para Azure services (opcional)
- Network Policies habilitadas no AKS

### Secrets Management
- Azure Key Vault para secrets
- External Secrets Operator para injeção em pods
- Rotation automática habilitada

---

## 📊 Arquitetura

```
┌─────────────────────────────────────────────────┐
│           Azure Subscription                    │
│  ┌───────────────────────────────────────────┐ │
│  │  Resource Group: platform-rg              │ │
│  │                                           │ │
│  │  ┌────────────────────────────────────┐  │ │
│  │  │  VNet: platform-vnet (10.0.0.0/16) │  │ │
│  │  │                                     │  │ │
│  │  │  ┌──────────────────────────────┐  │  │ │
│  │  │  │ Subnet: aks-nodes           │  │ │ │
│  │  │  │ (10.0.1.0/24)               │  │ │ │
│  │  │  │                              │  │ │ │
│  │  │  │  [AKS Cluster]              │  │ │ │
│  │  │  │  - Control Plane (managed)  │  │ │ │
│  │  │  │  - Node Pool (3x B2s)       │  │ │ │
│  │  │  └──────────────────────────────┘  │ │ │
│  │  │                                     │ │ │
│  │  │  ┌──────────────────────────────┐  │ │ │
│  │  │  │ Subnet: data-services       │  │ │ │
│  │  │  │ (10.0.2.0/24)               │  │ │ │
│  │  │  │                              │  │ │ │
│  │  │  │  [PostgreSQL Flexible]      │  │ │ │
│  │  │  │  [Redis Cache]              │  │ │ │
│  │  │  │  [Service Bus]              │  │ │ │
│  │  │  └──────────────────────────────┘  │ │ │
│  │  └────────────────────────────────────┘  │ │
│  │                                           │ │
│  │  [Azure Load Balancer] ──> [AKS]         │ │
│  │  [Blob Storage] ◄──> [AKS]               │ │
│  │  [ACR] ◄──> [AKS]                        │ │
│  │  [Key Vault] ◄──> [AKS]                  │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

**Referência Visual**: [Cloud Architect Azure - Diagrama Mermaid](../../docs/agents/cloud-architect-azure.md#arquitetura-azure-mermaid)

---

## 🔄 Ciclo de Vida

### 1. Provisioning
```bash
terraform apply
```

### 2. Updates
```bash
terraform plan   # Revisar mudanças
terraform apply  # Aplicar mudanças
```

### 3. Scaling
```bash
# Editar terraform.tfvars
node_count = 5  # de 3 para 5

terraform apply
```

### 4. Backup
- **Terraform State**: Armazenado em Azure Storage Account (backend remoto)
- **Cluster**: Velero para backup/restore de recursos K8s

### 5. Disaster Recovery
- Multi-zone (3 availability zones)
- Regional replication (opcional, +100% custo)

---

## 🧪 Validação

### Cluster Health
```bash
kubectl get nodes
kubectl get pods -A
kubectl get storageclasses
```

### Network Connectivity
```bash
kubectl run test-pod --image=nginx --rm -it -- /bin/bash
# Dentro do pod:
curl https://kubernetes.default.svc
```

### Storage
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: managed-premium
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-pvc
kubectl delete pvc test-pvc
```

---

## 📚 Referências

- [Azure AKS Documentation](https://learn.microsoft.com/azure/aks/)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
- [AKS Best Practices](https://learn.microsoft.com/azure/aks/best-practices)
- [Cloud Architect Azure](../../docs/agents/cloud-architect-azure.md)
- [CTO Analysis](../../docs/agents/cto.md)
- [ADR-020: Provisionamento de Clusters](../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)
- [ADR-021: Escolha do Orquestrador](../../SAD/docs/adrs/adr-021-orquestrador-containers.md)

---

## 🎯 Status

- ⏳ **Terraform**: Em desenvolvimento
- ⏸️ **Docs**: Planejados (architecture.md, runbook.md)
- ⏸️ **Validação**: Pendente (após provisionamento)

**Próximo Passo**: Implementar `kubernetes/terraform/` com módulos AKS
