# 💰 Análise de Custos - Plataforma Kubernetes AWS

**Última Atualização:** 2026-02-04
**Versão:** 3.1 (Marco 3 GitLab Staging Deployed: +$48.60/mês)
**Framework:** FinOps + TCO Analysis

---

## 📊 Resumo Executivo

| Métrica | Valor | Observações |
|---------|-------|-------------|
| **Custo Total Mensal (Marco 2)** | **~$685.70/mês** | Marco 0 + Marco 1 + Marco 2 + Fase 8 |
| **Custo Anual (Marco 2)** | **~$8.228.40/ano** | $685.70 × 12 meses |
| **Custo Marco 3 Fase 1 (Real)** | **$704.20/mês** | Marco 2 + Redis Operator ($18.50) |
| **Custo Marco 3 GitLab (Staging)** | **$752.80/mês** | Marco 3 Fase 1 + GitLab ALBs ($48.60) |
| **Custo Anual Marco 3** | **$9.033.60/ano** | $752.80 × 12 meses |
| **Economia vs Bitnami+Tanzu** | **$35,995/ano** | ✅ **Redis Operator implementado 2026-02-02** |
| **Custo por Node** | **~$98/mês** | $685.70 ÷ 7 nodes |
| **Custo por Pod (Platform)** | **~$19/mês** | $685.70 ÷ 36 pods observability |

### Tendência de Custos (Atualizada 2026-02-02)

```
Marco 0: $0.07/mês → Marco 1: $550/mês → Marco 2: $666/mês → Marco 2 Fase 8: $685.70/mês → Marco 3 Fase 1: $704.20/mês
```

**Marco 3 Real vs Projetado:** $704.20 vs $737.10 planejado = **-$32.90/mês economia adicional** (-4.5%)

---

## 🎯 Marco 3 Fase 1: Redis Operator - Implementação Confirmada

**Data:** 2026-02-02
**Status:** ✅ **Implementado e Validado**
**Economia Anual:** **$35,995/ano** vs Bitnami + Tanzu Standard

---

## 🎯 Marco 3 Fase 2: GitLab CE Deployment - Custos Reais (Staging)

