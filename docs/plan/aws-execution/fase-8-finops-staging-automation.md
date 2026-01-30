# Fase 8 - Automação FinOps STAGING (EventBridge + Lambda)

> **Automação Start/Stop Ambiente STAGING - Economia R$ 4.320/ano**
> **Pré-requisitos**: Marco 2 completo, STAGING environment existente
> **Status**: 📝 PLANEJADO (Aprovação pendente)

---

## Índice

1. [Visão Geral](#1-visão-geral)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Arquitetura da Solução](#3-arquitetura-da-solução)
4. [Implementação Terraform](#4-implementação-terraform)
5. [Lambda Function](#5-lambda-function)
6. [EventBridge Scheduler](#6-eventbridge-scheduler)
7. [Testes e Validação](#7-testes-e-validação)
8. [Monitoramento](#8-monitoramento)
9. [Troubleshooting](#9-troubleshooting)
10. [Checklist de Conclusão](#10-checklist-de-conclusão)

---

## 1. Visão Geral

### 1.1 Objetivos

**Problema:**
- Ambiente STAGING opera 24/7 mas é utilizado apenas 8h-18h Mon-Fri
- Desperdício de 70% do tempo (118h/semana sem uso)
- Custo STAGING: $187/mês ($60/mês evitável)

**Solução:**
- Automação start/stop via EventBridge + Lambda
- Schedule: 8:00 AM - 18:00 BRT, Mon-Fri
- Respeita feriados nacionais brasileiros (BrasilAPI)
- Health checks + Circuit breaker

**Benefícios:**
- Economia: R$ 4.320/ano (R$ 360/mês)
- ROI: 44% Year 1 (payback 6.7 meses)
- Zero toil operacional (vs manual shutdown 2×/dia)
- Aderência FinOps best practices

### 1.2 Estimativa de Custos

```
STAGING Atual (24/7):               $187/mês
STAGING Com Automação (50h/semana): $127/mês
─────────────────────────────────────────────
ECONOMIA:                            $60/mês ($720/ano)
ECONOMIA BRL (taxa 6.0):             R$ 360/mês (R$ 4.320/ano)

Investimento:                        R$ 3.000 (10h dev)
Custo Operacional Lambda:            R$ 24/ano ($2/mês)
ROI Year 1:                          44%
Payback:                             6.7 meses
```

### 1.3 Timeline

| Fase | Duração | Responsável | Entregável |
|------|---------|-------------|------------|
| **Aprovação** | 2 dias | Stakeholders | Sign-off ADR-024 |
| **Desenvolvimento** | 1 semana | DevOps | Lambda + Terraform module |
| **Testes** | 3 dias | QA + DevOps | Testes integrados |
| **Deploy** | 1 dia | DevOps | EventBridge habilitado |
| **Monitoramento** | 1 mês | FinOps | Validação economia real |
| **TOTAL** | 6 semanas | | Break-even: 6.7 meses |

---

## 2. Pré-requisitos

### 2.1 Infraestrutura

```bash
# Validar recursos existentes
aws eks describe-cluster --name marco2-staging --region us-east-1
aws rds describe-db-instances --db-instance-identifier marco2-staging-rds
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names eks-marco2-staging-regular-*
```

**Checklist:**
- [ ] Cluster EKS staging existente
- [ ] RDS PostgreSQL staging ativo
- [ ] Node groups identificados (critical vs regular)
- [ ] IAM permissions para Lambda (ASG, RDS, EKS)

### 2.2 Ferramentas

```bash
# Terraform >= 1.6
terraform version

# AWS CLI >= 2.0
aws --version

# kubectl configurado
kubectl get nodes --context marco2-staging

# Python 3.12 (para testes locais Lambda)
python3 --version
```

### 2.3 Permissões AWS

```bash
# Validar permissões IAM
aws iam get-user
aws sts get-caller-identity

# Permissões necessárias:
# - iam:CreateRole, iam:AttachRolePolicy
# - lambda:CreateFunction, lambda:UpdateFunctionCode
# - events:PutRule, events:PutTargets
# - autoscaling:UpdateAutoScalingGroup
# - rds:StopDBInstance, rds:StartDBInstance
# - dynamodb:PutItem, dynamodb:GetItem (circuit breaker)
```

---

## 3. Arquitetura da Solução

### 3.1 Diagrama de Componentes

```
┌─────────────────────────────────────────────────────────────┐
│              EventBridge Scheduler (2 rules)                │
├─────────────────────────────────────────────────────────────┤
│  Rule 1: STARTUP  → cron(0 11 ? * MON-FRI *)  # 8AM BRT    │
│  Rule 2: SHUTDOWN → cron(0 21 ? * MON-FRI *)  # 6PM BRT    │
│  Target: Lambda finops-scheduler-staging                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│         Lambda: finops-scheduler-staging (Python 3.12)      │
├─────────────────────────────────────────────────────────────┤
│  Handler: lambda_function.lambda_handler                    │
│  Memory: 512 MB                                             │
│  Timeout: 300s (5 min)                                      │
│  Environment Variables:                                     │
│    - ENVIRONMENT=staging                                    │
│    - ASG_NAMES=eks-marco2-staging-regular-*                 │
│    - RDS_INSTANCE_ID=marco2-staging-rds                     │
│    - DYNAMODB_TABLE=finops-scheduler-state                  │
│    - BRASIL_API_URL=https://brasilapi.com.br/api/...       │
├─────────────────────────────────────────────────────────────┤
│  Lógica:                                                    │
│  1. Verificar feriados (BrasilAPI + cache DynamoDB)        │
│  2. Health checks (GitLab jobs, ArgoCD syncs)              │
│  3. Executar ação:                                          │
│     STOP:  ASG min=0, RDS pause, scale operators to 0       │
│     START: RDS resume, ASG restore min=2, wait Ready        │
│  4. Circuit breaker tracking (DynamoDB)                     │
│  5. Métricas CloudWatch + notificação Slack                 │
└─────────────────────────────────────────────────────────────┘
         │                  │                  │
         ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ ASG Scaling  │  │  RDS Pause   │  │  DynamoDB    │
│ (EC2 Nodes)  │  │  (staging)   │  │  (state)     │
└──────────────┘  └──────────────┘  └──────────────┘
```

### 3.2 Node Groups Strategy

```yaml
# Node Group: critical-always-on (24/7)
Workloads:
  - GitLab (jobs noturnos agendados)
  - Harbor (registry sempre disponível)
  - ArgoCD (reconciliação contínua)
  - Prometheus/Grafana (observabilidade 24/7)
Instances:
  - 1× t3.medium
  - Custo: $30/mês
Behavior:
  - NUNCA desliga

# Node Group: regular (8h-18h Mon-Fri)
Workloads:
  - Keycloak staging
  - SonarQube staging
  - Kong staging
  - Redis Operator (scaled to 0)
  - RabbitMQ Operator (scaled to 0)
Instances:
  - 2× t3.medium
  - Custo: $60/mês (24/7) → $18/mês (30% uptime)
Behavior:
  - START: 8:00 AM BRT
  - STOP: 18:00 BRT (Mon-Fri)
```

### 3.3 Fluxo de Execução

**STARTUP (8:00 AM BRT):**

```
1. EventBridge dispara Lambda
2. Lambda verifica feriado (BrasilAPI)
   ├─ Feriado detectado? → SKIP (log + exit)
   └─ Dia útil? → Continua
3. RDS Start
   ├─ aws rds start-db-instance
   ├─ Retry 3× com backoff (30s, 60s, 120s)
   └─ Aguarda status "available" (timeout 5 min)
4. ASG Scale Up
   ├─ aws autoscaling update-auto-scaling-group --min-size 2 --desired-capacity 2
   ├─ Aguarda nodes join (timeout 3 min)
   └─ kubectl get nodes --selector=node-type=regular
5. Health Checks
   ├─ Nodes Ready? (kubectl wait)
   ├─ Pods Running? (kubectl get pods -n platform-core-staging)
   └─ RDS Available? (aws rds describe-db-instances)
6. Métricas CloudWatch
   ├─ finops.startup.duration = <seconds>
   ├─ finops.startup.success = 1
   └─ Notificação Slack: "✅ STAGING started in 6m23s"
7. Reset Circuit Breaker
   └─ DynamoDB: startup_failures = 0
```

**SHUTDOWN (18:00 BRT):**

```
1. EventBridge dispara Lambda
2. Health Checks (bloquear se jobs ativos)
   ├─ GitLab jobs running? GET /api/v4/jobs?scope[]=running
   │  └─ > 0 jobs? → SKIP shutdown (log + exit)
   ├─ ArgoCD syncs in progress? kubectl get applications -o json
   │  └─ Syncing? → SKIP shutdown
   └─ All clear? → Continua
3. Grace Period (5 min warning)
   ├─ Notificação Slack: "⚠️ STAGING will shutdown in 5 min"
   └─ Sleep 300s
4. Scale Operators to 0
   ├─ kubectl scale deployment redis-operator --replicas=0
   └─ kubectl scale deployment rabbitmq-cluster-operator --replicas=0
5. ASG Scale Down
   ├─ aws autoscaling update-auto-scaling-group --min-size 0 --desired-capacity 0
   └─ Aguarda nodes terminate (timeout 4 min)
6. RDS Pause
   ├─ aws rds stop-db-instance
   └─ Aguarda status "stopped" (timeout 5 min)
7. Métricas CloudWatch
   ├─ finops.shutdown.duration = <seconds>
   ├─ finops.cost_savings_daily = $2.40
   └─ Notificação Slack: "☑️ STAGING stopped. Saving $2.40 tonight."
```

---

## 4. Implementação Terraform

### 4.1 Estrutura de Diretórios

```bash
terraform/modules/finops-scheduler/
├── main.tf                 # Lambda, EventBridge, IAM
├── variables.tf            # Configurações (schedule, environment)
├── outputs.tf              # Lambda ARN, EventBridge rules
├── lambda/
│   ├── lambda_function.py  # Handler principal
│   ├── requirements.txt    # boto3, requests (BrasilAPI)
│   └── config.yaml         # Node groups, health checks
├── iam.tf                  # IAM Role + Policies
├── dynamodb.tf             # Circuit breaker state table
└── README.md
```

### 4.2 variables.tf

```hcl
# terraform/modules/finops-scheduler/variables.tf

variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
  default     = "staging"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "marco2-staging"
}

variable "rds_instance_id" {
  description = "RDS instance identifier"
  type        = string
  default     = "marco2-staging-rds"
}

variable "asg_names" {
  description = "Auto Scaling Group names (regular nodes)"
  type        = list(string)
  default     = ["eks-marco2-staging-regular-*"]
}

variable "startup_schedule" {
  description = "Cron expression for startup (UTC)"
  type        = string
  default     = "cron(0 11 ? * MON-FRI *)"  # 8:00 AM BRT
}

variable "shutdown_schedule" {
  description = "Cron expression for shutdown (UTC)"
  type        = string
  default     = "cron(0 21 ? * MON-FRI *)"  # 6:00 PM BRT
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 300  # 5 minutes
}

variable "lambda_memory" {
  description = "Lambda memory in MB"
  type        = number
  default     = 512
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "k8s-platform"
    Environment = "staging"
    ManagedBy   = "terraform"
    Component   = "finops-automation"
  }
}
```

### 4.3 main.tf (Lambda + EventBridge)

```hcl
# terraform/modules/finops-scheduler/main.tf

# Lambda Function
resource "aws_lambda_function" "finops_scheduler" {
  function_name = "finops-scheduler-${var.environment}"
  description   = "FinOps automation start/stop ${var.environment} environment"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"
  timeout = var.lambda_timeout
  memory_size = var.lambda_memory

  role = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      ENVIRONMENT       = var.environment
      CLUSTER_NAME      = var.cluster_name
      RDS_INSTANCE_ID   = var.rds_instance_id
      ASG_NAMES         = join(",", var.asg_names)
      DYNAMODB_TABLE    = aws_dynamodb_table.scheduler_state.name
      BRASIL_API_URL    = "https://brasilapi.com.br/api/feriados/v1"
      LOG_LEVEL         = "INFO"
    }
  }

  tags = var.tags
}

# Package Lambda code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# EventBridge Rule: STARTUP
resource "aws_cloudwatch_event_rule" "startup" {
  name                = "finops-startup-${var.environment}"
  description         = "Start ${var.environment} environment at 8 AM BRT"
  schedule_expression = var.startup_schedule

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "startup_target" {
  rule      = aws_cloudwatch_event_rule.startup.name
  target_id = "lambda-finops-scheduler"
  arn       = aws_lambda_function.finops_scheduler.arn

  input = jsonencode({
    action      = "start"
    environment = var.environment
  })
}

# EventBridge Rule: SHUTDOWN
resource "aws_cloudwatch_event_rule" "shutdown" {
  name                = "finops-shutdown-${var.environment}"
  description         = "Stop ${var.environment} environment at 6 PM BRT"
  schedule_expression = var.shutdown_schedule

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "shutdown_target" {
  rule      = aws_cloudwatch_event_rule.shutdown.name
  target_id = "lambda-finops-scheduler"
  arn       = aws_lambda_function.finops_scheduler.arn

  input = jsonencode({
    action      = "stop"
    environment = var.environment
  })
}

# Lambda permissions for EventBridge
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

### 4.4 iam.tf (IAM Role + Policies)

```hcl
# terraform/modules/finops-scheduler/iam.tf

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "finops-scheduler-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# Policy: CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy: Auto Scaling Groups
resource "aws_iam_role_policy" "asg_policy" {
  name = "finops-scheduler-asg-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ManageAutoScalingGroups"
      Effect = "Allow"
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:SuspendProcesses",
        "autoscaling:ResumeProcesses"
      ]
      Resource = "arn:aws:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/eks-${var.cluster_name}-regular-*"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/Environment" = var.environment
        }
      }
    }]
  })
}

# Policy: RDS
resource "aws_iam_role_policy" "rds_policy" {
  name = "finops-scheduler-rds-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ManageRDS"
      Effect = "Allow"
      Action = [
        "rds:DescribeDBInstances",
        "rds:StopDBInstance",
        "rds:StartDBInstance"
      ]
      Resource = "arn:aws:rds:*:*:db:${var.rds_instance_id}"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/Environment" = var.environment
        }
      }
    }]
  })
}

