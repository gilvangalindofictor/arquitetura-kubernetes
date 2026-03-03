# ADR-093: RDS PostgreSQL 14 to 16 In-Place Upgrade

**Status:** Approved (awaiting execution)
**Date:** 2026-03-03
**Decision Makers:** Platform SRE Team
**Context:** INFRA-002 - GitLab 18.x requires PostgreSQL 16, current version is 14.8.0
**Related:** ADR-051 (PostgreSQL RDS vs Operator), ADR-050 (Shared Data Services), ADR-060 (PostgreSQL Governance)

---

## Context

### Problem Statement

**Requirement:** GitLab 18.x (target upgrade from current 17.11.7) requires PostgreSQL 16 as a minimum database version. The current RDS instance runs PostgreSQL 14.8.0.

**Affected Services (shared RDS instance - ADR-050):**
- GitLab (primary consumer, `gitlab` database)
- Harbor (`harbor` database)
- Keycloak (`keycloak` database)
- ArgoCD (`argocd` database)
- SonarQube (`sonarqube` database)

**Current State:**
- RDS Instance: `k8s-platform-prod-postgresql`
- Engine: PostgreSQL 14.8.0
- Instance Class: db.t3.micro (staging)
- Storage: 20 GB gp3, single-AZ
- Backup Retention: 7 days
- Enhanced Monitoring: enabled (60s interval)
- Performance Insights: enabled (7 days retention)

### Why PostgreSQL 16

1. **GitLab 18.x hard requirement** - GitLab 18.0+ drops support for PostgreSQL 14
2. **PostgreSQL 14 EOL** - PostgreSQL 14 reaches end-of-life November 2026
3. **Performance improvements** - PostgreSQL 16 includes query planner improvements, SIMD acceleration for text processing, and logical replication enhancements
4. **Security** - PostgreSQL 16 includes enhanced password authentication (SCRAM-SHA-256 by default) and improved privilege management

## Decision

Perform an **in-place major version upgrade** from PostgreSQL 14.8.0 to 16.4 using Terraform with the following approach:

### Upgrade Strategy

1. **Pre-upgrade manual snapshot** - Create a manual RDS snapshot before `terraform apply` as a rollback safety net
2. **Terraform-managed upgrade** - Use `allow_major_version_upgrade = true` and `apply_immediately = true` in the postgresql module
3. **Staging-first execution** - Validate upgrade in staging before any production consideration
4. **Post-upgrade validation** - Verify all 5 database consumers can connect and operate normally
5. **Post-upgrade cleanup** - Reset `allow_major_version_upgrade` and `apply_immediately` to `false` after successful upgrade

### Terraform Changes

**Module (`modules/postgresql/variables.tf`):**
- Added `allow_major_version_upgrade` (bool, default: false)
- Added `apply_immediately` (bool, default: false)

**Module (`modules/postgresql/main.tf`):**
- Added `allow_major_version_upgrade = var.allow_major_version_upgrade` to `aws_db_instance.postgresql`
- Added `apply_immediately = var.apply_immediately` to `aws_db_instance.postgresql`
- `engine_version` already set to `"16.4"` (target version)

**Environment (`environments/staging/main.tf`):**
- Added `allow_major_version_upgrade = true` to `postgresql_staging` module call
- Added `apply_immediately = true` to `postgresql_staging` module call

## Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Downtime during upgrade | 10-20 minutes (all 5 services unavailable) | High (expected) | Schedule during maintenance window (Sun 04:00-05:00 UTC), notify stakeholders |
| Data loss during upgrade | Critical | Very Low | Pre-upgrade manual snapshot + automated 7-day retention backups |
| Application incompatibility with PG 16 | Service-specific failures | Low | PostgreSQL 16 is backward compatible; GitLab 17.11.7 already supports PG 16 |
| Extension incompatibility | Query failures | Low | Verify installed extensions compatibility before upgrade; AWS validates during pre-check |
| Rollback needed | Extended downtime (30-60 min restore from snapshot) | Low | Manual snapshot enables point-in-time restore to PG 14.8.0 |
| Parameter group changes | Performance regression | Low | AWS creates a new default parameter group for PG 16; review and tune post-upgrade |

### Downtime Analysis

