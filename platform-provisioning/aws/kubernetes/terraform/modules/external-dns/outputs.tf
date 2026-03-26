# -----------------------------------------------------------------------------
# External DNS Module - Outputs
# Fase 5: DNS automation for EKS services via Route53
# -----------------------------------------------------------------------------

output "namespace" {
  description = "Kubernetes namespace where external-dns is deployed"
  value       = var.namespace
}

output "iam_role_arn" {
  description = "IAM role ARN used by external-dns (IRSA)"
  value       = aws_iam_role.external_dns.arn
}

output "iam_role_name" {
  description = "IAM role name used by external-dns (IRSA)"
  value       = aws_iam_role.external_dns.name
}

output "service_account_name" {
  description = "Kubernetes ServiceAccount name for external-dns"
  value       = var.service_account_name
}

output "helm_release_name" {
  description = "Helm release name for external-dns"
  value       = helm_release.external_dns.name
}

output "helm_release_version" {
  description = "Deployed external-dns Helm chart version"
  value       = helm_release.external_dns.version
}

output "txt_owner_id" {
  description = "TXT ownership ID used by external-dns (for cross-cluster conflict prevention)"
  value       = "${var.cluster_name}-${var.environment}"
}