# Policy: EKS (health checks)
resource "aws_iam_role_policy" "eks_policy" {
  name = "finops-scheduler-eks-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "HealthChecks"
      Effect = "Allow"
      Action = [
        "eks:DescribeCluster",
        "eks:ListNodegroups"
      ]
      Resource = "arn:aws:eks:*:*:cluster/${var.cluster_name}"
    }]
  })
}

# Policy: DynamoDB (circuit breaker)
resource "aws_iam_role_policy" "dynamodb_policy" {
  name = "finops-scheduler-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CircuitBreakerState"
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ]
      Resource = aws_dynamodb_table.scheduler_state.arn
    }]
  })
}

# Policy: CloudWatch Metrics
resource "aws_iam_role_policy" "cloudwatch_policy" {
  name = "finops-scheduler-cloudwatch-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "Observability"
      Effect = "Allow"
      Action = [
        "cloudwatch:PutMetricData",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}
```

### 4.5 dynamodb.tf (Circuit Breaker State)

```hcl
# terraform/modules/finops-scheduler/dynamodb.tf

resource "aws_dynamodb_table" "scheduler_state" {
  name           = "finops-scheduler-state-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"  # On-demand
  hash_key       = "environment"

  attribute {
    name = "environment"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = merge(var.tags, {
    Name = "finops-scheduler-state-${var.environment}"
  })
}

# Initialize state table
resource "aws_dynamodb_table_item" "initial_state" {
  table_name = aws_dynamodb_table.scheduler_state.name
  hash_key   = aws_dynamodb_table.scheduler_state.hash_key

  item = jsonencode({
    environment = {
      S = var.environment
    }
    startup_failures = {
      N = "0"
    }
    shutdown_failures = {
      N = "0"
    }
    circuit_breaker_state = {
      S = "CLOSED"
    }
    last_startup = {
      S = "never"
    }
    last_shutdown = {
      S = "never"
    }
    holidays_cache = {
      M = {}
    }
    ttl = {
      N = tostring(timeadd(timestamp(), "30d"))
    }
  })
}
```

### 4.6 outputs.tf

```hcl
# terraform/modules/finops-scheduler/outputs.tf

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.finops_scheduler.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.finops_scheduler.function_name
}

output "eventbridge_rule_startup_arn" {
  description = "ARN of the EventBridge startup rule"
  value       = aws_cloudwatch_event_rule.startup.arn
}

output "eventbridge_rule_shutdown_arn" {
  description = "ARN of the EventBridge shutdown rule"
  value       = aws_cloudwatch_event_rule.shutdown.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB state table"
  value       = aws_dynamodb_table.scheduler_state.name
}

output "iam_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.arn
}
```

---

## 5. Lambda Function

### 5.1 lambda_function.py (Handler Principal)

```python
# terraform/modules/finops-scheduler/lambda/lambda_function.py

