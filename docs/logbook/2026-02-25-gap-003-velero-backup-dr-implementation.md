# Logbook: GAP-003 Velero Backup/DR Implementation

**Date**: 2026-02-25
**Type**: Feature Implementation
**Status**: ✅ READY FOR DEPLOYMENT
**Duration**: ~2 hours (preparation phase)
**Related**: ADR-078, ADR-052 (superseded)

---

## Summary

Implemented complete Velero backup/disaster recovery solution for Kubernetes platform, reversing ADR-052 decision to defer implementation to Production phase.

**Deliverables**:
- ✅ Terraform module for S3 bucket + IAM (IRSA)
- ✅ Helm values configuration for Velero v1.15.1
- ✅ 4 backup schedules (daily, weekly, hourly, monthly)
- ✅ Disaster recovery runbook (RTO: 1h, RPO: 24h)
- ✅ Automated restore testing CronJob
- ✅ ADR-078 documenting architecture and strategy shift

---

## Context

### Initial Decision (ADR-052 - Feb 11, 2026)

**Decision**: Defer Velero to Production phase
**Rationale**:
- STAGING data considered "disposable test data"
- Manual recovery estimated at < 2 hours
- Limited implementation bandwidth
- Cost optimization for MVP

### Strategy Shift (ADR-078 - Feb 25, 2026)

**New Decision**: Implement Velero in STAGING immediately
**Rationale**:
1. **Data Criticality Increased**:
   - GitLab: Repository content, CI/CD configs, runner tokens
   - Vault: 7 active KV paths, 10 synced ExternalSecrets
   - Keycloak: 6 integrated services (ArgoCD, GitLab, Harbor, Grafana, SonarQube, Vault)
   - ArgoCD: ApplicationSets automation, GitOps patterns

2. **Recovery Time Grew**:
   - Feb 11 estimate: 2 hours manual reconstruction
   - Feb 25 estimate: 6-8 hours (environment maturity increased complexity)

3. **Production Validation**:
   - Implementing in STAGING validates Production backup strategy
   - Identifies edge cases and operational issues before critical deployment
   - Proves RTO/RPO targets achievable

4. **Cost Justified**:
   - Cost: $30-60/month (S3 + EBS snapshots)
   - Value: Prevents 6-8 hour reconstruction effort
   - ROI: Positive after first incident avoided

---

## Implementation

### Phase 1: Terraform Infrastructure

**Module Created**: `/platform-provisioning/aws/kubernetes/terraform/modules/velero-backup/`

**Components**:
```hcl
# S3 Bucket
resource "aws_s3_bucket" "velero_backups" {
  bucket = "k8s-platform-staging-velero-backups-891377105802"
  # Versioning enabled
  # Server-side encryption (AES256)
  # Public access blocked
}

# Lifecycle Policies
- Daily backups: 7-day retention → prefix: daily/
- Weekly backups: 30-day retention → prefix: weekly/
- Monthly backups: 365-day retention → prefix: monthly/
- Glacier transition: 14 days (cost optimization)

# IAM Policy (IRSA)
- S3 permissions: GetObject, PutObject, DeleteObject, ListBucket
- EC2 permissions: DescribeVolumes, CreateSnapshot, DeleteSnapshot, CreateTags

# IAM Role
- Trust policy: EKS OIDC provider
- Condition: system:serviceaccount:velero:velero-server
```

**Files**:
- `main.tf`: S3 bucket, lifecycle, IAM policy, IAM role
- `variables.tf`: cluster_name, environment, bucket_name, OIDC config
- `outputs.tf`: bucket_name, bucket_arn, velero_role_arn
- `versions.tf`: Terraform >= 1.5, AWS provider ~> 5.0

---

### Phase 2: Helm Configuration

**File**: `/kubectl-manifests/velero/values.yaml`

**Configuration**:
```yaml
# IRSA (no static credentials)
credentials:
  useSecret: false

serviceAccount:
  server:
    annotations:
      eks.amazonaws.com/role-arn: ${VELERO_ROLE_ARN}

# Backup storage location
configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: ${VELERO_BUCKET_NAME}
      config:
        region: us-east-1
        serverSideEncryption: AES256

  # Volume snapshot location (EBS)
  volumeSnapshotLocation:
    - name: default
      provider: aws
      config:
        region: us-east-1

# AWS plugin
initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.11.0

# Node agent (restic) for file-level backups
deployNodeAgent: true

# Prometheus metrics
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
```

