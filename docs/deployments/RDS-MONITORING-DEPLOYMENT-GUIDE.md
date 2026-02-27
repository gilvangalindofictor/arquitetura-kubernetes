# RDS Monitoring Deployment Guide

**Version:** 1.0
**Date:** 2026-02-27
**Estimated Time:** 45 minutes
**Prerequisites:** AWS CLI, kubectl, Terraform 1.5+

---

## Overview

This guide deploys comprehensive RDS PostgreSQL monitoring to prevent silent database outages.

**Components:**
- CloudWatch Alarms (6 alerts): RDS instance stopped, CPU, connections, storage, latency
- Prometheus Alerts (6 alerts): Application-level connectivity detection
- Grafana Dashboard: Unified RDS health + dependent services view
- Runbook: Step-by-step incident response procedures

**Architecture:** Multi-layer monitoring (CloudWatch + Prometheus + Grafana)

**Related Documentation:**
- ADR-089: RDS Availability Monitoring (decision rationale)
- Runbook: `docs/runbooks/rds-monitoring-alerts-response.md`

---

## Pre-Deployment Checklist

### Required Information

- [ ] RDS instance identifier: `k8s-platform-prod-postgresql`
- [ ] RDS instance class: `db.t3.medium` (max_connections = 147)
- [ ] RDS region: `us-east-1`
- [ ] Alert email addresses: (add to `terraform.tfvars`)
- [ ] AWS CLI profile: `k8s-platform-prod`
- [ ] kubectl context: `k8s-platform-prod`

### Verify RDS Instance Exists

```bash
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus,Engine,EngineVersion]' \
  --output table \
  --region us-east-1 \
  --profile k8s-platform-prod

# Expected output:
# k8s-platform-prod-postgresql | db.t3.medium | available | postgres | 16.x
```

### Verify Kubernetes Cluster Access

```bash
kubectl cluster-info
kubectl get nodes

# Expected: EKS cluster k8s-platform-prod (3 node groups)
```

### Verify Prometheus/Grafana Installed

```bash
kubectl get pods -n staging-observability-monitoring | grep -E "prometheus|grafana"

# Expected:
# kube-prometheus-stack-prometheus-0
# kube-prometheus-stack-grafana-xxx
```

---

## Phase 1: Deploy CloudWatch Alarms (Terraform)

**Duration:** 15 minutes

### Step 1: Update Terraform Variables

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging

# Edit terraform.tfvars - add alert email
vim terraform.tfvars
```

**Add/Update:**

```hcl
# RDS Monitoring Alert Email (reuses FinOps email if not already set)
finops_alert_email = "devops@example.com"  # Replace with your email

# Optional: Add additional RDS-specific emails
# rds_alert_emails = ["sre-team@example.com", "database-team@example.com"]
```

### Step 2: Review Module Configuration

```bash
# Review RDS monitoring module
cat /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/modules/rds-monitoring/main.tf | less

# Review staging environment integration
cat /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging/rds-monitoring.tf
```

**Key Configuration:**
- `rds_instance_identifier`: `k8s-platform-prod-postgresql`
- `enable_performance_alerts`: `true` (all 6 alarms)
- `cpu_threshold`: `80` (percentage)
- `max_connections_override`: `147` (db.t3.medium PostgreSQL 16)
- `storage_threshold_gb`: `20` (GB free)
- `latency_threshold_ms`: `50` (milliseconds)

### Step 3: Terraform Plan

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging

# Initialize (if first time)
terraform init

# Plan changes
terraform plan -target=module.rds_monitoring_staging

# Expected resources to create:
# - aws_sns_topic.rds_alerts (1)
# - aws_sns_topic_policy.rds_alerts (1)
# - aws_sns_topic_subscription.email (1-N, based on email count)
# - aws_cloudwatch_metric_alarm.rds_stopped (1)
# - aws_cloudwatch_metric_alarm.rds_high_cpu (1)
# - aws_cloudwatch_metric_alarm.rds_high_connections (1)
# - aws_cloudwatch_metric_alarm.rds_low_storage (1)
# - aws_cloudwatch_metric_alarm.rds_high_read_latency (1)
# - aws_cloudwatch_metric_alarm.rds_high_write_latency (1)
# - aws_db_event_subscription.rds_instance_events (1)
# Total: ~10 resources
```

