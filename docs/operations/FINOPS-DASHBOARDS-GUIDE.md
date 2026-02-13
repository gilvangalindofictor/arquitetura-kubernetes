# 💰 FinOps Grafana Dashboards Guide

**Last Updated:** 2026-02-13
**Version:** 1.0.0
**Status:** Operational Guide
**Owner:** Platform Team

---

## 📋 Overview

Guia operacional para os **3 dashboards FinOps** deployados via Grafana + kube-prometheus-stack.

**Dashboards:**
1. **AWS Costs Overview** - Custos AWS em tempo real (CloudWatch Billing)
2. **Resource Utilization** - Uso de recursos cluster (CPU, Memory, Storage)
3. **FinOps Alerts** - Alertas de budget, idle resources, cost spikes

**Deployment:**
- Terraform module: `modules/observability`
- ConfigMaps auto-discovery: label `grafana_dashboard="1"`
- Namespace: `monitoring`
- Grafana URL: `http://grafana.staging.internal` (via ALB + /etc/hosts)

---

## 🎯 Dashboard 1: AWS Costs Overview

### Purpose

Monitorar custos AWS em tempo real baseado em CloudWatch Billing metrics.

### Panels (6 total)

#### 1. Monthly Cost Trend (Estimated Charges)
- **Type:** Time series
- **Metric:** `EstimatedCharges` (CloudWatch Billing)
- **Description:** Trend line dos custos mensais acumulados
- **Use Case:** Identificar padrões de crescimento de custo ao longo do mês

#### 2. Total Estimated Charges (Current Month)
- **Type:** Stat
- **Metric:** `EstimatedCharges` (current)
- **Description:** Total acumulado do mês atual
- **Thresholds:**
  - Green: < $700
  - Yellow: $700-850
  - Red: > $850

#### 3. Daily Cost Rate
- **Type:** Stat
- **Calculation:** `(Current Month Total) / (Days Elapsed)`
- **Description:** Taxa de gasto diário média
- **Use Case:** Projetar custo final do mês

#### 4. Cost Breakdown by Service
- **Type:** Pie chart
- **Metric:** `EstimatedCharges` by `ServiceName`
- **Description:** Distribuição de custos por serviço AWS (EKS, EC2, RDS, S3, etc.)
- **Use Case:** Identificar serviços mais caros

#### 5. Savings Realized (R$/ano)
- **Type:** Table
- **Data Source:** Static/manual updates
- **Description:** Lista de savings FinOps realizados
- **Columns:**
  - Initiative (e.g., "EBS gp2→gp3")
  - Savings (R$/ano)
  - Date Implemented
  - Status

**Current Savings (2026-02-13):**
- EKS 1.34 direct: R$ 25.920/ano
- Orphan resources cleanup: R$ 2.106/ano
- EBS gp3 migration: R$ 780/ano
- RDS weekend shutdown: R$ 1.200/ano
- CloudWatch Logs retention: R$ 54/ano
- Security Groups cleanup: R$ 576/ano
- **Total: R$ 30.636/ano**

#### 6. Cost per Node Group
- **Type:** Bar gauge
- **Calculation:** `(Node Group Instance Cost) × (Desired Size)`
- **Description:** Custo mensal estimado por node group (system, workloads, critical)
- **Use Case:** Identificar node groups overprovisioned

---

## 📊 Dashboard 2: Resource Utilization

### Purpose

Analisar uso de recursos do cluster (CPU, memory, storage) para identificar overprovisioning e rightsizing opportunities.

### Panels (10 total)

#### 1. CPU Usage by Node (%)
- **Type:** Time series
- **Metric:** `node_cpu_seconds_total` (Prometheus)
- **Description:** CPU usage % por node ao longo do tempo
- **Threshold:** > 80% sustained = capacity planning needed

#### 2. Memory Usage by Node (%)
- **Type:** Time series
- **Metric:** `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes`
- **Description:** Memory usage % por node
- **Threshold:** > 85% sustained = capacity planning needed