**Resource Allocation**:
- Velero server: 100m CPU / 256Mi RAM (requests), 500m CPU / 512Mi RAM (limits)
- Node agent: 100m CPU / 128Mi RAM (requests), 500m CPU / 512Mi RAM (limits)
- Node selector: workload=system
- Tolerations: system node pool

---

### Phase 3: Backup Schedules

**File**: `/kubectl-manifests/velero/backup-schedules.yaml`

**Schedules**:

| Name                    | Frequency      | Time (UTC) | Retention | Scope                     | RPO    |
| ----------------------- | -------------- | ---------- | --------- | ------------------------- | ------ |
| `daily-full-backup`     | Daily          | 02:00      | 7 days    | All namespaces (excl sys) | 24h    |
| `weekly-pvc-backup`     | Weekly (Sun)   | 03:00      | 30 days   | PVCs + PVs only           | 7 days |
| `hourly-critical`       | Hourly         | :00        | 24 hours  | Critical namespaces       | 1h     |
| `monthly-archive`       | Monthly (1st)  | 04:00      | 365 days  | Full cluster (compliance) | 30d    |

**Critical Namespaces** (hourly backup):
- `staging-security-vault`: Vault secrets management
- `keycloak`: SSO platform (6 integrated services)
- `argocd`: GitOps automation
- `gitlab-staging`: CI/CD platform + repositories

**Excluded Namespaces** (can be recreated):
- `kube-system`: System components
- `kube-public`: Public objects
- `kube-node-lease`: Node heartbeats

---

### Phase 4: Disaster Recovery Runbook

**File**: `/docs/runbooks/disaster-recovery.md`

**Procedures**:
1. **Full Cluster Restore**: Complete cluster rebuild (RTO: 60 minutes)
2. **Namespace Restore**: Single namespace recovery (RTO: 15 minutes)
3. **Application Restore**: Rollback to previous state (RTO: 10 minutes)
4. **Volume Restore**: PVC data recovery (RTO: 20 minutes)

**Validation Checklist**:
- All namespaces present
- All deployments ready
- All PVCs bound
- All pods running
- Critical services accessible
- External secrets synced
- Database connectivity
- SSO integration

**Troubleshooting**:
- Velero pod not running
- Backup not completing
- Restore stuck
- S3 access denied

---

### Phase 5: Automated Restore Testing

**File**: `/kubectl-manifests/velero/restore-testing-cronjob.yaml`

**Configuration**:
- **Schedule**: Weekly (Sunday 05:00 UTC) - after weekly backup completes
- **Test Procedure**:
  1. Find latest successful daily backup
  2. Delete previous test namespace
  3. Create restore to isolated namespace (`velero-restore-test`)
  4. Verify restored resources (deployments, services, configmaps)
  5. Wait for pods to be ready
  6. Collect statistics (warnings, errors)
  7. Cleanup test resources
  8. Send Slack notification (if configured)

- **Success Criteria**: Restore status = Completed, Errors = 0
- **Isolation**: Test namespace separate from production (no impact)
- **RBAC**: Dedicated ServiceAccount with cluster-scoped permissions

**Resource Allocation**:
- 100m CPU / 128Mi RAM (requests)
- 500m CPU / 256Mi RAM (limits)
- Timeout: 30 minutes

---

## Architecture Decisions (ADR-078)

### Key Decisions

1. **IRSA over Static Credentials**
   - No AWS access keys stored in cluster
   - Automatic credential rotation via OIDC
   - Least-privilege IAM policy

2. **S3 + EBS Snapshots (Hybrid)**
   - S3: Kubernetes resource manifests (YAML)
   - EBS Snapshots: Persistent volume data
   - Optimized for AWS native integration

3. **Lifecycle Policies for Cost Optimization**
   - Daily backups: 7-day retention (recent recovery)
   - Weekly backups: 30-day retention (mid-term recovery)
   - Monthly backups: 365-day retention (compliance/audit)
   - Glacier transition after 14 days (50% cost reduction)

4. **Multi-tier Backup Strategy**
   - Critical namespaces: Hourly backups (RPO: 1h)
   - All namespaces: Daily backups (RPO: 24h)
   - PVCs only: Weekly backups (long-term storage)
   - Full cluster: Monthly archive (compliance)

5. **Automated Restore Testing**
   - Weekly validation (prevents backup rot)
   - Isolated test namespace (no production impact)
   - Slack notifications (operational visibility)

