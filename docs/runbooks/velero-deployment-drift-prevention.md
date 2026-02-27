# Velero Deployment and Drift Prevention Runbook

**Document ID:** RUNBOOK-VELERO-001
**Last Updated:** 2026-02-26
**Related Issues:** AÇÃO-002, VALIDAÇÃO-002, GAP-012, V-008
**Audience:** Platform Team, SRE

---

## Overview

This runbook documents the correct Velero deployment process and drift prevention mechanisms to avoid IRSA (IAM Roles for Service Accounts) configuration drift.

### Background

**Issue Identified (VALIDAÇÃO-002):**
- Manual `kubectl patch` commands were used to fix IRSA role and S3 bucket drift
- These patches work but are not persistent across `helm upgrade` operations
- Future Helm operations could revert to incorrect values if not properly managed

**Resolution (AÇÃO-002):**
- Documented correct deployment process via Terraform + Helm
- Created drift detection automation
- Established GitOps best practices

---

## Architecture

### Deployment Method

Velero is deployed using a **two-tier approach**:

1. **Infrastructure (Terraform):** IAM roles, S3 buckets, CRR configuration
   - Module: `modules/velero-dr/`
   - Environment: `environments/staging/`
   - Outputs: `velero_role_arn`, `velero_bucket_name`, `velero_primary_bucket_name`, `velero_replica_bucket_name`

2. **Application (Helm):** Velero server, node-agent, CRDs
   - Chart: `vmware-tanzu/velero` v8.1.0
   - Values template: `kubectl-manifests/velero/values.yaml`
   - Deployment script: `scripts/deploy-velero.sh`

### Configuration Flow

```
Terraform State (Source of Truth)
    ↓
terraform output (velero_role_arn, velero_bucket_name)
    ↓
sed template substitution (values.yaml → values-rendered.yaml)
    ↓
helm upgrade --values values-rendered.yaml
    ↓
Kubernetes Resources (ServiceAccount, BackupStorageLocation)
```

---

## Correct Configuration

### Expected Values (from Terraform)

| Parameter | Value |
|-----------|-------|
| **IAM Role ARN** | `arn:aws:iam::891377105802:role/k8s-platform-prod-velero-dr-role` |
| **Primary S3 Bucket** | `velero-backups-staging-891377105802-us-east-1` |
| **Replica S3 Bucket** | `velero-backups-staging-891377105802-us-west-2` |
| **Namespace** | `velero` |
| **ServiceAccount** | `velero-server` |

### Kubernetes Resources

**ServiceAccount Annotation:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: velero-server
  namespace: velero
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::891377105802:role/k8s-platform-prod-velero-dr-role
```

**BackupStorageLocation:**
```yaml
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: default
  namespace: velero
spec:
  provider: aws
  objectStorage:
    bucket: velero-backups-staging-891377105802-us-east-1
  config:
    region: us-east-1
  default: true
  accessMode: ReadWrite
status:
  phase: Available
```

---

## Deployment Procedures

### Initial Deployment

**Prerequisites:**
- AWS credentials configured (`aws sso login`)
- kubectl context set to `k8s-platform-prod`
- Terraform initialized in `environments/staging/`

**Steps:**

1. **Deploy infrastructure (Terraform):**
   ```bash
   cd platform-provisioning/aws/kubernetes/terraform/environments/staging
   terraform plan -target=module.velero_dr_staging
   terraform apply -target=module.velero_dr_staging -auto-approve
   ```

2. **Verify Terraform outputs:**
   ```bash
   terraform output velero_role_arn
   terraform output velero_bucket_name
   ```

3. **Deploy Velero (Helm):**
   ```bash
   cd /home/gilvangalindo/projects/Arquitetura/Kubernetes
   ./scripts/deploy-velero.sh
   ```

   This script will:
   - Retrieve Terraform outputs
   - Template `values.yaml` with correct IAM role and bucket
   - Install Velero via Helm
   - Deploy backup schedules
   - Run validation tests

### Updating Velero

**⚠️ IMPORTANT: Never use raw `helm upgrade` commands!**

**Correct Method:**

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes
./scripts/deploy-velero.sh
```