### Step 4: Terraform Apply

```bash
terraform apply -target=module.rds_monitoring_staging

# Review plan output
# Type 'yes' to confirm
```

**Expected Output:**

```
module.rds_monitoring_staging.aws_sns_topic.rds_alerts: Creating...
module.rds_monitoring_staging.aws_sns_topic.rds_alerts: Creation complete
module.rds_monitoring_staging.aws_cloudwatch_metric_alarm.rds_stopped: Creating...
...
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.

Outputs:
rds_monitoring_sns_topic_arn = "arn:aws:sns:us-east-1:891377105802:staging-rds-alerts"
rds_monitoring_alarm_arns = {
  rds_stopped = "arn:aws:cloudwatch:us-east-1:891377105802:alarm:staging-rds-instance-stopped"
  ...
}
```

### Step 5: CRITICAL - Confirm SNS Email Subscriptions

**Action Required:** Check email inbox for SNS subscription confirmation emails.

```
Subject: AWS Notification - Subscription Confirmation
From: no-reply@sns.amazonaws.com

You have chosen to subscribe to the topic:
arn:aws:sns:us-east-1:891377105802:staging-rds-alerts

To confirm this subscription, click or visit the link below:
https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=...
```

**IMPORTANT:** Click "Confirm subscription" link in email. Alerts will NOT be delivered until confirmed!

**Verify Subscription Status:**

```bash
# Check SNS subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw rds_monitoring_sns_topic_arn) \
  --region us-east-1 \
  --profile k8s-platform-prod

# Expected output (SubscriptionArn should NOT be "PendingConfirmation"):
# {
#     "Subscriptions": [
#         {
#             "SubscriptionArn": "arn:aws:sns:us-east-1:891377105802:staging-rds-alerts:xxx",
#             "Protocol": "email",
#             "Endpoint": "devops@example.com"
#         }
#     ]
# }
```

### Step 6: Test CloudWatch Alarm

```bash
# Manually trigger alarm to test email delivery
aws cloudwatch set-alarm-state \
  --alarm-name staging-rds-instance-stopped \
  --state-value ALARM \
  --state-reason "Manual test of RDS monitoring alert system" \
  --region us-east-1 \
  --profile k8s-platform-prod

# Expected: Email notification received within 1 minute

# Reset alarm to OK
aws cloudwatch set-alarm-state \
  --alarm-name staging-rds-instance-stopped \
  --state-value OK \
  --state-reason "Test complete" \
  --region us-east-1 \
  --profile k8s-platform-prod

# Expected: "OK" email notification received
```

**Email Format:**

```
Subject: ALARM: "staging-rds-instance-stopped" in US East (N. Virginia)

You are receiving this email because your Amazon CloudWatch Alarm "staging-rds-instance-stopped" in the US East (N. Virginia) region has entered the ALARM state...

Alarm Details:
- Name: staging-rds-instance-stopped
- Description: CRITICAL: RDS instance is stopped. GitLab/Keycloak/SonarQube will fail...
- State Change: OK -> ALARM
- Reason: Manual test of RDS monitoring alert system
```

---

## Phase 2: Deploy Prometheus Alerts

**Duration:** 10 minutes

### Step 1: Review Prometheus Alerts

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes

# Review alert definitions
cat domains/observability/infra/alerts/rds-connectivity-alerts.yaml | less

# Key alerts:
# - GitLabRDSConnectivityFailure (CRITICAL, for: 5m)
# - KeycloakRDSConnectivityFailure (CRITICAL, for: 3m)
# - SonarQubeRDSConnectivityFailure (WARNING, for: 5m)
# - RDSPostgreSQLPlatformWideOutage (CRITICAL, for: 2m, pager=true)
# - PostgreSQLExporterDown (WARNING, for: 5m)
```

### Step 2: Deploy PrometheusRule CRD

```bash
kubectl apply -f domains/observability/infra/alerts/rds-connectivity-alerts.yaml

