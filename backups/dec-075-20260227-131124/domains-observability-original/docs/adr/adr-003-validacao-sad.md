# ADR 003 – Validação contra SAD Corporativo

## Contexto
O domínio **observability** foi migrado do projeto independente antes da criação do SAD (Software Architecture Document) corporativo v1.0. É necessário validar a aderência aos princípios arquiteturais sistêmicos e identificar gaps que violam o SAD.

**Data de Validação**: 2026-01-05
**SAD Referência**: `/SAD/docs/sad.md` v1.0 (congelado)

---

## Validação Realizada

### ✅ Conformidades

#### 1. OpenTelemetry como Padrão Único (ADR-006)
**Status**: **CONFORME**
- OpenTelemetry Collector implementado como gateway central
- Recebe OTLP via gRPC (4317) e HTTP (4318)
- Exporta para Prometheus, Loki e Tempo
- Arquitetura alinhada com o SAD

#### 2. Contratos entre Domínios
**Status**: **CONFORME**
- Domínio expõe interfaces conforme `/SAD/docs/architecture/domain-contracts.md`:
  - OpenTelemetry gRPC: porta 4317 (métricas, logs, traces)
  - Loki HTTP API: porta 80 (logs)
  - Tempo gRPC: porta 4317 (traces)
  - Grafana HTTP: porta 80 (dashboards)
  - Alertmanager API: porta 9093 (alertas)
- SLA target: 99.9% uptime

---

### ⚠️ Gaps Identificados

#### 1. Cloud-Agnostic OBRIGATÓRIO (ADR-003) — **VIOLAÇÃO CRÍTICA**
**Status**: **NÃO CONFORME** ❌

**Problemas**:
- Terraform usa recursos AWS-específicos:
  - `aws_eks_cluster` (EKS)
  - `aws_iam_role`, `aws_iam_policy` (IAM/IRSA)
  - `aws_s3_bucket` (S3)
- Storage class hardcoded: `gp2` (AWS EBS)
- Documentação assume apenas AWS

**Impacto**: Impossível migrar para GKE, AKS ou on-premises sem reescrever IaC

**Ação Corretiva Obrigatória**:
1. Refatorar Terraform para módulos cloud-agnostic:
   - Remover recursos EKS/ECS específicos
   - Usar apenas recursos Kubernetes nativos
   - Substituir S3 por object storage genérico (MinIO, AWS S3, GCS, Azure Blob)
2. Substituir `storageClassName: gp2` por variável parametrizada
3. Criar módulos reutilizáveis para diferentes clouds
4. Atualizar documentação para multi-cloud

**Referência SAD**: ADR-003, ADR-004

---

#### 2. Isolamento de Domínios (ADR-005) — **PARCIALMENTE CONFORME**
**Status**: **GAPS IDENTIFICADOS** ⚠️

**Conformidades**:
- ✅ ServiceAccounts criadas nos Helm charts
- ✅ Separação por namespace (observability)

**Gaps**:
- ❌ Namespace divergente: usa `observability` vs padrão SAD `k8s-observability`
- ❌ RBAC explícito não definido (Roles, RoleBindings)
- ❌ Network Policies ausentes (deny-all por padrão)
- ❌ Service Mesh não implementado (Linkerd sidecar injection)
- ❌ Resource Quotas não definidas

**Ação Corretiva**:
1. Renomear namespace para `k8s-observability`
2. Criar RBAC explícito:
   - Roles para Prometheus (list/get pods, servicemonitors)
   - Roles para Loki (read logs)
   - RoleBindings para ServiceAccounts
3. Implementar Network Policies:
   - Deny-all por padrão
   - Allow específicos para OTEL Collector → Prometheus/Loki/Tempo
   - Allow Grafana → datasources
4. Adicionar anotações para Service Mesh injection
5. Definir Resource Quotas por namespace

**Referência SAD**: ADR-005, ADR-007

---

#### 3. IaC e GitOps (ADR-004) — **PARCIALMENTE CONFORME**
**Status**: **GAPS IDENTIFICADOS** ⚠️

**Conformidades**:
- ✅ Terraform para IaC
- ✅ Helm charts para deploy Kubernetes

**Gaps**:
- ❌ ArgoCD não implementado (GitOps ausente)
- ❌ Drift detection não configurada
- ❌ CI/CD pipeline ausente
- ❌ Terraform state não gerenciado (backend local)

**Ação Corretiva**:
1. Integrar com ArgoCD (FASE 2 - após cicd-platform)
2. Configurar Terraform remote state (S3 + DynamoDB ou equivalente cloud-agnostic)
3. Implementar drift detection via ArgoCD
4. Criar pipeline CI/CD (validação Terraform, lint Helm)

**Referência SAD**: ADR-004

---

#### 4. Documentação e Rastreabilidade
**Status**: **GAPS IDENTIFICADOS** ⚠️

**Gaps**:
- ❌ ADRs locais não referenciam o SAD corporativo
- ❌ README não menciona princípios arquiteturais sistêmicos
- ❌ Contexto não atualizado com contratos entre domínios
- ❌ Falta referência ao Architect Guardian

**Ação Corretiva**:
1. Atualizar ADR-001 e ADR-002 com referências ao SAD
2. Adicionar seção "Conformidade com SAD" no README
3. Documentar dependências de platform-core (Service Mesh futuro)

---

## Resumo das Ações Corretivas

### Prioridade CRÍTICA (Bloqueador)
1. **Refatorar Terraform para cloud-agnostic** (ADR-003 violation)
   - Prazo: Antes de qualquer deploy em produção
   - Responsável: Arquiteto + SRE

### Prioridade ALTA
2. **Implementar RBAC e Network Policies** (ADR-005)
   - Prazo: FASE 2
3. **Integrar ArgoCD/GitOps** (ADR-004)
   - Prazo: Após cicd-platform (FASE 2)
4. **Padronizar namespace para k8s-observability**
   - Prazo: FASE 2

### Prioridade MÉDIA
5. **Atualizar documentação com referências ao SAD**
   - Prazo: FASE 2
6. **Implementar Service Mesh integration**
   - Prazo: Após platform-core (FASE 2)

---

## Decisão

**Domínio observability é APROVADO CONDICIONALMENTE** para FASE 2 com as seguintes condições:

1. ✅ Stack técnico está correto (OpenTelemetry, Prometheus, Loki, Tempo, Grafana)
2. ✅ Contratos entre domínios estão alinhados
3. ❌ **BLOQUEADOR**: Terraform deve ser refatorado para cloud-agnostic antes de produção
4. ⚠️ RBAC, Network Policies e GitOps devem ser implementados na FASE 2

**Recomendação**: Iniciar FASE 2 com correções incrementais enquanto mantém ambiente local funcional.

---

## Consequências

### Curto Prazo
- Domínio pode ser usado para PoC e desenvolvimento local
- Terraform atual serve como referência mas não vai para produção

### Médio Prazo
- Refatoração cloud-agnostic habilita multi-cloud
- RBAC e Network Policies aumentam segurança
- GitOps via ArgoCD automatiza deploys

### Longo Prazo
- Plataforma portável entre clouds
- Redução de vendor lock-in
- Conformidade total com SAD

---

## Referências
- `/SAD/docs/sad.md` (v1.0)
- `/SAD/docs/adrs/adr-003-cloud-agnostic.md`
- `/SAD/docs/adrs/adr-004-iac-gitops.md`
- `/SAD/docs/adrs/adr-005-seguranca-sistemica.md`
- `/SAD/docs/adrs/adr-006-observabilidade-transversal.md`
- `/SAD/docs/architecture/domain-contracts.md`
