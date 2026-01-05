# ADR-020: Provisionamento de Clusters e Escopo de Domínios

> **Status**: Proposto
> **Data**: 2026-01-05
> **Contexto**: Validação do domínio observability revelou necessidade de esclarecer escopo cloud-agnostic
> **Decisores**: Architect Guardian, CTO

---

## Contexto

A validação do domínio **observability** contra o SAD v1.0 identificou uma **violação crítica**: Terraform usando recursos AWS-específicos (EKS, IAM, S3), violando o princípio Cloud-Agnostic Obrigatório (ADR-003).

**Problema**: O SAD v1.0 estabelece "cloud-agnostic obrigatório" mas não fornece diretrizes claras sobre:
1. Quem provisiona os clusters Kubernetes?
2. O que os domínios podem/devem provisionar?
3. Como lidar com storage classes cloud-específicas?
4. Como abstrair object storage (S3/GCS/Azure Blob)?

**Necessidade**: Estabelecer escopo claro e diretrizes práticas para implementação cloud-agnostic.

---

## Decisão

### 1. Separação de Responsabilidades

#### Clusters Kubernetes: Provisionados EXTERNAMENTE
**Responsável**: Equipe de Platform Engineering / Infraestrutura

**Escopo**:
- Provisionamento de clusters Kubernetes (EKS, GKE, AKS, on-premises)
- VPC/Networking base
- IAM/RBAC base do cluster
- Storage classes instaladas
- Ingress controller base
- **Localização**: `/platform-provisioning` (fora de `/domains`)

**Terraform Separado**:
```hcl
# platform-provisioning/aws/main.tf
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  ...
}

# platform-provisioning/gcp/main.tf
module "gke" {
  source = "terraform-google-modules/kubernetes-engine/google"
  ...
}

# platform-provisioning/azure/main.tf
module "aks" {
  source = "Azure/aks/azurerm"
  ...
}
```

**Output**: Kubeconfig, storage classes disponíveis, endpoints

---

#### Domínios: Assumem Cluster Existente
**Responsável**: Equipes de domínio

**Escopo PERMITIDO** (Cloud-Agnostic):
- Namespaces Kubernetes
- RBAC (Roles, RoleBindings, ServiceAccounts)
- Services, Deployments, StatefulSets
- ConfigMaps, Secrets (referências, não valores)
- Network Policies
- PersistentVolumeClaims (usando storage class parametrizada)
- Helm charts
- ArgoCD Applications

**Escopo PROIBIDO** (Cloud-Specific):
- ❌ Provisionamento de clusters (EKS, GKE, AKS)
- ❌ IAM roles/policies cloud-específicas
- ❌ VPCs, Subnets, Security Groups
- ❌ Storage classes (usar as provisionadas)
- ❌ Load Balancers cloud-específicos
- ❌ Serviços gerenciados (RDS, CloudSQL, etc.)

---

### 2. Storage Classes Parametrizadas

#### Princípio
Domínios NÃO hardcodam storage classes. Usam variáveis parametrizadas.

#### Implementação Helm
```yaml
# values.yaml
storageClass: ""  # Vazio = default do cluster

# values-aws.yaml
storageClass: "gp3"

# values-gcp.yaml
storageClass: "pd-standard"

# values-azure.yaml
storageClass: "managed-premium"

# values-onprem.yaml
storageClass: "local-path"
```

#### Implementação Terraform
```hcl
variable "storage_class_name" {
  description = "Storage class for PVCs (provisioned externally)"
  type        = string
  default     = ""  # Empty = use cluster default
}

resource "kubernetes_persistent_volume_claim" "data" {
  metadata {
    name      = "app-data"
    namespace = var.namespace
  }
  spec {
    storage_class_name = var.storage_class_name
    access_modes       = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}
```

