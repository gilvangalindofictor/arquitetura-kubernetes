# FinOps: Scripts de Automação Start/Stop

**Objetivo:** Automatizar startup/shutdown de recursos EKS e RDS para economia de custos em ambientes não-produtivos.

**Economia Estimada:**
- **Dev/Staging (8h/dia):** $368.96/mês ($4.428/ano) por ambiente
- **Produção (10h/dia):** $333.52/mês ($4.002/ano) - se aplicável

---

## 📁 Arquivos

```
scripts/finops/
├── README.md                    # Este arquivo
├── startup-marco2.sh           # Script bash para start manual
├── shutdown-marco2.sh          # Script bash para stop manual
├── lambda-start-nodes.py       # Lambda function para start automático
├── lambda-stop-nodes.py        # Lambda function para stop automático
└── terraform/                  # Terraform para deploy Lambda + EventBridge
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

---

## 🚀 Quick Start

### Opção 1: Scripts Bash (Uso Manual)

```bash
# Development - Start
./startup-marco2.sh dev

# Development - Stop
./shutdown-marco2.sh dev

# Development - Stop com snapshot RDS
./shutdown-marco2.sh dev --snapshot
```

### Opção 2: Lambda Functions (Automático)

**Deploy via Terraform:**

```bash
cd scripts/finops/terraform

# Configurar variáveis
export TF_VAR_environment="dev"
export TF_VAR_cluster_name="k8s-platform-cluster"

# Deploy
terraform init
terraform plan
terraform apply
```

---

## 📋 Scripts Bash

### startup-marco2.sh

**Descrição:** Inicia nodes EKS + RDS

**Uso:**
```bash
./startup-marco2.sh [dev|staging|prod]
```

**Ações:**
1. Scale node groups: system (2), workloads (3), critical (2)
2. Aguarda nodes ficarem Ready (timeout 5min)
3. Start RDS instance
4. Aguarda RDS ficar available (timeout 5min)
5. Verifica pods da plataforma

**Logs:** `/var/log/k8s-startup-YYYYMMDD-HHMMSS.log`

**Tempo estimado:** 5-7 minutos

---

### shutdown-marco2.sh

**Descrição:** Para nodes EKS + RDS

**Uso:**
```bash
./shutdown-marco2.sh [dev|staging|prod] [--snapshot]
```

**Flags:**
- `--snapshot`: Cria snapshot RDS antes de parar (recomendado para long weekends)

**Ações:**
1. Drain graceful de pods críticos (Prometheus, Grafana, Loki)
2. (Opcional) Cria snapshot RDS
3. Stop RDS instance
4. Scale node groups para 0
5. Aguarda nodes terminarem (timeout 5min)
6. Calcula economia estimada

**Logs:** `/var/log/k8s-shutdown-YYYYMMDD-HHMMSS.log`

**Tempo estimado:** 3-5 minutos

---

## 🤖 Lambda Functions

### lambda-start-nodes.py

**Trigger:** EventBridge cron (Segunda-Sexta 08:00 BRT = 11:00 UTC)

**Environment Variables:**
```bash
CLUSTER_NAME=k8s-platform-cluster
AWS_REGION=us-east-1
ENVIRONMENT=dev
SNS_TOPIC_ARN=arn:aws:sns:us-east-1:ACCOUNT:k8s-finops-alerts
```

**IAM Permissions:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeNodegroup",
        "eks:UpdateNodegroupConfig",
        "rds:DescribeDBInstances",
        "rds:StartDBInstance",
        "sns:Publish",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

**Timeout:** 5 minutos
**Memory:** 256 MB
**Runtime:** Python 3.11

---

### lambda-stop-nodes.py

**Trigger:** EventBridge cron (Segunda-Sexta 18:00 BRT = 21:00 UTC)

**Environment Variables:**
```bash
CLUSTER_NAME=k8s-platform-cluster
AWS_REGION=us-east-1
ENVIRONMENT=dev
SNS_TOPIC_ARN=arn:aws:sns:us-east-1:ACCOUNT:k8s-finops-alerts
CREATE_RDS_SNAPSHOT=false  # true para sextas-feiras
```

**IAM Permissions:** (mesmas de start + `rds:StopDBInstance`, `rds:CreateDBSnapshot`)

**Features:**
- Calcula economia estimada automática
- Notificação SNS com resumo
- Snapshot RDS opcional (use `CREATE_RDS_SNAPSHOT=true`)

---

## 📅 EventBridge Schedules

### Horários Recomendados

| Ambiente | Start | Stop | Timezone |
|----------|-------|------|----------|
| **Development** | 08:00 BRT (11:00 UTC) | 18:00 BRT (21:00 UTC) | América/São_Paulo |
| **Staging** | 08:00 BRT (11:00 UTC) | 18:00 BRT (21:00 UTC) | América/São_Paulo |
| **Production** | N/A (always-on) | N/A (always-on) | - |

### Cron Expressions

**Start (Segunda-Sexta 08:00 BRT):**
```
cron(0 11 ? * MON-FRI *)
```

**Stop (Segunda-Sexta 18:00 BRT):**
```
cron(0 21 ? * MON-FRI *)
```

**Stop Sexta + Snapshot (18:00 BRT):**
```
cron(0 21 ? * FRI *)
```

**Restore Segunda (07:45 BRT - 15min antes):**
```
cron(45 10 ? * MON *)
```

---

## 🏷️ Tags para Automação

**Adicionar tag `Schedule` aos recursos:**

### Nodes Dev/Staging
```bash
aws eks tag-resource \
  --resource-arn arn:aws:eks:us-east-1:ACCOUNT:nodegroup/k8s-platform-cluster/system \
  --tags Schedule=office-hours,Environment=dev
