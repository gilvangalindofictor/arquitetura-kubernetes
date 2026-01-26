# -----------------------------------------------------------------------------
# AWS Load Balancer Controller Module
# Descrição: Provê Ingress Controller para EKS usando AWS ALB/NLB
# Versão: v2.11.0
# -----------------------------------------------------------------------------

# Obter informações do cluster EKS
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# Extrair OIDC provider URL do cluster
locals {
  oidc_provider_url = replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")
}

# Obter OIDC provider existente
data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# -----------------------------------------------------------------------------
# IAM Policy para AWS Load Balancer Controller
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy-${var.cluster_name}"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/iam-policy.json")

  tags = merge(
    var.tags,
    {
      Name      = "AWSLoadBalancerControllerIAMPolicy-${var.cluster_name}"
      Component = "aws-load-balancer-controller"
      Marco     = "marco2"
    }
  )
}

# -----------------------------------------------------------------------------
# IAM Role com IRSA (IAM Roles for Service Accounts)
# -----------------------------------------------------------------------------

# Trust policy para Service Account
data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.eks.arn]
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

resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "AWSLoadBalancerControllerRole-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role.json

  tags = merge(
    var.tags,
    {
      Name      = "AWSLoadBalancerControllerRole-${var.cluster_name}"
      Component = "aws-load-balancer-controller"
      Marco     = "marco2"
    }
  )
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

# -----------------------------------------------------------------------------
# Kubernetes Service Account
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "aws_load_balancer_controller" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_load_balancer_controller.arn
    }

    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Helm Release - AWS Load Balancer Controller
# -----------------------------------------------------------------------------

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.aws_load_balancer_controller.metadata[0].name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  # Tolerate system nodes
  set {
    name  = "tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "tolerations[0].value"
    value = "system"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  # Node affinity for system nodes
  set {
    name  = "nodeSelector.node-type"
    value = "system"
  }

  # Enable Shield, WAF, Cognito features if needed
  set {
    name  = "enableShield"
    value = var.enable_shield
  }

  set {
    name  = "enableWaf"
    value = var.enable_waf
  }

  set {
    name  = "enableWafv2"
    value = var.enable_wafv2
  }

  depends_on = [
    kubernetes_service_account.aws_load_balancer_controller,
    aws_iam_role_policy_attachment.aws_load_balancer_controller
  ]
}
