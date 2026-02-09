# -----------------------------------------------------------------------------
# Harbor Container Registry Module
# Private container registry with Trivy scanning and S3 storage (IRSA)
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# -----------------------------------------------------------------------------
# Random password for Harbor admin
# -----------------------------------------------------------------------------

resource "random_password" "harbor_admin" {
  length  = 24
  special = true
}

# -----------------------------------------------------------------------------
# Read PostgreSQL password from AWS Secrets Manager
# -----------------------------------------------------------------------------

data "aws_secretsmanager_secret" "postgresql_password" {
  name = "staging/postgresql/gitlab-password"
}

data "aws_secretsmanager_secret_version" "postgresql_password" {
  secret_id = data.aws_secretsmanager_secret.postgresql_password.id
}

# -----------------------------------------------------------------------------
# Read Redis password from Kubernetes secret
# -----------------------------------------------------------------------------

data "kubernetes_secret" "redis_password" {
  metadata {
    name      = "redis-password"
    namespace = "data-services"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for Harbor IRSA (S3 permissions)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "harbor_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:sub"
      values = [
        "system:serviceaccount:${var.namespace}:harbor",
        "system:serviceaccount:${var.namespace}:harbor-core",
        "system:serviceaccount:${var.namespace}:harbor-jobservice",
        "system:serviceaccount:${var.namespace}:harbor-registry"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "harbor" {
  name               = "HarborIRSA-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.harbor_assume_role.json

  tags = merge(var.common_tags, {
    Name                     = "HarborIRSA-${var.cluster_name}"
    "app.kubernetes.io/name" = "harbor"
  })
}

data "aws_iam_policy_document" "harbor_permissions" {
  # S3 permissions for image storage
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "harbor" {
  name        = "HarborIRSA-${var.cluster_name}"
  description = "IAM policy for Harbor IRSA (S3 image storage)"
  policy      = data.aws_iam_policy_document.harbor_permissions.json

  tags = merge(var.common_tags, {
    Name                     = "HarborIRSA-${var.cluster_name}"
    "app.kubernetes.io/name" = "harbor"
  })
}

resource "aws_iam_role_policy_attachment" "harbor" {
  role       = aws_iam_role.harbor.name
  policy_arn = aws_iam_policy.harbor.arn
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "harbor" {
  metadata {
    name = var.namespace

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"       = "harbor"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-harbor"
      "app.kubernetes.io/managed-by" = "terraform"
    })
  }
}

# -----------------------------------------------------------------------------
# Harbor ServiceAccount with IRSA annotation
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "harbor" {
  metadata {
    name      = "harbor"
    namespace = kubernetes_namespace.harbor.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.harbor.arn
    }

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "harbor"
      "app.kubernetes.io/instance" = "${var.cluster_name}-harbor"
    })
  }
}

# -----------------------------------------------------------------------------
# Harbor Admin Password Secret (managed by Terraform)
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "harbor_admin_password" {
  metadata {
    name      = "harbor-admin-password"
    namespace = kubernetes_namespace.harbor.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "harbor"
      "app.kubernetes.io/instance" = "${var.cluster_name}-harbor"
    })
  }

  data = {
    password = random_password.harbor_admin.result
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# Harbor Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "harbor" {
  name       = "harbor"
  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  version    = var.harbor_chart_version
  namespace  = kubernetes_namespace.harbor.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name          = var.cluster_name
    namespace             = var.namespace
    service_account       = kubernetes_service_account.harbor.metadata[0].name
    admin_password_secret = kubernetes_secret.harbor_admin_password.metadata[0].name
    postgresql_host       = var.postgresql_host
    postgresql_port       = var.postgresql_port
    postgresql_database   = var.postgresql_database
    postgresql_username   = var.postgresql_username
    postgresql_password   = data.aws_secretsmanager_secret_version.postgresql_password.secret_string
    redis_host            = var.redis_host
    redis_port            = var.redis_port
    redis_password_secret = data.kubernetes_secret.redis_password.data["password"]
    s3_bucket             = var.s3_bucket_name
    s3_region             = var.aws_region
    storage_class         = var.storage_class
    enable_trivy          = var.enable_trivy
    enable_monitoring     = var.enable_monitoring
  })]

  depends_on = [
    kubernetes_service_account.harbor,
    kubernetes_secret.harbor_admin_password,
    aws_iam_role_policy_attachment.harbor
  ]

  timeout = 600 # 10 minutes
}

# -----------------------------------------------------------------------------
# ConfigMap with Harbor robot account setup instructions
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "harbor_setup" {
  metadata {
    name      = "harbor-setup-instructions"
    namespace = kubernetes_namespace.harbor.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "harbor"
      "app.kubernetes.io/instance" = "${var.cluster_name}-harbor"
    })
  }

  data = {
    "create-robot-account.sh" = file("${path.module}/scripts/create-robot-account.sh")
  }
}
