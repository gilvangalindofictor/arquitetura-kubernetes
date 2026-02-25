# Grafana Dashboards for K8s Platform Monitoring

This directory contains Grafana dashboard definitions for monitoring critical platform services.

## Available Dashboards

### Velero Backup & Restore Monitoring

**File**: `velero-backup-monitoring.json`
**UID**: `velero-backup-monitoring`
**Tags**: velero, backup, disaster-recovery

Comprehensive dashboard for monitoring Velero backup and restore operations with real-time metrics from Prometheus.

#### Features

##### Success Rate Monitoring
- **24h/7d/30d Success Rate Gauges**: Visual representation of backup reliability over time
  - Green: ≥99% success rate
  - Yellow: 95-99% success rate
  - Red: <95% success rate

##### Duration and Performance Tracking
- **Backup Duration Trends**: Monitor backup execution time across schedules
- **Last Backup Duration**: Quick view of most recent backup performance
- **Backup Operations Rate**: Success vs failure trends over time

##### Storage and Capacity Metrics
- **Total S3 Backup Storage Usage**: Current backup storage consumption
  - Green: <100GB
  - Yellow: 100-500GB
  - Red: >500GB
- **Backup Tarball Size Trends**: Track backup size growth over time
- **Backup Size Trends (Items)**: Number of items backed up per schedule

##### Operational Insights
- **Last Successful Backup per Schedule**: Timestamp table showing last successful backup for each schedule
- **Failed Backups Table**: Detailed view of failed backups in last 24h (auto-filtered)
- **Restore Operations**: Success/Failed/PartiallyFailed restore tracking
- **Velero Pod Health Status**: Current status of Velero pods

##### Statistics
- **Successful Backups (24h)**: Total successful backups in last 24 hours
- **Failed Backups (24h)**: Total failed backups in last 24 hours (red if >0)

#### Dashboard Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `datasource` | Datasource | Prometheus datasource selector | Prometheus |
| `namespace` | Query | Velero namespace filter | velero |
| `schedule` | Query (multi-select) | Backup schedule filter | All |

#### Metrics Used

The dashboard uses the following Velero Prometheus metrics:

| Metric | Type | Description |
|--------|------|-------------|
| `velero_backup_success_total` | Counter | Total number of successful backups |
| `velero_backup_failure_total` | Counter | Total number of failed backups |
| `velero_backup_duration_seconds` | Gauge | Duration of last backup operation |
| `velero_backup_total_items` | Gauge | Total items in backup |
| `velero_backup_tarball_size_bytes` | Gauge | Size of backup tarball in bytes |
| `velero_backup_last_successful_timestamp` | Gauge | Unix timestamp of last successful backup |
| `velero_restore_success_total` | Counter | Total number of successful restores |
| `velero_restore_failed_total` | Counter | Total number of failed restores |
| `velero_restore_partial_failure_total` | Counter | Total number of partially failed restores |
| `up{job="velero"}` | Gauge | Velero pod health status |

