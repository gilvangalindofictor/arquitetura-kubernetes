# Demanda: Automação FinOps - Start/Stop Ambiente STAGING

**Data:** 2026-01-30
**Solicitante:** Arquitetura / FinOps
**Prioridade:** 🟡 MÉDIA
**Impacto Financeiro:** R$ 5.400/ano de economia
**Status:** 📋 PLANEJAMENTO

---

## 📋 Contexto

O ambiente **STAGING** do Marco 2 opera 24/7, mas é utilizado apenas em horário comercial (8h-18h, Mon-Fri). Isso gera **desperdício de recursos** estimado em **R$ 450/mês**.

Scripts manuais já foram validados ([shutdown-marco2.sh](../../scripts/finops/shutdown-marco2.sh), [startup-marco2.sh](../../scripts/finops/startup-marco2.sh)), mas requerem intervenção humana diária.

**Objetivo:** Automatizar start/stop via EventBridge + Lambda, reduzindo custos operacionais sem comprometer disponibilidade em horário de trabalho.

---

## 🎯 Objetivos

### Funcionais
- ✅ Schedule automático: **8h-18h, Mon-Fri** (horário Brasília - UTC-3)
- ✅ Respeitar **feriados nacionais brasileiros** (via BrasilAPI)
- ✅ Separar workloads:
  - **critical-always-on**: GitLab, Harbor, ArgoCD (ficam ligados 24/7)
  - **regular**: demais aplicações (desligam fora do horário)
- ✅ Health checks antes de desligar (evitar perda de jobs ativos)
- ✅ Circuit breaker: falhas em 3 startups consecutivos = desabilita automação

### Não-Funcionais
- ⏱️ **Startup time:** < 10 minutos (RDS + nodes + pods)
- 📊 **Observabilidade:** Logs no CloudWatch, métricas no Grafana
- 🔐 **Segurança:** IAM roles com least privilege
- 💰 **ROI:** Payback em 6.7 meses (investimento R$ 3.000)

---

## 💰 Análise de Custo-Benefício

### Cenário Atual (24/7 sem automação)

| Recurso | Quantidade | Custo Mensal | Custo Anual |
|---------|-----------|--------------|-------------|
| EKS Control Plane (rateio 50%) | 1 cluster | $37 | $444 |
| EC2 t3.medium nodes | 2 nodes | $60 | $720 |
| RDS db.t3.small Multi-AZ | 1 instance | $70 | $840 |
| Redis Operator (infra) | 3 pods | $10 | $120 |
| RabbitMQ Operator (infra) | 3 pods | $10 | $120 |
| **TOTAL STAGING 24/7** | - | **$187** | **$2.244** |

**Convertido (USD → BRL, taxa 6.0):** R$ 1.122/mês = **R$ 13.464/ano**

---

### Cenário Proposto (Automação 50h/semana)

| Recurso | Uptime | Custo Mensal | Economia |
|---------|--------|--------------|----------|
| EKS Control Plane | 24/7 (obrigatório) | $37 | $0 |
| EC2 t3.medium nodes | 50h/semana (30% do mês) | $18 | **$42** ✅ |
| RDS db.t3.small | Auto-pause (60% economia) | $30 | **$40** ✅ |
| Redis scaled to 0 | 50h/semana | $5 | **$5** ✅ |
| RabbitMQ scaled to 0 | 50h/semana | $5 | **$5** ✅ |
| Lambda scheduler | Minimal | $2 | - |
| **TOTAL STAGING COM AUTOMAÇÃO** | - | **$112** | **$75/mês** ✅ |

**Economia Mensal:** $75 = **R$ 450/mês**
**Economia Anual:** **R$ 5.400/ano** ✅

---

### ROI e Payback

| Métrica | Valor |
|---------|-------|
| **Investimento inicial** | R$ 3.000 (10h × R$ 300/h) |
| **Economia anual** | R$ 5.400 |
| **ROI Year 1** | 80% [(5.400 - 3.000) / 3.000] |
| **Payback period** | 6.7 meses |
| **NPV 3 anos (10% desconto)** | R$ 10.500 |

**Decisão:** ✅ **APROVAR** - ROI positivo e payback < 1 ano

---

## 🏗️ Arquitetura da Solução

### Componentes AWS

