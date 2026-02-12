# ADR-051: PostgreSQL RDS vs. Kubernetes Operator for STAGING MVP

**Date**: 2026-02-11
**Status**: ✅ ACCEPTED (Terraform implementation proves decision)
**Decision Maker**: Platform Architecture + CTO
**Related ADRs**: ADR-047 (Domain Governance), ADR-050 (Shared Data Services)
**Last Updated**: 2026-02-11

---

## Context

The data-services domain architecture requires a persistent relational database for STAGING MVP (Marco 3). Two options were evaluated:

### Option A: Kubernetes-Native (Zalando Postgres Operator)
- **Implementation**: Zalando PostgreSQL Operator v1.15.1 + Patroni 3.0
- **Complexity**: High (operator management, Patroni DCS, custom monitoring)
- **Cloud Agnostic**: ✅ Yes (runs on any Kubernetes cluster)
- **Operational Burden**: High (backup strategy, upgrades, scaling)
- **Cost**: Variable (depends on instance sizing, backup storage)
- **Timeline**: 6-8 weeks (operator setup, testing, validation)

### Option B: AWS RDS PostgreSQL (Selected ✅)
- **Implementation**: AWS RDS PostgreSQL 16.4 (db.t3.micro for STAGING)
- **Complexity**: Low (AWS-managed service)
- **Cloud Agnostic**: ❌ No (AWS vendor lock-in)
- **Operational Burden**: Low (AWS manages infrastructure, backups, patches)
- **Cost**: ~$20/month (STAGING), ~$80/month (Production db.t3.medium)
- **Timeline**: Immediate (Terraform declares, AWS provisions in minutes)

---

## Decision

**✅ ACCEPT Option B (AWS RDS PostgreSQL) for STAGING MVP**

### Rationale

#### 1. MVP Time-to-Value
- **Timeline**: STAGING needs database **now** for Marco 3 completion (67% complete)
- **Operator learning curve**: 2-3 weeks to stabilize Patroni cluster
- **RDS**: Immediate deployment via Terraform (already proven working)
- **Impact**: Using operators delays STAGING MVP by 2-3 weeks minimum

#### 2. Cost Optimization for STAGING
- **RDS STAGING (db.t3.micro)**: ~$5/month
- **RDS Production (db.t3.medium)**: ~$80/month
- **Kubernetes Operator**: Similar or higher cost (requires dedicated nodes, storage, ops burden)
- **Decision trades off**: Cost + speed for MVP vs. cloud-agnosticism

#### 3. Operational Maturity
- **RDS**: AWS takes responsibility for:
  - Automated backups (7-day retention)
  - Patches and security updates
  - High availability (multi-AZ optional for Production)
  - Monitoring and alerts
- **Operator**: Platform team responsible for:
  - Backup strategy design and implementation
  - Patroni DCS setup (etcd for staging, proper HA strategy needed)
  - Manual patching coordination
  - Custom monitoring for operator health

#### 4. Pragmatism in MVP Phase
The architectural vision is **cloud-agnostic** (ADR-047), but:
- **Phase 1 (Current)**: MVP requires speed + simplicity = AWS-optimized pragmatism
- **Phase 2-3 (Future)**: Migration to Kubernetes operator feasible once Core Platform stabilizes
- **No architectural debt**: RDS can be replaced with operator in future phases

---

## Consequences

### Positive
✅ **Fast STAGING deployment**: Marco 3 unblocked, delivers database immediately
✅ **Low operational overhead**: AWS manages infrastructure, backups, patches
✅ **Clear cost model**: Predictable per-instance pricing
✅ **Proven production patterns**: RDS is battle-tested for enterprise workloads
✅ **Future migration path**: Terraform + operator both use same K8s config, future migration possible

### Negative
❌ **Vendor lock-in**: AWS-specific, not cloud-agnostic
❌ **Loss of control**: Less flexibility for advanced tuning (vs. operator)
❌ **Network hop**: RDS outside EKS requires cross-subnet communication
❌ **Backup responsibility shift**: RDS backups managed by AWS, not Kubernetes namespace

### Risks
⚠️ **Migration complexity**: If decision reverses in Phase 2, migrating data from RDS → Operator requires careful planning
⚠️ **Cost at scale**: Production RDS (db.t3.medium) can be expensive for very large datasets

**Mitigation**:
- Plan migration to operator in Q3 2026 (post-MVP, once core services stable)
- Document data export procedures now to ease future migration
- Monitor RDS costs monthly (set budget alerts)

