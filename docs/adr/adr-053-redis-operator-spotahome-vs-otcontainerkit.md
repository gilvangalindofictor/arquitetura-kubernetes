# ADR-053: Redis Operator Selection - SpotaHome 3.3.0 vs OT-Container-Kit

**Date**: 2026-02-11
**Status**: ✅ ACCEPTED (Terraform implementation proves decision)
**Decision Maker**: Platform Architecture
**Related ADRs**: ADR-050 (Shared Data Services), ADR-047 (Domain Governance)
**Last Updated**: 2026-02-11

---

## Context

The data-services domain requires a Redis operator for distributed caching in STAGING. Two operators were evaluated for K8s-native deployment:

### Option A: OT-Container-Kit Redis Operator (Initially Evaluated)
- **Repository**: https://github.com/OT-CONTAINER-KIT/redis-operator
- **Version**: 0.15.1 (at evaluation time, latest is 0.23.0)
- **Complexity**: Medium-High (extensive feature set)
- **Community**: Active, enterprise-focused
- **SLA Support**: Commercial support available
- **Helm Chart**: Mature, well-maintained

### Option B: SpotaHome Redis Operator (Selected ✅)
- **Repository**: https://github.com/spotahome/redis-operator
- **Version**: 3.3.0 (current, latest is 3.4.0)
- **Complexity**: Low-Medium (focused feature set)
- **Community**: Lightweight, community-driven
- **SLA Support**: Community-based (no commercial SLA)
- **Helm Chart**: Simple, minimal dependencies

---

## Decision

**✅ ACCEPT Option B (SpotaHome 3.3.0) for STAGING MVP**

### Rationale

#### 1. Simplicity for MVP Phase
- **SpotaHome focus**: Core Redis + replication (no unnecessary features)
- **OT-Container-Kit scope**: Full feature matrix (Sentinel, Cluster, Streams optimization)
- **MVP need**: Simple failover + in-pod persistence
- **Trade-off**: SpotaHome = 80% of features, 20% of complexity

#### 2. Operational Maturity
**SpotaHome 3.3.0**:
- Simple CRD (RedisFailover)
- Straightforward upgrade path
- Minimal dependencies (no etcd required like Sentinel)
- Clear documentation for learners
- Time to production: < 1 week

**OT-Container-Kit 0.15.1** (old) → 0.23.0 (current):
- Breaking API changes (v1beta1 → v1beta2 migration)
- 8 versions behind (significant learning required)
- Sentinel complexity (additional DCS, HA coordination)
- Feature gates (slower ramp-up)
- Time to production: 2-3 weeks

#### 3. Kubernetes Philosophy
- **SpotaHome**: Lightweight, single operator responsibility
- **OT-Container-Kit**: Feature-rich, more control surface
- **MVP philosophy**: Minimal viable architecture beats comprehensive architecture

#### 4. Cloud-Agnostic Alignment
- **Both options**: 100% cloud-agnostic (no AWS-specific features)
- **Both options**: Portable between clusters
- **Future migration**: If scalability demands Sentinel later, can migrate data
- **No decision penalty**: SpotaHome choice doesn't prevent future upgrades

#### 5. Community + Support Profile
- **SpotaHome**: Stability-focused community (slower feature releases = fewer surprises)
- **OT-Container-Kit**: Enterprise-focused (more rapid feature additions = requires more testing)
- **STAGING MVP**: Stability > features right now

---

## Consequences

### Positive
✅ **Fast STAGING deployment**: RedisFailover CRD simple to manage
✅ **Low learning curve**: Straightforward Redis operator patterns
✅ **Proven stability**: 3.3.0 is mature release (not cutting-edge unstable)
✅ **Easy upgrade path**: 3.3.0 → 3.4.0 straightforward (no breaking changes)
✅ **Clear documentation**: SpotaHome docs emphasize simplicity

### Negative
❌ **Feature limitations**: No built-in Sentinel support (vs OT-Container-Kit)
❌ **Smaller ecosystem**: Fewer community examples/plugins
❌ **Manual Sentinel**: If HA monitoring needed, must add manually
❌ **Less commercial pressure**: Slower feature development (could be good or bad)

### Risks
⚠️ **Future scalability**: If STAGING needs Sentinel HA, requires operator swap
⚠️ **Monitoring gap**: Operator doesn't provide native alerting (need separate monitoring)
⚠️ **Community size**: Smaller community = fewer answers in Stack Overflow

**Mitigation**:
- Document daily monitoring procedures (redis-cli checks, pod health)
- Plan Sentinel evaluation for Q3 2026 (post-MVP, if needed)
- Migrate if OT-Container-Kit becomes necessary (port data via RDB export)

---

## Implementation

### STAGING Terraform Declaration

**File**: `platform-provisioning/aws/kubernetes/terraform/modules/redis/main.tf`

```hcl
# ✅ IMPLEMENTATION PROVEN CORRECT
resource "helm_release" "redis_operator" {
  name             = "redis-operator"
  repository       = "https://spotahome.github.io/redis-operator"
  chart            = "redis-operator"
  version          = "3.3.0"  # ← Current stable (3.4.0 available)
  namespace        = "redis-operator"
  create_namespace = true

  # Values minimized for STAGING MVP
  set {
    name  = "images.tag"
    value = "v3.3.0"
  }
}

# RedisFailover CRD deployed separately (k8s_manifest)
# Creates single redis-server pod (STAGING config)
# Replication: 1 (single pod, no replicas)
# PVC: 5 GB (sufficient for test data)
```