---

## Metrics & Monitoring

### Prometheus Metrics

**Backup Health**:
```promql
# Backup success rate (target: > 95%)
rate(velero_backup_success_total[24h]) / rate(velero_backup_total[24h])

# Backup duration (target: < 30 minutes)
histogram_quantile(0.95, velero_backup_duration_seconds_bucket)

# Failed backups (target: 0)
velero_backup_failure_total
```

**Restore Health**:
```promql
# Restore success rate (target: > 95%)
rate(velero_restore_success_total[7d]) / rate(velero_restore_total[7d])

# Last successful backup timestamp
velero_backup_last_successful_timestamp{schedule="daily-full-backup"}
```

### Alerts

**Critical**:
- `VeleroBackupFailed`: Backup failure detected
- `VeleroNoRecentBackup`: No successful backup in 24h

**Warning**:
- `VeleroBackupDurationHigh`: Backup taking > 30 minutes
- `VeleroRestoreTestFailed`: Weekly restore test failed

---

## Cost Estimation

### Monthly Costs (Staging)

**S3 Storage**:
- Daily backups (7-day retention): ~70 GB × $0.023/GB = **$1.61**
- Weekly backups (30-day retention): ~40 GB × $0.023/GB = **$0.92**
- Monthly backups (365-day retention, Glacier): ~120 GB × $0.004/GB = **$0.48**
- **Subtotal S3**: **$3.01/month**

**EBS Snapshots**:
- Daily PVC snapshots: ~350 GB × $0.05/GB = **$17.50**
- Weekly PVC snapshots: ~200 GB × $0.05/GB = **$10.00**
- Monthly archive snapshots: ~600 GB × $0.05/GB = **$30.00**
- **Subtotal Snapshots**: **$57.50/month**

**API Requests**:
- S3 PUT/GET: ~$0.01/month
- **Subtotal API**: **$0.01/month**

**Total Monthly Cost**: **~$60.52/month**

**Cost Optimization Options**:
- Reduce snapshot retention (3-day vs 7-day daily): -$30/month
- Exclude non-critical PVCs: -$15/month
- **Optimized Total**: **~$30/month**

### ROI Analysis

**Cost**: $30-60/month ($360-720/year)

**Value**:
- Prevents 6-8 hour reconstruction effort
- Developer hourly rate: $50/hour × 8 hours = $400 per incident
- Break-even: 1 incident avoided per year
- Expected incidents: 2-3 per year (accidental deletions, misconfigurations)

**ROI**: Positive ($800-1200 value vs $360-720 cost = **$440-480 net benefit/year**)

---

## Validation Plan

### Day 1 (Implementation Day)

- [ ] AWS SSO authentication successful
- [ ] Terraform apply creates S3 bucket + IAM role
- [ ] Helm install Velero successful
- [ ] Velero pods Running (deployment + node-agent DaemonSet)
- [ ] Backup storage location: Ready
- [ ] Volume snapshot location: Ready
- [ ] Manual test backup: Completed
- [ ] Manual test restore: Completed
- [ ] Restored resources verified in test namespace

### Day 2 (First Scheduled Backup)

- [ ] `daily-full-backup` executed at 02:00 UTC
- [ ] Backup status: Completed (check via `velero backup get`)
- [ ] Backup visible in S3 bucket
- [ ] Prometheus metrics collected
- [ ] No errors in Velero logs

### Week 1 (Full Cycle)

- [ ] 7 daily backups completed
- [ ] 24 hourly critical backups completed
- [ ] 1 weekly PVC backup completed
- [ ] Automated restore test PASSED (Sunday 05:00 UTC)
- [ ] S3 lifecycle policies applied (7-day retention)

### Month 1 (Long-term Validation)

- [ ] Monthly archive backup completed (1st of month)
- [ ] Old backups expired per retention policy
- [ ] S3 storage costs within budget ($30-60/month)
- [ ] DR runbook tested in simulated namespace deletion

---

## Deployment Instructions

### Prerequisites

```bash
# 1. AWS SSO authentication
aws sso login --profile k8s-platform-staging

# 2. Verify AWS access
aws sts get-caller-identity

# 3. Verify kubectl access
kubectl cluster-info
kubectl get nodes

# 4. Install Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.15.1/velero-v1.15.1-linux-amd64.tar.gz
tar -xzf velero-v1.15.1-linux-amd64.tar.gz
sudo mv velero-v1.15.1-linux-amd64/velero /usr/local/bin/
velero version --client-only
```