**Source**: [Velero Metrics Documentation](https://github.com/vmware-tanzu/velero/blob/main/pkg/metrics/metrics.go)

## Deployment

### Automated Deployment (Recommended)

Deploy the dashboard using the ConfigMap manifest:

```bash
# Apply the ConfigMap to monitoring namespace
kubectl apply -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/kubectl-manifests/monitoring/velero-dashboard-cm.yaml

# Verify ConfigMap creation
kubectl get configmap velero-dashboard -n monitoring

# Check Grafana sidecar logs for dashboard provisioning
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard
```

The Grafana sidecar will automatically detect the ConfigMap (labeled with `grafana_dashboard: "1"`) and provision the dashboard.

**Verification**:
1. Access Grafana UI
2. Navigate to Dashboards → Browse
3. Search for "Velero Backup & Restore Monitoring"
4. Verify all panels display data

### Manual Import

If automated provisioning fails or for testing purposes:

1. Copy contents of `velero-backup-monitoring.json`
2. In Grafana UI, go to Dashboards → Import
3. Paste JSON content
4. Select Prometheus datasource
5. Click "Import"

## Alert Configuration

### Recommended PrometheusRule Alerts

Create alerts based on the dashboard metrics to ensure proactive monitoring:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: velero-backup-alerts
  namespace: velero
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: velero.backup
    interval: 5m
    rules:
    # Critical: Backup failure detected
    - alert: VeleroBackupFailure
      expr: increase(velero_backup_failure_total[1h]) > 0
      for: 5m
      labels:
        severity: critical
        component: velero
      annotations:
        summary: "Velero backup failed"
        description: "Backup schedule {{ $labels.schedule }} in namespace {{ $labels.namespace }} has failed {{ $value }} times in the last hour"

    # Warning: Low backup success rate
    - alert: VeleroBackupSuccessRateLow
      expr: |
        (sum(increase(velero_backup_success_total[24h])) /
        (sum(increase(velero_backup_success_total[24h])) +
         sum(increase(velero_backup_failure_total[24h])))) * 100 < 95
      for: 1h
      labels:
        severity: warning
        component: velero
      annotations:
        summary: "Velero backup success rate below 95%"
        description: "Backup success rate is {{ $value | humanizePercentage }} over the last 24 hours (threshold: 95%)"

    # Warning: No recent successful backup
    - alert: VeleroBackupStale
      expr: time() - velero_backup_last_successful_timestamp > 86400
      for: 1h
      labels:
        severity: warning
        component: velero
      annotations:
        summary: "Velero backup schedule has not succeeded recently"
        description: "Backup schedule {{ $labels.schedule }} has not completed successfully in over 24 hours (last success: {{ $value | humanizeDuration }} ago)"

    # Warning: Backup duration increasing
    - alert: VeleroBackupDurationHigh
      expr: velero_backup_duration_seconds > 3600
      for: 15m
      labels:
        severity: warning
        component: velero
      annotations:
        summary: "Velero backup taking too long"
        description: "Backup schedule {{ $labels.schedule }} took {{ $value | humanizeDuration }} to complete (threshold: 1h)"

    # Warning: S3 storage usage high
    - alert: VeleroS3StorageHigh
      expr: sum(velero_backup_tarball_size_bytes) > 500000000000
      for: 1h
      labels:
        severity: warning
        component: velero
      annotations:
        summary: "Velero S3 backup storage usage high"
        description: "Total backup storage is {{ $value | humanize1024 }} (threshold: 500GB). Review retention policies."

    # Critical: Velero pod down
    - alert: VeleroPodDown
      expr: up{job="velero"} == 0
      for: 5m
      labels:
        severity: critical
        component: velero
      annotations:
        summary: "Velero pod is down"
        description: "Velero pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is not responding to health checks"

    # Warning: Restore failure
    - alert: VeleroRestoreFailure
      expr: increase(velero_restore_failed_total[1h]) > 0
      for: 5m
      labels:
        severity: warning
        component: velero
      annotations:
        summary: "Velero restore operation failed"
        description: "Restore operations have failed {{ $value }} times in the last hour in namespace {{ $labels.namespace }}"
```

**Deployment**:
```bash
kubectl apply -f /path/to/velero-prometheusrule.yaml
```

### Alert Severity Guide

| Severity | Response Time | Description |
|----------|---------------|-------------|
| **Critical** | Immediate (15min) | Backup failures or Velero pod down - immediate action required |
| **Warning** | 1-4 hours | Degraded performance or approaching limits - plan remediation |

### Alert Integration

Ensure alerts are routed to appropriate channels in AlertManager:

```yaml
route:
  routes:
  - receiver: 'platform-team-critical'
    match:
      severity: critical
      component: velero
    continue: false
  - receiver: 'platform-team-warning'
    match:
      severity: warning
      component: velero
    continue: true
```

## Key Metrics to Watch

### Daily Monitoring

1. **Backup Success Rate (24h)**: Should be ≥99%
   - Action if <99%: Review failed backup logs

2. **Last Successful Backup per Schedule**: Should be <24h for daily schedules
   - Action if stale: Check Velero pod logs and schedule configuration

3. **Failed Backups Table**: Should be empty
   - Action if failures: Investigate error messages, check S3 connectivity and credentials

### Weekly Review

1. **Backup Duration Trends**: Monitor for gradual increases
   - Action if increasing: Review backup scope, consider optimization

2. **S3 Storage Usage**: Track growth rate
   - Action if high: Adjust retention policies, clean up old backups

3. **Backup Size Trends**: Ensure proportional to cluster growth
   - Action if unexpected: Investigate data growth, verify backup filters

### Monthly Analysis

1. **Backup Success Rate (30d)**: Long-term reliability metric
   - Target: ≥99.9%

2. **Restore Operations**: Track restore success rate
   - Perform monthly restore testing to validate backups

3. **Velero Pod Health**: Ensure zero downtime
   - Review pod restarts and resource usage

## Troubleshooting

### Dashboard Not Appearing in Grafana

**Symptoms**: Dashboard not visible after applying ConfigMap

**Diagnosis**:
```bash
# Check if ConfigMap exists
kubectl get cm velero-dashboard -n monitoring

# Verify label is correct
kubectl get cm velero-dashboard -n monitoring -o yaml | grep grafana_dashboard

# Check Grafana sidecar logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard --tail=50
```

**Resolution**:
1. Ensure ConfigMap has label `grafana_dashboard: "1"`
2. Verify Grafana deployment has sidecar enabled
3. Check namespace matches Grafana deployment (usually `monitoring`)
4. Restart Grafana pod if needed: `kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring`

### No Data in Dashboard Panels

**Symptoms**: Dashboard loads but panels show "No Data"

**Diagnosis**:
```bash
# Check if Velero ServiceMonitor exists
kubectl get servicemonitor -n velero

# Verify Velero metrics endpoint is accessible
kubectl port-forward -n velero svc/velero 8085:8085
curl http://localhost:8085/metrics

# Check if Prometheus is scraping Velero
# In Grafana, query: up{job="velero"}
```

**Resolution**:
1. Verify Velero is deployed with metrics enabled (default port 8085)
2. Ensure ServiceMonitor exists and has correct label for Prometheus operator
3. Check Prometheus targets: Prometheus UI → Status → Targets → search "velero"
4. Verify network policies allow Prometheus → Velero communication

### Incorrect Metric Values

**Symptoms**: Dashboard shows unexpected values

**Diagnosis**:
```bash
# Query raw metrics from Prometheus
# Example: Check backup success total
curl -g 'http://prometheus:9090/api/v1/query?query=velero_backup_success_total'

# Verify namespace variable matches Velero deployment
kubectl get deployment -n velero
```

**Resolution**:
1. Ensure namespace variable in dashboard matches Velero deployment namespace
2. Verify schedule names match actual backup schedules: `kubectl get schedule -n velero`
3. Check metric retention in Prometheus (default: 15d)

## Related Documentation

- [Velero Official Documentation](https://velero.io/docs/)
- [Velero Prometheus Metrics](https://github.com/vmware-tanzu/velero/blob/main/pkg/metrics/metrics.go)
- [Logbook: V-008 Velero IRSA Implementation](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-25-v008-velero-irsa.md)
- [PrometheusRule CRD Documentation](https://prometheus-operator.dev/docs/operator/api/#monitoring.coreos.com/v1.PrometheusRule)

## Disaster Recovery Targets

Based on the monitoring dashboard, ensure the following targets are met:

| Metric | Target | Current Dashboard Panel |
|--------|--------|-------------------------|
| RPO (Recovery Point Objective) | 24 hours | Last Successful Backup per Schedule |
| RTO (Recovery Time Objective) | 1 hour | Restore Operations panel |
| Backup Success Rate | ≥99% | Success Rate gauges (24h/7d/30d) |
| Maximum Backup Duration | <1 hour | Backup Duration Trends |
| Backup Staleness Alert | <24 hours | Last Successful Backup per Schedule |

---

**Maintained by**: Platform Team
**Last Updated**: 2026-02-25
**Related Task**: V-011 (Velero Monitoring)
