# OIDC Monitoring System Implementation

**Date:** 2026-02-12
**Author:** Platform Team
**Status:** Ready for Deployment
**Version:** 1.0.0

---

## Executive Summary

This document describes the implementation of a comprehensive OIDC (OpenID Connect) monitoring system for the Kubernetes platform. The system continuously monitors authentication logs from Keycloak, GitLab, and ArgoCD to detect and alert on authentication issues before they impact users.

### Key Features

- **Continuous Monitoring**: Automated hourly checks of OIDC authentication flows
- **Pattern Detection**: Identifies 8 different error patterns (PKCE, expired codes, token errors, etc.)
- **Slack Alerts**: Real-time notifications when error threshold is exceeded
- **Detailed Reports**: JSON reports with error counts and sample log entries
- **48-Hour History**: Retains 48 hours of job history for trend analysis
- **Daily Summaries**: Aggregated daily reports for long-term tracking

---

## Architecture

### Components

1. **Monitoring Script** (`scripts/oidc-monitor.sh`)
   - Bash script that fetches and analyzes logs from multiple services
   - Uses kubectl to access pod logs from Keycloak, GitLab, and ArgoCD
   - Detects error patterns using regex matching
   - Generates JSON reports with error counts and samples
   - Sends Slack alerts when thresholds are exceeded

2. **Kubernetes CronJob** (`k8s/monitoring/oidc-monitor-cronjob.yaml`)
   - Runs hourly on schedule `0 * * * *`
   - Uses dedicated ServiceAccount with read-only pod log permissions
   - Stores logs and reports on persistent volume (5Gi PVC)
   - Includes daily summary job for aggregated reporting

3. **Deployment Script** (`scripts/deploy-oidc-monitor.sh`)
   - Automates deployment of all components
   - Updates ConfigMap with latest monitoring script
   - Configures Slack webhook (optional)
   - Verifies deployment and can run test job

4. **Documentation**
   - Full runbook: `docs/runbooks/oidc-monitoring.md`
   - Quick reference: `docs/runbooks/oidc-monitoring-quickref.md`
   - Implementation details: This document

---

## Files Created

### Scripts

| File | Size | Purpose | Executable |
|------|------|---------|------------|
| `/home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/oidc-monitor.sh` | 16K | Main monitoring script | Yes |
| `/home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/deploy-oidc-monitor.sh` | 7.0K | Deployment automation | Yes |

### Kubernetes Manifests

| File | Size | Purpose |
|------|------|---------|
| `/home/gilvangalindo/projects/Arquitetura/Kubernetes/k8s/monitoring/oidc-monitor-cronjob.yaml` | 12K | CronJob, ServiceAccount, RBAC, PVC, Secrets |

### Documentation

| File | Size | Purpose |
|------|------|---------|
| `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/runbooks/oidc-monitoring.md` | 21K | Complete runbook with troubleshooting |
| `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/runbooks/oidc-monitoring-quickref.md` | 5.1K | Quick reference guide |
| `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/oidc-monitoring-implementation.md` | This file | Implementation details |

---

## Error Detection Patterns

The system monitors for 8 distinct error patterns:

| Pattern | Regex | Example Error | Impact |
|---------|-------|---------------|--------|
| **login_error** | `LOGIN_ERROR\|login.*error\|authentication.*failed` | "Authentication failed for user john@example.com" | Users cannot log in |
| **invalid_request** | `invalid_request\|invalid.*client\|client.*not.*found` | "Invalid client: gitlab" | Application misconfiguration |
| **pkce_error** | `PKCE.*enforced\|pkce.*required\|code.*challenge.*required` | "PKCE code challenge required" | Security policy violation |
| **expired_code** | `expired.*code\|authorization.*code.*expired\|code.*invalid` | "Authorization code expired" | Network latency or clock skew |
| **token_error** | `invalid.*token\|token.*expired\|token.*validation.*failed` | "Token signature validation failed" | Key rotation or config issue |
| **redirect_error** | `redirect.*uri.*mismatch\|invalid.*redirect` | "Redirect URI mismatch" | Client configuration error |
| **scope_error** | `invalid.*scope\|scope.*not.*permitted` | "Scope 'admin' not permitted" | Permission misconfiguration |
| **generic_error** | `ERROR\|WARN.*oauth\|WARN.*oidc` | "WARN: OAuth token refresh failed" | General issues |