#### 3. Cluster CPU: Requests vs Allocatable
- **Type:** Time series (stacked)
- **Metrics:**
  - `kube_pod_container_resource_requests{resource="cpu"}`
  - `kube_node_status_allocatable{resource="cpu"}`
- **Description:** Total CPU requested vs disponível no cluster
- **Use Case:** Identificar se cluster pode acomodar mais workloads

#### 4. Cluster Memory: Requests vs Allocatable
- **Type:** Time series (stacked)
- **Metrics:** Same as #3 but `resource="memory"`
- **Use Case:** Identificar se cluster pode acomodar mais workloads

#### 5. Overprovisioning: CPU
- **Type:** Stat
- **Calculation:** `(Allocatable - Requests) / Allocatable × 100%`
- **Description:** % de CPU não solicitada (waste)
- **Thresholds:**
  - Green: < 20% (good utilization)
  - Yellow: 20-40% (moderate waste)
  - Red: > 40% (high waste, consider downsizing)

#### 6. Overprovisioning: Memory
- **Type:** Stat
- **Calculation:** Same as #5 but for memory
- **Use Case:** Identificar se node groups podem ser downsized

#### 7. EBS Volume Usage (%)
- **Type:** Bar gauge
- **Metric:** `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes`
- **Description:** % de uso por PVC
- **Threshold:** > 85% = resize needed

#### 8. Network Throughput by Node
- **Type:** Time series
- **Metric:** `rate(node_network_transmit_bytes_total[5m])`
- **Description:** Network TX/RX por node (Mbps)
- **Use Case:** Identificar nodes com alto tráfego (consider ENA optimization)

#### 9. Top 10 Pods by CPU Usage
- **Type:** Table
- **Metric:** `rate(container_cpu_usage_seconds_total[5m])`
- **Columns:** Namespace, Pod, CPU Usage (cores), % of Requests
- **Use Case:** Identificar pods com high CPU para rightsizing

#### 10. Top 10 Pods by Memory Usage
- **Type:** Table
- **Metric:** `container_memory_working_set_bytes`
- **Columns:** Namespace, Pod, Memory Usage (GB), % of Requests
- **Use Case:** Identificar pods com high memory para rightsizing

---

## 🚨 Dashboard 3: FinOps Alerts

### Purpose

Alertar sobre budget overruns, idle resources, cost spikes e anomalias.

### Panels (7 total)

#### 1. Monthly Budget Usage
- **Type:** Gauge
- **Metric:** `(Current Month Spend / Budget) × 100%`
- **Budget:** $900/mês (staging)
- **Thresholds:**
  - Green: < 80%
  - Yellow: 80-95%
  - Red: > 95%
- **Alert:** Slack notification at 85% e 95%

#### 2. Cost Spike Detection (Hourly Increase)
- **Type:** Time series
- **Calculation:** `rate(EstimatedCharges[1h])`
- **Description:** Taxa de aumento de custo por hora
- **Alert:** > $5/hour increase (anomaly detection)

#### 3. Pods with Low CPU Usage (<5% for 1h)
- **Type:** Table
- **Metric:** `avg_over_time(rate(container_cpu_usage_seconds_total[1h]))`
- **Threshold:** < 0.05 cores (5% of 1 core)
- **Use Case:** Identificar pods idle candidates para downscale

#### 4. PVCs Not Mounted (Orphan Volumes)
- **Type:** Table
- **Metric:** `kube_persistentvolumeclaim_info{volumename!=""} unless on(persistentvolumeclaim) kube_pod_spec_volumes_persistentvolumeclaims_info`
- **Description:** PVCs criados mas não usados por nenhum pod
- **Use Case:** Deletar volumes órfãos (savings EBS)

#### 5. Active Prometheus Alerts
- **Type:** Table
- **Metric:** `ALERTS{alertstate="firing"}`
- **Description:** Alertas Prometheus ativos (any severity)
- **Use Case:** Centralizar visão de alertas críticos