```

### RDS Dev
```bash
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:us-east-1:ACCOUNT:db:gitlab-dev \
  --tags Key=Schedule,Value=office-hours
```

### Production (always-on)
```bash
aws eks tag-resource \
  --resource-arn arn:aws:eks:us-east-1:ACCOUNT:nodegroup/k8s-platform-cluster/system \
  --tags Schedule=always-on,Environment=production
```

**Tags aceitas:**
- `Schedule=office-hours` → Gerenciado por automação
- `Schedule=always-on` → Sempre ligado, pular automação
- `Environment=dev|staging|prod` → Filtro por ambiente

---

## 🔍 Monitoramento

### CloudWatch Logs

**Log Groups:**
- `/aws/lambda/k8s-start-dev-nodes`
- `/aws/lambda/k8s-stop-dev-nodes`

**Queries úteis (CloudWatch Insights):**

```
# Verificar sucessos/falhas
fields @timestamp, statusCode, body.success
| filter @type = "END"
| sort @timestamp desc
| limit 20

# Economia calculada
fields @timestamp, body.savings.daily_usd, body.savings.monthly_usd
| filter body.savings.daily_usd > 0
| stats sum(body.savings.daily_usd) as total_daily_savings
```

### Alertas SNS

**Tópico:** `k8s-finops-alerts`

**Notificações enviadas:**
- ✅ Start bem-sucedido
- ✅ Stop bem-sucedido
- ❌ Falha ao iniciar nodes
- ❌ Falha ao parar RDS
- 📸 Snapshot criado

**Exemplo de mensagem:**
```
Subject: EKS Start - dev - SUCCESS

Environment: dev
Cluster: k8s-platform-cluster
Timestamp: 2026-01-29T11:00:00Z

Node Groups:
  - system: initiated
  - workloads: initiated
  - critical: initiated

RDS:
  - gitlab-dev: start_initiated
```

---

## 🛠️ Troubleshooting

### Nodes não startaram

**Sintoma:** Lambda executou mas nodes permanecem 0

**Verificar:**
```bash
# Check ASG
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `system`)].{Name:AutoScalingGroupName,Desired:DesiredCapacity,Min:MinSize,Max:MaxSize}'

# Check node group status
aws eks describe-nodegroup \
  --cluster-name k8s-platform-cluster \
  --nodegroup-name system
```

**Solução:** Verificar quotas EC2, capacity provider, subnet AZs

---

### RDS não inicia

**Sintoma:** RDS permanece `stopped` após Lambda

**Verificar:**
```bash
aws rds describe-db-instances \
  --db-instance-identifier gitlab-dev \
  --query 'DBInstances[0].[DBInstanceStatus,StatusInfos]'