import json
import boto3
import requests
import os
import time
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# AWS Clients
autoscaling = boto3.client('autoscaling')
rds = boto3.client('rds')
eks = boto3.client('eks')
dynamodb = boto3.client('dynamodb')
cloudwatch = boto3.client('cloudwatch')

# Environment variables
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'staging')
CLUSTER_NAME = os.environ.get('CLUSTER_NAME')
RDS_INSTANCE_ID = os.environ.get('RDS_INSTANCE_ID')
ASG_NAMES = os.environ.get('ASG_NAMES', '').split(',')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE')
BRASIL_API_URL = os.environ.get('BRASIL_API_URL')

def lambda_handler(event, context):
    """
    Main Lambda handler for FinOps scheduler

    Args:
        event: EventBridge event with 'action' (start|stop) and 'environment'
        context: Lambda context

    Returns:
        dict: Response with status and details
    """
    try:
        action = event.get('action')  # "start" or "stop"
        environment = event.get('environment', ENVIRONMENT)

        logger.info(f"FinOps Scheduler triggered: action={action}, environment={environment}")

        start_time = time.time()

        # 1. Check if it's a Brazilian holiday
        if is_brazilian_holiday():
            logger.info("Brazilian holiday detected - skipping action")
            return success_response("Skipped (holiday)", action, 0)

        # 2. Execute action
        if action == "start":
            result = start_environment(environment)
        elif action == "stop":
            result = stop_environment(environment)
        else:
            raise ValueError(f"Invalid action: {action}")

        duration = time.time() - start_time

        # 3. Update circuit breaker
        update_circuit_breaker(action, success=result['success'], duration=duration)

        # 4. Send CloudWatch metrics
        put_metrics(action, duration, result['success'])

        return result

    except Exception as e:
        logger.error(f"Lambda handler error: {str(e)}", exc_info=True)
        update_circuit_breaker(action, success=False, duration=time.time() - start_time)
        return error_response(str(e), action)

