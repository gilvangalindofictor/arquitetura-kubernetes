# OIDC Monitoring Runbook

## Overview

This runbook describes how to use the OIDC monitoring system to detect and troubleshoot authentication issues across Keycloak, GitLab, and ArgoCD.

**Purpose:** Continuously monitor OIDC authentication flows to detect issues before they impact users.

**Coverage:**
- Keycloak (Identity Provider)
- GitLab (OIDC Client)
- ArgoCD (OIDC Client)

**Created:** 2026-02-12
**Last Updated:** 2026-02-12
**Owner:** Platform Team

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                    OIDC Monitor System                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Keycloak    │  │   GitLab     │  │   ArgoCD     │     │
│  │  Namespace   │  │  Namespace   │  │  Namespace   │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                 │                  │              │
│         └─────────────────┼──────────────────┘              │
│                           │                                 │
│                    ┌──────▼──────┐                         │
│                    │ Log Monitor │                          │
│                    │   Script    │                          │
│                    └──────┬──────┘                         │
│                           │                                 │
│         ┌─────────────────┼─────────────────┐              │
│         │                 │                 │              │
│   ┌─────▼─────┐    ┌──────▼──────┐   ┌────▼─────┐        │
│   │   Logs    │    │   Reports   │   │  Slack   │        │
│   │    PVC    │    │  (JSON)     │   │  Alerts  │        │
│   └───────────┘    └─────────────┘   └──────────┘        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Error Detection Patterns

The monitor detects these error patterns:

| Pattern | Regex | Description |
|---------|-------|-------------|
| `login_error` | `LOGIN_ERROR\|login.*error\|authentication.*failed` | Generic login failures |
| `invalid_request` | `invalid_request\|invalid.*client\|client.*not.*found` | Invalid OAuth2 requests |
| `pkce_error` | `PKCE.*enforced\|pkce.*required\|code.*challenge.*required` | PKCE validation failures |
| `expired_code` | `expired.*code\|authorization.*code.*expired\|code.*invalid` | Authorization code expiration |
| `token_error` | `invalid.*token\|token.*expired\|token.*validation.*failed` | Token validation issues |
| `redirect_error` | `redirect.*uri.*mismatch\|invalid.*redirect` | Redirect URI mismatches |
| `scope_error` | `invalid.*scope\|scope.*not.*permitted` | OAuth scope issues |
| `generic_error` | `ERROR\|WARN.*oauth\|WARN.*oidc` | Generic OAuth/OIDC warnings |

---

## Quick Start

### Prerequisites

- Kubernetes cluster access with appropriate RBAC
- `kubectl` configured
- Slack webhook URL (optional, for alerts)

### Installation

#### 1. Update ConfigMap with Monitoring Script

```bash
# Navigate to scripts directory
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes

# Create ConfigMap with the actual script
kubectl create configmap oidc-monitor-script \
  --from-file=oidc-monitor.sh=scripts/oidc-monitor.sh \
  --namespace=monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### 2. Configure Slack Webhook (Optional)

```bash
# Create or update Slack webhook secret
kubectl create secret generic oidc-monitor-slack \
  --from-literal=webhook-url='https://hooks.slack.com/services/YOUR/WEBHOOK/URL' \
  --namespace=monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

**To create a Slack webhook:**
1. Go to https://api.slack.com/messaging/webhooks
2. Create a new webhook for your workspace
3. Choose the channel for alerts (e.g., `#platform-alerts`)
4. Copy the webhook URL

#### 3. Deploy Monitoring System

```bash
# Deploy all components
kubectl apply -f k8s/monitoring/oidc-monitor-cronjob.yaml

# Verify deployment
kubectl get cronjobs -n monitoring
kubectl get pvc -n monitoring
kubectl get serviceaccount -n monitoring
```

Expected output:
```
NAME                         SCHEDULE    SUSPEND   ACTIVE   LAST SCHEDULE   AGE
oidc-monitor-hourly          0 * * * *   False     0        <none>          10s
oidc-monitor-daily-report    0 9 * * *   False     0        <none>          10s
```

