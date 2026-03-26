# =============================================================================
# S3 Buckets Module Outputs
# =============================================================================

# GitLab Artifacts Bucket
# DEC-2026-03-24: conditional on enable_gitlab_artifacts (false in staging, true in prod)
output "gitlab_artifacts_bucket_name" {
  description = "GitLab artifacts S3 bucket name"
  value       = var.enable_gitlab_artifacts ? aws_s3_bucket.gitlab_artifacts[0].id : ""
}

output "gitlab_artifacts_bucket_arn" {
  description = "GitLab artifacts S3 bucket ARN"
  value       = var.enable_gitlab_artifacts ? aws_s3_bucket.gitlab_artifacts[0].arn : ""
}

output "gitlab_artifacts_bucket_region" {
  description = "GitLab artifacts S3 bucket region"
  value       = var.enable_gitlab_artifacts ? aws_s3_bucket.gitlab_artifacts[0].region : ""
}

output "gitlab_s3_policy_arn" {
  description = "IAM policy ARN for GitLab S3 access (IRSA)"
  value       = var.enable_gitlab_artifacts ? aws_iam_policy.gitlab_s3[0].arn : ""
}

# Harbor Images Bucket
output "harbor_images_bucket_name" {
  description = "Harbor images S3 bucket name"
  value       = aws_s3_bucket.harbor_images.id
}

output "harbor_images_bucket_arn" {
  description = "Harbor images S3 bucket ARN"
  value       = aws_s3_bucket.harbor_images.arn
}

output "harbor_images_bucket_region" {
  description = "Harbor images S3 bucket region"
  value       = aws_s3_bucket.harbor_images.region
}

output "harbor_s3_policy_arn" {
  description = "IAM policy ARN for Harbor S3 access (IRSA)"
  value       = aws_iam_policy.harbor_s3.arn
}

# Keycloak Backups Bucket (TASK-003)
output "keycloak_backups_bucket_name" {
  description = "Keycloak backups S3 bucket name"
  value       = aws_s3_bucket.keycloak_backups.id
}

output "keycloak_backups_bucket_arn" {
  description = "Keycloak backups S3 bucket ARN"
  value       = aws_s3_bucket.keycloak_backups.arn
}

output "keycloak_backups_bucket_region" {
  description = "Keycloak backups S3 bucket region"
  value       = aws_s3_bucket.keycloak_backups.region
}

output "keycloak_backup_s3_policy_arn" {
  description = "IAM policy ARN for Keycloak backup S3 access (IRSA)"
  value       = aws_iam_policy.keycloak_backup_s3.arn
}

# Summary
output "buckets_summary" {
  description = "Summary of all S3 buckets created"
  value = merge(
    var.enable_gitlab_artifacts ? {
      gitlab_artifacts = {
        name   = aws_s3_bucket.gitlab_artifacts[0].id
        arn    = aws_s3_bucket.gitlab_artifacts[0].arn
        region = aws_s3_bucket.gitlab_artifacts[0].region
      }
    } : {},
    {
      harbor_images = {
        name   = aws_s3_bucket.harbor_images.id
        arn    = aws_s3_bucket.harbor_images.arn
        region = aws_s3_bucket.harbor_images.region
      }
      keycloak_backups = {
        name   = aws_s3_bucket.keycloak_backups.id
        arn    = aws_s3_bucket.keycloak_backups.arn
        region = aws_s3_bucket.keycloak_backups.region
      }
    },
    var.enable_fct_proposals ? {
      fct_proposals = {
        name   = aws_s3_bucket.fct_proposals[0].id
        arn    = aws_s3_bucket.fct_proposals[0].arn
        region = aws_s3_bucket.fct_proposals[0].region
      }
    } : {}
  )
}

# FCT Proposals Bucket (TASK-004)
output "fct_proposals_bucket_name" {
  description = "FCT proposals S3 bucket name"
  value       = var.enable_fct_proposals ? aws_s3_bucket.fct_proposals[0].id : ""
}

output "fct_proposals_bucket_arn" {
  description = "FCT proposals S3 bucket ARN"
  value       = var.enable_fct_proposals ? aws_s3_bucket.fct_proposals[0].arn : ""
}

output "fct_proposals_bucket_region" {
  description = "FCT proposals S3 bucket region"
  value       = var.enable_fct_proposals ? aws_s3_bucket.fct_proposals[0].region : ""
}

output "hatch_etl_policy_arn" {
  description = "IAM policy ARN for Hatch ETL S3 access"
  value       = var.enable_fct_proposals ? aws_iam_policy.hatch_etl_fct_proposals[0].arn : ""
}

output "bucketconnector_policy_arn" {
  description = "IAM policy ARN for BucketConnector S3 access"
  value       = var.enable_fct_proposals ? aws_iam_policy.bucketconnector_fct_proposals[0].arn : ""
}
