#------------------------------------------------------------------------------
# Outputs — ECR Pull-Through Cache Module
#------------------------------------------------------------------------------

output "ecr_registry_prefix" {
  description = "Full ECR registry prefix (account.dkr.ecr.region.amazonaws.com)"
  value       = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "ecr_public_prefix" {
  description = "ECR pull-through prefix for ECR Public images"
  value       = var.enable_ecr_public ? "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/ecr-public" : ""
}

output "quay_prefix" {
  description = "ECR pull-through prefix for Quay.io images"
  value       = var.enable_quay ? "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/quay" : ""
}

output "ghcr_prefix" {
  description = "ECR pull-through prefix for GHCR images"
  value       = var.enable_ghcr ? "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/ghcr" : ""
}

output "k8s_prefix" {
  description = "ECR pull-through prefix for Kubernetes Registry images"
  value       = var.enable_k8s ? "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/k8s" : ""
}

output "docker_hub_prefix" {
  description = "ECR pull-through prefix for Docker Hub images"
  value       = var.enable_docker_hub ? "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/docker-hub" : ""
}

output "node_policy_arn" {
  description = "ARN of the IAM policy attached to node role"
  value       = aws_iam_policy.ecr_pull_through_cache.arn
}

output "template_custom_role_arn" {
  description = "ARN of the custom IAM role used by ECR repository creation templates (for tagging)"
  value       = aws_iam_role.ecr_template_custom.arn
}

output "vpc_endpoint_ecr_api_id" {
  description = "VPC Endpoint ID for ECR API (empty if disabled)"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ecr_api[0].id : ""
}

output "vpc_endpoint_ecr_dkr_id" {
  description = "VPC Endpoint ID for ECR DKR (empty if disabled)"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ecr_dkr[0].id : ""
}
