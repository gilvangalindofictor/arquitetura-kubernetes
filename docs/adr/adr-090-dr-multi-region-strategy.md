# ADR-090: Disaster Recovery Multi-Region Strategy — GAP-012

**Date**: 2026-03-03
**Status**: ACCEPTED (Phase 1 COMPLETE, Phase 2 PLANNED)
**Decision Maker**: CTO + Platform Architecture
**Related ADRs**: ADR-078 (Velero Backup/DR), ADR-079 (Velero IRSA Migration), ADR-051 (PostgreSQL RDS)
**GAP Reference**: GAP-012 — DR Multi-Region (SLA 99.9% iPaaS)

---

## Context

### Background

The platform runs on a single AWS region (us-east-1) with EKS, RDS PostgreSQL, and supporting services. While ADR-078 established Velero-based backup/restore for Kubernetes workloads, a single-region architecture remains vulnerable to regional AWS outages.

GAP-012 was created to address the 99.9% SLA requirement for iPaaS workloads by establishing multi-region disaster recovery capabilities. The implementation is structured in three phases to balance cost, complexity, and recovery objectives.

### Business Drivers

1. **SLA Compliance**: iPaaS platform requires 99.9% availability (8h 45m max annual downtime)
2. **Regulatory Risk**: Financial services clients require documented DR capabilities
3. **Regional Failure**: AWS us-east-1 has experienced multiple outages affecting multiple AZs simultaneously
4. **Data Protection**: PostgreSQL database contains critical application data (GitLab, Keycloak, Harbor, SonarQube)

### Current State (Pre-GAP-012)

| Component | Backup | DR Capability | Risk |
|-----------|--------|---------------|------|
| EKS Workloads | Velero daily/hourly (ADR-078) | Single region restore only | **HIGH** — no cross-region |
| PostgreSQL RDS | Automated backups (7d) | Same-region restore only | **HIGH** — regional failure |
| S3 Data | Bucket versioning | Same-region | **MEDIUM** — S3 11-9s durability |
| Vault Secrets | S3 snapshots | Same-region | **MEDIUM** |

---

## Decision

**ACCEPT: Implement GAP-012 Disaster Recovery Multi-Region in three phases.**

### Phase 1: S3 Cross-Region Replication + Velero DR (COMPLETE)

**Status**: DEPLOYED (2026-02-25)
**Module**: `modules/velero-dr/`

**Delivered**:
- S3 bucket in us-east-1 (primary) with Cross-Region Replication to us-west-2 (replica)
- Replication Time Control (RTC) with 15-minute SLA
- Velero IRSA role with cross-region S3 access (primary R/W + replica R/O)
- CloudWatch alarms for replication failures and pending bytes
- SNS alerting for DR events

**RTO/RPO Achieved**:
- RPO: 15 minutes (RTC SLA for S3 objects)
- RTO: 1 hour (Velero restore from replica bucket)

**Cost**: ~$5-10/month (S3 storage + CRR transfer)

### Phase 2: DR VPC + RDS Read Replica (PLANNED)

**Status**: MODULE READY, PENDING APPROVAL
**Module**: `modules/dr-multi-region/`

**Scope**:
- VPC in us-west-2 (10.1.0.0/16) mirroring primary structure
  - 2 public subnets (10.1.1.0/24, 10.1.2.0/24)
  - 3 private subnets (10.1.10.0/24, 10.1.11.0/24, 10.1.12.0/24)
  - Internet Gateway (always on)
  - NAT Gateway (optional, disabled by default to save ~$32/month)
- VPC Peering between us-east-1 and us-west-2
- RDS PostgreSQL cross-region read replica
  - Async replication (typically < 60s lag)
  - db.t4g.medium instance class (~$47/month)
  - gp3 storage, encrypted, Performance Insights enabled
  - Promotable to standalone primary in ~10 minutes
- CloudWatch alarms (replication lag, storage, availability)
- SNS alerting with email subscription

**RTO/RPO Target**:
- RPO: ~0 (async replication, < 60s lag)
- RTO: 10 minutes (RDS replica promotion) to 4 hours (full workload failover)

**Estimated Cost**:
| Resource | Monthly Cost |
|----------|-------------|
| RDS replica (db.t4g.medium) | ~$47 |
| VPC (no NAT) | ~$0 |
| NAT Gateway (if enabled) | ~$32 |
| VPC Peering data transfer | ~$5-10 |
| CloudWatch alarms | ~$1 |
| **Total (without NAT)** | **~$53-58** |
| **Total (with NAT)** | **~$85-90** |

### Phase 3: EKS DR Cluster (FUTURE)

**Status**: NOT STARTED
**Prerequisites**: Phase 2 complete + production workload analysis

**Scope** (planned):
- EKS cluster in us-west-2 (DR VPC private subnets)
- ArgoCD ApplicationSet for cross-region GitOps sync
- Route 53 failover routing (active-passive)
- Velero restore target in DR cluster
- Promote RDS replica + switch EKS workloads

**Estimated Timeline**: Q3-Q4 2026

---

## Architecture

### Phase 1 + 2 Combined Architecture

