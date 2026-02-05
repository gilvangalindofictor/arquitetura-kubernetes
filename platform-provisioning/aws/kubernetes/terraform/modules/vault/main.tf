# -----------------------------------------------------------------------------
# Vault HA Cluster Module
# Deploying HashiCorp Vault with KMS auto-unseal and Raft storage
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
  }
}

# -----------------------------------------------------------------------------
# KMS Key for Vault Auto-Unseal
# -----------------------------------------------------------------------------

resource "aws_kms_key" "vault_unseal" {
  description             = "KMS key for Vault auto-unseal - ${var.cluster_name}"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.common_tags, {
    Name                     = "${var.cluster_name}-vault-unseal"
    "app.kubernetes.io/name" = "vault"
    Purpose                  = "vault-auto-unseal"
  })
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/vault-unseal-${var.cluster_name}"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

# -----------------------------------------------------------------------------
# S3 Bucket for Vault Snapshots
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "vault_snapshots" {
  bucket = "${var.cluster_name}-vault-snapshots-${var.aws_account_id}"

  tags = merge(var.common_tags, {
    Name                     = "${var.cluster_name}-vault-snapshots"
    "app.kubernetes.io/name" = "vault"
    Purpose                  = "vault-snapshots"
  })
}

resource "aws_s3_bucket_versioning" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "vault_snapshots" {
  bucket = aws_s3_bucket.vault_snapshots.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# -----------------------------------------------------------------------------
# IAM Role for Vault IRSA (KMS + S3 permissions)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "vault_assume_role" {
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
      values   = ["system:serviceaccount:${var.namespace}:vault"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vault" {
  name               = "VaultIRSA-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.vault_assume_role.json

  tags = merge(var.common_tags, {
    Name                     = "VaultIRSA-${var.cluster_name}"
    "app.kubernetes.io/name" = "vault"
  })
}

data "aws_iam_policy_document" "vault_permissions" {
  # KMS permissions for auto-unseal
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.vault_unseal.arn]
  }

  # S3 permissions for snapshots
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.vault_snapshots.arn,
      "${aws_s3_bucket.vault_snapshots.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "vault" {
  name        = "VaultIRSA-${var.cluster_name}"
  description = "IAM policy for Vault IRSA (KMS auto-unseal + S3 snapshots)"
  policy      = data.aws_iam_policy_document.vault_permissions.json

  tags = merge(var.common_tags, {
    Name                     = "VaultIRSA-${var.cluster_name}"
    "app.kubernetes.io/name" = "vault"
  })
}

resource "aws_iam_role_policy_attachment" "vault" {
  role       = aws_iam_role.vault.name
  policy_arn = aws_iam_policy.vault.arn
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "vault" {
  metadata {
    name = var.namespace

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"       = "vault"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-vault"
      "app.kubernetes.io/managed-by" = "terraform"
    })
  }
}

# -----------------------------------------------------------------------------
# Vault ServiceAccount with IRSA annotation
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "vault" {
  metadata {
    name      = "vault"
    namespace = kubernetes_namespace.vault.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.vault.arn
    }

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "vault"
      "app.kubernetes.io/instance" = "${var.cluster_name}-vault"
    })
  }
}

# -----------------------------------------------------------------------------
# Vault Helm Release (HA with Raft storage)
# -----------------------------------------------------------------------------

resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = var.vault_chart_version
  namespace  = kubernetes_namespace.vault.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name      = var.cluster_name
    namespace         = var.namespace
    replicas          = var.replicas
    kms_key_id        = aws_kms_key.vault_unseal.id
    aws_region        = var.aws_region
    service_account   = kubernetes_service_account.vault.metadata[0].name
    storage_class     = var.storage_class
    pvc_size          = var.pvc_size
    enable_monitoring = var.enable_monitoring
  })]

  depends_on = [
    kubernetes_service_account.vault,
    aws_iam_role_policy_attachment.vault
  ]

  timeout = 600 # 10 minutes
}

# -----------------------------------------------------------------------------
# ConfigMap for Vault initialization script
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "vault_init" {
  metadata {
    name      = "vault-init-script"
    namespace = kubernetes_namespace.vault.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "vault"
      "app.kubernetes.io/instance" = "${var.cluster_name}-vault"
    })
  }

  data = {
    "init.sh" = file("${path.module}/scripts/init.sh")
  }
}