# Expected output:
# prometheusrule.monitoring.coreos.com/rds-connectivity-alerts created
```

### Step 3: Verify PrometheusRule Loaded

```bash
# Check PrometheusRule CRD created
kubectl get prometheusrules -n staging-observability-monitoring rds-connectivity-alerts

# Expected output:
# NAME                       AGE
# rds-connectivity-alerts    10s

# View detailed configuration
kubectl get prometheusrules -n staging-observability-monitoring rds-connectivity-alerts -o yaml
```

### Step 4: Verify Prometheus Loaded Rules

```bash
# Port-forward Prometheus UI
kubectl port-forward -n staging-observability-monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &

# Open browser: http://localhost:9090/alerts
# Search for: "RDS" or "GitLab" or "Keycloak"

# Expected: 6 new alert rules visible
# - GitLabRDSConnectivityFailure (Inactive)
# - KeycloakRDSConnectivityFailure (Inactive)
# - SonarQubeRDSConnectivityFailure (Inactive)
# - ArgoCDRDSConnectivityIssue (Inactive)
# - RDSPostgreSQLPlatformWideOutage (Inactive)
# - PostgreSQLExporterDown (Inactive or Pending)

# Stop port-forward
pkill -f "port-forward.*9090"
```

**Troubleshooting: Rules Not Appearing**

```bash
# Check Prometheus logs for errors
kubectl logs -n staging-observability-monitoring kube-prometheus-stack-prometheus-0 | grep -i "error\|rds-connectivity"

# Common errors:
# - "invalid expr" → YAML syntax error in alert rule
# - "group not found" → PrometheusRule label selector mismatch

# Verify label selectors
kubectl get prometheusrules -n staging-observability-monitoring rds-connectivity-alerts -o jsonpath='{.metadata.labels}'

# Expected labels:
# prometheus: kube-prometheus-stack-prometheus
# release: kube-prometheus-stack
# role: alert-rules
```

### Step 5: Test Prometheus Alert (Simulated Failure)

```bash
# Create test pod that simulates GitLab webservice stuck in Init
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-gitlab-init-stuck
  namespace: staging-platform-gitlab
  labels:
    app: webservice
    component: webservice
spec:
  initContainers:
    - name: configure-secrets
      image: busybox
      command: ['sh', '-c', 'sleep 600']  # Stuck in Init for 10 minutes
  containers:
    - name: webservice
      image: nginx
EOF

# Wait 5 minutes for alert to fire
sleep 300

# Check alert status in Prometheus
# Navigate to: http://localhost:9090/alerts
# Expected: GitLabRDSConnectivityFailure = FIRING (after 5 minutes)

# Cleanup test pod
kubectl delete pod -n staging-platform-gitlab test-gitlab-init-stuck
```

---

## Phase 3: Deploy Grafana Dashboard

**Duration:** 10 minutes

### Step 1: Review Dashboard Configuration

```bash
# Review dashboard ConfigMap
cat domains/observability/infra/grafana/rds-monitoring-dashboard-configmap.yaml | less

# Dashboard features:
# - 8 panels: RDS status, connections, CPU, storage, latency, service health, alerts
# - Data sources: CloudWatch (RDS metrics), Prometheus (pod health)
# - Auto-refresh: 30 seconds
# - Links: AWS Console, runbook
```

### Step 2: Deploy Dashboard ConfigMap

```bash
kubectl apply -f domains/observability/infra/grafana/rds-monitoring-dashboard-configmap.yaml

# Expected output:
# configmap/rds-monitoring-dashboard created
```

### Step 3: Verify Grafana Auto-Import

Grafana sidecar automatically imports dashboards with label `grafana_dashboard: "1"`.

```bash
# Check ConfigMap created with correct label
kubectl get configmap -n staging-observability-monitoring rds-monitoring-dashboard -o jsonpath='{.metadata.labels}' | grep grafana_dashboard