---

## Usage

### Running Manual Checks

#### Single Check (Last 5 Minutes)

```bash
# Create a job from the manual template
kubectl create job oidc-monitor-$(date +%Y%m%d-%H%M%S) \
  --from=job/oidc-monitor-manual \
  -n monitoring

# Watch the job
kubectl get jobs -n monitoring -w

# View logs
kubectl logs -n monitoring job/oidc-monitor-<timestamp> -f
```

#### Custom Duration Check (e.g., Last Hour)

```bash
# Run monitoring script locally with cluster access
./scripts/oidc-monitor.sh --single --interval 3600
```

#### Continuous Monitoring (48 Hours)

```bash
# Run in background
nohup ./scripts/oidc-monitor.sh --duration 172800 --interval 3600 > oidc-monitor.log 2>&1 &

# Monitor progress
tail -f oidc-monitor.log

# Check process
ps aux | grep oidc-monitor
```

### Viewing Reports

#### Access Report Files

```bash
# List all reports
kubectl exec -n monitoring deployment/oidc-monitor-viewer -- ls -lh /var/log/oidc-monitor/reports/

# View specific report
kubectl exec -n monitoring deployment/oidc-monitor-viewer -- cat /var/log/oidc-monitor/reports/oidc-report-20260212_143000.json | jq .

# Download reports locally
kubectl cp monitoring/<pod-name>:/var/log/oidc-monitor/reports ./local-reports/
```

#### Report Structure

```json
{
  "timestamp": "20260212_143000",
  "duration_seconds": 3600,
  "total_errors": 15,
  "errors": {
    "keycloak_login_error": 5,
    "gitlab_webservice_invalid_request": 3,
    "argocd_server_token_error": 7
  },
  "samples": {
    "keycloak_login_error_samples": "2026-02-12T14:25:31Z ERROR: Login failed for user...\n...",
    "gitlab_webservice_invalid_request_samples": "...",
    "argocd_server_token_error_samples": "..."
  }
}
```

### Analyzing Results

#### Check for Specific Error Types

```bash
# Find all reports with PKCE errors
kubectl exec -n monitoring <pod> -- sh -c "
  for report in /var/log/oidc-monitor/reports/*.json; do
    pkce_errors=\$(jq -r '.errors | to_entries[] | select(.key | contains(\"pkce\")) | .value' \"\$report\")
    if [ \"\$pkce_errors\" -gt 0 ]; then
      echo \"Report: \$report - PKCE Errors: \$pkce_errors\"
    fi
  done
"
```

#### Generate Summary Statistics

```bash
# Total errors in last 24 hours
kubectl exec -n monitoring <pod> -- sh -c "
  find /var/log/oidc-monitor/reports -name 'oidc-report-$(date +%Y%m%d)*.json' -exec jq -r '.total_errors' {} + | paste -sd+ | bc
"
```

---

## Scheduled Monitoring

### Hourly Monitoring

**Schedule:** Every hour (`:00`)
**CronJob:** `oidc-monitor-hourly`
**Function:** Checks logs from the last hour and alerts if errors exceed threshold

```bash
# Check CronJob status
kubectl get cronjob -n monitoring oidc-monitor-hourly

# View recent job runs
kubectl get jobs -n monitoring -l app=oidc-monitor --sort-by=.metadata.creationTimestamp

# View logs from last run
LAST_JOB=$(kubectl get jobs -n monitoring -l app=oidc-monitor -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n monitoring job/$LAST_JOB
```

### Daily Summary Report

**Schedule:** Daily at 9:00 AM UTC (6:00 AM BRT)
**CronJob:** `oidc-monitor-daily-report`
**Function:** Aggregates all hourly reports from previous day

