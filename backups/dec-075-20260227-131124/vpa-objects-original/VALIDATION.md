# VPA Configuration Validation Report

**Generated:** 2026-02-20
**Cluster:** EKS 1.34 staging (us-east-1)
**VPA Controller:** fairwinds v4.4.6

## Workload Discovery Summary

### ✅ Discovered Workloads

| Priority | Namespace | Workload | Type | Containers | Current Resources |
|----------|-----------|----------|------|------------|-------------------|
| **P0** | vault-system | vault | StatefulSet | vault | 500m/512Mi → 1000m/1Gi |
| **P0** | keycloak | keycloak-keycloakx | StatefulSet | keycloak | 1000m/2Gi → 2000m/4Gi |
| **P0** | gitlab-staging | gitlab-webservice-default | Deployment | webservice, workhorse | 500m/2Gi → 2000m/4Gi |
| **P0** | monitoring | prometheus-kube-prometheus-stack-prometheus | StatefulSet | prometheus, config-reloader | 100m/512Mi → 500m/2Gi |
| **P1** | harbor-system | harbor-core | Deployment | core | Not checked |
| **P1** | harbor-system | harbor-jobservice | Deployment | jobservice | Not checked |
| **P1** | monitoring | kube-prometheus-stack-grafana | Deployment | grafana, sc-dashboard, sc-datasources | Not checked |
| **P1** | argocd | argocd-server | Deployment | server | Not checked |
| **P2** | gitlab-staging | gitlab-sidekiq-all-in-1-v2 | Deployment | sidekiq | Not checked |
| **P2** | gitlab-staging | gitlab-gitaly | StatefulSet | gitaly | Not checked |
| **P2** | monitoring | loki-write | StatefulSet | loki | Not checked |
| **P2** | monitoring | tempo-ingester | StatefulSet | ingester | Not checked |

## Configuration Decisions

### 1. Resource Boundaries

**Philosophy:** Conservative minimums + generous maximums for 30-day discovery

- **minAllowed:** Set to ~50% of current requests (safety floor)
- **maxAllowed:** Set to 2-4x current limits (capture peak usage)

**Rationale:**
- VPA needs headroom to capture real peak usage patterns
- Too restrictive → truncated recommendations
- Too loose → wasteful during collection phase

### 2. Multi-Container Handling

**GitLab Webservice:**
- webservice: 250m/1Gi → 4000m/6Gi (main app)
- workhorse: 100m/128Mi → 1000m/1Gi (reverse proxy)

**Grafana:**
- grafana: 100m/256Mi → 1000m/1Gi (main app)
- sidecars: 50m/64Mi → 500m/512Mi (dashboard/datasource sync)

**Prometheus:**
- prometheus: 100m/512Mi → 2000m/4Gi (main app)
- config-reloader: 50m/64Mi → 500m/512Mi (config hot-reload)

### 3. StatefulSet vs Deployment

**StatefulSets (higher minimums):**
- vault: 250m/256Mi minimum (secret operations need stability)
- keycloak: 500m/1Gi minimum (SSO auth latency sensitive)
- prometheus: 100m/512Mi minimum (time-series DB)
- gitaly: 100m/256Mi minimum (git operations)
- loki-write: 100m/256Mi minimum (log ingestion)
- tempo-ingester: 100m/256Mi minimum (trace ingestion)

**Deployments (lower minimums):**
- Can scale horizontally more easily
- Tolerate more aggressive rightsizing

## Risk Assessment

### Low Risk
- updateMode: "Off" → no auto-apply
- minAllowed prevents under-provisioning
- maxAllowed prevents runaway resource requests

### Medium Risk
- VPA recommendations may suggest downsizing critical services
- **Mitigation:** Manual review before applying recommendations
- **Validation:** Test in staging before production

### High Risk
- None identified (recommendation-only mode)

## Pre-Deployment Checklist

- [ ] VPA CRD installed (`kubectl get crd verticalpodautoscalers.autoscaling.k8s.io`)
- [ ] VPA controller running (`kubectl get pods -n kube-system -l app=vpa-recommender`)
- [ ] Cluster metrics-server operational (`kubectl top nodes`)
- [ ] 30-day collection period scheduled (2026-02-20 to 2026-03-22)
- [ ] Baseline resource usage documented
- [ ] Cost baseline documented (current: R$ 38.372,80/year saved)

## Expected Data Collection

### Week 1-2 (Initial calibration)
- VPA builds baseline from current metrics
- Recommendations may be unstable
- Monitor for OOM kills or CPU throttling

### Week 3-4 (Pattern stabilization)
- Usage patterns emerge (business hours, batch jobs, etc)
- Recommendations stabilize
- Identify workloads with high variance

### Day 30 (Analysis ready)
- Export VPA recommendations: `kubectl get vpa -A -o json`
- Compare recommendations vs current configs
- Calculate potential savings
- Identify outliers (over/under-provisioned)

## Success Criteria

1. **Coverage:** All 12 VPA objects created successfully
2. **Data Quality:** ≥90% uptime for VPA recommender during 30 days
3. **Actionable Insights:** ≥8/12 workloads with stable recommendations
4. **Cost Savings:** Target R$ 8.712/year (as per MEMORY.md)

## Post-Collection Actions

1. Generate rightsizing report
2. Update Terraform/Helm values with new resource configs
3. Apply changes in staging → validate → production
4. Document savings in MEMORY.md
5. Schedule quarterly VPA review cycle

## Notes

- **Current VPA Status:** 12 VPA objects already exist (as per MEMORY.md)
- **This Task:** Redefine/validate VPA configurations for optimization
- **GitLab webservice:** Multi-container deployment requires per-container policies
- **Prometheus:** Time-series DB with variable memory usage (scrape intervals)
- **Keycloak:** SSO service with auth latency SLO (need adequate CPU)

## References

- MEMORY.md: VPA 12 workloads (30d → rightsizing)
- VPA Controller: fairwinds v4.4.6
- Cluster: EKS 1.34, t3.medium/large/xlarge nodes
- Target Savings: R$ 8.712/year (VPA rightsizing component)