---

## Monitored Services

### Keycloak (Identity Provider)

- **Namespace:** `keycloak`
- **Pod Selector:** `app.kubernetes.io/name=keycloakx`
- **Monitored Logs:** All Keycloak server logs
- **Key Errors:** Login failures, client authentication, token issuance

### GitLab (OIDC Client)

- **Namespace:** `gitlab-staging`
- **Pod Selectors:**
  - Webservice: `app=webservice` (container: `webservice`)
  - Workhorse: `app=webservice` (container: `gitlab-workhorse`)
- **Monitored Logs:** Rails application logs, proxy logs
- **Key Errors:** OIDC callback failures, token validation, user provisioning

### ArgoCD (OIDC Client)

- **Namespace:** `argocd`
- **Pod Selectors:**
  - Server: `app.kubernetes.io/name=argocd-server`
  - Dex: `app.kubernetes.io/name=argocd-dex-server`
- **Monitored Logs:** ArgoCD server logs, Dex SSO logs
- **Key Errors:** SSO failures, group/role mapping issues

---

## Deployment Guide

### Prerequisites

- Kubernetes cluster with kubectl access
- RBAC permissions to create ClusterRole, ClusterRoleBinding, ServiceAccount
- (Optional) Slack webhook URL for alerts

### Deployment Steps

#### Option 1: Automated Deployment (Recommended)

```bash
# Navigate to project root
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes

# Deploy with Slack alerts
./scripts/deploy-oidc-monitor.sh \
  --slack-webhook https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
  --test

# Deploy without Slack (can be configured later)
./scripts/deploy-oidc-monitor.sh --test
```

#### Option 2: Manual Deployment

```bash
# 1. Create namespace
kubectl create namespace monitoring

# 2. Create ConfigMap with script
kubectl create configmap oidc-monitor-script \
  --from-file=oidc-monitor.sh=scripts/oidc-monitor.sh \
  --namespace=monitoring

# 3. Configure Slack (optional)
kubectl create secret generic oidc-monitor-slack \
  --from-literal=webhook-url='YOUR_WEBHOOK_URL' \
  --namespace=monitoring

# 4. Deploy all resources
kubectl apply -f k8s/monitoring/oidc-monitor-cronjob.yaml

# 5. Verify deployment
kubectl get cronjobs,sa,pvc,secrets -n monitoring
```

### Post-Deployment Verification

```bash
# Check CronJob status
kubectl get cronjobs -n monitoring

# Run manual test
kubectl create job oidc-test-$(date +%s) \
  --from=job/oidc-monitor-manual \
  -n monitoring

# Wait for completion
kubectl wait --for=condition=complete --timeout=300s \
  job/oidc-test-$(date +%s) -n monitoring

# View test logs
kubectl logs -n monitoring job/oidc-test-<timestamp>
```

---

## Configuration

### Environment Variables

Configure behavior by modifying the CronJob environment variables:

```yaml
env:
  # Threshold for Slack alerts (errors per check)
  - name: ERROR_THRESHOLD
    value: "10"

  # Time window to check logs (seconds)
  - name: CHECK_INTERVAL
    value: "3600"  # 1 hour

  # Namespaces to monitor
  - name: KEYCLOAK_NAMESPACE
    value: "keycloak"
  - name: GITLAB_NAMESPACE
    value: "gitlab-staging"
  - name: ARGOCD_NAMESPACE
    value: "argocd"
```

### Customizing Schedule

```bash
# Run every 30 minutes instead of hourly
kubectl patch cronjob oidc-monitor-hourly -n monitoring \
  -p '{"spec":{"schedule":"*/30 * * * *"}}'

# Run every 4 hours
kubectl patch cronjob oidc-monitor-hourly -n monitoring \
  -p '{"spec":{"schedule":"0 */4 * * *"}}'
```

### Adjusting Error Threshold

```bash
# Increase threshold to reduce alert noise
kubectl set env cronjob/oidc-monitor-hourly -n monitoring ERROR_THRESHOLD=50

# Decrease threshold for more sensitive alerts
kubectl set env cronjob/oidc-monitor-hourly -n monitoring ERROR_THRESHOLD=5
```