**Alternative (Manual):**

```bash
# 1. Get Terraform outputs
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
VELERO_ROLE_ARN=$(terraform output -raw velero_role_arn)
VELERO_BUCKET=$(terraform output -raw velero_bucket_name)

# 2. Template values
cd ../../kubectl-manifests/velero
sed -e "s|\${VELERO_ROLE_ARN}|${VELERO_ROLE_ARN}|g" \
    -e "s|\${VELERO_BUCKET_NAME}|${VELERO_BUCKET}|g" \
    values.yaml > values-rendered.yaml

# 3. Apply Helm upgrade
helm upgrade velero vmware-tanzu/velero \
  --namespace velero \
  --values values-rendered.yaml \
  --reuse-values=false \
  --wait \
  --timeout 5m
```

### Emergency Drift Remediation

If drift is detected (e.g., after manual kubectl patches):

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes
./scripts/velero/update-velero-values.sh
```

This script will:
1. Detect current vs. expected configuration
2. Prompt for confirmation
3. Apply Helm upgrade with correct values
4. Validate configuration post-update

---

## Drift Detection

### Automated Drift Detection

**Script:** `scripts/velero/check-velero-drift.sh`

**Usage:**

```bash
# Human-readable output
./scripts/velero/check-velero-drift.sh

# JSON output (for CI/CD)
./scripts/velero/check-velero-drift.sh --json

# Auto-fix drift (with confirmation)
./scripts/velero/check-velero-drift.sh --auto-fix
```

**Exit Codes:**
- `0`: No drift detected
- `1`: Drift detected (requires remediation)
- `2`: Error (prerequisites not met)

**Example JSON Output:**

```json
{
  "drift_detected": false,
  "drift_issues": [],
  "expected": {
    "iam_role_arn": "arn:aws:iam::891377105802:role/k8s-platform-prod-velero-dr-role",
    "s3_bucket": "velero-backups-staging-891377105802-us-east-1"
  },
  "current": {
    "iam_role_arn": "arn:aws:iam::891377105802:role/k8s-platform-prod-velero-dr-role",
    "s3_bucket": "velero-backups-staging-891377105802-us-east-1",
    "bsl_status": "Available"
  },
  "cluster": "k8s-platform-prod",
  "namespace": "velero",
  "timestamp": "2026-02-26T19:45:00Z"
}
```

### Manual Verification

**Check ServiceAccount annotation:**
```bash
kubectl get sa velero-server -n velero \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
```

**Expected:** `arn:aws:iam::891377105802:role/k8s-platform-prod-velero-dr-role`

**Check BackupStorageLocation:**
```bash
kubectl get backupstoragelocation default -n velero -o yaml
```

**Expected:**
- `spec.objectStorage.bucket`: `velero-backups-staging-891377105802-us-east-1`
- `status.phase`: `Available`

---

## CI/CD Integration

### Pre-Deployment Validation

Add to CI/CD pipeline **before** Helm operations:

```yaml
# Example: GitLab CI
velero-drift-check:
  stage: validate
  script:
    - ./scripts/velero/check-velero-drift.sh --json
  allow_failure: false
```

### Post-Deployment Validation

Add to CI/CD pipeline **after** Helm operations:

```yaml
velero-post-deploy-check:
  stage: verify
  script:
    - ./scripts/velero/check-velero-drift.sh
    - velero backup create ci-test-$(date +%s) --include-namespaces test --wait
  allow_failure: false
```

### Scheduled Drift Audits

Create a Kubernetes CronJob for daily drift detection:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: velero-drift-audit
  namespace: velero
spec:
  schedule: "0 8 * * *"  # Daily at 8:00 UTC
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: velero-drift-auditor
          containers:
          - name: drift-check
            image: platform-tools:latest
            command:
            - /scripts/velero/check-velero-drift.sh
            - --json
          restartPolicy: OnFailure
```

---

## Common Issues

### Issue 1: IAM Role ARN Mismatch