def is_brazilian_holiday() -> bool:
    """
    Check if today is a Brazilian national holiday

    Returns:
        bool: True if today is a holiday
    """
    try:
        today = datetime.now().strftime("%Y-%m-%d")
        year = datetime.now().year

        # 1. Try BrasilAPI
        url = f"{BRASIL_API_URL}/{year}"
        response = requests.get(url, timeout=5)

        if response.status_code == 200:
            holidays = response.json()
            holiday_dates = [h['date'] for h in holidays]

            # Cache in DynamoDB (30 days TTL)
            cache_holidays(year, holiday_dates)

            return today in holiday_dates

        # 2. Fallback: DynamoDB cache
        cached_holidays = get_cached_holidays(year)
        if cached_holidays:
            logger.warning("BrasilAPI unavailable - using cached holidays")
            return today in cached_holidays

        # 3. Fallback: Static holidays (fixed dates only)
        static_holidays = get_static_holidays(year)
        logger.warning("BrasilAPI and cache unavailable - using static holidays")
        return today in static_holidays

    except Exception as e:
        logger.error(f"Holiday check error: {str(e)}", exc_info=True)
        # On error, assume NOT a holiday (fail-open)
        return False

def start_environment(environment: str) -> Dict:
    """
    Start the staging environment

    Steps:
        1. Start RDS (with retry)
        2. Scale up ASG
        3. Wait for nodes Ready
        4. Health checks

    Returns:
        dict: Result with success status and details
    """
    logger.info(f"Starting environment: {environment}")
    results = {}

    try:
        # 1. Start RDS
        logger.info(f"Starting RDS instance: {RDS_INSTANCE_ID}")
        start_rds_with_retry(RDS_INSTANCE_ID, max_retries=3)
        results['rds'] = 'started'

        # 2. Scale up ASG
        logger.info(f"Scaling up ASGs: {ASG_NAMES}")
        scale_asg(ASG_NAMES, desired_capacity=2, min_size=2, max_size=4)
        results['asg'] = 'scaled_up'

        # 3. Wait for nodes Ready (timeout 5 min)
        logger.info("Waiting for nodes to be Ready...")
        wait_for_nodes_ready(timeout=300)
        results['nodes'] = 'ready'

        # 4. Health checks (optional, non-blocking)
        try:
            health_status = run_health_checks()
            results['health_checks'] = health_status
        except Exception as e:
            logger.warning(f"Health checks failed (non-blocking): {str(e)}")
            results['health_checks'] = 'warning'

        logger.info(f"Environment started successfully: {json.dumps(results)}")
        return success_response("Started", "start", results)

    except Exception as e:
        logger.error(f"Start environment error: {str(e)}", exc_info=True)
        return error_response(f"Start failed: {str(e)}", "start", results)

