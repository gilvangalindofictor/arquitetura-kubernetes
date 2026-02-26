# Developer Guide: Progressive Deployment Strategies

**Version**: 1.0
**Date**: 2026-02-26
**Demand**: CICD-005
**ADR**: ADR-085
**Target audience**: Application developers, Platform engineers

---

## Overview

This guide explains how to use Argo Rollouts for progressive delivery on the K8s Platform. After reading this guide you will be able to:

1. Convert a `Deployment` to a `Rollout`
2. Define a custom `AnalysisTemplate`
3. Trigger manual promotion (Blue-Green)
4. Execute a manual rollback

---

## Prerequisites

- Argo Rollouts controller running in `argocd` namespace (deployed via Terraform CICD-005)
- kubectl argo rollouts plugin installed:
  ```bash
  # Install kubectl plugin
  curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
  chmod +x kubectl-argo-rollouts-linux-amd64
  sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
  ```
- AnalysisTemplates deployed to your namespace:
  ```bash
  kubectl apply -f domains/apps/manifests/analysis-templates/ -n <YOUR_NAMESPACE>
  ```
- Application exposing Prometheus metrics (see "Metric Requirements" section)

---

## Step 1: Converting Deployment to Rollout

The `Rollout` resource is a drop-in replacement for `Deployment`. The key differences are:

- `apiVersion`: `argoproj.io/v1alpha1` (instead of `apps/v1`)
- `kind`: `Rollout` (instead of `Deployment`)
- `spec.strategy`: replaced with `spec.strategy.canary` or `spec.strategy.blueGreen`

### Before (Deployment)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-app-ns
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: harbor.staging.example.com/apps/my-app:sha-abc123
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

### After (Rollout — Canary)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
  namespace: my-app-ns
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: harbor.staging.example.com/apps/my-app:sha-abc123
  strategy:
    canary:
      stableService: my-app-stable
      canaryService: my-app-canary
      steps:
        - setWeight: 20
        - analysis:
            templates:
              - templateName: success-rate
              - templateName: latency-p95
            args:
              - name: service-name
                value: my-app-canary
        - pause:
            duration: 5m
        - setWeight: 40
        - pause:
            duration: 5m
        - setWeight: 60
        - pause:
            duration: 5m
        - setWeight: 80
        - pause:
            duration: 5m
```

You also need two Kubernetes Services:

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: my-app-stable
  namespace: my-app-ns
spec:
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080

---
apiVersion: v1
kind: Service
metadata:
  name: my-app-canary
  namespace: my-app-ns
spec:
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

> **Note**: Argo Rollouts manages the pod selector labels on these services automatically. Do not set `rollouts-pod-template-hash` selector manually.

---

## Step 2: Metric Requirements

For analysis-driven rollouts (recommended), your application must expose Prometheus metrics:

### Required Metrics

| Metric | Type | Labels | Purpose |
|--------|------|--------|---------|
| `http_requests_total` | counter | `status`, `service` | Success rate, error rates |
| `http_request_duration_seconds_bucket` | histogram | `le`, `service` | P95 latency |

### How to Expose (examples by framework)

**Java Spring Boot** (Micrometer):
```yaml
management:
  endpoints:
    web:
      exposure:
        include: prometheus
  metrics:
    tags:
      service: my-app
```

**Go** (Prometheus client):
```go
var httpRequestsTotal = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "http_requests_total",
        Help: "Total HTTP requests",
    },
    []string{"status", "service"},
)
```

**Node.js** (prom-client):
```javascript
const counter = new Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['status', 'service'],
});
```

### Fallback: Time-Based Progression (No Metrics)

If your application does not expose the required metrics, use time-based pauses only. Remove the `analysis` step from the Rollout:

```yaml
strategy:
  canary:
    steps:
      - setWeight: 20
      - pause:
          duration: 10m   # Longer pause to allow manual observation
      - setWeight: 50
      - pause:
          duration: 10m
      - setWeight: 100
```

> **Warning**: Time-based progression has no automated rollback. An engineer must monitor the deployment and manually abort if issues are detected.

---

## Step 3: Deploying and Monitoring

### Deploy a new version

```bash
# Option 1: Update image via kubectl plugin (triggers rollout)
kubectl argo rollouts set image my-app my-app=harbor.example.com/apps/my-app:sha-newsha -n my-app-ns

