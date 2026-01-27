# -----------------------------------------------------------------------------
# Loki Module
# Descrição: Provê logging centralizado com Loki + S3 backend
# Versão Chart: v5.42.0
# Marco: 2 - Fase 4 (Logging)
# -----------------------------------------------------------------------------

# Obter informações do cluster EKS
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

data "aws_caller_identity" "current" {}

# Extrair OIDC provider URL do cluster
locals {
  oidc_provider_url = replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")
  account_id        = data.aws_caller_identity.current.account_id
  s3_bucket_name    = "k8s-platform-loki-${local.account_id}"
}

# Obter OIDC provider existente
data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# -----------------------------------------------------------------------------
# S3 Bucket para armazenamento de logs
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "loki" {
  bucket = local.s3_bucket_name

  # IMPORTANTE: Proteger bucket contra deleção acidental
  # Este bucket contém logs históricos que não devem ser perdidos
  lifecycle {
    prevent_destroy = true
    ignore_changes = [bucket]  # Prevenir recreate se o name for recalculado
  }

  tags = merge(
    var.tags,
    {
      Name        = local.s3_bucket_name
      Component   = "loki"
      Marco       = "marco2"
      Environment = "production"
      Service     = "logging"
      ManagedBy   = "terraform"
    }
  )
}

# Encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy (30 days retention)
resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Versioning (optional, disabled by default to save costs)
resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# -----------------------------------------------------------------------------
# IAM Policy para Loki S3 Access
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "loki_s3_policy" {
  statement {
    sid    = "LokiS3Access"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      aws_s3_bucket.loki.arn,
      "${aws_s3_bucket.loki.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "loki_s3" {
  name        = "LokiS3Policy-${var.cluster_name}"
  description = "IAM policy for Loki to access S3 bucket for log storage"
  policy      = data.aws_iam_policy_document.loki_s3_policy.json

  tags = merge(
    var.tags,
    {
      Name      = "LokiS3Policy-${var.cluster_name}"
      Component = "loki"
      Marco     = "marco2"
    }
  )
}

# -----------------------------------------------------------------------------
# IAM Role com IRSA (IAM Roles for Service Accounts)
# -----------------------------------------------------------------------------

# Trust policy para Service Account
data "aws_iam_policy_document" "loki_assume_role" {
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

resource "aws_iam_role" "loki" {
  name               = "LokiS3Role-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.loki_assume_role.json

  tags = merge(
    var.tags,
    {
      Name      = "LokiS3Role-${var.cluster_name}"
      Component = "loki"
      Marco     = "marco2"
    }
  )
}

# Attach S3 policy to role
resource "aws_iam_role_policy_attachment" "loki_s3" {
  role       = aws_iam_role.loki.name
  policy_arn = aws_iam_policy.loki_s3.arn
}

# -----------------------------------------------------------------------------
# Kubernetes Service Account
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "loki" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.loki.arn
    }

    labels = {
      "app.kubernetes.io/name"       = "loki"
      "app.kubernetes.io/component"  = "logging"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Helm Release - Loki
# -----------------------------------------------------------------------------

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.chart_version
  namespace  = var.namespace

  # -----------------------------------------------------------------------------
  # Deployment Mode: SimpleScalable
  # -----------------------------------------------------------------------------
  set {
    name  = "deploymentMode"
    value = "SimpleScalable"
  }

  # -----------------------------------------------------------------------------
  # Loki Configuration
  # -----------------------------------------------------------------------------
  set {
    name  = "loki.auth_enabled"
    value = "false"
  }

  set {
    name  = "loki.commonConfig.replication_factor"
    value = var.replication_factor
  }

  set {
    name  = "loki.commonConfig.path_prefix"
    value = "/var/loki"
  }

  # Storage configuration (S3)
  set {
    name  = "loki.storage.type"
    value = "s3"
  }

  set {
    name  = "loki.storage.bucketNames.chunks"
    value = local.s3_bucket_name
  }

  set {
    name  = "loki.storage.bucketNames.ruler"
    value = local.s3_bucket_name
  }

  set {
    name  = "loki.storage.bucketNames.admin"
    value = local.s3_bucket_name
  }

  set {
    name  = "loki.storage.s3.region"
    value = var.region
  }

  # Schema configuration
  set {
    name  = "loki.schemaConfig.configs[0].from"
    value = "2024-01-01"
  }

  set {
    name  = "loki.schemaConfig.configs[0].store"
    value = "tsdb"
  }

  set {
    name  = "loki.schemaConfig.configs[0].object_store"
    value = "s3"
  }

  set {
    name  = "loki.schemaConfig.configs[0].schema"
    value = "v13"
  }

  set {
    name  = "loki.schemaConfig.configs[0].index.prefix"
    value = "loki_index_"
  }

  set {
    name  = "loki.schemaConfig.configs[0].index.period"
    value = "24h"
  }

  # Retention configuration
  set {
    name  = "loki.limits_config.retention_period"
    value = "${var.retention_days * 24}h"
  }

  set {
    name  = "loki.limits_config.max_query_length"
    value = "${(var.retention_days + 1) * 24}h"
  }

  # Compactor configuration
  set {
    name  = "loki.compactor.working_directory"
    value = "/var/loki/compactor"
  }

  set {
    name  = "loki.compactor.shared_store"
    value = "s3"
  }

  set {
    name  = "loki.compactor.compaction_interval"
    value = "10m"
  }

  set {
    name  = "loki.compactor.retention_enabled"
    value = "true"
  }

  set {
    name  = "loki.compactor.retention_delete_delay"
    value = "2h"
  }

  # -----------------------------------------------------------------------------
  # Read Component (Query Path)
  # -----------------------------------------------------------------------------
  set {
    name  = "read.replicas"
    value = var.read_replicas
  }

  set {
    name  = "read.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "read.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "read.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "read.resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "read.nodeSelector.node-type"
    value = "system"
  }

  set {
    name  = "read.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "read.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "read.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "read.tolerations[0].effect"
    value = "NoSchedule"
  }

  # -----------------------------------------------------------------------------
  # Write Component (Ingestion Path)
  # -----------------------------------------------------------------------------
  set {
    name  = "write.replicas"
    value = var.write_replicas
  }

  set {
    name  = "write.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "write.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "write.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "write.resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "write.persistence.enabled"
    value = "true"
  }

  set {
    name  = "write.persistence.storageClass"
    value = var.storage_class
  }

  set {
    name  = "write.persistence.size"
    value = var.write_pvc_size
  }

  set {
    name  = "write.nodeSelector.node-type"
    value = "system"
  }

  set {
    name  = "write.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "write.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "write.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "write.tolerations[0].effect"
    value = "NoSchedule"
  }

  # -----------------------------------------------------------------------------
  # Backend Component (Compaction, etc.)
  # -----------------------------------------------------------------------------
  set {
    name  = "backend.replicas"
    value = var.backend_replicas
  }

  set {
    name  = "backend.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "backend.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "backend.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "backend.resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "backend.persistence.enabled"
    value = "true"
  }

  set {
    name  = "backend.persistence.storageClass"
    value = var.storage_class
  }

  set {
    name  = "backend.persistence.size"
    value = var.backend_pvc_size
  }

  set {
    name  = "backend.nodeSelector.node-type"
    value = "system"
  }

  set {
    name  = "backend.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "backend.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "backend.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "backend.tolerations[0].effect"
    value = "NoSchedule"
  }

  # -----------------------------------------------------------------------------
  # Gateway Component (Nginx reverse proxy)
  # -----------------------------------------------------------------------------
  set {
    name  = "gateway.enabled"
    value = "true"
  }

  set {
    name  = "gateway.replicas"
    value = "2"
  }

  set {
    name  = "gateway.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "gateway.resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "gateway.resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "gateway.resources.limits.memory"
    value = "128Mi"
  }

  set {
    name  = "gateway.nodeSelector.node-type"
    value = "system"
  }

  set {
    name  = "gateway.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "gateway.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "gateway.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "gateway.tolerations[0].effect"
    value = "NoSchedule"
  }

  # -----------------------------------------------------------------------------
  # Minio (Disable - using AWS S3)
  # -----------------------------------------------------------------------------
  set {
    name  = "minio.enabled"
    value = "false"
  }

  # -----------------------------------------------------------------------------
  # Service Account (IRSA)
  # -----------------------------------------------------------------------------
  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.loki.metadata[0].name
  }

  # -----------------------------------------------------------------------------
  # Monitoring
  # -----------------------------------------------------------------------------
  set {
    name  = "monitoring.selfMonitoring.enabled"
    value = "false"
  }

  set {
    name  = "monitoring.selfMonitoring.grafanaAgent.installOperator"
    value = "false"
  }

  set {
    name  = "monitoring.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "monitoring.serviceMonitor.namespace"
    value = var.namespace
  }

  # -----------------------------------------------------------------------------
  # Test Configuration (Disable tests to avoid self-monitoring requirement)
  # -----------------------------------------------------------------------------
  set {
    name  = "test.enabled"
    value = "false"
  }

  depends_on = [
    kubernetes_service_account.loki,
    aws_iam_role_policy_attachment.loki_s3,
    aws_s3_bucket.loki,
    aws_s3_bucket_lifecycle_configuration.loki
  ]
}
