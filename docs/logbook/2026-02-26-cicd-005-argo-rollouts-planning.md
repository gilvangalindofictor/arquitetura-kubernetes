# Logbook: CICD-005 Argo Rollouts Progressive Delivery

**Date**: 2026-02-26
**Type**: CI/CD Enhancement — Progressive Delivery
**Status**: READY FOR DEPLOYMENT (environment offline)
**Duration**: Preparation phase (all artifacts created, deployment pending cluster startup)
**Demand**: CICD-005
**Related**: ADR-085, ADR-084 (Immutable Tags), ADR-077 (ApplicationSets)

---

## Summary

Prepared all artifacts for Argo Rollouts progressive delivery on the K8s Platform. The implementation provides canary and blue-green deployment strategies with Prometheus-driven automated rollback.

**Total deliverables**: 18 files across 7 categories

| Category | Files | Status |
|----------|-------|--------|
| Terraform Module | 4 files | READY |
| AnalysisTemplates | 4 files | READY |
| Rollout Examples | 2 files | READY |
| GitLab CI Template | 1 file | READY |
| PrometheusRules | 1 file | READY |
| Grafana Dashboards | 2 files | READY |
| Documentation | 4 files (ADR + guide + runbook + logbook) | READY |

---

## Context

### Why Now

Marco 4 is 100% complete (2026-02-25). All 8 GAPs done, all 8 vulnerabilities remediated. The CI/CD pipeline is fully functional:
- GitLab CI: build/scan/deploy templates operational
- Harbor: container registry with immutable tags (CICD-004, ADR-084)
- ArgoCD: GitOps with ApplicationSets (GAP-006, ADR-077)
- Prometheus + Grafana: full observability

Progressive delivery was identified as the next CI/CD maturity step. The current `kubectl set image deployment/...` approach provides no traffic graduation, no automated rollback, and no pre-production validation.

### Technical Context

- Argo Rollouts chart version: 2.35.0 (argoproj/argo-helm)
- Namespace: `argocd` (co-located with ArgoCD, no new namespace)
- Prometheus URL: `http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`
- AnalysisTemplates are namespace-scoped — deployed to each application namespace

---

## Architecture Decisions

Key decisions documented in ADR-085:

1. **Argo Rollouts over Flagger**: Same ecosystem as ArgoCD, better GitOps integration
2. **Co-located in argocd namespace**: Avoids namespace sprawl, shares RBAC with ArgoCD
3. **Canary as default strategy**: Lower resource overhead than Blue-Green, analysis-driven progression
4. **Blue-Green for instant switchback scenarios**: Feature flags, A/B testing infrastructure
5. **Analysis-driven with NaN safety**: `isNaN()` guard prevents false rollbacks on cold starts
6. **failureLimit: 2 for most templates, 1 for 5xx**: Fail fast on server errors, tolerant on others

---

## Deliverables Created

### Terraform Module: `modules/argo-rollouts/`

```
platform-provisioning/aws/kubernetes/terraform/modules/argo-rollouts/
├── main.tf          # helm_release + ServiceMonitor + ConfigMap (index)
├── variables.tf     # metrics_enabled, prometheus_url, dashboard_enabled, etc.
├── outputs.tf       # release_name, release_status, dashboard_access_command
└── values.yaml.tpl  # Helm values: HA replicas, metrics port 8090, dashboard port 3100
```

Key design choices:
- `create_namespace = false`: namespace managed by argocd module
- `kubernetes_manifest` for ServiceMonitor (not in-chart, avoids CRD ordering issues)
- `kubernetes_config_map` for analysis templates index (documentation-as-code)

### AnalysisTemplate Library: `domains/apps/manifests/analysis-templates/`

```
domains/apps/manifests/analysis-templates/
├── success-rate.yaml      # HTTP success rate >= 95% | failureLimit: 2
├── latency-p95.yaml       # P95 latency < 500ms | failureLimit: 2
├── error-rate-4xx.yaml    # 4xx error rate < 5% | failureLimit: 2
└── error-rate-5xx.yaml    # 5xx error rate < 1% | failureLimit: 1 (strict)
```

All templates use `isNaN()` safety pattern:
```yaml
successCondition: result[0] >= 0.95 || isNaN(result[0])
failureCondition: result[0] < 0.95 && !isNaN(result[0])
```

This prevents false rollbacks when canary pods are warming up and no traffic has been routed yet.

### Rollout Examples: `domains/apps/manifests/rollouts/`

```
domains/apps/manifests/rollouts/
├── canary-example.yaml      # 20%→40%→60%→80%→100%, 5min pauses, analysis from step 1
└── blue-green-example.yaml  # autoPromotionEnabled: false, scaleDownDelay: 300s, pre+post analysis
```

Canary example includes both stable and canary Service resources (required for traffic splitting).
Blue-Green example includes both active and preview Service resources.

### GitLab CI Template

```
domains/cicd-platform/infra/gitlab-ci/templates/argo-rollouts.gitlab-ci.yml
```

Jobs:
- `.deploy-analysis-templates`: deploys AnalysisTemplate library to target namespace (idempotent)
- `rollout-deploy`: sets new image, triggers rollout, shows initial progress
- `rollout-verify`: watches until complete, paused, or failed
- `rollout-promote`: manual gate for Blue-Green (`when: manual`)
- `rollout-abort`: emergency rollback (`when: manual`)

Image: `argoproj/kubectl-argo-rollouts:latest` (official plugin image)

### PrometheusRules

```
domains/observability/infra/alerts/argo-rollouts-prometheus-rules.yaml
```

4 alerts:

