# ADR-005: Estratégia de Logging Centralizado

**Data:** 2026-01-26
**Status:** Accepted
**Autor:** DevOps Team
**Contexto:** Marco 2 - Fase 4 (Logging)

---

## Contexto

Durante o planejamento do Marco 2 - Fase 4 (Logging), identificamos **duas especificações conflitantes** sobre a solução de logging centralizado:

### Especificação 1: DEPLOY-CHECKLIST.md (Linha 316-319)

```markdown
### Fase 4: Fluent Bit + CloudWatch (Logging)
- Fluent Bit DaemonSet
- Log aggregation para CloudWatch Logs
- Dashboards de logs no Grafana
```

### Especificação 2: 04-observability-stack.md (Linhas 803-1075)

- **Loki** para logs (arquitetura completa de 270+ linhas)
- **OpenTelemetry Collector** para coleta
- **S3** como backend (retention 30 dias)
- Integração com Grafana e Tempo (correlação traces↔logs)

### Problema

A divergência entre as especificações pode causar:
- ❌ Incerteza sobre qual solução implementar
- ❌ Lock-in com AWS CloudWatch (viola princípio cloud-agnostic)
- ❌ Custos elevados ($55/mês CloudWatch vs $16/mês Loki)
- ❌ Perda de integração com stack de observabilidade (Prometheus, Tempo)

---

## Decisão

**Implementar Loki como solução primária de logging centralizado**, com as seguintes diretrizes:

### 1. Arquitetura de Logging

```
┌──────────────────────────────────────────────────────────┐
│              LOGGING ARCHITECTURE (Marco 2 Fase 4)        │
│                                                           │
│  ┌─────────────────────────────────────────────────┐    │
│  │     APPLICATION PODS (All Namespaces)            │    │
│  │           (stdout/stderr logs)                    │    │
│  └────────────────┬─────────────────────────────────┘    │
│                   │                                       │
│                   ▼                                       │
│  ┌──────────────────────────────────────────────┐        │
│  │         Fluent Bit DaemonSet                  │        │
│  │  • Parser: Docker JSON, CRI-O                 │        │
│  │  • Filter: Kubernetes metadata                │        │
│  │  • Output: Loki (primary)                     │        │
│  └────────────────┬─────────────────────────────┘        │
│                   │                                       │
│                   ▼                                       │
│  ┌──────────────────────────────────────────────┐        │
│  │            Loki (SimpleScalable)              │        │
│  │  • Read: 2 replicas                           │        │
│  │  • Write: 2 replicas                          │        │
│  │  • Backend: 2 replicas                        │        │
│  │  • Gateway: 2 replicas                        │        │
│  └────────────────┬─────────────────────────────┘        │
│                   │                                       │
│                   ▼                                       │
│  ┌──────────────────────────────────────────────┐        │
│  │          S3 Backend (IRSA)                    │        │
│  │  Bucket: k8s-platform-loki-{ACCOUNT_ID}      │        │
│  │  Retention: 30 days (lifecycle)               │        │
│  │  Cost: ~$11.50/month (500GB)                  │        │
│  └──────────────────────────────────────────────┘        │
│                                                           │
│  ┌──────────────────────────────────────────────┐        │
│  │         Grafana (Existing - Fase 3)           │        │
│  │  • Loki datasource (native integration)      │        │
│  │  • Log dashboards                             │        │
│  │  • Trace↔Log correlation (w/ Tempo)          │        │
│  └──────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│              CloudWatch (HOLD - Futuro)                   │
│  • Optional: Compliance/audit trail                      │
│  • Minimal mode: Critical logs only                      │
│  • Cost: +$6/month (if enabled)                          │
│  • Status: Documented, not implemented                   │
└──────────────────────────────────────────────────────────┘
```

### 2. Componentes a Implementar