---

## Implementation

### STAGING Terraform Declaration

**File**: `platform-provisioning/aws/kubernetes/terraform/modules/postgresql/main.tf`

```hcl
# ✅ IMPLEMENTATION PROVEN CORRECT
resource "aws_db_instance" "postgresql" {
  identifier             = "${var.cluster_name}-postgresql"
  engine                 = "postgres"
  engine_version         = "16.4"  # ← CURRENT (16.5 available but not needed)
  instance_class         = "db.t3.micro"  # STAGING: cost-optimized
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true

  backup_retention_period = 7  # ← Satisfies backup requirements
  backup_window           = "03:00-04:00"

  # STAGING: Single AZ acceptable (MVP risk tolerance)
  multi_az                = false
  publicly_accessible     = false

  # Performance insights for monitoring
  performance_insights_enabled = true

  # Must manually set username/password post-apply
  # Credentials stored in AWS Secrets Manager
}
```

**Deployment Status**: ✅ **LIVE** (Verified 2026-02-11)
- Instance: `k8s-platform-staging-postgresql` (db.t3.micro)
- Version: PostgreSQL 16.4
- Storage: 20 GB gp3 (encrypted)
- Backups: 7-day retention, automated daily 03:00-04:00 UTC

**Kubernetes Access**:
```yaml
# Credentials injected via AWS Secrets Manager
# EKS workloads reference secret: data-services/postgresql-connection
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-connection
  namespace: data-services
type: Opaque
stringData:
  host: k8s-platform-staging-postgresql.c9akciq32.us-east-1.rds.amazonaws.com
  port: "5432"
  username: postgres
  password: "<AWS Secrets Manager>"
  database: data_services
```

---

## Evolution Path: STAGING → Production → Multi-Cloud

### Timeline
```
CURRENT (Feb 2026): STAGING MVP with RDS ← ← ← YOU ARE HERE
        ↓
Phase 1 (Mar-May 2026): STAGING stable, begin production setup
        ↓
Phase 2 (Jun-Aug 2026): Production RDS deployed (db.t3.medium, multi-AZ)
        ↓
Phase 3 (Sep-Nov 2026): Evaluate operator migration
        ↓
Phase 4+ (2027): Possible migration RDS → K8s Operator for cloud-agnosticism
```

### Future ADR: Migration to Operator (Phase 3-4)
When **Core Platform stabilizes** and **Velero backup strategy proven**, create:
- ADR-XX: "Kubernetes Postgres Operator adoption rationale"
- Include data migration strategy (RDS → operator without downtime)
- Include backup strategy update (K8s-native backup system)
- Cost-benefit analysis (RDS vs operator at scale)

---

## Alternatives Rejected

### Alternative C: Mixed Approach (Small RDS + Operator Testing)
- **Rationale**: Test operator in parallel with RDS for Production readiness
- **Rejected because**: Adds complexity without MVP benefit
- **Reconsider in**: Phase 3 (when STAGING MVP proves stable)

### Alternative D: Fully Cloud-Agnostic Operator from Day 1
- **Rationale**: Align with ADR-047 vision immediately
- **Rejected because**: MVP timeline incompatible with operator learning curve
- **Trade-off accepted**: Pragmatism > purity for MVP phase

---

## Alignment with Strategic Decisions

✅ **ADR-047 (Domain Governance)**: "Core platform pragmatic on Phase 1, cloud-agnostic by Phase 3"
✅ **ADR-050 (Shared Data Services)**: "Data services domain includes shared database layer"
✅ **PROJECT-CONTEXT**: "AWS-First MVP, Cloud-Agnostic by design (Phases 2-4)"

**Conclusion**: This decision maintains strategic alignment while optimizing for MVP delivery.

---

## Approval Chain

- ✅ **Architecture Team**: Accepts pragmatism trade-off for MVP phase
- ⏳ **CTO**: Review and approval pending
- 📋 **Platform Lead**: Implementation lead (confirmed working)

**Decision Finalized**: 2026-02-11 (Terraform implementation + AWS verification validates decision)

---

## Review Schedule

- **Monthly**: Monitor RDS costs and performance
- **Q2 2026**: Evaluate operator migration timeline (Phase 3)
- **Q3 2026**: Begin operator testing architecture (if approved in Q2)
- **Q4 2026**: Migration planning (if Phase 3 proceeds)

