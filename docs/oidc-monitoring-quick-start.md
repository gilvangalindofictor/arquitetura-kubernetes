# OIDC Monitoring Quick Start Guide

**Time to Deploy:** 5 minutes
**Prerequisites:** kubectl access to cluster
**Status:** Production Ready

---

## What Is This?

A monitoring system that continuously watches your Keycloak, GitLab, and ArgoCD logs for OIDC authentication errors and alerts you via Microsoft Teams when problems are detected.

**Detects:**
- Login failures
- PKCE errors
- Token validation issues
- Expired authorization codes
- Redirect URI mismatches
- OAuth scope errors
- And more...

**Alerts:**

- Microsoft Teams notifications when errors exceed threshold (default: 10/hour)
- Detailed JSON reports with error samples
- Daily summary reports

---

## Installation (3 Steps)

### Step 1: Get Teams Incoming Webhook (Optional, 2 minutes)

1. Open Microsoft Teams and navigate to the target channel (e.g., `Platform Alerts`)
2. Click the `...` (More options) next to the channel name → **Connectors**
3. Search for **Incoming Webhook** and click **Configure**
4. Give the webhook a name (e.g., `OIDC Monitor`) and click **Create**
5. Copy the generated webhook URL: `https://outlook.office.com/webhook/<tenant-id>/...`

Skip this step if you don't want Teams alerts (monitoring will still work and save reports).

### Step 2: Deploy (1 minute)

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes

# With Teams alerts
./scripts/deploy-oidc-monitor.sh \
  --teams-webhook https://outlook.office.com/webhook/YOUR/WEBHOOK/URL \
  --test

# Without Teams (configure later)
./scripts/deploy-oidc-monitor.sh --test
```

The `--test` flag runs an immediate check to verify everything works.

### Step 3: Verify (1 minute)

```bash
# Check CronJobs are scheduled
kubectl get cronjobs -n monitoring

# Expected output:
# NAME                         SCHEDULE    SUSPEND   ACTIVE
# oidc-monitor-hourly          0 * * * *   False     0
# oidc-monitor-daily-report    0 9 * * *   False     0
```

**Done!** The system will now run hourly checks automatically.

---

## Usage

### View Latest Report

```bash
# Get any pod that has access to the PVC
POD=$(kubectl get jobs -n monitoring -l app=oidc-monitor -o jsonpath='{.items[-1].metadata.name}' | sed 's/-[0-9]*$//')
kubectl logs -n monitoring job/$(kubectl get jobs -n monitoring -l app=oidc-monitor -o jsonpath='{.items[-1].metadata.name}')
```

### Run Manual Check

```bash
# Check logs from last 5 minutes
kubectl create job oidc-check-$(date +%s) \
  --from=job/oidc-monitor-manual \
  -n monitoring

# Watch the job
kubectl logs -n monitoring job/oidc-check-<timestamp> -f
```

### Download Reports

```bash
# Find a pod with the PVC mounted
POD=$(kubectl get jobs -n monitoring -l app=oidc-monitor -o jsonpath='{.items[-1].spec.template.spec.containers[0].name}')

# List reports
kubectl exec -n monitoring <pod> -- ls /var/log/oidc-monitor/reports/

# Download all reports
kubectl cp monitoring/<pod>:/var/log/oidc-monitor/reports ./oidc-reports/
```

---

## Configuration

### Change Alert Threshold

```bash
# Reduce alerts (only alert if >50 errors)
kubectl set env cronjob/oidc-monitor-hourly -n monitoring ERROR_THRESHOLD=50

# More sensitive (alert if >5 errors)
kubectl set env cronjob/oidc-monitor-hourly -n monitoring ERROR_THRESHOLD=5
```

### Change Schedule

```bash
# Run every 30 minutes instead of hourly
kubectl patch cronjob oidc-monitor-hourly -n monitoring \
  -p '{"spec":{"schedule":"*/30 * * * *"}}'

# Run every 4 hours
kubectl patch cronjob oidc-monitor-hourly -n monitoring \
  -p '{"spec":{"schedule":"0 */4 * * *"}}'
```

### Update Teams Webhook

```bash
kubectl create secret generic oidc-monitor-teams \
  --from-literal=webhook-url='https://outlook.office.com/webhook/NEW/WEBHOOK/URL' \
  --namespace=monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Temporarily Disable

```bash
# Pause monitoring
kubectl patch cronjob oidc-monitor-hourly -n monitoring -p '{"spec":{"suspend":true}}'

# Resume
kubectl patch cronjob oidc-monitor-hourly -n monitoring -p '{"spec":{"suspend":false}}'
```

---

## Troubleshooting

### No Reports Generated

**Check if jobs are running:**
```bash
kubectl get jobs -n monitoring -l app=oidc-monitor --sort-by=.metadata.creationTimestamp
```

**Check last job logs:**
```bash
LAST_JOB=$(kubectl get jobs -n monitoring -l app=oidc-monitor -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n monitoring job/$LAST_JOB
```

**Common causes:**
- No pods running in monitored namespaces
- RBAC permissions issue
- PVC not mounted

### Teams Alerts Not Working

**Test webhook:**
```bash
WEBHOOK=$(kubectl get secret -n monitoring oidc-monitor-teams -o jsonpath='{.data.webhook-url}' | base64 -d)
curl -X POST -H 'Content-type: application/json' --data '{"text":"Test"}' "$WEBHOOK"
```

**Check threshold:**
```bash
kubectl get cronjob oidc-monitor-hourly -n monitoring -o yaml | grep ERROR_THRESHOLD
# If threshold is too high, errors won't trigger alerts
```

### Permission Denied

**Verify RBAC:**
```bash
kubectl describe clusterrolebinding oidc-monitor-reader-binding
```

