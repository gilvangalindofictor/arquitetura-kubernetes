# =============================================================================
# CLUSTER AUTOSCALER TAGS - Auto Scaling Groups
# =============================================================================
# Adds required tags to existing Auto Scaling Groups for Cluster Autoscaler
# discovery. These tags are separate from the node group creation to avoid
# triggering resource replacement.
# =============================================================================

# Get ASG names from node groups
data "aws_eks_node_groups" "cluster" {
  cluster_name = aws_eks_cluster.main.name

  depends_on = [
    aws_eks_node_group.system,
    aws_eks_node_group.workloads,
    aws_eks_node_group.critical
  ]
}

# Get ASG details for system node group
data "aws_autoscaling_groups" "system" {
  filter {
    name   = "tag:eks:nodegroup-name"
    values = ["system"]
  }

  filter {
    name   = "tag:eks:cluster-name"
    values = [var.cluster_name]
  }

  depends_on = [aws_eks_node_group.system]
}

# Get ASG details for workloads node group
data "aws_autoscaling_groups" "workloads" {
  filter {
    name   = "tag:eks:nodegroup-name"
    values = ["workloads"]
  }

  filter {
    name   = "tag:eks:cluster-name"
    values = [var.cluster_name]
  }

  depends_on = [aws_eks_node_group.workloads]
}

# Get ASG details for critical node group
data "aws_autoscaling_groups" "critical" {
  filter {
    name   = "tag:eks:nodegroup-name"
    values = ["critical"]
  }

  filter {
    name   = "tag:eks:cluster-name"
    values = [var.cluster_name]
  }

  depends_on = [aws_eks_node_group.critical]
}

# -----------------------------------------------------------------------------
# ADD CLUSTER AUTOSCALER TAGS - Workloads ASG (Autoscaling ENABLED)
# -----------------------------------------------------------------------------

resource "aws_autoscaling_group_tag" "workloads_ca_enabled" {
  count = length(data.aws_autoscaling_groups.workloads.names) > 0 ? 1 : 0

  autoscaling_group_name = data.aws_autoscaling_groups.workloads.names[0]

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "workloads_ca_cluster" {
  count = length(data.aws_autoscaling_groups.workloads.names) > 0 ? 1 : 0

  autoscaling_group_name = data.aws_autoscaling_groups.workloads.names[0]

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

# -----------------------------------------------------------------------------
# ADD CLUSTER AUTOSCALER TAGS - System ASG (Autoscaling DISABLED)
# -----------------------------------------------------------------------------
# Note: Even though autoscaling is disabled, we still add tags for documentation
# To disable autoscaling: set min=max in scaling_config

resource "aws_autoscaling_group_tag" "system_ca_disabled" {
  count = length(data.aws_autoscaling_groups.system.names) > 0 ? 1 : 0

  autoscaling_group_name = data.aws_autoscaling_groups.system.names[0]

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "false"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "system_ca_cluster_disabled" {
  count = length(data.aws_autoscaling_groups.system.names) > 0 ? 1 : 0

  autoscaling_group_name = data.aws_autoscaling_groups.system.names[0]

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "disabled"
    propagate_at_launch = false
  }
}

# -----------------------------------------------------------------------------
# ADD CLUSTER AUTOSCALER TAGS - Critical ASG (Autoscaling DISABLED)
# -----------------------------------------------------------------------------

resource "aws_autoscaling_group_tag" "critical_ca_disabled" {
  count = length(data.aws_autoscaling_groups.critical.names) > 0 ? 1 : 0

  autoscaling_group_name = data.aws_autoscaling_groups.critical.names[0]

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "false"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "critical_ca_cluster_disabled" {
  count = length(data.aws_autoscaling_groups.critical.names) > 0 ? 1 : 0

  autoscaling_group_name = data.aws_autoscaling_groups.critical.names[0]

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "disabled"
    propagate_at_launch = false
  }
}

# -----------------------------------------------------------------------------
# OUTPUTS
# -----------------------------------------------------------------------------

output "autoscaling_groups_tagged" {
  description = "Auto Scaling Groups with Cluster Autoscaler tags"
  value = {
    workloads = {
      name               = length(data.aws_autoscaling_groups.workloads.names) > 0 ? data.aws_autoscaling_groups.workloads.names[0] : "not-found"
      autoscaling_enabled = "true"
    }
    system = {
      name                = length(data.aws_autoscaling_groups.system.names) > 0 ? data.aws_autoscaling_groups.system.names[0] : "not-found"
      autoscaling_enabled = "false"
    }
    critical = {
      name                = length(data.aws_autoscaling_groups.critical.names) > 0 ? data.aws_autoscaling_groups.critical.names[0] : "not-found"
      autoscaling_enabled = "false"
    }
  }
}
