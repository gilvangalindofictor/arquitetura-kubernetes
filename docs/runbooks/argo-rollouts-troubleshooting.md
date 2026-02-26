# Runbook: Argo Rollouts Troubleshooting

**Version**: 1.0
**Date**: 2026-02-26
**Demand**: CICD-005
**On-call**: Platform SRE

---

## Quick Reference

| Symptom | Likely Cause | Quick Fix |
|---------|-------------|-----------|
| Rollout stuck in Progressing >30min | Pause waiting for promotion | `kubectl argo rollouts promote <name> -n <ns>` |
| AnalysisRun Failed | Metric threshold exceeded | Check PromQL, then `kubectl argo rollouts abort <name>` |
| AnalysisRun Inconclusive | No traffic to canary yet | Wait 2-5 minutes |
| Rollout in Degraded phase | Abort or failed rollout | `kubectl argo rollouts undo <name> -n <ns>` |
| Controller pod not running | Helm release issue | `kubectl rollout restart deploy/argo-rollouts -n argocd` |
| Analysis never starts | AnalysisTemplate missing | `kubectl apply -f analysis-templates/ -n <ns>` |

---

## Diagnostic Commands

### Get rollout status

```bash
# Current state
kubectl argo rollouts get rollout <ROLLOUT_NAME> -n <NAMESPACE>

# Live watch
kubectl argo rollouts get rollout <ROLLOUT_NAME> -n <NAMESPACE> --watch

# Detailed description with events
kubectl argo rollouts describe rollout <ROLLOUT_NAME> -n <NAMESPACE>

# Revision history
kubectl argo rollouts history rollout <ROLLOUT_NAME> -n <NAMESPACE>
```

### Inspect AnalysisRuns

```bash
# List all AnalysisRuns in namespace
kubectl get analysisrun -n <NAMESPACE> --sort-by=.metadata.creationTimestamp

# Describe a specific AnalysisRun (shows metric results)
kubectl describe analysisrun <ANALYSISRUN_NAME> -n <NAMESPACE>

# Get AnalysisRun YAML (full details)
kubectl get analysisrun <ANALYSISRUN_NAME> -n <NAMESPACE> -o yaml

# List AnalysisTemplates
kubectl get analysistemplate -n <NAMESPACE>
```

### Check controller health

```bash
# Controller pod status
kubectl get pods -n argocd -l app.kubernetes.io/name=argo-rollouts

# Controller logs (last 100 lines)
kubectl logs -n argocd deploy/argo-rollouts --tail=100

# Controller logs with errors
kubectl logs -n argocd deploy/argo-rollouts | grep -i "error\|fail\|warn"
```

### Check services and ReplicaSets

```bash
# List ReplicaSets (stable vs canary)
kubectl get rs -n <NAMESPACE> -l app=<APP_NAME>

# Describe services (check selectors)
kubectl describe svc <APP_NAME>-stable -n <NAMESPACE>
kubectl describe svc <APP_NAME>-canary -n <NAMESPACE>
```

---

## Scenario 1: Rollout Stuck in Progressing

### Alert: `RolloutStuck` (critical)

**Definition**: Rollout in Progressing state for more than 30 minutes.

**Most common causes:**

1. **Paused step waiting for promotion** (Blue-Green with `autoPromotionEnabled: false`)
2. **Analysis waiting for metrics** (canary service has no traffic yet)
3. **Pod cannot start** (ImagePullBackOff, CrashLoopBackOff, resource constraints)

### Diagnosis

```bash
# Check current step and why it is paused
kubectl argo rollouts describe rollout <ROLLOUT_NAME> -n <NAMESPACE>
# Look for: "Status: Paused" and "Message:"

# Check pods
kubectl get pods -n <NAMESPACE> -l app=<APP_NAME>
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# Check events
kubectl get events -n <NAMESPACE> --sort-by=.lastTimestamp | tail -20
```

### Resolution

**Case 1: Legitimate pause (Blue-Green, waiting for human promotion)**

```bash
# If pre-promotion analysis passed and manual review is complete:
kubectl argo rollouts promote <ROLLOUT_NAME> -n <NAMESPACE>
```

**Case 2: Pod cannot start (ImagePullBackOff, CrashLoopBackOff)**

```bash
# Check pod error
kubectl describe pod <FAILING_POD> -n <NAMESPACE>

# Fix the image or config, push new commit (ArgoCD syncs)
# Then abort the stuck rollout and let the new revision start fresh:
kubectl argo rollouts abort <ROLLOUT_NAME> -n <NAMESPACE>
# Fix the issue and push a new commit
```

**Case 3: No traffic to canary (AnalysisRun Inconclusive)**

```bash
# Verify canary service is receiving traffic
kubectl get svc <APP_NAME>-canary -n <NAMESPACE>
# Check that the ingress/LB is pointing to the service

# If traffic is flowing but analysis is still inconclusive, check the query:
kubectl describe analysisrun -n <NAMESPACE> | grep -A5 "Message:"
# Common issue: metric name mismatch (service label different from service name)
```