# Option 2: Update the Rollout spec (GitOps: push manifest change, ArgoCD syncs)
# Edit spec.template.spec.containers[0].image in your YAML and push to git

# Option 3: GitLab CI (recommended)
# The argo-rollouts.gitlab-ci.yml template handles this automatically
```

### Watch rollout progress

```bash
# Live watch (blocks terminal until complete)
kubectl argo rollouts get rollout my-app -n my-app-ns --watch

# Current status only
kubectl argo rollouts get rollout my-app -n my-app-ns
```

### Dashboard access

```bash
# Port-forward to Argo Rollouts Dashboard
kubectl port-forward svc/argo-rollouts-dashboard 3100:3100 -n argocd
# Open: http://localhost:3100
```

---

## Step 4: Triggering Manual Promotion (Blue-Green)

For Blue-Green rollouts with `autoPromotionEnabled: false`, you must manually trigger the promotion after validating the preview version.

### Pre-promotion checklist

1. Access the preview (green) version:
   ```bash
   kubectl port-forward svc/my-app-preview 8080:80 -n my-app-ns
   # Test: curl http://localhost:8080/health
   ```

2. Check analysis run status (pre-promotion analysis must be Successful):
   ```bash
   kubectl get analysisrun -n my-app-ns
   kubectl describe analysisrun <name> -n my-app-ns
   ```

3. Review dashboard in Grafana: "Argo Rollouts — Deployment Progress"

### Execute promotion

```bash
# Promote: switches activeService from blue to green (instant)
kubectl argo rollouts promote my-app -n my-app-ns

# In GitLab CI: click "Play" on the `rollout-promote` job
```

### Immediate rollback after promotion (within 5 minutes)

Blue keeps running for `scaleDownDelaySeconds` (300s). Within this window:

```bash
# Undo: switches active service back to blue
kubectl argo rollouts undo my-app -n my-app-ns
```

After 5 minutes, blue is scaled down and undo creates a new rollout instead.

---

## Step 5: Manual Rollback

### Abort current rollout (canary in progress)

Aborts the rollout and reverts all traffic to stable:

```bash
kubectl argo rollouts abort my-app -n my-app-ns
```

After abort, the Rollout enters `Degraded` phase. Scale it back up:

```bash
# Restart with previous stable image
kubectl argo rollouts undo my-app -n my-app-ns
```

### Undo to previous revision

```bash
# View revision history
kubectl argo rollouts history rollout my-app -n my-app-ns

# Rollback to specific revision
kubectl argo rollouts undo my-app --to-revision=2 -n my-app-ns
```

### Emergency: force stable

If Argo Rollouts is unresponsive, you can manually patch the ReplicaSet:

```bash
# Scale down canary RS manually (find RS names)
kubectl get rs -n my-app-ns -l app=my-app
kubectl scale rs <canary-rs-name> --replicas=0 -n my-app-ns
kubectl scale rs <stable-rs-name> --replicas=3 -n my-app-ns
```

> **Note**: This bypasses Argo Rollouts. ArgoCD will detect drift and resync. Ensure you also update the Rollout manifest in git.

---

## Step 6: Defining a Custom AnalysisTemplate

Use this when the default templates don't cover your metrics. Copy and customize:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: my-custom-analysis
  namespace: my-app-ns  # Namespace-scoped
spec:
  args:
    - name: service-name
    - name: prometheus-url
      value: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090

  metrics:
    - name: my-custom-metric
      interval: 1m
      count: 5
      failureLimit: 2

      provider:
        prometheus:
          address: "{{args.prometheus-url}}"
          query: |
            # Replace with your custom PromQL query
            my_app_custom_metric_total{service="{{args.service-name}}"}

      # Define your success condition
      successCondition: result[0] > 100
      failureCondition: result[0] <= 100
```

Reference it in your Rollout:

```yaml
strategy:
  canary:
    steps:
      - setWeight: 20
      - analysis:
          templates:
            - templateName: success-rate          # platform library
            - templateName: my-custom-analysis    # your custom template
          args:
            - name: service-name
              value: my-app-canary
      - pause:
          duration: 5m
```

