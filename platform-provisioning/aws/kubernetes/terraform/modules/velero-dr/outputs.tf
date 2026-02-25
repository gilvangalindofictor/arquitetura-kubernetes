output "bucket_name" {
  description = "Name of the Velero backup S3 bucket"
  value       = aws_s3_bucket.velero_backups.bucket
}

output "bucket_arn" {
  description = "ARN of the Velero backup S3 bucket"
  value       = aws_s3_bucket.velero_backups.arn
}

output "velero_role_arn" {
  description = "ARN of the IAM role for Velero service account"
  value       = aws_iam_role.velero.arn
}

output "velero_policy_arn" {
  description = "ARN of the IAM policy for Velero"
  value       = aws_iam_policy.velero.arn
}

output "aws_region" {
  description = "AWS region for backups"
  value       = var.aws_region
}
