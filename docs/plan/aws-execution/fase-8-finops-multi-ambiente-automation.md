# Fase 8 - Automação FinOps Multi-Ambiente (EventBridge + Lambda)

> **Automação Start/Stop STAGING + PRODUCTION - Economia R$ 22.104/ano (Fase 3)**
> **Pré-requisitos**: Marco 2 completo, ambientes STAGING e PRODUCTION existentes
> **Status**: 📝 PLANEJADO (Implementação faseada 3-etapas)

---

## Índice

1. [Visão Geral](#1-visão-geral)
2. [Estratégia Evolutiva 3-Fases](#2-estratégia-evolutiva-3-fases)
3. [Pré-requisitos](#3-pré-requisitos)
4. [Arquitetura Multi-Ambiente](#4-arquitetura-multi-ambiente)
5. [Implementação Fase 1: STAGING](#5-implementação-fase-1-staging)
6. [Implementação Fase 2: PRODUCTION](#6-implementação-fase-2-production)
7. [Implementação Fase 3: STAGING On-Demand](#7-implementação-fase-3-staging-on-demand)
8. [Terraform Multi-Ambiente](#8-terraform-multi-ambiente)
9. [Lambda Functions](#9-lambda-functions)
10. [Testes e Validação](#10-testes-e-validação)
11. [Monitoramento Consolidado](#11-monitoramento-consolidado)
12. [Troubleshooting Multi-Ambiente](#12-troubleshooting-multi-ambiente)
13. [Checklist de Conclusão](#13-checklist-de-conclusão)

---

## 1. Visão Geral

### 1.1 Objetivos Consolidados

**Problema Multi-Ambiente:**
- **STAGING:** Opera 24/7 mas utilizado apenas 8h-18h Mon-Fri (70% desperdício)
- **PRODUCTION:** Opera 24/7 mas clientes ativos apenas 7h-0h (29% desperdício madrugada)
- **Custo Total:** $839/mês ($187 STAGING + $652 PRODUCTION)
- **Desperdício:** $190/mês evitável

**Solução Faseada:**
1. **Fase 1:** STAGING automação → Validação técnica (1 mês)
2. **Fase 2:** PRODUCTION automação → Economia consolidada
3. **Fase 3:** STAGING on-demand → Economia máxima

**Benefícios Totais (Fase 3):**
- Economia: R$ 22.104/ano (R$ 1.842/mês)
- ROI: 391% Year 1 (payback 2.4 meses)
- Zero toil operacional
- SLA garantido: STAGING 99.5%, PRODUCTION 99.9%

### 1.2 Estimativa de Custos Consolidada

```
┌────────────────────────────────────────────────────────────┐
│ Fase 1: STAGING Apenas                                     │
├────────────────────────────────────────────────────────────┤
│ STAGING 24/7:               $187/mês                       │
│ STAGING Automação:          $127/mês                       │
│ ─────────────────────────────────────────                 │
│ ECONOMIA:                    $60/mês ($720/ano)            │
│ ECONOMIA BRL:                R$ 360/mês (R$ 4.320/ano)     │
│ Investimento:                R$ 3.000 (10h dev)            │
│ ROI Year 1:                  44%                           │
│ Payback:                     6.7 meses                     │
├────────────────────────────────────────────────────────────┤
│ Fase 2: STAGING + PRODUCTION                               │
├────────────────────────────────────────────────────────────┤
│ STAGING Automação:          $127/mês                       │
│ PROD 24/7:                  $652/mês                       │
│ PROD Automação:             $522/mês                       │
│ ─────────────────────────────────────────                 │
│ TOTAL Fase 2:               $649/mês (vs $839 24/7)       │
│ ECONOMIA:                    $190/mês ($2.280/ano)         │
│ ECONOMIA BRL:                R$ 1.140/mês (R$ 13.680/ano)  │
│ Investimento Total:          R$ 4.500 (15h dev)            │
│ ROI Year 1:                  204%                          │
│ Payback:                     3.9 meses                     │
├────────────────────────────────────────────────────────────┤
│ Fase 3: STAGING On-Demand + PRODUCTION                     │
├────────────────────────────────────────────────────────────┤
│ STAGING On-Demand (5%):     $9.35/mês (vs $187 24/7)      │
│ PROD Automação:             $522/mês                       │
│ ─────────────────────────────────────────                 │
│ TOTAL Fase 3:               $531.35/mês (vs $839 24/7)    │
│ ECONOMIA:                    $307.65/mês ($3.692/ano)      │
│ ECONOMIA BRL:                R$ 1.842/mês (R$ 22.104/ano)  │
│ Investimento:                R$ 4.500 (não muda)           │
│ ROI Year 1:                  391%                          │
│ Payback:                     2.4 meses                     │
│ NPV 3 anos:                  R$ 50.479 (ROI 1.121%)        │
└────────────────────────────────────────────────────────────┘
```

### 1.3 Timeline Consolidada

| Fase | Prazo | Duração | Responsável | Milestone Crítico |
|------|-------|---------|-------------|-------------------|
| **Fase 1: STAGING Deploy** | 2026-02-17 | 3 semanas | DevOps | Lambda + EventBridge STAGING |
| **Fase 1: STAGING Validação** | 2026-03-17 | 1 mês | FinOps | SLA 99.5%, 0 falhas, economia R$ 360/mês |
| **Go/No-Go Fase 2** | 2026-03-20 | 3 dias | Stakeholders | STAGING operação estável 1 mês SEM falhas |
| **Fase 2: PROD Environment** | 2026-04-01 | - | Infra Team | Marco 3 deployado, workloads ativos |
| **Fase 2: PROD Deploy** | 2026-04-15 | 1 semana | DevOps | Lambda + EventBridge PROD |
| **Fase 2: PROD Validação** | 2026-06-15 | 2 meses | FinOps | SLA 99.9%, economia R$ 1.140/mês |
| **Go/No-Go Fase 3** | 2026-06-20 | 5 dias | Stakeholders | PROD estável 2 meses + cobertura testes > 80% |
| **Fase 3: STAGING On-Demand** | 2026-09-15 | 3 meses | FinOps | STAGING usado < 2×/mês, economia R$ 1.842/mês |

---

## 2. Estratégia Evolutiva 3-Fases

### 2.1 Fase 1: STAGING 8h-18h Mon-Fri (Pré-PROD)

**Objetivo:** Validar automação em ambiente não-crítico antes de expandir para PRODUCTION.

**Escopo:**
```
STAGING (Dev+Homolog):  Ligado 8h-18h Mon-Fri (desenvolvimento ativo)
PROD:                   Não existe (Marco 3 pendente)
────────────────────────────────────
Economia:               R$ 4.320/ano
Investimento:           R$ 3.000
ROI Year 1:             44%
Payback:                6.7 meses
```

**Componentes:**
- EventBridge: 2 rules (startup 8h, shutdown 18h Mon-Fri BRT)
- Lambda: finops-scheduler-staging (Python 3.12)
- DynamoDB: finops-scheduler-state (circuit breaker)
- IAM Role: finops-scheduler-staging-role (least privilege)

**Schedule:**
- STARTUP: 8:00 AM BRT (11:00 UTC) - Mon-Fri
- SHUTDOWN: 6:00 PM BRT (21:00 UTC) - Mon-Fri
- Feriados: SKIP (não liga, via BrasilAPI)

**Health Checks (básicos):**
- Bloquear shutdown se GitLab jobs ativos
- Bloquear shutdown se ArgoCD syncs em progresso
- Aguardar RDS available (startup)

**Critérios de Sucesso (Go/No-Go Fase 2):**
- [ ] STAGING operação 1 mês SEM falhas
- [ ] SLA 99.5% (8h-18h) atingido
- [ ] Economia observada ≥ R$ 360/mês (tolerância 10%)
- [ ] Zero incidentes críticos (circuit breaker nunca ativado)
- [ ] Equipe confortável com automação (survey > 8/10)

---

### 2.2 Fase 2: STAGING + PRODUCTION (Go-Live Simultâneo)

**Objetivo:** Expandir automação para PRODUCTION com health checks rigorosos e rollback automático.

**Escopo:**
```
STAGING (Dev+Homolog):  Ligado 8h-18h Mon-Fri (testes + homologação)
PROD:                   Ligado 7h-0h 7 dias/semana (operação clientes)
────────────────────────────────────
Economia STAGING:       R$ 4.320/ano
Economia PROD:          R$ 9.360/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 13.680/ano ✅
Investimento Incremental: R$ 1.500 (5h dev PROD)
ROI Year 1:             204%
Payback:                3.9 meses
```

**Componentes Adicionais PROD:**
- EventBridge: 2 rules (startup 7h, shutdown 0h 7 dias/semana BRT)
- Lambda: finops-scheduler-production (Python 3.12, health checks rigorosos)
- IAM Role: finops-scheduler-production-role (environment-specific)
- Snapshots RDS: Automáticos pré-shutdown (RPO < 1h)

**Schedule PROD:**
- STARTUP: 7:00 AM BRT (10:00 UTC) - 7 dias/semana
- SHUTDOWN: 00:00 (meia-noite) BRT (03:00 UTC) - 7 dias/semana
- Feriados: LIGA SEMPRE (clientes ativos)

**Health Checks PROD (rigorosos):**
- Bloquear shutdown se transações DB ativas (> 0)
- Bloquear shutdown se conexões idle recentes (< 5 min, > 10)
- Bloquear shutdown se mensagens RabbitMQ pendentes (> 100)
- Bloquear shutdown se manutenção não agendada (AlertManager)
- Criar snapshot RDS PRÉ-shutdown (RPO < 1h)

**Rollback Automático PROD:**
- Threshold: 2 falhas consecutivas (vs 3 STAGING)
- Ação: Desabilita EventBridge, startup manual, PagerDuty P1
- ETA: < 5 min recovery

**Critérios de Sucesso (Go/No-Go Fase 3):**
- [ ] PROD operação 2 meses SEM falhas
- [ ] SLA 99.9% (7h-0h) atingido
- [ ] Economia observada ≥ R$ 1.140/mês (tolerância 10%)
- [ ] Zero rollbacks automáticos (startup sempre bem-sucedido)
- [ ] Cobertura testes automatizados > 80% (PROD production-first)
- [ ] STAGING usado < 2×/mês (validar necessidade real)

---

### 2.3 Fase 3: STAGING On-Demand + PRODUCTION (Estável)

**Objetivo:** Maximizar economia levando STAGING para on-demand (95% economia adicional).

**Escopo:**
```
STAGING:                DESLIGADO permanentemente (liga SOB DEMANDA)
PROD:                   Ligado 7h-0h 7 dias/semana (operação)
────────────────────────────────────
Economia STAGING:       R$ 12.744/ano ✅ (95% economia, uptime ~5%)
Economia PROD:          R$ 9.360/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 22.104/ano ✅✅
NPV 3 anos:             R$ 50.479 (ROI 1.121%)
```

**Mudanças:**
- STAGING EventBridge rules: DISABLED permanentemente
- STAGING startup: Manual sob demanda (via script ou Terraform)
- Uptime estimado: 5% (ligando ~1×/semana, 10h/mês)
- Custo STAGING otimizado: R$ 720/ano (vs R$ 13.464/ano 24/7)

**Gatilhos Fase 3:**
- [ ] PROD estável > 3 meses sem incidentes críticos
- [ ] Cobertura testes automatizados > 80%
- [ ] Equipe confortável com CI/CD production-first
- [ ] STAGING usado < 2×/mês (validar necessidade real)

**Critérios de Sucesso (Fase 3):**
- [ ] Economia observada ≥ R$ 1.842/mês (tolerância 10%)
- [ ] STAGING startup manual < 10 min quando necessário
- [ ] Zero impacto em produção (workloads testados antes de deploy)

---

## 3. Pré-requisitos

### 3.1 Infraestrutura Fase 1 (STAGING)

```bash
# Validar recursos existentes STAGING
aws eks describe-cluster --name marco2-staging --region us-east-1
aws rds describe-db-instances --db-instance-identifier marco2-staging-rds
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names eks-marco2-staging-regular-*
```

**Checklist STAGING:**
- [ ] Cluster EKS staging existente
- [ ] RDS PostgreSQL staging ativo
- [ ] Node groups identificados (critical-always-on vs regular)
- [ ] IAM permissions para Lambda (ASG, RDS, DynamoDB)

### 3.2 Infraestrutura Fase 2 (PRODUCTION)

```bash
# Validar recursos existentes PRODUCTION
aws eks describe-cluster --name marco2-production --region us-east-1
aws rds describe-db-instances --db-instance-identifier marco2-prod-rds
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names eks-marco2-production-production-*
```

**Checklist PRODUCTION:**
- [ ] Marco 3 deployado (workloads ativos)
- [ ] Cluster EKS production existente
- [ ] RDS PostgreSQL production ativo Multi-AZ
- [ ] Node groups identificados (critical-always-on vs production)
- [ ] Load tests validados (99.9% SLA confirmado)
- [ ] Runbooks recovery documentados

### 3.3 Ferramentas

```bash
# Terraform >= 1.6
terraform version

# AWS CLI >= 2.0
aws --version

# kubectl configurado
kubectl get nodes --context marco2-staging
kubectl get nodes --context marco2-production

# Python 3.12 (para testes locais Lambda)
python3 --version

# jq (para processar JSON)
jq --version
```

### 3.4 Permissões AWS Multi-Ambiente

```bash
# Validar permissões IAM
aws iam get-user
aws sts get-caller-identity

# Permissões necessárias (environment-specific via tags):
# - iam:CreateRole, iam:AttachRolePolicy
# - lambda:CreateFunction, lambda:UpdateFunctionCode
# - events:PutRule, events:PutTargets
# - autoscaling:UpdateAutoScalingGroup (staging + production)
# - rds:StopDBInstance, rds:StartDBInstance (staging + production)
# - rds:CreateDBSnapshot (production apenas)
# - dynamodb:PutItem, dynamodb:GetItem (shared circuit breaker)
# - sns:Publish (notificações)
```

---

## 4. Arquitetura Multi-Ambiente

### 4.1 Diagrama Consolidado

```
┌─────────────────────────────────────────────────────────────────────┐
│              EventBridge Scheduler (4 rules total)                  │
├─────────────────────────────────────────────────────────────────────┤
│  STAGING:                                                           │
│    Rule 1: STARTUP  → cron(0 11 ? * MON-FRI *)  # 8AM BRT          │
│    Rule 2: SHUTDOWN → cron(0 21 ? * MON-FRI *)  # 6PM BRT          │
│  PRODUCTION:                                                        │
│    Rule 3: STARTUP  → cron(0 10 ? * * *)        # 7AM BRT          │
│    Rule 4: SHUTDOWN → cron(0 3 ? * * *)         # 0AM (meia-noite) │
└─────────────────────────────────────────────────────────────────────┘
                            │           │
                    ┌───────┴───────┐   │
                    ▼               ▼   ▼
    ┌───────────────────────┐   ┌───────────────────────┐
    │ Lambda: staging       │   │ Lambda: production    │
    │ (Python 3.12)         │   │ (Python 3.12)         │
    ├───────────────────────┤   ├───────────────────────┤
    │ Health checks básicos │   │ Health checks rigorosos│
    │ Circuit breaker: 3    │   │ Circuit breaker: 2    │
    │ Notificação: Slack    │   │ Notificação: PagerDuty│
    │ Feriados: SKIP        │   │ Feriados: LIGA        │
    │ Rollback: Manual      │   │ Rollback: Automático  │
    │ Snapshot RDS: Não     │   │ Snapshot RDS: Sim     │
    └───────────────────────┘   └───────────────────────┘
         │     │     │                │     │     │
         ▼     ▼     ▼                ▼     ▼     ▼
    ┌──────────────────┐       ┌──────────────────┐
    │ AWS Resources    │       │ AWS Resources    │
    │ (STAGING)        │       │ (PRODUCTION)     │
    ├──────────────────┤       ├──────────────────┤
    │ ASG regular      │       │ ASG production   │
    │ RDS staging      │       │ RDS production   │
    │ Redis/RabbitMQ   │       │ Redis/RabbitMQ   │
    └──────────────────┘       └──────────────────┘
              │                         │
              └─────────┬───────────────┘
                        ▼
        ┌───────────────────────────────────┐
        │ DynamoDB: finops-scheduler-state  │
        │ (Shared circuit breaker tracking) │
        └───────────────────────────────────┘
```

### 4.2 Comparação STAGING vs PRODUCTION

| Aspecto | STAGING | PRODUCTION |
|---------|---------|------------|
| **Schedule** | 8h-18h Mon-Fri | 7h-0h 7 dias/semana |
| **Uptime** | 50h/semana (30%) | 119h/semana (71%) |
| **Feriados** | SKIP (não liga) | LIGA (clientes ativos) |
| **Health Checks** | Básicos (GitLab jobs) | Rigorosos (transações DB, conexões, queues) |
| **Rollback** | Manual (30 min) | Automático (< 5 min) |
| **SLA** | 99.5% (8h-18h) | 99.9% (7h-0h) |
| **Circuit Breaker** | 3 falhas | 2 falhas (mais sensível) |
| **Snapshot RDS** | Não | Sim (pré-shutdown, RPO < 1h) |
| **Notificação** | Slack #finops-alerts | PagerDuty P1 + Slack #prod-incidents |
| **Investimento** | R$ 3.000 (10h dev) | R$ 1.500 (5h incremental) |
| **Economia Anual** | R$ 4.320 | R$ 9.360 |
| **ROI Year 1** | 44% | 521% |
| **Payback** | 6.7 meses | 1.9 meses |

---

## 5. Implementação Fase 1: STAGING

### 5.1 Terraform Module STAGING

```hcl
# terraform/modules/finops-scheduler-staging/main.tf
module "finops_scheduler_staging" {
  source = "./modules/finops-scheduler"

  environment          = "staging"
  schedule_startup     = "cron(0 11 ? * MON-FRI *)"  # 8AM BRT
  schedule_shutdown    = "cron(0 21 ? * MON-FRI *)"  # 6PM BRT

  asg_names            = ["eks-marco2-staging-regular-*"]
  rds_instance_id      = "marco2-staging-rds"
  dynamodb_table_name  = "finops-scheduler-state"

  health_check_gitlab_enabled  = true
  health_check_argocd_enabled  = true

  circuit_breaker_threshold    = 3
  notification_slack_webhook   = var.slack_webhook_url

  brasil_api_enabled   = true
  skip_holidays        = true  # STAGING não liga em feriados

  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
    Project     = "finops-automation"
  }
}
```

### 5.2 Lambda Function STAGING

**Arquivo:** `terraform/modules/finops-scheduler/lambda/staging/lambda_function.py`

```python
import json
import boto3
import os
import requests
from datetime import datetime

# AWS Clients
autoscaling = boto3.client('autoscaling')
rds = boto3.client('rds')
dynamodb = boto3.client('dynamodb')

# Environment Variables
ENVIRONMENT = os.environ['ENVIRONMENT']  # staging
ASG_NAMES = os.environ['ASG_NAMES'].split(',')
RDS_INSTANCE_ID = os.environ['RDS_INSTANCE_ID']
DYNAMODB_TABLE = os.environ['DYNAMODB_TABLE']
BRASIL_API_URL = os.environ.get('BRASIL_API_URL', 'https://brasilapi.com.br/api/feriados/v1/')

def lambda_handler(event, context):
    """
    Handler principal: startup ou shutdown baseado no event trigger
    """
    action = event.get('action')  # 'startup' ou 'shutdown'

    print(f"[{ENVIRONMENT}] Iniciando ação: {action}")

    # 1. Verificar feriados (STAGING SKIP em feriados)
    if is_holiday() and action == 'startup':
        print(f"[{ENVIRONMENT}] Feriado detectado via BrasilAPI - SKIP startup")
        return {'statusCode': 200, 'body': 'Holiday detected - skipped'}

    # 2. Health checks pré-ação
    if action == 'shutdown' and not pre_shutdown_health_checks():
        print(f"[{ENVIRONMENT}] Health checks FAILED - POSTPONING shutdown")
        return {'statusCode': 200, 'body': 'Health checks failed - postponed'}

    # 3. Executar ação
    try:
        if action == 'startup':
            execute_startup()
        elif action == 'shutdown':
            execute_shutdown()

        # 4. Resetar circuit breaker (sucesso)
        reset_circuit_breaker()

        # 5. Métricas CloudWatch
        publish_metrics(action, success=True)

        return {'statusCode': 200, 'body': f'{action} completed successfully'}

    except Exception as e:
        print(f"[{ENVIRONMENT}] ERROR: {str(e)}")

        # Incrementar circuit breaker
        increment_circuit_breaker()

        # Métricas falha
        publish_metrics(action, success=False)

        raise

def is_holiday():
    """
    Verifica se hoje é feriado nacional brasileiro via BrasilAPI
    Cache local DynamoDB (30 dias TTL) + fallback lista estática
    """
    today = datetime.now().strftime('%Y-%m-%d')
    year = datetime.now().year

    # Buscar cache DynamoDB
    cached = get_holiday_cache(today)
    if cached is not None:
        return cached

    # Buscar BrasilAPI
    try:
        response = requests.get(f"{BRASIL_API_URL}{year}", timeout=5)
        holidays = response.json()

        for holiday in holidays:
            if holiday['date'] == today:
                # Salvar cache
                save_holiday_cache(today, is_holiday=True)
                return True

        save_holiday_cache(today, is_holiday=False)
        return False

    except Exception as e:
        print(f"[{ENVIRONMENT}] BrasilAPI unreachable: {str(e)} - usando fallback")

        # Fallback: lista estática feriados fixos
        static_holidays = {
            f"{year}-01-01": "Ano Novo",
            f"{year}-04-21": "Tiradentes",
            f"{year}-05-01": "Dia do Trabalho",
            f"{year}-09-07": "Independência",
            f"{year}-10-12": "Nossa Senhora Aparecida",
            f"{year}-11-02": "Finados",
            f"{year}-11-15": "Proclamação da República",
            f"{year}-12-25": "Natal"
        }

        return today in static_holidays

def pre_shutdown_health_checks():
    """
    Health checks STAGING (básicos):
    - GitLab jobs ativos (bloqueia shutdown)
    - ArgoCD syncs em progresso (bloqueia shutdown)
    """
    # GitLab API check (exemplo)
    # gitlab_jobs = requests.get("http://gitlab.staging/api/v4/jobs?scope[]=running").json()
    # if len(gitlab_jobs) > 0:
    #     return False

    # ArgoCD check (exemplo)
    # argocd_syncs = kubectl_get_argocd_syncing_apps()
    # if argocd_syncs > 0:
    #     return False

    return True  # Health checks passed

def execute_startup():
    """
    Startup STAGING:
    1. Resume RDS
    2. Scale ASG min=2
    3. Aguardar nodes Ready (async, não bloqueia)
    """
    print(f"[{ENVIRONMENT}] Starting RDS instance: {RDS_INSTANCE_ID}")
    rds.start_db_instance(DBInstanceIdentifier=RDS_INSTANCE_ID)

    for asg_name in ASG_NAMES:
        print(f"[{ENVIRONMENT}] Scaling ASG: {asg_name} to min=2")
        autoscaling.update_auto_scaling_group(
            AutoScalingGroupName=asg_name,
            MinSize=2,
            DesiredCapacity=2
        )

def execute_shutdown():
    """
    Shutdown STAGING:
    1. Scale ASG min=0
    2. Pause RDS
    3. Scale operators to 0 (Redis, RabbitMQ)
    """
    for asg_name in ASG_NAMES:
        print(f"[{ENVIRONMENT}] Scaling ASG: {asg_name} to min=0")
        autoscaling.update_auto_scaling_group(
            AutoScalingGroupName=asg_name,
            MinSize=0,
            DesiredCapacity=0
        )

    print(f"[{ENVIRONMENT}] Stopping RDS instance: {RDS_INSTANCE_ID}")
    rds.stop_db_instance(DBInstanceIdentifier=RDS_INSTANCE_ID)

def get_holiday_cache(date):
    """Buscar cache feriados no DynamoDB"""
    # Implementação DynamoDB GetItem
    pass

def save_holiday_cache(date, is_holiday):
    """Salvar cache feriados no DynamoDB (TTL 30 dias)"""
    # Implementação DynamoDB PutItem com TTL
    pass

def reset_circuit_breaker():
    """Resetar contador circuit breaker após sucesso"""
    # Implementação DynamoDB PutItem
    pass

def increment_circuit_breaker():
    """Incrementar contador circuit breaker após falha"""
    # Implementação DynamoDB UpdateItem
    # Se failures >= 3, notificar Slack + desabilitar EventBridge
    pass

def publish_metrics(action, success):
    """Publicar métricas CloudWatch"""
    cloudwatch = boto3.client('cloudwatch')
    cloudwatch.put_metric_data(
        Namespace='FinOps/Scheduler',
        MetricData=[
            {
                'MetricName': f'{action}_success' if success else f'{action}_failure',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': ENVIRONMENT}
                ]
            }
        ]
    )
```

### 5.3 Deploy Fase 1

```bash
# 1. Deploy Terraform STAGING
cd terraform/environments/staging
terraform init
terraform plan -var-file="staging.tfvars"
terraform apply -var-file="staging.tfvars"

# 2. Validar recursos criados
aws lambda get-function --function-name finops-scheduler-staging
aws events list-rules --name-prefix finops-scheduler-staging
aws dynamodb describe-table --table-name finops-scheduler-state

# 3. Teste manual (simular startup)
aws lambda invoke \
  --function-name finops-scheduler-staging \
  --payload '{"action": "startup"}' \
  response.json

cat response.json

# 4. Habilitar EventBridge rules (após validação manual)
aws events enable-rule --name finops-scheduler-staging-startup
aws events enable-rule --name finops-scheduler-staging-shutdown
```

---

## 6. Implementação Fase 2: PRODUCTION

### 6.1 Terraform Module PRODUCTION

```hcl
# terraform/modules/finops-scheduler-production/main.tf
module "finops_scheduler_production" {
  source = "./modules/finops-scheduler"

  environment          = "production"
  schedule_startup     = "cron(0 10 ? * * *)"  # 7AM BRT 7 dias/semana
  schedule_shutdown    = "cron(0 3 ? * * *)"   # 0AM (meia-noite) BRT 7 dias/semana

  asg_names            = ["eks-marco2-production-production-*"]
  rds_instance_id      = "marco2-prod-rds"
  dynamodb_table_name  = "finops-scheduler-state"  # Shared com STAGING

  health_check_gitlab_enabled       = true
  health_check_transactions_enabled = true   # PROD: Transações DB
  health_check_connections_enabled  = true   # PROD: Conexões idle
  health_check_queues_enabled       = true   # PROD: RabbitMQ queues

  circuit_breaker_threshold    = 2  # PROD: mais sensível (2 vs 3 STAGING)
  notification_pagerduty_key   = var.pagerduty_api_key
  notification_slack_webhook   = var.slack_webhook_url_prod

  brasil_api_enabled   = true
  skip_holidays        = false  # PROD: liga SEMPRE, incluindo feriados

  rds_snapshot_enabled = true  # PROD: snapshot pré-shutdown
  rollback_automatic   = true  # PROD: rollback automático

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "finops-automation"
    CriticalSystem = "true"
  }
}
```

### 6.2 Lambda Function PRODUCTION (Rigorosa)

**Diferenças vs STAGING:**
- Health checks rigorosos (transações DB, conexões, queues)
- Circuit breaker threshold: 2 falhas (vs 3 STAGING)
- Snapshot RDS pré-shutdown
- Rollback automático
- Notificação PagerDuty P1

**Arquivo:** `terraform/modules/finops-scheduler/lambda/production/lambda_function.py`

```python
def pre_shutdown_health_checks_production():
    """
    Health checks PRODUCTION (rigorosos):
    BLOQUEIA shutdown se qualquer condição falhar
    """
    # 1. Verificar transações DB ativas
    active_transactions = check_rds_active_transactions(RDS_INSTANCE_ID)
    if active_transactions > 0:
        print(f"[PROD] {active_transactions} active DB transactions - POSTPONING shutdown")
        notify_pagerduty(severity="warning", message=f"PROD shutdown postponed: {active_transactions} active transactions")
        return False

    # 2. Verificar conexões idle recentes (< 5 min)
    idle_connections = check_rds_idle_connections(RDS_INSTANCE_ID, threshold_minutes=5)
    if idle_connections > 10:
        print(f"[PROD] {idle_connections} idle DB connections > 5 min - POSTPONING shutdown")
        return False

    # 3. Verificar mensagens RabbitMQ pendentes
    pending_messages = check_rabbitmq_queue_depth()
    if pending_messages > 100:
        print(f"[PROD] {pending_messages} pending messages in RabbitMQ - POSTPONING shutdown")
        notify_slack(channel="#prod-alerts", message=f"PROD shutdown postponed: {pending_messages} pending messages")
        return False

    # 4. Verificar AlertManager maintenance window
    if not check_alertmanager_maintenance_window():
        print(f"[PROD] No maintenance window configured - POSTPONING shutdown")
        return False

    # 5. Criar snapshot RDS PRÉ-shutdown (RPO < 1h)
    snapshot_id = create_rds_snapshot(RDS_INSTANCE_ID)
    print(f"[PROD] RDS snapshot created: {snapshot_id}")

    return True  # AUTORIZA shutdown

def create_rds_snapshot(db_instance_id):
    """
    Criar snapshot RDS automático antes de shutdown
    """
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    snapshot_id = f"prod-autosave-{timestamp}"

    rds.create_db_snapshot(
        DBSnapshotIdentifier=snapshot_id,
        DBInstanceIdentifier=db_instance_id,
        Tags=[
            {'Key': 'AutoGenerated', 'Value': 'finops-scheduler'},
            {'Key': 'Environment', 'Value': 'production'}
        ]
    )

    # Aguardar snapshot completo (timeout 10 min)
    waiter = rds.get_waiter('db_snapshot_completed')
    waiter.wait(
        DBSnapshotIdentifier=snapshot_id,
        WaiterConfig={'Delay': 30, 'MaxAttempts': 20}
    )

    return snapshot_id

def automatic_rollback_production():
    """
    Rollback automático PRODUCTION se startup falha 2×
    """
    failures = get_circuit_breaker_count()

    if failures >= 2:  # Threshold PROD: 2 falhas
        print(f"[PROD] CRITICAL: Startup failed 2× - TRIGGERING AUTOMATIC ROLLBACK")

        # 1. Desabilitar automação (circuit breaker)
        disable_eventbridge_rules(environment="production")

        # 2. Startup MANUAL via runbook
        trigger_manual_startup_runbook(environment="production")

        # 3. Notificar PagerDuty P1 IMEDIATO
        notify_pagerduty(
            severity="critical",
            message="PRODUCTION startup failed 2× - manual intervention required",
            escalation_level="P1"
        )

        # 4. Escalar gerência (SLA breach iminente)
        notify_slack(
            channel="#prod-incidents",
            message="@oncall @tech-lead @product-owner PRODUCTION startup failed 2×. Manual recovery in progress. ETA 15 min.",
            escalation=True
        )

        # 5. Preparar comunicação externa (status page)
        update_status_page(
            status="investigating",
            eta="15 min",
            message="We are experiencing issues starting our systems. Team is working on recovery."
        )
```

### 6.3 Deploy Fase 2

```bash
# 1. Validar Fase 1 completa (Go/No-Go)
# - STAGING operação 1 mês SEM falhas
# - SLA 99.5% atingido
# - Economia R$ 360/mês observada

# 2. Deploy Terraform PRODUCTION
cd terraform/environments/production
terraform init
terraform plan -var-file="production.tfvars"
terraform apply -var-file="production.tfvars"

# 3. Validar recursos criados
aws lambda get-function --function-name finops-scheduler-production
aws events list-rules --name-prefix finops-scheduler-production

# 4. Teste manual PROD (simular startup DRY-RUN)
aws lambda invoke \
  --function-name finops-scheduler-production \
  --payload '{"action": "startup", "dry_run": true}' \
  response.json

cat response.json

# 5. Load test PROD (validar 99.9% SLA)
cd tests/load
./run-load-test-production.sh

# 6. Habilitar EventBridge rules PROD (após validação)
aws events enable-rule --name finops-scheduler-production-startup
aws events enable-rule --name finops-scheduler-production-shutdown
```

---

## 7. Implementação Fase 3: STAGING On-Demand

### 7.1 Mudanças Fase 3

**Objetivo:** STAGING permanece desligado, liga apenas sob demanda manual.

**Ações:**
1. Desabilitar EventBridge rules STAGING (permanentemente)
2. Atualizar documentação: STAGING startup apenas manual
3. Criar script startup rápido STAGING

```bash
# 1. Desabilitar automação STAGING
aws events disable-rule --name finops-scheduler-staging-startup
aws events disable-rule --name finops-scheduler-staging-shutdown

# 2. Validar desabilitação
aws events list-rules --name-prefix finops-scheduler-staging --query 'Rules[*].[Name,State]'

# 3. Criar script startup manual STAGING
cat <<'EOF' > scripts/finops/startup-staging-manual.sh
#!/bin/bash
set -e

echo "🚀 Starting STAGING environment manually..."

# 1. Invocar Lambda startup
aws lambda invoke \
  --function-name finops-scheduler-staging \
  --payload '{"action": "startup"}' \
  /tmp/response.json

cat /tmp/response.json

# 2. Aguardar nodes Ready (5-8 min)
echo "⏳ Aguardando nodes Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=10m --context marco2-staging

# 3. Validar pods Running
echo "✅ Validando pods..."
kubectl get pods -A --context marco2-staging | grep -v Running | grep -v Completed || true

echo "✅ STAGING started successfully!"
EOF

chmod +x scripts/finops/startup-staging-manual.sh
```

### 7.2 Documentação Fase 3

**Atualizar README e runbooks:**

```markdown
## STAGING Environment (On-Demand - Fase 3)

**Status:** DESLIGADO permanentemente (liga sob demanda manual)

**Quando ligar STAGING:**
- Testes de integração complexos que requerem environment completo
- Homologação de features críticas antes de deploy PROD
- Troubleshooting de issues que não reproduzem localmente
- Estimativa: ~1×/semana (10h/mês uptime)

**Como ligar STAGING:**

```bash
# Startup manual STAGING (5-8 min)
./scripts/finops/startup-staging-manual.sh

# Shutdown manual STAGING (quando terminar)
./scripts/finops/shutdown-staging-manual.sh
```

**Custos:**
- 24/7: R$ 1.122/mês (R$ 13.464/ano)
- On-demand (5% uptime): R$ 60/mês (R$ 720/ano)
- **Economia: R$ 1.062/mês (R$ 12.744/ano)** ✅
```

---

## 8. Terraform Multi-Ambiente

### 8.1 Estrutura de Diretórios

```
terraform/
├── modules/
│   ├── finops-scheduler/
│   │   ├── main.tf              # Module principal reutilizável
│   │   ├── variables.tf         # Variáveis parametrizadas
│   │   ├── iam.tf               # IAM roles + policies
│   │   ├── dynamodb.tf          # Circuit breaker state (shared)
│   │   ├── lambda/
│   │   │   ├── staging/
│   │   │   │   └── lambda_function.py
│   │   │   └── production/
│   │   │       └── lambda_function.py
│   │   └── outputs.tf
├── environments/
│   ├── staging/
│   │   ├── main.tf              # Invoca module staging
│   │   ├── staging.tfvars       # Variáveis STAGING
│   │   └── backend.tf           # S3 backend STAGING
│   └── production/
│       ├── main.tf              # Invoca module production
│       ├── production.tfvars    # Variáveis PRODUCTION
│       └── backend.tf           # S3 backend PRODUCTION
```

### 8.2 Module Principal (Reutilizável)

**Arquivo:** `terraform/modules/finops-scheduler/main.tf`

```hcl
# Lambda Function
resource "aws_lambda_function" "finops_scheduler" {
  function_name = "finops-scheduler-${var.environment}"
  role          = aws_iam_role.finops_scheduler.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300  # 5 min
  memory_size   = 512

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      ASG_NAMES           = join(",", var.asg_names)
      RDS_INSTANCE_ID     = var.rds_instance_id
      DYNAMODB_TABLE      = var.dynamodb_table_name
      BRASIL_API_URL      = var.brasil_api_url
      SKIP_HOLIDAYS       = var.skip_holidays
      CIRCUIT_BREAKER_THRESHOLD = var.circuit_breaker_threshold
      SLACK_WEBHOOK_URL   = var.notification_slack_webhook
      PAGERDUTY_API_KEY   = var.notification_pagerduty_key
      RDS_SNAPSHOT_ENABLED = var.rds_snapshot_enabled
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "finops-scheduler-${var.environment}"
    }
  )
}

# EventBridge Rules
resource "aws_cloudwatch_event_rule" "startup" {
  name                = "finops-scheduler-${var.environment}-startup"
  description         = "Trigger ${var.environment} startup"
  schedule_expression = var.schedule_startup
  is_enabled          = var.eventbridge_enabled

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "shutdown" {
  name                = "finops-scheduler-${var.environment}-shutdown"
  description         = "Trigger ${var.environment} shutdown"
  schedule_expression = var.schedule_shutdown
  is_enabled          = var.eventbridge_enabled

  tags = var.tags
}

# EventBridge Targets
resource "aws_cloudwatch_event_target" "startup_target" {
  rule      = aws_cloudwatch_event_rule.startup.name
  target_id = "FinOpsSchedulerStartup"
  arn       = aws_lambda_function.finops_scheduler.arn

  input = jsonencode({
    action = "startup"
  })
}

resource "aws_cloudwatch_event_target" "shutdown_target" {
  rule      = aws_cloudwatch_event_rule.shutdown.name
  target_id = "FinOpsSchedulerShutdown"
  arn       = aws_lambda_function.finops_scheduler.arn

  input = jsonencode({
    action = "shutdown"
  })
}

# Lambda Permissions (EventBridge invoke)
resource "aws_lambda_permission" "allow_eventbridge_startup" {
  statement_id  = "AllowExecutionFromEventBridgeStartup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.startup.arn
}

resource "aws_lambda_permission" "allow_eventbridge_shutdown" {
  statement_id  = "AllowExecutionFromEventBridgeShutdown"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.shutdown.arn
}
```

### 8.3 Variables (Parametrizadas)

**Arquivo:** `terraform/modules/finops-scheduler/variables.tf`

```hcl
variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be staging or production"
  }
}

variable "schedule_startup" {
  description = "Cron expression for startup (UTC)"
  type        = string
  # STAGING: cron(0 11 ? * MON-FRI *)  # 8AM BRT
  # PROD:    cron(0 10 ? * * *)        # 7AM BRT 7 days
}

variable "schedule_shutdown" {
  description = "Cron expression for shutdown (UTC)"
  type        = string
  # STAGING: cron(0 21 ? * MON-FRI *)  # 6PM BRT
  # PROD:    cron(0 3 ? * * *)         # 0AM BRT 7 days
}

variable "asg_names" {
  description = "List of ASG names to scale (supports wildcards)"
  type        = list(string)
}

variable "rds_instance_id" {
  description = "RDS instance identifier"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB table for circuit breaker state (shared)"
  type        = string
  default     = "finops-scheduler-state"
}

variable "skip_holidays" {
  description = "Skip startup on Brazilian national holidays"
  type        = bool
  default     = true  # STAGING: true, PROD: false
}

variable "circuit_breaker_threshold" {
  description = "Number of consecutive failures before disabling automation"
  type        = number
  default     = 3  # STAGING: 3, PROD: 2
}

variable "rds_snapshot_enabled" {
  description = "Create RDS snapshot before shutdown (PROD only)"
  type        = bool
  default     = false  # STAGING: false, PROD: true
}

variable "notification_slack_webhook" {
  description = "Slack webhook URL for notifications"
  type        = string
  sensitive   = true
}

variable "notification_pagerduty_key" {
  description = "PagerDuty API key for critical alerts (PROD only)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "eventbridge_enabled" {
  description = "Enable EventBridge rules (disable for Fase 3 STAGING on-demand)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

---

## 9. Lambda Functions

### 9.1 Código Comum (Shared)

**Arquivo:** `terraform/modules/finops-scheduler/lambda/shared/utils.py`

```python
"""
Shared utilities para Lambda STAGING e PRODUCTION
"""
import boto3
import requests
from datetime import datetime, timedelta

dynamodb = boto3.client('dynamodb')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

def is_holiday(brasil_api_url, dynamodb_table, skip_holidays=True):
    """
    Verifica feriado nacional brasileiro
    Cache DynamoDB (30 dias TTL) + fallback estático
    """
    if not skip_holidays:
        return False  # PROD: nunca skip

    today = datetime.now().strftime('%Y-%m-%d')
    year = datetime.now().year

    # Cache DynamoDB
    try:
        response = dynamodb.get_item(
            TableName=dynamodb_table,
            Key={'pk': {'S': f'holiday#{today}'}}
        )

        if 'Item' in response:
            return response['Item']['is_holiday']['BOOL']
    except Exception as e:
        print(f"DynamoDB cache miss: {str(e)}")

    # BrasilAPI
    try:
        response = requests.get(f"{brasil_api_url}{year}", timeout=5)
        holidays = response.json()

        for holiday in holidays:
            if holiday['date'] == today:
                # Save cache
                save_holiday_cache(dynamodb_table, today, is_holiday=True)
                return True

        save_holiday_cache(dynamodb_table, today, is_holiday=False)
        return False

    except Exception as e:
        print(f"BrasilAPI failed: {str(e)} - usando fallback")
        return is_holiday_static_fallback(today, year)

def save_holiday_cache(table_name, date, is_holiday):
    """Salvar cache feriado DynamoDB (TTL 30 dias)"""
    ttl = int((datetime.now() + timedelta(days=30)).timestamp())

    dynamodb.put_item(
        TableName=table_name,
        Item={
            'pk': {'S': f'holiday#{date}'},
            'is_holiday': {'BOOL': is_holiday},
            'ttl': {'N': str(ttl)}
        }
    )

def is_holiday_static_fallback(date, year):
    """Fallback: feriados nacionais fixos"""
    static_holidays = {
        f"{year}-01-01": "Ano Novo",
        f"{year}-04-21": "Tiradentes",
        f"{year}-05-01": "Dia do Trabalho",
        f"{year}-09-07": "Independência",
        f"{year}-10-12": "Nossa Senhora Aparecida",
        f"{year}-11-02": "Finados",
        f"{year}-11-15": "Proclamação da República",
        f"{year}-12-25": "Natal"
    }
    return date in static_holidays

def get_circuit_breaker_count(dynamodb_table, environment):
    """Buscar contador circuit breaker"""
    try:
        response = dynamodb.get_item(
            TableName=dynamodb_table,
            Key={'pk': {'S': f'circuit_breaker#{environment}'}}
        )

        if 'Item' in response:
            return int(response['Item']['failures']['N'])
        return 0
    except Exception:
        return 0

def increment_circuit_breaker(dynamodb_table, environment, threshold):
    """Incrementar circuit breaker, desabilitar se threshold atingido"""
    try:
        response = dynamodb.update_item(
            TableName=dynamodb_table,
            Key={'pk': {'S': f'circuit_breaker#{environment}'}},
            UpdateExpression='ADD failures :inc',
            ExpressionAttributeValues={':inc': {'N': '1'}},
            ReturnValues='UPDATED_NEW'
        )

        failures = int(response['Attributes']['failures']['N'])

        if failures >= threshold:
            print(f"[{environment}] Circuit breaker OPEN: {failures} failures >= {threshold}")
            disable_eventbridge_rules(environment)
            send_critical_alert(environment, failures)

        return failures
    except Exception as e:
        print(f"Circuit breaker increment error: {str(e)}")
        return 0

def reset_circuit_breaker(dynamodb_table, environment):
    """Resetar circuit breaker após sucesso"""
    dynamodb.put_item(
        TableName=dynamodb_table,
        Item={
            'pk': {'S': f'circuit_breaker#{environment}'},
            'failures': {'N': '0'},
            'last_success': {'S': datetime.now().isoformat()}
        }
    )

def publish_cloudwatch_metric(namespace, metric_name, value, environment):
    """Publicar métrica CloudWatch"""
    cloudwatch.put_metric_data(
        Namespace=namespace,
        MetricData=[
            {
                'MetricName': metric_name,
                'Value': value,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': environment}
                ],
                'Timestamp': datetime.now()
            }
        ]
    )

def send_critical_alert(environment, failures):
    """Enviar alerta crítico (Slack + PagerDuty se PROD)"""
    # Implementação notificações
    pass
```

---

## 10. Testes e Validação

### 10.1 Testes Unitários

```bash
# Estrutura testes
tests/
├── unit/
│   ├── test_holiday_detection.py
│   ├── test_health_checks.py
│   ├── test_circuit_breaker.py
│   └── test_metrics.py
├── integration/
│   ├── test_staging_startup.py
│   ├── test_staging_shutdown.py
│   ├── test_production_startup.py
│   └── test_production_shutdown.py
└── e2e/
    ├── test_full_cycle_staging.sh
    └── test_full_cycle_production.sh

# Rodar testes unitários
cd tests/unit
pytest -v

# Rodar testes integração (STAGING)
cd tests/integration
pytest test_staging_startup.py -v

# Rodar teste E2E (STAGING)
cd tests/e2e
./test_full_cycle_staging.sh
```

### 10.2 Teste Manual STAGING

```bash
# 1. Teste startup manual
aws lambda invoke \
  --function-name finops-scheduler-staging \
  --payload '{"action": "startup"}' \
  /tmp/response.json

cat /tmp/response.json

# 2. Validar nodes Ready
kubectl get nodes --context marco2-staging

# 3. Validar pods Running
kubectl get pods -A --context marco2-staging | grep -v Running

# 4. Teste shutdown manual
aws lambda invoke \
  --function-name finops-scheduler-staging \
  --payload '{"action": "shutdown"}' \
  /tmp/response.json

# 5. Validar ASG scaled to 0
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names eks-marco2-staging-regular-* \
  --query 'AutoScalingGroups[*].[AutoScalingGroupName,MinSize,DesiredCapacity]'

# 6. Validar RDS stopped
aws rds describe-db-instances \
  --db-instance-identifier marco2-staging-rds \
  --query 'DBInstances[0].DBInstanceStatus'
```

### 10.3 Teste Manual PRODUCTION (Dry-Run)

```bash
# 1. Teste startup DRY-RUN (não executa, apenas valida)
aws lambda invoke \
  --function-name finops-scheduler-production \
  --payload '{"action": "startup", "dry_run": true}' \
  /tmp/response.json

cat /tmp/response.json

# 2. Load test PROD (validar SLA 99.9%)
cd tests/load
./run-load-test-production.sh

# Output esperado:
# - Requests: 10,000
# - Success rate: 99.9%+
# - p95 latency: < 500ms
# - p99 latency: < 1s

# 3. Health checks validation
./validate-prod-health-checks.sh
```

---

## 11. Monitoramento Consolidado

### 11.1 CloudWatch Metrics

| Métrica | Namespace | STAGING | PRODUCTION | Alerta |
|---------|-----------|---------|------------|--------|
| `startup_duration` | FinOps/Scheduler | < 8 min | < 8 min | > 10 min (warning) |
| `shutdown_duration` | FinOps/Scheduler | < 5 min | < 5 min | > 7 min (info) |
| `cost_savings_daily` | FinOps/Costs | $2/dia | $4.33/dia | < 80% esperado (warning) |
| `circuit_breaker_state` | FinOps/Health | 0 (closed) | 0 (closed) | 1 (critical + PagerDuty) |
| `holiday_detected` | FinOps/Scheduler | 0/1 | 0 (sempre liga) | N/A (info) |
| `health_check_failures` | FinOps/Health | count | count | > 3/dia (warning) |
| `sla_availability` | FinOps/SLA | 99.5% | 99.9% | < target (critical) |

### 11.2 Grafana Dashboards

**Dashboard 1: FinOps Multi-Ambiente Overview**

```yaml
Panels:
  1. Uptime Real vs Planejado (timeseries 30 dias)
     - STAGING: 50h/semana esperado
     - PRODUCTION: 119h/semana esperado

  2. Economia Acumulada (gauge)
     - Fase 1: R$ 360/mês (target)
     - Fase 2: R$ 1.140/mês (target)
     - Fase 3: R$ 1.842/mês (target)

  3. Falhas e Circuit Breaker (stat)
     - STAGING: Threshold 3
     - PRODUCTION: Threshold 2

  4. SLA Compliance (gauge)
     - STAGING: 99.5% target
     - PRODUCTION: 99.9% target

  5. Startup Duration Trend (timeseries)
     - STAGING: 6 min média
     - PRODUCTION: 6 min média
```

**Dashboard 2: FinOps PRODUCTION Critical**

```yaml
Panels (PROD-specific):
  1. Revenue Impact (currency)
     - Downtime × R$ 5.000/h

  2. Rollback Automático (counter)
     - Triggered count

  3. Health Check Blocks (timeseries)
     - Transações ativas
     - Conexões idle
     - Mensagens RabbitMQ

  4. RDS Snapshots (table)
     - Último snapshot timestamp
     - Size
     - Status
```

### 11.3 Alertas Consolidados

**STAGING:**

| Condição | Severidade | Destino | Ação |
|----------|-----------|---------|------|
| Startup duration > 15 min | 🟡 Warning | Slack #finops-alerts | Investigar RDS/nodes performance |
| Startup failed 3× | 🔴 Critical | Slack #finops-alerts | Disable automation, manual recovery |
| Cost savings < $1.60/dia | 🟡 Warning | Slack #finops | Validar uptime real |

**PRODUCTION:**

| Condição | Severidade | Destino | Ação |
|----------|-----------|---------|------|
| Startup duration > 10 min | 🔴 Critical | PagerDuty P1 + Slack #prod-incidents | Rollback automático triggered |
| Startup failed 2× | 🔴 Critical | PagerDuty P1 + Slack #prod-incidents | Manual intervention, status page |
| SLA < 99.9% | 🔴 Critical | PagerDuty P1 | Disable automation, root cause analysis |
| Health check blocks > 5/dia | 🟡 Warning | Slack #prod-alerts | Revisar schedule shutdown (carga noturna?) |

---

## 12. Troubleshooting Multi-Ambiente

### 12.1 Problemas Comuns STAGING

**Problema: Startup falha (RDS timeout)**

```bash
# 1. Verificar status RDS
aws rds describe-db-instances \
  --db-instance-identifier marco2-staging-rds \
  --query 'DBInstances[0].[DBInstanceStatus,DBInstanceIdentifier]'

# 2. Forçar start manual
aws rds start-db-instance --db-instance-identifier marco2-staging-rds

# 3. Logs Lambda
aws logs tail /aws/lambda/finops-scheduler-staging --follow
```

**Problema: Circuit breaker ativado**

```bash
# 1. Verificar contador DynamoDB
aws dynamodb get-item \
  --table-name finops-scheduler-state \
  --key '{"pk": {"S": "circuit_breaker#staging"}}'

# 2. Resetar circuit breaker
aws dynamodb put-item \
  --table-name finops-scheduler-state \
  --item '{"pk": {"S": "circuit_breaker#staging"}, "failures": {"N": "0"}}'

# 3. Re-habilitar EventBridge
aws events enable-rule --name finops-scheduler-staging-startup
```

### 12.2 Problemas Comuns PRODUCTION

**Problema: Rollback automático triggered**

```bash
# 1. Verificar logs Lambda (rollback reason)
aws logs tail /aws/lambda/finops-scheduler-production --since 1h --follow

# 2. Verificar health checks (qual falhou?)
# - Transações DB ativas?
# - Conexões idle?
# - Mensagens RabbitMQ?

# 3. Startup manual PROD (recovery)
./scripts/finops/startup-marco2.sh production --force

# 4. Validar serviços críticos
kubectl get pods -n production -l tier=critical --context marco2-production

# 5. Update status page (comunicação externa)
./scripts/update-status-page.sh --status operational
```

**Problema: SLA 99.9% breach**

```bash
# 1. Calcular downtime real
aws cloudwatch get-metric-statistics \
  --namespace FinOps/SLA \
  --metric-name sla_availability \
  --dimensions Name=Environment,Value=production \
  --start-time $(date -u -d '1 month ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average

# 2. Identificar causa (startup falhas? shutdown bloqueado?)
# 3. Decisão: Desabilitar automação se SLA não atingível
aws events disable-rule --name finops-scheduler-production-startup
aws events disable-rule --name finops-scheduler-production-shutdown

# 4. Escalar para gerência (decisão estratégica)
# - Manter 24/7 PROD (R$ 9.360/ano perdidos)
# - Ajustar schedule (ex: 6h-0h ao invés de 7h-0h)
# - Revisar health checks (muito rigorosos?)
```

---

## 13. Checklist de Conclusão

### 13.1 Fase 1: STAGING (Conclusão)

**Pré-Deploy:**
- [ ] Terraform code revisado (peer review)
- [ ] IAM policies validadas (least privilege)
- [ ] Lambda function testada localmente
- [ ] BrasilAPI cache implementado (DynamoDB)
- [ ] Circuit breaker testado (3 falhas threshold)

**Deploy:**
- [ ] Terraform apply STAGING executado
- [ ] Lambda deployed (finops-scheduler-staging)
- [ ] EventBridge rules criadas (disabled inicial)
- [ ] DynamoDB table criada (finops-scheduler-state)
- [ ] Teste manual startup/shutdown bem-sucedido

**Validação 1 Mês:**
- [ ] EventBridge rules habilitadas
- [ ] Operação 30 dias SEM falhas
- [ ] SLA 99.5% (8h-18h) atingido
- [ ] Economia observada ≥ R$ 360/mês (tolerância 10%)
- [ ] Zero circuit breaker triggers
- [ ] Grafana dashboard configurado
- [ ] Alertas Slack funcionando

**Go/No-Go Fase 2:**
- [ ] Retrospectiva equipe (learnings STAGING)
- [ ] Aprovação stakeholders (arquitetura + FinOps)
- [ ] Sign-off Product Owner (PROD automation)

---

### 13.2 Fase 2: PRODUCTION (Conclusão)

**Pré-Deploy:**
- [ ] STAGING validado 1 mês (Fase 1 completa)
- [ ] Marco 3 deployado (PROD environment ativo)
- [ ] Load tests PROD executados (99.9% SLA confirmado)
- [ ] Lambda PROD code revisado (health checks rigorosos)
- [ ] Runbooks recovery documentados (rollback manual)
- [ ] PagerDuty integration configurada

**Deploy:**
- [ ] Terraform apply PRODUCTION executado
- [ ] Lambda deployed (finops-scheduler-production)
- [ ] EventBridge rules PROD criadas (disabled inicial)
- [ ] Teste manual startup/shutdown PROD (dry-run)
- [ ] Snapshot RDS pré-shutdown validado

**Validação 2 Meses:**
- [ ] EventBridge rules PROD habilitadas
- [ ] Operação 60 dias SEM falhas
- [ ] SLA 99.9% (7h-0h) atingido
- [ ] Economia observada ≥ R$ 1.140/mês (tolerância 10%)
- [ ] Zero rollbacks automáticos
- [ ] STAGING usado < 2×/mês (on-demand candidato)
- [ ] Cobertura testes automatizados > 80%

**Go/No-Go Fase 3:**
- [ ] PROD estável 2 meses
- [ ] Equipe confortável CI/CD production-first
- [ ] Validar necessidade STAGING (< 2×/mês?)
- [ ] Aprovação STAGING on-demand (economia adicional R$ 1.062/mês)

---

### 13.3 Fase 3: STAGING On-Demand (Conclusão)

**Mudanças:**
- [ ] EventBridge rules STAGING disabled permanentemente
- [ ] Script startup manual STAGING criado
- [ ] Documentação atualizada (README, runbooks)
- [ ] Treinamento equipe (quando/como ligar STAGING)

**Validação 3 Meses:**
- [ ] STAGING uptime < 10% (on-demand)
- [ ] Economia observada ≥ R$ 1.842/mês
- [ ] Zero impacto produção (workloads testados antes)
- [ ] Startup manual STAGING < 10 min

**Retrospectiva Final:**
- [ ] Economia total validada: R$ 22.104/ano
- [ ] ROI Year 1: 391%
- [ ] NPV 3 anos: R$ 50.479
- [ ] Lessons learned documentadas
- [ ] Celebração equipe! 🎉

---

## 14. Referências

### 14.1 Documentação Interna

- [Demanda STAGING](../../demands/2026-01-30-automacao-finops-staging.md)
- [Demanda PRODUCTION](../../demands/2026-01-30-automacao-finops-production.md)
- [ADR-024: FinOps Automation Multi-Ambiente](../../context/decisions.md#adr-024)
- [Architecture Multi-Ambiente](../../context/architecture.md#fase-9-finops-automation-multi-ambiente)
- [Costs Analysis](../../context/costs.md#automação-finops-multi-ambiente)
- [Risks STAGING](../../context/risks.md#r-019)
- [Risks PRODUCTION](../../context/risks.md#r-020)

### 14.2 Scripts Úteis

```bash
# Scripts finops/
scripts/finops/
├── shutdown-marco2.sh           # Shutdown manual multi-ambiente
├── startup-marco2.sh            # Startup manual multi-ambiente
├── startup-staging-manual.sh    # Startup STAGING on-demand (Fase 3)
├── validate-health-checks.sh    # Validar health checks
└── update-status-page.sh        # Atualizar status page externa
```

### 14.3 AWS Documentation

- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS EventBridge Scheduler](https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html)
- [RDS Stop/Start](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_StopInstance.html)
- [Auto Scaling Groups](https://docs.aws.amazon.com/autoscaling/ec2/userguide/what-is-amazon-ec2-auto-scaling.html)

### 14.4 APIs Externas

- [BrasilAPI Feriados](https://brasilapi.com.br/docs#tag/Feriados-Nacionais)

---

**Mantenedor:** DevOps Team
**Última Revisão:** 2026-01-30
**Status:** 📝 PLANEJADO - Aguardando aprovação Fase 1

**Próximos Passos:**
1. Aprovação stakeholders (Arquitetura, FinOps, Security, Product Owner)
2. Deploy Fase 1 STAGING (target: 2026-02-17)
3. Validação 1 mês STAGING
4. Go/No-Go Fase 2
5. Deploy Fase 2 PRODUCTION (target: 2026-04-15)
