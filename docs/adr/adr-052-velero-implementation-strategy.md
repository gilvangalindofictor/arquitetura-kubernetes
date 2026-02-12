# ADR-052: Velero Backup Strategy - Implementation Deferral for STAGING MVP

**Date**: 2026-02-11
**Status**: 🟡 PENDING CTO DECISION
**Decision Maker**: CTO + Platform Architecture
**Related ADRs**: ADR-051 (PostgreSQL RDS), ADR-005 (Logging Strategy), ADR-022 (FinOps)
**Last Updated**: 2026-02-11

---

## Context

The data-services domain handles mission-critical data (databases, message queues, caches). Backup/restore strategy must address:

1. **PostgreSQL backups**: RDS automated (7-day retention) ✅
2. **Redis persistence**: Operator handles RDB snapshots + AOF ✅
3. **RabbitMQ persistence**: Quorum queues only without backup
4. **Disaster Recovery**: Zero Kubernetes namespace backup capability
5. **Data Recovery**: No automated restore path for application data

### Velero: What's the Gap?

**Velero provides**:
- Kubernetes cluster-wide backup (all namespaces, all resources)
- Namespace-level restore capabilities
- S3-based backup storage with lifecycle policies
- Scheduled backup automation
- Disaster recovery procedures

**Current STAGING implementation**:
❌ **Zero Velero deployment** (deliberately absent from Terraform)
✅ **S3 bucket prepared**: `platform-backups` (empty, ready for use)
✅ **RDS backups configured**: 7-day retention, automated daily
⚠️ **Redis/RabbitMQ**: HA via replication, NO backup protection

---

## Problem Statement

### Backup Coverage Gaps (STAGING)

| Component  | Backup Type                | Status                  | Risk                           |
| ---------- | -------------------------- | ----------------------- | ------------------------------ |
| PostgreSQL | RDS automated              | ✅ PROTECTED (7 days)    | Low (AWS-managed)              |
| Redis      | Operator RDB               | 🔄 PARTIAL (in-pod only) | Medium (loss on pod deletion)  |
| RabbitMQ   | None (HA replication only) | ❌ UNPROTECTED           | High (quorum loss = data loss) |
| Kubernetes | None                       | ❌ UNPROTECTED           | CRITICAL (config loss)         |

---

## Options Evaluated

### Option A: Implement Velero Now (STAGING)
- **Scope**: Full K8s namespace backup + restore
- **Effort**: 2-3 weeks (Terraform module + helm_release + testing)
- **Cost**: ~$5-10/month (S3 storage minimal, mostly free tier)
- **Benefit**: Complete disaster recovery capability
- **ROI**: Low for MVP phase (STAGING data is test data, can be recreated)

**Pros**:
✅ Future-proof (ready for Production)
✅ Validates backup/restore processes now
✅ Minimal incremental S3 cost

**Cons**:
❌ 2-3 weeks timeline (blocks other priorities)
❌ Operational overhead (test restores regularly)
❌ Incremental complexity (another Helm release to manage)
❌ STAGING MVP data is disposable anyway

---

### Option B: Defer Velero to Production Phase (Recommended ✅)
- **STAGING**: Accept backup gaps, document risk
- **Production**: Implement Velero as production-readiness requirement (Phase 2)
- **Timeline**: Phase 2-3 (Apr-Jul 2026)
- **Effort Shift**: Concentrate on STAGING stability now, backup strategy later

**Pros**:
✅ Faster STAGING completion (unblocks delivery)
✅ Proven disaster recovery plan in Production context
✅ Learn from STAGING MVPs before Production bet
✅ Users expect gaps in MVP, not Production

**Cons**:
❌ STAGING data unprotected (acceptable risk for MVP)
❌ No backup testing until Production (mitigated by simple restore strategy)

---

### Option C: Hybrid Approach (Partial Velero)
- **STAGING**: Velero for K8s config only (no application data)
- **PostgreSQL**: RDS backups suffice (decision from ADR-051)
- **Redis/RabbitMQ**: Skip for STAGING, HA provides resilience
- **Effort**: 1 week (Velero core only, no operators tested)

**Pros**:
✅ Partial protection (K8s config safe)
✅ Learning curve for Production implementation
✅ Reasonable effort (1 week vs 3 weeks)

**Cons**:
❌ Incomplete protection (application data not backed)
❌ Still operational overhead
❌ Not recommended: Better to skip entirely (Option B) or do full (Option A)

---

## Recommendation

**✅ ACCEPT Option B: Defer Velero to Production Phase**

### Rationale

#### 1. MVP Risk Tolerance
- **STAGING data criticality**: Low (test data, can be recreated in hours)
- **STAGING failure scenario**: Re-run setup scripts, restore from git, re-populate test data
- **Recovery time**: < 2 hours (acceptable for MVP)
- **MVP philosophy**: Fast delivery > perfect protection

#### 2. Production Will Require Full Strategy Anyway
- Production RDS: Multi-AZ RDS backups (AWS-managed)
- Production Redis: Velero provides namespace-level restore + RDB snapshots
- Production RabbitMQ: Velero for cluster config + queue recovery via replay
- **Better to design for Production context** where stakes are higher

#### 3. Time Budget Optimization
- **STAGING MVP remaining**: ~3 weeks (Marco 3 final integration)
- **Velero effort**: 2-3 weeks (module, helm_release, testing, docs)
- **Opportunity cost**: Delay other STAGING features (CD/CI improvements, observability enhancements)
- **Better use**: Stabilize STAGING MVP, then plan Production phase

