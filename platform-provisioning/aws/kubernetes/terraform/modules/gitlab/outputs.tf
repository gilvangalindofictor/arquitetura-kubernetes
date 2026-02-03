# =============================================================================
# GitLab Module Outputs - Marco 3 Fase 2
# Baseado em análise Terraform Specialist (Agent a3bcddf)
# =============================================================================

output "namespace" {
  description = "GitLab Kubernetes namespace"
  value       = kubernetes_namespace.gitlab.metadata[0].name
}

output "gitlab_url" {
  description = "GitLab URL (retrieve ALB DNS after deployment with: kubectl get ingress -n gitlab)"
  value       = var.enable_tls ? "https://${var.domain_name}" : "Pending ALB provisioning - check kubectl get ingress -n gitlab"
}

output "alb_dns_name" {
  description = "GitLab ALB DNS name (retrieve with: kubectl get ingress -n gitlab -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')"
  value       = "Check after deployment: kubectl get ingress -n gitlab"
}

output "root_password_secret_name" {
  description = "GitLab root password Kubernetes secret name"
  value       = kubernetes_secret.gitlab_root_password.metadata[0].name
  sensitive   = true
}

output "helm_chart_version" {
  description = "GitLab Helm chart version deployed"
  value       = helm_release.gitlab.version
}

output "service_account_name" {
  description = "GitLab ServiceAccount name (IRSA)"
  value       = kubernetes_service_account.gitlab.metadata[0].name
}

output "irsa_role_arn" {
  description = "IAM Role ARN for GitLab IRSA (S3 access)"
  value       = aws_iam_role.gitlab_sa.arn
}

output "postgresql_connection" {
  description = "PostgreSQL connection details"
  value = {
    host     = var.postgresql_host
    port     = var.postgresql_port
    database = var.postgresql_database
    username = var.postgresql_username
  }
  sensitive = true
}

output "redis_connection" {
  description = "Redis connection details"
  value = {
    host = var.redis_host
    port = var.redis_port
  }
}

output "s3_buckets" {
  description = "S3 buckets used by GitLab"
  value = {
    artifacts = var.s3_artifacts_bucket
    uploads   = var.s3_uploads_bucket
  }
}