| Componente | Função | Deployment |
|-----------|--------|-----------|
| **Loki** | Armazenamento de logs | Helm chart `grafana/loki` v5.42.0 via Terraform |
| **Fluent Bit** | Coletor de logs | Helm chart `fluent/fluent-bit` v0.43.0 via Terraform |
| **S3 Bucket** | Backend persistence | Terraform resource |
| **IAM Role (IRSA)** | Loki → S3 access | Terraform resource |
| **Grafana Datasource** | Visualização | Já configurado em Fase 3 |

### 3. CloudWatch: Hold (Não Implementar Agora)

**Status:** Documentado como opção futura, **não implementado** no Marco 2 Fase 4

**Rationale para Hold:**
- ✅ Loki atende 100% dos requisitos operacionais
- ✅ Economia de $396/ano vs CloudWatch-only
- ✅ Cloud-agnostic (facilita migração futura)
- ⏸️ CloudWatch pode ser adicionado depois se compliance/audit exigir

**Quando considerar CloudWatch:**
- Requisitos de compliance específicos (SOC2, PCI-DSS)
- Auditoria de logs por entidades externas
- Integração com ferramentas AWS-specific (CloudTrail, GuardDuty)

---

## Rationale

### Por que Loki sobre CloudWatch?

#### 1. **Cloud-Agnostic (Princípio Arquitetural)**

Alinhamento com documentação do projeto:

> **PROJECT-CONTEXT.md:** "Cloud-Agnostic onde possível: Redis e RabbitMQ via Helm (bitnami), não serviços gerenciados"

| Aspecto | Loki | CloudWatch |
|---------|------|-----------|
| Portabilidade | ✅ Roda em qualquer K8s (AWS, Azure, GCP, on-prem) | ❌ Lock-in AWS |
| Migração futura | ✅ Zero mudanças na aplicação | ❌ Requer refactor completo |
| Vendor neutrality | ✅ Open source (Apache 2.0) | ❌ Proprietary AWS |

**Impacto:** Se migrarmos para Azure/GCP no futuro, Loki funciona out-of-the-box. CloudWatch requer substituição total.

#### 2. **Custo (Economia de ~$396/ano)**

**Análise de Custos (Baseado em 500GB/mês de logs):**

| Item | Loki (S3) | CloudWatch |
|------|-----------|-----------|
| Ingestion | Incluído | $25.00/mês (50GB) |
| Storage | $11.50/mês (S3 500GB) | $30.00/mês (50GB, 7 dias) |
| API Calls | $2.00/mês | Incluído |
| EBS PVCs | $2.40/mês (3x10GB) | N/A |
| **Subtotal** | **$15.90/mês** | **$55.00/mês** |
| **Anual** | **$190.80/ano** | **$660.00/ano** |
| **Economia** | **Base** | **+$469.20/ano** |

**Fontes:**
- [cost-estimation.md](../plan/cost-estimation.md) linhas 145-150: "CloudWatch optimization: $64/month → $10/month usando Loki"
- AWS CloudWatch Pricing: $0.50/GB ingestion, $0.03/GB storage

#### 3. **Integração com Stack de Observabilidade (Três Pilares)**

**Grafana Native Integration:**

```yaml
# Grafana datasource (já configurado em Fase 3)
datasources:
  - name: Loki
    type: loki
    url: http://loki-gateway:3100
    jsonData:
      derivedFields:
        - datasourceUid: tempo
          matcherRegex: "traceID=(\\w+)"
          name: TraceID
          url: "$${__value.raw}"
```

**Benefícios:**
- ✅ **Correlação Trace↔Log:** Clique em trace → visualiza logs do span
- ✅ **Unified UI:** Métricas (Prometheus) + Logs (Loki) + Traces (Tempo) em um dashboard
- ✅ **Mesma empresa:** Loki e Grafana são ambos da Grafana Labs (suporte integrado)
- ✅ **LogQL:** Linguagem de query similar ao PromQL (curva de aprendizado reduzida)

**CloudWatch Integration:**
- ⚠️ Datasource separado
- ⚠️ Sem correlação automática com Tempo
- ⚠️ Query language diferente (CloudWatch Insights)

#### 4. **Arquitetura Já Documentada (04-observability-stack.md)**

