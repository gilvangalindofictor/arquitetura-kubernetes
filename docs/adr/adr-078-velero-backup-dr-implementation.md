# ADR-078: Velero Backup/DR Implementation - GAP-003 / GAP-012

**Date**: 2026-02-25
**Updated**: 2026-03-04
**Status**: ✅ IMPLEMENTADO — Phase 1 DEPLOYADO (2026-02-26) | Phase 2 PLANEJADO (aguardando deploy)
**Decision Maker**: CTO + Platform Architecture
**Related ADRs**: ADR-052 (Velero Deferral - SUPERSEDED), ADR-051 (PostgreSQL RDS), ADR-090 (DR Multi-Region Strategy)
**Supersedes**: ADR-052 (Strategy Changed: Implement Now vs Defer to Production)

---

## Implementation Status (2026-03-04)

### Phase 1 — S3 CRR (DEPLOYADO 2026-02-26)

| Item | Status | Detalhe |
|------|--------|---------|
| S3 Primary Bucket (us-east-1) | ✅ ATIVO | `velero-backups-staging-891377105802-us-east-1` |
| S3 Replica Bucket (us-west-2) | ✅ ATIVO | `velero-backups-staging-891377105802-us-west-2` |
| S3 CRR + RTC 15min SLA | ✅ ATIVO | `velero-backup-replication` rule, RTC enabled |
| IAM IRSA Role | ✅ ATIVO | `k8s-platform-prod-velero-dr-role` (primary + replica) |
| CloudWatch Alarms | ✅ ATIVOS | `velero-s3-crr-replication-failed-staging`, `velero-s3-crr-pending-bytes-high-staging` |
| Terraform Module | ✅ CRIADO | `modules/velero-dr/` (509 lines) |
| RDS Replica Module | ✅ CRIADO | `modules/rds-replica/` (284 lines, count=0 aguardando Phase 2) |

### Phase 2 — VPC DR + BSL + Schedules

| Item | Status | Artefato |
|------|--------|----------|
| VPC DR us-west-2 (TF module) | 📋 PRONTO PARA DEPLOY | `modules/vpc-dr/` (4 arquivos) |
| BackupStorageLocation DR | 📋 PRONTO PARA DEPLOY | `domains/backup-dr/infra/velero/backup-storage-location-dr.yaml` |
| **Schedule daily-full-backup** | **✅ ATIVO** | `kubectl get schedule -n velero daily-full-backup` → Scheduled |
| **Schedule hourly-incremental** | **✅ ATIVO** | `kubectl get schedule -n velero hourly-incremental` → Scheduled |
| **Velero Helm** | **✅ DEPLOYED** | Rev 7+ `deployed` — root causes IRSA ARN + role name + nodeSelector fixados |
| Grafana Dashboard DR | 📋 PRONTO PARA DEPLOY | `domains/observability/infra/grafana/dr-replication-dashboard-configmap.yaml` |
| RDS Replica ativação | ⏸️ BLOQUEADO | Aguarda VPC DR deploy + aprovação liderança |

> ✅ **V-009 RESOLVIDO (2026-03-04)**: Schedules daily+hourly ativos. Helm deployed. Root causes:
> IRSA ARN malformed (`:role:` → `/role/`), wrong role name (`velero-role` → `velero-dr-role`),
> nodeSelector saturado (`platform` → `applications`), CPU request reduzido (100m → 50m).

### Deploy Sequence (Phase 2)

```bash
# Step 1: Deploy VPC DR (Terraform)
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
# Adicionar module "vpc_dr_staging" em main.tf (ver seção abaixo)
terraform plan -target=module.vpc_dr_staging
terraform apply -target=module.vpc_dr_staging

# Step 2: Velero Helm upgrade (adiciona BSL us-west-2)
helm upgrade velero vmware-tanzu/velero \
  --namespace velero \
  --reuse-values \
  --values domains/backup-dr/infra/velero/velero-values-dr-update.yaml

# Step 3: Apply BackupStorageLocation + Schedules
kubectl apply -f domains/backup-dr/infra/velero/backup-storage-location-dr.yaml
kubectl apply -f domains/backup-dr/infra/velero/schedule-daily-full.yaml
kubectl apply -f domains/backup-dr/infra/velero/schedule-hourly-incremental.yaml

# Step 4: Apply Grafana Dashboard
kubectl apply -f domains/observability/infra/grafana/dr-replication-dashboard-configmap.yaml

# Step 5 (gate de liderança): Ativar RDS Replica
# terraform apply -target=module.rds_replica_staging (count = 1)

# Verify
velero backup-location get
velero schedule get
```