```
┌─────────────────────────────────────────────────────────────┐
│                    EventBridge Scheduler                    │
├─────────────────────────────────────────────────────────────┤
│  Schedule 1: STARTUP (8:00 AM BRT = 11:00 UTC)             │
│  - Rule: cron(0 11 ? * MON-FRI *)                          │
│  - Target: Lambda finops-scheduler-staging                  │
│  - Input: {"action": "start", "environment": "staging"}     │
├─────────────────────────────────────────────────────────────┤
│  Schedule 2: SHUTDOWN (6:00 PM BRT = 21:00 UTC)            │
│  - Rule: cron(0 21 ? * MON-FRI *)                          │
│  - Target: Lambda finops-scheduler-staging                  │
│  - Input: {"action": "stop", "environment": "staging"}      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│           Lambda: finops-scheduler-staging                  │
│  - Runtime: Python 3.12                                     │
│  - Memory: 512 MB                                           │
│  - Timeout: 300s (5 min)                                    │
│  - IAM Role: finops-scheduler-role                          │
├─────────────────────────────────────────────────────────────┤
│  Lógica:                                                    │
│  1. Verificar feriados (BrasilAPI)                          │
│  2. Health checks (GitLab jobs ativos, ArgoCD syncs)        │
│  3. Executar ação:                                          │
│     - STOP: ASG → 0 replicas, RDS → pause                  │
│     - START: RDS → resume, ASG → replicas originais         │
│  4. Aguardar health checks (pods Ready)                     │
│  5. Notificar Teams/SNS                                     │
│  6. Registrar métricas (CloudWatch)                         │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ ASG Scaling  │  │  RDS Pause   │  │ DynamoDB     │
│ (EC2 Nodes)  │  │  (Staging)   │  │ (State Lock) │
└──────────────┘  └──────────────┘  └──────────────┘
```

### Node Groups Strategy

```yaml
# Node Group: critical-always-on (24/7)
- GitLab (CI/CD não pode parar)
- Harbor (registry sempre disponível)
- ArgoCD (reconciliação contínua)
- Prometheus/Grafana (observabilidade)

# Node Group: regular (8h-18h Mon-Fri)
- Keycloak staging
- SonarQube staging
- Kong staging
- Redis Operator (scaled to 0)
- RabbitMQ Operator (scaled to 0)
```

**Justificativa:** GitLab possui jobs noturnos agendados (backups, security scans). Desligá-lo causaria falhas de CI/CD.

---

## 🔐 Segurança e Compliance

