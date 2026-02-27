# Snapshot Lifecycle Module

Automates EBS snapshot retention using AWS Data Lifecycle Manager (DLM).

## Overview

This module creates three DLM lifecycle policies to automatically manage EBS snapshot retention:

1. **Velero Backups**: 30 days retention (tagged with `velero.io/backup`)
2. **Manual Snapshots**: 14 days retention (tagged with `Type=manual-snapshot`)
3. **Migration Snapshots**: 7 days retention (tagged with `Purpose=migration`)

## Financial Impact

- **Current State**: 22 snapshots (213 GB, R$ 766/ano), no snapshots > 30 days
- **Projected Savings**: R$ 252/ano (30% reduction post-stabilization, 3 months)
- **ROI**: Prevents snapshot accumulation, automates manual cleanup tasks

## Usage

```hcl
module "snapshot_lifecycle" {
  source = "../../modules/snapshot-lifecycle"

  policy_name_prefix       = "k8s-platform-staging"
  velero_retention_days    = 30
  manual_retention_days    = 14
  migration_retention_days = 7

  common_tags = {
    Environment = "staging"
    ManagedBy   = "Terraform"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| policy_name_prefix | Prefix for IAM role and policy names | `string` | `"k8s-platform"` | no |
| velero_retention_days | Retention period for Velero backup snapshots (days) | `number` | `30` | no |
| manual_retention_days | Retention period for manual snapshots (days) | `number` | `14` | no |
| migration_retention_days | Retention period for migration snapshots (days) | `number` | `7` | no |
| common_tags | Common tags applied to all resources | `map(string)` | `{}` | no |

### Input Validation

- `velero_retention_days`: 7-365 days
- `manual_retention_days`: 1-180 days
- `migration_retention_days`: 1-30 days

## Outputs

| Name | Description |
|------|-------------|
| dlm_role_arn | ARN of the IAM role used by DLM policies |
| dlm_role_name | Name of the IAM role used by DLM policies |
| velero_policy_id | ID of the DLM policy for Velero backups |
| velero_policy_arn | ARN of the DLM policy for Velero backups |
| manual_policy_id | ID of the DLM policy for manual snapshots |
| manual_policy_arn | ARN of the DLM policy for manual snapshots |
| migration_policy_id | ID of the DLM policy for migration snapshots |
| migration_policy_arn | ARN of the DLM policy for migration snapshots |
| policy_summary | Summary of DLM retention policies |

## IAM Permissions

The module creates an IAM role with least-privilege permissions:

- `ec2:CreateSnapshot`, `ec2:CreateSnapshots`, `ec2:DeleteSnapshot`
- `ec2:DescribeVolumes`, `ec2:DescribeSnapshots`, `ec2:DescribeInstances`
- `ec2:CreateTags`, `ec2:DeleteTags`
- `events:PutRule`, `events:DeleteRule`, `events:DescribeRule`, etc. (for scheduling)

## DLM Policy Schedule

All policies run daily at different times (UTC):

- **Velero**: 03:00 UTC (00:00 BRT)
- **Manual**: 03:30 UTC (00:30 BRT)
- **Migration**: 04:00 UTC (01:00 BRT)

## Tagging Strategy

### Snapshots Must Have These Tags

| Policy | Tag Key | Tag Value | Example |
|--------|---------|-----------|---------|
| Velero | `velero.io/backup` | Any value (`*`) | `velero.io/backup=daily-20260227` |
| Manual | `Type` | `manual-snapshot` | `Type=manual-snapshot` |
| Migration | `Purpose` | `migration` | `Purpose=migration` |

### DLM-Managed Tags

DLM automatically adds these tags to snapshots it manages:

```hcl
ManagedBy       = "DLM"
RetentionPolicy = "velero-backups|manual-snapshots|migration-snapshots"
```

## Deployment Notes

1. **Initial Apply**: Run `terraform plan` to review changes before applying
2. **Validation**: Verify DLM policies in AWS Console → EC2 → Lifecycle Manager
3. **Monitoring**: Check DLM policy execution in CloudWatch Events
4. **Stabilization**: Full savings realized after 3 months of operation

## Integration with Existing Infrastructure

This module complements the `snapshot-cleanup` Lambda module:

- **DLM (this module)**: Automated retention based on tags (proactive)
- **Lambda cleanup**: Weekly cleanup of old snapshots not managed by DLM (reactive)

Both modules work together to ensure comprehensive snapshot lifecycle management.

## References

- [AWS Data Lifecycle Manager Documentation](https://docs.aws.amazon.com/ebs/latest/userguide/snapshot-lifecycle.html)
- [DLM IAM Roles](https://docs.aws.amazon.com/ebs/latest/userguide/snapshot-lifecycle-iam-role.html)
- Related: `modules/snapshot-cleanup/` (Lambda-based cleanup)