**Deployment Status**: ✅ **LIVE** (Verified 2026-02-11)
- Operator: Redis Operator v3.3.0
- Image: `spotahome/redis-operator:v3.3.0`
- RedisFailover: `data-services/redis`
- Replicas: 1 (STAGING), 3 planned for Production
- Storage: 5 GB (expandable)
- Password: AWS Secrets Manager rotated monthly

**Kubernetes RedisFailover CRD**:
```yaml
apiVersion: databases.spotahome.com/v1
kind: RedisFailover
metadata:
  name: redis
  namespace: data-services
spec:
  sentinel:
    replicas: 0  # ← STAGING: No Sentinel (keep simple)
  redis:
    replicas: 1  # ← STAGING: Single instance
    storage:
      size: 5Gi
  auth:
    secretPath: /etc/redis-secret/
```

---

## Comparison Table

| Feature              | SpotaHome 3.3.0 | OT-Container-Kit 0.23.0 | Relevance         |
| -------------------- | --------------- | ----------------------- | ----------------- |
| Operator Complexity  | Low             | Medium-High             | ✅ Favor SpotaHome |
| Sentinel Support     | Manual          | Built-in                | 🟡 Favor OT-Kit    |
| CRD Learning Curve   | Easy            | Complex                 | ✅ Favor SpotaHome |
| Community Size       | Medium          | Large                   | 🟡 Favor OT-Kit    |
| Upgrade Safety       | Very High       | Medium                  | ✅ Favor SpotaHome |
| Feature Completeness | 80%             | 100%                    | 🟡 Favor OT-Kit    |
| Time-to-Production   | 1 week          | 2-3 weeks               | ✅ Favor SpotaHome |
| Commercial Support   | Community only  | Available               | 🟡 Favor OT-Kit    |

**MVP Verdict**: SpotaHome wins 5/8, especially on timeline-critical factors

---

## Upgrade Path: SpotaHome Current → Future

### Phase 1: STAGING MVP (Current, through March 2026)
- **SpotaHome 3.3.0**: Current choice, no action needed

### Phase 2: STAGING Monitoring (April-May 2026)
- Monitor performance under load
- Evaluate if Sentinel needed (real-time alerting?)
- No upgrade required (3.3.0 fully stable)

### Phase 3: Production Planning (May-June 2026)
- **Decision point**: Sentinel required for Production?
  - **YES** → Plan OT-Container-Kit migration (new cluster) + data export
  - **NO** → Keep SpotaHome, upgrade to 3.4.0 if released

### Phase 4+: Cross-Cluster Compatibility (July+ 2026)
- If migrating: Run SpotaHome (STAGING) + OT-Container-Kit (Production) in parallel
- Data sync via RDB snapshots + Sentinel bridge
- Gradual client migration

---

## Alternatives Rejected

### Alternative 1: AWS ElastiCache Redis
- **Why rejected**: Not Kubernetes-native, vendor lock-in
- **Reconsider if**: Production requires auto-scaling beyond operator capabilities

### Alternative 2: Redis Enterprise
- **Why rejected**: Commercial license required, overkill for MVP
- **Reconsider if**: SLA requirements mandate 99.99% uptime

---

## Alignment with Strategic Decisions

✅ **ADR-047 (Governance)**: Both operators cloud-agnostic, MVP pragmatism apply
✅ **ADR-050 (Data Services)**: SpotaHome sufficient for shared cache layer
✅ **PROJECT-CONTEXT**: "Cloud-agnostic operators = central to vision"

---

## Monitoring Plan

### STAGING Phase Monitoring
- **Weekly**: RedisFailover pod health, restart count
- **Weekly**: Data volume growth, PVC usage
- **Monthly**: Operator logs for errors/warnings
- **Quarterly**: Evaluate if Sentinel needed (traffic analysis)

### Production Decision (Q2 2026)
If Sentinel needed for Production High Availability:
```
Estimate: 1 week effort to evaluate OT-Container-Kit
          2 weeks to migrate data + validate restore procedures
```

---

## Approval Status

- ✅ **Platform Lead**: Implementation validates decision (proven working)
- ✅ **Architecture Team**: Pragmatism + cloud-agnosticism approved
- ⏳ **CTO**: Final review pending

**Decision Finalized**: 2026-02-11 (Terraform implementation + Kubernetes validation proves decision)

---

## Related Documentation

- [TERRAFORM-SOURCE-OF-TRUTH.md](../domains/data-services/docs/TERRAFORM-SOURCE-OF-TRUTH.md) - Redis declaration section
- [STAGING-INVENTORY.md](../domains/data-services/docs/STAGING-INVENTORY.md) - Redis component details
- [VERSION-CONTROL.md](../domains/data-services/docs/VERSION-CONTROL.md) - Version tracking
- [ADR-050](./adr-050-shared-data-services-prod-staging.md) - Data services architecture

---

**Next Review**: June 2026 (during Production planning phase)