# Expected: grafana_dashboard: "1"

# Wait 30-60 seconds for sidecar to detect and import dashboard
sleep 60
```

### Step 4: Access Grafana Dashboard

```bash
# Port-forward Grafana
kubectl port-forward -n staging-observability-monitoring svc/kube-prometheus-stack-grafana 3000:80 &

# Get Grafana admin password
kubectl get secret -n staging-observability-monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
echo

# Open browser: http://localhost:3000
# Login: admin / <password>
# Navigate: Dashboards → Browse → Search "RDS PostgreSQL Monitoring"
```

### Step 5: Configure CloudWatch Data Source (If Not Exists)

**Check if CloudWatch datasource exists:**

Navigate to: Configuration → Data Sources

If "CloudWatch" data source exists:
- ✅ Skip to Step 6 (dashboard should load data)

If "CloudWatch" data source missing:

1. Click "Add data source"
2. Select "CloudWatch"
3. Configure:
   - Name: `cloudwatch`
   - Authentication Provider: `AWS SDK Default`
   - Default Region: `us-east-1`
4. Click "Save & Test"

**Expected:** "Data source is working" message

### Step 6: Verify Dashboard Panels Loading

**Panel Checklist:**

1. **RDS Instance Status** (Stat):
   - Should show "1" (green) if RDS running
   - Should show "0" (red) if RDS stopped
   - Data source: CloudWatch, Metric: `DatabaseConnections`

2. **Database Connections** (Time series):
   - Should show line graph (0-147 scale)
   - Current connections visible
   - Data source: CloudWatch

3. **CPU Utilization** (Time series):
   - Should show 0-100% graph
   - Threshold line at 80%
   - Data source: CloudWatch

4. **Free Storage** (Time series):
   - Should show bytes remaining
   - Threshold line at 20GB
   - Data source: CloudWatch

5. **Read/Write Latency** (Time series):
   - Should show 2 lines (read, write)
   - Threshold line at 50ms (0.05s)
   - Data source: CloudWatch

6. **GitLab Health** (Stat):
   - Should show "1" (green) if GitLab healthy
   - Data source: Prometheus

7. **Active RDS-Related Alerts** (Table):
   - Should show current firing alerts (if any)
   - Data source: Prometheus

**Troubleshooting: Panels Show "No Data"**

**CloudWatch Panels:**

```bash
# Verify CloudWatch datasource configured
# Check AWS CLI can access CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=k8s-platform-prod-postgresql \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-east-1 \
  --profile k8s-platform-prod

# If data returned: Grafana datasource misconfigured
# If no data: RDS might be stopped or metrics delayed
```

**Prometheus Panels:**

```bash
# Test Prometheus query
curl -s 'http://localhost:9090/api/v1/query?query=kube_pod_status_phase{namespace="staging-platform-gitlab"}' | jq

# If data returned: Dashboard query syntax error
# If no data: kube-state-metrics not running
```

---

## Phase 4: Runbook Distribution

**Duration:** 5 minutes

### Step 1: Review Runbook

```bash
# Review comprehensive runbook
cat docs/runbooks/rds-monitoring-alerts-response.md | less

# Sections:
# - Critical alerts: RDS stopped, platform outage, GitLab/Keycloak connectivity
# - Warning alerts: High CPU, connections, storage, latency
# - Diagnostic decision trees
# - Step-by-step remediation procedures
# - Escalation matrix
# - Post-incident actions
```

### Step 2: Update Runbook URLs

**Action Required:** Replace placeholder URLs with actual values.

```bash
# Edit runbook
vim docs/runbooks/rds-monitoring-alerts-response.md

