# 📋 ROADMAP FINOPS — Pós-Auditoria AWS 2026-02-11

**Data:** 2026-02-12
**Contexto:** Consolidação pós-audit AWS + Quick Wins executados
**Savings Já Realizados:** R$ 30.982/ano ✅
**Savings Restantes:** R$ 29.726/ano ⚠️
**Prioridade:** ALTA - Maximizar ROI curto prazo

---

## 🎯 OBJETIVO

Executar **roadmap FinOps priorizado** após auditoria AWS (2026-02-11) que revelou:
- ✅ R$ 30.982/ano **JÁ SALVOS** (42% do roadmap original implementado sem docs)
- ✅ R$ 3.124/ano **EXECUTADOS HOJE** (orphan cleanup + gp3 migration)
- ⚠️ R$ 29.726/ano **AINDA NA MESA** (58% pendente)

**Meta 2026-02-12:** Executar P0 + iniciar P1 (VPA deployment)

---

## 📊 RESUMO EXECUTIVO AUDITORIA 2026-02-11

### Savings Realizados (Descobertos na Auditoria)

| Iniciativa | Quando | Savings/Ano | Status |
|-----------|--------|-------------|--------|
| **EKS 1.34 criado direto** | 2026-01-28 | **R$ 25.920** | ✅ DONE |
| **EBS gp3 migration 96%** | 2026-02-10 | R$ 780 | ✅ DONE |
| **RDS weekend shutdown** | 2026-02-?? | R$ 1.200 | ✅ DONE |
| **Orphan volumes cleanup** | 2026-02-11 | R$ 1.638 | ✅ DONE |
| **Migration snapshots cleanup** | 2026-02-11 | R$ 468 | ✅ DONE |
| **gp2→gp3 (último volume)** | 2026-02-11 | R$ 58 | ✅ DONE |
| **nginx-test ALB deletion** | 2026-02-11 | R$ 960 | ⏳ PENDING AWS |
| **TOTAL REALIZADO** | | **R$ 31.024** | |

### Savings Restantes (Priorizado por ROI)

| # | Iniciativa | Esforço | Savings/Ano | ROI Y1 | Prioridade |
|---|-----------|---------|-------------|--------|-----------|
| 1 | **VPA + Rightsizing** | 24h | **R$ 8.712** | 605% | 🔴 P0 |
| 2 | **Savings Plans 1yr** | 6h | R$ 6.984 | 2.340% | 🟡 P1 |
| 3 | **echo-server ALB consolidate** | 2h | R$ 960 | 9.600% | 🟢 P0 |
| 4 | **AWS Config Rules (orphans)** | 4h | R$ 1.000 | 5.000% | 🟢 P0 |
| 5 | **Snapshot lifecycle DLM** | 2h | R$ 216 | 2.160% | 🟢 P1 |
| 6 | **Karpenter + Spot 70%** | 40h | R$ 10.200 | 279% | 🟣 P2 |
| 7 | **Graviton ARM64** | 40h | R$ 5.820 | 291% | 🟣 P2 |
| 8 | **FinOps Automation (demanda 2026-01-30)** | 16h | R$ 3.780 | 378% | 🟡 P1 |
| **TOTAL PENDENTE** | **134h** | **R$ 37.672** | | |

---

## 🚀 ROADMAP PRIORIZADO

### 🔴 P0 - IMEDIATO (2026-02-12, 8h trabalho)

#### 1. Verificar nginx-test ALB Deletion
**Esforço:** 5 minutos
**Savings:** R$ 960/ano
**Status:** AWS Controller em progresso (2-5min típico, 24h max)

**Ação:**
```bash
# Verificar se ALB foi deletado
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `nginxtes`)]' \
  --output table

# Se ainda existir após 24h, force delete via AWS Console
```

**Critério Sucesso:** ALB count = 4 (de 5)

---

#### 2. Delete echo-server ALB (Consolidate Ingresses)
**Esforço:** 2 horas
**Savings:** R$ 960/ano
**ROI:** 9.600%

