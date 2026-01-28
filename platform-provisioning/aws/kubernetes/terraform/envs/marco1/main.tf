terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Marco       = "marco1"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "subnet-id"
    values = var.private_subnet_ids
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "subnet-id"
    values = var.public_subnet_ids
  }
}

# -----------------------------------------------------------------------------
# Security Group para EKS Cluster
# -----------------------------------------------------------------------------

resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.cluster_name}-cluster-sg-"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "eks_cluster_ingress_workstation_https" {
  description       = "Allow workstation to communicate with the cluster API Server"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.existing.cidr_block]
  security_group_id = aws_security_group.eks_cluster.id
}

# -----------------------------------------------------------------------------
# Security Group para EKS Nodes
# -----------------------------------------------------------------------------

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.cluster_name}-node-sg-"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name                                        = "${var.cluster_name}-node-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "eks_nodes_internal" {
  description              = "Allow nodes to communicate with each other"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_nodes.id
}

resource "aws_security_group_rule" "eks_nodes_cluster_inbound" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
}

resource "aws_security_group_rule" "eks_cluster_inbound" {
  description              = "Allow pods to communicate with the cluster API Server"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = var.eks_cluster_role_arn

  # Importante: definir como false para coincidir com o comportamento padrão da AWS
  # Evita replace desnecessário ao importar clusters existentes
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_security_group_rule.eks_cluster_ingress_workstation_https
  ]

  tags = {
    Name = var.cluster_name
  }
}

# -----------------------------------------------------------------------------
# KMS Key para criptografia de secrets
# -----------------------------------------------------------------------------

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS cluster ${var.cluster_name} secrets encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name = "${var.cluster_name}-eks-secrets"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

# -----------------------------------------------------------------------------
# EKS Node Group: system
# -----------------------------------------------------------------------------

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "system"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnet_ids
  version         = var.cluster_version

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 30

  labels = {
    node-type = "system"
    workload  = "platform"
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name      = "${var.cluster_name}-system"
    NodeGroup = "system"
  }

  depends_on = [aws_eks_cluster.main, aws_eks_addon.vpc_cni]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# -----------------------------------------------------------------------------
# EKS Node Group: workloads
# -----------------------------------------------------------------------------

resource "aws_eks_node_group" "workloads" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "workloads"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnet_ids
  version         = var.cluster_version

  scaling_config {
    desired_size = 3
    min_size     = 2
    max_size     = 6
  }

  instance_types = ["t3.large"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 50

  labels = {
    node-type = "workloads"
    workload  = "applications"
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name      = "${var.cluster_name}-workloads"
    NodeGroup = "workloads"
  }

  depends_on = [aws_eks_cluster.main, aws_eks_addon.vpc_cni]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# -----------------------------------------------------------------------------
# EKS Node Group: critical
# -----------------------------------------------------------------------------

resource "aws_eks_node_group" "critical" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "critical"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnet_ids
  version         = var.cluster_version

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  instance_types = ["t3.xlarge"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 100

  labels = {
    node-type = "critical"
    workload  = "databases"
  }

  taint {
    key    = "workload"
    value  = "critical"
    effect = "NO_SCHEDULE"
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name      = "${var.cluster_name}-critical"
    NodeGroup = "critical"
  }

  depends_on = [aws_eks_cluster.main, aws_eks_addon.vpc_cni]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# -----------------------------------------------------------------------------
# IRSA for EBS CSI Driver
# -----------------------------------------------------------------------------

# Get OIDC provider
data "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Extract OIDC provider URL (without https://)
locals {
  oidc_provider_url = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn
}

# IAM Policy for EBS CSI Driver (AWS managed policy)
data "aws_iam_policy" "ebs_csi_driver" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# IAM Role for EBS CSI Driver Service Account
data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "AmazonEKS_EBS_CSI_DriverRole-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json

  tags = {
    Name      = "AmazonEKS_EBS_CSI_DriverRole-${var.cluster_name}"
    Component = "ebs-csi-driver"
    Marco     = "marco1"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = data.aws_iam_policy.ebs_csi_driver.arn
}

# -----------------------------------------------------------------------------
# EKS Add-ons
# -----------------------------------------------------------------------------

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.18.5-eksbuild.1" # Use latest compatible version
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_cluster.main]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = "v1.11.3-eksbuild.2" # Use latest compatible version
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_cluster.main, aws_eks_addon.vpc_cni]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.31.2-eksbuild.3" # Use latest compatible version
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_cluster.main]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.37.0-eksbuild.1" # Use latest compatible version
  resolve_conflicts_on_update = "PRESERVE"
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn

  depends_on = [
    aws_eks_node_group.system,
    aws_iam_role_policy_attachment.ebs_csi_driver
  ]
}