### Step 1: Apply Terraform (15 minutes)

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform

# Verify module exists
ls -la modules/velero-backup/

# Initialize Terraform (if needed)
terraform init

# Plan changes
terraform plan -out=velero-backup.tfplan

# Review plan output
# Expected: + aws_s3_bucket.velero_backups
#           + aws_iam_policy.velero
#           + aws_iam_role.velero
#           + aws_iam_role_policy_attachment.velero

# Apply changes
terraform apply velero-backup.tfplan

# Save outputs
VELERO_ROLE_ARN=$(terraform output -raw velero_role_arn)
VELERO_BUCKET=$(terraform output -raw velero_bucket_name)

echo "Velero Role ARN: ${VELERO_ROLE_ARN}"
echo "Velero Bucket: ${VELERO_BUCKET}"
```

### Step 2: Install Velero via Helm (10 minutes)

```bash
cd kubectl-manifests/velero

# Add Helm repository
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Template values.yaml with Terraform outputs
sed -e "s|\${VELERO_ROLE_ARN}|${VELERO_ROLE_ARN}|g" \
    -e "s|\${VELERO_BUCKET_NAME}|${VELERO_BUCKET}|g" \
    values.yaml > values-rendered.yaml

# Verify templated values
grep -E "role-arn|bucket:" values-rendered.yaml

# Install Velero
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --values values-rendered.yaml \
  --wait \
  --timeout 5m

# Verify installation
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n velero --timeout=300s
kubectl get pods -n velero
velero version
```

**Expected Output**:
```
Client:
  Version: v1.15.1

Server:
  Version: v1.15.1
```

### Step 3: Deploy Backup Schedules (5 minutes)

```bash
# Apply backup schedules
kubectl apply -f backup-schedules.yaml

# Verify schedules created
velero schedule get

# Expected output:
# NAME                      STATUS    SCHEDULE      PAUSED
# daily-full-backup         Enabled   0 2 * * *     false
# weekly-pvc-backup         Enabled   0 3 * * 0     false
# hourly-critical-backup    Enabled   0 * * * *     false
# monthly-archive-backup    Enabled   0 4 1 * *     false

# Describe schedule details
velero schedule describe daily-full-backup
```

### Step 4: Test Manual Backup (10 minutes)

```bash
# Create manual test backup
velero backup create test-backup-$(date +%Y%m%d%H%M%S) \
  --include-namespaces cert-manager \
  --wait \
  --timeout 10m

# Check backup status
BACKUP_NAME=$(velero backup get -o json | jq -r '.items[0].metadata.name')
velero backup describe ${BACKUP_NAME} --details

# Verify backup in S3
aws s3 ls s3://${VELERO_BUCKET}/backups/${BACKUP_NAME}/ --recursive

# Check backup logs
velero backup logs ${BACKUP_NAME}
```

### Step 5: Test Manual Restore (10 minutes)

```bash
# Create restore from test backup
velero restore create test-restore-$(date +%Y%m%d%H%M%S) \
  --from-backup ${BACKUP_NAME} \
  --namespace-mappings cert-manager:velero-restore-test \
  --wait \
  --timeout 10m

# Check restore status
RESTORE_NAME=$(velero restore get -o json | jq -r '.items[0].metadata.name')
velero restore describe ${RESTORE_NAME} --details

# Verify restored resources
kubectl get all -n velero-restore-test

# Cleanup test namespace
kubectl delete namespace velero-restore-test
velero restore delete ${RESTORE_NAME} --confirm
velero backup delete ${BACKUP_NAME} --confirm
```

### Step 6: Deploy Automated Restore Testing (5 minutes)

```bash
# Apply restore testing CronJob
kubectl apply -f restore-testing-cronjob.yaml

# Verify CronJob created
kubectl get cronjob -n velero

# Run manual test now (optional)
kubectl create job velero-restore-test-manual \
  --from=cronjob/velero-restore-test \
  -n velero

# Monitor test logs
kubectl logs -n velero job/velero-restore-test-manual -f

# Expected output: ✅ Restore test PASSED
```

### Step 7: Configure Monitoring (5 minutes)

```bash
# Verify Prometheus ServiceMonitor created
kubectl get servicemonitor -n velero

