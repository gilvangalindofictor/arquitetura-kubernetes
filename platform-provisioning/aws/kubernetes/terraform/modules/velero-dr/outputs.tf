# =============================================================================
# Velero DR Multi-Region Module — Outputs
# GAP-012: Disaster Recovery Multi-Region
# =============================================================================

# ---------------------------------------------------------------------------
# S3 Buckets
# ---------------------------------------------------------------------------

output "primary_bucket_arn" {
  description = "ARN of the primary Velero backup S3 bucket (us-east-1 — source of CRR)"
  value       = aws_s3_bucket.velero_primary.arn
}

output "primary_bucket_name" {
  description = "Name of the primary Velero backup S3 bucket"
  value       = aws_s3_bucket.velero_primary.bucket
}

output "primary_bucket_region" {
  description = "AWS region of the primary Velero backup S3 bucket"
  value       = aws_s3_bucket.velero_primary.region
}

output "replica_bucket_arn" {
  description = "ARN of the replica Velero backup S3 bucket (us-west-2 — CRR destination / DR site)"
  value       = aws_s3_bucket.velero_replica.arn
}

output "replica_bucket_name" {
  description = "Name of the replica Velero backup S3 bucket"
  value       = aws_s3_bucket.velero_replica.bucket
}

output "replica_bucket_region" {
  description = "AWS region of the replica Velero backup S3 bucket"
  value       = aws_s3_bucket.velero_replica.region
}

# ---------------------------------------------------------------------------
# IAM — CRR replication role
# ---------------------------------------------------------------------------

output "replication_role_arn" {
  description = "ARN of the IAM role used by S3 CRR to replicate objects to the replica bucket"
  value       = aws_iam_role.velero_s3_crr.arn
}

# ---------------------------------------------------------------------------
# IAM — Velero IRSA role
# ---------------------------------------------------------------------------

output "velero_role_arn" {
  description = "ARN of the IAM role for the Velero service account (IRSA). Use in Helm values: serviceAccount.server.annotations.'eks.amazonaws.com/role-arn'"
  value       = aws_iam_role.velero_dr.arn
}

output "velero_policy_arn" {
  description = "ARN of the IAM policy granting Velero access to primary and replica S3 buckets"
  value       = aws_iam_policy.velero_dr.arn
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for Velero DR CloudWatch alarms. Empty string when create_sns_topic = false."
  value       = var.create_sns_topic ? aws_sns_topic.velero_dr_alerts[0].arn : var.existing_sns_topic_arn
}

output "cloudwatch_alarm_replication_failed_arn" {
  description = "ARN of the CloudWatch alarm that fires on S3 CRR replication failures"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.velero_replication_failed[0].arn : ""
}

output "cloudwatch_alarm_replication_pending_arn" {
  description = "ARN of the CloudWatch alarm that fires when replication bytes pending > 1GB"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.velero_replication_pending[0].arn : ""
}

# ---------------------------------------------------------------------------
# Backwards compatibility — legacy outputs kept for existing staging references
# ---------------------------------------------------------------------------

# Alias: matches the original velero-dr module output used in staging/outputs.tf
output "bucket_name" {
  description = "Alias for primary_bucket_name (backwards compatibility with v1 module)"
  value       = aws_s3_bucket.velero_primary.bucket
}

output "bucket_arn" {
  description = "Alias for primary_bucket_arn (backwards compatibility with v1 module)"
  value       = aws_s3_bucket.velero_primary.arn
}