#### 6. Nodes Count by Node Group
- **Type:** Stat
- **Metric:** `count by (label_node_type) (kube_node_info)`
- **Description:** Contagem de nodes por node group (system, workloads, critical)
- **Use Case:** Validar auto-scaling behavior

#### 7. EBS Volume Type Distribution
- **Type:** Pie chart
- **Metric:** `count by (volume_type) (kube_persistentvolume_info)`
- **Description:** Distribuição gp2 vs gp3
- **Use Case:** Track migration gp2→gp3 (20% savings)

---

## 🔧 Common Operations

### Access Dashboards

```bash
# 1. Port-forward Grafana (if ALB not accessible)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# 2. Get admin password
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d

# 3. Open browser
http://localhost:3000

# Login: admin / <password>
```

**Via ALB (staging):**
- URL: `http://grafana.staging.internal`
- Add to `/etc/hosts`: `<ALB_IP> grafana.staging.internal`

### Locate Dashboards

```
Grafana UI → Dashboards → Browse
Filter by tag: "finops"
```

Dashboards should appear as:
- AWS Costs Overview
- FinOps Alerts
- Resource Utilization

### Update Dashboard JSON

```bash
# 1. Edit dashboard JSON locally
vim platform-provisioning/aws/kubernetes/terraform/modules/observability/grafana-dashboards/aws-costs-overview.json

# 2. Apply via Terraform
cd platform-provisioning/aws/kubernetes/terraform/environments/staging/
terraform plan -target=module.observability
terraform apply -target=module.observability

# 3. Verify update (dashboard reloads automatically via sidecar)
kubectl get configmap -n monitoring grafana-dashboard-aws-costs-overview -o yaml
```

**Note:** Grafana sidecar polls ConfigMaps every 60s. Changes auto-reload.

### Add New Panel

```json
// Example: Add "S3 Bucket Size" panel to aws-costs-overview.json
{
  "id": 7,
  "title": "S3 Bucket Total Size (GB)",
  "type": "stat",
  "gridPos": {"x": 8, "y": 8, "w": 8, "h": 4},
  "datasource": {"type": "cloudwatch", "uid": "cloudwatch"},
  "targets": [
    {
      "dimensions": {
        "BucketName": "*",
        "StorageType": "StandardStorage"
      },
      "metricName": "BucketSizeBytes",
      "namespace": "AWS/S3",
      "period": "86400",
      "statistic": "Average"
    }
  ],
  "fieldConfig": {
    "defaults": {
      "unit": "decbytes",
      "decimals": 2
    }
  }
}
```

---

## 📈 FinOps KPIs

### Monthly Tracking

Track these KPIs mensalmente using dashboards:

| KPI | Target | Current (2026-02) | Dashboard |
|-----|--------|------------------|-----------|
| Monthly Spend | < $900 | ~$835 (93%) | AWS Costs Overview |
| CPU Overprovisioning | < 30% | ~25% | Resource Utilization |
| Memory Overprovisioning | < 30% | ~22% | Resource Utilization |
| Orphan PVCs | 0 | 0 | FinOps Alerts |
| gp3 Adoption | 100% | 97% (14/14 PVCs) | FinOps Alerts |
| Budget Alert Fires | 0 | 0 | FinOps Alerts |

### Quarterly Review

Review FinOps savings realized:

```bash
# Generate savings report
grep "Savings:" docs/logbook/*.md | \
  awk -F': ' '{sum+=$3} END {print "Total: R$ " sum "/ano"}'
```

**Q1 2026 Savings:** R$ 30.636/ano realized

---

## 🚨 Alerting Rules

### Budget Alert (Prometheus Alert)

