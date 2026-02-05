# -----------------------------------------------------------------------------
# Vault Module Outputs
# -----------------------------------------------------------------------------

output "namespace" {
  description = "Vault namespace"
  value       = kubernetes_namespace.vault.metadata[0].name
}

output "service_account" {
  description = "Vault ServiceAccount name"
  value       = kubernetes_service_account.vault.metadata[0].name
}

output "iam_role_arn" {
  description = "IAM Role ARN for Vault IRSA"
  value       = aws_iam_role.vault.arn
}

output "kms_key_id" {
  description = "KMS Key ID for Vault auto-unseal"
  value       = aws_kms_key.vault_unseal.id
}

output "kms_key_arn" {
  description = "KMS Key ARN for Vault auto-unseal"
  value       = aws_kms_key.vault_unseal.arn
}

output "s3_bucket_name" {
  description = "S3 bucket name for Vault snapshots"
  value       = aws_s3_bucket.vault_snapshots.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN for Vault snapshots"
  value       = aws_s3_bucket.vault_snapshots.arn
}

output "vault_addr" {
  description = "Vault service address (internal)"
  value       = "http://vault.${kubernetes_namespace.vault.metadata[0].name}.svc.cluster.local:8200"
}