**Observação:** A especificação detalhada de Loki já existe no plano arquitetural (270+ linhas):

- Configuração completa do Helm chart
- IRSA setup (IAM roles, policies, trust relationships)
- SimpleScalable mode (read/write/backend separation)
- S3 backend configuration
- Lifecycle policies
- Retention management

**Evitar desperdício:** Usar arquitetura já planejada vs criar nova para CloudWatch.

#### 5. **Consistência com ADR-004 (Terraform + Helm Provider)**

**Pattern Estabelecido:**

```terraform
# Mesmo padrão do AWS Load Balancer Controller e Cert-Manager
module "loki" {
  source = "./modules/loki"

  # Helm release via Terraform
  chart_version = "5.42.0"

  # IRSA para S3 access
  iam_role_arn = aws_iam_role.loki_s3_access.arn

  # Dependências gerenciadas
  depends_on = [module.kube_prometheus_stack]
}
```

**CloudWatch Alternative:**
- Requer Fluent Bit com CloudWatch output (IAM diferente)
- Não há "Helm chart para CloudWatch" (configuração manual)
- Menos consistente com Platform Services pattern

---

## Alternativas Consideradas

### Opção A: CloudWatch Logs (Conforme DEPLOY-CHECKLIST.md)

| Prós | Contras |
|------|---------|
| ✅ Nativo AWS | ❌ Lock-in AWS (viola cloud-agnostic) |
| ✅ Integração com CloudTrail | ❌ Custo 3x maior ($55/mês vs $16/mês) |
| ✅ Compliance built-in | ❌ Sem correlação Trace↔Log |
| | ❌ Query language diferente |
| | ❌ Não usa stack Grafana Labs |

**Decisão:** ❌ Rejeitado - Custo e lock-in não justificam

### Opção B: EFK Stack (Elasticsearch + Fluentd + Kibana)

| Prós | Contras |
|------|---------|
| ✅ Maturidade (usado há anos) | ❌ Elasticsearch requer 3+ nodes (custo) |
| ✅ Powerful queries | ❌ Complexidade operacional (tuning JVM) |
| | ❌ Não integra com Grafana nativamente |
| | ❌ Licença Elastic não é Apache 2.0 |

**Decisão:** ❌ Rejeitado - Overhead operacional muito alto

### Opção C: Loki + S3 (04-observability-stack.md)

| Prós | Contras |
|------|---------|
| ✅ Cloud-agnostic | ⚠️ Diverge de DEPLOY-CHECKLIST.md |
| ✅ Custo 3x menor | ⚠️ Curva de aprendizado (LogQL) |
| ✅ Integração Grafana nativa | |
| ✅ Correlação Trace↔Log automática | |
| ✅ Arquitetura já documentada | |
| ✅ Consistente com ADR-004 | |

**Decisão:** ✅ **ESCOLHIDO** - Benefícios superam os contras

### Opção D: Loki + CloudWatch (Híbrido)

| Prós | Contras |
|------|---------|
| ✅ Melhor dos dois mundos | ⚠️ Complexidade operacional (2 sistemas) |
| ✅ Compliance via CloudWatch | ⚠️ Custo aumenta ($22/mês) |
| ✅ Operacional via Loki | ⚠️ Duplicação de logs |

**Decisão:** 🔄 **HOLD** - Documentado, não implementado agora. Adicionar se compliance exigir.

---

## Consequências

### Positivas

✅ **Cloud-Agnostic:** Portabilidade para Azure/GCP sem refactor (alinha com princípio arquitetural)
✅ **Economia de Custos:** $15.90/mês (Loki) vs $55/mês (CloudWatch) = **$469.20/ano de economia**
✅ **Unified Observability:** Métricas + Logs + Traces em Grafana (correlação automática)
✅ **Arquitetura Documentada:** 04-observability-stack.md já especifica Loki (270+ linhas)
✅ **Consistência IaC:** Terraform + Helm Provider (mesmo padrão de ADR-004)
✅ **Retention Flexível:** 30 dias em S3 (vs 7 dias padrão CloudWatch) sem custo adicional
✅ **Open Source:** Apache 2.0 license, sem vendor lock-in