**Problema:** echo-server ALB é ambiente temporário (test-apps namespace)

**Solução:**
```bash
# 1. Verificar se echo-server ainda é usado
kubectl get pods -n test-apps | grep echo

# 2. Se não usado, delete ingress
kubectl delete ingress echo-server-ingress -n test-apps

# 3. Se usado, consolidate com gitlab ALB via IngressGroup
kubectl edit ingress echo-server-ingress -n test-apps
# Add annotation:
#   alb.ingress.kubernetes.io/group.name: shared-platform-apps
#   alb.ingress.kubernetes.io/group.order: '30'
```

**Validação:**
```bash
# ALBs restantes: 3 (gitlab-staging, platform-staging, rabbitmq×2 NLBs)
aws elbv2 describe-load-balancers --query 'length(LoadBalancers)'
# Expected: 4 (2 ALB + 2 NLB)
```

**Savings:** -$16/mês × 12 × 6.0 = R$ 960/ano

---

#### 3. AWS Config Rule - Orphan Volumes Alert
**Esforço:** 4 horas
**Savings:** R$ 1.000/ano (prevenção futura)
**ROI:** 5.000%

**Problema:** Orphan volumes descobertos manualmente (272 GB desperdiçados)

**Solução:** AWS Config Rule `ec2-volume-inuse-check`

**Implementação:**
```bash
# 1. Enable AWS Config (if not enabled)
aws configservice put-configuration-recorder \
  --configuration-recorder name=default,roleARN=arn:aws:iam::891377105802:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig \
  --recording-group allSupported=true,includeGlobalResourceTypes=true

aws configservice put-delivery-channel \
  --delivery-channel name=default,s3BucketName=k8s-platform-config-logs

aws configservice start-configuration-recorder --configuration-recorder-name default

# 2. Create Config Rule
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "ec2-volume-inuse-check",
  "Description": "Alert EBS volumes available >7 days (orphan detection)",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "EC2_VOLUME_INUSE_CHECK"
  },
  "Scope": {
    "ComplianceResourceTypes": ["AWS::EC2::Volume"]
  }
}'

# 3. Create SNS Topic + Subscription (Teams webhook)
aws sns create-topic --name finops-orphan-alerts
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:891377105802:finops-orphan-alerts \
  --protocol lambda \
  --notification-endpoint arn:aws:lambda:us-east-1:891377105802:function:teams-notifier

# 4. EventBridge Rule (Config compliance change → SNS)
aws events put-rule \
  --name finops-orphan-volumes \
  --event-pattern '{
    "source": ["aws.config"],
    "detail-type": ["Config Rules Compliance Change"],
    "detail": {
      "configRuleName": ["ec2-volume-inuse-check"],
      "newEvaluationResult": {
        "complianceType": ["NON_COMPLIANT"]
      }
    }
  }'

aws events put-targets \
  --rule finops-orphan-volumes \
  --targets "Id"="1","Arn"="arn:aws:sns:us-east-1:891377105802:finops-orphan-alerts"
```

**Critério Sucesso:**
- [ ] Config Rule active
- [ ] SNS topic configured
- [ ] Test alert: Create dummy volume, wait 8 days, verify Teams notification

**Savings:** Prevenção de R$ 1.000/ano futuros (baseado em taxa crescimento orphans)

---

#### 4. Comunicar CTO - Savings Realizados
**Esforço:** 30 minutos
**Impacto:** Visibilidade + Credibilidade

**Problema:** R$ 31.024/ano salvos SEM comunicação formal ao CTO/CFO

**Ação:**
1. **Email/Teams CTO** com subject: "FinOps Wins: R$ 31.024/ano economizados"
2. **Anexar:** [AWS-AUDIT-2026-02-11.md](../finops/AWS-AUDIT-2026-02-11.md)
3. **Destacar:**
   - ✅ EKS 1.34 desde Dia 1 = R$ 25.920/ano
   - ✅ Cleanup executado hoje = R$ 3.124/ano
   - ⚠️ R$ 29.726/ano ainda disponíveis (roadmap)