### Terraform Module Addition (environments/staging/main.tf)

```hcl
# GAP-012 Phase 2: VPC DR us-west-2
module "vpc_dr_staging" {
  source = "../../modules/vpc-dr"
  providers = {
    aws.dr = aws.us-west-2
  }

  environment          = local.environment
  name_prefix          = local.cluster_name
  dr_region            = "us-west-2"
  vpc_cidr             = "10.1.0.0/16"
  rds_subnet_cidr_az_a = "10.1.128.0/20"
  rds_subnet_cidr_az_b = "10.1.144.0/20"
  db_subnet_group_name = "k8s-platform-dr-db-subnet-group"
  tags                 = local.common_tags
}
```

---

---

## Context

### Background

On 2026-02-11, [ADR-052](./adr-052-velero-implementation-strategy.md) deferred Velero implementation to Production phase based on:

- **Rationale**: STAGING MVP data is disposable, limited implementation bandwidth
- **Decision**: Accept backup gaps in STAGING, implement for Production (Q2-Q3 2026)
- **Recovery Plan**: Manual reconstruction < 2 hours (Terraform + RDS restore)

### Strategy Shift

**As of 2026-02-25**, the decision has been **reversed** for the following reasons:

1. **Operational Maturity**: STAGING environment now hosts critical integrations:
   - GitLab CI/CD pipelines with production templates
   - Keycloak SSO with 6 integrated services
   - Vault secrets management (7 KV paths)
   - ArgoCD GitOps with ApplicationSets automation
   - Harbor container registry with production images

2. **Data Criticality Increased**:
   - **GitLab**: Repository content, CI/CD configurations, runner tokens
   - **Vault**: 7 active ExternalSecrets, 10 synced K8s secrets
   - **Keycloak**: Realm configuration, OIDC clients, user/group mappings
   - **Recovery Time Impact**: Manual rebuild now estimated at 6-8 hours (vs 2 hours in Feb 11)

3. **Production Readiness**: Implementing Velero in STAGING now provides:
   - Proven disaster recovery procedures before Production launch
   - Validated backup/restore workflows
   - Identified edge cases and operational learnings
   - Tested RTO/RPO metrics

4. **Cost vs Value**:
   - **Cost**: $5-10/month S3 storage (minimal)
   - **Value**: Prevents 6-8 hour reconstruction effort, validates Production strategy
   - **ROI**: Positive after first incident avoided

---

## Problem Statement

### Current Backup Coverage (Pre-ADR-078)

| Component  | Backup Type        | Status              | Risk                               |
| ---------- | ------------------ | ------------------- | ---------------------------------- |
| PostgreSQL | RDS automated      | ✅ PROTECTED (7d)    | Low (AWS-managed)                  |
| Redis      | Operator RDB       | 🔄 PARTIAL (in-pod)  | Medium (loss on pod/PVC deletion)  |
| RabbitMQ   | None (HA only)     | ❌ UNPROTECTED       | High (quorum loss = data loss)     |
| Kubernetes | Git IaC only       | ❌ UNPROTECTED       | **CRITICAL** (config drift, state) |
| Vault      | S3 snapshots       | ✅ PROTECTED         | Low (auto-unseal KMS)              |
| GitLab     | RDS + Redis + Repo | 🔄 PARTIAL           | **CRITICAL** (repository loss)     |

### Gap Impact Assessment

**Scenario: Namespace Deletion (Accidental)**

- **Without Velero**:
  - GitLab namespace deleted → Lose repository content, CI/CD configs, runner tokens
  - Recovery: Re-deploy Helm chart + restore RDS → **6-8 hours** (repo content lost)
  - Business Impact: CI/CD pipelines down, developers blocked

- **With Velero**:
  - GitLab namespace deleted → Restore from daily backup
  - Recovery: `velero restore create` → **15 minutes**
  - Business Impact: Minimal, last 24h changes only

---

## Decision

**✅ ACCEPT: Implement Velero Backup/DR in STAGING (GAP-003)**

### Implementation Scope

**Infrastructure (Terraform)**:
- S3 bucket with lifecycle policies (7d daily, 30d weekly, 365d monthly)
- IAM policy for Velero (S3 + EC2 snapshots)
- IRSA role for velero-server ServiceAccount
- Server-side encryption (AES256)
- Public access block

**Kubernetes Deployment (Helm)**:
- Velero v1.15.1 via vmware-tanzu/velero chart v8.1.0
- AWS plugin v1.11.0 for S3 + EBS integration
- Node agent (restic) for file-level backups
- Prometheus ServiceMonitor for metrics