# Find and replace:
# - https://github.com/<org>/<repo> → Your actual GitHub org/repo
# - devops@example.com → Your actual team email
# - #platform-alerts → Your actual Slack channel
# - https://grafana.staging.internal → Your actual Grafana URL
```

### Step 3: Distribute Runbook

1. **Add to Team Wiki:**
   - Upload `rds-monitoring-alerts-response.md` to Confluence/Notion
   - Tag: "Runbook", "RDS", "Incident Response", "P1"

2. **Add to On-Call Playbook:**
   - Link runbook in PagerDuty/OpsGenie incident template
   - Include in on-call engineer onboarding checklist

3. **Team Walkthrough:**
   - Schedule 30-minute team meeting
   - Walk through critical alert procedures
   - Practice RDS start command

---

## Phase 5: Testing & Validation

**Duration:** 15 minutes

### Test 1: CloudWatch Alarm Notification

**Already completed in Phase 1, Step 6.** ✅

### Test 2: Prometheus Alert Firing

**Already completed in Phase 2, Step 5.** ✅

### Test 3: End-to-End Outage Simulation (OPTIONAL, HIGH RISK)

**⚠️ CAUTION:** This test stops RDS, causing platform-wide outage. Only run during planned maintenance window.

```bash
# Pre-requisites:
# - [ ] Scheduled maintenance window (30 minutes)
# - [ ] Team notified (no production work during test)
# - [ ] Backup verification complete
# - [ ] Rollback plan confirmed

# Step 1: Stop RDS
aws rds stop-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --profile k8s-platform-prod

# Expected timeline:
# T+0: RDS status = "stopping"
# T+1min: CloudWatch alarm fires (email received)
# T+3min: GitLab webservice stuck in Init:2/3
# T+5min: Prometheus alert "GitLabRDSConnectivityFailure" fires
# T+5min: Keycloak pods CrashLoopBackOff
# T+5min: Prometheus alert "RDSPostgreSQLPlatformWideOutage" fires

# Step 2: Monitor alerts
watch -n 5 'kubectl get pods -A | grep -E "gitlab-webservice|keycloak|sonarqube"'

# Step 3: Verify Grafana dashboard
# Open: http://localhost:3000/d/rds-monitoring
# Expected: RDS Status panel shows "STOPPED" (red)

# Step 4: Start RDS (Follow runbook procedure)
aws rds start-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --profile k8s-platform-prod

# Expected timeline:
# T+0: RDS status = "starting"
# T+3-5min: RDS status = "available"
# T+3-5min: CloudWatch alarm clears (OK email received)
# T+4-6min: GitLab webservice Init → Running
# T+4-6min: Keycloak CrashLoop → Running
# T+6-8min: Prometheus alerts clear

# Step 5: Verify service recovery
curl -I https://gitlab.staging.internal  # Expected: HTTP 200
curl -I https://keycloak.staging.internal/auth/realms/platform  # Expected: HTTP 200
```

**Test Results Documentation:**

Record results in `docs/deployments/RDS-MONITORING-TEST-RESULTS.md`:

```markdown
# RDS Monitoring Test Results

**Date:** 2026-02-27
**Test Type:** End-to-End Outage Simulation
**Duration:** 15 minutes (RDS stopped to full recovery)

## Timeline

| Time | Event | Status |
|------|-------|--------|
| 14:00:00 | RDS stop initiated | ✅ |
| 14:01:15 | CloudWatch alarm fired | ✅ Email received |
| 14:03:30 | GitLab pods stuck in Init | ✅ |
| 14:05:00 | Prometheus GitLab alert fired | ✅ |
| 14:05:45 | Keycloak CrashLoopBackOff | ✅ |
| 14:06:00 | Prometheus platform-wide alert fired | ✅ |
| 14:07:00 | RDS start initiated | ✅ |
| 14:11:30 | RDS available | ✅ |
| 14:12:00 | GitLab webservice Running | ✅ |
| 14:12:30 | Keycloak Running | ✅ |
| 14:13:00 | Prometheus alerts cleared | ✅ |
| 14:15:00 | Service recovery verified | ✅ |

## Metrics

- **MTTD** (Mean Time To Detect): 1 minute 15 seconds (target: <2min) ✅
- **MTTR** (Mean Time To Resolve): 15 minutes (target: <15min) ✅
- **Alert Accuracy**: 100% (all expected alerts fired)
- **False Positives**: 0