**Deploy por Cloud**:
```bash
# AWS
terraform apply -var="storage_class_name=gp3"

# GCP
terraform apply -var="storage_class_name=pd-standard"

# Azure
terraform apply -var="storage_class_name=managed-premium"
```

---

### 3. Object Storage Genérico (S3-Compatible)

#### Princípio
Usar abstração S3-compatible para logs, backups, traces de longo prazo.

#### Opções por Cloud

| Provider | Storage | Endpoint | Auth |
|----------|---------|----------|------|
| **AWS** | S3 | `s3.amazonaws.com` | IAM IRSA |
| **GCP** | GCS (S3 API) | `storage.googleapis.com` | Workload Identity |
| **Azure** | Blob (S3 API via gateway) | Custom | Managed Identity |
| **On-Prem** | MinIO | `minio.domain.local` | Access Key |
| **Local Dev** | MinIO (Docker) | `localhost:9000` | minioadmin |

#### Implementação Loki (exemplo)
```yaml
# Helm values.yaml
loki:
  storage:
    type: s3
    s3:
      endpoint: ""           # Parametrizado
      bucketnames: loki-data
      region: ""             # Parametrizado
      access_key_id: ""      # From secret
      secret_access_key: ""  # From secret
      insecure: false

# values-aws.yaml
loki:
  storage:
    s3:
      endpoint: s3.us-east-1.amazonaws.com
      region: us-east-1

# values-minio.yaml (local/on-prem)
loki:
  storage:
    s3:
      endpoint: minio.observability.svc.cluster.local:9000
      region: us-east-1  # Fake para MinIO
      insecure: true
```

#### Terraform Approach
```hcl
variable "object_storage_endpoint" {
  description = "S3-compatible endpoint (provisioned externally)"
  type        = string
}

variable "object_storage_bucket" {
  description = "Bucket name for domain storage"
  type        = string
}

# Domínio NÃO cria bucket, apenas usa
data "kubernetes_secret" "storage_credentials" {
  metadata {
    name      = "object-storage-credentials"
    namespace = var.namespace
  }
}
```

**Bucket criado externamente** em `/platform-provisioning`:
```hcl
# AWS
resource "aws_s3_bucket" "loki" {
  bucket = "observability-loki-${var.environment}"
}

# GCP
resource "google_storage_bucket" "loki" {
  name = "observability-loki-${var.environment}"
}

# MinIO (on-prem)
resource "minio_s3_bucket" "loki" {
  bucket = "observability-loki-${var.environment}"
}
```

---

### 4. Diretrizes de Terraform para Domínios

#### Estrutura Recomendada
```
/domains/{domain}/infra/terraform/
├── main.tf              # Provider kubernetes, helm
├── variables.tf         # Inputs parametrizados
├── namespaces.tf        # Kubernetes namespaces
├── rbac.tf              # Roles, RoleBindings, ServiceAccounts
├── network-policies.tf  # Network Policies
├── helm-releases.tf     # Helm deployments
└── outputs.tf           # Endpoints, URLs

# NÃO INCLUIR:
❌ modules/eks/
❌ modules/iam/
❌ modules/vpc/
❌ aws_*.tf
❌ google_*.tf
❌ azurerm_*.tf
```

#### Providers Permitidos
```hcl
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    # kubectl para CRDs
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# Provider configurado com kubeconfig externo
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}
```

#### Providers PROIBIDOS nos Domínios
```hcl
❌ provider "aws"
❌ provider "google"
❌ provider "azurerm"
❌ provider "azuread"
```

---

### 5. Secrets Management

#### Princípio
Domínios NÃO gerenciam secrets diretamente. Referenciam secrets provisionados externamente.

#### Opções

**Opção 1: External Secrets Operator (Recomendado)**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: loki-storage-credentials
  namespace: k8s-observability
spec:
  secretStoreRef:
    name: vault-backend  # Provisionado em secrets-management domain
    kind: SecretStore
  target:
    name: loki-storage-secret
  data:
    - secretKey: access_key_id
      remoteRef:
        key: observability/loki/s3
        property: access_key_id