**Backup Schedules**:

| Schedule              | Frequency      | Retention | Scope                     | RPO    |
| --------------------- | -------------- | --------- | ------------------------- | ------ |
| `daily-full-backup`   | Daily 2:00 UTC | 7 days    | All namespaces (excl sys) | 24h    |
| `weekly-pvc-backup`   | Sun 3:00 UTC   | 30 days   | PVCs + PVs only           | 7 days |
| `hourly-critical`     | Hourly         | 24h       | Critical namespaces       | 1h     |
| `monthly-archive`     | 1st of month   | 365 days  | Full cluster (compliance) | 30d    |

**Critical Namespaces (Hourly Backup)**:
- `staging-security-vault`
- `keycloak`
- `argocd`
- `gitlab-staging`

**Disaster Recovery**:
- **RTO Target**: 1 hour (full cluster restore)
- **RPO Target**: 24 hours (daily backups) / 1 hour (critical namespaces)
- **Runbook**: [docs/runbooks/disaster-recovery.md](../runbooks/disaster-recovery.md)
- **Automated Testing**: Weekly restore test via CronJob (Sun 5:00 UTC)

---

## Architecture

### Backup Flow

```
┌─────────────────┐      ┌──────────────┐      ┌─────────────────┐
│ Velero Schedule │─────>│ Velero       │─────>│ S3 Bucket       │
│ (CronJob)       │      │ Controller   │      │ (Backups)       │
└─────────────────┘      └──────────────┘      └─────────────────┘
                                │
                                │ creates
                                v
                         ┌──────────────┐
                         │ EBS Snapshot │
                         │ (Volumes)    │
                         └──────────────┘
```

### Restore Flow

```
┌──────────────┐      ┌──────────────┐      ┌─────────────────┐
│ velero CLI   │─────>│ Velero       │<─────│ S3 Bucket       │
│ or CRD       │      │ Controller   │      │ (Backup Data)   │
└──────────────┘      └──────────────┘      └─────────────────┘
                                │
                                │ restores
                                v
                         ┌──────────────┐
                         │ Kubernetes   │
                         │ Resources    │
                         └──────────────┘
                                │
                                │ mounts
                                v
                         ┌──────────────┐
                         │ EBS Volume   │
                         │ (from snap)  │
                         └──────────────┘
```

### IAM Permissions (IRSA)

**Velero Service Account**:
- Namespace: `velero`
- ServiceAccount: `velero-server`
- Annotation: `eks.amazonaws.com/role-arn: <velero-role-arn>`

**IAM Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::k8s-platform-staging-velero-backups-891377105802",
        "arn:aws:s3:::k8s-platform-staging-velero-backups-891377105802/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVolumes",
        "ec2:DescribeSnapshots",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Implementation

### Phase 1: Terraform Infrastructure (15 minutes)

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform

# 1. Add module to main.tf
cat >> main.tf <<EOF

# Velero Backup/DR Module
module "velero_backup" {
  source = "./modules/velero-backup"

  cluster_name       = var.cluster_name
  environment        = "staging"
  bucket_name        = "k8s-platform-staging-velero-backups-891377105802"
  velero_namespace   = "velero"
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.cluster_oidc_issuer_url
  aws_region         = "us-east-1"
}
EOF

# 2. Add outputs
cat >> outputs.tf <<EOF

output "velero_bucket_name" {
  description = "Velero backup S3 bucket name"
  value       = module.velero_backup.bucket_name
}

output "velero_role_arn" {
  description = "Velero IAM role ARN"
  value       = module.velero_backup.velero_role_arn
}
EOF

# 3. Apply Terraform
terraform init
terraform plan
terraform apply
```

### Phase 2: Helm Installation (10 minutes)

```bash
# 1. Add Helm repo
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# 2. Get IAM role ARN from Terraform
VELERO_ROLE_ARN=$(terraform output -raw velero_role_arn)
VELERO_BUCKET=$(terraform output -raw velero_bucket_name)

# 3. Template values.yaml
cd kubectl-manifests/velero
sed -e "s|\${VELERO_ROLE_ARN}|${VELERO_ROLE_ARN}|g" \
    -e "s|\${VELERO_BUCKET_NAME}|${VELERO_BUCKET}|g" \
    values.yaml > values-rendered.yaml

# 4. Install Velero
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --values values-rendered.yaml \
  --wait \
  --timeout 5m