def stop_environment(environment: str) -> Dict:
    """
    Stop the staging environment

    Steps:
        1. Health checks (block if jobs active)
        2. Scale down ASG
        3. Stop RDS

    Returns:
        dict: Result with success status and details
    """
    logger.info(f"Stopping environment: {environment}")
    results = {}

    try:
        # 1. Health checks (block shutdown if jobs active)
        logger.info("Checking for active GitLab jobs...")
        if has_active_gitlab_jobs():
            logger.warning("Active GitLab jobs detected - postponing shutdown")
            return skip_response("Active jobs detected", "stop")
        results['health_checks'] = 'passed'

        # 2. Grace period (5 min warning)
        logger.info("Grace period: 5 minutes before shutdown")
        # Note: In production, send Slack notification here
        time.sleep(300)  # 5 min
        results['grace_period'] = 'completed'

        # 3. Scale down ASG
        logger.info(f"Scaling down ASGs: {ASG_NAMES}")
        scale_asg(ASG_NAMES, desired_capacity=0, min_size=0, max_size=4)
        results['asg'] = 'scaled_down'

        # 4. Stop RDS
        logger.info(f"Stopping RDS instance: {RDS_INSTANCE_ID}")
        stop_rds(RDS_INSTANCE_ID)
        results['rds'] = 'stopped'

        logger.info(f"Environment stopped successfully: {json.dumps(results)}")
        return success_response("Stopped", "stop", results)

    except Exception as e:
        logger.error(f"Stop environment error: {str(e)}", exc_info=True)
        return error_response(f"Stop failed: {str(e)}", "stop", results)

