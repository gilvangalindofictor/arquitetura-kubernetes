# Deployment Guide — Snapshot Lifecycle Module

## Pre-Deployment Checklist

1. **Verify Snapshot Tags**: Ensure existing snapshots have proper tags
   ```bash
   aws ec2 describe-snapshots --owner-ids self \
     --query 'Snapshots[*].[SnapshotId,Tags[?Key==`velero.io/backup`].Value]' \
     --output table
   ```

2. **Review Current Snapshots**: Document baseline before DLM activation
   ```bash
   aws ec2 describe-snapshots --owner-ids self \
     --query 'Snapshots[*].[SnapshotId,StartTime,VolumeSize,State,Description]' \
     --output table
   ```

3. **Terraform Plan**: Review changes before applying
   ```bash
   cd environments/staging
   terraform plan -target=module.snapshot_lifecycle
   ```

## Deployment Steps

### Step 1: Terraform Apply (Staging)

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging

# Apply only the snapshot_lifecycle module
terraform apply -target=module.snapshot_lifecycle
```

**Expected Output:**
```
Terraform will perform the following actions:

  # module.snapshot_lifecycle.aws_dlm_lifecycle_policy.migration_snapshots will be created
  + resource "aws_dlm_lifecycle_policy" "migration_snapshots" {
      + arn                = (known after apply)
      + description        = "DLM policy for migration snapshots - 7 days retention"
      + execution_role_arn = (known after apply)
      + id                 = (known after apply)
      + state              = "ENABLED"
      + tags               = {
          + "Environment"   = "staging"
          + "Name"          = "migration-snapshot-lifecycle"
          + "Purpose"       = "Automated retention for migration-related snapshots"
          + "Criticality"   = "Low"
          + "RetentionDays" = "7"
        }
    }

  # module.snapshot_lifecycle.aws_dlm_lifecycle_policy.manual_snapshots will be created
  + resource "aws_dlm_lifecycle_policy" "manual_snapshots" {
      + arn                = (known after apply)
      + description        = "DLM policy for manual snapshots - 14 days retention"
      + execution_role_arn = (known after apply)
      + id                 = (known after apply)
      + state              = "ENABLED"
      + retention_days     = 14
    }

  # module.snapshot_lifecycle.aws_dlm_lifecycle_policy.velero_backups will be created
  + resource "aws_dlm_lifecycle_policy" "velero_backups" {
      + arn                = (known after apply)
      + description        = "DLM policy for Velero backup snapshots - 30 days retention"
      + execution_role_arn = (known after apply)
      + id                 = (known after apply)
      + state              = "ENABLED"
      + retention_days     = 30
    }

  # module.snapshot_lifecycle.aws_iam_role.dlm will be created
  # module.snapshot_lifecycle.aws_iam_policy.dlm will be created
  # module.snapshot_lifecycle.aws_iam_role_policy_attachment.dlm will be created

Plan: 6 to add, 0 to change, 0 to destroy.
```

### Step 2: Verify DLM Policies in AWS Console

1. Navigate to: **EC2 → Elastic Block Store → Lifecycle Manager**
2. Confirm three policies are listed:
   - `velero-snapshot-lifecycle` (ENABLED)
   - `manual-snapshot-lifecycle` (ENABLED)
   - `migration-snapshot-lifecycle` (ENABLED)

### Step 3: Monitor First Execution

DLM policies run daily. First execution times (UTC):

- **Velero**: 03:00 UTC (00:00 BRT)
- **Manual**: 03:30 UTC (00:30 BRT)
- **Migration**: 04:00 UTC (01:00 BRT)

**Check Execution Status:**
```bash
aws dlm get-lifecycle-policy --policy-id <policy-id>
```

## Post-Deployment Validation

### Day 1: Verify Policy Activation

```bash
# List all DLM policies
aws dlm get-lifecycle-policies --query 'Policies[*].[PolicyId,State,PolicyType]' --output table

# Get detailed policy info
aws dlm get-lifecycle-policy --policy-id policy-0xxxxxxxxxxxxx
```

### Week 1: Monitor Snapshot Retention

```bash
# Check for DLM-managed tags
aws ec2 describe-snapshots --owner-ids self \
  --filters "Name=tag:ManagedBy,Values=DLM" \
  --query 'Snapshots[*].[SnapshotId,StartTime,Tags[?Key==`RetentionPolicy`].Value]' \
  --output table
```

### Month 1: Validate Savings

```bash
# Count snapshots by age
aws ec2 describe-snapshots --owner-ids self \
  --query 'Snapshots[?StartTime>=`2026-01-01`] | length(@)'

# Expected reduction: 30% of 213 GB = ~64 GB deleted
# Cost reduction: R$ 252/ano ÷ 12 = ~R$ 21/month
```

## Rollback Procedure

If DLM policies cause issues:

1. **Disable Policies (Non-Destructive)**
   ```bash
   aws dlm update-lifecycle-policy \
     --policy-id <policy-id> \
     --state DISABLED
   ```

2. **Terraform Destroy Module**
   ```bash
   cd environments/staging
   terraform destroy -target=module.snapshot_lifecycle
   ```

3. **Revert Code Changes**
   ```bash
   git revert <commit-hash>
   ```

## Troubleshooting

### Issue: DLM Not Deleting Old Snapshots

**Cause**: Snapshots missing required tags

**Solution**:
```bash
# Tag existing Velero snapshots
aws ec2 create-tags \
  --resources snap-xxxxxxxxx \
  --tags Key=velero.io/backup,Value=manual-tag

# Tag manual snapshots
aws ec2 create-tags \
  --resources snap-yyyyyyyyy \
  --tags Key=Type,Value=manual-snapshot
```

### Issue: IAM Permission Denied

**Cause**: DLM role missing permissions

**Solution**: Verify IAM policy attachment
```bash
aws iam get-role --role-name k8s-platform-staging-dlm-lifecycle-role
aws iam list-attached-role-policies --role-name k8s-platform-staging-dlm-lifecycle-role
```

### Issue: Snapshots Deleted Too Aggressively

**Cause**: Retention days too low

**Solution**: Update module variables
```hcl
module "snapshot_lifecycle" {
  # Increase retention
  velero_retention_days = 45  # Was 30
  manual_retention_days = 21  # Was 14
}
```

Then apply:
```bash
terraform apply -target=module.snapshot_lifecycle
```

## Integration with Existing Cleanup

The `snapshot-cleanup` Lambda module continues to run weekly:

- **DLM (this module)**: Tag-based retention (daily)
- **Lambda cleanup**: Removes old untagged snapshots (weekly Monday 03:00 UTC)

Both modules are complementary and do not conflict.

## Success Criteria

- ✅ 3 DLM policies active and ENABLED
- ✅ IAM role created with least-privilege permissions
- ✅ No manual snapshots > 30 days old after 1 month
- ✅ Velero snapshots auto-deleted after 30 days
- ✅ Migration snapshots auto-deleted after 7 days
- ✅ Cost reduction: R$ 252/ano (validated in 3 months)

## References

- **Terraform Module**: `/modules/snapshot-lifecycle/`
- **Environment Config**: `/environments/staging/main.tf` (lines 2113-2133)
- **Cost Analysis**: MEMORY.md (FinOps savings tracking)
- **Related Modules**: `snapshot-cleanup` (Lambda-based cleanup)
