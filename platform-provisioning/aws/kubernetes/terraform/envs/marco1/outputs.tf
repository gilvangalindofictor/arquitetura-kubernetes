# -----------------------------------------------------------------------------
# Outputs do EKS Cluster
# -----------------------------------------------------------------------------

output "cluster_id" {
  description = "ID do cluster EKS"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Versão do Kubernetes"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "Security group ID do cluster"
  value       = aws_security_group.eks_cluster.id
}

output "node_security_group_id" {
  description = "Security group ID dos nodes"
  value       = aws_security_group.eks_nodes.id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data do cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_arn" {
  description = "ARN do cluster EKS"
  value       = aws_eks_cluster.main.arn
}

output "kms_key_id" {
  description = "KMS key ID usado para criptografia de secrets"
  value       = aws_kms_key.eks.id
}

output "kms_key_arn" {
  description = "KMS key ARN usado para criptografia de secrets"
  value       = aws_kms_key.eks.arn
}

# -----------------------------------------------------------------------------
# Outputs dos Node Groups
# -----------------------------------------------------------------------------

output "node_group_system_id" {
  description = "ID do node group system"
  value       = aws_eks_node_group.system.id
}

output "node_group_system_status" {
  description = "Status do node group system"
  value       = aws_eks_node_group.system.status
}

output "node_group_workloads_id" {
  description = "ID do node group workloads"
  value       = aws_eks_node_group.workloads.id
}

output "node_group_workloads_status" {
  description = "Status do node group workloads"
  value       = aws_eks_node_group.workloads.status
}

output "node_group_critical_id" {
  description = "ID do node group critical"
  value       = aws_eks_node_group.critical.id
}

output "node_group_critical_status" {
  description = "Status do node group critical"
  value       = aws_eks_node_group.critical.status
}

# -----------------------------------------------------------------------------
# Comando para configurar kubectl
# -----------------------------------------------------------------------------

output "kubectl_config_command" {
  description = "Comando para configurar kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name} --profile k8s-platform-prod"
}