```

**Causas comuns:**
- RDS em maintenance window
- Snapshot em progresso
- Account limits (max 40 RDS instances)

**Solução:**
```bash
# Force start manual
aws rds start-db-instance --db-instance-identifier gitlab-dev
```

---

### Lambda timeout

**Sintoma:** Lambda termina após 5min sem completar

**Solução:**
- Aumentar timeout para 10min (console Lambda → Configuration → General)
- Verificar se EKS API está respondendo (VPC networking)
- Checar IAM permissions

---

### Pods CrashLoopBackOff após start

**Sintoma:** Nodes sobem mas pods ficam reiniciando

**Verificar:**
```bash
kubectl get pods -n observability
kubectl describe pod <pod-name> -n observability
```

**Causas comuns:**
- PVCs não montaram (EBS CSI driver)
- ConfigMaps/Secrets ausentes
- ImagePullBackOff (ECR auth)

**Solução:**
```bash
# Restart pods
kubectl rollout restart deployment -n observability
```

---

## 📊 Economia Real (Medição)

### AWS Cost Explorer

**Filtros:**
1. **Tag:** `Schedule=office-hours`
2. **Service:** EC2, RDS
3. **Granularity:** Daily
4. **Period:** Last 30 days

**Query:**
```
cost_per_day_with_startstop vs cost_baseline_24x7
```

**KPIs esperados:**
- **Economia Dev:** ~54% (8h/dia útil)
- **Economia Staging:** ~54% (8h/dia útil)
- **Uptime conformance:** >95% (poucos erros Lambda)

### Grafana Dashboard

**Painel:** `FinOps - StartStop Monitoring`

**Métricas:**
1. Node count timeline (esperado: 7→0→7)
2. RDS status (stopped → available)
3. Lambda execution duration
4. Daily cost trend

---

## 🔄 Runbook Operacional

### Manual Start (Emergency)

```bash
# Via script
./startup-marco2.sh dev

# Via AWS CLI
aws eks update-nodegroup-config \
  --cluster-name k8s-platform-cluster \
  --nodegroup-name system \
  --scaling-config minSize=2,desiredSize=2,maxSize=4

aws rds start-db-instance --db-instance-identifier gitlab-dev
```

### Manual Stop (Emergency)

```bash
# Via script
./shutdown-marco2.sh dev --snapshot

# Via AWS CLI
aws eks update-nodegroup-config \
  --cluster-name k8s-platform-cluster \
  --nodegroup-name system \
  --scaling-config minSize=0,desiredSize=0,maxSize=4

aws rds stop-db-instance --db-instance-identifier gitlab-dev
```

### Verificar Status

```bash
# Nodes
kubectl get nodes

# RDS
aws rds describe-db-instances \
  --db-instance-identifier gitlab-dev \
  --query 'DBInstances[0].DBInstanceStatus'

# Lambda última execução
aws lambda get-function \
  --function-name k8s-start-dev-nodes \
  --query 'Configuration.LastUpdateStatus'
```

---

## 📚 Referências

- [Documento Principal: STARTUP-SHUTDOWN-STRATEGY.md](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/finops/STARTUP-SHUTDOWN-STRATEGY.md)
- [AWS Lambda + EventBridge](https://docs.aws.amazon.com/lambda/latest/dg/services-cloudwatchevents.html)
- [EKS Update Node Group](https://docs.aws.amazon.com/eks/latest/APIReference/API_UpdateNodegroupConfig.html)
- [RDS Stop Limitations](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_StopInstance.html)

---

## ✅ Checklist de Implementação

- [ ] Scripts bash testados em dev
- [ ] Lambda functions deployed
- [ ] EventBridge rules configuradas
- [ ] SNS topic + subscriptions criadas
- [ ] IAM policies attachadas
- [ ] Tags aplicadas aos recursos
- [ ] Alertas CloudWatch configurados
- [ ] Grafana dashboard criado
- [ ] Runbook documentado
- [ ] Teste completo ciclo start/stop (1 semana trial)

---

**Mantenedores:** FinOps Team + DevOps
**Última atualização:** 2026-01-29
**Próxima revisão:** 2026-02-15
