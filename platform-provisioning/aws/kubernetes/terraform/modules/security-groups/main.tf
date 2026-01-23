// Módulo esqueleto: security-groups mínimo para EKS
variable "vpc_id" { type = string }

resource "aws_security_group" "eks_cluster" {
  name        = "eks-cluster-sg"
  vpc_id      = var.vpc_id
  description = "SG para control plane/cluster"
}

resource "aws_security_group" "eks_nodes" {
  name        = "eks-nodes-sg"
  vpc_id      = var.vpc_id
  description = "SG para worker nodes"
}

output "eks_cluster_sg" { value = aws_security_group.eks_cluster.id }
output "eks_nodes_sg" { value = aws_security_group.eks_nodes.id }