### IAM Role: finops-scheduler-role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageAutoScalingGroups",
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:SuspendProcesses",
        "autoscaling:ResumeProcesses"
      ],
      "Resource": "arn:aws:autoscaling:us-east-1:*:autoScalingGroup:*:autoScalingGroupName/eks-marco2-staging-regular-*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/Environment": "staging"
        }
      }
    },
    {
      "Sid": "ManageRDS",
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:StopDBInstance",
        "rds:StartDBInstance"
      ],
      "Resource": "arn:aws:rds:us-east-1:*:db:marco2-staging-rds",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/Environment": "staging"
        }
      }
    },
    {
      "Sid": "HealthChecks",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListNodegroups"
      ],
      "Resource": "arn:aws:eks:us-east-1:*:cluster/marco2-staging"
    },
    {
      "Sid": "Observability",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

**Princípios Aplicados:**
- ✅ Least privilege (apenas recursos staging)
- ✅ Condições baseadas em tags (Resource tag check)
- ✅ Sem permissões PROD (blast radius limitado)

---

## ⚠️ Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| **Falha no startup (RDS timeout)** | 🟡 Média | 🔴 Alto | Retry 3x com backoff exponencial, alertas Teams |
| **Feriados não detectados** | 🟢 Baixa | 🟡 Médio | Cache local de feriados, fallback para lista estática |
| **GitLab job perdido durante shutdown** | 🟢 Baixa | 🔴 Alto | Health check: bloquear shutdown se jobs ativos |
| **Lambda timeout (300s)** | 🟢 Baixa | 🟡 Médio | Operações assíncronas, StepFunctions para fluxos longos |
| **Circuit breaker ativado erroneamente** | 🟢 Baixa | 🟡 Médio | Threshold ajustável (3 falhas), notificação imediata |

### Circuit Breaker Logic

```python
# DynamoDB state tracking
if startup_failures >= 3:
    state = "CIRCUIT_OPEN"
    notify_oncall("FinOps automation disabled - 3 consecutive failures")
    disable_eventbridge_rule("finops-scheduler-startup")
```

**Recuperação Manual:**
1. Investigar logs CloudWatch
2. Corrigir problema raiz
3. Reset circuit: `aws dynamodb update-item --table finops-state --key '{"env":"staging"}' --update-expression "SET failures = :zero"`
4. Reativar regra EventBridge

---

## 📊 Observabilidade

### Métricas CloudWatch

| Métrica | Namespace | Descrição |
|---------|-----------|-----------|
| `finops.startup.duration` | FinOps/Scheduler | Tempo total de startup (target: < 10 min) |
| `finops.shutdown.duration` | FinOps/Scheduler | Tempo total de shutdown (target: < 5 min) |
| `finops.cost_savings_daily` | FinOps/Costs | Economia diária estimada (USD) |
| `finops.circuit_breaker_state` | FinOps/Health | 0 = closed, 1 = open |

### Dashboards Grafana

**Dashboard: FinOps Staging Automation**
- Uptime real vs planejado (gráfico temporal)
- Economia acumulada (mês atual)
- Histórico de startups/shutdowns (timeline)
- Falhas e circuit breaker status

### Alertas

| Condição | Severidade | Ação |
|----------|-----------|------|
| Startup duration > 15 min | 🟡 Warning | Teams canal finops-alerts |
| Startup failed 3x consecutivas | 🔴 Critical | PagerDuty on-call + disable automation |
| BrasilAPI unreachable | 🟢 Info | Fallback para lista estática, log warning |

---

## 🚀 Plano de Implementação

### Fase 1: Preparação (1 semana)

**1.1 - Terraform Module: finops-scheduler**
```bash
# Estrutura
terraform/modules/finops-scheduler/
├── main.tf                 # Lambda, EventBridge, IAM
├── variables.tf            # Configurações (schedule, environment)
├── outputs.tf              # Lambda ARN, EventBridge rules
├── lambda/
│   ├── handler.py          # Lógica principal
│   ├── requirements.txt    # boto3, requests (BrasilAPI)
│   └── config.yaml         # Node groups, health checks
└── README.md
```

**1.2 - Lambda Handler (handler.py)**
```python
import boto3
import requests
from datetime import datetime, timedelta

def lambda_handler(event, context):
    action = event['action']  # "start" ou "stop"
    environment = event['environment']  # "staging"

    # 1. Verificar feriados
    if is_brazilian_holiday():
        return skip_action("Brazilian holiday detected")

    # 2. Health checks (se stop)
    if action == "stop":
        if gitlab_has_active_jobs():
            return skip_action("GitLab jobs active - postponing shutdown")

    # 3. Executar ação
    if action == "start":
        start_environment(environment)
    else:
        stop_environment(environment)

    # 4. Métricas
    cloudwatch.put_metric_data(
        Namespace='FinOps/Scheduler',
        MetricData=[{
            'MetricName': f'{action}_duration',
            'Value': duration_seconds,
            'Unit': 'Seconds'
        }]
    )

    return {"status": "success", "action": action}
```

**1.3 - EventBridge Rules (Terraform)**
```hcl
resource "aws_cloudwatch_event_rule" "startup_staging" {
  name                = "finops-startup-staging"
  description         = "Start staging environment at 8 AM BRT"
  schedule_expression = "cron(0 11 ? * MON-FRI *)"  # 11:00 UTC = 8:00 BRT
}

resource "aws_cloudwatch_event_target" "startup_target" {
  rule      = aws_cloudwatch_event_rule.startup_staging.name
  target_id = "lambda-finops-scheduler"
  arn       = aws_lambda_function.finops_scheduler.arn

  input = jsonencode({
    action      = "start"
    environment = "staging"
  })
}
```

---

### Fase 2: Testes (3 dias)

**2.1 - Teste Manual Lambda**
```bash
# Invocar Lambda localmente
aws lambda invoke \
  --function-name finops-scheduler-staging \
  --payload '{"action":"start","environment":"staging"}' \
  response.json

# Verificar logs
aws logs tail /aws/lambda/finops-scheduler-staging --follow
```

**2.2 - Teste de Shutdown**
```bash
# Simular shutdown
aws lambda invoke \
  --function-name finops-scheduler-staging \
  --payload '{"action":"stop","environment":"staging"}' \
  response.json

# Validar estado
kubectl get nodes -l environment=staging,node-type=regular
# Esperado: 0 nodes
```

**2.3 - Teste de Startup**
```bash
# Simular startup
aws lambda invoke --function-name finops-scheduler-staging \
  --payload '{"action":"start","environment":"staging"}' response.json

# Aguardar 10 minutos
sleep 600

# Validar
kubectl get nodes -l environment=staging,node-type=regular
# Esperado: 2 nodes Ready

kubectl get pods -n platform-core-staging
# Esperado: Todos Running
```

**2.4 - Teste de Feriado**
```bash
# Mockar BrasilAPI para retornar feriado
# Configurar Lambda environment variable:
BRASIL_API_MOCK=true

# Invocar Lambda
aws lambda invoke --function-name finops-scheduler-staging \
  --payload '{"action":"stop","environment":"staging"}' response.json

# Verificar resposta
cat response.json
# Esperado: {"status": "skipped", "reason": "Brazilian holiday"}
```

---

### Fase 3: Deploy Gradual (1 semana)

**Semana 1:**
- Segunda-feira: Startup manual (validar funcionamento)
- Quarta-feira: Shutdown manual
- Sexta-feira: Habilitar EventBridge (monitoramento intensivo)

**Semana 2:**
- Monitorar economia real vs projetada
- Ajustar thresholds de health checks
- Documentar runbooks

---

## 📚 Documentação Complementar

### Runbooks

**Runbook 1: Startup Falhou**
```bash
# 1. Verificar logs Lambda
aws logs tail /aws/lambda/finops-scheduler-staging --follow

# 2. Verificar RDS
aws rds describe-db-instances --db-instance-identifier marco2-staging-rds

# 3. Startup manual (fallback)
cd scripts/finops
./startup-marco2.sh staging

# 4. Reset circuit breaker
aws dynamodb update-item \
  --table-name finops-scheduler-state \
  --key '{"environment": {"S": "staging"}}' \
  --update-expression "SET startup_failures = :zero" \
  --expression-attribute-values '{":zero": {"N": "0"}}'
```

**Runbook 2: Desabilitar Automação Temporariamente**
```bash
# Desabilitar regras EventBridge
aws events disable-rule --name finops-startup-staging
aws events disable-rule --name finops-shutdown-staging

# Notificar equipe
# Notify via Teams (use curl with Teams webhook or teams-cli)
# teams-notify canal finops "FinOps automation disabled - manual intervention required"
```

---

## 🎯 Critérios de Sucesso

| Métrica | Target | Medição |
|---------|--------|---------|
| **Disponibilidade staging (8h-18h)** | 99.5% | CloudWatch Synthetics |
| **Startup time** | < 10 min | CloudWatch Logs Insights |
| **Economia mensal** | R$ 450 ± 10% | AWS Cost Explorer |
| **Falhas mensais** | < 2 | Lambda errors metric |
| **Satisfação equipe** | > 8/10 | Survey trimestral |

---

## 📅 Timeline

| Marco | Prazo | Responsável |
|-------|-------|-------------|
| Aprovação arquitetura | 2026-02-03 | Arquitetura + FinOps |
| Desenvolvimento Lambda | 2026-02-10 | DevOps |
| Testes integrados | 2026-02-13 | QA + DevOps |
| Deploy produção | 2026-02-17 | DevOps |
| Monitoramento 1 mês | 2026-03-17 | FinOps |
| Retrospectiva | 2026-03-20 | Time completo |

---

## 🔗 Referências

- [Quickstart Plan](../plan/aws-execution/quickstart-marco2.md) (linha 453-469)
- [Scripts Existentes](../../scripts/finops/)
- [ADR-024: FinOps Automation](../context/decisions.md#adr-024) (a ser criado)
- [BrasilAPI - Feriados](https://brasilapi.com.br/docs#tag/Feriados)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS EventBridge Scheduler](https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html)

---

**Aprovações Necessárias:**
- [ ] Arquitetura (análise técnica)
- [ ] FinOps (ROI validado)
- [ ] Security (IAM policies)
- [ ] Product Owner (priorização)

**Status:** 📋 PLANEJAMENTO → Aguardando aprovação