## Issues Found

None. All systems performed as expected.

## Action Items

- [ ] Update team wiki with runbook link
- [ ] Schedule quarterly monitoring review
```

---

## Post-Deployment Verification

### Checklist

- [ ] **CloudWatch Alarms:**
  - [ ] 6 alarms created (`aws cloudwatch describe-alarms --alarm-name-prefix staging-rds`)
  - [ ] SNS topic created (`aws sns list-topics | grep rds-alerts`)
  - [ ] Email subscriptions confirmed (SubscriptionArn != "PendingConfirmation")
  - [ ] Test alarm fired and email received
  - [ ] RDS event subscription created (`aws rds describe-event-subscriptions`)

- [ ] **Prometheus Alerts:**
  - [ ] PrometheusRule CRD deployed (`kubectl get prometheusrules -n staging-observability-monitoring`)
  - [ ] 6 alert rules visible in Prometheus UI
  - [ ] Test alert fired (simulated pod stuck in Init)

- [ ] **Grafana Dashboard:**
  - [ ] ConfigMap deployed with `grafana_dashboard: "1"` label
  - [ ] Dashboard auto-imported and visible in Grafana UI
  - [ ] All 8 panels loading data (CloudWatch + Prometheus)
  - [ ] Links to AWS Console and runbook working

- [ ] **Documentation:**
  - [ ] Runbook reviewed and URLs updated
  - [ ] Runbook added to team wiki
  - [ ] ADR-089 reviewed and approved
  - [ ] Deployment guide completed

### Monitoring Health Check

Run daily for first week:

```bash
#!/bin/bash
# File: scripts/monitoring/rds-health-check.sh

echo "=== RDS Monitoring Health Check ==="
echo ""

# 1. CloudWatch Alarms
echo "1. CloudWatch Alarms:"
aws cloudwatch describe-alarms \
  --alarm-name-prefix staging-rds \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table \
  --region us-east-1 \
  --profile k8s-platform-prod

echo ""

# 2. SNS Subscriptions
echo "2. SNS Subscriptions:"
SNS_TOPIC_ARN=$(terraform output -raw rds_monitoring_sns_topic_arn 2>/dev/null)
if [ -n "$SNS_TOPIC_ARN" ]; then
  aws sns list-subscriptions-by-topic \
    --topic-arn $SNS_TOPIC_ARN \
    --query 'Subscriptions[*].[Protocol,Endpoint,SubscriptionArn]' \
    --output table \
    --region us-east-1 \
    --profile k8s-platform-prod
else
  echo "ERROR: SNS topic ARN not found"
fi

echo ""

# 3. Prometheus Rules
echo "3. Prometheus Rules:"
kubectl get prometheusrules -n staging-observability-monitoring rds-connectivity-alerts -o jsonpath='{.status}' 2>/dev/null
if [ $? -eq 0 ]; then
  echo "✅ PrometheusRule loaded"
else
  echo "❌ PrometheusRule not found"
fi

echo ""

# 4. Grafana Dashboard
echo "4. Grafana Dashboard:"
kubectl get configmap -n staging-observability-monitoring rds-monitoring-dashboard -o jsonpath='{.metadata.labels.grafana_dashboard}' 2>/dev/null
if [ $? -eq 0 ]; then
  echo "✅ Dashboard ConfigMap deployed"
else
  echo "❌ Dashboard ConfigMap not found"
fi

echo ""
echo "=== Health Check Complete ==="
```

---

## Rollback Procedure

If issues occur, rollback in reverse order:

### 1. Remove Grafana Dashboard

```bash
kubectl delete configmap -n staging-observability-monitoring rds-monitoring-dashboard
```

### 2. Remove Prometheus Alerts

```bash
kubectl delete prometheusrule -n staging-observability-monitoring rds-connectivity-alerts
```

### 3. Remove CloudWatch Alarms (Terraform)

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging

terraform destroy -target=module.rds_monitoring_staging

# Type 'yes' to confirm

# Expected: 10 resources destroyed (alarms, SNS topic, event subscription)
```