# 5. Verify installation
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n velero --timeout=300s
kubectl get pods -n velero
velero version
```

### Phase 3: Backup Schedules (5 minutes)

```bash
# Apply backup schedules
kubectl apply -f backup-schedules.yaml

# Verify schedules created
velero schedule get

# Trigger manual backup for testing
velero backup create test-backup --include-namespaces cert-manager --wait
velero backup describe test-backup --details
```

### Phase 4: Restore Testing (10 minutes)

```bash
# Apply automated restore testing CronJob
kubectl apply -f restore-testing-cronjob.yaml

# Run manual restore test
kubectl create job velero-restore-test-manual \
  --from=cronjob/velero-restore-test \
  -n velero

# Monitor test
kubectl logs -n velero job/velero-restore-test-manual -f

# Expected: ✅ Restore test PASSED
```

### Phase 5: Monitoring (5 minutes)

```bash
# Verify Prometheus ServiceMonitor
kubectl get servicemonitor -n velero

# Check metrics in Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Navigate to: http://localhost:9090/targets
# Search for: velero

# Expected metrics:
# - velero_backup_total
# - velero_backup_success_total
# - velero_restore_total
# - velero_backup_last_successful_timestamp
```

---

## Validation Criteria

### Day 1 (Implementation Day)

- [ ] Terraform apply successful (S3 bucket + IAM role created)
- [ ] Velero pods Running (deployment + node-agent DaemonSet)
- [ ] Backup storage location Ready
- [ ] Volume snapshot location Ready
- [ ] Manual test backup Completed
- [ ] Manual test restore Completed
- [ ] Restored resources verified in test namespace

### Day 2 (First Scheduled Backup)

- [ ] `daily-full-backup` executed at 2:00 UTC
- [ ] Backup status: Completed
- [ ] Backup in S3 bucket
- [ ] Prometheus metrics visible
- [ ] No errors in Velero logs

### Week 1 (Full Cycle)

- [ ] Daily backups completing successfully
- [ ] Hourly critical backups completing
- [ ] Weekly PVC backup completed
- [ ] Automated restore test PASSED (Sunday)
- [ ] S3 lifecycle policies applied (check after 7 days)

### Month 1 (Long-term Validation)

- [ ] Monthly archive backup completed
- [ ] Old backups expired per retention policy
- [ ] S3 storage costs within budget ($5-10/month)
- [ ] DR runbook tested in simulated incident

---

## Metrics & Monitoring

### Success Metrics

**Backup Health**:
```promql
# Backup success rate (target: > 95%)
rate(velero_backup_success_total[24h]) / rate(velero_backup_total[24h])

# Backup duration (target: < 30 minutes)
velero_backup_duration_seconds

# Failed backups (target: 0)
velero_backup_failure_total
```

**Restore Health**:
```promql
# Restore success rate (target: > 95%)
rate(velero_restore_success_total[7d]) / rate(velero_restore_total[7d])

# Restore duration (target: < 15 minutes)
velero_restore_duration_seconds
```

**Storage Costs**:
```bash
# S3 bucket size (target: < 100 GB)
aws s3 ls s3://k8s-platform-staging-velero-backups-891377105802/ --recursive --summarize

# Monthly cost (target: $5-10)
aws ce get-cost-and-usage \
  --time-period Start=2026-02-01,End=2026-03-01 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --filter file://s3-cost-filter.json
```

### Alerts (Prometheus)

```yaml
# Alert: Backup failure
- alert: VeleroBackupFailed
  expr: velero_backup_failure_total > 0
  for: 5m
  annotations:
    summary: "Velero backup failed"

# Alert: No recent backup
- alert: VeleroNoRecentBackup
  expr: time() - velero_backup_last_successful_timestamp{schedule="daily-full-backup"} > 86400
  for: 1h
  annotations:
    summary: "No successful backup in 24h"