# ... (continues with helper functions)
```

**(Continuação do lambda_function.py em requirements.txt e config.yaml)**

### 5.2 requirements.txt

```txt
# terraform/modules/finops-scheduler/lambda/requirements.txt

boto3==1.34.0
requests==2.31.0
```

### 5.3 config.yaml

```yaml
# terraform/modules/finops-scheduler/lambda/config.yaml

# Node Groups Configuration
node_groups:
  critical:
    name: "critical-always-on"
    workloads:
      - "gitlab"
      - "harbor"
      - "argocd"
      - "prometheus"
      - "grafana"
    instances: 1
    instance_type: "t3.medium"
    behavior: "always-on"  # NEVER shutdown

  regular:
    name: "regular"
    workloads:
      - "keycloak"
      - "sonarqube"
      - "kong"
      - "redis-operator"
      - "rabbitmq-operator"
    instances: 2
    instance_type: "t3.medium"
    behavior: "scheduled"  # Start/stop automation

# Health Checks Configuration
health_checks:
  gitlab:
    enabled: true
    api_url: "http://gitlab.k8s-platform.seudominio.com.br/api/v4"
    endpoint: "/jobs?scope[]=running"
    timeout: 10
    block_shutdown_if_active: true

  argocd:
    enabled: false  # Optional
    api_url: "http://argocd.k8s-platform.seudominio.com.br/api/v1"
    endpoint: "/applications"
    timeout: 10
    block_shutdown_if_syncing: false

# Circuit Breaker Configuration
circuit_breaker:
  failure_threshold: 3
  reset_after_hours: 24
  alert_on_open: true

# Feriados Configuration
feriados:
  api_url: "https://brasilapi.com.br/api/feriados/v1"
  cache_ttl_days: 30
  fallback_static:
    - "01-01"  # Ano Novo
    - "04-21"  # Tiradentes
    - "05-01"  # Dia do Trabalho
    - "09-07"  # Independência
    - "10-12"  # Nossa Senhora Aparecida
    - "11-02"  # Finados
    - "11-15"  # Proclamação da República
    - "12-25"  # Natal
```

---

## 6. EventBridge Scheduler

### 6.1 Deploy Terraform Module

```bash
cd terraform/modules/finops-scheduler

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan (dry-run)
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

### 6.2 Verificar Deploy

```bash
# Lambda function
aws lambda get-function --function-name finops-scheduler-staging

# EventBridge rules
aws events list-rules --name-prefix finops

# Test invocation (manual)
aws lambda invoke \
  --function-name finops-scheduler-staging \
  --payload '{"action":"start","environment":"staging"}' \
  response.json

cat response.json
```

---

## 7. Testes e Validação

### 7.1 Teste Manual Shutdown

