# ADR 004 – Re-validação contra SAD v1.1

## Contexto
O SAD foi descongelado e atualizado (v1.0 → v1.1) com diretrizes práticas de implementação cloud-agnostic baseadas na primeira validação deste domínio.

**Data**: 2026-01-05
**SAD Referência**: `/SAD/docs/sad.md` v1.1 (descongelado)
**Mudanças Principais**: ADR-020 (Provisionamento de Clusters), atualizações em ADR-003 e ADR-004

---

## O que Mudou no SAD v1.1

### Novas Diretrizes
1. **ADR-020**: Provisionamento de Clusters e Escopo de Domínios
   - Clusters provisionados EXTERNAMENTE aos domínios
   - Domínios assumem cluster existente
   - Storage classes parametrizadas obrigatórias
   - Object storage S3-compatible
   - Terraform nos domínios: apenas providers `kubernetes`, `helm`, `kubectl`

2. **ADR-003 Atualizado**: Diretrizes práticas cloud-agnostic
   - Separação `/platform-provisioning` vs `/domains`
   - Proibido hardcoding de storage classes
   - Parametrização obrigatória

3. **ADR-004 Atualizado**: Escopo de IaC clarificado
   - Platform provisioning: cloud-specific permitido
   - Domain provisioning: apenas K8s nativo

---

## Re-validação do Domínio Observability

### Status Anterior (Validação #1 - ADR-003)
❌ **VIOLAÇÃO CRÍTICA**: Terraform AWS-específico (EKS, IAM, S3)

### Status Atual (Re-validação #2 - contra SAD v1.1)

#### ✅ Agora ACEITO pelo SAD v1.1

**Justificativa**: Com ADR-020, o escopo ficou claro:

1. **Terraform AWS-específico**: ✅ **ACEITO SE MOVIDO**
   - `modules/eks`, `modules/iam`, `modules/s3` devem ser movidos para `/platform-provisioning/aws/`
   - Domínio observability mantém apenas recursos Kubernetes nativos

2. **Storage Classes**: ⚠️ **REQUER PARAMETRIZAÇÃO**
   - Atual: `storageClassName: gp2` (hardcoded)
   - Requerido: `storageClassName: {{ .Values.storageClass }}`
   - **Ação**: Atualizar Helm values

3. **Object Storage (S3)**: ⚠️ **REQUER PARAMETRIZAÇÃO**
   - Atual: Referências S3 hardcoded
   - Requerido: Endpoint parametrizado S3-compatible
   - **Ação**: Variáveis para endpoint, bucket, credenciais

4. **Terraform Providers**: ⚠️ **REQUER REFATORAÇÃO**
   - Atual: Usa providers `aws`
   - Requerido: Apenas `kubernetes`, `helm`, `kubectl`
   - **Ação**: Separar em `/platform-provisioning` vs `/domains/observability`

---

## Decisão Final (Re-validação #2)

### ✅ APROVADO COM PLANO DE REFATORAÇÃO

O domínio observability está **APROVADO** com entendimento de que:

1. **Terraform cloud-specific não é mais violação** se movido para `/platform-provisioning`
2. **Domínio precisa refatoração** para seguir novo escopo do ADR-020
3. **Plano de refatoração claro** foi estabelecido

---

## Plano de Refatoração (Priorizado)

### Fase 1: Reestruturação de IaC (Prioridade ALTA)

#### 1.1 Criar `/platform-provisioning/aws/observability`
```bash
mkdir -p platform-provisioning/aws/observability
mv domains/observability/infra/terraform/modules/eks platform-provisioning/aws/observability/
mv domains/observability/infra/terraform/modules/iam platform-provisioning/aws/observability/
mv domains/observability/infra/terraform/modules/s3 platform-provisioning/aws/observability/
```

#### 1.2 Refatorar `/domains/observability/infra/terraform`
**Antes**:
```hcl
# main.tf
provider "aws" { ... }
module "eks" { ... }
module "iam" { ... }
module "s3" { ... }
```

**Depois**:
```hcl
# main.tf
terraform {
  required_providers {
    kubernetes = { ... }
    helm = { ... }
    kubectl = { ... }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

resource "kubernetes_namespace" "observability" {
  metadata {
    name = "k8s-observability"
  }
}

# RBAC, Services, PVCs parametrizados
```

**Inputs esperados** (do platform provisioning):
```hcl
variable "kubeconfig_path" {
  description = "Path to kubeconfig (from platform provisioning)"
}

variable "storage_class_name" {
  description = "Storage class for PVCs (gp3, pd-standard, etc)"
  default     = ""
}

variable "object_storage_endpoint" {
  description = "S3-compatible endpoint"
}

variable "object_storage_bucket_loki" {
  description = "Bucket for Loki (created externally)"
}

variable "object_storage_bucket_tempo" {
  description = "Bucket for Tempo (created externally)"
}
```

---

### Fase 2: Parametrizar Storage Classes (Prioridade ALTA)

#### 2.1 Atualizar Helm Values
**kube-prometheus-stack/values.yaml**:
```yaml
# Antes
storageClassName: gp2

# Depois
storageClassName: {{ .Values.global.storageClass | default "" }}
```

