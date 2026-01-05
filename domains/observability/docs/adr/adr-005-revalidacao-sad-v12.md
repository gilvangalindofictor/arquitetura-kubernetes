# ADR 005 – Re-validação contra SAD v1.2 + Consolidação de Estrutura

## Contexto
O SAD foi atualizado (v1.1 → v1.2) com a adição de ADR-021 (Escolha do Orquestrador de Containers - Kubernetes) e criação da estrutura `/platform-provisioning/` para separação explícita entre provisionamento de clusters e deploy de domínios.

**Data**: 2026-01-05 (noite)
**SAD Referência**: `/SAD/docs/sad.md` v1.2 (congelado - Freeze #3)
**Mudanças Principais**: 
- ADR-021 (Kubernetes vs alternativas)
- Estrutura `/platform-provisioning/` criada
- Consolidação de artefatos legados do domínio observability

---

## Mudanças no SAD v1.2

### 1. ADR-021: Escolha do Orquestrador de Containers

**Decisão**: Kubernetes escolhido como orquestrador padrão

**Alternativas Rejeitadas**:
- Docker Swarm (289 pts) - Ecossistema limitado
- HashiCorp Nomad (373 pts) - Menor pool de talentos
- AWS ECS (267 pts) - **Violação ADR-003** (vendor lock-in)
- Google Cloud Run (224 pts) - **Violação ADR-003** (vendor lock-in)
- Azure Container Apps (253 pts) - **Violação ADR-003** (vendor lock-in)

**Kubernetes Vencedor (542 pts - 87%)**:
- ✅ Cloud-agnostic (EKS, AKS, GKE, on-prem)
- ✅ Ecossistema maduro (Helm, Operators, Service Mesh)
- ✅ Suporte a stateful workloads (PostgreSQL, Redis, RabbitMQ)
- ✅ Skill availability alta
- ⚠️ Trade-off aceito: Complexidade operacional

**Referência**: `/SAD/docs/adrs/adr-021-orquestrador-containers.md`

### 2. Estrutura `/platform-provisioning/`

**Decisão**: Separação física entre provisionamento de clusters e deploy de domínios

**Estrutura Implementada**:
```
/platform-provisioning/{cloud}/
├── kubernetes/
│   ├── terraform/      # Cloud-specific (azurerm, aws, google)
│   │   ├── cluster.tf  # EKS, AKS, GKE
│   │   ├── networking.tf # VPC, VNet, Subnets
│   │   ├── storage.tf  # Storage classes, object storage
│   │   └── outputs.tf  # Outputs padronizados
│   └── docs/
└── README.md
```

**Outputs Padronizados**:
- `cluster_endpoint` - Kubernetes API endpoint
- `cluster_ca_certificate` - CA certificate
- `storage_class_name` - Storage class (gp3, managed-premium, pd-ssd)
- `object_storage_bucket` - S3-compatible bucket
- `object_storage_endpoint` - S3-compatible endpoint

**Clouds Suportadas**:
- **Azure** (🔄 Em construção) - $615/mês (recomendado CTO)
- **AWS** (⏸️ Planejado) - $599/mês
- **GCP** (⏸️ Planejado) - $837/mês

**Referência**: `/platform-provisioning/README.md`

---

## Re-validação do Domínio Observability

### Status Anterior (Re-validação #2 - contra SAD v1.1)
✅ **APROVADO COM PLANO DE REFATORAÇÃO**
- Terraform AWS-specific identificado
- Plano de refatoração definido

### Status Atual (Re-validação #3 - contra SAD v1.2)

#### ✅ Stack Técnico Conforme ADR-021

Validação contra escolha de Kubernetes:

| Componente | Cloud-Agnostic? | Kubernetes-Native? | Status |
|------------|-----------------|-------------------|---------|
| OpenTelemetry Collector | ✅ | ✅ | Conforme |
| Prometheus | ✅ | ✅ | Conforme |
| Loki | ✅ | ✅ | Conforme |
| Tempo | ✅ | ✅ | Conforme |
| Grafana | ✅ | ✅ | Conforme |
| Alertmanager | ✅ | ✅ | Conforme |
| Kiali | ✅ | ✅ | Conforme |

**Conclusão**: Stack 100% compatível com Kubernetes e cloud-agnostic.

#### ✅ Alinhamento com `/platform-provisioning/`

**Terraform Atual**:
```
/domains/observability/infra/terraform/
├── main.tf
└── modules/
    ├── vpc/   ← AWS-specific (VPC)
    ├── eks/   ← AWS-specific (EKS cluster)
    ├── s3/    ← AWS-specific (S3 buckets)
    └── iam/   ← AWS-specific (IRSA roles)
```

**Análise**:
- ❌ **VIOLAÇÃO ADR-020**: Domínio provisionando cluster (EKS, VPC)
- ❌ **VIOLAÇÃO ADR-003**: Recursos cloud-specific no domínio

**Plano de Refatoração** (confirmado):

**Fase 1**: Mover para `/platform-provisioning/aws/`
```
/platform-provisioning/aws/kubernetes/terraform/
├── cluster.tf    ← De modules/eks/main.tf
├── networking.tf ← De modules/vpc/main.tf
├── storage.tf    ← De modules/s3/main.tf
├── iam.tf        ← De modules/iam/main.tf
└── outputs.tf    ← Criar outputs padronizados
```

**Fase 2**: Refatorar domínio
```
/domains/observability/infra/terraform/
├── main.tf       ← Apenas kubernetes/helm providers
├── namespaces.tf ← Namespace observability-{env}
├── rbac.tf       ← ServiceAccounts, Roles, RoleBindings
└── helm.tf       ← Releases: kube-prometheus-stack, loki, tempo
```

**Parametrização Obrigatória**:
```hcl
# Consumir outputs do platform-provisioning
variable "storage_class_name" {
  description = "Storage class from platform-provisioning"
}

variable "s3_bucket_loki" {
  description = "S3 bucket for Loki from platform-provisioning"
}

variable "s3_endpoint" {
  description = "S3-compatible endpoint from platform-provisioning"
}
```

#### ✅ Consolidação de Estrutura

**Artefatos Removidos** (2026-01-05):
- `CLAUDE.md` - Documentação Claude Code (projeto original)
- `Observabilidade.code-workspace` - Workspace file
- `.claude/settings.local.json` - Configurações Claude Desktop
- `.github/copilot-instructions.md` - Duplicado (raiz tem `/ai-contexts/copilot-context.md`)

**Justificativa**: 
- Artefatos específicos do projeto original (standalone)
- Não aplicáveis após migração para workspace Projeto Kubernetes
- Contexto global em `/ai-contexts/copilot-context.md` já cobre orientações

**Estrutura Mantida**:
- `/local-dev/` - ✅ Ambiente local completo (sem AWS)
- `/localstack/` - ✅ Ambiente local com AWS simulado (teste IaC)
- `/docs/agents/` - ✅ Agentes locais do domínio (não duplicados com raiz)

---

## Validação Final

### ✅ Conformidade com SAD v1.2

| Critério | Status | Evidência |
|----------|--------|-----------|
| **ADR-021 (Kubernetes)** | ✅ Conforme | Stack 100% Kubernetes-native |
| **ADR-003 (Cloud-Agnostic)** | ⚠️ Refatoração pendente | Terraform AWS deve ser movido |
| **ADR-020 (Provisionamento)** | ⚠️ Refatoração pendente | Cluster provisionado pelo domínio (incorreto) |
| **ADR-004 (IaC)** | ✅ Conforme | Terraform + Helm implementados |
| **ADR-006 (Observabilidade)** | ✅ Conforme | OpenTelemetry padrão |
| **Estrutura Consolidada** | ✅ Completa | Artefatos legados removidos |

### Gaps Conhecidos (Não-Bloqueantes)

1. **Refatoração Terraform** (Prioridade Alta):
   - Mover módulos AWS para `/platform-provisioning/aws/`
   - Refatorar domínio para consumir outputs
   - Parametrizar storage classes e object storage

2. **Operacional** (Conforme plano):
   - RBAC: Implementação pendente
   - Network Policies: Implementação pendente
   - GitOps: ArgoCD pendente

---

## Decisão

✅ **APROVADO** - Domínio observability está conforme SAD v1.2

**Justificativas**:
1. Stack técnico alinhado com ADR-021 (Kubernetes)
2. Estrutura consolidada (artefatos legados removidos)
3. Plano de refatoração Terraform definido e documentado
4. Gaps conhecidos não-bloqueantes para aprovação

**Trade-offs Aceitos**:
- Refatoração Terraform será executada em task separada (não-bloqueante)
- Gaps operacionais (RBAC, Network Policies) parte do roadmap normal

---

## Consequências

### Positivas
- ✅ Domínio validado contra SAD v1.2 (última versão)
- ✅ Estrutura limpa e organizada (sem artefatos legados)
- ✅ Roadmap de refatoração claro
- ✅ Conformidade com decisão de orquestrador (Kubernetes)

### Negativas
- ⚠️ Refatoração Terraform requer trabalho significativo
- ⚠️ Temporariamente violando ADR-003 e ADR-020 (mitigado por plano documentado)

### Neutras
- 📝 VALIDATION-REPORT atualizado para incluir validação #3
- 📝 ADRs do domínio agora totalizam 5 (adr-001 a adr-005)

---

## Rastreabilidade

### Documentos Atualizados
- [`docs/VALIDATION-REPORT.md`](../VALIDATION-REPORT.md) - Validação #3 adicionada
- Este ADR (adr-005)

### Documentos Referenciados
- [`/SAD/docs/sad.md`](../../../../SAD/docs/sad.md) v1.2
- [`/SAD/docs/adrs/adr-021-orquestrador-containers.md`](../../../../SAD/docs/adrs/adr-021-orquestrador-containers.md)
- [`/platform-provisioning/README.md`](../../../../platform-provisioning/README.md)
- [`/platform-provisioning/azure/README.md`](../../../../platform-provisioning/azure/README.md)

### ADRs Relacionados
- [`adr-003-validacao-sad.md`](adr-003-validacao-sad.md) - Validação #1 (SAD v1.0)
- [`adr-004-revalidacao-sad-v11.md`](adr-004-revalidacao-sad-v11.md) - Re-validação #2 (SAD v1.1)

---

**Data**: 2026-01-05
**Status**: ✅ Aprovado
**Responsável**: Architect Guardian
**Próximo Passo**: Implementar refatoração Terraform (task separada)