---

## Troubleshooting

### Issue: CloudWatch Alarm Not Firing

**Symptom:** RDS stopped, but no email notification received

**Causes:**
1. SNS subscription not confirmed
2. Email in spam folder
3. Alarm in INSUFFICIENT_DATA state

**Solutions:**

```bash
# 1. Check subscription status
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw rds_monitoring_sns_topic_arn) \
  --region us-east-1 \
  --profile k8s-platform-prod

# If SubscriptionArn = "PendingConfirmation":
# → Check email inbox for confirmation link

# 2. Check alarm state
aws cloudwatch describe-alarms \
  --alarm-names staging-rds-instance-stopped \
  --region us-east-1 \
  --profile k8s-platform-prod

# If StateValue = "INSUFFICIENT_DATA":
# → Alarm needs 1 evaluation period (1 minute) to collect data
# → Wait 2 minutes and check again

# 3. Manually trigger alarm (test)
aws cloudwatch set-alarm-state \
  --alarm-name staging-rds-instance-stopped \
  --state-value ALARM \
  --state-reason "Manual test" \
  --region us-east-1 \
  --profile k8s-platform-prod
```

### Issue: Prometheus Alert Not Firing

**Symptom:** Pod stuck in Init, but no Prometheus alert

**Causes:**
1. PrometheusRule not loaded (label selector mismatch)
2. Alert evaluation period not elapsed (`for: 5m`)
3. kube-state-metrics not running

**Solutions:**

```bash
# 1. Check PrometheusRule loaded
kubectl get prometheusrules -n staging-observability-monitoring rds-connectivity-alerts -o yaml

# Verify labels match Prometheus selector:
# prometheus: kube-prometheus-stack-prometheus
# release: kube-prometheus-stack
# role: alert-rules

# 2. Check Prometheus logs
kubectl logs -n staging-observability-monitoring kube-prometheus-stack-prometheus-0 | grep -i error

# 3. Check kube-state-metrics running
kubectl get pods -n staging-observability-monitoring | grep kube-state-metrics

# If not running:
kubectl rollout restart deployment/kube-prometheus-stack-kube-state-metrics -n staging-observability-monitoring
```

### Issue: Grafana Dashboard Not Loading Data

**Symptom:** Dashboard panels show "No Data"

**Causes:**
1. CloudWatch datasource not configured
2. AWS credentials missing (for CloudWatch datasource)
3. Dashboard query syntax error

**Solutions:**

```bash
# 1. Check CloudWatch datasource exists
# Navigate to: Grafana UI → Configuration → Data Sources
# Look for: "CloudWatch" datasource

# 2. Test CloudWatch datasource
# Click: Data Sources → CloudWatch → "Save & Test"
# Expected: "Data source is working"

# 3. Check Grafana logs
kubectl logs -n staging-observability-monitoring deployment/kube-prometheus-stack-grafana | grep -i "cloudwatch\|error"

# 4. Manually test CloudWatch query
# Open: Grafana → Explore → Select "CloudWatch" datasource
# Namespace: AWS/RDS
# Metric: DatabaseConnections
# Dimension: DBInstanceIdentifier = k8s-platform-prod-postgresql
```

---

## Next Steps

1. **Week 1:** Monitor alert volume, tune thresholds if needed
2. **Week 2:** Conduct runbook walkthrough with team
3. **Week 4:** Review MTTD/MTTR metrics, document lessons learned
4. **Month 3:** Quarterly monitoring review (ADR-089 revisit)

---

## Support

**Documentation:**
- ADR-089: `docs/adr/adr-089-rds-availability-monitoring.md`
- Runbook: `docs/runbooks/rds-monitoring-alerts-response.md`
- Terraform Module: `platform-provisioning/.../modules/rds-monitoring/README.md`

**Contacts:**
- Platform SRE Team: #platform-sre (Slack)
- On-Call Engineer: PagerDuty
- AWS Support: Premium Support case (for RDS infrastructure issues)

---

**Document Version:** 1.0 (2026-02-27)