```
  us-east-1 (PRIMARY)                        us-west-2 (DR)
 +---------------------------+              +---------------------------+
 | VPC 10.0.0.0/16           |              | VPC 10.1.0.0/16           |
 |                           |   VPC Peer   |                           |
 | +-------+    +---------+  |<------------>| +-------+                 |
 | | EKS   |    | RDS     |  |              | |       |    +---------+  |
 | | Cluster|   | Primary |  |  async repl  | |       |    | RDS     |  |
 | |        |   | PG 16   |--+------------->| |       |    | Replica |  |
 | +-------+    +---------+  |              | |       |    | PG 16   |  |
 |                           |              | +-------+    +---------+  |
 | +----------+              |              |                           |
 | | S3 Velero|  S3 CRR     |              | +----------+              |
 | | Primary  |------------>-+------------->| | S3 Velero|              |
 | +----------+              |              | | Replica  |              |
 |                           |              | +----------+              |
 +---------------------------+              +---------------------------+
```

### Failover Procedure (Phase 2)

1. **Detect**: CloudWatch alarm fires (replication lag or primary unavailable)
2. **Assess**: Confirm regional failure vs transient issue (5 min)
3. **Promote RDS**: `aws rds promote-read-replica --db-instance-identifier <replica-id>` (~10 min)
4. **Update DNS**: Point application connection strings to new primary endpoint
5. **Validate**: Run health checks against promoted instance
6. **Notify**: SNS alert to operations team

### Failover Procedure (Phase 3 — Future)

1. Steps 1-3 from Phase 2
2. **Restore Workloads**: `velero restore create --from-backup <latest> --namespace-mappings ...`
3. **Route Traffic**: Update Route 53 to point to DR ALB/NLB
4. **Scale**: Adjust DR EKS node groups for production load

---

## CIDR Allocation Plan

| Region | VPC CIDR | Public Subnets | Private Subnets |
|--------|----------|----------------|-----------------|
| us-east-1 (primary) | 10.0.0.0/16 | 10.0.1.0/24 (a), 10.0.2.0/24 (b) | 10.0.10.0/24 (a), 10.0.11.0/24 (b), 10.0.12.0/24 (c) |
| us-west-2 (DR) | 10.1.0.0/16 | 10.1.1.0/24 (a), 10.1.2.0/24 (b) | 10.1.10.0/24 (a), 10.1.11.0/24 (b), 10.1.12.0/24 (c) |

Non-overlapping CIDRs are mandatory for VPC peering.

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Replication lag exceeds SLA | Low | High | CloudWatch alarm at 60s, auto-SNS alert |
| VPC peering connectivity issues | Low | Medium | Route table validation, security group testing |
| DR VPC cost overrun | Low | Low | NAT disabled by default, db.t4g.medium sizing |
| Replica promotion failure | Low | Critical | Documented runbook, quarterly DR drill |
| CIDR conflict with future VPCs | Low | Medium | Documented allocation plan, /16 blocks reserved |
| Cross-region data transfer costs | Medium | Low | Monitor via Cost Explorer, S3 lifecycle policies |

---

## Validation Criteria

### Phase 2 Deployment Checklist

- [ ] DR VPC created in us-west-2 (10.1.0.0/16)
- [ ] 2 public + 3 private subnets created with correct CIDRs
- [ ] Internet Gateway attached and public route table configured
- [ ] VPC Peering active (us-east-1 <-> us-west-2)
- [ ] Route tables updated for cross-VPC traffic
- [ ] RDS read replica created and replicating
- [ ] Replication lag < 60s sustained
- [ ] CloudWatch alarms configured and tested
- [ ] SNS notifications received on test alarm
- [ ] Security groups restrict access to private subnets only

### DR Drill (Quarterly)

- [ ] Promote replica to standalone (test environment)
- [ ] Verify application connectivity to promoted instance
- [ ] Measure actual RTO against 10-minute target
- [ ] Document findings and update runbook

---

## Cost Summary

| Phase | Monthly Cost | Annual Cost | Status |
|-------|-------------|-------------|--------|
| Phase 1 (S3 CRR + Velero) | ~$7.50 | ~R$ 540 | DEPLOYED |
| Phase 2 (VPC + RDS Replica) | ~$55 | ~R$ 3,960 | PLANNED |
| Phase 3 (EKS DR Cluster) | ~$200-400 | ~R$ 14,400-28,800 | FUTURE |

**Phase 2 ROI**: Prevents 4-8 hour outage during regional failure. Single outage cost estimated at R$ 15,000-50,000 (developer downtime + SLA penalty + recovery effort). Payback in < 1 incident.

---

## Related Documentation

- **Phase 1 Module**: `platform-provisioning/aws/kubernetes/terraform/modules/velero-dr/`
- **Phase 2 Module**: `platform-provisioning/aws/kubernetes/terraform/modules/dr-multi-region/`
- **RDS Replica Pattern**: `platform-provisioning/aws/kubernetes/terraform/modules/rds-replica/`
- **Velero Backup ADR**: [ADR-078](./adr-078-velero-backup-dr-implementation.md)
- **PostgreSQL RDS ADR**: [ADR-051](./adr-051-postgresql-rds-vs-operator.md)
- **DR Runbook**: [docs/runbooks/disaster-recovery.md](../runbooks/disaster-recovery.md)

---

## Approval Status

- PENDING: **CTO** — Phase 2 us-west-2 VPC and RDS replica cost approval
- PENDING: **Platform Lead** — Technical review of dr-multi-region module
- ACCEPTED: **Architecture Team** — Phase 1 delivered, Phase 2 design approved

---

**Phase 1 Deployed**: 2026-02-25
**Phase 2 Module Ready**: 2026-03-03
**Phase 2 Deployment Target**: Pending us-west-2 VPC approval
**Phase 3 Planning**: Q3-Q4 2026