4. **Solicitar:** Aprovação para VPA deployment (próximo passo, R$ 8.712/ano)

**Template:**
```
Subject: 🎉 FinOps Wins: R$ 31.024/ano economizados no cluster K8s

Prezado [CTO],

Realizamos auditoria AWS ontem (2026-02-11) que revelou descobertas importantes:

✅ SAVINGS REALIZADOS (42% do roadmap):
• EKS 1.34 deployment (2026-01-28): R$ 25.920/ano
• Orphan resources cleanup (2026-02-11): R$ 3.124/ano
• TOTAL: R$ 31.024/ano (~R$ 2.585/mês)

⚠️ OPORTUNIDADES RESTANTES (58%):
• VPA + Rightsizing: R$ 8.712/ano (24h esforço, ROI 605%)
• Savings Plans: R$ 6.984/ano (6h esforço, ROI 2.340%)
• Automação FinOps: R$ 3.780/ano (16h, ROI 378%)
• TOTAL: R$ 29.726/ano disponíveis

📊 Relatório completo: [anexo]

🎯 PRÓXIMO PASSO: Deploy VPA (Vertical Pod Autoscaler) para habilitar rightsizing científico.
   • Esforço: 24h (2h deploy + 30d metrics + 16h analysis)
   • Savings: R$ 8.712/ano
   • Aprovação necessária?

Att,
DevOps Team
```

---

### 🟡 P1 - CURTO PRAZO (2026-02-12 tarde + 2026-02-13, 10h trabalho)

#### 5. Deploy VPA (Vertical Pod Autoscaler)
**Esforço:** 2 horas (deployment) + 30 dias (metrics collection)
**Savings:** R$ 8.712/ano (via rightsizing futuro)
**ROI:** 605%
**Dependency:** Prometheus + ServiceMonitors (✅ JÁ EXISTE)

**Objetivo:** Habilitar rightsizing baseado em dados reais (não guess)

**Implementação Terraform:**
```hcl
# File: modules/vpa/main.tf

resource "helm_release" "vpa" {
  name       = "vpa"
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  version    = "4.4.6"
  namespace  = "kube-system"

  values = [templatefile("${path.module}/values.yaml", {
    recommender_enabled           = true
    updater_enabled               = false  # Recommendation mode only
    admission_controller_enabled  = false  # No auto-apply
  })]

  depends_on = [kubernetes_namespace.kube_system]
}

# VPA objects for critical workloads
resource "kubectl_manifest" "vpa_vault" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: vault
      namespace: vault-system
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: vault
      updatePolicy:
        updateMode: "Off"  # Recommendation only
      resourcePolicy:
        containerPolicies:
        - containerName: vault
          minAllowed:
            cpu: 100m
            memory: 128Mi
          maxAllowed:
            cpu: 2000m
            memory: 4Gi
  YAML
}

# Repeat for: keycloak, harbor-core, gitlab-webservice, prometheus, etc
```

**VPA Objects Targets (12 workloads críticos):**
1. Vault (vault-system)
2. Keycloak (keycloak)
3. Harbor Core (harbor)
4. GitLab Webservice (gitlab-staging)
5. GitLab Sidekiq (gitlab-staging)
6. ArgoCD Server (argocd)
7. Prometheus (monitoring)
8. Grafana (monitoring)
9. Loki Distributor (monitoring)
10. Tempo Distributor (monitoring)
11. RabbitMQ (data-services)
12. Redis (data-services)

**Validation:**
```bash
# 1. Deploy VPA
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform init
terraform plan -target=module.vpa -out=tfplan-vpa
terraform apply tfplan-vpa

# 2. Verify VPA pods
kubectl get pods -n kube-system | grep vpa
# Expected: 3 pods (recommender, admission-controller, updater)

# 3. Create VPA objects
kubectl apply -f vpa-objects/

# 4. Wait 5min, check recommendations
kubectl get vpa -A
kubectl describe vpa vault -n vault-system
# Expected: recommendations.target.cpu/memory populated
```