---

## Common Errors and Solutions

### Error: "AnalysisRun Failed: no data returned"

**Cause**: Prometheus query returns empty result (not NaN) — the metric does not exist at all.

**Fix**: Verify the metric exists:
```bash
kubectl exec -n monitoring deploy/kube-prometheus-stack-prometheus -- \
  curl -s 'http://localhost:9090/api/v1/query?query=http_requests_total{service="my-app-canary"}' | jq
```

If empty, check your application's metric name and labels.

### Error: "AnalysisRun Inconclusive"

**Cause**: The metric returned NaN (no traffic to canary yet). With `isNaN()` safety enabled, this resolves automatically after traffic starts flowing.

**Action**: Wait for traffic to arrive (usually after 1-2 minutes of weight being active).

### Error: "Rollout stuck in Progressing >30min"

**Cause**: Usually a paused step waiting for manual promotion, or a replica that cannot start.

**Check**:
```bash
kubectl argo rollouts describe rollout my-app -n my-app-ns
kubectl get events -n my-app-ns --field-selector=reason=BackOff
```

**Fix**:
- If paused: `kubectl argo rollouts promote my-app -n my-app-ns`
- If pod crash: fix the image, push new commit
- If timeout: `kubectl argo rollouts abort my-app -n my-app-ns`

### Error: "Service selector not matching pods"

**Cause**: The canary/stable services have been manually edited and the label selector is wrong.

**Fix**: Delete and recreate the services. Argo Rollouts manages the `rollouts-pod-template-hash` selector automatically — do not set it manually.

---

## Good vs Bad Examples

### Good: Using immutable tags with Rollout

```yaml
# Good: sha-prefixed immutable tag (ADR-084 compliant)
containers:
  - name: my-app
    image: harbor.example.com/apps/my-app:sha-a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
```

### Bad: Using latest or mutable tags

```yaml
# Bad: mutable tag — unpredictable rollback behavior
containers:
  - name: my-app
    image: harbor.example.com/apps/my-app:latest
```

### Good: Analysis with proper args

```yaml
# Good: service-name arg matches actual service name
- analysis:
    templates:
      - templateName: success-rate
    args:
      - name: service-name
        value: my-app-canary  # Must match the canaryService name
```

### Bad: Hardcoded service name in AnalysisTemplate

```yaml
# Bad: hardcoding service name prevents template reuse
# Don't modify the library templates — use args instead
```

---

## FAQ

**Q: Can I use Rollout with ArgoCD Image Updater?**

A: Yes. Image Updater detects new tags and updates the Rollout spec. The controller picks up the change and starts the canary/blue-green process automatically.

**Q: Does Rollout work with Kyverno policies?**

A: Yes. Kyverno policies apply to pods created by Rollout's ReplicaSets. Ensure your Kyverno `require-labels` policy includes `rollouts-pod-template-hash` as an optional label (it is added by the controller, not by the manifest author).

**Q: Can I have both a Deployment and a Rollout for the same app?**

A: No. Replace the Deployment with a Rollout. They cannot coexist for the same selector. Delete the Deployment first, then apply the Rollout.

**Q: What happens if Argo Rollouts controller crashes during a canary?**

A: The ReplicaSets continue running in their last known state. Traffic distribution via services is unchanged. When the controller recovers, it resumes from the last stable state. No traffic spike occurs.

**Q: How do I run Rollouts in multiple environments (staging + production)?**

A: Use separate Rollout manifests per environment (with different namespace and replica count). The GitLab CI template uses `K8S_NAMESPACE` variable to target the correct environment.

---

## Resources

- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [AnalysisTemplate Examples](../../../domains/apps/manifests/analysis-templates/)
- [Canary Rollout Example](../../../domains/apps/manifests/rollouts/canary-example.yaml)
- [Blue-Green Rollout Example](../../../domains/apps/manifests/rollouts/blue-green-example.yaml)
- [GitLab CI Template](../../../domains/cicd-platform/infra/gitlab-ci/templates/argo-rollouts.gitlab-ci.yml)
- [ADR-085](../adr/adr-085-argo-rollouts-progressive-delivery.md)
- [Runbook: Troubleshooting](../runbooks/argo-rollouts-troubleshooting.md)
