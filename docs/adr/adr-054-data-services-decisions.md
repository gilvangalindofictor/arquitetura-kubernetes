# Architecture Decision Records - Data Services Domain

**Última Atualização**: 2026-02-11
**Escopo**: Decisões arquiteturais específicas do domínio data-services
**Status**: Três novas decisões documentadas (ADR-051, ADR-052, ADR-053)

---

## 📋 ADRs Relacionados a Data Services

### Core Decisions (Phase 1 - STAGING MVP)

#### ✅ [ADR-051: PostgreSQL RDS vs. Operator](./adr-051-postgresql-rds-vs-operator.md)
**Status**: ✅ ACCEPTED
**Date**: 2026-02-11
**Summary**: Use AWS RDS PostgreSQL 16.4 for STAGING MVP instead of Kubernetes operator
- **Why**: Speed + cost optimization for MVP phase
- **Cost**: ~$5/month (STAGING db.t3.micro), ~$80/month (Production db.t3.medium planned)
- **Trade-off**: Vendor lock-in accepted for MVP, migration path reserved for Phase 2
- **Implementation**: Terraform `modules/postgresql/main.tf` (7-day RDS backups configured)
- **Follow-up Decision**: Migration to Kubernetes operator planned for Phase 3 (Sep-Nov 2026)

**Key Quote**: *"Pragmatism in Phase 1, cloud-agnostic by Phase 3"*

---

#### 🟡 [ADR-052: Velero Backup Strategy](./adr-052-velero-implementation-strategy.md)
**Status**: 🟡 PENDING CTO DECISION
**Date**: 2026-02-11
**Summary**: Defer Velero implementation to Production phase, accept backup gaps in STAGING MVP
- **Why**: MVP data is test data (recoverable), implementation bandwidth better spent on core features
- **Gap**: Zero Kubernetes backup (STAGING data only), RDS backups for PostgreSQL only
- **Recovery plan**: < 2 hours downtime (re-run terraform, RDS restore, operator pod restart)
- **Implementation**: Zero changes needed (S3 bucket "platform-backups" prepared but empty)
- **Follow-up Decision**: CTO decision required before Production launch (deadline: April 2026)

**Key Quote**: *"STAGING MVP can accept gaps; Production requires comprehensive strategy"*

**Decision Matrix for CTO**:
| Option                        | Scope                | Effort        | Cost              | Production Timeline |
| ----------------------------- | -------------------- | ------------- | ----------------- | ------------------- |
| A) Lightweight                | RDS only             | 1 week        | <$5/month         | June 2026           |
| **B) Standard (Recommended)** | **Full Velero**      | **2-3 weeks** | **$50-100/month** | **June 2026**       |
| C) Enterprise                 | Velero + replication | 4 weeks       | $200+/month       | July 2026           |

---

#### ✅ [ADR-053: Redis Operator - SpotaHome vs OT-Container-Kit](./adr-053-redis-operator-spotahome-vs-otcontainerkit.md)
**Status**: ✅ ACCEPTED
**Date**: 2026-02-11
**Summary**: Use SpotaHome Redis Operator 3.3.0 instead of OT-Container-Kit for simplicity
- **Why**: Lower complexity, faster MVP delivery, cloud-agnostic equally
- **Trade-off**: Manual Sentinel if HA monitoring needed (vs OT-Kit built-in)
- **Implementation**: Terraform `modules/redis/main.tf` (RedisFailover CRD, 1 replica STAGING)
- **Migration path**: Can swap to OT-Container-Kit in Q3 2026 if Sentinel needed
- **Cost**: Same (both operators minimal cost)

**Key Quote**: *"80% of features, 20% of complexity = MVP wins"*

---

#### ⏳ [ADR-050: Shared Data Services - Prod vs Staging](./adr-050-shared-data-services-prod-staging.md)
**Status**: ✅ ACCEPTED
**Date**: 2026-02-09
**Summary**: Single data-services domain shared between Production and STAGING environments
- **Architecture**: Separate RDS instances, separate operator namespaces (no data sharing)
- **STAGING**: db.t3.micro, 1 replica (Redis/RabbitMQ)
- **Production**: db.t3.medium, 3 replicas (future)
- **Related**: ADR-051 (RDS decision), ADR-052 (backup strategy)

---

### Related Infrastructure Decisions

#### ✅ [ADR-047: Estrutura Corporativa / Governance](./adr-047-estrutura-corporativa-dominios.md)
**Relevance to Data Services**: Domain isolation + cloud-agnostic principles
**Key Decision Affecting Data Services**:
- *"Phase 1: AWS pragmatism (RDS, Secrets Manager)"*
- *"Phase 2-3: Migrate to cloud-agnostic operators (Patroni, Velero)"*

---

#### ✅ [ADR-049: Governança RBAC](./adr-049-governanca-rbac-dominios-corporativos.md)
**Relevance to Data Services**: Access control for database + Redis + RabbitMQ
**Key Patterns**:
- Service account per workload (separate write/read permissions)
- Secrets management via AWS Secrets Manager (ADR-003)

---

#### ✅ [ADR-005: Logging Strategy](./adr-005-logging-strategy.md)
**Relevance to Data Services**: CloudWatch logs for RDS, operator logs for Redis/RabbitMQ
**Integration Points**:
- PostgreSQL slow query logs → CloudWatch
- Operator events → Kubernetes logs → observability pipeline (Loki)

---

#### ✅ [ADR-022: FinOps Automation](./adr-022-finops-automation-strategy.md)
**Relevance to Data Services**: Cost tracking for RDS + S3 storage
**Key Metrics**:
- RDS instance hours × cost/hour
- S3 storage for backups (platform-backups bucket)
- Node group sizing optimization