# Check metrics endpoint
kubectl port-forward -n velero svc/velero 8085:8085 &
curl http://localhost:8085/metrics | grep velero_backup

# Access Prometheus UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
# Navigate to: http://localhost:9090/targets
# Search for: velero

# Verify metrics visible:
# - velero_backup_total
# - velero_backup_success_total
# - velero_backup_last_successful_timestamp
```

---

## Known Issues & Mitigations

### Issue 1: AWS SSO Token Expiration

**Symptom**: Backup fails with "Error getting credentials: AccessDenied"

**Cause**: AWS SSO session expired (12-hour default)

**Mitigation**:
```bash
# Re-authenticate
aws sso login --profile k8s-platform-staging

# Verify access
aws sts get-caller-identity
```

**Prevention**: IRSA eliminates this issue (no user credentials needed)

---

### Issue 2: EBS Snapshot Quota Limit

**Symptom**: Backup fails with "SnapshotCreationPerVolumeRateExceeded"

**Cause**: AWS limits snapshots per volume (5 per hour)

**Mitigation**:
```bash
# Reduce backup frequency for PVCs
# OR exclude non-critical PVCs from snapshots
velero backup create <name> --snapshot-volumes=false
```

**Prevention**: Stagger backup schedules, request quota increase

---

### Issue 3: Large Backup Duration

**Symptom**: Backup takes > 30 minutes

**Cause**: Large PVCs (e.g., GitLab repositories > 100 GB)

**Mitigation**:
```bash
# Exclude large PVCs from daily backups
velero backup create <name> --exclude-resources persistentvolumeclaims

# Use weekly PVC-specific backup instead
```

**Prevention**: Separate backup schedules for large volumes

---

## Next Steps

### Immediate (Week 1)

- [ ] Monitor first daily backup (2026-02-26 02:00 UTC)
- [ ] Monitor first hourly critical backup
- [ ] Verify S3 bucket lifecycle policies applied
- [ ] Check Prometheus metrics collection
- [ ] Update PROJECT-CONTEXT.md with Velero status

### Short-term (Month 1)

- [ ] Run simulated disaster recovery drill
- [ ] Test namespace deletion + restore
- [ ] Validate weekly restore test automation
- [ ] Review S3 costs vs budget
- [ ] Optimize backup retention if needed

### Long-term (Quarter 1)

- [ ] Replicate Velero setup for Production cluster
- [ ] Cross-region backup replication (DR enhancement)
- [ ] Integrate with incident management (PagerDuty/Opsgenie)
- [ ] Create Velero operational playbooks

---

## References

- **ADR-078**: [Velero Backup/DR Implementation](../adr/adr-078-velero-backup-dr-implementation.md)
- **ADR-052**: [Velero Implementation Deferral](../adr/adr-052-velero-implementation-strategy.md) (SUPERSEDED)
- **DR Runbook**: [Disaster Recovery Procedures](../runbooks/disaster-recovery.md)
- **Velero Docs**: https://velero.io/docs/v1.15/
- **AWS Plugin**: https://github.com/vmware-tanzu/velero-plugin-for-aws

---

## Commit Information

**Expected Commit Message**:
```
feat(backup): implement Velero DR solution (GAP-003)

- Terraform module: S3 bucket + IAM policy/role (IRSA)
- Helm values: Velero v1.15.1 + AWS plugin v1.11.0
- Backup schedules: daily (7d), weekly (30d), hourly critical, monthly archive
- DR runbook: RTO 1h, RPO 24h (critical: 1h)
- Automated restore testing: weekly CronJob
- ADR-078: Strategy shift from deferred (ADR-052) to immediate implementation

Cost: $30-60/month
Value: Prevents 6-8h reconstruction effort
ROI: Positive after 1 incident avoided

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Files Modified/Created**:
- `platform-provisioning/aws/kubernetes/terraform/modules/velero-backup/` (new module)
- `platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/velero/` (new manifests)
- `docs/adr/adr-078-velero-backup-dr-implementation.md` (new ADR)
- `docs/runbooks/disaster-recovery.md` (new runbook)
- `docs/logbook/2026-02-25-gap-003-velero-backup-dr-implementation.md` (this file)

---

**Status**: ✅ READY FOR DEPLOYMENT
**Estimated Deployment Time**: 60 minutes
**Risk Level**: LOW (isolated namespace, automated testing)
**Rollback Plan**: Delete Velero namespace, remove Terraform module
