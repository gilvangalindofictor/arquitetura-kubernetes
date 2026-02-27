output "dlm_role_arn" {
  description = "ARN of the IAM role used by DLM policies"
  value       = aws_iam_role.dlm.arn
}

output "dlm_role_name" {
  description = "Name of the IAM role used by DLM policies"
  value       = aws_iam_role.dlm.name
}

output "velero_policy_id" {
  description = "ID of the DLM policy for Velero backups"
  value       = aws_dlm_lifecycle_policy.velero_backups.id
}

output "velero_policy_arn" {
  description = "ARN of the DLM policy for Velero backups"
  value       = aws_dlm_lifecycle_policy.velero_backups.arn
}

output "manual_policy_id" {
  description = "ID of the DLM policy for manual snapshots"
  value       = aws_dlm_lifecycle_policy.manual_snapshots.id
}

output "manual_policy_arn" {
  description = "ARN of the DLM policy for manual snapshots"
  value       = aws_dlm_lifecycle_policy.manual_snapshots.arn
}

output "migration_policy_id" {
  description = "ID of the DLM policy for migration snapshots"
  value       = aws_dlm_lifecycle_policy.migration_snapshots.id
}

output "migration_policy_arn" {
  description = "ARN of the DLM policy for migration snapshots"
  value       = aws_dlm_lifecycle_policy.migration_snapshots.arn
}

output "policy_summary" {
  description = "Summary of DLM retention policies"
  value = {
    velero_retention_days    = var.velero_retention_days
    manual_retention_days    = var.manual_retention_days
    migration_retention_days = var.migration_retention_days
    total_policies           = 3
  }
}