**Criar values por cloud**:
```yaml
# values-aws.yaml
global:
  storageClass: gp3

# values-gcp.yaml
global:
  storageClass: pd-standard

# values-azure.yaml
global:
  storageClass: managed-premium

# values-local.yaml
global:
  storageClass: local-path
```

#### 2.2 Atualizar Loki, Tempo
Mesma abordagem para todos os charts com PVCs.

---

### Fase 3: Parametrizar Object Storage (Prioridade MÉDIA)

#### 3.1 Loki Values
```yaml
# values.yaml
loki:
  storage:
    type: s3
    s3:
      endpoint: {{ .Values.objectStorage.endpoint }}
      bucketnames: {{ .Values.objectStorage.bucketLoki }}
      region: {{ .Values.objectStorage.region }}
      # Credentials from External Secret

# values-aws.yaml
objectStorage:
  endpoint: s3.us-east-1.amazonaws.com
  region: us-east-1
  bucketLoki: observability-loki-prod

# values-minio.yaml (local/on-prem)
objectStorage:
  endpoint: minio.k8s-observability.svc.cluster.local:9000
  region: us-east-1  # Fake para MinIO
  bucketLoki: loki-data
```

#### 3.2 Tempo, Prometheus (long-term)
Mesma abordagem.

---

### Fase 4: Documentação Multi-Cloud (Prioridade BAIXA)

#### 4.1 Atualizar README
```markdown
## Deploy

### AWS
1. Provision platform: `cd platform-provisioning/aws/observability && terraform apply`
2. Deploy domain: `cd domains/observability/infra/terraform && terraform apply -var="kubeconfig_path=~/.kube/config" -var="storage_class_name=gp3"`

### GCP
1. Provision platform: `cd platform-provisioning/gcp/observability && terraform apply`
2. Deploy domain: `cd domains/observability/infra/terraform && terraform apply -var="storage_class_name=pd-standard"`

### Local (Docker Desktop + MinIO)
1. Deploy domain: `cd domains/observability/infra/terraform && terraform apply -var="storage_class_name=hostpath"`
```

---

## Validação Pós-Refatoração

### Checklist ADR-020
- [ ] `/platform-provisioning/aws/observability` criado com módulos cloud-specific
- [ ] `/domains/observability/infra/terraform` usa APENAS providers K8s
- [ ] Storage classes parametrizadas (variável `storage_class_name`)
- [ ] Object storage endpoint parametrizado
- [ ] Namespace renomeado: `observability` → `k8s-observability`
- [ ] README documenta deploy em AWS/GCP/Azure/local
- [ ] RBAC explícito criado
- [ ] Network Policies criadas
- [ ] Resource Quotas definidas

### Architect Guardian Scan
```bash
# Deve retornar vazio
grep -r "aws_\|google_\|azurerm_" domains/observability/infra/terraform/
```

---

## Resumo das Mudanças v1.0 → v1.1

| Aspecto | ADR-003 (v1.0) | ADR-004 (v1.1) | Status |
|---------|----------------|----------------|--------|
| **Terraform AWS-específico** | ❌ VIOLAÇÃO | ✅ ACEITO (se em `/platform-provisioning`) | Refatoração planejada |
| **Storage Classes** | ⚠️ Implícito | ✅ Diretrizes claras (parametrização) | Implementação pendente |
| **Object Storage** | ⚠️ Não definido | ✅ S3-compatible obrigatório | Implementação pendente |
| **Escopo de Domínios** | ❌ Confuso | ✅ Claramente definido (ADR-020) | Documentado |

---

## Consequências

### Positivas ✅
1. **Clareza Arquitetural**: Escopo de cloud-agnostic agora está claro
2. **Terraform Não É Vilão**: Cloud-specific permitido em contexto correto
3. **Plano Executável**: Refatoração tem passos claros e priorizados
4. **Validação Futura**: Template para validar novos domínios

### Negativas ⚠️
1. **Refatoração Significativa**: Domínio requer reestruturação de IaC
2. **Dependência de Platform**: Domínios dependem de `/platform-provisioning`

### Mitigações
- Refatoração incremental (fase 1 → fase 4)
- Ambiente local continua funcional durante refatoração
- Platform provisioning pode ser criado gradualmente

---

## Decisão Final

**APROVADO** ✅

O domínio observability está **APROVADO COM PLANO DE REFATORAÇÃO CLARA**.

**Razão**: O SAD v1.1 esclareceu que:
- Terraform cloud-specific não é violação se separado corretamente
- Domínio tem stack técnico correto
- Plano de refatoração é executável e priorizado

**Próximos Passos**:
1. Recongelar SAD v1.1 (Freeze #2)
2. Iniciar refatoração do domínio (opcional, não bloqueador para FASE 2)
3. Criar template de domínio cloud-agnostic baseado nas diretrizes

---

## Referências
- `/SAD/docs/sad.md` v1.1
- `/SAD/docs/adrs/adr-020-provisionamento-clusters.md`
- `/SAD/docs/adrs/adr-003-cloud-agnostic.md` (atualizado)
- `/SAD/docs/adrs/adr-004-iac-gitops.md` (atualizado)
- ADR-003 (primeira validação)
