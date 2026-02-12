# OIDC Monitoring Quick Reference

## Installation

```bash
# Deploy monitoring system
./scripts/deploy-oidc-monitor.sh --slack-webhook https://hooks.slack.com/services/YOUR/WEBHOOK/URL --test

# Update script only
./scripts/deploy-oidc-monitor.sh --update-only
```

## Common Commands

### Run Manual Checks

```bash
# Quick check (last 5 minutes)
kubectl create job oidc-check-$(date +%s) --from=job/oidc-monitor-manual -n monitoring

# View logs
kubectl logs -n monitoring job/oidc-check-<timestamp> -f
```

### View Reports

```bash
# List all reports
kubectl exec -n monitoring <pod> -- ls -lh /var/log/oidc-monitor/reports/

# View latest report
LATEST=$(kubectl exec -n monitoring <pod> -- ls -t /var/log/oidc-monitor/reports/ | head -1)
kubectl exec -n monitoring <pod> -- cat /var/log/oidc-monitor/reports/$LATEST | jq .

# Download reports
kubectl cp monitoring/<pod>:/var/log/oidc-monitor/reports ./reports/
```

### Check Status

```bash
# Check CronJobs
kubectl get cronjobs -n monitoring

# View recent jobs
kubectl get jobs -n monitoring -l app=oidc-monitor --sort-by=.metadata.creationTimestamp

# Check last hourly run
LAST_JOB=$(kubectl get jobs -n monitoring -l app=oidc-monitor -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n monitoring job/$LAST_JOB
```

### Configuration

```bash
# Update Slack webhook
kubectl create secret generic oidc-monitor-slack \
  --from-literal=webhook-url='https://hooks.slack.com/services/YOUR/WEBHOOK/URL' \
  --namespace=monitoring --dry-run=client -o yaml | kubectl apply -f -

# Change error threshold
kubectl set env cronjob/oidc-monitor-hourly -n monitoring ERROR_THRESHOLD=20

# Change schedule (every 30 minutes)
kubectl patch cronjob oidc-monitor-hourly -n monitoring -p '{"spec":{"schedule":"*/30 * * * *"}}'

# Suspend monitoring
kubectl patch cronjob oidc-monitor-hourly -n monitoring -p '{"spec":{"suspend":true}}'
```

## Troubleshooting

### No Logs Found

```bash
# Verify pods are running
kubectl get pods -n keycloak
kubectl get pods -n gitlab-staging
kubectl get pods -n argocd

# Check namespaces configuration
kubectl get cronjob oidc-monitor-hourly -n monitoring -o yaml | grep NAMESPACE
```

### Permission Issues

```bash
# Verify RBAC
kubectl describe clusterrolebinding oidc-monitor-reader-binding

# Test permissions
kubectl auth can-i get pods --as=system:serviceaccount:monitoring:oidc-monitor -n keycloak
```

### Slack Not Working

```bash
# Check secret
kubectl get secret -n monitoring oidc-monitor-slack -o jsonpath='{.data.webhook-url}' | base64 -d

# Test webhook
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test"}' \
  $(kubectl get secret -n monitoring oidc-monitor-slack -o jsonpath='{.data.webhook-url}' | base64 -d)
```

### Disk Full

```bash
# Check usage
kubectl exec -n monitoring <pod> -- df -h /var/log/oidc-monitor

# Clean old reports (>7 days)
kubectl exec -n monitoring <pod> -- find /var/log/oidc-monitor -type f -mtime +7 -delete
```

## Error Patterns Reference

| Pattern | Description | Common Causes |
|---------|-------------|---------------|
| `login_error` | Authentication failed | Wrong credentials, locked account |
| `invalid_request` | Malformed OAuth request | Missing parameters, invalid client |
| `pkce_error` | PKCE validation failed | PKCE not enabled, code challenge missing |
| `expired_code` | Authorization code expired | Network delay, clock skew |
| `token_error` | Token validation failed | Expired token, invalid signature |
| `redirect_error` | Redirect URI mismatch | Configuration mismatch in client |
| `scope_error` | Invalid OAuth scope | Scope not configured in client |

## Service-Specific Investigation

### Keycloak

```bash
kubectl logs -n keycloak <pod> --tail=100 | grep -i error
kubectl exec -n keycloak <pod> -- curl http://localhost:8080/auth/health/ready
```

### GitLab

```bash
kubectl logs -n gitlab-staging <webservice-pod> -c webservice | grep -i "oidc\|oauth"
kubectl get secret -n gitlab-staging gitlab-oidc-keycloak -o jsonpath='{.data.provider}' | base64 -d
```

### ArgoCD

```bash
kubectl logs -n argocd <server-pod> | grep -i "oidc\|sso"
kubectl get configmap -n argocd argocd-cm -o yaml | grep -A 20 "dex.config"
```

## Alert Response Checklist

1. View latest report from Slack alert
2. Identify affected service (keycloak/gitlab/argocd)
3. Check service pod health
4. View service logs for errors
5. Verify OIDC configuration
6. Apply remediation if needed
7. Monitor for 1 hour to confirm fix
8. Document incident and resolution

## Quick Links

- Full Documentation: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/runbooks/oidc-monitoring.md`
- Monitoring Script: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/oidc-monitor.sh`
- Kubernetes Manifests: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/k8s/monitoring/oidc-monitor-cronjob.yaml`
- Deployment Script: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/deploy-oidc-monitor.sh`
