# Cluster Autoscaler Tags for EKS Node Groups
# Fix: Enable autoscaling for system and critical node groups
# Context: Grafana pod stuck Pending 18h due to disabled autoscaling
# Decision: ADR-TBD - Enable autoscaling for infra node groups
# Date: 2026-02-20

# Get Auto Scaling Group names from EKS node groups
data "aws_eks_node_group" "system" {
  cluster_name    = local.cluster_name
  node_group_name = "system"
}

data "aws_eks_node_group" "critical" {
  cluster_name    = local.cluster_name
  node_group_name = "critical"
}

data "aws_eks_node_group" "workloads" {
  cluster_name    = local.cluster_name
  node_group_name = "workloads"
}

# Enable Cluster Autoscaler for system node group
resource "aws_autoscaling_group_tag" "system_cluster_autoscaler_enabled" {
  autoscaling_group_name = data.aws_eks_node_group.system.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${local.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

# Enable Cluster Autoscaler for critical node group
resource "aws_autoscaling_group_tag" "critical_cluster_autoscaler_enabled" {
  autoscaling_group_name = data.aws_eks_node_group.critical.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${local.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

# Ensure workloads node group tag is present (already should be "owned")
resource "aws_autoscaling_group_tag" "workloads_cluster_autoscaler_enabled" {
  autoscaling_group_name = data.aws_eks_node_group.workloads.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${local.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

# Additional tag for discovery (recommended by AWS)
resource "aws_autoscaling_group_tag" "system_cluster_autoscaler_discovery" {
  autoscaling_group_name = data.aws_eks_node_group.system.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "critical_cluster_autoscaler_discovery" {
  autoscaling_group_name = data.aws_eks_node_group.critical.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "workloads_cluster_autoscaler_discovery" {
  autoscaling_group_name = data.aws_eks_node_group.workloads.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}
