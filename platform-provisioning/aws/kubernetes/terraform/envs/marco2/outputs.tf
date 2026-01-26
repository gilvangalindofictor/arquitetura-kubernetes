# -----------------------------------------------------------------------------
# Outputs - Marco 2
# -----------------------------------------------------------------------------

output "aws_load_balancer_controller_role_arn" {
  description = "ARN da IAM Role do AWS Load Balancer Controller"
  value       = module.aws_load_balancer_controller.iam_role_arn
}

output "aws_load_balancer_controller_service_account" {
  description = "Nome da Service Account do AWS Load Balancer Controller"
  value       = module.aws_load_balancer_controller.service_account_name
}

output "aws_load_balancer_controller_namespace" {
  description = "Namespace do AWS Load Balancer Controller"
  value       = module.aws_load_balancer_controller.namespace
}
