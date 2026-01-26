# -----------------------------------------------------------------------------
# Outputs - AWS Load Balancer Controller Module
# -----------------------------------------------------------------------------

output "iam_role_arn" {
  description = "ARN da IAM Role criada para o controller"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "iam_role_name" {
  description = "Nome da IAM Role criada para o controller"
  value       = aws_iam_role.aws_load_balancer_controller.name
}

output "iam_policy_arn" {
  description = "ARN da IAM Policy criada para o controller"
  value       = aws_iam_policy.aws_load_balancer_controller.arn
}

output "service_account_name" {
  description = "Nome da Service Account Kubernetes"
  value       = kubernetes_service_account.aws_load_balancer_controller.metadata[0].name
}

output "namespace" {
  description = "Namespace onde o controller foi instalado"
  value       = var.namespace
}

output "helm_release_name" {
  description = "Nome do Helm release"
  value       = helm_release.aws_load_balancer_controller.name
}

output "helm_release_version" {
  description = "Versão do Helm chart instalado"
  value       = helm_release.aws_load_balancer_controller.version
}