```bash
# 1. Invoke Lambda
aws lambda invoke \
  --function-name finops-scheduler-staging \
  --payload '{"action":"stop","environment":"staging"}' \
  response.json

# 2. Verificar logs
aws logs tail /aws/lambda/finops-scheduler-staging --follow

# 3. Validar estado
kubectl get nodes -l node-type=regular
# Esperado: 0 nodes

aws rds describe-db-instances --db-instance-identifier marco2-staging-rds \
  --query 'DBInstances[0].DBInstanceStatus'
# Esperado: "stopped" ou "stopping"

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names eks-marco2-staging-regular-* \
  --query 'AutoScalingGroups[0].DesiredCapacity'
# Esperado: 0
```

### 7.2 Teste Manual Startup

```bash
# 1. Invoke Lambda
aws lambda invoke \
  --function-name finops-scheduler-staging \
  --payload '{"action":"start","environment":"staging"}' \
  response.json

# 2. Aguardar 10 minutos
sleep 600

# 3. Validar estado
kubectl get nodes -l node-type=regular
# Esperado: 2 nodes Ready

aws rds describe-db-instances --db-instance-identifier marco2-staging-rds \
  --query 'DBInstances[0].DBInstanceStatus'
# Esperado: "available"

kubectl get pods -n platform-core-staging
# Esperado: Todos Running
```

### 7.3 Teste de Feriado (Mock)

```bash
# Atualizar Lambda environment variable
aws lambda update-function-configuration \
  --function-name finops-scheduler-staging \
  --environment Variables={BRASIL_API_MOCK=true,BRASIL_API_MOCK_HOLIDAY=true}

# Invocar Lambda
aws lambda invoke \
  --function-name finops-scheduler-staging \
  --payload '{"action":"stop","environment":"staging"}' \
  response.json

# Verificar resposta
cat response.json
# Esperado: {"status": "skipped", "reason": "Brazilian holiday"}
```

### 7.4 Teste Circuit Breaker

```bash
# Simular 3 falhas consecutivas
for i in {1..3}; do
  # Provocar erro (ex: RDS instance ID inválido)
  aws lambda update-function-configuration \
    --function-name finops-scheduler-staging \
    --environment Variables={RDS_INSTANCE_ID=invalid-id}

  aws lambda invoke \
    --function-name finops-scheduler-staging \
    --payload '{"action":"start","environment":"staging"}' \
    response.json

  sleep 10
done

# Verificar DynamoDB state
aws dynamodb get-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment": {"S": "staging"}}' \
  --query 'Item.{failures:startup_failures.N,state:circuit_breaker_state.S}'

# Esperado: failures=3, state="OPEN"

# Verificar EventBridge rule disabled
aws events describe-rule --name finops-startup-staging \
  --query 'State'
# Esperado: "DISABLED"
```

---

## 8. Monitoramento

### 8.1 CloudWatch Metrics

```bash
# Verificar métricas
aws cloudwatch list-metrics --namespace FinOps/Scheduler

# Métricas disponíveis:
# - finops.startup.duration (seconds)
# - finops.shutdown.duration (seconds)
# - finops.startup.success (1/0)
# - finops.shutdown.success (1/0)
# - finops.cost_savings_daily (USD)
# - finops.circuit_breaker_state (0=closed, 1=open)
```

### 8.2 CloudWatch Dashboard

```bash
# Criar dashboard via CLI
aws cloudwatch put-dashboard --dashboard-name FinOps-Staging-Automation \
  --dashboard-body file://dashboard.json
```

**dashboard.json:**

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "title": "Startup Duration (Last 30 Days)",
        "metrics": [
          ["FinOps/Scheduler", "startup.duration", {"stat": "Average"}]
        ],
        "period": 86400,
        "stat": "Average",
        "region": "us-east-1",
        "yAxis": {
          "left": {"label": "Seconds"}
        }
      }
    },
    {
      "type": "metric",
      "properties": {
        "title": "Cost Savings Accumulated",
        "metrics": [
          ["FinOps/Scheduler", "cost_savings_daily", {"stat": "Sum"}]
        ],
        "period": 2592000,
        "stat": "Sum",
        "region": "us-east-1",
        "yAxis": {
          "left": {"label": "USD"}
        }
      }
    }
  ]
}
```

### 8.3 CloudWatch Alarms

```bash
# Alarm: Startup Duration > 15 min
aws cloudwatch put-metric-alarm \
  --alarm-name finops-startup-duration-warning \
  --alarm-description "Startup taking > 15 min" \
  --metric-name startup.duration \
  --namespace FinOps/Scheduler \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 900 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching

# Alarm: 3 Startup Failures Consecutive
aws cloudwatch put-metric-alarm \
  --alarm-name finops-circuit-breaker-open \
  --alarm-description "Circuit breaker activated (3 failures)" \
  --metric-name circuit_breaker_state \
  --namespace FinOps/Scheduler \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 0.5 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:finops-alerts