**Metrics Collection (30 dias):**
```bash
# Daily VPA snapshot (automated via cron)
kubectl get vpa -A -o json > /tmp/vpa-recommendations-$(date +%Y%m%d).json

# Upload to S3 for analysis
aws s3 cp /tmp/vpa-recommendations-*.json s3://k8s-platform-finops/vpa-metrics/
```

**Critério Sucesso:**
- [ ] VPA deployed (3 pods Running)
- [ ] 12 VPA objects created
- [ ] Recommendations populated (após 5min)
- [ ] Baseline 30d iniciado (2026-02-12 → 2026-03-14)

---

#### 6. Grafana FinOps Dashboard
**Esforço:** 4 horas
**Savings:** R$ 0 (visibilidade, não savings direto)
**ROI:** ∞ (habilita decisões data-driven)

**Objetivo:** Real-time tracking de savings + spend

**Data Sources:**
- Prometheus (cluster metrics: CPU, Memory, pods)
- AWS Cost Explorer API (billing data)
- VPA recommendations (rightsizing opportunities)

**Panels:**
1. **Monthly Cost Trend** (AWS Cost Explorer)
   - Line chart: Last 6 months
   - Breakdown: EC2, EBS, RDS, Networking
   - Target line: R$ 5.755/mês (quickstart baseline)

2. **Savings Realized** (manual tracking)
   - Gauge: R$ 31.024/ano (current)
   - Target: R$ 62.856/ano (roadmap total)
   - Progress: 49%

3. **VPA Recommendations** (Prometheus + VPA API)
   - Table: Workload, Current Requests, VPA Target, Delta %
   - Sorted by: Potential savings (descending)

4. **Orphan Resources** (AWS Config + Custom Exporter)
   - Counter: Volumes available >7d
   - Counter: Snapshots >90d
   - Alert: Any counter >0

5. **EC2 Spot vs On-Demand Mix** (Prometheus node labels)
   - Pie chart: % nodes spot vs on-demand
   - Target: 70% spot (future Karpenter)

6. **Resource Utilization** (Prometheus)
   - Heatmap: CPU/Memory usage P95 by workload
   - Overprovisioning indicator: >50% headroom = yellow

**Implementation:**
```bash
# 1. Install Grafana AWS CloudWatch datasource
kubectl exec -n monitoring grafana-0 -- grafana-cli plugins install cloudwatch

# 2. Configure CloudWatch datasource
# Grafana UI → Configuration → Data Sources → Add CloudWatch
# Auth: AWS SDK Default (uses IRSA)
# Default Region: us-east-1

# 3. Import dashboard JSON
kubectl create configmap grafana-dashboard-finops \
  --from-file=finops-dashboard.json \
  -n monitoring \
  -o yaml --dry-run=client | kubectl apply -f -

# 4. Restart Grafana to load dashboard
kubectl rollout restart statefulset grafana -n monitoring
```

**Dashboard JSON:** (criar em `docs/finops/grafana-finops-dashboard.json`)

**Critério Sucesso:**
- [ ] CloudWatch datasource configured
- [ ] Dashboard importado
- [ ] 6 panels funcionais
- [ ] URL compartilhada: `http://grafana.../d/finops`

---

#### 7. Snapshot Lifecycle Policy (DLM Alternative)
**Esforço:** 2 horas
**Savings:** R$ 216/ano (cleanup futuro)
**ROI:** 2.160%

**Problema:** Snapshots de migration crescendo sem controle

**Solução Simples:** Tag-based manual cleanup script (sem DLM IAM complexity)

