# DT-005: Alertas Deploy Runbook

**Version**: 1.1
**Last Updated**: 2026-03-09
**Owner**: Platform SRE Team
**Cluster**: k8s-platform-prod (EKS 1.34, us-east-1)
**Namespace**: staging-observability-monitoring
**Status**: Production Ready — Artefatos criados, aguardando Teams webhooks reais (ADR-103)

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Deploy Sequence](#deploy-sequence)
4. [Step 1: Configure Teams Webhooks](#step-1-configure-teams-webhooks)
5. [Step 2: Apply PrometheusRules](#step-2-apply-prometheusrules)
6. [Step 3: Apply AlertmanagerConfig CRD](#step-3-apply-alertmanagerconfig-crd)
7. [Step 4: Helm Upgrade (Alertmanager)](#step-4-helm-upgrade-alertmanager)
8. [Step 5: Validation](#step-5-validation)
9. [How to Test an Alert](#how-to-test-an-alert)
10. [Troubleshooting](#troubleshooting)
11. [Rollback](#rollback)

---

## Overview

DT-005 deploys 37 Prometheus alerting rules across 4 groups, plus Teams-based Alertmanager routing (ADR-103):

| Group | Alerts | Channel |
|---|---|---|
| dt005-kubernetes-platform | 12 | alerts-critical, alerts-warning |
| dt005-data-services | 10 | alerts-data-services |
| dt005-security-compliance | 8 | alerts-security |
| dt005-application-slo | 7 | alerts-critical, alerts-warning |
| **Total** | **37** | **4 channels** |

**Artifacts:**

- `domains/observability/infra/alerts/dt005-prometheus-rules.yaml`
- `domains/observability/infra/alerts/dt005-alertmanager-config.yaml` (reference)
- `domains/observability/infra/alerts/dt005-alertmanager-config-crd.yaml` (deploy this)
- `domains/observability/infra/helm/kube-prometheus-stack/alertmanager-values-patch.yaml`
- `scripts/observability/configure-teams-webhooks.sh`
- `scripts/observability/deploy-dt005-alerts.sh`
- 17 runbooks in `domains/observability/docs/runbooks/`

---

## Prerequisites

Before deploying, verify:

```bash
# 1. kubectl connected to k8s-platform-prod
kubectl cluster-info
kubectl config current-context

# 2. AWS session active
aws sts get-caller-identity

# 3. Namespace exists
kubectl get namespace staging-observability-monitoring

# 4. kube-prometheus-stack deployed
kubectl get pods -n staging-observability-monitoring | grep -E "prometheus|alertmanager"

# 5. Prometheus Operator CRDs installed
kubectl get crd | grep monitoring.coreos.com
# Should show: prometheusrules.monitoring.coreos.com
# Should show: alertmanagerconfigs.monitoring.coreos.com
```

---

## Deploy Sequence

```
1. Get Teams Incoming Webhook URLs (from Teams channel admin)
       |
       v
2. configure-teams-webhooks.sh  →  K8s Secret: alertmanager-teams-webhooks
       |
       v
3. kubectl apply dt005-prometheus-rules.yaml
       |
       v
4. kubectl apply dt005-alertmanager-config-crd.yaml
       |
       v
5. helm upgrade (alertmanager-values-patch.yaml)  →  enables CRD discovery
       |
       v
6. Validation (Prometheus UI + Alertmanager UI)
```

---

## Step 1: Configure Teams Webhooks

### Create Teams Incoming Webhooks

In Microsoft Teams, create 4 Incoming Webhook connectors across the designated alert channels:

| Channel | Purpose |
|---|---|
| alerts-critical | severity=critical (node down, pod crashing, 5xx spike) |
| alerts-warning | severity=warning (batched, low-noise) |
| alerts-data-services | PostgreSQL, Redis, RabbitMQ events |
| alerts-security | Vault, cert-manager, ExternalSecrets, Kyverno |

**Teams Incoming Webhook setup** (per channel):

1. Open the target Teams channel → click `...` → **Connectors**
2. Search for **Incoming Webhook** → **Configure**
3. Name it (e.g., `alerts-critical`) → **Create**
4. Copy the webhook URL: `https://outlook.office.com/webhook/<tenant>/...`

Teams docs: [Add Incoming Webhook to Teams channel](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook)

### Run the webhook configuration script

```bash
cd /path/to/k8s-platform-repo

./scripts/observability/configure-teams-webhooks.sh \
  "https://outlook.office.com/webhook/TENANT/alerts-critical-url" \
  "https://outlook.office.com/webhook/TENANT/alerts-warning-url" \
  "https://outlook.office.com/webhook/TENANT/alerts-data-services-url" \
  "https://outlook.office.com/webhook/TENANT/alerts-security-url"
```

**Order of arguments:**

1. critical channel webhook
2. warning channel webhook
3. data-services channel webhook
4. security channel webhook

The script will:

- Validate URL format (`https://outlook.office.com/webhook/...`)
- Send a test ping to each webhook
- Create K8s Secret `alertmanager-teams-webhooks` in `staging-observability-monitoring`
- Apply Kyverno-compliant labels to the Secret

### Verify the Secret

```bash
kubectl get secret alertmanager-teams-webhooks \
  -n staging-observability-monitoring \
  -o jsonpath='{.data}' | \
  python3 -c "import sys,json; [print(k) for k in json.load(sys.stdin).keys()]"

# Expected output:
# teams-webhook-critical
# teams-webhook-data
# teams-webhook-security
# teams-webhook-warning
```

---

## Step 2: Apply PrometheusRules

```bash
NAMESPACE="staging-observability-monitoring"

kubectl apply \
  -f domains/observability/infra/alerts/dt005-prometheus-rules.yaml \
  -n ${NAMESPACE}

# Verify
kubectl get prometheusrule -n ${NAMESPACE}
# Expected: dt005-platform-alerts   AGE
```

The PrometheusRule contains labels required for Prometheus to pick it up:

```yaml
labels:
  prometheus: kube-prometheus-stack-prometheus
  role: alert-rules
```

These must match the `ruleSelector` in the Prometheus spec (already set in `values.yaml`).

**Wait 30-60 seconds** for Prometheus Operator to reconcile.

---

## Step 3: Apply AlertmanagerConfig CRD

```bash
NAMESPACE="staging-observability-monitoring"

kubectl apply \
  -f domains/observability/infra/alerts/dt005-alertmanager-config-crd.yaml \
  -n ${NAMESPACE}

# Verify
kubectl get alertmanagerconfig -n ${NAMESPACE}
# Expected: dt005-teams-routing   READY

# Check CRD status
kubectl describe alertmanagerconfig dt005-teams-routing -n ${NAMESPACE}
```

The AlertmanagerConfig CRD uses Secret references for webhook URLs:

```yaml
url:
  name: alertmanager-teams-webhooks
  key: teams-webhook-critical
```

No plaintext URLs are stored in the YAML file.

---

## Step 4: Helm Upgrade (Alertmanager)

This step enables the Prometheus Operator to discover AlertmanagerConfig CRDs.

```bash
NAMESPACE="staging-observability-monitoring"
HELM_RELEASE="kube-prometheus-stack"

# Dry-run first
helm upgrade ${HELM_RELEASE} prometheus-community/kube-prometheus-stack \
  -n ${NAMESPACE} \
  -f domains/observability/infra/helm/kube-prometheus-stack/values.yaml \
  -f domains/observability/infra/helm/kube-prometheus-stack/alertmanager-values-patch.yaml \
  --reuse-values \
  --dry-run

# Apply
helm upgrade ${HELM_RELEASE} prometheus-community/kube-prometheus-stack \
  -n ${NAMESPACE} \
  -f domains/observability/infra/helm/kube-prometheus-stack/values.yaml \
  -f domains/observability/infra/helm/kube-prometheus-stack/alertmanager-values-patch.yaml \
  --reuse-values

# Monitor rollout
kubectl rollout status statefulset/alertmanager-kube-prometheus-stack-alertmanager \
  -n ${NAMESPACE}
```

Key changes in `alertmanager-values-patch.yaml`:

- `alertmanagerConfigSelector.matchLabels: {demand: dt005}` — discovers our CRD
- `alertmanagerConfigNamespaceSelector` — scoped to our namespace
- `retention: 120h` — 5 days of silence/notification history
- `storage: 2Gi (gp3)` — cost-optimized
- `replicas: 2` — HA with gossip deduplication
- `evaluationInterval: 30s` — tighter SLO evaluation

---

## Step 5: Validation

### 5.1 Verify PrometheusRules loaded

```bash
# Port-forward to Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 \
  -n staging-observability-monitoring &

# List all DT-005 rules
curl -s http://localhost:9090/api/v1/rules | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
groups = data['data']['groups']
dt005 = [g for g in groups if 'dt005' in g['name']]
print(f'DT-005 groups: {len(dt005)}')
for g in dt005:
    print(f'  {g[\"name\"]}: {len(g[\"rules\"])} rules')
total = sum(len(g[\"rules\"]) for g in dt005)
print(f'Total rules: {total}')
"
# Expected:
#   DT-005 groups: 4
#   dt005-kubernetes-platform: 12 rules
#   dt005-data-services: 10 rules
#   dt005-security-compliance: 8 rules
#   dt005-application-slo: 7 rules
#   Total rules: 37

kill %1  # Stop port-forward
```

### 5.2 Verify Alertmanager config

```bash
# Port-forward to Alertmanager
kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 \
  -n staging-observability-monitoring &

# Check config status
curl -s http://localhost:9093/api/v2/status | \
  python3 -c "import sys,json; s=json.load(sys.stdin); print(s.get('versionInfo',{}).get('version','unknown'))"

# List receivers
curl -s http://localhost:9093/api/v2/receivers | python3 -m json.tool

# Expected receivers: teams-critical, teams-warning, teams-data-services, teams-security, null

kill %1  # Stop port-forward
```

### 5.3 Full automated validation

```bash
# Run the full deploy script (validates + applies)
./scripts/observability/deploy-dt005-alerts.sh --skip-verify

# Or with Prometheus verification
./scripts/observability/deploy-dt005-alerts.sh
```

---

## How to Test an Alert

### Method 1: Simulate PodCrashLooping (non-destructive)

```bash
# Deploy a deliberately crashing pod
kubectl run crash-test \
  --image=busybox \
  --restart=Always \
  -n staging-observability-monitoring \
  -- sh -c "exit 1"

# Watch it crash-loop
kubectl get pod crash-test -n staging-observability-monitoring -w

# Wait ~10 minutes for 5+ restarts, then check Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 \
  -n staging-observability-monitoring
# http://localhost:9090/alerts  -> PodCrashLooping should appear

# Check Teams alerts-critical channel for the notification

# Cleanup
kubectl delete pod crash-test -n staging-observability-monitoring
```

### Method 2: Test Alertmanager webhook directly

```bash
# Port-forward to Alertmanager
kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 \
  -n staging-observability-monitoring &

# Send a test alert via API
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[
    {
      "labels": {
        "alertname": "TestAlert",
        "severity": "critical",
        "namespace": "staging-observability-monitoring",
        "service": "test"
      },
      "annotations": {
        "summary": "[TEST] DT-005 webhook validation",
        "description": "This is a test alert sent during DT-005 deployment validation. Safe to ignore."
      },
      "startsAt": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",
      "endsAt": "'"$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ)"'"
    }
  ]'

# Check Teams alerts-critical channel for the test notification
# Then silence/resolve via UI: http://localhost:9093

kill %1
```

### Method 3: Trigger a real warning condition (NodeHighCpuUsage)

```bash
# Deploy a CPU stress pod (safe, runs in isolated pod)
kubectl run cpu-stress \
  --image=containerstack/cpu-stress \
  --restart=Never \
  --limits=cpu=1 \
  -n staging-observability-monitoring

# Wait ~15 minutes for NodeHighCpuUsage to fire
# Check: http://localhost:9090/alerts (after port-forward)

# Cleanup
kubectl delete pod cpu-stress -n staging-observability-monitoring
```

---

## Troubleshooting

### Alert not appearing in Prometheus UI

**Symptom**: Applied PrometheusRule, but alert not visible at `http://localhost:9090/alerts`.

**Check 1**: Verify PrometheusRule labels match ruleSelector.

```bash
kubectl get prometheusrule dt005-platform-alerts \
  -n staging-observability-monitoring \
  -o jsonpath='{.metadata.labels}'

# Must contain:
# "prometheus": "kube-prometheus-stack-prometheus"
# "role": "alert-rules"
```

**Check 2**: Check Prometheus Operator logs for reconciliation errors.

```bash
kubectl logs -n staging-observability-monitoring \
  -l app.kubernetes.io/name=kube-prometheus-stack-operator \
  --tail=50 | grep -i "prometheusrule\|dt005"
```

**Check 3**: Check ruleNamespaceSelector.

```bash
kubectl get prometheus -n staging-observability-monitoring \
  kube-prometheus-stack-prometheus \
  -o jsonpath='{.spec.ruleNamespaceSelector}'
# Should be {} (all namespaces) or include staging-observability-monitoring
```

---

### Teams notifications not firing

**Symptom**: Alert appears in Prometheus, Alertmanager shows it as active, but no Teams message.

**Check 1**: Verify Secret exists with correct keys.

```bash
kubectl get secret alertmanager-teams-webhooks \
  -n staging-observability-monitoring \
  -o jsonpath='{.data}' | python3 -c \
  "import sys,json; [print(k) for k in json.load(sys.stdin).keys()]"
```

**Check 2**: Check AlertmanagerConfig is Ready.

```bash
kubectl get alertmanagerconfig dt005-teams-routing \
  -n staging-observability-monitoring -o yaml | grep -A5 "status:"
```

**Check 3**: Check Alertmanager logs for webhook errors.

```bash
kubectl logs -n staging-observability-monitoring \
  -l app.kubernetes.io/name=alertmanager \
  --tail=100 | grep -i "error\|failed\|teams\|webhook"
```

**Check 4**: Verify webhook URL is valid.

```bash
# Decode and test the secret
WEBHOOK=$(kubectl get secret alertmanager-teams-webhooks \
  -n staging-observability-monitoring \
  -o jsonpath='{.data.teams-webhook-critical}' | base64 -d)

curl -s -X POST "${WEBHOOK}" \
  -H "Content-Type: application/json" \
  -d '{"text":"[TEST] Direct webhook test from troubleshooting runbook"}'
# Expected: 1 (Teams returns "1" on success)
```

---

### Webhook returns HTTP 4xx

| Code | Cause | Fix |
|---|---|---|
| 400 | Invalid JSON payload | Check Alertmanager template for syntax errors |
| 403 | Connector disabled or expired | Regenerate Incoming Webhook in Teams channel settings |
| 404 | Wrong tenant/connector URL | Verify URL from Teams channel connector settings |
| 429 | Rate limited | Increase groupInterval/repeatInterval in AlertmanagerConfig |

---

### AlertmanagerConfig not picked up

**Symptom**: `kubectl get alertmanagerconfig` shows the object but Alertmanager doesn't use it.

**Check**: Verify `alertmanagerConfigSelector` is set in Alertmanager spec.

```bash
kubectl get alertmanager -n staging-observability-monitoring \
  kube-prometheus-stack-alertmanager \
  -o jsonpath='{.spec.alertmanagerConfigSelector}'
# Must show: {"matchLabels":{"demand":"dt005"}}
```

If missing, the helm upgrade with `alertmanager-values-patch.yaml` was not applied. Re-run:

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n staging-observability-monitoring \
  -f domains/observability/infra/helm/kube-prometheus-stack/values.yaml \
  -f domains/observability/infra/helm/kube-prometheus-stack/alertmanager-values-patch.yaml \
  --reuse-values
```

---

### PrometheusRule has syntax errors

```bash
# Validate YAML syntax locally
python3 -c "import yaml,sys; yaml.safe_load(open('domains/observability/infra/alerts/dt005-prometheus-rules.yaml'))"

# Validate PromQL expressions (requires promtool)
promtool check rules domains/observability/infra/alerts/dt005-prometheus-rules.yaml
```

---

## Rollback

### Remove PrometheusRules (stops alerting)

```bash
kubectl delete prometheusrule dt005-platform-alerts \
  -n staging-observability-monitoring
```

### Remove AlertmanagerConfig (reverts to base values.yaml routing)

```bash
kubectl delete alertmanagerconfig dt005-teams-routing \
  -n staging-observability-monitoring
```

### Remove Teams webhooks Secret

```bash
kubectl delete secret alertmanager-teams-webhooks \
  -n staging-observability-monitoring
```

### Rollback helm upgrade

```bash
helm rollback kube-prometheus-stack -n staging-observability-monitoring
# Or to a specific revision:
helm history kube-prometheus-stack -n staging-observability-monitoring
helm rollback kube-prometheus-stack <REVISION> -n staging-observability-monitoring
```

---

## Related Documentation

- [dt005-pod-crash-looping.md](../../../domains/observability/docs/runbooks/dt005-pod-crash-looping.md)
- [dt005-node-not-ready.md](../../../domains/observability/docs/runbooks/dt005-node-not-ready.md)
- [dt005-postgresql-down.md](../../../domains/observability/docs/runbooks/dt005-postgresql-down.md)
- [dt005-vault-sealed.md](../../../domains/observability/docs/runbooks/dt005-vault-sealed.md)
- [dt005-certificate-expiring.md](../../../domains/observability/docs/runbooks/dt005-certificate-expiring.md)
- [dt005-external-secret-sync-failure.md](../../../domains/observability/docs/runbooks/dt005-external-secret-sync-failure.md)
- ADR-103: Alertas via Microsoft Teams — `docs/adr/adr-103-teams-alertas-plataforma.md`