```bash
# Check daily report status
kubectl get cronjob -n monitoring oidc-monitor-daily-report

# View latest daily report
kubectl exec -n monitoring <pod> -- cat /var/log/oidc-monitor/reports/daily-summary-$(date -d yesterday +%Y%m%d).json | jq .
```

---

## Troubleshooting

### Common Issues

#### 1. No Logs Found

**Symptom:** Monitor reports 0 errors but you know there are issues.

**Possible Causes:**
- Pods not running in monitored namespaces
- Incorrect namespace configuration
- Logs rotated before collection

**Resolution:**
```bash
# Verify pods are running
kubectl get pods -n keycloak
kubectl get pods -n gitlab-staging
kubectl get pods -n argocd

# Check namespace configuration
kubectl get configmap -n monitoring oidc-monitor-script -o yaml | grep NAMESPACE

# Reduce check interval for more frequent monitoring
kubectl set env cronjob/oidc-monitor-hourly -n monitoring CHECK_INTERVAL=1800
```

#### 2. Permission Denied

**Symptom:** Monitor fails with "Forbidden" or "permission denied" errors.

**Resolution:**
```bash
# Verify ServiceAccount has correct permissions
kubectl describe clusterrolebinding oidc-monitor-reader-binding

# Test permissions
kubectl auth can-i get pods --as=system:serviceaccount:monitoring:oidc-monitor -n keycloak
kubectl auth can-i get pods/log --as=system:serviceaccount:monitoring:oidc-monitor -n gitlab-staging
```

#### 3. Slack Alerts Not Sending

**Symptom:** Errors detected but no Slack notifications.

**Resolution:**
```bash
# Verify Slack secret exists and is correct
kubectl get secret -n monitoring oidc-monitor-slack
kubectl get secret -n monitoring oidc-monitor-slack -o jsonpath='{.data.webhook-url}' | base64 -d

# Test webhook manually
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test alert from OIDC monitor"}' \
  $(kubectl get secret -n monitoring oidc-monitor-slack -o jsonpath='{.data.webhook-url}' | base64 -d)

# Check threshold configuration
kubectl get cronjob -n monitoring oidc-monitor-hourly -o yaml | grep ERROR_THRESHOLD
```

#### 4. PVC Full

**Symptom:** Monitor fails with "No space left on device".

**Resolution:**
```bash
# Check PVC usage
kubectl exec -n monitoring <pod> -- df -h /var/log/oidc-monitor

# Clean old reports (keep last 7 days)
kubectl exec -n monitoring <pod> -- sh -c "
  find /var/log/oidc-monitor -type f -mtime +7 -delete
"

# Resize PVC if needed
kubectl patch pvc oidc-monitor-logs -n monitoring -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'
```

#### 5. High False Positive Rate

**Symptom:** Too many alerts for benign issues.

**Resolution:**
```bash
# Increase error threshold
kubectl set env cronjob/oidc-monitor-hourly -n monitoring ERROR_THRESHOLD=50

# Adjust patterns by modifying the script
# Edit scripts/oidc-monitor.sh and update the ERROR_PATTERNS array
# Then update the ConfigMap:
kubectl create configmap oidc-monitor-script \
  --from-file=oidc-monitor.sh=scripts/oidc-monitor.sh \
  --namespace=monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## Alert Response Procedures

### When You Receive an Alert

#### 1. Acknowledge and Assess

```bash
# View latest report mentioned in alert
kubectl exec -n monitoring <pod> -- cat /var/log/oidc-monitor/reports/<report-file> | jq .

# Check current error rate
./scripts/oidc-monitor.sh --single --interval 300
```

#### 2. Identify Affected Service

Based on error keys in the report:
- `keycloak_*` → Keycloak issue
- `gitlab_webservice_*` → GitLab OIDC issue
- `gitlab_workhorse_*` → GitLab proxy issue
- `argocd_server_*` → ArgoCD OIDC issue
- `argocd_dex_*` → ArgoCD Dex SSO issue

#### 3. Investigate Root Cause

**For Keycloak Issues:**
```bash
# Check Keycloak pod health
kubectl get pods -n keycloak -l app.kubernetes.io/name=keycloakx