```

**Opção 2: Sealed Secrets**
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: loki-storage-credentials
  namespace: k8s-observability
spec:
  encryptedData:
    access_key_id: AgB... # Encrypted
```

**Opção 3: IRSA/Workload Identity (Cloud-Specific)**
```yaml
# ServiceAccount com anotação cloud-specific
apiVersion: v1
kind: ServiceAccount
metadata:
  name: loki
  namespace: k8s-observability
  annotations:
    # AWS
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/loki-s3-access
    # GCP
    iam.gke.io/gcp-service-account: loki@PROJECT.iam.gserviceaccount.com
    # Azure
    azure.workload.identity/client-id: CLIENT_ID
```

**Nota**: Anotações cloud-specific são aceitáveis se gerenciadas por variáveis:
```yaml
annotations:
  {{ .Values.cloudProvider.annotations | toYaml }}
```

---

## Consequências

### Positivas ✅
1. **Clareza de Escopo**: Domínios sabem exatamente o que podem provisionar
2. **Portabilidade Real**: Domínios funcionam em qualquer cluster Kubernetes
3. **Separação de Responsabilidades**: Platform Engineering vs Domain Engineering
4. **Reutilização**: IaC de domínios reutilizável entre clouds
5. **Testabilidade**: Domínios testáveis localmente (Kind, Minikube, Docker Desktop)

### Negativas ⚠️
1. **Complexidade Inicial**: Requer setup de `/platform-provisioning` antes dos domínios
2. **Coordenação**: Equipes de domínio dependem de Platform Engineering para clusters
3. **Refatoração**: Domínio observability requer refatoração significativa

### Mitigações
- Documentar claramente em `/platform-provisioning/README.md`
- Criar scripts de bootstrap para cada cloud
- Fornecer templates Terraform para novos domínios

---

## Validação

### Checklist para Domínios Cloud-Agnostic
- [ ] Terraform usa APENAS providers `kubernetes`, `helm`, `kubectl`
- [ ] Storage classes parametrizadas por variável
- [ ] Object storage endpoint parametrizado
- [ ] Secrets referenciados, não criados inline
- [ ] Namespaces, RBAC, Network Policies usando APIs K8s nativas
- [ ] Helm charts com `values-{cloud}.yaml` separados
- [ ] README documenta deploy em múltiplas clouds
- [ ] CI/CD testa deploy em Kind/Minikube

### Architect Guardian Validation
```bash
# Scan para recursos cloud-specific
grep -r "aws_\|google_\|azurerm_" domains/*/infra/terraform/

# Deve retornar vazio (exit code 1)
```

---

## Implementação

### Fase 1: Criar `/platform-provisioning`
```bash
mkdir -p platform-provisioning/{aws,gcp,azure,on-premises}
```

### Fase 2: Refatorar Domínio Observability
- Remover `modules/eks`, `modules/iam`, `modules/s3`
- Parametrizar storage classes
- Documentar deploy multi-cloud

### Fase 3: Template para Novos Domínios
- Criar `domain-template/` com estrutura aprovada
- CI/CD validation obrigatória

---

## Referências

### ADRs Relacionados
- ADR-003: Cloud-Agnostic e Portabilidade
- ADR-004: IaC e GitOps
- ADR-009: Secrets Management

### Documentação Externa
- [Kubernetes Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [S3 API Compatibility](https://min.io/docs/minio/linux/integrations/aws-cli-with-minio.html)
- [External Secrets Operator](https://external-secrets.io/)
- [IRSA (AWS)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Workload Identity (GCP)](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)

---

## Aprovação

- [ ] Architect Guardian: Validado
- [ ] CTO: Aprovado
- [ ] Platform Engineering Lead: Aprovado
- [ ] Domínio Observability: Refatoração planejada