---

## Usage Examples

### Running Manual Checks

```bash
# Quick check (last 5 minutes)
./scripts/oidc-monitor.sh --single --interval 300

# Check last hour
./scripts/oidc-monitor.sh --single --interval 3600

# Continuous monitoring for 24 hours, checking every hour
./scripts/oidc-monitor.sh --duration 86400 --interval 3600
```

### Viewing Reports

```bash
# Get a pod with PVC mounted
POD=$(kubectl get pods -n monitoring -l app=oidc-monitor -o jsonpath='{.items[0].metadata.name}')

# List all reports
kubectl exec -n monitoring $POD -- ls -lh /var/log/oidc-monitor/reports/

# View latest report
LATEST=$(kubectl exec -n monitoring $POD -- ls -t /var/log/oidc-monitor/reports/ | head -1)
kubectl exec -n monitoring $POD -- cat /var/log/oidc-monitor/reports/$LATEST | jq .

# Download all reports
kubectl cp monitoring/$POD:/var/log/oidc-monitor/reports ./oidc-reports/
```

### Sample Report Output

```json
{
  "timestamp": "20260212_143000",
  "duration_seconds": 3600,
  "total_errors": 15,
  "errors": {
    "keycloak_login_error": 5,
    "keycloak_pkce_error": 2,
    "gitlab_webservice_invalid_request": 3,
    "argocd_server_token_error": 5
  },
  "samples": {
    "keycloak_login_error_samples": "2026-02-12T14:25:31Z ERROR: Login failed for user john@example.com: Invalid credentials\n2026-02-12T14:28:15Z ERROR: Login failed for user jane@example.com: Account locked",
    "gitlab_webservice_invalid_request_samples": "..."
  }
}
```

---

## Monitoring the Monitor

### Health Checks

```bash
# Check if CronJobs are running
kubectl get cronjobs -n monitoring

# View recent job history
kubectl get jobs -n monitoring -l app=oidc-monitor --sort-by=.metadata.creationTimestamp

# Check for failed jobs
kubectl get jobs -n monitoring --field-selector status.successful=0
```

### Alert Configuration

Set up Prometheus alerts to monitor the monitoring system itself:

```yaml
- alert: OIDCMonitorJobFailed
  expr: kube_job_status_failed{job_name=~"oidc-monitor.*"} > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "OIDC monitor job failed"
    description: "Job {{ $labels.job_name }} has failed"

- alert: OIDCMonitorNotRunning
  expr: time() - kube_job_status_completion_time{job_name=~"oidc-monitor-hourly.*"} > 7200
  for: 10m
  labels:
    severity: critical
  annotations:
    summary: "OIDC monitor has not run recently"
    description: "No successful job in the last 2 hours"
```

---

## Slack Alert Format

When errors exceed the threshold, the system sends a Slack alert:

```
⚠️ OIDC Authentication Alert

Total Errors: 23
Threshold: 10
Timestamp: 20260212_143000
Check Interval: 3600s

Error Summary:
• keycloak_login_error: 8
• gitlab_webservice_invalid_request: 5
• argocd_server_token_error: 10

Report: /var/log/oidc-monitor/reports/oidc-report-20260212_143000.json
```

---

## Maintenance

### Log Rotation

Reports accumulate over time. Clean periodically:

```bash
# Manual cleanup (keep last 30 days)
kubectl exec -n monitoring <pod> -- find /var/log/oidc-monitor -type f -mtime +30 -delete

# Check disk usage
kubectl exec -n monitoring <pod> -- df -h /var/log/oidc-monitor
```

### Updating the Monitoring Script

```bash
# Make changes to scripts/oidc-monitor.sh
vim scripts/oidc-monitor.sh

# Update ConfigMap
./scripts/deploy-oidc-monitor.sh --update-only

# Or manually
kubectl create configmap oidc-monitor-script \
  --from-file=oidc-monitor.sh=scripts/oidc-monitor.sh \
  --namespace=monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## Troubleshooting

### Issue: No Logs Found

**Symptom:** Reports show 0 errors but issues are occurring.

**Solutions:**
1. Verify pods are running: `kubectl get pods -n keycloak,gitlab-staging,argocd`
2. Check namespace configuration in CronJob environment variables
3. Reduce CHECK_INTERVAL to capture more recent logs

### Issue: Permission Denied

**Symptom:** Monitor fails with "Forbidden" errors.

**Solution:**
```bash
# Verify RBAC
kubectl describe clusterrolebinding oidc-monitor-reader-binding