# View detailed logs
kubectl logs -n keycloak <keycloak-pod> --tail=100 | grep -i error

# Check database connectivity
kubectl exec -n keycloak <keycloak-pod> -- curl -s http://localhost:8080/auth/health/ready
```

**For GitLab Issues:**
```bash
# Check GitLab webservice health
kubectl get pods -n gitlab-staging -l app=webservice

# View OIDC-related logs
kubectl logs -n gitlab-staging <webservice-pod> -c webservice | grep -i "oidc\|oauth"

# Check OIDC configuration
kubectl get secret -n gitlab-staging gitlab-oidc-keycloak -o jsonpath='{.data.provider}' | base64 -d
```

**For ArgoCD Issues:**
```bash
# Check ArgoCD server health
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server

# View OIDC logs
kubectl logs -n argocd <argocd-server-pod> | grep -i "oidc\|sso"

# Check Dex configuration
kubectl get configmap -n argocd argocd-cm -o yaml | grep -A 20 "dex.config"
```

#### 4. Common Remediation Actions

**PKCE Errors:**
- Verify PKCE is enabled in OIDC client configuration
- Check that client supports PKCE (required for public clients)
- Update client configuration in Keycloak if needed

**Redirect URI Mismatch:**
- Verify redirect URIs in Keycloak client match application configuration
- Check for trailing slashes, HTTP vs HTTPS
- Update client redirect URIs: `kubectl exec -n keycloak <pod> -- ...`

**Expired Code:**
- Check for clock skew between services
- Verify authorization code lifetime (default: 60s)
- Increase code lifetime if network latency is high

**Token Errors:**
- Verify token signing keys are valid
- Check token expiration settings
- Ensure services can reach OIDC discovery endpoint

---

## Configuration

### Environment Variables

Modify these in the CronJob manifest or when running manually:

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_DIR` | `/var/log/oidc-monitor` | Log file directory |
| `REPORT_DIR` | `/var/log/oidc-monitor/reports` | Report output directory |
| `ERROR_THRESHOLD` | `10` | Errors per check before alerting |
| `CHECK_INTERVAL` | `3600` | Seconds of logs to check (hourly = 3600) |
| `MONITORING_DURATION` | `3600` | Total monitoring duration for continuous mode |
| `KEYCLOAK_NAMESPACE` | `keycloak` | Keycloak namespace |
| `GITLAB_NAMESPACE` | `gitlab-staging` | GitLab namespace |
| `ARGOCD_NAMESPACE` | `argocd` | ArgoCD namespace |
| `SLACK_WEBHOOK_URL` | (empty) | Slack webhook for alerts |

### Modifying Monitoring Schedule

```bash
# Change to run every 30 minutes
kubectl patch cronjob oidc-monitor-hourly -n monitoring -p '{"spec":{"schedule":"*/30 * * * *"}}'

# Change to run every 4 hours
kubectl patch cronjob oidc-monitor-hourly -n monitoring -p '{"spec":{"schedule":"0 */4 * * *"}}'

# Suspend monitoring temporarily
kubectl patch cronjob oidc-monitor-hourly -n monitoring -p '{"spec":{"suspend":true}}'

# Resume monitoring
kubectl patch cronjob oidc-monitor-hourly -n monitoring -p '{"spec":{"suspend":false}}'
```

### Customizing Error Patterns

Edit `/home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/oidc-monitor.sh`:

```bash
# Add new pattern
declare -A ERROR_PATTERNS=(
    # Existing patterns...
    ["custom_pattern"]="your_regex_here"
)

# Update ConfigMap
kubectl create configmap oidc-monitor-script \
  --from-file=oidc-monitor.sh=scripts/oidc-monitor.sh \
  --namespace=monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## Maintenance

### Log Rotation

Logs and reports accumulate over time. Clean periodically:

```bash
# Manual cleanup (keep last 30 days)
kubectl exec -n monitoring <pod> -- find /var/log/oidc-monitor -type f -mtime +30 -delete