#### 4. Learning Value
- **Deploying Velero in Production** with clear requirements > Deploying in STAGING "just in case"
- **Test restore procedures in Production** where failure cost drives diligence
- **Captured learnings** inform future cloud-agnostic backup strategy

---

## Decision

**✅ ACCEPT Option B (Defer Velero to Production Phase)**

### STAGING Phase (Current - Through March 2026)

**Zero Velero Implementation**:
```hcl
# Terraform: NO velero helm_release declared
# S3 bucket "platform-backups" prepared but unused
# Status: Deliberate gap, acceptable for MVP
```

**Backup Coverage STAGING**:
- ✅ PostgreSQL: RDS 7-day automated backups
- 🔄 Redis: Operator in-pod RDB (no distributed backup)
- ❌ RabbitMQ: None (rely on quorum HA)
- ❌ Kubernetes: None (config tracked in git)

**Risk Acceptance**:
```
STAGING Failure Scenario Recovery Plan:
1. Kubernetes failure → Re-run terraform apply (IaC recovery)
2. PostgreSQL failure → AWS RDS restore from backup
3. Redis failure → Kubernetes pod restart (replicas reconstruct data)
4. RabbitMQ failure → Pod restart, replay messages from producers

Total recovery time: < 2 hours (acceptable for MVP)
```

### Production Phase (Q2-Q3 2026)

**Decision Required from CTO**:

```
Before Production launch (est. June 2026), decide:

A) Lightweight backup (RDS only, accept K8s config loss)
   - Cost: Very low ($20/month S3)
   - Coverage: Database protected only
   - OK for: Stateless workloads, config in git

B) Standard backup (Full Velero)
   - Cost: Medium ($50-100/month S3)
   - Coverage: Complete disaster recovery
   - OK for: Risk-averse orgs, complex stateful apps

C) Enterprise backup (Velero + off-site replication)
   - Cost: High ($200+/month)
   - Coverage: Cross-region backup, 3-copy rule
   - OK for: SLA requirements > 99.95%

Current recommendation: Option B (Standard)
Timeline: Implement 2 weeks before Production launch
```

---

## Implementation

### STAGING (Current): Zero Changes

```bash
# Verify NO Velero in Terraform:
grep -r "velero\|backup.*restore" \
  platform-provisioning/aws/kubernetes/terraform/modules/ \
  platform-provisioning/aws/kubernetes/terraform/environments/staging/

# Result: ZERO matches (deliberate)
# S3 bucket exists (platform-backups) but unused
```

### Future: Production Implementation (Phase 2, Apr-Jul 2026)

**ADR-XXX** (to be created): "Velero Production Implementation"

```hcl
# Planned Terraform structure:
# modules/velero/
#   ├── main.tf          # Helm release + RBAC
#   ├── s3.tf            # S3 bucket policy
#   ├── variables.tf     # Configurable backup retention
#   └── outputs.tf       # Velero endpoint for testing

# environments/production/
#   ├── velero.tf        # Production backup schedule
#   │                    # (daily 03:00 UTC, 30-day retention)
#   │
```

---

## Monitoring & Decisions

### STAGING Phase Monitoring
- ✅ Weekly: RDS backup size, retention verification
- ✅ Monthly: S3 cost tracking (should be ~$0 now)
- 🚨 Immediately: Report any data loss to Architecture team

### Decision Point: Q2 2026 Planning
**April 2026 Decision**: Velero for Production — Which option (A/B/C from above)?
- **Input needed**: CTO risk tolerance, SLA requirements, budget constraints
- **Timeline**: Must decide by mid-April for June Production launch

---

## Alignment with Strategic Decisions

✅ **ADR-051 (PostgreSQL RDS)**: RDS backups satisfy DB backup needs
✅ **ADR-047 (Governance)**: MVP pragmatism, Production robustness
✅ **ADR-022 (FinOps)**: Cost-optimized for STAGING, full coverage for Production

---

## Risk Register

| Risk                          | Probability | Impact | Mitigation                                |
| ----------------------------- | ----------- | ------ | ----------------------------------------- |
| STAGING data loss (Redis/RMQ) | Low         | Low    | Re-deploy operators, data reconvergence   |
| Production unprepared (delay) | Medium      | Medium | Plan Velero in Q2 now, allocate resources |
| S3 bucket unused complexity   | Low         | Low    | Velero will use it, no wasted investment  |

---

## Approval Status

- ⏳ **CTO**: Review and approval **REQUIRED**
- ⏳ **Platform Lead**: Technical validation pending
- ⏳ **Architecture Team**: Risk acceptance pending

**Pending Input**: CTO decision on Production backup strategy (deadline: April 2026)

---

## Related Documentation

- [TERRAFORM-SOURCE-OF-TRUTH.md](../domains/data-services/docs/TERRAFORM-SOURCE-OF-TRUTH.md) - "Velero: Not declared" section
- [STAGING-BACKUP-STRATEGY.md](../domains/data-services/docs/STAGING-BACKUP-STRATEGY.md) - Detailed backup gaps analysis
- [ADR-051](./adr-051-postgresql-rds-vs-operator.md) - PostgreSQL backup strategy (RDS)
- [ADR-022](./adr-022-finops-automation-strategy.md) - Cost optimization strategy

---

**Decision Finalized**: Pending CTO approval (2026-02-11)