---

## 📊 Decision Timeline

```
2026-02-11: ✅ ADR-051 (RDS), 🟡 ADR-052 (Velero), ✅ ADR-053 (Redis)
            └─ STAGING MVP architectural decisions finalized

2026-04-xx: 🟡 ADR-052 Decision Point
            └─ CTO decides Velero strategy for Production

2026-06-xx: 📋 ADR-XXX: Velero Production Implementation
            └─ Create detailed Velero implementation plan

2026-09-xx: 📋 ADR-XXX: RDS → Postgres Operator Migration
            └─ Plan migration for Phase 2-3

2026-12-xx: 📋 ADR-XXX: Multi-environment Strategy
            └─ Expand to support Production + additional staging/dev
```

---

## 🎯 Critical Implementation Status

| ADR | Component         | Terraform Declaration              | Current Status  | Risk Level |
| --- | ----------------- | ---------------------------------- | --------------- | ---------- |
| 051 | PostgreSQL RDS    | ✅ `modules/postgresql/main.tf` L12 | ✅ LIVE (16.4)   | ✅ Low      |
| 053 | Redis Operator    | ✅ `modules/redis/main.tf` L18      | ✅ LIVE (3.3.0)  | ✅ Low      |
| -   | RabbitMQ Operator | ✅ `modules/rabbitmq/main.tf` L5-25 | ✅ LIVE (2.19.0) | ✅ Low      |
| 052 | Velero            | ❌ NOT DECLARED                     | 🚫 NOT DEPLOYED  | 🟡 Medium   |

**Risk Assessment**: STAGING MVP 80% complete, only Velero decision pending (acceptable for MVP)

---

## 📚 Related Documentation

### STAGING Environment Specifics
- [TERRAFORM-SOURCE-OF-TRUTH.md](../domains/data-services/docs/TERRAFORM-SOURCE-OF-TRUTH.md) - Terraform ↔ STAGING reconciliation
- [STAGING-INVENTORY.md](../domains/data-services/docs/STAGING-INVENTORY.md) - Component details
- [VERSION-CONTROL.md](../domains/data-services/docs/VERSION-CONTROL.md) - Version tracking + upgrade planning
- [STAGING-ANALYSIS-FINDINGS.md](../domains/data-services/docs/STAGING-ANALYSIS-FINDINGS.md) - Audit findings

### Architecture Overview
- [PROJECT-CONTEXT.md](../../PROJECT-CONTEXT.md) - Project-level context
- [ARCHITECTURE-DIAGRAMS.md](../../ARCHITECTURE-DIAGRAMS.md) - Visual architecture representations
- [SAD (Systems Architecture Document)](../SAD/docs/sad.md) - Overall system design

---

## 🔍 How to Navigate This Package

### For Platform Engineers
1. Start: [ADR-051](./adr-051-postgresql-rds-vs-operator.md) (RDS pragmatism)
2. Then: [ADR-053](./adr-053-redis-operator-spotahome-vs-otcontainerkit.md) (Redis simplicity)
3. Then: [VERSION-CONTROL.md](../domains/data-services/docs/VERSION-CONTROL.md) (upgrades + paths)

### For CTO/Decision Makers
1. Start: [ADR-052](./adr-052-velero-implementation-strategy.md) (pending decision)
2. Then: [TERRAFORM-SOURCE-OF-TRUTH.md](../domains/data-services/docs/TERRAFORM-SOURCE-OF-TRUTH.md) (validation proof)
3. Then: [STAGING-AUDIT-SUMMARY.md](../domains/data-services/docs/STAGING-AUDIT-SUMMARY.md) (confidence level)

### For New Team Members
1. Start: [PROJECT-CONTEXT.md](../../PROJECT-CONTEXT.md) (what are we building?)
2. Then: [STAGING-INVENTORY.md](../domains/data-services/docs/STAGING-INVENTORY.md) (what do we have?)
3. Then: [ADR-051, 052, 053](./adr-051-postgresql-rds-vs-operator.md) (why did we choose this?)

---

## ✅ Checklist: STAGING Data Services MVP

- ✅ PostgreSQL RDS 16.4 (Terraform + AWS)
- ✅ Redis SpotaHome 3.3.0 (Terraform + K8s)
- ✅ RabbitMQ Official 2.19.0 (Terraform + K8s)
- ✅ RDS Backups 7-day automated
- ✅ Network routing (K8s → RDS)
- ✅ Secrets management (AWS Secrets Manager → K8s)
- 🟡 Velero backup (Pending CTO decision for Production)
- 🚧 Monitoring integration (Observability domain)
- 🚧 CD/CI pipeline (CI/CD domain)

---

## 🚀 Phase Evolution (Planned)

### Phase 1 ✅ (Current: Through Mar 2026)
- STAGING MVP complete
- All operators live + stable
- Pragmatic AWS integrations proven

### Phase 2 (Apr-Jun 2026)
- Production environment setup
- Backup strategy decision + Velero implementation
- Multi-environment terraform structure

### Phase 3 (Jul-Sep 2026)
- Migration planning: RDS → PostgreSQL Operator
- Observability integration
- FinOps tracking + optimization

### Phase 4+ (Oct 2026+)
- Cloud-agnostic core fully portals
- Multi-cloud deployment capability
- Full disaster recovery automation

---

**Prepared by**: Platform Architecture AI Audit
**Reviewed by**: Platform Team
**Last Updated**: 2026-02-11