```

---

## 9. Troubleshooting

### 9.1 Startup Falhou

**Diagnóstico:**

```bash
# 1. Ver logs Lambda
aws logs tail /aws/lambda/finops-scheduler-staging --follow --since 1h

# 2. Verificar RDS status
aws rds describe-db-instances --db-instance-identifier marco2-staging-rds

# 3. Verificar ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names eks-marco2-staging-regular-*

# 4. Verificar nodes Kubernetes
kubectl get nodes -l node-type=regular
```

**Recovery Manual:**

```bash
cd scripts/finops
./startup-marco2.sh staging

# OU comandos AWS diretos
aws rds start-db-instance --db-instance-identifier marco2-staging-rds
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name eks-marco2-staging-regular-xxx \
  --desired-capacity 2
```

### 9.2 Circuit Breaker Ativado

**Reset:**

```bash
# 1. Investigar causa raiz
aws logs tail /aws/lambda/finops-scheduler-staging --since 24h | grep ERROR

# 2. Resetar DynamoDB state
aws dynamodb update-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment": {"S": "staging"}}' \
  --update-expression "SET startup_failures = :zero, circuit_breaker_state = :closed" \
  --expression-attribute-values '{":zero": {"N": "0"}, ":closed": {"S": "CLOSED"}}'

# 3. Reabilitar EventBridge rule
aws events enable-rule --name finops-startup-staging
aws events enable-rule --name finops-shutdown-staging
```

### 9.3 BrasilAPI Indisponível

**Verificar Cache:**

```bash
# Ver cache DynamoDB
aws dynamodb get-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment": {"S": "staging"}}' \
  --query 'Item.holidays_cache'
```

**Atualizar Manualmente:**

```bash
# Atualizar lista estática no Lambda
aws lambda update-function-configuration \
  --function-name finops-scheduler-staging \
  --environment Variables={...,STATIC_HOLIDAYS="2026-01-01,2026-04-21,..."}
```

---

## 10. Checklist de Conclusão

### 10.1 Deploy

- [ ] Terraform module criado e validado
- [ ] Lambda function deployed
- [ ] EventBridge rules configuradas (DISABLED inicialmente)
- [ ] IAM roles e policies aplicadas
- [ ] DynamoDB table criada
- [ ] CloudWatch dashboard criado
- [ ] Alarms configurados

### 10.2 Testes

- [ ] Teste manual shutdown executado com sucesso
- [ ] Teste manual startup executado com sucesso
- [ ] Teste feriado (mock) validado
- [ ] Teste circuit breaker validado
- [ ] Health checks GitLab testados

### 10.3 Monitoramento

- [ ] CloudWatch Logs funcionando
- [ ] CloudWatch Metrics enviadas corretamente
- [ ] Dashboard FinOps criado
- [ ] Alarms configurados e testados
- [ ] Slack notifications (opcional) configuradas

### 10.4 Documentação

- [ ] Runbooks criados (startup-failed, circuit-breaker-reset)
- [ ] Documentação atualizada (architecture.md, costs.md, risks.md)
- [ ] ADR-024 aprovado
- [ ] Demanda fechada com validação economia real

### 10.5 Produção

- [ ] Stakeholders aprovaram deploy
- [ ] EventBridge rules HABILITADAS
- [ ] Monitoramento 1ª semana (observação intensiva)
- [ ] Economia observada ≥ R$ 350/mês (threshold viabilidade)
- [ ] Retrospectiva realizada (lessons learned)

---

## Referências

- [ADR-024: FinOps Automation STAGING](../../context/decisions.md#adr-024)
- [Demanda](../../demands/2026-01-30-automacao-finops-staging.md)
- [Architecture](../../context/architecture.md#fase-9-finops-automation-staging-environment)
- [Costs Analysis](../../context/costs.md#automacao-finops-staging-planejada---adr-024)
- [Risks](../../context/risks.md#r-019-riscos-automação-finops-staging-eventbridge-lambda)
- [Scripts Existentes](../../../scripts/finops/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS EventBridge Scheduler](https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html)
- [BrasilAPI Feriados](https://brasilapi.com.br/docs#tag/Feriados-Nacionais)

---

**Autor:** DevOps Team
**Data:** 2026-01-30
**Versão:** 1.0
**Status:** 📝 PLANEJADO → Aguardando aprovação stakeholders