# Test permissions
kubectl auth can-i get pods --as=system:serviceaccount:monitoring:oidc-monitor -n keycloak
kubectl auth can-i get pods/log --as=system:serviceaccount:monitoring:oidc-monitor -n keycloak
```

### Issue: Slack Alerts Not Sending

**Solutions:**
1. Verify secret: `kubectl get secret -n monitoring oidc-monitor-slack -o jsonpath='{.data.webhook-url}' | base64 -d`
2. Test webhook manually: `curl -X POST -H 'Content-type: application/json' --data '{"text":"Test"}' <webhook-url>`
3. Check ERROR_THRESHOLD is not too high

### Issue: PVC Full

**Solution:**
```bash
# Check usage
kubectl exec -n monitoring <pod> -- df -h /var/log/oidc-monitor

# Clean old files
kubectl exec -n monitoring <pod> -- find /var/log/oidc-monitor -type f -mtime +7 -delete

# Resize PVC
kubectl patch pvc oidc-monitor-logs -n monitoring -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'
```

---

## Security Considerations

### RBAC Permissions

The monitor uses minimal required permissions:

- **ClusterRole:** Read-only access to pods and pod logs
- **No write permissions:** Cannot modify any resources
- **Namespace scoped:** Only accesses specified namespaces

### Secret Management

- Slack webhook URL stored in Kubernetes Secret
- Never logged or exposed in reports
- Optional (system works without Slack integration)

### Log Data

- Reports may contain sensitive error messages
- Store PVC with appropriate access controls
- Consider encrypting PVC if required by compliance

---

## Performance Impact

### Resource Usage

**Per CronJob run:**
- CPU: 100m request, 500m limit
- Memory: 256Mi request, 512Mi limit
- Disk: ~1-5MB per report (depends on error volume)

**Total cluster impact:**
- Negligible: Only runs for 1-2 minutes per hour
- No impact on monitored pods (read-only log access)

### Network Impact

- Minimal: Only fetches logs via Kubernetes API
- One HTTP POST to Slack per alert (if configured)

---

## Future Enhancements

### Planned Improvements

1. **Grafana Dashboard**: Visualize error trends over time
2. **Prometheus Metrics**: Export error counts as metrics
3. **Email Alerts**: Alternative to Slack for notifications
4. **Pattern Learning**: ML-based anomaly detection
5. **Remediation Actions**: Automatic pod restart on certain errors
6. **Multi-cluster Support**: Monitor OIDC across multiple clusters

### Extensibility

The system is designed to be extensible:

- Add new error patterns in `ERROR_PATTERNS` array
- Monitor additional services by adding pod selectors
- Customize report format by modifying `generate_report()` function
- Integrate with other alerting systems (PagerDuty, Opsgenie, etc.)

---

## References

### Internal Documentation

- [OIDC Monitoring Runbook](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/runbooks/oidc-monitoring.md)
- [Quick Reference Guide](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/runbooks/oidc-monitoring-quickref.md)
- [Keycloak Upgrade Logbook](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-11-keycloak-upgrade-17to26.md)
- [GitLab OIDC Integration](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-11-gitlab-oidc-integration.md)

### External Resources

- [OAuth 2.0 RFC 6749](https://tools.ietf.org/html/rfc6749)
- [OpenID Connect Core Spec](https://openid.net/specs/openid-connect-core-1_0.html)
- [Keycloak Documentation](https://www.keycloak.org/docs/latest/)
- [GitLab OmniAuth Docs](https://docs.gitlab.com/ee/integration/omniauth.html)
- [ArgoCD SSO Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)

---

## Changelog

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2026-02-12 | 1.0.0 | Initial implementation | Platform Team |

---

## Support

For issues or questions:

1. Check troubleshooting section in runbook
2. Review recent reports for patterns
3. Contact Platform Team: `#platform-team` Slack channel
4. For urgent issues: PagerDuty escalation

**Maintainer:** Platform Team
**Last Review:** 2026-02-12
**Next Review:** 2026-03-12
