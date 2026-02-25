# Velero Backup/DR Terraform Module

Terraform module for provisioning AWS infrastructure required by Velero backup/disaster recovery solution.

## Overview

This module creates:
- **S3 Bucket**: Backup storage with versioning, encryption, lifecycle policies
- **IAM Policy**: Permissions for S3 access and EBS snapshot management
- **IAM Role**: IRSA (IAM Roles for Service Accounts) for velero-server ServiceAccount

## Features

- IRSA authentication (no static credentials)
- Server-side encryption (AES256)
- Lifecycle policies for cost optimization
- Public access blocked
- Multi-tier retention (daily, weekly, monthly)
- Glacier transition after 14 days

## Usage

```hcl
module "velero_backup" {
  source = "./modules/velero-backup"

  cluster_name       = "k8s-platform-staging"
  environment        = "staging"
  bucket_name        = "k8s-platform-staging-velero-backups-891377105802"
  velero_namespace   = "velero"
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.cluster_oidc_issuer_url
  aws_region         = "us-east-1"
}
```

## Inputs

| Name                | Type   | Default   | Description                                |
| ------------------- | ------ | --------- | ------------------------------------------ |
| `cluster_name`      | string | -         | Name of the EKS cluster                    |
| `environment`       | string | -         | Environment name (staging, production)     |
| `bucket_name`       | string | -         | Name of the S3 bucket for Velero backups   |
| `velero_namespace`  | string | `"velero"`| Kubernetes namespace for Velero            |
| `oidc_provider_arn` | string | -         | ARN of the EKS OIDC provider               |
| `oidc_provider_url` | string | -         | URL of the EKS OIDC provider               |
| `aws_region`        | string | `"us-east-1"` | AWS region for backups                 |

## Outputs

| Name               | Description                                  |
| ------------------ | -------------------------------------------- |
| `bucket_name`      | Name of the Velero backup S3 bucket          |
| `bucket_arn`       | ARN of the Velero backup S3 bucket           |
| `velero_role_arn`  | ARN of the IAM role for Velero ServiceAccount|
| `velero_policy_arn`| ARN of the IAM policy for Velero             |
| `aws_region`       | AWS region for backups                       |

## S3 Lifecycle Policies

The module configures three lifecycle rules:

### 1. Daily Backup Retention
- **Prefix**: `daily/`
- **Retention**: 7 days
- **Noncurrent Versions**: 3 days

### 2. Weekly Backup Retention
- **Prefix**: `weekly/`
- **Retention**: 30 days
- **Noncurrent Versions**: 7 days

### 3. Glacier Transition
- **All Objects**: Transition to Glacier after 14 days
- **Cost Savings**: ~50% reduction vs Standard S3

## IAM Permissions

### S3 Permissions
- `s3:GetObject`
- `s3:PutObject`
- `s3:DeleteObject`
- `s3:AbortMultipartUpload`
- `s3:ListMultipartUploadParts`
- `s3:ListBucket`

### EC2 Permissions (for EBS snapshots)
- `ec2:DescribeVolumes`
- `ec2:DescribeSnapshots`
- `ec2:CreateTags`
- `ec2:CreateVolume`
- `ec2:CreateSnapshot`
- `ec2:DeleteSnapshot`

## IRSA Configuration

The IAM role is configured for IRSA (IAM Roles for Service Accounts):

```hcl
assume_role_policy = {
  Principal = {
    Federated = var.oidc_provider_arn
  }
  Condition = {
    StringEquals = {
      "${oidc_provider_url}:sub" = "system:serviceaccount:velero:velero-server"
      "${oidc_provider_url}:aud" = "sts.amazonaws.com"
    }
  }
}
```

This allows the `velero-server` ServiceAccount in the `velero` namespace to assume the IAM role without static credentials.

## Cost Estimation

### Monthly Costs (Staging - 50 GB data)

**S3 Storage**:
- Daily backups (7-day retention): ~70 GB × $0.023/GB = $1.61
- Weekly backups (30-day retention): ~40 GB × $0.023/GB = $0.92
- Monthly backups (365-day Glacier): ~120 GB × $0.004/GB = $0.48
- **Total S3**: ~$3.01/month

**EBS Snapshots**:
- Daily PVC snapshots: ~350 GB × $0.05/GB = $17.50
- Weekly PVC snapshots: ~200 GB × $0.05/GB = $10.00
- Monthly archive snapshots: ~600 GB × $0.05/GB = $30.00
- **Total Snapshots**: ~$57.50/month

**Total Estimated Cost**: ~$60/month (staging environment)

### Cost Optimization
- Reduce snapshot retention: Save ~$30/month
- Exclude non-critical PVCs: Save ~$15/month
- **Optimized Total**: ~$30/month

## Security

- **Encryption**: Server-side encryption (AES256) enabled
- **Versioning**: Enabled for accidental deletion protection
- **Public Access**: Blocked via bucket public access block
- **IAM**: Least-privilege permissions via IRSA
- **Tags**: All resources tagged for cost allocation

## Examples

### Staging Environment

```hcl
module "velero_backup_staging" {
  source = "./modules/velero-backup"

  cluster_name       = "k8s-platform-staging"
  environment        = "staging"
  bucket_name        = "k8s-platform-staging-velero-backups-891377105802"
  velero_namespace   = "velero"
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.cluster_oidc_issuer_url
  aws_region         = "us-east-1"
}
```

### Production Environment

```hcl
module "velero_backup_production" {
  source = "./modules/velero-backup"

  cluster_name       = "k8s-platform-production"
  environment        = "production"
  bucket_name        = "k8s-platform-production-velero-backups-891377105802"
  velero_namespace   = "velero"
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.cluster_oidc_issuer_url
  aws_region         = "us-east-1"
}
```

## Post-Deployment

After applying this module:

1. **Install Velero via Helm**:
   ```bash
   VELERO_ROLE_ARN=$(terraform output -raw velero_role_arn)
   VELERO_BUCKET=$(terraform output -raw velero_bucket_name)

   helm install velero vmware-tanzu/velero \
     --namespace velero \
     --create-namespace \
     --set credentials.useSecret=false \
     --set serviceAccount.server.annotations."eks\.amazonaws\.com/role-arn"=${VELERO_ROLE_ARN} \
     --set configuration.backupStorageLocation[0].bucket=${VELERO_BUCKET}
   ```

2. **Apply Backup Schedules**:
   ```bash
   kubectl apply -f kubectl-manifests/velero/backup-schedules.yaml
   ```

3. **Verify Installation**:
   ```bash
   velero version
   velero backup-location get
   velero schedule get
   ```

## Related Documentation

- [ADR-079: Velero Backup/DR Implementation](../../../../../docs/adr/adr-079-velero-backup-dr-implementation.md)
- [Disaster Recovery Runbook](../../../../../docs/runbooks/disaster-recovery.md)
- [Logbook: GAP-003 Implementation](../../../../../docs/logbook/2026-02-25-gap-003-velero-backup-dr-implementation.md)

## Requirements

- Terraform >= 1.5
- AWS Provider ~> 5.0
- EKS cluster with OIDC provider configured
- kubectl access to cluster
- Velero CLI v1.15+

## License

Managed by Platform Team - Internal Use Only