- **Single-AZ staging instance:** 10-20 minutes expected downtime
- **AWS upgrade process:** Stop instance -> Upgrade engine -> Start instance -> Apply parameter group
- **No Multi-AZ failover available** (staging is single-AZ by design, DT-004)

## Execution Plan (INFRA-002)

### Pre-Upgrade Checklist

```bash
# 1. Verify current engine version
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].{Engine:Engine,Version:EngineVersion,Status:DBInstanceStatus}'

# 2. Create manual pre-upgrade snapshot
aws rds create-db-snapshot \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --db-snapshot-identifier k8s-platform-prod-postgresql-pre-pg16-upgrade-$(date +%Y%m%d)

# 3. Wait for snapshot completion
aws rds wait db-snapshot-available \
  --db-snapshot-identifier k8s-platform-prod-postgresql-pre-pg16-upgrade-$(date +%Y%m%d)

# 4. Verify snapshot is available
aws rds describe-db-snapshots \
  --db-snapshot-identifier k8s-platform-prod-postgresql-pre-pg16-upgrade-$(date +%Y%m%d) \
  --query 'DBSnapshots[0].{Status:Status,Engine:Engine,EngineVersion:EngineVersion}'
```

### Terraform Apply

```bash
# 5. Plan the upgrade (review changes carefully)
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform plan -target=module.postgresql_staging

# 6. Apply the upgrade
terraform apply -target=module.postgresql_staging
```

### Post-Upgrade Validation

```bash
# 7. Verify engine version upgraded
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].{Engine:Engine,Version:EngineVersion,Status:DBInstanceStatus}'

# 8. Test connectivity from each consumer
kubectl exec -it deploy/gitlab-webservice -n gitlab-staging -- \
  psql "host=k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com port=5432 dbname=gitlab user=gitlab_user" \
  -c "SELECT version();"

# 9. Verify all pods are running
kubectl get pods -A | grep -E '(gitlab|harbor|keycloak|argocd|sonarqube)' | grep -v Running

# 10. Check PostgreSQL logs for upgrade issues
aws rds describe-events \
  --source-identifier k8s-platform-prod-postgresql \
  --source-type db-instance \
  --duration 120
```

### Post-Upgrade Cleanup

After successful validation, reset the upgrade flags in `environments/staging/main.tf`:

```hcl
# INFRA-002: Upgrade completed successfully — reset flags to prevent accidental upgrades
allow_major_version_upgrade = false
apply_immediately           = false
```

## Rollback Procedure

If the upgrade fails or causes issues:

```bash
# 1. Restore from pre-upgrade snapshot (creates a NEW instance)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier k8s-platform-prod-postgresql-restored \
  --db-snapshot-identifier k8s-platform-prod-postgresql-pre-pg16-upgrade-YYYYMMDD \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name k8s-platform-prod-postgresql

# 2. Update DNS/endpoints to point to restored instance
# 3. Delete the failed upgraded instance
# 4. Rename restored instance to original identifier
```

## Consequences

### Positive
- Unblocks GitLab 18.x upgrade path (INFRA-001 dependency resolved)
- PostgreSQL 16 performance improvements benefit all 5 consumers
- Aligned with PostgreSQL 14 EOL timeline (November 2026)
- Terraform-managed upgrade ensures reproducibility and auditability

### Negative
- 10-20 minutes planned downtime for all database-dependent services
- Requires manual pre-upgrade snapshot (not automated by Terraform)
- Post-upgrade parameter group review needed

### Neutral
- No schema changes required (backward compatible)
- No application code changes required for any of the 5 consumers
- PostgreSQL extensions maintained automatically by AWS during upgrade

## References

- [AWS RDS PostgreSQL Major Version Upgrade](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_UpgradeDBInstance.PostgreSQL.html)
- [PostgreSQL 16 Release Notes](https://www.postgresql.org/docs/16/release-16.html)
- [GitLab 18.x Database Requirements](https://docs.gitlab.com/ee/install/requirements.html#postgresql-requirements)
- INFRA-001: GitLab 17.x to 18.x upgrade (blocked on INFRA-002)
- INFRA-002: PostgreSQL 14 to 16 upgrade (this ADR)
