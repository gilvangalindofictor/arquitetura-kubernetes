# ADR-085: Argo Rollouts Progressive Delivery Strategy

**Date**: 2026-02-26
**Status**: ACCEPTED
**Decision Maker**: Platform Architecture + CTO
**Related ADRs**: ADR-004 (Terraform vs Helm), ADR-077 (ApplicationSets GitOps), ADR-084 (Immutable Image Tags)
**Demand**: CICD-005

---

## Context

### Background

The K8s Platform CI/CD stack (Marco 4) is fully operational as of 2026-02-25:
- GitLab CI/CD: end-to-end pipelines with build/scan/deploy stages
- ArgoCD: GitOps with ApplicationSets and 7 auto-generated Applications
- Harbor: Container registry with immutable image tags (CICD-004/ADR-084)
- Prometheus + Grafana: Full observability stack

The current deploy mechanism (`deploy.gitlab-ci.yml`) uses `kubectl set image deployment/<name>` — a direct Kubernetes rolling update. This provides zero traffic control: the moment a new pod is scheduled, it immediately enters the load balancer rotation.

### Problem

With the current rolling update approach:

1. **No traffic graduation**: 100% traffic shifts to new replicas as they become ready. No way to send 10% to the new version while analyzing error rates.
2. **No automated rollback on metrics degradation**: If the new version introduces a regression (5xx spike, latency increase), ArgoCD notices only if the pod crashes. Subtle regressions (increased error rate without crashes) are invisible to the pipeline.
3. **No blue-green isolation**: Pre-production validation runs against staging data, not production traffic patterns. Blue-green would allow live validation on production traffic before completing the switch.
4. **Manual rollback only**: Engineers must intervene manually to rollback. MTTR increases.

### Argo Rollouts Capability

Argo Rollouts is the de-facto Kubernetes progressive delivery controller. It replaces the standard `Deployment` controller with a `Rollout` CRD that supports:
- **Canary**: Incremental traffic shifting with automated analysis gates
- **Blue-Green**: Parallel environment deployment with manual or automated promotion
- **AnalysisRun**: Pluggable metric analysis via Prometheus, Datadog, New Relic, etc.
- **Auto-rollback**: Reverts to stable version if analysis fails
- **GitOps-native**: Full ArgoCD integration (Rollout CRDs appear in ArgoCD UI)

---

## Decision

**ACCEPT: Implement Argo Rollouts Progressive Delivery (CICD-005)**

### Deployment Model

Argo Rollouts is deployed as a Helm release in the existing `argocd` namespace. This co-location pattern is intentional:
- ArgoCD already manages the namespace lifecycle
- Both components share RBAC (ArgoCD manages Rollout sync; Rollouts controller manages pod updates)
- Reduces namespace sprawl (avoids creating `argo-rollouts` namespace)
- Consistent with how ArgoCD ApplicationSets manage rollouts in the GitOps model

### Strategy Selection Framework

The strategy choice depends on the risk profile of the change:

| Criterion | Use Canary | Use Blue-Green |
|-----------|-----------|----------------|
| Change type | High-risk (DB migrations, API changes) | Low-risk (feature flags, config changes) |
| Traffic validation needed | Yes (gradual % increase) | No (full traffic validation at once) |
| Instant rollback priority | Medium | High (single service pointer swap) |
| Pre-production validation | Partial (traffic slice) | Full (preview environment) |
| Resource overhead during deploy | Low (extra replica or two) | High (2x replicas during transition) |
| Example use cases | Schema migration, ML model update | Feature flag, A/B test infrastructure |

**Default recommendation**: **Canary** for most deployments. Blue-Green for scenarios requiring instant switchback or parallel environment validation.

### Analysis-Driven vs Time-Based Progression

Two modes are supported:

**Analysis-driven (preferred)**: AnalysisTemplate queries Prometheus. Rollout progresses only when metrics are healthy. Automated rollback if thresholds are violated.

**Time-based (fallback)**: For applications that do not expose `http_requests_total` or `http_request_duration_seconds`. Progression is time-gated only (pause between steps). Provides no automated rollback — relies on human observation.

**CRITICAL REQUIREMENT**: Applications MUST expose:
```
http_requests_total{status="<code>", service="<name>"}  (Prometheus counter)
http_request_duration_seconds_bucket{le="...", service="<name>"}  (Prometheus histogram)
```

If the application does not expose these metrics, AnalysisTemplates will return NaN and the `isNaN()` check treats it as healthy (time-based safety net). Teams must document this in their Rollout manifest.

### AnalysisTemplate Library

Four reusable templates are provided in `domains/apps/manifests/analysis-templates/`:

| Template | Threshold | Failure Limit | Use Case |
|----------|-----------|--------------|----------|
| `success-rate` | >= 95% | 2 consecutive failures | Primary gate (all services) |
| `latency-p95` | < 500ms | 2 consecutive failures | Primary gate (all services) |
| `error-rate-4xx` | < 5% | 2 consecutive failures | API-heavy services |
| `error-rate-5xx` | < 1% | 1 failure | Critical: strict threshold |

Templates use `isNaN()` safety: if the app produces no traffic (new deployment, cold start), NaN results are treated as healthy. This prevents false rollbacks on cold starts.

### Canary Step Configuration

The standard canary progression is:
```
20% → (analysis: success-rate + latency-p95) → 5min pause
40% → 5min pause
60% → 5min pause
80% → 5min pause
100% → promotion complete
```

Total minimum rollout time: ~20 minutes (4 x 5min pauses + analysis time).
This is acceptable for production deployments where stability > speed.

For development/staging environments, teams can reduce pause duration to 1-2 minutes.

### GitLab CI Integration

Progressive delivery is integrated into the CI pipeline as new stages:
```
stages:
  - build
  - scan
  - deploy      # rollout-deploy: sets new image
  - verify      # rollout-verify: watches until complete or paused
  - promote     # rollout-promote: manual gate (Blue-Green)
                # rollout-abort: emergency rollback
```

The `rollout-promote` job is `when: manual` — requiring human approval in the GitLab UI for Blue-Green promotions. For Canary, promotion is automatic when all analysis passes.

---

## Alternatives Considered

### Alternative 1: Flagger

Flagger (Weaveworks) is a Kubernetes progressive delivery operator.

**Why rejected**:
- Heavier integration with Istio/Linkerd service mesh (we run without a service mesh)
- Less mature ArgoCD integration compared to Argo Rollouts
- Argo Rollouts is in the same ecosystem (Argo Project) — team already familiar with ArgoCD

### Alternative 2: Standard Kubernetes rolling update with manual traffic splitting

Keep the current rolling update but add a manual traffic splitting step using multiple Deployments.

**Why rejected**:
- High operational overhead (manual service weight adjustments)
- No automated analysis or rollback
- Not GitOps-compatible without custom tooling

### Alternative 3: Spinnaker

Full continuous delivery platform with advanced traffic management.

**Why rejected**:
- Significant operational complexity (requires persistent storage, multiple microservices)
- Not cloud-native (K8s-native alternatives are lighter)
- Overkill for current platform scale

---

## Consequences

### Positive

1. **Automated rollback**: 5xx spikes and latency regressions are detected automatically via Prometheus analysis. No human intervention required for rollback in most cases.
2. **Incremental risk**: Canary limits blast radius. A bad deploy affects only 20% of traffic initially.
3. **GitOps-native**: Rollouts appear in ArgoCD UI, synced via ApplicationSets. Full GitOps compliance.
4. **Observability**: Prometheus metrics (`argo_rollout_info`, `argo_analysis_run_info`) feed into Grafana dashboards and alerts.
5. **Immutable tag alignment**: Works with CICD-004 immutable tags (sha-${CI_COMMIT_SHA}).

### Negative / Trade-offs

1. **Migration effort**: Existing `Deployment` resources must be converted to `Rollout` resources. This is a one-time effort per service.
2. **Metric requirement**: Services without Prometheus metrics cannot use analysis-driven progression. They fall back to time-based pauses.
3. **Canary resource overhead**: During a canary rollout, an extra replica set exists. For services with 3+ replicas, this is ~1 extra pod.
4. **Blue-Green resource overhead**: During promotion, 2x replicas run for `scaleDownDelaySeconds` (5min). This is a temporary cost.
5. **Learning curve**: Developers must understand Rollout CRD vs Deployment. A developer guide is provided.

### Neutral

- The Argo Rollouts dashboard is read-only. Write operations (promote/abort) remain in GitLab CI or kubectl CLI.
- AnalysisTemplates are namespace-scoped: each application namespace needs the templates deployed.

---

## Implementation Plan

1. **Phase 1 (CICD-005 — 2026-02-26)**: Prepare all artifacts (Terraform module, AnalysisTemplates, CI template, dashboards, documentation). Deploy when environment is online.
2. **Phase 2 (TBD)**: Pilot with one low-risk service (e.g., sonarqube exporter). Validate analysis templates with real traffic.
3. **Phase 3 (TBD)**: Convert remaining services. Enforce Rollout as standard for all new applications.

---

## References

- [Argo Rollouts documentation](https://argoproj.github.io/argo-rollouts/)
- [Argo Rollouts Helm chart](https://github.com/argoproj/argo-helm/tree/main/charts/argo-rollouts)
- ADR-077: ApplicationSets GitOps Automation
- ADR-084: Immutable Image Tags Enforcement
- CICD-005 implementation: `platform-provisioning/aws/kubernetes/terraform/modules/argo-rollouts/`
