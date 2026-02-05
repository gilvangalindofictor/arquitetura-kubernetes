# -----------------------------------------------------------------------------
# Harbor Module Outputs
# -----------------------------------------------------------------------------

output "namespace" {
  description = "Harbor namespace"
  value       = kubernetes_namespace.harbor.metadata[0].name
}

output "service_account_name" {
  description = "Harbor ServiceAccount name (IRSA)"
  value       = kubernetes_service_account.harbor.metadata[0].name
}

output "service_account_role_arn" {
  description = "Harbor IRSA role ARN"
  value       = aws_iam_role.harbor.arn
}

output "admin_password_secret" {
  description = "Harbor admin password secret name"
  value       = kubernetes_secret.harbor_admin_password.metadata[0].name
  sensitive   = true
}

output "harbor_url" {
  description = "Harbor UI/Registry URL (internal cluster DNS)"
  value       = "http://harbor-core.${kubernetes_namespace.harbor.metadata[0].name}.svc.cluster.local"
}

output "registry_url" {
  description = "Harbor registry URL for docker push/pull"
  value       = "harbor-core.${kubernetes_namespace.harbor.metadata[0].name}.svc.cluster.local"
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN used for image storage"
  value       = var.s3_bucket_arn
}