**Case 4: Truly stuck (unknown reason)**

```bash
# Force abort (rolls back to stable)
kubectl argo rollouts abort <ROLLOUT_NAME> -n <NAMESPACE>

# Check controller logs for errors
kubectl logs -n argocd deploy/argo-rollouts --since=1h | grep -i error
```

---

## Scenario 2: AnalysisRun Failed

### Alert: `AnalysisFailed` (critical)

**Definition**: An AnalysisRun reached Failed phase, triggering automatic rollback.

This alert fires when a canary deployment was automatically rolled back due to metric thresholds being exceeded.

### What happened

1. The new version (canary) was receiving traffic
2. The AnalysisRun measured metrics via Prometheus
3. A metric exceeded the failure threshold (e.g., 5xx rate > 1%)
4. After `failureLimit` consecutive failures, the AnalysisRun was marked Failed
5. Argo Rollouts automatically rolled back to the stable version

### Post-failure investigation

```bash
# 1. Get the failed AnalysisRun name
kubectl get analysisrun -n <NAMESPACE> --sort-by=.metadata.creationTimestamp

# 2. See which metric failed and the values
kubectl describe analysisrun <ANALYSISRUN_NAME> -n <NAMESPACE>
# Look for: "Status: Failed" under each metric

# 3. Get the exact PromQL query used
kubectl get analysisrun <ANALYSISRUN_NAME> -n <NAMESPACE> -o yaml | grep -A20 "provider:"

# 4. Run the query manually in Prometheus to see historical values
# (substitute {{args.service-name}} with the actual service name)
# Access Prometheus: kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```

### Common failure patterns

**Pattern 1: 5xx spike at canary start**

The new version crashes on startup and returns 500s before Kubernetes marks it Unready.

```
Diagnosis:
- Check pod logs: kubectl logs -n <NAMESPACE> -l app=<APP_NAME> --previous
- Check if readiness probe is misconfigured
Fix:
- Fix the startup bug
- Improve readiness probe to reflect actual readiness
```

**Pattern 2: Latency increase during traffic shift**

The new version is functionally correct but slower under load.

```
Diagnosis:
- Compare p95 latency of canary vs stable in Grafana dashboard
- Check resource limits (is the canary pod CPU throttled?)
Fix:
- Increase resource limits in the Rollout spec
- Optimize the performance regression in code
```

**Pattern 3: Spurious failure (infrastructure issue)**

Prometheus query returned unreliable data (e.g., Prometheus was restarting).

```
Diagnosis:
- Check Prometheus availability during the analysis window
  kubectl get pods -n monitoring -l app=kube-prometheus-stack-prometheus
- Check if the failure window correlates with any infrastructure events
Fix:
- Increase failureLimit in the AnalysisTemplate (from 2 to 3)
- Add a minimum-traffic guard in the PromQL query
```

---

## Scenario 3: Frequent Rollbacks

### Alert: `FrequentRollbacks` (warning)

**Definition**: More than 3 rollbacks in the past 1 hour.

This indicates deployment instability. The same service is repeatedly being deployed and rolled back.

### Investigation

```bash
# Check revision history
kubectl argo rollouts history rollout <ROLLOUT_NAME> -n <NAMESPACE>

# List recent AnalysisRuns and their phases
kubectl get analysisrun -n <NAMESPACE> --sort-by=.metadata.creationTimestamp

# Correlate with GitLab CI pipelines
# Check which commits are triggering the rollouts
```

### Common causes and actions

**Cause 1: Code regression in recent commits**

Action: Review the last 3-5 commits. Identify the regression. Fix and push.

```bash
# Pause rollouts while investigating (prevents further canary noise)
kubectl argo rollouts pause <ROLLOUT_NAME> -n <NAMESPACE>
```

**Cause 2: AnalysisTemplate threshold too strict**

The 95% success rate threshold may be too tight for services with naturally high 4xx rates (e.g., search APIs where "not found" is expected).

Action: Create a service-specific AnalysisTemplate with a relaxed threshold:

```yaml
# In your app namespace, not in the platform library
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate-relaxed
  namespace: my-app-ns
spec:
  args:
    - name: service-name
  metrics:
    - name: success-rate
      interval: 1m
      count: 5
      failureLimit: 3  # Allow 3 failures (vs 2 in default)
      provider:
        prometheus:
          address: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
          query: |
            sum(rate(http_requests_total{status=~"2..", service="{{args.service-name}}"}[2m])) /
            sum(rate(http_requests_total{service="{{args.service-name}}"}[2m]))
      successCondition: result[0] >= 0.90 || isNaN(result[0])  # 90% instead of 95%
      failureCondition: result[0] < 0.90 && !isNaN(result[0])
```

**Cause 3: Infrastructure instability (Prometheus, network)**

Check if the rollbacks correlate with infrastructure events:

```bash
# Check for recent cluster events
kubectl get events --all-namespaces --sort-by=.lastTimestamp | tail -30

# Check Prometheus health
kubectl get pods -n monitoring
```

