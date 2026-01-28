# =============================================================================
# OUTPUTS - Cluster Autoscaler Module
# =============================================================================

output "iam_role_arn" {
  description = "ARN of the IAM role used by Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.name
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy attached to the Cluster Autoscaler role"
  value       = aws_iam_policy.cluster_autoscaler.arn
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = kubernetes_service_account.cluster_autoscaler.metadata[0].name
}

output "namespace" {
  description = "Namespace where Cluster Autoscaler is installed"
  value       = var.namespace
}

output "helm_release_name" {
  description = "Name of the Helm release"
  value       = helm_release.cluster_autoscaler.name
}

output "helm_release_version" {
  description = "Version of the Helm chart deployed"
  value       = helm_release.cluster_autoscaler.version
}

output "scale_down_enabled" {
  description = "Whether scale-down is enabled"
  value       = var.scale_down_enabled
}

output "configuration_summary" {
  description = "Summary of Cluster Autoscaler configuration"
  value = {
    cluster_name                      = var.cluster_name
    namespace                         = var.namespace
    scale_down_enabled                = var.scale_down_enabled
    scale_down_delay_after_add        = var.scale_down_delay_after_add
    scale_down_unneeded_time          = var.scale_down_unneeded_time
    scale_down_utilization_threshold  = var.scale_down_utilization_threshold
    kubernetes_version                = var.kubernetes_version
  }
}