**Data Deploy:** 2026-02-04
**Status:** ✅ **Deployed (Staging)** | [Logbook](../logbook/2026-02-04-execucao-pendente-staging.md) | [ADR-030](decisions.md#adr-030)
**Custo Mensal Real (Staging):** **$48.60/mês** (3 ALBs apenas, dependências compartilhadas)
**Custo Mensal Projetado (Full):** **$92.71/mês** (com runner jobs + storage)
**Custo Anual:** **$1,112.52/ano**

### 📊 GitLab Staging - Custos Reais (2026-02-04)

**Environment:** Staging | **Namespace:** gitlab-staging | **Helm:** gitlab/gitlab 8.7.0

#### Custos Confirmados (Staging)

| Componente | Especificação | Custo/Mês | Custo/Ano | Observações |
|------------|---------------|-----------|-----------|-------------|
| **ALB webservice** | HTTP (80) + HTTPS (443) | $16.20 | $194.40 | k8s-gitlabst-gitlabwe-*.us-east-1.elb.amazonaws.com |
| **ALB registry** | HTTP (80) + HTTPS (443) | $16.20 | $194.40 | k8s-gitlabst-gitlabre-*.us-east-1.elb.amazonaws.com |
| **ALB kas** | HTTP (80) + HTTPS (443) | $16.20 | $194.40 | k8s-gitlabst-gitlabka-*.us-east-1.elb.amazonaws.com |
| **SUBTOTAL ALBs** | | **$48.60** | **$583.20** | 3 ALBs dedicados (ADR-021 Fase 1) |
| **Compute (Pods)** | 12 pods Running | $0 | $0 | Shared workloads node group |
| **PostgreSQL RDS** | db.t3.small shared | $0 | $0 | Já existente (Marco 3 Fase 1) |
| **Redis Operator** | Spotahome shared | $0 | $0 | Já existente (Marco 3 Fase 1) |
| **S3 Buckets** | artifacts + uploads | $0 | $0 | Já existente (Marco 3 Fase 1) |
| **IAM IRSA** | gitlab-sa-role | $0 | $0 | IRSA (sem access keys) |
| **Runner Jobs** | ⚠️ Non-functional | $0 | $0 | CrashLoop (ADR-021 Fase 1 DNS issue) |
| **TOTAL STAGING** | | **$48.60/mês** | **$583.20/ano** | ✅ Validado 2026-02-04 |

**Comparação vs Projetado:** -$44.11/mês (-47.6% economia temporária até runner funcional)

---

### Decisão Arquitetural: GitLab CE Self-Hosted Kubernetes

**Contexto:** Escolha entre GitLab SaaS, EC2 self-hosted, ou Kubernetes self-hosted.

| Cenário | Custo/Mês (10 users) | Custo/Ano | vs K8s | Ops Toil | Decisão |
|---------|---------------------|-----------|--------|----------|---------|
| **GitLab SaaS Premium** | $290.00 | $3,480 | +214% | ✅ Zero | ❌ Custo proibitivo |
| **EC2 Single Instance** | $199.71 | $2,396 | +115% | ⚠️ Médio | ❌ Sem HA |
| **EC2 HA Multi-Instance** | $263.47 | $3,162 | +184% | ⚠️ Alto | ❌ Caro + toil |
| **GitLab K8s Self-Hosted** | **$92.71** | **$1,113** | **Baseline** | ⚠️ Médio | ✅ **ESCOLHIDO** |
| **GitHub Team + Actions** | $136.00 | $1,632 | +47% | ✅ Zero | ⚠️ Lock-in Microsoft |

**Decisão Final:** GitLab CE Self-Hosted em Kubernetes
**Rationale:** Melhor custo absoluto (<$100/mês), multi-cloud portability, compliance (dados na infra própria)

### Breakdown Custos Detalhado

**Infraestrutura Deployada:**
- **Webservice:** 2 pods (Rails app: 500m CPU, 2Gi RAM cada)
- **Sidekiq:** 1 pod (background jobs: 500m CPU, 1Gi RAM)
- **Gitaly:** 1 pod (Git storage: 200m CPU, 512Mi RAM, 50Gi PVC)
- **GitLab Runner:** 2 pods (orchestrators: 100m CPU, 256Mi RAM cada)
- **GitLab Shell:** 1 pod (SSH: 25m CPU, 50Mi RAM estimado)
- **Total Requests:** 2.125 vCPU, 6.35 GB RAM

**Dependências Externas (já contabilizadas Marco 3 Fase 1):**
- PostgreSQL RDS: $30/mês (shared GitLab + Harbor + ArgoCD)
- Redis Operator: $18.50/mês (cache + sessions + Sidekiq jobs)

| Componente | Especificação | Custo/Mês | Custo/Ano | % Total | Observações |
|------------|---------------|-----------|-----------|---------|-------------|
| **Compute (Pods)** | 2.125 vCPU, 6.35 GB RAM | $32.31 | $387.72 | 34.8% | 15.2% cluster capacity (shared nodes) |
| **Networking (ALB + NLB)** | 1 ALB HTTP + 1 NLB SSH | $43.45 | $521.40 | 46.9% | Maior custo (2 load balancers) |
| **Storage (EBS + S3)** | Gitaly 50GB gp3 + S3 10GB | $5.99 | $71.88 | 6.5% | Artifacts 90d retention |
| **Runner Jobs (Ephemeral)** | 100 jobs/dia × 3min × 100m CPU | $9.46 | $113.52 | 10.2% | Pods temporários CI/CD |
| **IAM/Security** | Secrets Manager (1 secret) | $0.40 | $4.80 | 0.4% | GitLab root password |
| **Hidden Costs** | CloudWatch logs + metrics | $1.10 | $13.20 | 1.2% | Observability |
| **TOTAL GitLab CE** | | **$92.71** | **$1,112.52** | **100%** | Desenvolvimento (10 devs, 20 pipelines/dia) |

### Análise de Overprovisioning e Otimizações

**Problemas Identificados:**

1. **Gitaly PVC Oversized** ⚠️
   - Provisionado: 50Gi gp3
   - Uso estimado: 3 GB (6% utilização)
   - Overprovisioning: 47 GB desperdício
   - Economia potencial: $3.20/mês (reduzir para 10Gi em novos deploys)
   - **Status:** Manter 50Gi atual (resize impossível), usar 10Gi próximos clusters

2. **Shared ALB Opportunity** ✅ QUICK WIN
   - Custo atual: 3 ALBs separados (GitLab + Harbor + ArgoCD) = 3 × $23 = $69/mês
   - Otimização: Consolidar em 1 ALB via IngressGroup annotation
   - Economia: $46/mês total ($15.33/app)
   - Esforço: 1h implementação
   - ROI: Imediato, zero risco
   - **AÇÃO:** Implementar IngressGroup no próximo deploy Harbor

3. **NLB SSH (GitLab Shell)** ⚠️
   - Custo: $20.43/mês
   - Uso: ~10% clones via SSH (maioria usa HTTPS)
   - Economia potencial: $20.43/mês (desabilitar SSH, forçar HTTPS)
   - Trade-off: DX inferior (onboarding 1h/dev × 10 devs = $1,000)
   - ROI Year 1: -75% (negativo)
   - **DECISÃO:** Manter NLB (SSH é DX superior)

4. **Runner Jobs Ephemeral** ⚠️ CUSTO OCULTO IDENTIFICADO
   - Não estava contabilizado inicialmente
   - 100 jobs/dia × 3min × 100m CPU = $9.46/mês
   - Economia spot instances: -70% = -$6.62/mês
   - Investimento Karpenter: $600
   - Payback: 88 meses (7.3 anos)
   - **DECISÃO:** Aceitar custo $9.46/mês, documentado

**Otimizações Rejeitadas (ROI negativo):**
- ❌ Spot Instances runners (payback 7 anos)
- ❌ VPA para Sidekiq/Webservice (payback 87 meses)
- ❌ Docker cache S3 (payback 105 meses)

### Custo Otimizado Projetado

**Cenário Base (atual):**
- GitLab CE: $92.71/mês
- TOTAL: $92.71/mês

**Cenário Otimizado (Shared ALB aplicado):**
- GitLab CE base: $92.71/mês
- Shared ALB economy: -$15.33/mês
- **TOTAL OTIMIZADO: $77.38/mês**

**Economia:** $15.33/mês (-16.5%)
**Economia Anual:** $184/ano

### ROI vs Alternativas

**Break-even Analysis:**

GitLab SaaS Premium ($29/user/mês):
- Break-even: 3 usuários ($87/mês SaaS = $83/mês self-hosted)
- 10 usuários: $290/mês SaaS vs $93/mês K8s = **$197/mês desperdício** (+214%)
- 50 usuários: $1,450/mês SaaS vs $136/mês K8s (produção scaled) = **$1,314/mês desperdício** (+964%)

GitHub Team + Actions:
- 10 usuários: $40/mês + $96/mês Actions = $136/mês
- vs K8s: +$43.29/mês (+47%)
- Trade-off: Zero ops, mas vendor lock-in Microsoft

### Consolidação Marco 3 Completo

**Custo Total Marco 3 (Fase 1 + Fase 2):**

```
Marco 3 Fase 1 (Base):       $704.20/mês
- Marco 2 completo:          $685.70/mês
- Redis Operator:            +$18.50/mês

Marco 3 Fase 2 (GitLab):     +$92.71/mês
- GitLab pods:               $32.31/mês
- Networking (ALB + NLB):    $43.45/mês
- Storage (EBS + S3):        $5.99/mês
- Runner ephemeral jobs:     $9.46/mês
- Security + Hidden:         $1.50/mês

────────────────────────────────────────
TOTAL Marco 3 (Fase 1 + 2):  $796.91/mês
TOTAL Anual:                 $9,562.92/ano
```

**Nota:** PostgreSQL ($30/mês) e Redis ($18.50/mês) já estão contabilizados no Marco 3 Fase 1, são compartilhados por GitLab, Harbor e ArgoCD.

### Cenários de Custo (Dev vs Produção)

| Cenário | Usuários | Pipelines/dia | Compute | Networking | Storage | Total/Mês |
|---------|----------|--------------|---------|------------|---------|-----------|
| **Desenvolvimento** | 10 devs | 20 | $32.31 | $43.45 | $5.99 | **$92.71** |
| **Produção** | 50 devs | 100 | $60.74 | $58.00 | $14.50 | **$136.44** |

**Análise usada:** Cenário DESENVOLVIMENTO ($92.71/mês)
**Rationale:** Marco 3 é ambiente de homologação/staging inicial.

### Métricas de Sucesso (KPIs)

**Operacionais:**
- Uptime GitLab UI: > 99.5% (8h-18h Mon-Fri)
- Pipeline success rate: > 95%
- Startup time pós-deploy: < 5 min

**Financeiras:**
- Custo real vs projetado: ±10% ($83-$102/mês)
- Overprovisioning CPU: < 30% idle
- Storage utilization Gitaly: > 20% (monitorar após 30d)

**Próxima Validação:** 2026-03-02 (30 dias operação)
- CloudWatch Metrics: CPU/Memory usage real vs requests
- Cost Explorer: Custo observado vs $92.71 projetado
- GitLab Admin: Artifacts storage growth rate

### Referências

- [GitLab Terraform Module](../../platform-provisioning/aws/kubernetes/terraform/envs/marco3/modules/gitlab/main.tf)
- [GitLab Values Template](../../platform-provisioning/aws/kubernetes/terraform/envs/marco3/modules/gitlab/values.yaml.tpl)
- [S3 Buckets Module](../../platform-provisioning/aws/kubernetes/terraform/envs/marco3/modules/s3-buckets/main.tf)
- [Marco 3 Diary](../diary/marco3-diary.md) - Implementação Redis Operator

### Decisão Arquitetural: Spotahome Redis Operator

| Cenário | Custo/Mês | Custo/Ano | vs Operator | ROI | Status |
|---------|-----------|-----------|-------------|-----|--------|
| **Bitnami Helm + Tanzu Standard** | $3,018.12 | $36,217.44 | +$35,995 | -99.4% | ❌ Bloqueado |
| **AWS ElastiCache (managed)** | $79.81 | $957.72 | +$736 | -76.8% | ⚠️ Alternativa |
| **Spotahome Redis Operator** | **$18.50** | **$222.00** | **Baseline** | - | ✅ **IMPLEMENTADO** |

**Decisão Final:** Spotahome Redis Operator
**Rationale:** Economia massiva ($35,995/ano), HA automático < 30s, cloud-agnostic, zero licenciamento

### Breakdown Custos Detalhado

| Componente | Especificação | Custo/Mês | Custo/Ano | Observações |
|------------|---------------|-----------|-----------|-------------|
| **Operator (pods)** | 6 pods (3 Redis + 3 Sentinel) | $0.00 | $0.00 | Usa nodes existentes |
| **EBS Volumes** | 3× 8GB gp2 | $1.92 | $23.04 | Persistent storage ($0.08/GB) |
| **EBS Snapshots** | Daily backups 7d retention | $0.50 | $6.00 | AWS Backup |
| **CloudWatch Metrics** | 5 custom metrics | $0.00 | $0.00 | Free tier (10 metrics) |
| **Secrets Manager** | 1 secret (shared) | $0.00 | $0.00 | Compartilhado Marco 2 |
| **Licenciamento** | Open Source Apache 2.0 | **$0.00** | **$0.00** | **Zero cost** |
| **TOTAL** | | **$18.50** | **$222.00** | |

### ROI Confirmado

**Investimento Migração:** $1,300 (13h @ $100/h)
**Economia Ano 1:** $35,995
**ROI Year 1:** **2,668%**
**Payback Period:** **13 dias**
**NPV 3 anos:** $87,030 (ROI cumulativo 6,695%)

### Recursos Provisionados

**Infraestrutura:**
- ✅ 3 Redis pods (rfr-redis-0, rfr-redis-1, rfr-redis-2) - READY 1/1
- ✅ 3 Sentinel pods (rfs-redis-xxx) - READY 1/1
- ✅ 3 PVCs 8Gi gp2 (EBS volumes encrypted)
- ✅ 3 Services (rfrm-redis master, rfrs-redis replicas, rfs-redis sentinel)

**Validações:**
- ✅ Conectividade: `redis-cli PING` → `PONG`
- ✅ HA: Sentinel failover automático < 30s
- ✅ Security: Pod Security Standards = Restricted, runAsNonRoot: true

**Referências:**
- [ADR-023](./decisions.md#adr-023) - Migration to Kubernetes Operators
- [Marco 3 Diary](../diary/marco3-diary.md) - Implementação detalhada 2026-02-02

---

## 🔄 Operações de Shutdown (FinOps)

**Data de Implementação:** 2026-01-30 10:00 BRT
**Status:** ✅ Ativo

### Resumo da Operação

| Métrica | Valor | Detalhes |
|---------|-------|----------|
| **Script Utilizado** | `shutdown-marco2.sh dev --snapshot` | Shutdown controlado com snapshot RDS |
| **Tempo de Execução** | ~6 minutos | Drain pods + snapshot RDS + scale nodes |
| **Snapshot RDS Criado** | `k8s-platform-prod-postgresql-shutdown-20260130-100049` | Backup antes do stop |
| **Nodes Desligados** | 7 → 0 (em andamento: 3 DaemonSets) | System, workloads, critical |
| **RDS Status** | Available → Stopping (pending) | Aguardando fim do backup automático |
| **Economia Ativada** | **~$177.61/mês** | 8h/dia útil (22 dias/mês) |
| **Custo Remanescente** | **~$508.09/mês** | EKS Control Plane + NAT + Storage |

### Breakdown de Economia

#### Recursos Desligados (Economia Ativada)
| Componente | Custo 24/7 | Custo 8h/dia | Economia |
|------------|------------|--------------|----------|
| EC2 Nodes (7× t3.medium) | $212.59/mês | $50.45/mês | **$162.14/mês** |
| Data Transfer NAT | $22.50/mês | $5.34/mês | **$17.16/mês** |
| ALB LCU Charges | $10.00/mês | $2.37/mês | **$7.63/mês** |
| RDS PostgreSQL (Marco 3) | Não ativo ainda | N/A | $0.00 |
| **SUBTOTAL ECONOMIA** | | | **$186.93/mês** |

#### Recursos que Permanecem Ativos (Custos Fixos)
| Componente | Custo/Mês | Justificativa |
|------------|-----------|---------------|
| EKS Control Plane | $73.00 | AWS managed, não pode ser stopped |
| NAT Gateways (2× hour charge) | $66.00 | Necessário para restart rápido |
| S3 Storage (Loki + Tempo + State) | $23.50 | Dados preservados |
| ALBs Hour Charge (2×) | $32.40 | Hour charge persiste, LCU vai pra 0 |
| EBS Volumes (PVCs detached) | $8.96 | Prometheus, Grafana, Loki, Alertmanager |
| CloudWatch Logs | $10.08 | Retention de logs |
| Secrets Manager | $0.40 | Grafana password |
| DynamoDB + Route53 | $0.75 | Terraform state + DNS |
| **SUBTOTAL FIXO** | **$215.09/mês** | **31.4% do custo total** |

### Validação da Operação

**Critérios de Sucesso:**
- ✅ Snapshot RDS criado com sucesso
- ✅ Node groups escalados para 0 (desiredSize=0)
- ⚠️ 3 nodes ainda em terminação (DaemonSets aguardando remoção pelo ASG)
- ⚠️ RDS ainda em "available" (estava em backup, stop será manual se necessário)

**Log da Operação:** `/tmp/k8s-shutdown-20260130-100014.log`

### Instruções de Restart

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes
./scripts/finops/startup-marco2.sh dev
```

**Tempo Estimado:** 5-8 minutos
**Validação Pós-Startup:**
- Nodes Ready: 7/7
- Pods Running: ~77
- RDS Available: `available`

### Projeção de Economia Anual

**Cenário:** Desenvolvimento 8h/dia, segunda-sexta (22 dias úteis/mês)

| Período | Custo 24/7 | Custo Shutdown | Economia |
|---------|------------|----------------|----------|
| **Mensal** | $685.70 | $508.09 | **$177.61** (25.9%) |
| **Anual** | $8.228.40 | $6.097.08 | **$2.131.32** (25.9%) |

**ROI Investimento Automação ($500):** 2.8 meses payback, **426% ROI Ano 1**

**Próximas Fases:**
1. ✅ **Fase 1:** Validação manual (esta execução)
2. ⏳ **Fase 2:** Automação EventBridge + Lambda (Q1 2026)
3. ⏳ **Fase 3:** Dashboard CloudWatch FinOps (Q1 2026)

---

## 💡 Automação FinOps STAGING (🚀 ATIVA - ADR-024)

**Data Planejamento:** 2026-01-30
**Data Ativação:** 2026-02-02
**Status:** 🚀 **ATIVA** (EventBridge automation ENABLED)
**ROI Projetado:** 44% Year 1 (payback 6.7 meses)
**Validação:** 5/5 testes manuais completos (100% sucesso)

### Contexto

Ambiente STAGING opera 24/7 mas é utilizado apenas **8h-18h Mon-Fri** (horário comercial Brasil). Isso representa **desperdício de 70%** do tempo (118h/semana sem uso real).

**Custo STAGING Atual (24/7):**

| Componente | Quantidade | Custo/Mês | Observações |
|------------|-----------|-----------|-------------|
| EKS Control Plane (rateio 50%) | 1 cluster | $37.00 | Compartilhado com PROD |
| EC2 nodes regular (2× t3.medium) | 2 nodes | $60.00 | Workloads general purpose |
| RDS db.t3.small Multi-AZ | 1 instance | $70.00 | PostgreSQL databases staging |
| Redis Operator (infra) | 3 pods | $10.00 | Cache + sessions |
| RabbitMQ Operator (infra) | 3 pods | $10.00 | Message queue |
| **TOTAL STAGING 24/7** | | **$187.00/mês** | **R$ 1.122/mês** (taxa 6.0) |

**Perda Anual:** R$ 1.122/mês × 12 = **R$ 13.464/ano**

---

### Solução Proposta: EventBridge + Lambda Automation

**Arquitetura:**
- EventBridge Scheduler: 2 rules (startup 8h BRT, shutdown 18h BRT Mon-Fri)
- Lambda Function: Python 3.12, 512MB, 300s timeout
- DynamoDB: Circuit breaker state tracking
- BrasilAPI: Verificação feriados nacionais brasileiros
- IAM Role: finops-scheduler-role (least privilege, staging-only)

**Schedule:**
- **STARTUP:** 8:00 AM BRT (11:00 UTC) - Segunda a Sexta
- **SHUTDOWN:** 6:00 PM BRT (21:00 UTC) - Segunda a Sexta
- **Feriados:** Automação SKIP (via BrasilAPI)

**Node Groups Strategy:**

| Node Group | Behavior | Workloads | Uptime | Justificativa |
|------------|----------|-----------|--------|---------------|
| **critical-always-on** (1× t3.medium) | Nunca desliga | GitLab, Harbor, ArgoCD, Prometheus/Grafana | 24/7 | GitLab jobs noturnos, observabilidade essencial |
| **regular** (2× t3.medium) | Automação start/stop | Keycloak, SonarQube, Kong, Redis, RabbitMQ | 50h/semana | Workloads non-critical, uso horário comercial |

**Justificativa Separação:**
- GitLab: Jobs agendados noturnos (backups 2 AM, security scans 4 AM) não podem ser interrompidos
- Harbor: Push/pull images pipelines automatizados podem ocorrer fora horário
- Prometheus/Grafana: Observabilidade 24/7 permite troubleshooting histórico

---

### Breakdown de Economia Detalhado

**Cenário COM Automação (50h/semana uptime):**

| Recurso | Custo 24/7 | Uptime % | Custo Otimizado | Economia |
|---------|------------|----------|-----------------|----------|
| EKS Control Plane (rateio) | $37.00 | 100% (obrigatório) | $37.00 | $0.00 |
| EC2 critical-always-on (1× t3.medium) | - | 100% (novo) | $30.00 | $0.00 (novo custo) |
| EC2 regular (2× t3.medium) | $60.00 | 30% (50h/215h) | $18.00 | **$42.00** ✅ |
| RDS db.t3.small auto-pause | $70.00 | 43% (pausado 57% tempo) | $30.00 | **$40.00** ✅ |
| Redis scaled to 0 | $10.00 | 30% | $5.00 | **$5.00** ✅ |
| RabbitMQ scaled to 0 | $10.00 | 30% | $5.00 | **$5.00** ✅ |
| Lambda + EventBridge | $0.00 | - | $2.00 | **-$2.00** (overhead) |
| **TOTAL COM AUTOMAÇÃO** | **$187.00** | | **$127.00** | **$60.00/mês** |

**Economia Mensal:** $60.00/mês
**Economia Anual:** $60.00 × 12 = **$720.00/ano (USD)** = **R$ 4.320/ano (BRL, taxa 6.0)**

**Percentual Redução:** $60 / $187 = **32.1% economia STAGING**

---

### Custos da Automação

**Investimento Inicial (One-time):**

| Item | Horas | Custo/Hora | Total |
|------|-------|------------|-------|
| Desenvolvimento Lambda (Python) | 6h | R$ 300/h | R$ 1.800 |
| Terraform módulo finops-scheduler | 2h | R$ 300/h | R$ 600 |
| Testes integrados (local + AWS) | 2h | R$ 300/h | R$ 600 |
| **TOTAL INVESTIMENTO** | **10h** | | **R$ 3.000** |

**Custos Operacionais Mensais:**

| Componente | Quantidade | Custo/Mês |
|------------|-----------|-----------|
| Lambda executions | 44 invocações/mês (2×/dia × 22 dias úteis) | $0.00 (free tier 1M requests) |
| Lambda compute | 300s × 44 × 512MB | $0.20 |
| EventBridge rules | 2 rules | $1.00 |
| DynamoDB (state tracking) | On-demand, <100 writes | $0.02 |
| CloudWatch Logs | 1MB/dia logs | $0.03 |
| S3 (Lambda code) | 5MB | $0.00 |
| **TOTAL OPERACIONAL** | | **$1.25/mês** (~$2/mês arredondado) |

---

### ROI e Análise Financeira

**Cálculo ROI Year 1:**

```
Economia Anual:      R$ 4.320
Investimento Inicial: R$ 3.000
Custo Operacional:   R$ 24 (R$ 2/mês × 12)
────────────────────────────────
Economia Líquida:    R$ 1.296

ROI Year 1 = (1.296 / 3.000) = 43.2%
```

**Payback Period:**

```
Payback = Investimento / Economia Mensal
Payback = R$ 3.000 / R$ 450 = 6.7 meses
```

**NPV 3 Anos (taxa desconto 10% a.a.):**

| Ano | Economia Anual | Desconto 10% | Valor Presente |
|-----|---------------|--------------|----------------|
| Year 0 | - | - | -R$ 3.000 (investimento) |
| Year 1 | R$ 4.320 | 1.10 | R$ 3.927 |
| Year 2 | R$ 4.320 | 1.21 | R$ 3.570 |
| Year 3 | R$ 4.320 | 1.33 | R$ 3.248 |
| **NPV Total** | | | **R$ 7.745** |

**ROI Cumulativo 3 Anos:** (R$ 7.745 / R$ 3.000) = **258%**

---

### 🚀 Status Atual da Economia (ATIVA desde 2026-02-02)

**EventBridge Automation:** ✅ HABILITADA
**Primeira Execução Automática:** 2026-02-03 08:00 BRT (segunda-feira)

**Economia Projetada:**
- **Mensal:** R$ 360/mês (USD $60, taxa 6.0)
- **Anual:** R$ 4.320/ano
- **Início:** 2026-02-03 (primeira semana completa)

**Tracking Mensal:**
| Métrica | Target | Status |
|---------|--------|--------|
| Uptime semanal | 50h (30%) | 📊 Monitoramento ativo |
| Economia mensal | R$ 360 | ⏳ Validação após 30 dias |
| Falhas startup/shutdown | <2/mês | ✅ Circuit breaker ativo |
| Lambda performance | <3s | ✅ Média 1.5s (5/5 testes) |

**Próxima Validação:** 2026-03-03 (30 dias operação)
- Cost Explorer: Comparar fev vs jan (baseline 24/7)
- CloudWatch Metrics: Uptime real vs projetado
- DynamoDB State: Verificar falhas acumuladas

**Recursos Ativos Gerando Economia:**
- Lambda START/STOP: 44 execuções/mês (~R$ 2/mês overhead)
- EventBridge Rules: 2 rules ENABLED (startup Mon-Fri 08:00 BRT, shutdown 18:00 BRT)
- DynamoDB Circuit Breaker: Auto-disable após 3 falhas
- SNS Notifications: Alerta email em falhas

---

### Análise de Sensibilidade

**Variação Uptime Real vs Projetado:**

| Cenário | Uptime Real | Economia/Ano | ROI Year 1 | Payback | Decisão |
|---------|-------------|--------------|-----------|---------|---------|
| **Pessimista** | 60h/semana (35%) | R$ 3.600 | 20% | 10 meses | ✅ Ainda viável |
| **Base Case** | 50h/semana (30%) | R$ 4.320 | 44% | 6.7 meses | ✅ **PLANEJADO** |
| **Otimista** | 40h/semana (24%) | R$ 5.040 | 68% | 5.6 meses | ✅ Ideal |

**Conclusão:** ROI positivo em **todos os cenários**, decisão **robusta a variações de uptime**.

---

### Comparação com Alternativas

| Abordagem | Custo Mensal | Economia/Ano | Toil/Mês | ROI Year 1 | Decisão |
|-----------|--------------|--------------|----------|-----------|---------|
| **Status Quo (24/7)** | $187 | $0 | 0h | N/A | ❌ REJEITADO (desperdício) |
| **Shutdown manual diário** | $135 | $624 | 8h (2×/dia × 20min × 22d) | -100% (custo oculto R$ 7.200/ano FTE) | ❌ REJEITADO (toil alto) |
| **Automação parcial (sem feriados)** | $140 | $564 | 1h (manutenção) | 5% | ❌ REJEITADO (ROI baixo) |
| **Automação completa (EventBridge)** | $127 | $720 | 0.5h (monitoramento) | 44% | ✅ **ESCOLHIDO** |
| **Delete STAGING (usar só PROD)** | $0 | $2.244 | - | N/A | ❌ REJEITADO (violação best practices) |

**Justificativa:** Automação completa tem **melhor custo-benefício**, zero toil operacional, ROI sólido 44%.

---

### Custos Operacionais Detalhados (Hidden Costs)

**Análise Agente FinOps (2026-01-30):** Identificação de custos não documentados inicialmente.

#### Breakdown Completo STAGING

| Componente | Quantidade | Custo/Mês | Observações |
|------------|-----------|-----------|-------------|
| **Lambda executions** | 44 calls/mês (2×/dia × 22d úteis) | $0.00 | Free tier (1M requests) |
| **Lambda compute** | 300s × 44 × 512MB | $0.15 | GB-seconds pricing |
| **EventBridge rules** | 2 rules (startup + shutdown) | $1.00 | $1/rule/mês |
| **DynamoDB on-demand** | 88 writes + 176 reads/mês | $0.03 | Circuit breaker state |
| **CloudWatch Logs** | 1MB/dia logs | $0.05 | 30d retention |
| **CloudWatch Metrics (custom)** | 5 metrics | $0.15 | finops.staging.* metrics |
| **NAT Gateway data transfer** | 3MB/mês (BrasilAPI) | $0.00 | $0.045/GB = negligível |
| **Data Transfer OUT** | 2MB/dia (RDS → Lambda logs) | $0.05 | CloudWatch ingestion |
| **KMS key (DynamoDB encryption)** | 1 key | $1.00 | Encryption at rest |
| **Snapshots RDS (testing)** | Nenhum (STAGING) | $0.00 | Apenas PRODUCTION |
| **TOTAL OPERACIONAL STAGING** | | **$2.43/mês** | Arredondado: $2.50/mês |

**Nota FinOps:** Custos hidden representam **+0.4%** do custo total ($2.43/$127 = 1.9%), portanto **não impactam ROI significativamente**.

#### Custos Incrementais por Ambiente

**Comparação STAGING vs PRODUCTION:**

| Item | STAGING | PRODUCTION | Diferença |
|------|---------|------------|-----------|
| Lambda compute | $0.15 | $0.30 | 2× calls (60 vs 44) |
| EventBridge | $1.00 | $1.00 | Mesmo |
| DynamoDB | $0.03 | $0.00 | Shared (custo já em STAGING) |
| CloudWatch Logs | $0.05 | $0.05 | Similar |
| KMS key | $1.00 | $0.00 | Shared (custo já em STAGING) |
| **Snapshots RDS** | $0.00 | **$1.65** | PROD-specific (7d retention) |
| **TOTAL** | **$2.43** | **$3.00** | +$0.57 incremental |

**Impacto no ROI:**

```
Economia STAGING ajustada:
Antes: $60/mês - $2.00/mês (estimated) = $58/mês
Agora: $60/mês - $2.43/mês (real) = $57.57/mês

ROI Year 1 ajustado:
Economia anual: $57.57 × 12 = $690.84 (vs $720 projetado)
Economia BRL: R$ 4.145/ano (vs R$ 4.320 projetado)
Diferença: -R$ 175/ano (-4%)

ROI: (R$ 4.145 - R$ 36) / R$ 3.000 = 137% → 43.6% (vs 44% projetado)
Payback: R$ 3.000 / (R$ 4.145/12) = 6.9 meses (vs 6.7 meses projetado)
```

**Conclusão FinOps:** Hidden costs ajustam ROI de **44% → 43.6%** (variação **negligível < 1%**). Decisão **mantida**: projeto APROVADO.

---

### Riscos e Mitigações

| Risco | Probabilidade | Impacto Financeiro | Mitigação | Custo Contingência |
|-------|--------------|-------------------|-----------|-------------------|
| **Falha startup (RDS timeout)** | 🟡 5% | $60/dia sem staging | Retry 3× exponential backoff, alerta PagerDuty | $0 (tempo DevOps) |
| **GitLab job perdido** | 🟢 2% | $200/rebuild | Health check bloqueia shutdown se jobs ativos | $0 (prevenção) |
| **BrasilAPI indisponível** | 🟢 1% | $2/feriado | Cache local DynamoDB (30d TTL), fallback lista estática | $0 (redundância) |
| **Lambda timeout 300s** | 🟢 1% | $0 | Operações assíncronas, Step Functions fallback | $50 (se necessário) |
| **Circuit breaker erro** | 🟢 1% | $60/dia | Manual override, notificação imediata, recovery runbook | $0 (processo) |

**Custo Total Contingência:** $50 one-time (Step Functions se necessário)

---

### Timeline e Milestones

| Fase | Prazo | Entregável | Responsável | Investimento Acumulado |
|------|-------|------------|-------------|------------------------|
| **Aprovação** | 2026-02-03 | Stakeholder sign-off (Arquitetura, FinOps, Security) | Tech Lead | R$ 0 |
| **Desenvolvimento** | 2026-02-10 | Lambda function + Terraform module | DevOps | R$ 2.400 (8h) |
| **Testes** | 2026-02-13 | Testes integrados local + AWS | QA + DevOps | R$ 3.000 (10h) |
| **Deploy** | 2026-02-17 | EventBridge habilitado, monitoramento ativo | DevOps | R$ 3.000 |
| **Validação** | 2026-03-17 | 1 mês operação, KPIs validados | FinOps | R$ 3.000 |
| **Retrospectiva** | 2026-03-20 | Economia real vs projetada, lessons learned | Time completo | R$ 3.000 |

**Break-even Point:** 2026-08-20 (6.7 meses após deploy)

---

### Métricas de Sucesso (KPIs)

**Operacionais:**

| Métrica | Target | Medição | Alerta |
|---------|--------|---------|--------|
| **Uptime real STAGING (8h-18h)** | ≥ 99.5% | CloudWatch Synthetics | < 99% = Investigar |
| **Startup time médio** | < 8 min | CloudWatch Logs | > 10 min = Warning |
| **Shutdown time médio** | < 5 min | CloudWatch Logs | > 7 min = Info |
| **Falhas startup/mês** | < 2 | Lambda errors metric | ≥ 3 = Critical |

**Financeiras:**

| Métrica | Target | Medição | Alerta |
|---------|--------|---------|--------|
| **Economia mensal observada** | R$ 450 ± 10% | AWS Cost Explorer | < R$ 400 = Investigar uptime |
| **Uptime real vs planejado** | 48-52h/semana | CloudWatch metrics | < 45h ou > 55h = Revisar schedule |
| **Custo Lambda operacional** | < $3/mês | AWS Billing | > $5 = Otimizar timeout |

**Qualidade:**

| Métrica | Target | Medição | Alerta |
|---------|--------|---------|--------|
| **Zero data loss** | 100% (0 incidentes) | Health checks + backups | 1 incidente = Post-mortem |
| **SLA disponibilidade** | 99.5% (8h-18h) | Uptime monitoring | < 99% = SLA breach |
| **Satisfação equipe** | > 8/10 | Survey trimestral | < 7/10 = Revisar automação |

---

### Impacto na Consolidação de Custos

**Atualização Marco 2 + STAGING Automation:**

```
Marco 0 + 1 + 2 Base (PROD):   $666.00/mês
Marco 2 Fase 8 (OpenTelemetry): +$19.70/mês
────────────────────────────────────────────
SUBTOTAL PROD:                  $685.70/mês

STAGING Cenários:
┌─────────────────────────────────────────────────────────────┐
│ Opção A: STAGING 24/7 (SEM automação)                      │
│ STAGING:                        +$187.00/mês                │
│ TOTAL (PROD + STAGING 24/7):    $872.70/mês ($10.472/ano)  │
├─────────────────────────────────────────────────────────────┤
│ Opção B: STAGING AUTOMATED (COM automação FinOps)          │
│ STAGING:                        +$127.00/mês                │
│ TOTAL (PROD + STAGING AUTO):    $812.70/mês ($9.752/ano)   │
│ ECONOMIA:                       -$60/mês ($720/ano)         │
└─────────────────────────────────────────────────────────────┘
```

**Recomendação:** Opção B - STAGING AUTOMATED ✅
- Economia: $720/ano (R$ 4.320/ano)
- ROI 44%, payback 6.7 meses
- Zero toil operacional
- Aderência FinOps best practices

---

### Próximos Passos

**Fase Aprovação (Semana 1 - até 2026-02-03):**
- [ ] Revisão arquitetura (Tech Lead) - 1h
- [ ] Aprovação FinOps (ROI validado) - 30min
- [ ] Aprovação Security (IAM policies) - 1h
- [ ] Sign-off Product Owner - 15min

**Fase Desenvolvimento (Semana 2 - até 2026-02-10):**
- [ ] Terraform module `finops-scheduler` (6h)
- [ ] Lambda function Python (4h)
- [ ] Testes locais (2h)

**Fase Validação (Semana 3 - até 2026-02-17):**
- [ ] Deploy staging (1h)
- [ ] Testes integrados AWS (2h)
- [ ] Habilitar EventBridge production (30min)
- [ ] Monitoramento 24h (observação contínua)

**Fase Monitoramento (1 mês - até 2026-03-17):**
- [ ] Validar economia real vs projetada
- [ ] Ajustar thresholds health checks
- [ ] Documentar runbooks recovery
- [ ] Retrospectiva equipe (lessons learned)

---

### Referências

- [Demanda Completa STAGING](../demands/2026-01-30-automacao-finops-staging.md)
- [ADR-024: FinOps Automation Multi-Ambiente](./decisions.md#adr-024)
- [Architecture Documentation](./architecture.md#fase-9-finops-automation-multi-ambiente)
- [Scripts Existentes](../../scripts/finops/shutdown-marco2.sh)
- [BrasilAPI Feriados](https://brasilapi.com.br/docs#tag/Feriados-Nacionais)

---

## 💡 Automação FinOps PRODUCTION (Planejada - ADR-024)

**Data Planejamento:** 2026-01-30
**Status:** 📝 PLANEJADO (aguardando STAGING 1 mês validação)
**Target Deploy:** 2026-04-15
**ROI Projetado:** 521% Year 1 (payback 1.9 meses)

### Contexto

Ambiente **PRODUCTION** (quando em operação) precisa estar disponível durante horário comercial estendido **7h-0h BRT** (17h/dia, 7 dias/semana), mas pode ser **desligado na madrugada (0h-7h)** quando não há operações críticas.

**Análise de Tráfego:**
- Horário pico: 8h-22h (90% do tráfego)
- Madrugada 0h-7h: < 2% do tráfego total
- Transações críticas: Finalizadas até 23h59 (política comercial)
- Manutenção: Janela 2h-6h (backups, patches, compactação)

**Custo PRODUCTION Atual (Projeção 24/7):**

| Componente | Quantidade | Custo/Mês | Observações |
|------------|-----------|-----------|-------------|
| EKS Control Plane (rateio 50%) | 1 cluster | $37.00 | Compartilhado com STAGING |
| EC2 nodes production (4× t3.large) | 4 nodes | $240.00 | Workloads produção, scaled 2× vs STAGING |
| RDS db.t3.large Multi-AZ | 1 instance | $280.00 | PostgreSQL production, alta disponibilidade |
| Redis Operator (production tier) | 6 pods | $20.00 | Cache + sessions produção |
| RabbitMQ Operator (production tier) | 6 pods | $20.00 | Message queue produção |
| S3 backups + artifacts | 1TB | $23.00 | Artifacts produção + snapshots automáticos |
| ALB production | 2 ALBs | $32.00 | Frontend + backend APIs |
| **TOTAL PRODUCTION 24/7** | | **$652.00/mês** | **R$ 3.912/mês** (taxa 6.0) |

**Perda Anual (downtime madrugada):** R$ 3.912/mês × 12 = **R$ 46.944/ano**

---

### Solução Proposta: EventBridge + Lambda Automation PROD

**Arquitetura:**
- EventBridge Scheduler: 2 rules (startup 7h BRT, shutdown 0h BRT 7 dias/semana)
- Lambda Function: Python 3.12, 512MB, 300s timeout (PROD-optimized)
- DynamoDB: Circuit breaker state tracking (shared com STAGING)
- BrasilAPI: Verificação feriados (PROD liga SEMPRE, incluindo feriados)
- IAM Role: finops-scheduler-production-role (least privilege, production-only)

**Schedule:**
- **STARTUP:** 7:00 AM BRT (10:00 UTC) - 7 dias/semana (incluindo feriados)
- **SHUTDOWN:** 00:00 (meia-noite) BRT (03:00 UTC) - 7 dias/semana
- **Feriados:** Automação LIGA (clientes ativos em feriados)

**Diferenças vs STAGING:**

| Aspecto | STAGING | PRODUCTION |
|---------|---------|------------|
| **Schedule** | 8h-18h Mon-Fri | 7h-0h 7 dias/semana |
| **Uptime** | 50h/semana (30%) | 119h/semana (71%) |
| **Feriados** | SKIP (não liga) | LIGA (clientes ativos) |
| **Health Checks** | GitLab jobs (básico) | Transações ativas + Conexões DB (rigoroso) |
| **Rollback** | Manual (30 min) | Automático (< 5 min) |
| **SLA** | 99.5% (8h-18h) | 99.9% (7h-0h) |
| **Circuit Breaker** | 3 falhas | 2 falhas (mais sensível) |
| **Snapshot RDS** | Não | Sim (pré-shutdown, RPO < 1h) |
| **Notificação Falha** | Slack | PagerDuty + Slack |

**Node Groups Strategy PROD:**

| Node Group | Behavior | Workloads | Uptime | Justificativa |
|------------|----------|-----------|--------|---------------|
| **critical-always-on** (1× t3.medium) | Nunca desliga | Prometheus/Grafana (observabilidade 24/7), GitLab CI/CD, AlertManager | 24/7 | Observabilidade essencial 24/7, CI/CD jobs noturnos (backups 2 AM, scans 4 AM), alertas madrugada |
| **production** (4× t3.large) | Automação start/stop | Apps cliente, APIs, Kong Gateway, Redis cache, RabbitMQ queues | 119h/semana | Workloads clientes, shutdown seguro madrugada (< 2% tráfego) |

**Justificativa Shutdown Madrugada:**
- Análise métricas: 0h-7h representa < 2% do tráfego total diário
- Transações críticas: Finalizadas até 23h59 (política comercial)
- Manutenção agendada: Janela 2h-6h (backups, patches, compactação)
- Observabilidade: Mantida 24/7 para troubleshooting histórico

---

### Breakdown de Economia Detalhado PRODUCTION

**Cenário COM Automação (119h/semana uptime = 71%):**

| Recurso | Custo 24/7 | Uptime % | Custo Otimizado | Economia |
|---------|------------|----------|-----------------|----------|
| EKS Control Plane (rateio) | $37.00 | 100% (obrigatório) | $37.00 | $0.00 |
| EC2 critical-always-on (1× t3.medium) | - | 100% (novo) | $30.00 | $0.00 (novo custo) |
| EC2 production (4× t3.large) | $240.00 | 71% (119h/168h) | $170.00 | **$70.00** ✅ |
| RDS db.t3.large (sem auto-pause Multi-AZ) | $280.00 | 71% (stop/start manual) | $199.00 | **$81.00** ✅ |
| Redis scaled to 0 | $20.00 | 71% | $14.00 | **$6.00** ✅ |
| RabbitMQ scaled to 0 | $20.00 | 71% | $14.00 | **$6.00** ✅ |
| S3 + ALB | $55.00 | 100% (sempre ativo) | $55.00 | $0.00 |
| Lambda + EventBridge | $0.00 | - | $3.00 | **-$3.00** (overhead) |
| **TOTAL COM AUTOMAÇÃO** | **$652.00** | | **$522.00** | **$130.00/mês** |

**Economia Mensal:** $130.00/mês
**Economia Anual:** $130.00 × 12 = **$1.560/ano (USD)** = **R$ 9.360/ano (BRL, taxa 6.0)**

**Percentual Redução:** $130 / $652 = **19.9% economia PRODUCTION**

---

### Custos da Automação PRODUCTION (Incremental)

**Investimento Incremental** (além do já feito para STAGING):

| Item | Horas | Custo/Hora | Total |
|------|-------|------------|-------|
| Adaptação Lambda PROD (health checks rigorosos) | 3h | R$ 300/h | R$ 900 |
| Testes PROD (simulação carga, failover) | 2h | R$ 300/h | R$ 600 |
| **TOTAL INVESTIMENTO INCREMENTAL** | **5h** | | **R$ 1.500** |

**Investimento Total Multi-Ambiente:**
- STAGING: R$ 3.000 (10h desenvolvimento)
- PRODUCTION: R$ 1.500 (5h incremental)
- **TOTAL: R$ 4.500**

**Custos Operacionais Mensais PROD:**

| Componente | Quantidade | Custo/Mês |
|------------|-----------|-----------|
| Lambda executions | 60 invocações/mês (2×/dia × 30 dias) | $0.00 (free tier) |
| Lambda compute | 300s × 60 × 512MB | $0.30 |
| EventBridge rules | 2 rules | $1.00 |
| DynamoDB (state tracking) | Shared com STAGING | $0.00 |
| CloudWatch Logs | 2MB/dia logs | $0.05 |
| Snapshots RDS (7 dias retention) | 100GB × 7 snapshots | $1.65 |
| **TOTAL OPERACIONAL PROD** | | **$3.00/mês** |

---

### ROI e Análise Financeira PRODUCTION

**Cálculo ROI Year 1:**

```
Economia Anual:      R$ 9.360
Investimento:        R$ 1.500 (incremental)
Custo Operacional:   R$ 36 (R$ 3/mês × 12)
────────────────────────────────
Economia Líquida:    R$ 7.824

ROI Year 1 = (7.824 / 1.500) = 521% ✅
```

**Payback Period:**

```
Payback = Investimento / Economia Mensal
Payback = R$ 1.500 / R$ 780 = 1.9 meses ✅
```

**NPV 3 Anos (taxa desconto 10% a.a.):**

| Ano | Economia Anual | Desconto 10% | Valor Presente |
|-----|---------------|--------------|----------------|
| Year 0 | - | - | -R$ 1.500 (investimento) |
| Year 1 | R$ 9.360 | 1.10 | R$ 8.509 |
| Year 2 | R$ 9.360 | 1.21 | R$ 7.736 |
| Year 3 | R$ 9.360 | 1.33 | R$ 7.037 |
| **NPV Total** | | | **R$ 21.782** |

**ROI Cumulativo 3 Anos:** (R$ 21.782 / R$ 1.500) = **1.452%** ✅

---

### Health Checks Rigorosos PRODUCTION

**PRÉ-SHUTDOWN (00:00 BRT):**

```python
def production_pre_shutdown_health_checks():
    """
    Health checks PRODUCTION - BLOQUEIAM shutdown se falharem
    SLA 99.9% requer validação rigorosa
    """
    checks = []

    # 1. Verificar transações ativas (RDS)
    active_transactions = check_rds_active_transactions()
    if active_transactions > 0:
        logger.warning(f"{active_transactions} active DB transactions - POSTPONING shutdown")
        notify_pagerduty(severity="warning", message="PROD shutdown postponed: active transactions")
        return False  # BLOQUEIA shutdown

    # 2. Verificar conexões abertas (> 5 min idle)
    idle_connections = check_rds_idle_connections(threshold_minutes=5)
    if idle_connections > 10:
        logger.warning(f"{idle_connections} idle DB connections > 5 min - POSTPONING shutdown")
        return False

    # 3. Verificar queues RabbitMQ (mensagens pendentes)
    pending_messages = check_rabbitmq_queue_depth()
    if pending_messages > 100:
        logger.warning(f"{pending_messages} pending messages in RabbitMQ - POSTPONING shutdown")
        notify_slack(channel="#prod-alerts", message=f"PROD shutdown postponed: {pending_messages} pending messages")
        return False

    # 4. Verificar jobs GitLab CI/CD
    running_jobs = check_gitlab_running_jobs()
    if running_jobs > 0:
        logger.info(f"{running_jobs} GitLab jobs running - OK (critical-always-on)")

    # 5. Verificar AlertManager silences (manutenção programada)
    if not check_alertmanager_maintenance_window():
        logger.warning("No maintenance window configured - POSTPONING shutdown")
        return False

    # 6. Criar snapshot RDS PRÉ-shutdown (RPO < 1h)
    snapshot_id = create_rds_snapshot(db_instance="marco2-prod-rds")
    logger.info(f"RDS snapshot created: {snapshot_id}")
    checks.append("snapshot_created")

    logger.info(f"PRODUCTION pre-shutdown health checks PASSED: {checks}")
    return True  # AUTORIZA shutdown
```

**Critérios Bloqueio PROD:**
- Transações DB ativas (commits pendentes)
- Conexões idle recentes (< 5 min)
- Mensagens RabbitMQ não processadas (> 100)
- Manutenção não agendada (AlertManager)

**Critérios NÃO Bloqueiam:**
- GitLab CI/CD jobs (rodam em critical-always-on)
- Prometheus scraping (observabilidade 24/7)
- Grafana queries (dashboards históricos)

---

### Snapshot RDS Automático PRODUCTION

**PRÉ-SHUTDOWN (Segurança):**

```bash
# Criar snapshot RDS antes de stop (segurança)
aws rds create-db-snapshot \
  --db-instance-identifier marco2-prod-rds \
  --db-snapshot-identifier "prod-autosave-$(date +%Y%m%d-%H%M%S)" \
  --tags Key=AutoGenerated,Value=finops-scheduler Key=Environment,Value=production

# Aguardar snapshot completo (timeout 10 min)
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier "prod-autosave-$(date +%Y%m%d-%H%M%S)"

# Lifecycle: Deletar snapshots > 7 dias
aws rds describe-db-snapshots \
  --db-instance-identifier marco2-prod-rds \
  --query "DBSnapshots[?SnapshotCreateTime<'$(date -d '7 days ago' --iso-8601)'].DBSnapshotIdentifier" \
  --output text | xargs -n1 aws rds delete-db-snapshot --db-snapshot-identifier
```

**Benefícios:**
- Recovery point objetivo (RPO): < 1h (snapshot 23h59)
- Recovery time objetivo (RTO): < 10 min (restore snapshot)
- Compliance: Auditoria completa (snapshots tagged)
- Custo: $1.65/mês (100GB × 7 snapshots × $0.095/GB/mês ÷ 7)

---

### Rollback Automático PRODUCTION

**Cenário: Startup Falha às 7h AM (horário comercial)**

**Impacto:**
- Clientes sem acesso: 7h-8h (1h downtime)
- Perda receita estimada: R$ 5.000/h
- SLA breach: 60 min > 43 min/mês (violação 99.9%)

**Rollback Automático:**

```python
def production_automatic_rollback():
    """
    Rollback automático se startup falha
    Threshold PROD: 2 falhas (vs 3 STAGING, mais sensível)
    """
    if startup_failures >= 2:
        logger.critical("PRODUCTION startup failed 2× - TRIGGERING AUTOMATIC ROLLBACK")

        # 1. Desabilitar automação (circuit breaker)
        disable_eventbridge_rules(environment="production")

        # 2. Startup MANUAL via runbook
        trigger_manual_startup_runbook(environment="production")

        # 3. Notificar on-call IMEDIATO (PagerDuty)
        send_pagerduty_alert(
            severity="critical",
            message="PROD startup failed - manual intervention required",
            escalation_level="P1"
        )

        # 4. Escalar para gerência (SLA breach iminente)
        send_slack_escalation(
            channel="#prod-incidents",
            message="PRODUCTION startup failed 2×. Manual recovery in progress. ETA 15 min.",
            mention=["@oncall", "@tech-lead", "@product-owner"]
        )

        # 5. Preparar comunicação externa (status page)
        prepare_status_page_update(
            status="investigating",
            eta="15 min",
            message="We are experiencing issues starting our systems. Team is working on recovery."
        )
```

**Recovery Manual:**

```bash
# Runbook: PROD Startup Manual
cd scripts/finops
./startup-marco2.sh production --force --skip-health-checks

# Validar serviços críticos
kubectl get pods -n production -l tier=critical
aws rds describe-db-instances --db-instance-identifier marco2-prod-rds

# Restore snapshot se RDS corrompido (última opção)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier marco2-prod-rds-restore \
  --db-snapshot-identifier "prod-autosave-20260130-235959"
```

---

## 🎯 Economia Consolidada Multi-Ambiente (Estratégia Evolutiva)

### Fase 1: Pré-PROD (Atual)
```
STAGING (Dev+Homolog):  Ligado 8h-18h Mon-Fri (desenvolvimento ativo)
PROD:                   Não existe
────────────────────────────────────
Economia STAGING:       R$ 4.320/ano
Economia PROD:          R$ 0/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 4.320/ano ✅
Investimento:           R$ 3.000 (STAGING)
ROI Year 1:             44%
Payback:                6.7 meses
```

### Fase 2: PROD Go-Live (Operação Simultânea)
```
STAGING (Dev+Homolog):  Ligado 8h-18h Mon-Fri (testes + homologação)
PROD:                   Ligado 7h-0h 7 dias/semana (operação)
────────────────────────────────────
Economia STAGING:       R$ 4.320/ano
Economia PROD:          R$ 9.360/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 13.680/ano ✅✅
Investimento Total:     R$ 4.500 (STAGING + PROD)
ROI Year 1:             204%
Payback:                3.9 meses
```

### Fase 3: PROD Estável (STAGING On-Demand)
```
STAGING:                DESLIGADO permanentemente (liga SOB DEMANDA)
PROD:                   Ligado 7h-0h 7 dias/semana (operação)
────────────────────────────────────
Economia STAGING:       R$ 12.744/ano ✅ (95% economia, uptime ~5%)
Economia PROD:          R$ 9.360/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 22.104/ano ✅✅✅
Investimento Total:     R$ 4.500 (não muda)
ROI Year 1:             391%
Payback:                2.4 meses
NPV 3 anos:             R$ 50.479 (ROI cumulativo 1.121%)
```

**Cálculo Fase 3 (STAGING sob demanda):**
- Custo STAGING 24/7: R$ 13.464/ano
- Uptime estimado Fase 3: 5% (ligando ~1×/semana para testes pontuais, 10h/mês)
- Custo otimizado: R$ 720/ano (5% × R$ 13.464 + overhead Lambda)
- **Economia: R$ 12.744/ano** (vs R$ 4.320/ano Fase 2)

**Gatilhos para Fase 3:**
- [ ] PROD estável > 3 meses sem incidentes críticos
- [ ] Cobertura testes automatizados > 80%
- [ ] Equipe confortável com CI/CD production-first
- [ ] STAGING usado < 2×/mês (validar necessidade real)

---

### ROI Consolidado por Fase

| Fase | Economia Anual | Investimento Acumulado | ROI Year 1 | Payback | NPV 3 Anos |
|------|---------------|------------------------|-----------|---------|------------|
| **Fase 1 (Atual)** | R$ 4.320 | R$ 3.000 | 44% | 6.7 meses | R$ 7.745 |
| **Fase 2 (Go-Live)** | R$ 13.680 | R$ 4.500 | 204% | 3.9 meses | R$ 32.261 |
| **Fase 3 (Estável)** | R$ 22.104 | R$ 4.500 | 391% | 2.4 meses | R$ 50.479 |

**NPV 3 Anos (Fase 3 estável):**
```
Year 1: R$ 22.104 / 1.10 = R$ 20.095
Year 2: R$ 22.104 / 1.21 = R$ 18.268
Year 3: R$ 22.104 / 1.33 = R$ 16.616
────────────────────────────────────
NPV 3 anos: R$ 54.979
Investimento: R$ 4.500
────────────────────────────────────
NPV líquido: R$ 50.479 (ROI cumulativo 1.121%) ✅✅✅
```

---

### Comparação Custos STAGING vs PRODUCTION

| Aspecto | STAGING | PRODUCTION | Justificativa |
|---------|---------|------------|---------------|
| **Custo 24/7** | $187/mês | $652/mês | PROD scaled 2× (t3.large vs t3.medium), Multi-AZ RDS |
| **Custo Otimizado** | $127/mês | $522/mês | Automação aplicada em ambos |
| **Economia Mensal** | $60/mês | $130/mês | PROD economia maior (mais recursos) |
| **Economia Anual** | R$ 4.320 | R$ 9.360 | PROD 2.17× maior economia |
| **Uptime** | 30% (50h/semana) | 71% (119h/semana) | PROD opera 7 dias/semana |
| **Investimento** | R$ 3.000 | R$ 1.500 (incremental) | PROD reutiliza código STAGING |
| **ROI Year 1** | 44% | 521% | PROD ROI 11.8× maior (economia > investimento) |
| **Payback** | 6.7 meses | 1.9 meses | PROD payback 3.5× mais rápido |

---

### Impacto na Consolidação de Custos

**Atualização Marco 2 + Multi-Ambiente Automation:**

```
Marco 0 + 1 + 2 Base (PROD):   $666.00/mês
Marco 2 Fase 8 (OpenTelemetry): +$19.70/mês
────────────────────────────────────────────
SUBTOTAL PROD:                  $685.70/mês

Multi-Ambiente Cenários:
┌─────────────────────────────────────────────────────────────────────┐
│ Fase 1 (Pré-PROD): STAGING automação apenas                        │
│ STAGING Automated:              +$127.00/mês                        │
│ TOTAL (PROD + STAGING AUTO):    $812.70/mês ($9.752/ano)           │
│ ECONOMIA vs 24/7:               -$60/mês ($720/ano)                 │
├─────────────────────────────────────────────────────────────────────┤
│ Fase 2 (Go-Live): STAGING + PRODUCTION automação simultânea        │
│ STAGING Automated:              +$127.00/mês                        │
│ PRODUCTION Automated:           +$522.00/mês                        │
│ TOTAL (PROD + STAGING + PROD):  $1.334.70/mês ($16.016/ano)        │
│ ECONOMIA vs 24/7:               -$190/mês ($2.280/ano = R$ 13.680) │
├─────────────────────────────────────────────────────────────────────┤
│ Fase 3 (Estável): STAGING on-demand + PRODUCTION automação         │
│ STAGING On-Demand (5% uptime):  +$9.35/mês (vs $187 24/7)          │
│ PRODUCTION Automated:           +$522.00/mês                        │
│ TOTAL (PROD + STAGING MIN):     $1.217.05/mês ($14.604/ano)        │
│ ECONOMIA vs 24/7 Fase 2:        -$307.65/mês ($3.692/ano = R$ 22.104) │
└─────────────────────────────────────────────────────────────────────┘
```

**Recomendação:** Implementação faseada ✅
- **Fase 1:** STAGING automação → Validação técnica, ROI 44%
- **Fase 2:** PRODUCTION automação → Economia consolidada R$ 13.680/ano, ROI 204%
- **Fase 3:** STAGING on-demand → Economia máxima R$ 22.104/ano, ROI 391%

---

### Timeline e Dependências

| Fase | Prazo | Entregável | Responsável | Milestone Crítico |
|------|-------|------------|-------------|-------------------|
| **STAGING deploy** | 2026-02-17 | Automação STAGING ativa | DevOps | 1 mês validação SEM falhas |
| **STAGING validação** | 2026-03-17 | KPIs validados (SLA 99.5%, economia R$ 450/mês) | FinOps | Go/No-Go PROD automation |
| **PROD environment** | 2026-04-01 | Marco 3 deployado, workloads ativos | Infra Team | RDS, nodes, apps production |
| **PROD automation dev** | 2026-04-08 | Lambda PROD + health checks rigorosos | DevOps (5h) | STAGING learnings aplicados |
| **PROD automation deploy** | 2026-04-15 | EventBridge PROD habilitado | DevOps | Testes carga + runbooks |
| **PROD validação** | 2026-06-15 | SLA 99.9% confirmado, economia R$ 780/mês | FinOps + Ops | 2 meses operação estável |
| **Fase 3 (On-demand)** | 2026-09-15 | STAGING on-demand ativo | FinOps | PROD estável 3 meses |

**Milestone Crítico:** PROD automation SOMENTE após STAGING 1 mês operação SEM falhas

---

### Referências Multi-Ambiente

- [Demanda STAGING](../demands/2026-01-30-automacao-finops-staging.md)
- [Demanda PRODUCTION](../demands/2026-01-30-automacao-finops-production.md)
- [ADR-024: FinOps Automation Multi-Ambiente](./decisions.md#adr-024)
- [Architecture Documentation](./architecture.md#fase-9-finops-automation-multi-ambiente)
- [Risks STAGING](./risks.md#r-019-riscos-automação-finops-staging)
- [Risks PRODUCTION](./risks.md#r-020-riscos-automação-finops-production)
- [Plano Executável Multi-Ambiente](../plan/aws-execution/fase-8-finops-multi-ambiente-automation.md)

---

## 🧮 Breakdown Detalhado por Marco

### Marco 0: Baseline & State Management

| Componente | Especificação | Custo/Mês | Custo/Ano |
|------------|---------------|-----------|-----------|
| S3 Terraform State | 10MB storage, 100 requests/mês | $0.05 | $0.60 |
| DynamoDB Lock Table | On-demand, <1k requests | $0.02 | $0.24 |
| **TOTAL Marco 0** | | **$0.07** | **$0.84** |

**Observações:**
- Custo desprezível (< $1/ano)
- Backend S3 com versioning habilitado (disaster recovery)

---

### Marco 1: Infraestrutura Base EKS

| Componente | Especificação | Quantidade | Custo Unitário | Custo/Mês |
|------------|---------------|------------|----------------|-----------|
| **EKS Control Plane** | Managed Kubernetes | 1 cluster | $73.00 | $73.00 |
| **EC2 Nodes - System** | t3.medium (2 vCPU, 4GB RAM) | 2 nodes | $30.37 | $60.74 |
| **EC2 Nodes - Workloads** | t3.medium (2 vCPU, 4GB RAM) | 3 nodes | $30.37 | $91.11 |
| **EC2 Nodes - Critical** | t3.medium (2 vCPU, 4GB RAM) | 2 nodes | $30.37 | $60.74 |
| **EBS Volumes (Root)** | gp3 50GB por node | 7 nodes | $4.00 | $28.00 |
| **NAT Gateways** | 2 AZs (reaproveitados) | 2 NAT GW | $32.85 | $65.70 |
| **Data Transfer NAT** | ~500GB/mês egress | | | ~$22.50 |
| **VPC Endpoints** | Interface endpoints (opcional) | 0 | $7.20 | $0.00 |
| **EKS Add-ons** | vpc-cni, kube-proxy, coredns, ebs-csi | 4 add-ons | $0.00 | $0.00 |
| **TOTAL Marco 1** | | | | **$401.79** |

**Observações:**
- **Economia NAT Gateways:** Reaproveitamento de VPC existente economiza $65.70/mês ($788.40/ano) se comparado a criar nova VPC
- **Reserved Instances:** Potencial economia de 31% (~$124/ano) se converter nodes para RI 1-year
- **Spot Instances:** Não aplicável (platform services requerem estabilidade)

**Projeção 12 Meses:**
```
Base: $401.79/mês × 12 = $4.821.48/ano
Com RI (31% desconto): $401.79 × 0.69 × 12 = $3.326.82/ano
Economia RI: $1.494.66/ano
```

---

### Marco 2: Platform Services

| Componente | Especificação | Custo/Mês | Observações |
|------------|---------------|-----------|-------------|
| **Fase 1: ALB Controller** | Pods em nodes existentes | $0.00 | Sem overhead |
| **Fase 2: Cert-Manager** | Pods em nodes existentes | $0.00 | CRDs gratuitos |
| **Fase 3: Prometheus Stack** | | **$2.56** | |
| ├─ EBS PVC Prometheus | gp3 20GB | $1.60 | Métricas retention 15 dias |
| ├─ EBS PVC Grafana | gp3 5GB | $0.40 | Dashboards + config |
| ├─ EBS PVC Alertmanager | gp3 2GB | $0.16 | Alerts storage |
| └─ Secrets Manager | 1 secret (Grafana password) | $0.40 | KMS encryption |
| **Fase 4: Loki + Fluent Bit** | | **$19.70** | |
| ├─ S3 Loki Storage | 500GB (estimado) | $11.50 | $0.023/GB/mês |
| ├─ S3 Requests | PUT 10M, GET 5M | $0.50 | Ingestion + queries |
| ├─ S3 Data Transfer | 100GB egress | $3.00 | Queries from Grafana |
| ├─ EBS PVC Loki Write | gp3 10GB × 2 replicas | $1.60 | WAL (Write-Ahead Log) |
| ├─ EBS PVC Loki Backend | gp3 10GB × 2 replicas | $1.60 | Index cache |
| └─ S3 Lifecycle Mgmt | 30 dias retention | $1.50 | Automated expiration |
| **Fase 5: Network Policies** | Calico policy-only | $0.00 | Sem nodes adicionais |
| **Fase 6: Cluster Autoscaler** | Pod em nodes existentes | $0.00 | IRSA gratuito |
| **Fase 7: Test Applications** | | **$32.40** | |
| ├─ ALB nginx-test | Internet-facing | $16.20 | LCU charges ~$5/mês |
| └─ ALB echo-server | Internet-facing | $16.20 | LCU charges ~$5/mês |
| **Fase 8: OpenTelemetry (Traces)** | | **$19.70** | **NOVO** |
| ├─ S3 Tempo Storage | 500GB traces | $11.50 | $0.023/GB/mês |
| ├─ S3 API Requests | PUT 5M, GET 2M | $5.00 | Trace ingestion + queries |
| ├─ EBS PVC Tempo Ingester | gp3 20GB | $1.60 | Write-Ahead Log |
| └─ EBS PVC Tempo Compactor | gp3 20GB | $1.60 | Compaction cache |
| **TOTAL Marco 2** | | **$74.36** | **Atualizado** |

**Observações Fase 4 (Loki):**
- **Economia vs CloudWatch:** $50/mês CloudWatch - $19.70/mês Loki = **$30.30/mês saved** ($363.60/ano)
- **ROI:** Break-even em 1 mês (comparado a CloudWatch Logs)
- **S3 Lifecycle otimização:** Após 90 dias mover para Glacier economizaria $9/mês adicional (80% storage cost)

**Observações Fase 7 (Test Apps):**
- **Consolidação ALBs:** Usando IngressGroup annotation, reduziria para 1 ALB ($16.20/mês saved)
- **Fase 7.1 (TLS):** Adiciona $0.90/mês (Route53 hosted zone), total $33.30/mês

**Observações Fase 8 (OpenTelemetry Traces):**
- **ADR-020:** Grafana Tempo escolhido vs Jaeger (economia $205.55/mês com Cassandra backend)
- **Componentes:** Tempo backend (6 pods) + OpenTelemetry Collector (2 pods Gateway mode)
- **Integração:** Correlação traces ↔ logs ↔ metrics em Grafana (single pane observability)
- **Otimizações possíveis:** Sampling 10% + retenção 7 dias reduziria para $4.45/mês (economia $15.25/mês)
- **IRSA:** TempoS3Role-k8s-platform-prod (padrão reutilizado de Loki)

**Breakdown Platform Services (Atualizado):**
```
Monitoring (Fase 3): $2.56/mês (3.4%)
Logging (Fase 4): $19.70/mês (26.5%)
Test Apps (Fase 7): $32.40/mês (43.6%)
Tracing (Fase 8): $19.70/mês (26.5%)  ← NOVO
──────────────────────────────────
Total Marco 2: $74.36/mês (100%)
```

---

## 💸 Consolidação Marco 0 + Marco 1 + Marco 2 + Fase 8

| Categoria | Componentes | Custo/Mês | % Total |
|-----------|-------------|-----------|---------|
| **Compute** | EKS Control Plane + EC2 Nodes | $285.59 | 41.6% |
| **Storage** | EBS (Root + PVCs) + S3 (Loki + Tempo) | $67.76 | 9.9% |
| **Networking** | NAT Gateways + Data Transfer + ALBs | $120.60 | 17.6% |
| **Platform Services** | Monitoring + Logging + Tracing | $41.96 | 6.1% |
| **Test Apps** | 2 ALBs | $32.40 | 4.7% |
| **Secrets** | AWS Secrets Manager | $0.40 | 0.1% |
| **Database** | DynamoDB State Lock | $0.25 | 0.0% |
| **VPC (Reused)** | NAT Gateways (baseline) | $65.70 | 9.6% |
| **TOTAL Marco 2 + Fase 8** | | **$685.70** | **100%** |

### Gráfico de Distribuição

```
Compute (43%) ████████████████████████████
Storage (7%)  ███████
Networking (18%) ██████████████████
Platform (3%) ███
Test Apps (5%) █████
NAT GW Reused (10%) ██████████
Other (14%) ██████████████
```

---

## 🔄 Custos Fixos vs Variáveis + Economia Start/Stop

**Referência:** [ADR-022](decisions.md#adr-022-startupshutdown-automation-strategy-finops) - Startup/Shutdown Automation Strategy

### Breakdown Fixos vs Variáveis (Marco 2 + Fase 8)

Análise detalhada dos componentes que persistem durante shutdown (custos fixos) vs componentes que podem ser desligados (custos variáveis):

| Categoria | Componente | Custo/Mês | % | Tipo | Comportamento Shutdown |
|-----------|------------|-----------|---|------|------------------------|
| **CUSTOS FIXOS (Always On)** | | **$200.75** | **29.3%** | | |
| Compute | EKS Control Plane | $73.00 | 10.6% | Fixo | Não pode ser stopped (AWS managed) |
| Networking | NAT Gateways (2) | $66.00 | 9.6% | Fixo | Necessário para cluster (sempre on) |
| Storage | S3 (State + Loki + Tempo) | $34.57 | 5.0% | Fixo | Dados persistentes (logs, traces, state) |
| Networking | ALBs (2) | $16.20 | 2.4% | Fixo | Ingress endpoints (sempre on) |
| Networking | CloudWatch Logs | $10.08 | 1.5% | Fixo | Retenção logs infraestrutura |
| Secrets | AWS Secrets Manager | $0.40 | 0.1% | Fixo | Credentials (Grafana, futuros) |
| DNS | Route53 Hosted Zone | $0.50 | 0.1% | Fixo | DNS (Marco 3) |
| **CUSTOS VARIÁVEIS (Stop/Start)** | | **$484.95** | **70.7%** | | |
| Compute | EC2 Nodes (7× t3.medium) | $477.12 | 69.6% | Variável | Terminate (ASG scale to 0) |
| Storage | EBS Volumes (PVCs) | $5.36 | 0.8% | Variável | Persist (detached, custo mantido) |
| Networking | Data Transfer | $2.47 | 0.3% | Variável | Zero quando nodes stopped |
| **TOTAL MARCO 2 + FASE 8** | | **$685.70** | **100%** | | |

### Cenários de Economia Start/Stop

**Premissa:** Infraestrutura é desligada (ASG scale to 0) fora do horário de uso, mantendo apenas custos fixos.

| Cenário | Uptime | Dias/Semana | Horas/Dia | Custo Fixo | Custo Variável | Total/Mês | Economia/Mês | Economia/Ano | % Redução |
|---------|--------|-------------|-----------|------------|----------------|-----------|--------------|--------------|-----------|
| **Baseline (24/7)** | 100% | 7 dias | 24h | $200.75 | $484.95 | $685.70 | - | - | - |
| **Dev 8h/dia** | 33% | 5 dias | 8h | $200.75 | $160.74 | $361.49 | **$324.21** | **$3,890.52** | **47.3%** |
| **Dev 10h/dia** | 42% | 5 dias | 10h | $200.75 | $200.93 | $401.68 | $284.02 | $3,408.24 | 41.4% |
| **Dev 12h/dia** | 50% | 5 dias | 12h | $200.75 | $241.11 | $441.86 | $243.84 | $2,926.08 | 35.6% |
| **Prod 24/5** (noturno off) | 71% | 5 dias | 24h | $200.75 | $344.31 | $545.06 | $140.64 | $1,687.68 | 20.5% |
| **Prod 16/7** (noturno off) | 67% | 7 dias | 16h | $200.75 | $324.92 | $525.67 | $160.03 | $1,920.36 | 23.3% |

**Cálculo Custo Variável por Cenário:**
- Custo Variável = $484.95 × (Uptime %)
- Exemplo Dev 8h/dia: $484.95 × 33% = $160.74

### ROI Automação Startup/Shutdown

**Investimento Inicial:**
- Desenvolvimento scripts bash (up.sh, down.sh, health-check.sh): 8h × $50/h = $400
- GitHub Actions workflows (automação CI/CD): 4h × $50/h = $200
- Testes e documentação: 2h × $50/h = $100
- **TOTAL INVESTIMENTO:** $700

**Economia Anual por Cenário:**
| Cenário | Economia/Ano | ROI Year 1 | Payback |
|---------|--------------|------------|---------|
| Dev 8h/dia | $3,890.52 | **556%** | **1.6 meses** |
| Dev 10h/dia | $3,408.24 | 487% | 1.8 meses |
| Dev 12h/dia | $2,926.08 | 418% | 2.2 meses |
| Prod 24/5 | $1,687.68 | 241% | 3.7 meses |

**Recomendação:** Implementar IMEDIATAMENTE para ambientes dev/staging. ROI Year 1 de 556% justifica investimento de 14h development.

### Cold Start Times & Operational Impact

| Operação | Tempo | Descrição |
|----------|-------|-----------|
| **Startup (Nodes Only)** | 5-8 min | ASG scale up → Nodes join → Pods scheduled |
| **Shutdown (Nodes Only)** | 2-4 min | Drain pods → Terminate nodes (ASG scale to 0) |
| **Startup (Full Cluster)** | 15-18 min | Terraform apply (EKS + nodes + Helm releases) |

**Health Checks Pós-Startup:**
```bash
# Validação automática (scripts/health-check.sh)
✅ 7 nodes Ready
✅ 36 pods Running (monitoring namespace)
✅ Grafana UI accessible (http://localhost:3000)
✅ Loki ingestion functional (LogQL queries)
✅ Tempo traces functional (TraceQL queries)
```

### Custos Fixos Inevitáveis

Mesmo com shutdown completo (ASG scale to 0), estes custos persistem:

| Componente | Custo/Mês | Justificativa |
|------------|-----------|---------------|
| EKS Control Plane | $73.00 | AWS managed, não pode ser stopped |
| NAT Gateways (2) | $66.00 | Necessário para cluster restart, não deleteable sem downtime |
| S3 Storage | $34.57 | Dados persistentes (logs, traces, terraform state) |
| ALBs (2) | $16.20 | Ingress endpoints, não destroyable sem recreate |
| CloudWatch Logs | $10.08 | Retenção logs infraestrutura (auditoria) |
| Secrets Manager | $0.40 | Credentials (Grafana admin, futuros) |
| Route53 Hosted Zone | $0.50 | DNS (Marco 3, zero custo se não criado ainda) |
| **TOTAL FIXO** | **$200.75/mês** | **29.3% do custo total** |

**Implicação:** Economia máxima possível é **70.7%** ($484.95/mês), nunca 100%.

### Marco 3 Considerações RDS

**Problema:** RDS PostgreSQL (Marco 3 Data Services) não pode ficar stopped > 7 dias. AWS auto-restart após 7 dias.

**Soluções Avaliadas:**

| Abordagem | Economia/Mês | Restore Time | Custo Snapshot | Complexidade |
|-----------|--------------|--------------|----------------|--------------|
| **RDS 24/7 (Always On)** | $0 | Instant | $0 | ⚡ Baixa |
| **RDS Stop/Start (< 7d)** | $50 (Full) | 3-5 min | $0 | 🟡 Média |
| **Snapshot + Delete + Restore** | $40.50 | 10-15 min | $9.50/mês (100GB) | 🔴 Alta |

**Decisão Recomendada (Marco 3):**
- **Dev/Staging:** Snapshot + Delete + Restore (economia $40.50/mês líquida)
- **Produção:** RDS 24/7 (dados persistentes necessários, zero downtime)

### Scripts Implementados

**Localização:** `platform-provisioning/aws/kubernetes/terraform/scripts/`

| Script | Descrição | Tempo Exec | Status |
|--------|-----------|------------|--------|
| `up.sh` | Startup infraestrutura (ASG scale + health checks) | 6-8 min | ✅ Implementado |
| `down.sh` | Shutdown infraestrutura (drain + scale to 0) | 3-4 min | ✅ Implementado |
| `health-check.sh` | Validação pós-startup (nodes, pods, Grafana) | 1-2 min | ✅ Implementado |

**Uso Manual:**
```bash
# Ligar infraestrutura (início do dia)
./scripts/up.sh
# Output: "✅ Infrastructure started in 6m23s. Grafana: http://..."

# Desligar infraestrutura (fim do dia)
./scripts/down.sh
# Output: "☑️ Infrastructure stopped. Saving $22.05 tonight."
```

### Automação GitHub Actions (Roadmap Q2 2026)

**Workflows Planejados:**
- `.github/workflows/infra-shutdown.yml` → Cron: 22:00 UTC (19h BRT) Mon-Fri
- `.github/workflows/infra-startup.yml` → Cron: 11:00 UTC (8h BRT) Mon-Fri
- Notifications: Slack `#infrastructure` channel
- Fallback: Manual trigger via `workflow_dispatch`

**Economia Automação Q2 2026:** $324.21/mês ($3,890.52/ano) com 8h/dia uptime

### Métricas de Sucesso

**KPIs Fase 1 (Manual):**
- ✅ Cold start < 10 min (target: 5-8 min)
- ✅ Zero data loss em 30 shutdowns consecutivos
- ✅ Economia > $300/mês
- ✅ Health check success rate > 95%

**KPIs Fase 2 (GitHub Actions):**
- [ ] Automação success rate > 99%
- [ ] Notificações < 2 min após evento
- [ ] Rollback automático < 5 min (se health check fail)
- [ ] Economia anualizada > $3.500/ano

---

## 📉 Economia e Otimizações

### Economias Já Realizadas

| Decisão | vs Alternativa | Economia/Mês | Economia/Ano | Status |
|---------|----------------|--------------|--------------|--------|
| Loki vs CloudWatch | $50/mês vs $19.70/mês | $30.30 | $363.60 | ✅ Implementado |
| VPC Reuse vs New VPC | $0 vs $65.70 NAT GW | $65.70 | $788.40 | ✅ Implementado |
| Calico policy-only vs Overlay | $0 vs $100/mês nodes | $100.00 | $1.200.00 | ✅ Implementado |
| ACM vs Third-party CA | $0 vs $33/mês | $33.00 | $396.00 | ✅ Implementado (Fase 7.1) |
| Tempo vs Jaeger+Cassandra | $19.70 vs $210/mês | $190.30 | $2.283.60 | ✅ Implementado (Fase 8) |
| **Operators vs Bitnami Tanzu** | **$0 vs $6.000/mês** | **$6.000.00** | **$72.000.00** | ⏳ **Marco 3 (ADR-023)** |
| **TOTAL ECONOMIAS** | | **$6.419.30** | **$77.031.60** | |

### Otimizações Futuras (Não Implementadas)

| Otimização | Economia Estimada/Mês | Economia/Ano | Esforço | Risco |
|------------|------------------------|--------------|---------|-------|
| **Reserved Instances (1-year)** | ~$124.00 | $1.488.00 | BAIXO | BAIXO |
| **S3 Glacier após 90 dias** | $9.00 | $108.00 | BAIXO | BAIXO |
| **Consolidar ALBs (IngressGroup)** | $16.20 | $194.40 | MÉDIO | MÉDIO |
| **Spot Instances (workloads)** | $45.00 | $540.00 | ALTO | ALTO |
| **VPC Endpoints (evitar NAT)** | $20.00 | $240.00 | MÉDIO | BAIXO |
| **Cluster Autoscaler scale-down** | $31.00 | $372.00 | BAIXO | MÉDIO |
| **TOTAL POTENCIAL** | **$245.20** | **$2.942.40** | | |

### ROI das Otimizações

**Quick Wins (BAIXO esforço, BAIXO risco):**
1. **Reserved Instances:** $1.488/ano economia, 1h esforço
2. **S3 Lifecycle Glacier:** $108/ano economia, 30min esforço
3. **Cluster Autoscaler tuning:** $372/ano economia (já implementado, aguardando dados)

**Custo-Benefício:**
- RI + Glacier = $1.596/ano economia, ~1.5h esforço total
- ROI: $1.064/hora de trabalho

---

## 🔮 Marco 3: Workloads - VALORES REAIS APROVADOS

### Fase 1 (Sem Domínio) - Implementação Imediata

**ADR-021:** Deployment sem domínio registrado, usando LoadBalancer (NLB) para databases e ALB DNS HTTP para workloads.

| Componente | Especificação | Custo/Mês | Observações |
|------------|---------------|-----------|-------------|
| **Data Services (Tier 1)** | | **$69.18** | ✅ **COM Quick Wins** |
| ├─ RDS PostgreSQL | db.t3.small (2 vCPU, 2GB), Single-AZ | $37.78 | ✅ Quick Win: -$26.28/mês vs db.t3.medium |
| ├─ **Redis (Spotahome Operator)** | RedisFailover CRD (1 master + 2 replicas + 3 sentinels) | **$0.00** | Usa nodes existentes, **ADR-023** |
| ├─ **RabbitMQ (Cluster Operator)** | RabbitmqCluster CRD (3 nodes) | **$0.00** | Usa nodes existentes, **ADR-023** |
| ├─ ~~NLB PostgreSQL~~ | ~~LoadBalancer para acesso externo~~ | ~~$16.20~~ | ✅ Quick Win: ExternalName Service ($0.00) |
| ├─ NLB Redis | LoadBalancer para acesso externo | $16.20 | Redis CLI, Redis Desktop Manager |
| ├─ S3 Buckets | gitlab-artifacts + harbor-images (700GB) | $11.70 | ✅ Quick Win: Intelligent-Tiering + Glacier |
| **Workloads (Tier 2)** | | **$48.60** | |
| ├─ GitLab CE | ALB DNS HTTP (sem domínio) | $16.20 | CI/CD Platform (usa RDS shared + Redis + S3) |
| ├─ ArgoCD | ALB DNS HTTP | $16.20 | GitOps platform |
| ├─ Harbor | ALB DNS HTTP + S3 backend | $16.20 | Registry + Trivy scan (usa RDS shared + S3) |
| **SUBTOTAL Marco 3 Fase 1 (COM Quick Wins)** | | **$117.78** | ✅ **Economia $98.82/mês vs baseline** |

### 🏆 Quick Wins FinOps Implementadas (2026-02-02)

**Framework:** executor-terraform.md POST-HOOK update-costs.md

| Otimização | Baseline | Otimizado | Economia/Mês | Economia/Ano | ROI | Payback | Status |
|------------|----------|-----------|--------------|--------------|-----|---------|--------|
| **RDS db.t3.small inicial** | db.t3.medium ($64.06) | db.t3.small ($37.78) | **$26.28** | **$315.36** | 15.8:1 | 0.8 meses | ✅ **IMPLEMENTADO** |
| **S3 Intelligent-Tiering** | STANDARD ($16.10) | INTELLIGENT_TIERING ($11.70) | **$4.40** | **$52.80** | 52.8:1 | 0.02 meses | ✅ **IMPLEMENTADO** |
| **S3 Lifecycle Glacier** | STANDARD_IA ($16.10) | GLACIER_IR 180d ($7.10) | **$48.00** | **$576.00** | ∞ | imediato | ✅ **JÁ EXISTENTE** |
| **PostgreSQL ExternalName** | NLB ($16.20) | Service ClusterIP ($0.00) | **$16.20** | **$194.40** | ∞ | imediato | ✅ **IMPLEMENTADO** |
| **TOTAL QUICK WINS** | | | **$94.88/mês** | **$1.138.56/ano** | **12.0:1** | **1 mês** | |

**Detalhamento das Implementações:**

1. **RDS db.t3.small inicial** (Módulo: `marco3/modules/postgresql/variables.tf:24`)
   - Alterado default de `db.t3.medium` → `db.t3.small`
   - Justificativa: GitLab CE inicial (<50 usuários) não precisa 4GB RAM
   - Escalável: Upgrade para db.t3.medium é zero-downtime (apenas terraform apply)
   - Economia: $315.36/ano ($26.28/mês)

2. **S3 Intelligent-Tiering** (Módulo: `marco3/modules/s3-buckets/main.tf`)
   - GitLab artifacts: Transition para INTELLIGENT_TIERING (day 0)
   - Harbor images: Transition para INTELLIGENT_TIERING (day 0)
   - Archive Access tier: 90 dias
   - Deep Archive Access tier: 180 dias
   - Economia: $52.80/ano ($4.40/mês)

3. **S3 Lifecycle Glacier** (Já existente no código)
   - Harbor images: STANDARD → STANDARD_IA (90d) → GLACIER_IR (180d)
   - GitLab artifacts: Expire após 90 dias (cleanup automático)
   - Economia: $576.00/ano ($48.00/mês)

4. **PostgreSQL ExternalName Service** (Módulo: `marco3/modules/postgresql/main.tf`)
   - Removido NLB LoadBalancer ($16.20/mês)
   - Kubernetes Service tipo ExternalName apontando para RDS endpoint
   - Acesso interno: `postgresql-external.default.svc.cluster.local:5432`
   - Economia: $194.40/ano ($16.20/mês)

**Investimento Total:** 2.5h desenvolvimento ($75 @ $30/h)

**ROI Consolidado:**
- Economia anual: $1.138.56/ano
- Investimento: $75
- ROI: (1.138,56 / 75) = **15.2:1**
- Payback: 75 / (1.138,56 / 12) = **0.79 meses (~24 dias)**

### Otimizações Q1 2026 (Implementação Paralela)

| Otimização | Economia/Mês | Esforço | Status |
|------------|--------------|---------|--------|
| **Reserved Instances EC2 (1 ano)** | -$124.00 | 1h | ✅ Aprovado |
| **Consolidar ALBs (IngressGroup)** | -$16.20 | 2h | ✅ Aprovado |
| **PostgreSQL RDS Shared** | -$25.00 | 4h | ✅ Aprovado (já contemplado) |
| **TOTAL ECONOMIA Q1** | **-$165.20** | **7h** | |

### Projeção Consolidada REAL (Atualizada 2026-02-02 - Quick Wins)

```
Marco 0 + 1 + 2 Base:              $666.00/mês
Marco 2 Fase 8 (OpenTelemetry):     +$19.70/mês
Marco 3 Data Services:              +$69.18/mês  ✅ COM Quick Wins
Marco 3 Workloads:                  +$48.60/mês  ✅ COM Quick Wins
──────────────────────────────────────────────────
SUBTOTAL COM QUICK WINS:           $803.48/mês ($9.641.76/ano)

Quick Wins FinOps Implementadas (2026-02-02):
✅ RDS db.t3.small:                 -$26.28/mês
✅ S3 Intelligent-Tiering:          -$4.40/mês
✅ S3 Lifecycle Glacier:            -$48.00/mês
✅ PostgreSQL ExternalName:         -$16.20/mês
──────────────────────────────────────────────────
SUBTOTAL QUICK WINS:               -$94.88/mês (-$1.138.56/ano)

Otimizações Q1 2026 (Planejadas):
- Reserved Instances EC2:          -$124.00/mês
- Consolidar ALBs (IngressGroup):   -$16.20/mês
──────────────────────────────────────────────────
TOTAL ECONOMIA Q1:                 -$140.20/mês (-$1.682.40/ano)

CUSTO FASE 1 FINAL OTIMIZADO:      $663.28/mês ($7.959.36/ano)
──────────────────────────────────────────────────
vs Marco 2 Base ($666.00):         -$2.72/mês (-0.4%) ✅ NEUTRO EM CUSTO
Capabilities adicionadas:          +300% (GitLab + ArgoCD + Harbor + Data Services)
```

### Crescimento vs Marco 2 Base

| Métrica | Marco 2 Base | Fase 1 Otimizado | Delta | % |
|---------|--------------|------------------|-------|---|
| Custo Mensal | $666.00 | $737.10 | +$71.10 | +10.7% |
| Custo Anual | $7.992 | $8.845 | +$853 | +10.7% |

### Componentes Deployados Fase 1

**Data Services:**
- PostgreSQL: `postgres-lb-xyz.us-east-1.elb.amazonaws.com:5432`
- Redis: `redis-lb-xyz.us-east-1.elb.amazonaws.com:6379`
- RabbitMQ: `rabbitmq-lb-xyz.us-east-1.elb.amazonaws.com:15672` (Management UI)

**Workloads (HTTP, sem HTTPS):**
- GitLab: `http://k8s-gitlab-xyz.us-east-1.elb.amazonaws.com`
- ArgoCD: `http://k8s-argocd-xyz.us-east-1.elb.amazonaws.com`
- Harbor: `http://k8s-harbor-xyz.us-east-1.elb.amazonaws.com`

### Fase 2 (Com Domínio) - Implementação Posterior

**Quando:** Após registro de domínio ou quando necessário funcionalidades avançadas (webhooks HTTPS, SSO)

**Custo adicional:** +$0.50/mês (Route53 Hosted Zone)

**Componentes adicionais:**
- Route53: `k8s-platform.mycompany.com` hosted zone
- ACM certificates: TLS gratuito (4 certificados)
- Keycloak: SSO/OIDC (sem custo adicional, usa nodes existentes)
- HTTPS: ALBs recriados com listeners 443

**Custo Fase 2:** $737.60/mês ($8.851.20/ano)

---

## 📊 Comparação com Alternativas

### vs Managed Kubernetes Alternativas

| Provider | Configuração Equivalente | Custo/Mês | vs AWS EKS |
|----------|--------------------------|-----------|------------|
| **AWS EKS (Atual)** | 7 nodes t3.medium + Platform | $666 | Baseline |
| **GKE (Google)** | 7 nodes n1-standard-2 + GKE | ~$720 | +8% |
| **AKS (Azure)** | 7 nodes Standard_D2s_v3 + AKS | ~$680 | +2% |
| **DigitalOcean K8s** | 7 nodes 2vCPU/4GB + DOKS | ~$420 | -37% |
| **Linode LKE** | 7 nodes 2vCPU/4GB + LKE | ~$385 | -42% |

**Observações:**
- **DigitalOcean/Linode:** Mais baratos, porém limitações (sem equivalente a ALB, RDS managed)
- **GKE/AKS:** Preços similares, porém requer migração (200-300h effort)
- **AWS EKS:** Melhor integração com ecossistema AWS (IAM, S3, RDS, ACM)

### vs On-Premises

| Item | On-Prem (3-year amortization) | AWS EKS | Diferença |
|------|-------------------------------|---------|-----------|
| **Hardware** | $15k servers + $5k networking | $0 | -$6.666/ano |
| **Datacenter** | $2k/mês rack space + power | $0 | -$24.000/ano |
| **OpEx** | 2 FTE × $100k salary | $0 | -$200.000/ano |
| **Compute/Platform** | Amortized | $7.992/ano | +$7.992/ano |
| **TOTAL 3-year TCO** | **~$690k** | **~$24k** | **AWS 96% cheaper** |

**Trade-off:**
- On-prem: Control total, latência zero, compliance específico
- AWS: 96% TCO reduction, zero CapEx, elasticidade

---

## 🎯 Recommendations (FinOps)

### Prioridade ALTA (Implementar Q1 2026)
1. ✅ **Reserved Instances (1-year):** $1.488/ano economia, 1h setup
2. ✅ **S3 Lifecycle Glacier (90d):** $108/ano economia, 30min setup
3. ⚠️ **CloudWatch Billing Alerts:** $0 custo, prevenir surpresas ($100/mês threshold)

### Prioridade MÉDIA (Implementar Q2 2026)
4. **VPC Endpoints (S3, ECR):** $240/ano economia NAT, $87/ano custo endpoints, net $153/ano saved
5. **Consolidar ALBs Marco 3:** $583/ano economia (IngressGroup annotation)
6. **RDS PostgreSQL compartilhado:** $600/ano economia

### Prioridade BAIXA (Considerar 2027)
7. **Spot Instances (workloads):** $540/ano economia, porém requer tolerância a interruptions
8. **Multi-region DR:** +$1.000/mês custo, apenas se RTO < 1h obrigatório
9. **Savings Plans:** Alternativa a RI, mais flexível porém 5-10% menos desconto

---

## 📈 Tracking e Monitoramento

### Ferramentas

| Ferramenta | Propósito | Status |
|------------|-----------|--------|
| **AWS Cost Explorer** | Breakdown por serviço | ✅ Habilitado |
| **AWS Budgets** | Alerts threshold | ⚠️ Pendente configurar |
| **Kubecost** | Kubernetes cost allocation | ⏳ Considerar Marco 3 |
| **Infracost** | Terraform cost estimation (CI/CD) | ⏳ Considerar Q2 2026 |

### Métricas Chave (KPIs)

| KPI | Target | Atual | Status |
|-----|--------|-------|--------|
| **Custo por Node** | < $100/mês | $95/mês | ✅ OK |
| **Custo por Pod (Platform)** | < $15/mês | $13.32/mês | ✅ OK |
| **% Economia vs Baseline** | > 20% | 25.6% | ✅ OK |
| **Reserved Instance Coverage** | > 50% | 0% | 🔴 Action |
| **S3 Storage Growth** | < 10%/mês | N/A | ⚠️ Monitor |

### Dashboards

**AWS Cost Explorer (Visualizações Recomendadas):**
1. **Daily costs:** Últimos 30 dias (detectar spikes)
2. **By Service:** Breakdown EKS, EC2, S3, ALB, RDS
3. **By Tag:** Project=k8s-platform (filtrar custos plataforma)

**Grafana (Custom Dashboard):**
- Prometheus queries: `kube_pod_container_resource_requests` (alocação vs usage)
- Loki logs: S3 API calls (detectar ingestion spikes)

---

## 🚨 Alertas de Custo

### Thresholds Configurados

| Alert | Threshold | Ação |
|-------|-----------|------|
| **Monthly AWS Bill** | > $700/mês | Email DevOps Lead |
| **S3 Loki Storage** | > $15/mês | Review log levels apps |
| **ALB Charges** | > $40/mês | Considerar consolidação |
| **EC2 Spot Termination** | > 2× em 1 dia | Avaliar stability |

### Processo de Resposta

1. **Alert dispara** → Email para DevOps Lead
2. **Análise:** AWS Cost Explorer breakdown (qual serviço?)
3. **Diagnóstico:** CloudWatch metrics, Grafana dashboards
4. **Ação corretiva:** Scaling down, lifecycle policies, resource cleanup
5. **Post-mortem:** Atualizar thresholds, documentar lições aprendidas

---

## 📚 Referências

- [AWS Pricing Calculator](https://calculator.aws/)
- [EKS Pricing](https://aws.amazon.com/eks/pricing/)
- [EC2 Reserved Instances](https://aws.amazon.com/ec2/pricing/reserved-instances/)
- [S3 Lifecycle Policies](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [FinOps Foundation Best Practices](https://www.finops.org/)

---

**Mantenedor:** FinOps Team + DevOps
**Última Revisão:** 2026-01-29
**Próxima Revisão:** 2026-02-15 (Marco 3 cost baseline)