---

## Scenario 4: Rollout in Degraded Phase

### Alert: `RolloutDegraded` (warning)

**Definition**: Rollout phase is Degraded (not all replicas available).

### Causes

1. An abort was triggered but some pods failed to terminate cleanly
2. The stable version itself has unhealthy pods
3. PVC binding issues during replica restart

### Resolution

```bash
# Check what is degraded
kubectl argo rollouts get rollout <ROLLOUT_NAME> -n <NAMESPACE>
kubectl get pods -n <NAMESPACE> -l app=<APP_NAME>

# For most cases: undo to previous known-good revision
kubectl argo rollouts undo <ROLLOUT_NAME> -n <NAMESPACE>

# If undo doesn't help, check pod events
kubectl describe pod <FAILING_POD> -n <NAMESPACE>
```

---

## Manual Rollback Procedures

### Procedure 1: Quick abort (rollout in progress)

Stops the current rollout immediately and reverts all traffic to stable:

```bash
kubectl argo rollouts abort <ROLLOUT_NAME> -n <NAMESPACE>
# Rollout enters Degraded phase — traffic is on stable

# Confirm traffic is back on stable service
kubectl get endpoints <APP_NAME>-stable -n <NAMESPACE>
```

### Procedure 2: Full rollback to previous revision

```bash
# List revisions
kubectl argo rollouts history rollout <ROLLOUT_NAME> -n <NAMESPACE>

# Rollback to previous revision
kubectl argo rollouts undo <ROLLOUT_NAME> -n <NAMESPACE>

# Or rollback to specific revision
kubectl argo rollouts undo <ROLLOUT_NAME> --to-revision=N -n <NAMESPACE>

# Watch rollback progress
kubectl argo rollouts get rollout <ROLLOUT_NAME> -n <NAMESPACE> --watch
```

### Procedure 3: Emergency — bypass Argo Rollouts

Use only if the controller is non-functional:

```bash
# Find stable ReplicaSet
kubectl get rs -n <NAMESPACE> -l app=<APP_NAME> --sort-by=.metadata.creationTimestamp

# Scale stable up to full capacity
kubectl scale rs <STABLE_RS_NAME> --replicas=<DESIRED_COUNT> -n <NAMESPACE>

# Scale canary down to 0
kubectl scale rs <CANARY_RS_NAME> --replicas=0 -n <NAMESPACE>

# Fix service selectors manually if needed
kubectl patch svc <APP_NAME>-stable -n <NAMESPACE> \
  -p '{"spec":{"selector":{"app":"<APP_NAME>","rollouts-pod-template-hash":"<STABLE_HASH>"}}}'
```

> **IMPORTANT**: After emergency bypass, update the Rollout manifest in git and let ArgoCD sync to restore normal operation.

---

## Controller Troubleshooting

### Controller is not processing rollouts

```bash
# Check controller pod
kubectl get pods -n argocd -l app.kubernetes.io/name=argo-rollouts

# Check for OOM or crash
kubectl describe pod <CONTROLLER_POD> -n argocd

# Restart controller
kubectl rollout restart deploy/argo-rollouts -n argocd

# Check logs after restart
kubectl logs -n argocd deploy/argo-rollouts --tail=50
```

### RBAC errors in controller logs

```bash
# Check ClusterRole
kubectl get clusterrole argo-rollouts -o yaml | grep -A20 "rules:"

# If missing permissions, re-apply Helm chart
helm upgrade argo-rollouts argo/argo-rollouts \
  --namespace argocd \
  --reuse-values \
  --version 2.35.0
```

### Prometheus connectivity issues

```bash
# Test Prometheus access from argocd namespace
kubectl exec -n argocd deploy/argo-rollouts -- \
  wget -qO- http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/-/healthy

# If failing, check NetworkPolicy
kubectl get netpol -n monitoring
kubectl get netpol -n argocd
```

---

## Post-Incident Actions

After any rollback or investigation:

1. **Document the failure**: Add entry to ops log
2. **Root cause analysis**: Was it code, infrastructure, or threshold issue?
3. **Update AnalysisTemplate**: If threshold was too strict, create a service-specific template
4. **Update developer guide**: If a new failure pattern was discovered
5. **Check ArgoCD sync status**: Ensure ArgoCD shows in-sync state after incident resolution

```bash
# Verify ArgoCD sync status for the affected app
kubectl get application -n argocd | grep <APP_NAME>
```

---

## References

- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [ADR-085: Progressive Delivery Strategy](../adr/adr-085-argo-rollouts-progressive-delivery.md)
- [Developer Guide](../guides/progressive-deployment-strategies.md)
- [Grafana Dashboard: Deployment Progress](/d/argo-rollouts-deployment-progress)
- [Grafana Dashboard: Health Overview](/d/argo-rollouts-health)
- [PrometheusRules](../../domains/observability/infra/alerts/argo-rollouts-prometheus-rules.yaml)