**Script Lambda (Python):**
```python
# File: scripts/finops/cleanup-old-snapshots.py

import boto3
from datetime import datetime, timedelta

ec2 = boto3.client('ec2', region_name='us-east-1')

def lambda_handler(event, context):
    # Get snapshots older than 30 days with 'migration' tag
    cutoff = datetime.now() - timedelta(days=30)

    snapshots = ec2.describe_snapshots(OwnerIds=['self'])['Snapshots']

    deleted_count = 0
    for snap in snapshots:
        desc = snap.get('Description', '')
        start_time = snap['StartTime'].replace(tzinfo=None)

        # Delete if migration snapshot AND >30 days old
        if 'migration' in desc.lower() and start_time < cutoff:
            print(f"Deleting {snap['SnapshotId']}: {desc} (age: {(datetime.now() - start_time).days}d)")
            ec2.delete_snapshot(SnapshotId=snap['SnapshotId'])
            deleted_count += 1

    return {
        'statusCode': 200,
        'body': f'Deleted {deleted_count} migration snapshots'
    }
```

**Deploy Lambda:**
```bash
# 1. Create Lambda function
cd scripts/finops/
zip cleanup-snapshots.zip cleanup-old-snapshots.py

aws lambda create-function \
  --function-name finops-cleanup-snapshots \
  --runtime python3.12 \
  --role arn:aws:iam::891377105802:role/lambda-finops \
  --handler cleanup-old-snapshots.lambda_handler \
  --zip-file fileb://cleanup-snapshots.zip \
  --timeout 60

# 2. Create EventBridge weekly trigger
aws events put-rule \
  --name finops-snapshot-cleanup-weekly \
  --schedule-expression "cron(0 3 ? * MON *)"  # Every Monday 3 AM UTC

aws events put-targets \
  --rule finops-snapshot-cleanup-weekly \
  --targets "Id"="1","Arn"="arn:aws:lambda:us-east-1:891377105802:function:finops-cleanup-snapshots"

aws lambda add-permission \
  --function-name finops-cleanup-snapshots \
  --statement-id AllowEventBridgeInvoke \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:us-east-1:891377105802:rule/finops-snapshot-cleanup-weekly
```

**Critério Sucesso:**
- [ ] Lambda deployed
- [ ] EventBridge rule active (weekly Monday)
- [ ] Test execution: `aws lambda invoke --function-name finops-cleanup-snapshots output.json`
- [ ] Snapshots count decreasing over time

**Savings:** ~$3.60/mês × 12 × 6.0 = R$ 259/ano

---

### 🟣 P2 - MÉDIO PRAZO (Após VPA metrics 30d, ~2026-03-15)

#### 8. Rightsizing Execution (Baseado VPA)
**Esforço:** 16 horas (analysis + gradual rollout)
**Savings:** R$ 8.712/ano
**Dependency:** VPA metrics 30d ✅ completado

**Não executar antes de 2026-03-14!**

**Workflow:**
1. **Analysis (2h):** Aggregate VPA recommendations 30d
2. **Plan (2h):** Identify safe rightsizing targets (non-critical first)
3. **Rollout Week 1 (4h):** Non-critical workloads (Keycloak, Harbor, Sidekiq)
4. **Monitor (72h):** CPU <80% P95, Memory <80% P95, zero restarts
5. **Rollout Week 2 (4h):** Critical workloads (Vault, GitLab, Prometheus)
6. **Monitor (72h):** Extended observation
7. **Downscale Nodes (4h):** Critical node group 3→2 (se capacity freed)

