# =============================================================================
# CLUSTER AUTOSCALER MODULE - Main Configuration
# =============================================================================
# Implements Kubernetes Cluster Autoscaler with IRSA for AWS permissions
# Works with existing EKS Node Groups and Auto Scaling Groups
# =============================================================================

# -----------------------------------------------------------------------------
# DATA SOURCES
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Get EKS cluster info
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

# Get OIDC provider
data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# -----------------------------------------------------------------------------
# LOCALS
# -----------------------------------------------------------------------------

locals {
  oidc_provider_url = replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn
  account_id        = data.aws_caller_identity.current.account_id
  region            = data.aws_region.current.name
}

# -----------------------------------------------------------------------------
# IAM POLICY for Cluster Autoscaler
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_autoscaler" {
  # Describe Auto Scaling Groups
  statement {
    sid    = "DescribeAutoScalingGroups"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
    ]
    resources = ["*"]
  }

  # Describe EC2 Instances (for node discovery)
  statement {
    sid    = "DescribeInstances"
    effect = "Allow"
    actions = [
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
    ]
    resources = ["*"]
  }

  # Modify Auto Scaling Groups (scale up/down)
  statement {
    sid    = "ModifyAutoScalingGroups"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]

    # Restrict to EKS node groups only
    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "ClusterAutoscalerPolicy-${var.cluster_name}"
  description = "IAM policy for Cluster Autoscaler to manage Auto Scaling Groups"
  policy      = data.aws_iam_policy_document.cluster_autoscaler.json

  tags = merge(
    var.tags,
    {
      Name      = "ClusterAutoscalerPolicy-${var.cluster_name}"
      Component = "cluster-autoscaler"
    }
  )
}

# -----------------------------------------------------------------------------
# IAM ROLE for Cluster Autoscaler (IRSA)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_autoscaler_assume_role" {
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
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "ClusterAutoscalerRole-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume_role.json

  tags = merge(
    var.tags,
    {
      Name      = "ClusterAutoscalerRole-${var.cluster_name}"
      Component = "cluster-autoscaler"
    }
  )
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

# -----------------------------------------------------------------------------
# KUBERNETES SERVICE ACCOUNT
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }

    labels = {
      "app.kubernetes.io/name"       = "cluster-autoscaler"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  automount_service_account_token = true
}

# -----------------------------------------------------------------------------
# HELM RELEASE - Cluster Autoscaler
# -----------------------------------------------------------------------------

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.chart_version
  namespace  = var.namespace

  # Wait for service account to be created
  depends_on = [
    kubernetes_service_account.cluster_autoscaler,
    aws_iam_role_policy_attachment.cluster_autoscaler
  ]

  values = [
    yamlencode({
      # AWS and EKS configuration
      autoDiscovery = {
        clusterName = var.cluster_name
        enabled     = true
        tags        = ["k8s.io/cluster-autoscaler/enabled", "k8s.io/cluster-autoscaler/${var.cluster_name}"]
      }

      awsRegion = local.region

      # Service Account (use existing one)
      rbac = {
        create                 = true
        serviceAccount = {
          create      = false
          name        = var.service_account_name
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
          }
        }
      }

      # Deployment configuration
      replicaCount = 1

      # Resources
      resources = {
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }

      # Priority class
      priorityClassName = "system-cluster-critical"

      # Node placement
      nodeSelector = {
        "node-type" = "system"
      }

      # Tolerations (run on system nodes)
      tolerations = [
        {
          key      = "node-role.kubernetes.io/control-plane"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]

      # Cluster Autoscaler configuration
      extraArgs = {
        "v"                                 = "4" # Log verbosity
        "stderrthreshold"                   = "info"
        "cloud-provider"                    = "aws"
        "skip-nodes-with-system-pods"       = "false" # Allow scaling nodes with system pods
        "balance-similar-node-groups"       = "true"  # Balance across AZs
        "skip-nodes-with-local-storage"     = "false" # Can scale nodes with local storage
        "scale-down-enabled"                = var.scale_down_enabled
        "scale-down-delay-after-add"        = var.scale_down_delay_after_add
        "scale-down-unneeded-time"          = var.scale_down_unneeded_time
        "scale-down-utilization-threshold"  = var.scale_down_utilization_threshold
        "max-node-provision-time"           = "15m0s"
        "max-graceful-termination-sec"      = "600"
        "expander"                          = "least-waste" # Cost-efficient expander
      }

      # Service monitor (for Prometheus scraping)
      serviceMonitor = {
        enabled   = true
        namespace = var.namespace
        interval  = "30s"
      }

      # Pod labels
      podLabels = {
        "app.kubernetes.io/name"    = "cluster-autoscaler"
        "app.kubernetes.io/version" = var.chart_version
      }

      # Pod annotations (Prometheus)
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "8085"
        "prometheus.io/path"   = "/metrics"
      }

      # Security context
      securityContext = {
        runAsNonRoot = true
        runAsUser    = 65534 # nobody
        fsGroup      = 65534
      }

      containerSecurityContext = {
        allowPrivilegeEscalation = false
        readOnlyRootFilesystem   = true
        capabilities = {
          drop = ["ALL"]
        }
      }

      # Image
      image = {
        repository = "registry.k8s.io/autoscaling/cluster-autoscaler"
        tag        = "v${var.kubernetes_version}.0" # Match EKS version
        pullPolicy = "IfNotPresent"
      }
    })
  ]

  # Force update if values change
  recreate_pods = true
  cleanup_on_fail = true
  timeout         = 600

  lifecycle {
    create_before_destroy = true
  }
}