**Symptoms:**
- Velero pods in CrashLoopBackOff
- Logs: `NoSuchEntity: The role with name k8s-platform-prod-velero-role cannot be found`

**Root Cause:**
- ServiceAccount annotation points to old/non-existent IAM role

**Resolution:**
```bash
./scripts/velero/update-velero-values.sh
```

### Issue 2: S3 Bucket Mismatch

**Symptoms:**
- BackupStorageLocation status: `Unavailable`
- Logs: `NoSuchBucket: The specified bucket does not exist`

**Root Cause:**
- BackupStorageLocation configured with old/non-existent bucket

**Resolution:**
```bash
./scripts/velero/update-velero-values.sh
```

### Issue 3: Manual Patches Lost After Helm Upgrade

**Symptoms:**
- Configuration correct after `kubectl patch`, but reverted after `helm upgrade`

**Root Cause:**
- Helm manages resources declaratively; manual patches are overwritten

**Resolution:**
- **DO NOT** use `kubectl patch` for Velero configuration
- **ALWAYS** use `scripts/deploy-velero.sh` or `scripts/velero/update-velero-values.sh`
- Updates must go through Helm values templating process

---

## Best Practices

### DO ✅

1. **Use deployment scripts:** Always use `scripts/deploy-velero.sh` for deployments
2. **Verify Terraform outputs:** Ensure Terraform state is up-to-date before Helm operations
3. **Run drift detection:** Check for drift before and after changes
4. **Template values:** Use sed templating to substitute Terraform outputs into `values.yaml`
5. **Document changes:** Update this runbook when deployment process changes

### DON'T ❌

1. **Avoid manual patches:** Never use `kubectl patch` for ServiceAccount or BackupStorageLocation
2. **Avoid raw Helm commands:** Never run `helm upgrade` without templated values
3. **Avoid hardcoded values:** Never hardcode IAM role ARNs or bucket names in values.yaml
4. **Avoid out-of-band changes:** All configuration must go through GitOps workflow
5. **Avoid skipping validation:** Always run drift detection after changes

---

## Monitoring and Alerts

### Key Metrics

- **BackupStorageLocation availability:** `velero_backup_storage_location_available{location="default"}`
- **Backup success rate:** `velero_backup_success_total / velero_backup_total`
- **IRSA assume role errors:** `aws_sts_assume_role_errors{service_account="velero-server"}`

### Recommended Alerts

**BackupStorageLocation Unavailable:**
```yaml
- alert: VeleroBackupStorageLocationUnavailable
  expr: velero_backup_storage_location_available{location="default"} == 0
  for: 5m
  annotations:
    summary: "Velero BackupStorageLocation unavailable"
    description: "Check for IRSA drift or S3 bucket access issues"
    runbook: "docs/runbooks/velero-deployment-drift-prevention.md"
```

**Configuration Drift Detected:**
```yaml
- alert: VeleroConfigurationDrift
  expr: velero_drift_detected == 1
  for: 1m
  annotations:
    summary: "Velero configuration drift detected"
    description: "Run: ./scripts/velero/update-velero-values.sh"
    runbook: "docs/runbooks/velero-deployment-drift-prevention.md"
```

---

## References

- **Terraform Module:** `modules/velero-dr/`
- **Helm Values Template:** `kubectl-manifests/velero/values.yaml`
- **Deployment Script:** `scripts/deploy-velero.sh`
- **Drift Detection Script:** `scripts/velero/check-velero-drift.sh`
- **Update Script:** `scripts/velero/update-velero-values.sh`
- **ADR:** `docs/adr/adr-079-velero-backup-dr-implementation.md`
- **VALIDAÇÃO-002:** Manual patches applied 2026-02-25
- **AÇÃO-002:** Drift prevention implementation 2026-02-26

---

## Change Log

| Date | Author | Changes |
|------|--------|---------|
| 2026-02-26 | Platform Team | Initial version - documented correct deployment process and drift prevention |
| 2026-02-25 | Platform Team | Manual drift remediation (VALIDAÇÃO-002) |
