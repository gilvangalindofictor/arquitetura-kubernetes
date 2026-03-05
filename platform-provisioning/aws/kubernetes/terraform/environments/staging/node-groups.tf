# node-groups.tf — EKS Node Groups (system, workloads, critical)
# Importado em 2026-03-05 — anteriormente gerenciados via AWS CLI (eks create-nodegroup)
# NOTE: data "aws_eks_node_group" já definidos em cluster-autoscaler-tags.tf — não replicar aqui
#
# Taint real do critical: workload=critical:NO_SCHEDULE (capturado via describe-nodegroup 2026-03-05)
# NOTA: platform-config.yaml documenta value="database" mas AWS retornou value="critical" — usando valor real
# max_size system: aumentado de 4→6 em 2026-03-05 (IaC debt documentado)
#
# ReleaseVersion: 1.34.2-20260129 — gerenciado via lifecycle ignore_changes (cluster autoscaler pode alterar)

locals {
  node_role_arn   = "arn:aws:iam::891377105802:role/k8s-platform-eks-node-role"
  private_subnets = ["subnet-0288a67cd352effa7", "subnet-0472ab28726cdf745"]

  node_group_common_tags = {
    Marco       = "marco1"
    Project     = "K8s-Platform"
    Owner       = "Platform-Team"
    ManagedBy   = "Terraform"
    CostCenter  = "Engineering"
    Environment = "staging"
  }
}

resource "aws_eks_node_group" "system" {
  cluster_name    = local.cluster_name
  node_group_name = "system"
  node_role_arn   = local.node_role_arn
  subnet_ids      = local.private_subnets

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  disk_size      = 30
  instance_types = ["t3.medium"]
  version        = "1.34"
  release_version = "1.34.2-20260129"

  scaling_config {
    desired_size = 4 # gerenciado pelo cluster autoscaler
    min_size     = 2
    max_size     = 6 # aumentado de 4→6 em 2026-03-05
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    node-type = "system"
    workload  = "platform"
  }

  tags = merge(local.node_group_common_tags, {
    Name      = "k8s-platform-prod-system"
    NodeGroup = "system"
  })

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size, # cluster autoscaler gerencia desired_size
      release_version,                 # EKS managed updates alteram release_version
    ]
  }
}

resource "aws_eks_node_group" "workloads" {
  cluster_name    = local.cluster_name
  node_group_name = "workloads"
  node_role_arn   = local.node_role_arn
  subnet_ids      = local.private_subnets

  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  disk_size       = 50
  instance_types  = ["t3.large"]
  version         = "1.34"
  release_version = "1.34.2-20260129"

  scaling_config {
    desired_size = 6 # gerenciado pelo cluster autoscaler
    min_size     = 2
    max_size     = 6
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    node-type = "workloads"
    workload  = "applications"
  }

  tags = merge(local.node_group_common_tags, {
    Name      = "k8s-platform-prod-workloads"
    NodeGroup = "workloads"
  })

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size,
      release_version,
    ]
  }
}

resource "aws_eks_node_group" "critical" {
  cluster_name    = local.cluster_name
  node_group_name = "critical"
  node_role_arn   = local.node_role_arn
  subnet_ids      = local.private_subnets

  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  disk_size       = 100
  instance_types  = ["t3.xlarge"]
  version         = "1.34"
  release_version = "1.34.2-20260129"

  scaling_config {
    desired_size = 2 # gerenciado pelo cluster autoscaler
    min_size     = 2
    max_size     = 4
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    node-type = "critical"
    workload  = "databases"
  }

  taint {
    key    = "workload"
    value  = "critical" # valor real capturado via describe-nodegroup (platform-config.yaml documenta "database" — divergência documentada)
    effect = "NO_SCHEDULE"
  }

  tags = merge(local.node_group_common_tags, {
    Name      = "k8s-platform-prod-critical"
    NodeGroup = "critical"
  })

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size,
      release_version,
    ]
  }
}