### Negativas

⚠️ **Divergência de DEPLOY-CHECKLIST.md:** Requer atualização do documento (Linha 316-319)
⚠️ **Curva de Aprendizado:** Time precisa aprender LogQL (similar a PromQL, mas nova linguagem)
⚠️ **Responsabilidade Operacional:** Gerenciar Loki (vs fully-managed CloudWatch)
⚠️ **Complexity Initial:** Setup IRSA, S3 lifecycle, Loki tuning

### Neutras

🔄 **CloudWatch Hold:** Documentado como opção futura, pode ser adicionado depois se necessário
🔄 **Grafana Datasource:** Loki datasource já está configurado em kube-prometheus-stack (Fase 3)
🔄 **Migração Futura:** Se precisar CloudWatch, dual-shipping é possível (Fluent Bit suporta múltiplos outputs)

---

## Plano de Implementação

### Fase 1: Infraestrutura AWS (2-3h)

- [ ] Criar S3 bucket: `k8s-platform-loki-{ACCOUNT_ID}`
- [ ] Configurar lifecycle policy (30 dias)
- [ ] Habilitar encryption (AES256)
- [ ] Criar IAM policy para Loki (S3: ListBucket, GetObject, PutObject, DeleteObject)
- [ ] Criar IAM role com OIDC trust relationship
- [ ] Attach policy ao role

### Fase 2: Terraform Module - Loki (2-3h)

- [ ] Criar `modules/loki/main.tf`:
  - Helm release (chart `grafana/loki` v5.42.0)
  - SimpleScalable mode: read=2, write=2, backend=2, gateway=2
  - S3 backend configuration
  - ServiceAccount annotation (IRSA)
- [ ] Criar `modules/loki/variables.tf`:
  - namespace, chart_version, retention_period, s3_region, replicas
- [ ] Criar `modules/loki/outputs.tf`:
  - loki_gateway_endpoint, s3_bucket_name, iam_role_arn
- [ ] Criar `modules/loki/iam.tf`:
  - IAM policy, IAM role, trust policy (padrão IRSA)
- [ ] Criar `modules/loki/versions.tf`:
  - Provider constraints

### Fase 3: Terraform Module - Fluent Bit (2-3h)

- [ ] Criar `modules/fluent-bit/main.tf`:
  - Helm release (chart `fluent/fluent-bit` v0.43.0)
  - DaemonSet mode (all nodes)
  - Parsers: Docker JSON, CRI-O
  - Filters: Kubernetes metadata, log levels
  - Output: Loki gateway
- [ ] Criar `modules/fluent-bit/variables.tf`:
  - namespace, loki_endpoint, exclude_namespaces
- [ ] Criar `modules/fluent-bit/outputs.tf`:
  - daemonset_name

### Fase 4: Integration (1h)

- [ ] Atualizar `marco2/main.tf`:
  ```terraform
  module "loki" {
    source = "./modules/loki"
    namespace = "monitoring"
    depends_on = [module.kube_prometheus_stack]
  }

  module "fluent_bit" {
    source = "./modules/fluent-bit"
    namespace = "monitoring"
    loki_endpoint = "http://loki-gateway.monitoring:3100/loki/api/v1/push"
    depends_on = [module.loki]
  }
  ```

### Fase 5: Grafana Dashboards (1-2h)

- [ ] Verificar Loki datasource no Grafana (deve estar configurado)
- [ ] Importar dashboards da comunidade:
  - Dashboard ID 13639: Kubernetes Logs App
  - Dashboard ID 12019: Loki Dashboard
  - Dashboard ID 15141: Kubernetes Logs Browser
- [ ] Criar dashboard customizado:
  - Log volume por namespace
  - Error rate trends
  - Top error messages

### Fase 6: Validation (1-2h)