```yaml
# prometheus-alerts/finops-budget.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: finops-budget-alert
  namespace: monitoring
  labels:
    prometheus: kube-prometheus-stack
data:
  finops-budget-alert.yaml: |
    groups:
    - name: finops
      interval: 1h
      rules:
      - alert: MonthlyBudgetExceeded85
        expr: (cloudwatch_aws_billing_estimated_charges_sum / 900) * 100 > 85
        for: 15m
        labels:
          severity: warning
          team: finops
        annotations:
          summary: "Monthly budget exceeded 85% ({{ $value }}%)"
          description: "Staging environment has used {{ $value }}% of $900 monthly budget"

      - alert: MonthlyBudgetExceeded95
        expr: (cloudwatch_aws_billing_estimated_charges_sum / 900) * 100 > 95
        for: 5m
        labels:
          severity: critical
          team: finops
        annotations:
          summary: "Monthly budget exceeded 95% ({{ $value }}%)"
          description: "CRITICAL: Staging environment has used {{ $value }}% of $900 monthly budget. Review costs immediately."
```

### Deploy Alert

```bash
kubectl apply -f prometheus-alerts/finops-budget.yaml
```

---

## 🔍 Troubleshooting

### Dashboard not showing data

**Symptom:** Panels show "No data"

**Diagnosis:**
1. Check CloudWatch datasource configured
2. Verify IAM permissions for CloudWatch read
3. Check Prometheus metrics available

```bash
# Test CloudWatch access
kubectl exec -n monitoring kube-prometheus-stack-grafana-xxx -- \
  curl -s http://localhost:3000/api/datasources/proxy/1/api/v1/query?query=up | jq .

# Check Prometheus metrics
kubectl port-forward -n monitoring prometheus-kube-prometheus-stack-prometheus-0 9090
curl http://localhost:9090/api/v1/query?query=up | jq .
```

**Resolution:**
- Ensure CloudWatch datasource UID matches dashboard JSON (`"uid": "cloudwatch"`)
- Verify IRSA role for Grafana has `cloudwatch:GetMetricStatistics` permission

---

### Dashboard update not reflecting

**Symptom:** Edited JSON but Grafana shows old version

**Diagnosis:**
1. Check ConfigMap updated
2. Check sidecar logs

```bash
# Verify ConfigMap content
kubectl get configmap -n monitoring grafana-dashboard-aws-costs-overview \
  -o jsonpath='{.data.aws-costs-overview\.json}' | jq '.panels[0].title'

# Check sidecar logs
kubectl logs -n monitoring kube-prometheus-stack-grafana-xxx -c grafana-sc-dashboard
```

**Resolution:**
- Sidecar auto-reload every 60s
- Force reload: Delete pod `kubectl delete pod -n monitoring kube-prometheus-stack-grafana-xxx`

---

## 📚 References

- **Terraform Module:** [modules/observability/main.tf](../../platform-provisioning/aws/kubernetes/terraform/modules/observability/main.tf)
- **Dashboard JSONs:** [modules/observability/grafana-dashboards/](../../platform-provisioning/aws/kubernetes/terraform/modules/observability/grafana-dashboards/)
- **Grafana Docs:** [grafana.com/docs/grafana/latest/dashboards/](https://grafana.com/docs/grafana/latest/dashboards/)
- **Prometheus Metrics:** [prometheus.io/docs/prometheus/latest/querying/basics/](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- **CloudWatch Billing:** [docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/gs_monitor_estimated_charges_with_cloudwatch.html](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/gs_monitor_estimated_charges_with_cloudwatch.html)

---

## 🚀 Future Enhancements

### Planned (Q1 2026)

1. **Automated Cost Anomaly Detection**
   - ML-based spike detection
   - Auto-alert on anomalous spend patterns

2. **Per-Namespace Cost Allocation**
   - Break down costs by Kubernetes namespace
   - Chargeback reports per team

3. **Spot Instance Savings Tracking**
   - Dashboard panel for Spot vs On-Demand savings
   - Interruption rate metrics

4. **Forecasting Panel**
   - Predict month-end cost based on current trend
   - Linear regression on daily cost rate

### Considered but Deferred

- **AWS Cost Explorer Integration:** CloudWatch Billing sufficient for now
- **Real-time cost updates:** Hourly CloudWatch sufficient (vs real-time $$$)

---

**Maintainer:** Platform Team
**Last Review:** 2026-02-13
**Next Review:** 2026-03-13 (monthly)