```

---

## Cost Analysis

### Monthly Costs

**S3 Storage** (7-day daily + 30-day weekly + 365-day monthly):
- Daily backups: ~10 GB × 7 = 70 GB × $0.023/GB = $1.61
- Weekly backups: ~10 GB × 4 = 40 GB × $0.023/GB = $0.92
- Monthly backups: ~10 GB × 12 = 120 GB × $0.004/GB (Glacier) = $0.48
- **Total Storage**: ~$3.01/month

**EBS Snapshots**:
- Daily PVC snapshots: ~50 GB × 7 = 350 GB × $0.05/GB = $17.50
- Weekly PVC snapshots: ~50 GB × 4 = 200 GB × $0.05/GB = $10.00
- Monthly archive: ~50 GB × 12 = 600 GB × $0.05/GB = $30.00
- **Total Snapshots**: ~$57.50/month

**API Requests**:
- S3 PUT/GET: ~1000 requests/month × $0.005/1000 = $0.005
- **Total API**: ~$0.01/month

**Grand Total**: ~$60.52/month

**Cost Optimization**:
- Reduce snapshot retention (e.g., 3-day daily vs 7-day): -$30/month
- Exclude non-critical PVCs from snapshots: -$15/month
- **Optimized Total**: ~$30/month

---

## Risk Assessment

| Risk                           | Probability | Impact | Mitigation                                   |
| ------------------------------ | ----------- | ------ | -------------------------------------------- |
| Backup failure (S3 access)     | Low         | High   | IRSA role monitoring, IAM policy validation  |
| Restore failure (incompatible) | Low         | Medium | Weekly automated restore testing             |
| Storage cost overrun           | Medium      | Low    | S3 lifecycle policies, retention limits      |
| Snapshot quota limit           | Low         | Medium | AWS Service Quotas monitoring                |
| Backup duration timeout        | Low         | Medium | Exclude large non-critical resources         |
| Human error (wrong restore)    | Medium      | High   | Namespace mapping, DR runbook, training      |

---

## Comparison: ADR-052 vs ADR-078

| Aspect                 | ADR-052 (Deferred)                  | ADR-078 (Implemented)                |
| ---------------------- | ----------------------------------- | ------------------------------------ |
| **Decision**           | Defer to Production                 | Implement in STAGING now             |
| **Rationale**          | MVP data disposable                 | Data criticality increased           |
| **RTO**                | 2-6 hours (manual rebuild)          | 1 hour (Velero restore)              |
| **RPO**                | RDS backups only (PostgreSQL)       | 24h (daily) / 1h (critical)          |
| **Cost**               | $0/month (no backup infra)          | $30-60/month (S3 + snapshots)        |
| **Risk Acceptance**    | High (data loss acceptable)         | Low (full recovery capability)       |
| **Production Ready**   | Untested (implement later)          | Proven (validated in STAGING)        |
| **Timeline**           | Q2-Q3 2026 (Production phase)       | 2026-02-25 (immediate)               |

---

## Alignment with Strategic Decisions

✅ **ADR-051 (PostgreSQL RDS)**: RDS backups remain primary for database, Velero adds K8s config backup
✅ **ADR-047 (Governance)**: Production-grade robustness now vs "good enough" MVP
✅ **ADR-022 (FinOps)**: $30-60/month investment prevents $2k+ incident recovery cost
✅ **ADR-074 (Namespace Migration)**: Velero enables safe namespace migrations with rollback capability

---

## Related Documentation

- **Supersedes**: [ADR-052: Velero Implementation Deferral](./adr-052-velero-implementation-strategy.md)
- **Runbook**: [Disaster Recovery Procedures](../runbooks/disaster-recovery.md)
- **Terraform Module**: `/platform-provisioning/aws/kubernetes/terraform/modules/velero-backup/`
- **Helm Values**: `/platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/velero/values.yaml`
- **Backup Schedules**: `/platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/velero/backup-schedules.yaml`
- **Restore Testing**: `/platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/velero/restore-testing-cronjob.yaml`

---

## Approval Status

- ✅ **CTO**: Approved (2026-02-25) - Strategy shift justified by increased data criticality
- ✅ **Platform Lead**: Technical validation approved
- ✅ **Architecture Team**: Risk acceptance approved

---

**Decision Finalized**: 2026-02-25
**Implementation Deadline**: 2026-02-27
**First DR Test**: 2026-03-04 (weekly restore test)

---

## Appendix: Key Learnings from ADR-052

**What Changed Since Feb 11**:

1. **STAGING Maturity**: Evolved from "disposable test" to "production-like integration environment"
2. **Data Criticality**: GitLab repositories, Vault secrets, Keycloak SSO configs now business-critical
3. **Recovery Complexity**: Manual rebuild estimate increased 2-6 hours → 6-8 hours
4. **Production Readiness**: Early implementation validates Production backup strategy
5. **Cost vs Risk**: $30-60/month cost justified by 6-8 hour reconstruction effort savings

**Decision Process**:

- **Feb 11**: "Skip Velero, data is disposable" ✅ Correct for MVP context
- **Feb 25**: "Implement Velero, data now critical" ✅ Correct for matured environment
- **Lesson**: Re-evaluate architectural decisions as environment matures