- [ ] Criar `scripts/validate-fase4.sh`:
  - Check S3 bucket exists
  - Check IAM role permissions
  - Check Loki pods Running (read, write, backend, gateway)
  - Check Fluent Bit DaemonSet (7 nodes)
  - Query Loki API: `/loki/api/v1/labels`
  - Test log query in Grafana
- [ ] Executar terraform plan
- [ ] Executar terraform apply
- [ ] Validar ingestion rate: `rate({namespace="monitoring"}[5m])`

### Fase 7: Documentation (1h)

- [ ] Atualizar DEPLOY-CHECKLIST.md (Fase 4: Loki + Fluent Bit)
- [ ] Criar runbook: Common log queries (LogQL examples)
- [ ] Documentar Grafana access e dashboards
- [ ] Atualizar diário de bordo

**Tempo Total Estimado:** 10-15 horas

---

## Validação

### Checklist de Conformidade

#### Funcional
- [ ] Loki pods Running: read=2/2, write=2/2, backend=2/2, gateway=2/2
- [ ] Fluent Bit DaemonSet: 7/7 pods Running (todos os nodes)
- [ ] S3 bucket criado: `k8s-platform-loki-{ACCOUNT_ID}`
- [ ] Lifecycle policy configurada (30 dias)
- [ ] Logs visíveis no Grafana Explore
- [ ] Query LogQL funcionando: `{namespace="monitoring"} |= "error"`
- [ ] Correlação Trace↔Log testada (clique em trace ID → logs aparecem)

#### Não-Funcional
- [ ] Log ingestion latency < 30 segundos
- [ ] Log query response time < 5 segundos (last 1h)
- [ ] Loki memory usage < 1GB total (read+write+backend)
- [ ] Fluent Bit memory usage < 128Mi per node
- [ ] Storage growth rate documentado

#### Segurança
- [ ] IRSA configurado (ServiceAccount annotation)
- [ ] S3 bucket encryption habilitada (AES256)
- [ ] IAM policy least privilege (S3 bucket específico)
- [ ] Loki API ClusterIP only (não exposto externamente)
- [ ] CloudTrail logging S3 access

#### Documentação
- [ ] ADR-005 aprovado
- [ ] DEPLOY-CHECKLIST.md atualizado
- [ ] Validation script criado
- [ ] Grafana dashboard guide
- [ ] LogQL query examples documentados

### Testes

```bash
# 1. Verificar Loki pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# Esperado:
# loki-read-0           1/1   Running
# loki-read-1           1/1   Running
# loki-write-0          1/1   Running
# loki-write-1          1/1   Running
# loki-backend-0        1/1   Running
# loki-backend-1        1/1   Running
# loki-gateway-xxx      1/1   Running

# 2. Verificar Fluent Bit DaemonSet
kubectl get daemonset -n monitoring fluent-bit

# Esperado:
# NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
# fluent-bit   7         7         7       7            7

# 3. Query Loki API
kubectl port-forward -n monitoring svc/loki-gateway 3100:3100
curl -s "http://localhost:3100/loki/api/v1/labels"

# Esperado:
# {"status":"success","data":["namespace","pod","container",...]}

# 4. Test log ingestion
kubectl logs -n monitoring deployment/loki-gateway --tail=50

# Procurar por: "POST /loki/api/v1/push" (logs sendo recebidos)

# 5. Grafana Explore (Manual)
# - Acessar Grafana: http://localhost:3000
# - Explore → Loki datasource
# - Query: {namespace="monitoring"} |= "error"
# - Verificar logs aparecem

# 6. Validar correlação Trace↔Log
# - Abrir dashboard com traces (Tempo)
# - Clicar em um trace ID
# - Verificar botão "Logs for this span"
# - Clicar → deve abrir Loki com logs filtrados
```

---

## Rollback Plan

**Se deployment falhar:**