**Test permissions:**
```bash
kubectl auth can-i get pods --as=system:serviceaccount:monitoring:oidc-monitor -n keycloak
kubectl auth can-i get pods/log --as=system:serviceaccount:monitoring:oidc-monitor -n keycloak
```

### Reports Show 0 Errors But Issues Exist

**Check namespace configuration:**
```bash
kubectl get cronjob oidc-monitor-hourly -n monitoring -o yaml | grep -A 5 "env:"
```

**Verify correct namespaces:**
- Keycloak: `keycloak`
- GitLab: `gitlab-staging`
- ArgoCD: `argocd`

**Adjust if needed:**
```bash
kubectl set env cronjob/oidc-monitor-hourly -n monitoring \
  KEYCLOAK_NAMESPACE=your-keycloak-namespace \
  GITLAB_NAMESPACE=your-gitlab-namespace \
  ARGOCD_NAMESPACE=your-argocd-namespace
```

---

## Sample Teams Alert

When errors exceed the threshold, you'll receive an alert like this:

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

**What to do:**
1. Click the report path to see details
2. Identify the affected service (keycloak, gitlab, or argocd)
3. Check service logs for more context
4. Follow remediation steps in [full runbook](./runbooks/oidc-monitoring.md)

---

## Sample Report

Reports are saved as JSON files with this structure:

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
    "keycloak_login_error_samples": "2026-02-12T14:25:31Z ERROR: Login failed for user john@example.com: Invalid credentials\n...",
    "gitlab_webservice_invalid_request_samples": "..."
  }
}
```

The `samples` section includes actual log lines for each error type (up to 3 samples per type).

---

## Error Types Reference

| Error Type | What It Means | Common Causes |
|------------|---------------|---------------|
| `login_error` | User authentication failed | Wrong password, locked account, expired password |
| `invalid_request` | Malformed OAuth request | Missing client ID, invalid parameters |
| `pkce_error` | PKCE validation failed | Client doesn't send code challenge, PKCE disabled |
| `expired_code` | Authorization code expired | Network latency, clock skew, >60s between redirect and token exchange |
| `token_error` | Token validation failed | Expired token, wrong signing key, token tampered |
| `redirect_error` | Redirect URI mismatch | Client redirect URI doesn't match configured value in Keycloak |
| `scope_error` | OAuth scope issue | Requested scope not configured, insufficient permissions |
| `generic_error` | Other OAuth/OIDC error | Various issues, check samples for details |

---

## Updating the System

### Update Monitoring Script

If you modify `scripts/oidc-monitor.sh`:

```bash
# Option 1: Use deployment script
./scripts/deploy-oidc-monitor.sh --update-only

# Option 2: Manual update
kubectl create configmap oidc-monitor-script \
  --from-file=oidc-monitor.sh=scripts/oidc-monitor.sh \
  --namespace=monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Update Kubernetes Resources

If you modify `k8s/monitoring/oidc-monitor-cronjob.yaml`:

```bash
kubectl apply -f k8s/monitoring/oidc-monitor-cronjob.yaml
```

---

## Maintenance

### Clean Old Reports

Reports accumulate over time (1-5 MB per report depending on error volume).

**Manual cleanup (keep last 30 days):**
```bash
POD=$(kubectl get jobs -n monitoring -l app=oidc-monitor -o jsonpath='{.items[-1].spec.template.spec.containers[0].name}')
kubectl exec -n monitoring <pod> -- find /var/log/oidc-monitor -type f -mtime +30 -delete
```

**Check disk usage:**
```bash
kubectl exec -n monitoring <pod> -- df -h /var/log/oidc-monitor
```

**Resize PVC if needed:**
```bash
kubectl patch pvc oidc-monitor-logs -n monitoring -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'
```

---

## Advanced Usage

### Continuous Monitoring (48 Hours)

Run on your local machine with cluster access:

```bash
# Monitor continuously for 48 hours, checking every hour
./scripts/oidc-monitor.sh --duration 172800 --interval 3600

# Run in background
nohup ./scripts/oidc-monitor.sh --duration 172800 --interval 3600 > oidc-monitor.log 2>&1 &

# Monitor progress
tail -f oidc-monitor.log
```

### Custom Error Patterns

Edit `scripts/oidc-monitor.sh` and modify the `ERROR_PATTERNS` array:

```bash
declare -A ERROR_PATTERNS=(
    # ... existing patterns ...
    ["custom_pattern"]="your_regex_here|alternative_pattern"
)
```

Then update the ConfigMap:
```bash
./scripts/deploy-oidc-monitor.sh --update-only
```

---

## Additional Resources

**Detailed Documentation:**
- [Full Runbook](./runbooks/oidc-monitoring.md) - Complete guide with troubleshooting
- [Quick Reference](./runbooks/oidc-monitoring-quickref.md) - Command cheat sheet
- [Implementation Guide](./oidc-monitoring-implementation.md) - Architecture and design

**Related Logbooks:**
- [Keycloak Upgrade 17→26](./logbook/2026-02-11-keycloak-upgrade-17to26.md)
- [GitLab OIDC Integration](./logbook/2026-02-11-gitlab-oidc-integration.md)

**External Resources:**
- [OAuth 2.0 Errors](https://tools.ietf.org/html/rfc6749#section-4.1.2.1)
- [OpenID Connect Errors](https://openid.net/specs/openid-connect-core-1_0.html#AuthError)

---

## Support

**Questions?** Check the [troubleshooting section](#troubleshooting) above.

**Found a bug?** Contact Platform Team in the `Platform Team` Microsoft Teams channel.

**Urgent issues?** Follow incident response procedures and escalate to on-call engineer.

---

**Last Updated:** 2026-02-12
**Version:** 1.0.0