# Automate with CronJob
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: oidc-monitor-cleanup
  namespace: monitoring
spec:
  schedule: "0 2 * * 0"  # Weekly at 2 AM Sunday
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: oidc-monitor
          restartPolicy: OnFailure
          containers:
          - name: cleanup
            image: busybox
            command:
            - /bin/sh
            - -c
            - find /var/log/oidc-monitor -type f -mtime +30 -delete
            volumeMounts:
            - name: logs
              mountPath: /var/log/oidc-monitor
          volumes:
          - name: logs
            persistentVolumeClaim:
              claimName: oidc-monitor-logs
EOF
```

### Monitoring the Monitor

Ensure the monitoring system itself is healthy:

```bash
# Check CronJob execution
kubectl get cronjobs -n monitoring

# Check for failed jobs
kubectl get jobs -n monitoring -l app=oidc-monitor --field-selector status.successful=0

# Set up alerts for monitor failures (example)
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-rules
  namespace: monitoring
data:
  oidc-monitor-rules.yaml: |
    groups:
    - name: oidc-monitor
      interval: 5m
      rules:
      - alert: OIDCMonitorJobFailed
        expr: kube_job_status_failed{job_name=~"oidc-monitor.*"} > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "OIDC monitor job failed"
          description: "Job {{ \$labels.job_name }} has failed"
EOF
```

---

## Metrics and Reporting

### Key Metrics to Track

1. **Total Errors per Day**: Trend over time
2. **Error Rate per Service**: Which service has most issues
3. **Error Type Distribution**: Most common error patterns
4. **Alert Frequency**: How often threshold is exceeded
5. **Mean Time to Detection (MTTD)**: Time between error occurrence and detection

### Generating Custom Reports

```bash
# Weekly summary
kubectl exec -n monitoring <pod> -- sh -c "
  for day in {1..7}; do
    date=\$(date -d \"-\$day day\" +%Y%m%d)
    echo \"Date: \$date\"
    find /var/log/oidc-monitor/reports -name \"oidc-report-\${date}*.json\" \
      -exec jq -r '.total_errors' {} + | paste -sd+ | bc
  done
"

# Export to CSV for analysis
kubectl exec -n monitoring <pod> -- sh -c "
  echo 'Timestamp,Service,ErrorType,Count' > /tmp/oidc-errors.csv
  for report in /var/log/oidc-monitor/reports/*.json; do
    jq -r '.timestamp as \$ts | .errors | to_entries[] | [\$ts, .key, .value] | @csv' \"\$report\" >> /tmp/oidc-errors.csv
  done
  cat /tmp/oidc-errors.csv
"
```

---

## References

### Related Documentation

- [Keycloak Upgrade Logbook](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-11-keycloak-upgrade-17to26.md)
- [GitLab OIDC Integration Logbook](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-11-gitlab-oidc-integration.md)
- [Cluster Remediation Runbook](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/operations/2026-02-09-remediation-runbook.md)

### External Resources

- [OAuth 2.0 Error Codes](https://tools.ietf.org/html/rfc6749#section-4.1.2.1)
- [OpenID Connect Error Codes](https://openid.net/specs/openid-connect-core-1_0.html#AuthError)
- [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [GitLab OmniAuth Documentation](https://docs.gitlab.com/ee/integration/omniauth.html)
- [ArgoCD SSO Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)

---

## Changelog

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2026-02-12 | 1.0.0 | Initial version | Platform Team |

---

## Support

For issues or questions:

1. Check troubleshooting section above
2. Review recent reports in `/var/log/oidc-monitor/reports/`
3. Escalate to Platform Team with report file and error samples
4. For urgent production issues, follow incident response procedures

**Emergency Contacts:**
- Platform Team: `#platform-team` Slack channel
- On-call Engineer: PagerDuty escalation policy