```bash
# 1. Rollback Fluent Bit (para parar ingestion)
cd platform-provisioning/aws/kubernetes/terraform/envs/marco2
terraform destroy -target=module.fluent_bit

# 2. Rollback Loki
terraform destroy -target=module.loki

# 3. Cleanup AWS resources
aws s3 rb s3://k8s-platform-loki-{ACCOUNT_ID} --force
aws iam detach-role-policy --role-name LokiS3Role --policy-arn arn:aws:iam::{ACCOUNT_ID}:policy/LokiS3Policy
aws iam delete-role --role-name LokiS3Role
aws iam delete-policy --policy-arn arn:aws:iam::{ACCOUNT_ID}:policy/LokiS3Policy

# 4. Fallback
# Continue usando kubectl logs para troubleshooting
# Planeje retry com lessons learned
```

**Se performance issues:**

```bash
# Scale up Loki
# modules/loki/main.tf
set {
  name  = "read.replicas"
  value = "3"  # era 2
}

# Increase resources
set {
  name  = "read.resources.limits.memory"
  value = "1Gi"  # era 512Mi
}

terraform apply
```

---

## CloudWatch: Opção Futura (HOLD)

### Quando Adicionar CloudWatch

**Cenários para ativar CloudWatch Logs:**

1. **Compliance Regulatório**
   - Auditoria externa requer logs nativos AWS
   - PCI-DSS Level 1, SOC2 Type II exige CloudWatch

2. **Integration AWS-Native**
   - CloudTrail correlation (security events)
   - GuardDuty findings correlation
   - AWS Security Hub integration

3. **Requisito de Cliente**
   - Cliente/stakeholder exige CloudWatch explicitamente

### Como Adicionar CloudWatch (Futuro)

Se necessário, adicionar CloudWatch é simples:

```terraform
# modules/fluent-bit/main.tf
module "fluent_bit" {
  cloudwatch_enabled = true  # Atualmente false
}
```

**Impacto:**
- Fluent Bit configurado com dual-output (Loki + CloudWatch)
- IAM role adicional para CloudWatch Logs (PutLogEvents)
- Custo adicional: ~$6/mês (minimal mode: apenas critical logs)
- Grafana datasource adicional (CloudWatch)

**Documentação:** Ver `modules/fluent-bit/README.md` (seção CloudWatch Integration)

---

## Referências

### Documentação Técnica
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/manual/)
- [04-observability-stack.md](../plan/aws-execution/04-observability-stack.md) (Linhas 803-1075)
- [Terraform Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)

### Custos e Pricing
- [AWS CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/)
- [AWS S3 Pricing](https://aws.amazon.com/s3/pricing/)
- [cost-estimation.md](../plan/cost-estimation.md) (Linhas 145-150)

### Best Practices
- [Grafana Loki Best Practices](https://grafana.com/docs/loki/latest/best-practices/)
- [IRSA (IAM Roles for Service Accounts)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [LogQL Language](https://grafana.com/docs/loki/latest/logql/)

---

## Decisões Relacionadas

- [ADR-001: Setup e Governança](adr-001-setup-e-governanca.md)
- [ADR-002: Estrutura de Domínios](adr-002-estrutura-de-dominios.md)
- [ADR-003: Secrets Management Strategy](adr-003-secrets-management-strategy.md) - Pattern de IRSA para replicar
- [ADR-004: Terraform vs Helm for Platform Services](adr-004-terraform-vs-helm-for-platform-services.md) - Terraform + Helm Provider
- **ADR-006 (Futuro):** Distributed Tracing Strategy (Tempo + OTEL)

---

## Aprovação

### Stakeholders

| Role | Nome | Aprovação | Data |
|------|------|-----------|------|
| DevOps Lead | - | ✅ Approved | 2026-01-26 |
| Platform Engineer | - | ✅ Approved | 2026-01-26 |
| FinOps | - | ✅ Approved (custo) | 2026-01-26 |

### Decisão Final

✅ **APPROVED** - Loki como solução primária de logging
⏸️ **HOLD** - CloudWatch documentado, não implementado (adicionar se necessário)

---

**Última atualização:** 2026-01-26
**Aprovado por:** DevOps Team
**Próxima revisão:** Marco 3 (quando adicionar Tempo/Traces, validar correlação Trace↔Log)
**Status:** ✅ READY FOR IMPLEMENTATION