| Alert | Severity | Trigger | Action |
|-------|----------|---------|--------|
| `RolloutStuck` | critical | Progressing > 30min | Investigate, promote or abort |
| `AnalysisFailed` | critical | AnalysisRun phase=Failed | Root cause analysis |
| `FrequentRollbacks` | warning | >3 rollbacks/1h | Check code quality, adjust thresholds |
| `RolloutDegraded` | warning | Rollout phase=Degraded | Undo to previous revision |

### Grafana Dashboards

```
domains/observability/infra/grafana/dashboards/
├── argo-rollouts-deployment-progress.json  # Real-time rollout progress
└── argo-rollouts-health.json               # Platform-wide health overview
```

**Deployment Progress dashboard** (UID: `argo-rollouts-deployment-progress`):
- Canary weight gauge (0-100%)
- Rollout phase stat with color mapping
- AnalysisRun phase stat
- Success rate time series (canary vs threshold)
- P95 latency time series (canary vs stable vs threshold)
- 5xx error rate comparison
- Rollout state table

**Health Overview dashboard** (UID: `argo-rollouts-health`):
- Summary stats: total rollouts, progressing, degraded, rollbacks (24h), promotions (24h)
- Success rate per service (bar gauge + time series)
- Rollback frequency bar chart
- Rollout duration time series (with 30min alert threshold line)
- AnalysisRun status table

Both dashboards use Prometheus datasource variable (`DS_PROMETHEUS`) for portability.

### Documentation

| File | Purpose |
|------|---------|
| `docs/adr/adr-085-argo-rollouts-progressive-delivery.md` | Architecture decision record |
| `docs/guides/progressive-deployment-strategies.md` | Developer guide: convert Deployment → Rollout, custom AnalysisTemplate |
| `docs/runbooks/argo-rollouts-troubleshooting.md` | SRE runbook: stuck rollout, failed analysis, frequent rollbacks, manual rollback |
| `docs/logbook/2026-02-26-cicd-005-argo-rollouts-planning.md` | This logbook |

---

## Deployment Instructions (Post-Cluster Startup)

When the environment comes back online:

### Step 1: Deploy Terraform module

```bash
cd platform-provisioning/aws/kubernetes/terraform/

# Add module invocation to main.tf (see below for snippet)
# Then:
terraform init
terraform plan -out=tfplan-cicd005.out
terraform apply tfplan-cicd005.out
```

Module invocation to add to `main.tf`:

```hcl
module "argo_rollouts" {
  source = "./modules/argo-rollouts"

  cluster_name      = var.cluster_name
  namespace         = "argocd"
  chart_version     = "2.35.0"
  metrics_enabled   = true
  dashboard_enabled = true
  prometheus_url    = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"

  depends_on = [module.argocd]
}
```

### Step 2: Verify deployment

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argo-rollouts
kubectl get svc -n argocd | grep rollouts
kubectl argo rollouts version
```

### Step 3: Deploy PrometheusRules

```bash
kubectl apply -f domains/observability/infra/alerts/argo-rollouts-prometheus-rules.yaml
kubectl get prometheusrule -n monitoring cicd005-argo-rollouts-alerts
```

### Step 4: Import Grafana dashboards

```bash
# Option A: Grafana UI (Dashboards → Import → Upload JSON)
# Files:
#   domains/observability/infra/grafana/dashboards/argo-rollouts-deployment-progress.json
#   domains/observability/infra/grafana/dashboards/argo-rollouts-health.json

# Option B: kubectl ConfigMap (if using Grafana sidecar)
kubectl create configmap grafana-dashboard-argo-rollouts-progress \
  --from-file=argo-rollouts-deployment-progress.json \
  -n monitoring
kubectl label cm grafana-dashboard-argo-rollouts-progress grafana_dashboard=1 -n monitoring
```

### Step 5: Pilot rollout (first service)

```bash
# Deploy AnalysisTemplates to pilot namespace
kubectl apply -f domains/apps/manifests/analysis-templates/ -n <PILOT_NAMESPACE>

# Copy and customize canary-example.yaml for pilot service
cp domains/apps/manifests/rollouts/canary-example.yaml /tmp/pilot-rollout.yaml
# Edit: name, namespace, image, service names, replica count

# Apply
kubectl apply -f /tmp/pilot-rollout.yaml -n <PILOT_NAMESPACE>

# Trigger rollout
kubectl argo rollouts set image pilot-app pilot-app=harbor.example.com/apps/pilot:sha-new -n <PILOT_NAMESPACE>

# Watch
kubectl argo rollouts get rollout pilot-app -n <PILOT_NAMESPACE> --watch
```

---

## Metric Requirements for Application Teams

Applications must expose these Prometheus metrics to use analysis-driven rollouts:

```
http_requests_total{status="<code>", service="<app-name>"}  (counter)
http_request_duration_seconds_bucket{le="<bound>", service="<app-name>"}  (histogram)
```

Teams without these metrics can use time-based progression only (no automated rollback). The developer guide covers both patterns.

---

## Known Limitations

1. **Namespace-scoped AnalysisTemplates**: Templates must be deployed to each application namespace. Platform library templates (`domains/apps/manifests/analysis-templates/`) serve as the canonical source.
2. **No Istio/service mesh**: Traffic splitting is pod-count based (Kubernetes service selector). For true weight-based splitting, a service mesh or ingress integration (NGINX/ALB) is needed. This is a Phase 2 concern.
3. **Blue-Green resource cost**: During the 5-minute grace period, 2x replicas run. This increases node resource usage temporarily.
4. **ArgoCD drift detection**: After manual abort/promote outside of ArgoCD, ArgoCD may show OutOfSync. This is expected — reconcile by pushing the desired state to git.
