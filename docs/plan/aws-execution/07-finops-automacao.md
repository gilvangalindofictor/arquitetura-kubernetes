# 07 - FinOps e Automação

> **Otimização de Custos e Automação Operacional**
> **Pré-requisitos**: Docs 01-06 concluídos

---

## Índice

1. [Visão Geral](#1-visão-geral)
2. [Cost Allocation Tags](#2-cost-allocation-tags)
3. [AWS Budgets](#3-aws-budgets)
4. [Cost Explorer e Análise](#4-cost-explorer-e-análise)
5. [Start/Stop Automation](#5-startstop-automation)
6. [Right-Sizing](#6-right-sizing)
7. [Reserved Instances e Savings Plans](#7-reserved-instances-e-savings-plans)
8. [Otimizações Específicas](#8-otimizações-específicas)
9. [Dashboard FinOps](#9-dashboard-finops)
10. [Checklist de Conclusão](#10-checklist-de-conclusão)

---

## 1. Visão Geral

### 1.1 Estratégia FinOps

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         FINOPS FRAMEWORK                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│     INFORM              OPTIMIZE              OPERATE                    │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐               │
│  │ Visibility  │ ──▶ │ Right-Size  │ ──▶ │ Automate   │               │
│  │ - Tagging   │     │ - Instances │     │ - Start/   │               │
│  │ - Budgets   │     │ - Storage   │     │   Stop     │               │
│  │ - Alerts    │     │ - Reserved  │     │ - Scaling  │               │
│  └─────────────┘     └─────────────┘     └─────────────┘               │
│         │                   │                   │                       │
│         ▼                   ▼                   ▼                       │
│  ┌─────────────────────────────────────────────────────────┐           │
│  │                  CONTINUOUS IMPROVEMENT                  │           │
│  │         Monthly Review → Adjust → Implement              │           │
│  └─────────────────────────────────────────────────────────┘           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Estimativa de Custos Base

| Recurso | Tipo | Qtd | Custo Mensal (USD) |
|---------|------|-----|-------------------|
| **EKS Cluster** | Control Plane | 1 | $73 |
| **EC2 - System** | t3.medium | 2 | $60 |
| **EC2 - Workloads** | t3.large | 3 | $180 |
| **EC2 - Critical** | t3.xlarge | 2 | $240 |
| **RDS PostgreSQL** | db.t3.medium Multi-AZ | 1 | $140 |
| **EBS Volumes** | gp3 ~500GB | - | $50 |
| **S3** | ~100GB | - | $5 |
| **NAT Gateway** | 2 AZs | 2 | $90 |
| **ALB** | 1 | 1 | $25 |
| **Data Transfer** | ~500GB | - | $45 |
| **Outros** | CloudWatch, etc | - | $30 |
| **TOTAL** | | | **~$938/mês** |

### 1.3 Metas de Otimização

| Meta | Target | Economia Estimada |
|------|--------|-------------------|
| Start/Stop Dev (12h/dia) | 50% compute | ~$200/mês |
| Reserved Instances (1yr) | 30% desconto | ~$150/mês |
| Right-sizing | 20% oversized | ~$50/mês |
| S3 Lifecycle | Glacier após 90d | ~$3/mês |
| **Total Potencial** | | **~$400/mês (43%)** |

---

## 2. Cost Allocation Tags

### 2.1 Estratégia de Tagging

```
TAG HIERARCHY
=============

Required Tags (Obrigatórias):
├── Environment: dev | homolog | production
├── Project: k8s-platform
├── Owner: devops-team
├── CostCenter: infrastructure
└── ManagedBy: terraform | manual | helm

Optional Tags (Recomendadas):
├── Application: gitlab | redis | rabbitmq | monitoring
├── Component: webservice | sidekiq | runner | collector
├── Tier: frontend | backend | data | observability
└── Schedule: office-hours | always-on | weekdays
```

### 2.2 Ativar Cost Allocation Tags

**Console AWS** → **Billing** → **Cost allocation tags**

1. **AWS-generated tags**: Ativar
   - `aws:createdBy`
   - `aws:cloudformation:stack-name`

2. **User-defined tags**: Ativar
   - `Environment`
   - `Project`
   - `Owner`
   - `CostCenter`
   - `Application`
   - `Schedule`

### 2.3 Aplicar Tags nos Recursos

#### EC2 / Node Groups

**Console AWS** → **EC2** → **Instances** → Selecionar → **Tags** → **Manage tags**

```
Key                 Value
---                 -----
Environment         production
Project             k8s-platform
Owner               devops-team
CostCenter          infrastructure
Application         eks-node
Schedule            always-on
```

#### RDS

**Console AWS** → **RDS** → **Databases** → Selecionar → **Tags** → **Add tags**

```
Key                 Value
---                 -----
Environment         production
Project             k8s-platform
Owner               devops-team
CostCenter          infrastructure
Application         gitlab-db
Schedule            always-on
```

#### EKS Cluster

```bash
aws eks tag-resource \
  --resource-arn arn:aws:eks:us-east-1:ACCOUNT_ID:cluster/k8s-platform-cluster \
  --tags Environment=production,Project=k8s-platform,Owner=devops-team,CostCenter=infrastructure
```

#### S3 Buckets

```bash
for BUCKET in k8s-platform-gitlab-backups k8s-platform-loki-logs k8s-platform-tempo-traces k8s-platform-velero-backups; do
  aws s3api put-bucket-tagging \
    --bucket $BUCKET \
    --tagging 'TagSet=[{Key=Environment,Value=production},{Key=Project,Value=k8s-platform},{Key=Owner,Value=devops-team},{Key=CostCenter,Value=infrastructure}]'
done
```

### 2.4 Tag Policy (AWS Organizations)

Se usando AWS Organizations, criar Tag Policy:

```json
{
  "tags": {
    "Environment": {
      "tag_key": {
        "@@assign": "Environment"
      },
      "tag_value": {
        "@@assign": ["dev", "homolog", "production"]
      },
      "enforced_for": {
        "@@assign": ["ec2:instance", "rds:db", "s3:bucket"]
      }
    },
    "Project": {
      "tag_key": {
        "@@assign": "Project"
      },
      "enforced_for": {
        "@@assign": ["ec2:instance", "rds:db"]
      }
    }
  }
}
```

---

## 3. AWS Budgets

### 3.1 Criar Budget Mensal

**Console AWS** → **Billing** → **Budgets** → **Create budget**

#### Budget 1: Total Mensal

1. **Budget type**: Cost budget
2. **Name**: `k8s-platform-monthly`
3. **Period**: Monthly
4. **Budget amount**: Fixed - $1,000
5. **Scope**: All services (filter by tag depois)

**Alerts:**
- Alert 1: 50% actual ($500) → Email devops-team
- Alert 2: 80% actual ($800) → Email devops-team + SNS
- Alert 3: 100% forecasted → Email devops-team + manager

#### Budget 2: Por Serviço (EKS/EC2)

1. **Name**: `k8s-platform-compute`
2. **Budget amount**: $600
3. **Filters**:
   - Service: Amazon Elastic Compute Cloud - Compute
   - Service: Amazon Elastic Kubernetes Service
4. **Alerts**: 80% actual

#### Budget 3: Data Transfer

1. **Name**: `k8s-platform-data-transfer`
2. **Budget amount**: $100
3. **Filters**:
   - Usage Type Group: Data Transfer
4. **Alerts**: 80% actual (data transfer pode explodir)

### 3.2 Budget via CLI

```bash
cat > budget.json << 'EOF'
{
  "BudgetName": "k8s-platform-monthly",
  "BudgetLimit": {
    "Amount": "1000",
    "Unit": "USD"
  },
  "BudgetType": "COST",
  "TimeUnit": "MONTHLY",
  "CostFilters": {
    "TagKeyValue": [
      "user:Project$k8s-platform"
    ]
  }
}
EOF

aws budgets create-budget \
  --account-id ACCOUNT_ID \
  --budget file://budget.json \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {
          "SubscriptionType": "EMAIL",
          "Address": "devops-team@empresa.com"
        }
      ]
    }
  ]'
```

### 3.3 Budget Actions (Auto-remediation)

**Console AWS** → **Budgets** → Selecionar budget → **Budget actions** → **Create action**

1. **Action type**: Apply IAM policy
2. **Action threshold**: 100% of budgeted amount
3. **IAM policy**: Criar policy que nega criação de recursos

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": [
        "ec2:RunInstances",
        "rds:CreateDBInstance"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Project": "k8s-platform"
        }
      }
    }
  ]
}
```

---

## 4. Cost Explorer e Análise

### 4.1 Habilitar Cost Explorer

**Console AWS** → **Billing** → **Cost Explorer** → **Enable Cost Explorer**

(Pode levar 24h para dados aparecerem)

### 4.2 Criar Relatórios Customizados

#### Relatório 1: Custo por Serviço

1. **Date range**: Last 3 months
2. **Granularity**: Monthly
3. **Group by**: Service
4. **Filters**: Tag: Project = k8s-platform

#### Relatório 2: Custo por Ambiente

1. **Group by**: Tag: Environment
2. **Filters**: Tag: Project = k8s-platform

#### Relatório 3: Trend de Compute

1. **Group by**: Usage Type
2. **Filters**: Service = EC2

### 4.3 Salvar Relatórios

**Console AWS** → **Cost Explorer** → **Save as report**

Relatórios recomendados:
- `k8s-platform-monthly-overview`
- `k8s-platform-daily-compute`
- `k8s-platform-cost-by-env`

### 4.4 Cost Anomaly Detection

**Console AWS** → **Cost Management** → **Cost Anomaly Detection** → **Create monitor**

1. **Name**: `k8s-platform-anomaly`
2. **Monitor type**: AWS Services
3. **Alert subscription**:
   - Threshold: $50 impact
   - Email: devops-team@empresa.com

---

## 5. Start/Stop Automation

### 5.1 Arquitetura da Automação

```
┌─────────────────────────────────────────────────────────────────────┐
│                    START/STOP AUTOMATION                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐        ┌─────────────┐        ┌─────────────┐     │
│  │ EventBridge │   ──▶  │   Lambda    │   ──▶  │  EKS/ASG    │     │
│  │   (Cron)    │        │  Function   │        │   Nodes     │     │
│  └─────────────┘        └─────────────┘        └─────────────┘     │
│                                                                      │
│  Schedule:                                                           │
│  ├─ START: Mon-Fri 08:00 BRT                                        │
│  └─ STOP:  Mon-Fri 20:00 BRT                                        │
│                                                                      │
│  Resources:                                                          │
│  ├─ EKS Node Groups (Schedule=office-hours)                         │
│  └─ RDS (se dev/homolog)                                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.2 Lambda Function - Stop Nodes

**Console AWS** → **Lambda** → **Create function**

1. **Function name**: `k8s-stop-dev-nodes`
2. **Runtime**: Python 3.11
3. **Architecture**: arm64
4. **Permissions**: Create new role

**Código da função:**

```python
import boto3
import os

def lambda_handler(event, context):
    """
    Para os node groups marcados com Schedule=office-hours
    """
    eks = boto3.client('eks')
    cluster_name = os.environ.get('CLUSTER_NAME', 'k8s-platform-cluster')

    # Listar node groups
    nodegroups = eks.list_nodegroups(clusterName=cluster_name)['nodegroups']

    stopped = []
    for ng in nodegroups:
        # Obter tags
        ng_info = eks.describe_nodegroup(
            clusterName=cluster_name,
            nodegroupName=ng
        )['nodegroup']

        tags = ng_info.get('tags', {})

        # Verificar se deve ser parado
        if tags.get('Schedule') == 'office-hours':
            # Scale to 0
            eks.update_nodegroup_config(
                clusterName=cluster_name,
                nodegroupName=ng,
                scalingConfig={
                    'minSize': 0,
                    'desiredSize': 0,
                    'maxSize': ng_info['scalingConfig']['maxSize']
                }
            )
            stopped.append(ng)
            print(f"Stopped nodegroup: {ng}")

    return {
        'statusCode': 200,
        'body': f"Stopped nodegroups: {stopped}"
    }
```

**Environment Variables:**
- `CLUSTER_NAME`: `k8s-platform-cluster`

**IAM Policy para Lambda:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:ListNodegroups",
        "eks:DescribeNodegroup",
        "eks:UpdateNodegroupConfig"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

### 5.3 Lambda Function - Start Nodes

```python
import boto3
import os

def lambda_handler(event, context):
    """
    Inicia os node groups marcados com Schedule=office-hours
    """
    eks = boto3.client('eks')
    cluster_name = os.environ.get('CLUSTER_NAME', 'k8s-platform-cluster')

    # Configurações originais (poderia vir de Parameter Store)
    original_config = {
        'system-ng': {'min': 2, 'desired': 2, 'max': 4},
        'workloads-ng': {'min': 2, 'desired': 3, 'max': 6},
        'critical-ng': {'min': 1, 'desired': 2, 'max': 4}
    }

    nodegroups = eks.list_nodegroups(clusterName=cluster_name)['nodegroups']

    started = []
    for ng in nodegroups:
        ng_info = eks.describe_nodegroup(
            clusterName=cluster_name,
            nodegroupName=ng
        )['nodegroup']

        tags = ng_info.get('tags', {})

        if tags.get('Schedule') == 'office-hours':
            config = original_config.get(ng, {'min': 1, 'desired': 2, 'max': 4})

            eks.update_nodegroup_config(
                clusterName=cluster_name,
                nodegroupName=ng,
                scalingConfig={
                    'minSize': config['min'],
                    'desiredSize': config['desired'],
                    'maxSize': config['max']
                }
            )
            started.append(ng)
            print(f"Started nodegroup: {ng}")

    return {
        'statusCode': 200,
        'body': f"Started nodegroups: {started}"
    }
```

### 5.4 EventBridge Rules

**Console AWS** → **EventBridge** → **Rules** → **Create rule**

#### Rule 1: Stop Nodes

1. **Name**: `k8s-stop-dev-evening`
2. **Schedule**: Cron expression
   - `cron(0 23 ? * MON-FRI *)` (20:00 BRT = 23:00 UTC)
3. **Target**: Lambda function `k8s-stop-dev-nodes`

#### Rule 2: Start Nodes

1. **Name**: `k8s-start-dev-morning`
2. **Schedule**: Cron expression
   - `cron(0 11 ? * MON-FRI *)` (08:00 BRT = 11:00 UTC)
3. **Target**: Lambda function `k8s-start-dev-nodes`

### 5.5 Parar RDS em Dev/Homolog

**Nota**: RDS pode ser parado por até 7 dias. Após isso, reinicia automaticamente.

```python
import boto3

def stop_dev_rds(event, context):
    rds = boto3.client('rds')

    # Listar DBs com tag Schedule=office-hours
    dbs = rds.describe_db_instances()['DBInstances']

    for db in dbs:
        # Obter tags
        arn = db['DBInstanceArn']
        tags = rds.list_tags_for_resource(ResourceName=arn)['TagList']
        tags_dict = {t['Key']: t['Value'] for t in tags}

        if tags_dict.get('Schedule') == 'office-hours' and db['DBInstanceStatus'] == 'available':
            rds.stop_db_instance(DBInstanceIdentifier=db['DBInstanceIdentifier'])
            print(f"Stopped RDS: {db['DBInstanceIdentifier']}")
```

### 5.6 Kubernetes CronJob para Scale Down

Alternativa usando kubectl dentro do cluster:

```yaml
# scale-down-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-down-workloads
  namespace: kube-system
spec:
  schedule: "0 23 * * 1-5"  # 20:00 BRT
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: cluster-autoscaler
          containers:
            - name: kubectl
              image: bitnami/kubectl:latest
              command:
                - /bin/bash
                - -c
                - |
                  # Scale down GitLab (manter mínimo)
                  kubectl scale deployment -n gitlab gitlab-webservice --replicas=1
                  kubectl scale deployment -n gitlab gitlab-sidekiq --replicas=1

                  # Scale down observability
                  kubectl scale deployment -n observability grafana --replicas=0

                  echo "Scale down completed"
          restartPolicy: OnFailure
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-up-workloads
  namespace: kube-system
spec:
  schedule: "0 11 * * 1-5"  # 08:00 BRT
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: cluster-autoscaler
          containers:
            - name: kubectl
              image: bitnami/kubectl:latest
              command:
                - /bin/bash
                - -c
                - |
                  # Scale up GitLab
                  kubectl scale deployment -n gitlab gitlab-webservice --replicas=2
                  kubectl scale deployment -n gitlab gitlab-sidekiq --replicas=2

                  # Scale up observability
                  kubectl scale deployment -n observability grafana --replicas=1

                  echo "Scale up completed"
          restartPolicy: OnFailure
```

---

## 6. Right-Sizing

### 6.1 AWS Compute Optimizer

**Console AWS** → **Compute Optimizer** → **Opt in** (se ainda não ativado)

Após 24-48h, verificar recomendações:

1. **EC2 instances**: Verificar se estão oversized
2. **EBS volumes**: Verificar tipo (gp2 → gp3) e tamanho
3. **Lambda functions**: Memory optimization

### 6.2 Análise de Utilização

```bash
# CloudWatch - CPU média dos últimos 7 dias
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=eks-system-ng-xxxxx \
  --start-time $(date -d '7 days ago' --iso-8601=seconds) \
  --end-time $(date --iso-8601=seconds) \
  --period 3600 \
  --statistics Average \
  --query 'Datapoints[*].[Timestamp,Average]' \
  --output table
```

### 6.3 Recomendações por Componente

| Componente | Atual | Recomendado | Economia |
|------------|-------|-------------|----------|
| System nodes | t3.medium (2) | Manter | - |
| Workload nodes | t3.large (3) | t3.medium se <40% CPU | ~$60/mês |
| Critical nodes | t3.xlarge (2) | t3.large se <50% CPU | ~$80/mês |
| RDS | db.t3.medium | Manter (não fazer downgrade) | - |
| EBS gp2 | gp2 | gp3 | ~$10/mês |

### 6.4 Migrar EBS gp2 → gp3

```bash
# Listar volumes gp2
aws ec2 describe-volumes \
  --filters "Name=volume-type,Values=gp2" \
  --query 'Volumes[*].[VolumeId,Size,State]' \
  --output table

# Modificar para gp3 (sem downtime)
aws ec2 modify-volume \
  --volume-id vol-0123456789abcdef0 \
  --volume-type gp3 \
  --iops 3000 \
  --throughput 125

# Verificar status
aws ec2 describe-volumes-modifications \
  --volume-ids vol-0123456789abcdef0
```

---

## 7. Reserved Instances e Savings Plans

### 7.1 Análise de Uso para RI/SP

**Console AWS** → **Cost Explorer** → **Recommendations** → **Reserved Instance recommendations**

Ou:

**Console AWS** → **Cost Explorer** → **Savings Plans** → **Recommendations**

### 7.2 Recomendações para k8s-platform

| Tipo | Commitment | Desconto | Recomendação |
|------|------------|----------|--------------|
| **EC2 Savings Plan** | 1 ano | 30-40% | Sim, para compute estável |
| **Compute Savings Plan** | 1 ano | 20-30% | Sim, mais flexível |
| **RDS Reserved** | 1 ano | 30-40% | Sim, se produção estável |
| **EC2 Reserved** | 1 ano | 40-50% | Não recomendado (menos flexível) |

### 7.3 Comprar Savings Plan

**Console AWS** → **Cost Explorer** → **Savings Plans** → **Purchase Savings Plans**

1. **Savings Plan type**: Compute Savings Plans (mais flexível)
2. **Term**: 1 year
3. **Payment option**: No Upfront (ou Partial Upfront para mais desconto)
4. **Hourly commitment**: Baseado na recomendação (~$0.50/h para este cenário)

**Estimativa:**
- Commitment: $0.50/hora
- Mensal: ~$365
- Economia vs On-Demand: ~$150/mês (30%)

### 7.4 RDS Reserved Instance

**Console AWS** → **RDS** → **Reserved instances** → **Purchase reserved DB instance**

1. **DB instance class**: db.t3.medium
2. **Multi-AZ**: Yes
3. **Term**: 1 year
4. **Offering type**: No Upfront

---

## 8. Otimizações Específicas

### 8.1 S3 Lifecycle Policies

**Console AWS** → **S3** → Selecionar bucket → **Management** → **Create lifecycle rule**

#### Loki Logs Bucket

```json
{
  "Rules": [
    {
      "ID": "logs-lifecycle",
      "Status": "Enabled",
      "Filter": {},
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 365
      }
    }
  ]
}
```

#### Velero Backups Bucket

```json
{
  "Rules": [
    {
      "ID": "backup-lifecycle",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "backups/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 365
      }
    }
  ]
}
```

### 8.2 NAT Gateway Optimization

NAT Gateway é um dos maiores custos. Opções:

1. **Usar NAT Instance** (t3.micro): Economia de ~$60/mês, mas menos HA
2. **VPC Endpoints**: Reduz tráfego pelo NAT

#### Criar VPC Endpoints

```bash
# S3 Gateway Endpoint (gratuito)
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-0123456789abcdef0 \
  --service-name com.amazonaws.us-east-1.s3 \
  --route-table-ids rtb-private-1 rtb-private-2 rtb-private-3

# ECR DKR Interface Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-0123456789abcdef0 \
  --service-name com.amazonaws.us-east-1.ecr.dkr \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-private-1a subnet-private-1b subnet-private-1c \
  --security-group-ids sg-endpoints

# ECR API Interface Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-0123456789abcdef0 \
  --service-name com.amazonaws.us-east-1.ecr.api \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-private-1a subnet-private-1b subnet-private-1c \
  --security-group-ids sg-endpoints
```

### 8.3 CloudWatch Logs Optimization

```bash
# Definir retenção para 30 dias (padrão é forever)
aws logs put-retention-policy \
  --log-group-name /aws/eks/k8s-platform-cluster/cluster \
  --retention-in-days 30

# Listar todos os log groups sem retenção
aws logs describe-log-groups \
  --query 'logGroups[?retentionInDays==`null`].logGroupName' \
  --output text
```

### 8.4 Spot Instances para Workloads

Adicionar Spot ao node group de workloads:

**Console AWS** → **EKS** → **Clusters** → **Node groups** → **Create node group**

1. **Name**: `workloads-spot-ng`
2. **Capacity type**: Spot
3. **Instance types**: t3.large, t3a.large, m5.large (múltiplos para pool)
4. **Scaling**: min=0, desired=2, max=10

**Kubernetes labels para scheduling:**
```yaml
nodeSelector:
  node.kubernetes.io/capacity-type: spot  # Para workloads tolerantes
```

---

## 9. Dashboard FinOps

### 9.1 Grafana Dashboard - Cost Overview

```json
{
  "dashboard": {
    "title": "FinOps - Cost Overview",
    "panels": [
      {
        "title": "Daily Cost Trend",
        "type": "timeseries",
        "datasource": "CloudWatch",
        "targets": [
          {
            "namespace": "AWS/Billing",
            "metricName": "EstimatedCharges",
            "dimensions": {"Currency": "USD"},
            "period": "86400",
            "stat": "Maximum"
          }
        ]
      },
      {
        "title": "Cost by Service",
        "type": "piechart",
        "datasource": "CloudWatch",
        "targets": [
          {
            "namespace": "AWS/Billing",
            "metricName": "EstimatedCharges",
            "dimensions": {"ServiceName": "AmazonEC2"},
            "stat": "Maximum"
          },
          {
            "namespace": "AWS/Billing",
            "metricName": "EstimatedCharges",
            "dimensions": {"ServiceName": "AmazonRDS"},
            "stat": "Maximum"
          },
          {
            "namespace": "AWS/Billing",
            "metricName": "EstimatedCharges",
            "dimensions": {"ServiceName": "AmazonEKS"},
            "stat": "Maximum"
          }
        ]
      },
      {
        "title": "Budget Status",
        "type": "gauge",
        "targets": [
          {
            "expr": "(aws_billing_estimated_charges / 1000) * 100",
            "legendFormat": "% of $1000 budget"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "max": 100,
            "thresholds": {
              "steps": [
                {"color": "green", "value": 0},
                {"color": "yellow", "value": 70},
                {"color": "red", "value": 90}
              ]
            }
          }
        }
      },
      {
        "title": "Node Count by Type",
        "type": "stat",
        "targets": [
          {
            "expr": "count(kube_node_info) by (node)",
            "legendFormat": "Total Nodes"
          }
        ]
      },
      {
        "title": "Resource Utilization",
        "type": "table",
        "targets": [
          {
            "expr": "avg(container_cpu_usage_seconds_total) by (namespace)",
            "legendFormat": "CPU"
          },
          {
            "expr": "avg(container_memory_usage_bytes) by (namespace)",
            "legendFormat": "Memory"
          }
        ]
      }
    ]
  }
}
```

### 9.2 Alertas de Custo

```yaml
# prometheus-rules/cost-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: finops-alerts
  namespace: observability
spec:
  groups:
    - name: finops
      rules:
        - alert: HighNodeCount
          expr: count(kube_node_info) > 10
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "More than 10 nodes running"
            description: "Node count is {{ $value }}. Review if all nodes are necessary."

        - alert: UnderutilizedNodes
          expr: |
            avg by (node) (
              1 - (
                sum by (node) (rate(container_cpu_usage_seconds_total[5m]))
                /
                sum by (node) (kube_node_status_allocatable{resource="cpu"})
              )
            ) > 0.7
          for: 24h
          labels:
            severity: info
          annotations:
            summary: "Node {{ $labels.node }} is underutilized"
            description: "CPU usage is less than 30% for 24h. Consider right-sizing."

        - alert: HighPVCUsage
          expr: |
            kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.8
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "PVC {{ $labels.persistentvolumeclaim }} usage > 80%"
```

### 9.3 Relatório Mensal Automático

```python
# monthly-cost-report.py (Lambda)
import boto3
import json
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ce = boto3.client('ce')
    sns = boto3.client('sns')

    # Período: mês anterior
    end = datetime.now().replace(day=1)
    start = (end - timedelta(days=1)).replace(day=1)

    # Obter custos
    response = ce.get_cost_and_usage(
        TimePeriod={
            'Start': start.strftime('%Y-%m-%d'),
            'End': end.strftime('%Y-%m-%d')
        },
        Granularity='MONTHLY',
        Metrics=['UnblendedCost'],
        GroupBy=[
            {'Type': 'DIMENSION', 'Key': 'SERVICE'}
        ],
        Filter={
            'Tags': {
                'Key': 'Project',
                'Values': ['k8s-platform']
            }
        }
    )

    # Formatar relatório
    report = f"=== K8S Platform - Cost Report {start.strftime('%B %Y')} ===\n\n"

    total = 0
    for group in response['ResultsByTime'][0]['Groups']:
        service = group['Keys'][0]
        cost = float(group['Metrics']['UnblendedCost']['Amount'])
        total += cost
        report += f"{service}: ${cost:.2f}\n"

    report += f"\nTOTAL: ${total:.2f}\n"
    report += f"Budget: $1,000.00\n"
    report += f"Status: {'UNDER' if total < 1000 else 'OVER'} BUDGET\n"

    # Enviar via SNS
    sns.publish(
        TopicArn='arn:aws:sns:us-east-1:ACCOUNT_ID:k8s-cost-reports',
        Subject=f'K8S Platform Cost Report - {start.strftime("%B %Y")}',
        Message=report
    )

    return {'statusCode': 200, 'body': report}
```

---

## 10. Checklist de Conclusão

### 10.1 Definition of Done - FinOps

| Item | Critério | Status |
|------|----------|--------|
| **Tagging** | Todos recursos com tags obrigatórias | ☐ |
| **Cost Allocation** | Tags ativadas no Billing | ☐ |
| **Budgets** | Budget mensal configurado com alertas | ☐ |
| **Cost Explorer** | Relatórios salvos e funcionando | ☐ |
| **Anomaly Detection** | Monitor configurado | ☐ |
| **Start/Stop** | Lambda functions para dev/homolog | ☐ |
| **EventBridge** | Schedules configurados | ☐ |
| **Right-Sizing** | Compute Optimizer habilitado | ☐ |
| **S3 Lifecycle** | Policies em todos buckets | ☐ |
| **VPC Endpoints** | S3 e ECR endpoints criados | ☐ |
| **Savings Plans** | Avaliado e documentado | ☐ |
| **Dashboard** | Grafana FinOps dashboard | ☐ |
| **Alertas** | PrometheusRules de custo | ☐ |

### 10.2 Comandos de Verificação Final

```bash
# Verificar tags
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=k8s-platform \
  --query 'ResourceTagMappingList[*].ResourceARN' | wc -l

# Verificar budgets
aws budgets describe-budgets --account-id ACCOUNT_ID

# Verificar Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `k8s-`)].FunctionName'

# Verificar EventBridge rules
aws events list-rules --query 'Rules[?contains(Name, `k8s-`)].Name'

# Verificar VPC Endpoints
aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[*].[ServiceName,State]' --output table
```

### 10.3 Próximos Passos

- **Doc 08**: [Validação e Checklist](./08-validacao-checklist.md) - Smoke Tests, DoD final, Handoff

---

## Referências

- [AWS Cost Management](https://docs.aws.amazon.com/cost-management/)
- [AWS Compute Optimizer](https://docs.aws.amazon.com/compute-optimizer/)
- [AWS Savings Plans](https://docs.aws.amazon.com/savingsplans/)
- [FinOps Foundation](https://www.finops.org/)
- [EKS Best Practices - Cost Optimization](https://aws.github.io/aws-eks-best-practices/cost_optimization/cost_opt_compute/)