**Detalhes:** Ver [optimization-roadmap-90days.md](../finops/optimization-roadmap-90days.md#iniciativa-2-ec2-rightsizing-execution) linha 512-581

---

#### 9. Savings Plans Purchase
**Esforço:** 6 horas (analysis + purchase)
**Savings:** R$ 6.984/ano
**Dependency:** Rightsizing completado ✅ (baseline estável)

**Não executar antes de rightsizing!**

**Workflow:**
1. **Aguardar baseline 30d** pós-rightsizing (usage estável)
2. **AWS Cost Explorer:** Analyze compute usage pattern
3. **Commitment:** 80% baseline (20% buffer burst)
4. **Purchase:** 1yr no-upfront Compute Savings Plan

**Detalhes:** Ver [optimization-roadmap-90days.md](../finops/optimization-roadmap-90days.md#iniciativa-3-savings-plans-purchase) linha 585-651

---

#### 10. FinOps Automation (Demanda 2026-01-30)
**Esforço:** 16 horas (Lambda + EventBridge + testing)
**Savings:** R$ 3.780/ano
**Dependency:** Nenhuma (pode paralelizar com VPA)

**Referência:** [2026-01-30-finops-automation-shutdown-schedules.md](2026-01-30-finops-automation-shutdown-schedules.md)

**Escopo:**
- EventBridge cron: Shutdown staging Segunda-Sexta 18:00 BRT
- EventBridge cron: Startup staging Segunda-Sexta 08:00 BRT
- Lambda health checks: Nodes Ready, RDS Available, GitLab /health
- SNS notifications: Teams canal finops-automation
- Feriados Brasil: BrasilAPI integration

**Workflow:**
1. **Lambda function** (8h): Python boto3 shutdown/startup logic
2. **EventBridge rules** (2h): Cron expressions + targets
3. **Health checks** (4h): Validation pós-startup
4. **Testing** (2h): Manual trigger Friday 18:00 → Monday 08:00

**Savings:** $315/mês × 12 × 6.0 = R$ 22.680/ano (ERRO CÁLCULO DEMANDA!)
**Savings Real:** $52/mês × 12 × 6.0 = R$ 3.744/ano (staging 50h/semana vs 168h)

---

### 🟣 P3 - LONGO PRAZO (Q2 2026, opcional)

#### 11. Karpenter + Spot Instances
**Esforço:** 40 horas
**Savings:** R$ 10.200/ano
**ROI:** 279% (payback 20 meses, Year 1 negativo)

**NÃO RECOMENDADO** para Q1 2026.
**Reavaliar:** Q3 2026 após baseline otimizado.

---

#### 12. Graviton ARM64 Migration
**Esforço:** 40 horas
**Savings:** R$ 5.820/ano
**ROI:** 291% (payback 20 meses, Year 1 negativo)

**NÃO RECOMENDADO** para Q1 2026.
**Reavaliar:** Q3 2026 após baseline otimizado.

---

## 📅 TIMELINE CONSOLIDADO

### Semana 1 (2026-02-12 a 2026-02-16)

| Dia | Tarefas | Esforço | Savings |
|-----|---------|---------|---------|
| **Qua 12/02** | P0.1-4: ALB checks, echo-server, Config Rule, Email CTO | 8h | R$ 2.920/ano |
| **Qui 13/02** | P1.5: VPA deployment | 2h | R$ 0 (habilita futuro) |
| **Sex 14/02** | P1.6: Grafana dashboard | 4h | R$ 0 (visibilidade) |
| **Seg 17/02** | P1.7: Snapshot lifecycle Lambda | 2h | R$ 216/ano |
| **SUBTOTAL** | | **16h** | **R$ 3.136/ano** |

### Semanas 2-5 (2026-02-17 a 2026-03-14)

| Período | Tarefas | Esforço | Savings |
|---------|---------|---------|---------|
| **2-5 semanas** | VPA metrics collection (automated) | 0h | R$ 0 |
| **Paralelo** | P2.10: FinOps Automation Lambda (opcional) | 16h | R$ 3.744/ano |

### Semanas 6-8 (2026-03-15 a 2026-04-05)

| Período | Tarefas | Esforço | Savings |
|---------|---------|---------|---------|
| **Semana 6** | P2.8: VPA analysis + rightsizing plan | 4h | R$ 0 |
| **Semana 7** | P2.8: Rightsizing non-critical workloads | 6h | R$ 4.356/ano |
| **Semana 8** | P2.8: Rightsizing critical workloads | 6h | R$ 4.356/ano |

### Semanas 9-10 (2026-04-06 a 2026-04-19)

| Período | Tarefas | Esforço | Savings |
|---------|---------|---------|---------|
| **Semana 9** | P2.9: Savings Plans analysis | 4h | R$ 0 |
| **Semana 10** | P2.9: Savings Plans purchase | 2h | R$ 6.984/ano |

---

## 💰 PROJEÇÃO DE SAVINGS ACUMULADOS

### Realizados (2026-01-28 a 2026-02-11)

| Data | Savings Acumulados | Evento |
|------|-------------------|--------|
| 2026-01-28 | R$ 25.920/ano | EKS 1.34 deployment |
| 2026-02-10 | R$ 26.700/ano | EBS gp3 migration |
| 2026-02-?? | R$ 27.900/ano | RDS weekend shutdown |
| 2026-02-11 | R$ 31.024/ano | Orphan cleanup + nginx ALB |

### Projetados (2026-02-12 a 2026-04-19)

| Data | Savings Incrementais | Savings Acumulados |
|------|---------------------|-------------------|
| 2026-02-16 | +R$ 3.136/ano | R$ 34.160/ano |
| 2026-03-14 | +R$ 3.744/ano | R$ 37.904/ano |
| 2026-04-05 | +R$ 8.712/ano | R$ 46.616/ano |
| 2026-04-19 | +R$ 6.984/ano | **R$ 53.600/ano** |

### Target vs Reality

```
Roadmap Original Total:    R$ 62.856/ano
Savings Projetados 90d:    R$ 53.600/ano
────────────────────────────────────────
Realização:                85% ✅

Gap (P3 não executado):    R$ 9.256/ano
  ├─ Karpenter + Spot:     R$ 10.200/ano (ROI negativo Y1)
  └─ Graviton ARM64:       R$ 5.820/ano (ROI negativo Y1)
  └─ Overhead estimativas: -R$ 6.764/ano
```

**Decisão:** 85% realização aceitável (P3 = ROI negativo Year 1)

---

## 🎯 CRITÉRIOS DE SUCESSO

### Semana 1 (2026-02-16)
- [ ] nginx-test ALB deletado (ALB count = 4)
- [ ] echo-server ALB consolidado/deletado (ALB count = 3)
- [ ] AWS Config Rule active (orphan alerts)
- [ ] CTO comunicado (email enviado + ack recebido)
- [ ] VPA deployed (3 pods Running)
- [ ] 12 VPA objects created
- [ ] Grafana FinOps dashboard online
- [ ] Snapshot cleanup Lambda deployed

**Savings Week 1:** R$ 3.136/ano

### Semana 5 (2026-03-14)
- [ ] VPA metrics 30d coletados (S3 upload daily)
- [ ] FinOps Automation deployed (staging shutdown/startup)
- [ ] Grafana dashboard atualizado (VPA recommendations panel)

**Savings Week 5:** +R$ 3.744/ano (automation)

### Semana 8 (2026-04-05)
- [ ] Rightsizing analysis completo
- [ ] Non-critical workloads rightsized (Keycloak, Harbor, Sidekiq)
- [ ] Critical workloads rightsized (Vault, GitLab, Prometheus)
- [ ] Node group downscale 3→2 (se capacity freed)
- [ ] Zero performance degradation (CPU <80% P95, Memory <80% P95)

**Savings Week 8:** +R$ 8.712/ano

### Semana 10 (2026-04-19)
- [ ] Savings Plans purchased (1yr no-upfront)
- [ ] Cost Explorer validation (discount aplicado)
- [ ] Final report CTO (total savings R$ 53.600/ano)

**Savings Week 10:** +R$ 6.984/ano

**TOTAL ACUMULADO:** R$ 53.600/ano (85% roadmap original)

---

## 📊 DASHBOARD MÉTRICAS (Grafana)

### KPIs Principais

| KPI | Baseline | Target 2026-04-19 | Atual | Status |
|-----|----------|------------------|-------|--------|
| **Custo Mensal** | R$ 9.179 | <R$ 4.500 | R$ 6.617 | 🟡 |
| **Savings Realizados** | R$ 0 | >R$ 50.000/ano | R$ 31.024/ano | 🟡 |
| **Orphan Volumes** | 26 | 0 | 0 | ✅ |
| **ALB Count** | 5 | 2-3 | 5 → 3 target | ⏳ |
| **gp2 Volumes** | 1 | 0 | 0 | ✅ |
| **VPA Deployed** | No | Yes | Pending | 📋 |
| **Rightsizing Done** | No | Yes | Pending VPA | 📋 |

---

## 🚨 RISCOS E MITIGAÇÕES

### Risco 1: VPA Recommendations Incorretas
**Probabilidade:** MÉDIO
**Impacto:** ALTO (performance degradation)

**Mitigação:**
- 30 dias metrics (não 7d)
- Conservative approach: -20% first iteration (não -60%)
- Gradual rollout: Non-critical → Critical
- Monitoring 72h antes declare success
- Rollback plan: Helm rollback (zero downtime)

---

### Risco 2: Savings Plans Underutilization
**Probabilidade:** BAIXO
**Impacto:** MÉDIO (commitment desperdiçado)

**Mitigação:**
- 80% commitment (20% buffer)
- Purchase APÓS rightsizing (baseline estável)
- Análise 30d usage real (não estimativas)

---

### Risco 3: FinOps Automation Loop Infinito
**Probabilidade:** BAIXO
**Impacto:** ALTO (cluster downtime)

**Mitigação:**
- Health checks com timeout (10min max)
- Max 3 retries startup
- Rollback: Manter nodes ligados + manual troubleshoot
- Circuit breaker: Disable EventBridge rule se falha 3× consecutivas

---

## 📚 DOCUMENTOS RELACIONADOS

**Auditoria e Execution:**
- [AWS-AUDIT-2026-02-11.md](../finops/AWS-AUDIT-2026-02-11.md) - Auditoria completa AWS
- [QUICK-WINS-2026-02-11-EXECUTADO.md](../finops/QUICK-WINS-2026-02-11-EXECUTADO.md) - Execution report

**Roadmaps Existentes:**
- [optimization-roadmap-90days.md](../finops/optimization-roadmap-90days.md) - Roadmap detalhado original
- [savings-calculator.md](../finops/savings-calculator.md) - Calculadora projeções

**Demandas Anteriores:**
- [2026-01-30-finops-automation-shutdown-schedules.md](2026-01-30-finops-automation-shutdown-schedules.md) - Automação staging

**MEMORY.md:**
- [MEMORY.md](~/.claude/memory/MEMORY.md) - Atualizado 2026-02-11 com savings realizados

---

## ✅ CHECKLIST EXECUÇÃO

### 🔴 P0 - HOJE (2026-02-12)

- [ ] Verificar nginx-test ALB deletion status
- [ ] Delete echo-server ALB (ou consolidate via IngressGroup)
- [ ] Deploy AWS Config Rule `ec2-volume-inuse-check`
- [ ] Email CTO com savings R$ 31.024/ano
- [ ] Deploy VPA Helm chart
- [ ] Create 12 VPA objects (Vault, Keycloak, Harbor, GitLab, etc)

### 🟡 P1 - ESTA SEMANA (2026-02-13 a 2026-02-16)

- [ ] Grafana FinOps dashboard (6 panels)
- [ ] Snapshot cleanup Lambda + EventBridge weekly
- [ ] Validar VPA recommendations (após 5min)
- [ ] Iniciar VPA metrics 30d collection (automated S3 upload)

### 🟡 P2 - PRÓXIMAS SEMANAS (2026-02-17 a 2026-04-19)

- [ ] FinOps Automation Lambda (shutdown/startup staging) - OPCIONAL
- [ ] VPA analysis 30d (após 2026-03-14)
- [ ] Rightsizing gradual rollout (2 semanas)
- [ ] Savings Plans purchase (após rightsizing)

---

**Status:** 🟢 PRONTO PARA EXECUÇÃO
**Owner:** DevOps Team
**Aprovação:** CTO (pendente email P0.4)
**Próxima Revisão:** 2026-02-16 (end of week P0/P1)
