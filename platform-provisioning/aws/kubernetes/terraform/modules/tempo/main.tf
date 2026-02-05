# -----------------------------------------------------------------------------
# Tempo Module
# Descrição: Provê distributed tracing com Grafana Tempo + S3 backend
# Versão Chart: v1.10.x (tempo-distributed)
# Marco: 2 - Fase 8 (Tracing)
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
  s3_bucket_name    = "k8s-platform-tempo-${local.account_id}"
}

# Obter OIDC provider existente
data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# -----------------------------------------------------------------------------
# S3 Bucket para armazenamento de traces
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "tempo" {
  bucket = local.s3_bucket_name

  # IMPORTANTE: Proteger bucket contra deleção acidental
  # Este bucket contém traces históricos que podem ser necessários para debugging
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [bucket] # Prevenir recreate se o name for recalculado
  }

  tags = merge(
    var.tags,
    {
      Name        = local.s3_bucket_name
      Component   = "tempo"
      Marco       = "marco2"
      Fase        = "8"
      Environment = "production"
      Service     = "tracing"
      ManagedBy   = "terraform"
    }
  )
}

# Encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy (7 days retention default - ADR-020, FinOps requirement)
resource "aws_s3_bucket_lifecycle_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  rule {
    id     = "delete-old-traces-7d"
    status = "Enabled"

    filter {}

    expiration {
      days = var.retention_days
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # Cleanup noncurrent versions (if versioning enabled)
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

# Versioning (disabled by default to save costs - FinOps recommendation)
resource "aws_s3_bucket_versioning" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# -----------------------------------------------------------------------------
# IAM Policy para Tempo S3 Access
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "tempo_s3_policy" {
  statement {
    sid    = "TempoS3Access"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      aws_s3_bucket.tempo.arn,
      "${aws_s3_bucket.tempo.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "tempo_s3" {
  name        = "TempoS3Policy-${var.cluster_name}"
  description = "IAM policy for Tempo to access S3 bucket for trace storage"
  policy      = data.aws_iam_policy_document.tempo_s3_policy.json

  tags = merge(
    var.tags,
    {
      Name      = "TempoS3Policy-${var.cluster_name}"
      Component = "tempo"
      Marco     = "marco2"
      Fase      = "8"
    }
  )
}

# -----------------------------------------------------------------------------
# IAM Role com IRSA (IAM Roles for Service Accounts)
# -----------------------------------------------------------------------------

# Trust policy para Service Account
data "aws_iam_policy_document" "tempo_assume_role_policy" {
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

resource "aws_iam_role" "tempo" {
  name               = "TempoS3Role-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.tempo_assume_role_policy.json

  # AWS Specialist recommendation: Increase session duration from 1h to 12h
  # Reason: Compaction jobs podem demorar > 1h
  max_session_duration = 43200 # 12 hours

  tags = merge(
    var.tags,
    {
      Name      = "TempoS3Role-${var.cluster_name}"
      Component = "tempo"
      Marco     = "marco2"
      Fase      = "8"
    }
  )
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "tempo_s3" {
  role       = aws_iam_role.tempo.name
  policy_arn = aws_iam_policy.tempo_s3.arn
}

# -----------------------------------------------------------------------------
# Kubernetes Service Account
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "tempo" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.tempo.arn
    }

    labels = {
      "app.kubernetes.io/name"       = "tempo"
      "app.kubernetes.io/instance"   = "tempo"
      "app.kubernetes.io/component"  = "tracing"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  # Automount service account token
  automount_service_account_token = true
}

# -----------------------------------------------------------------------------
# Helm Release - Grafana Tempo Distributed
# -----------------------------------------------------------------------------

resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo-distributed"
  version    = var.chart_version
  namespace  = var.namespace

  # Timeout: 15 minutos (múltiplos componentes: distributor, ingester, querier, compactor)
  timeout         = 900
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true

  # Não recriar, apenas update in-place (FinOps: avoid trace loss)
  force_update  = false
  recreate_pods = false

  # -----------------------------------------------------------------------------
  # Global Configuration
  # -----------------------------------------------------------------------------

  set {
    name  = "fullnameOverride"
    value = "tempo"
  }

  # -----------------------------------------------------------------------------
  # Service Account (use existing created by Terraform)
  # -----------------------------------------------------------------------------

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.tempo.metadata[0].name
  }

  # -----------------------------------------------------------------------------
  # Storage Backend - S3
  # -----------------------------------------------------------------------------

  set {
    name  = "storage.trace.backend"
    value = "s3"
  }

  set {
    name  = "storage.trace.s3.bucket"
    value = aws_s3_bucket.tempo.id
  }

  set {
    name  = "storage.trace.s3.endpoint"
    value = "s3.${var.region}.amazonaws.com"
  }

  set {
    name  = "storage.trace.s3.region"
    value = var.region
  }

  # IRSA: Credentials via IAM Role (não hardcoded)
  set {
    name  = "storage.trace.s3.access_key"
    value = ""
  }

  set {
    name  = "storage.trace.s3.secret_key"
    value = ""
  }

  # -----------------------------------------------------------------------------
  # Distributor (receives traces from OTel Collector)
  # -----------------------------------------------------------------------------

  set {
    name  = "distributor.replicas"
    value = var.distributor_replicas
  }

  set {
    name  = "distributor.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "distributor.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "distributor.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "distributor.resources.limits.memory"
    value = "256Mi"
  }

  # Toleration for system nodes (ADR-042 pattern)
  set {
    name  = "distributor.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "distributor.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "distributor.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "distributor.tolerations[0].effect"
    value = "NoSchedule"
  }

  # Toleration for critical nodes (ADR-042 pattern)
  set {
    name  = "distributor.tolerations[1].key"
    value = "workload"
  }

  set {
    name  = "distributor.tolerations[1].operator"
    value = "Equal"
  }

  set {
    name  = "distributor.tolerations[1].value"
    value = "critical"
  }

  set {
    name  = "distributor.tolerations[1].effect"
    value = "NoSchedule"
  }

  # -----------------------------------------------------------------------------
  # Ingester (writes traces to S3)
  # -----------------------------------------------------------------------------

  set {
    name  = "ingester.replicas"
    value = var.ingester_replicas
  }

  # Replication factor MUST match number of replicas (FinOps: 2 vs 3 default)
  set {
    name  = "ingester.lifecycler.ring.replication_factor"
    value = var.ingester_replicas
  }

  set {
    name  = "ingester.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "ingester.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "ingester.resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "ingester.resources.limits.memory"
    value = "512Mi"
  }

  # PVC for Write-Ahead Log (FinOps: 10Gi vs 20Gi original)
  set {
    name  = "ingester.persistence.enabled"
    value = "true"
  }

  set {
    name  = "ingester.persistence.size"
    value = var.ingester_pvc_size
  }

  set {
    name  = "ingester.persistence.storageClass"
    value = var.storage_class
  }

  # Toleration for system nodes (ADR-042 pattern)
  set {
    name  = "ingester.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "ingester.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "ingester.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "ingester.tolerations[0].effect"
    value = "NoSchedule"
  }

  # Toleration for critical nodes (ADR-042 pattern)
  set {
    name  = "ingester.tolerations[1].key"
    value = "workload"
  }

  set {
    name  = "ingester.tolerations[1].operator"
    value = "Equal"
  }

  set {
    name  = "ingester.tolerations[1].value"
    value = "critical"
  }

  set {
    name  = "ingester.tolerations[1].effect"
    value = "NoSchedule"
  }

  # Liveness/Readiness Probes (stateful component needs more time)
  set {
    name  = "ingester.livenessProbe.initialDelaySeconds"
    value = "60"
  }

  set {
    name  = "ingester.livenessProbe.periodSeconds"
    value = "30"
  }

  set {
    name  = "ingester.livenessProbe.timeoutSeconds"
    value = "10"
  }

  set {
    name  = "ingester.livenessProbe.failureThreshold"
    value = "5"
  }

  set {
    name  = "ingester.readinessProbe.initialDelaySeconds"
    value = "30"
  }

  set {
    name  = "ingester.readinessProbe.periodSeconds"
    value = "10"
  }

  set {
    name  = "ingester.readinessProbe.timeoutSeconds"
    value = "5"
  }

  set {
    name  = "ingester.readinessProbe.failureThreshold"
    value = "3"
  }

  # -----------------------------------------------------------------------------
  # Querier (reads traces from S3)
  # -----------------------------------------------------------------------------

  set {
    name  = "querier.replicas"
    value = var.querier_replicas
  }

  set {
    name  = "querier.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "querier.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "querier.resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "querier.resources.limits.memory"
    value = "512Mi"
  }

  set {
  # Toleration for system nodes (ADR-042 pattern)
  set {
    name  = "querier.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "querier.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "querier.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "querier.tolerations[0].effect"
    value = "NoSchedule"
  }

  # Toleration for critical nodes (ADR-042 pattern)
  set {
    name  = "querier.tolerations[1].key"
    value = "workload"
  }

  set {
    name  = "querier.tolerations[1].operator"
    value = "Equal"
  }

  set {
    name  = "querier.tolerations[1].value"
    value = "critical"
  }

  set {
    name  = "querier.tolerations[1].effect"
    value = "NoSchedule"
  }

  # Liveness/Readiness Probes (needs time to connect to S3)
  set {
    name  = "querier.livenessProbe.initialDelaySeconds"
    value = "45"
  }

  set {
    name  = "querier.livenessProbe.periodSeconds"
    value = "20"
  }

  set {
    name  = "querier.livenessProbe.timeoutSeconds"
    value = "5"
  }

  set {
    name  = "querier.livenessProbe.failureThreshold"
    value = "5"
  }

  set {
    name  = "querier.readinessProbe.initialDelaySeconds"
    value = "20"
  }

  set {
    name  = "querier.readinessProbe.periodSeconds"
    value = "10"
  }

  set {
    name  = "querier.readinessProbe.timeoutSeconds"
    value = "5"
  }

  set {
    name  = "querier.readinessProbe.failureThreshold"
    value = "3"
  }

  # -----------------------------------------------------------------------------
  # Query Frontend (Grafana datasource endpoint)
  # -----------------------------------------------------------------------------

  set {
    name  = "queryFrontend.replicas"
    value = "2"
  }

  set {
    name  = "queryFrontend.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "queryFrontend.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "queryFrontend.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "queryFrontend.resources.limits.memory"
    value = "256Mi"
  }

  set {
  # Toleration for system nodes (ADR-042 pattern)
  set {
    name  = "queryFrontend.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "queryFrontend.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "queryFrontend.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "queryFrontend.tolerations[0].effect"
    value = "NoSchedule"
  }

  # Toleration for critical nodes (ADR-042 pattern)
  set {
    name  = "queryFrontend.tolerations[1].key"
    value = "workload"
  }

  set {
    name  = "queryFrontend.tolerations[1].operator"
    value = "Equal"
  }

  set {
    name  = "queryFrontend.tolerations[1].value"
    value = "critical"
  }

  set {
    name  = "queryFrontend.tolerations[1].effect"
    value = "NoSchedule"
  }

  # -----------------------------------------------------------------------------
  # Compactor (consolidates traces in S3)
  # -----------------------------------------------------------------------------

  set {
    name  = "compactor.replicas"
    value = var.compactor_replicas
  }

  set {
    name  = "compactor.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "compactor.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "compactor.resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "compactor.resources.limits.memory"
    value = "512Mi"
  }

  # PVC for compaction cache (FinOps: 10Gi vs 20Gi original)
  set {
    name  = "compactor.persistence.enabled"
    value = "true"
  }

  set {
    name  = "compactor.persistence.size"
    value = var.compactor_pvc_size
  }

  set {
    name  = "compactor.persistence.storageClass"
    value = var.storage_class
  }

  set {
  # Toleration for system nodes (ADR-042 pattern)
  set {
    name  = "compactor.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "compactor.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "compactor.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "compactor.tolerations[0].effect"
    value = "NoSchedule"
  }

  # Toleration for critical nodes (ADR-042 pattern)
  set {
    name  = "compactor.tolerations[1].key"
    value = "workload"
  }

  set {
    name  = "compactor.tolerations[1].operator"
    value = "Equal"
  }

  set {
    name  = "compactor.tolerations[1].value"
    value = "critical"
  }

  set {
    name  = "compactor.tolerations[1].effect"
    value = "NoSchedule"
  }

  # Liveness/Readiness Probes (stateful component needs more time)
  set {
    name  = "compactor.livenessProbe.initialDelaySeconds"
    value = "60"
  }

  set {
    name  = "compactor.livenessProbe.periodSeconds"
    value = "30"
  }

  set {
    name  = "compactor.livenessProbe.timeoutSeconds"
    value = "10"
  }

  set {
    name  = "compactor.livenessProbe.failureThreshold"
    value = "5"
  }

  set {
    name  = "compactor.readinessProbe.initialDelaySeconds"
    value = "30"
  }

  set {
    name  = "compactor.readinessProbe.periodSeconds"
    value = "10"
  }

  set {
    name  = "compactor.readinessProbe.timeoutSeconds"
    value = "5"
  }

  set {
    name  = "compactor.readinessProbe.failureThreshold"
    value = "3"
  }

  # -----------------------------------------------------------------------------
  # Monitoring - ServiceMonitor para Prometheus
  # -----------------------------------------------------------------------------

  set {
    name  = "metaMonitoring.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "metaMonitoring.serviceMonitor.namespace"
    value = var.namespace
  }

  # CRITICAL: Label deve match Prometheus ServiceMonitor selector
  set {
    name  = "metaMonitoring.serviceMonitor.labels.release"
    value = "kube-prometheus-stack"
  }

  set {
    name  = "metaMonitoring.serviceMonitor.interval"
    value = "30s"
  }

  # -----------------------------------------------------------------------------
  # Gateway (optional, provides single entry point)
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
  # Toleration for system nodes (ADR-042 pattern)
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

  # Toleration for critical nodes (ADR-042 pattern)
  set {
    name  = "gateway.tolerations[1].key"
    value = "workload"
  }

  set {
    name  = "gateway.tolerations[1].operator"
    value = "Equal"
  }

  set {
    name  = "gateway.tolerations[1].value"
    value = "critical"
  }

  set {
    name  = "gateway.tolerations[1].effect"
    value = "NoSchedule"
  }

  # -----------------------------------------------------------------------------
  # Dependencies
  # -----------------------------------------------------------------------------

  depends_on = [
    aws_s3_bucket.tempo,
    aws_iam_role_policy_attachment.tempo_s3,
    kubernetes_service_account.tempo
  ]
}

# -----------------------------------------------------------------------------
# Network Policies (Calico)
# -----------------------------------------------------------------------------

# Policy 1: Allow Apps → OTel Collector (ingress traces)
resource "kubernetes_network_policy" "allow_otel_collector_ingress" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-otel-collector-ingress"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "tempo"
      "app.kubernetes.io/component"  = "network-policy"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "opentelemetry-collector"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      # Allow from all namespaces (apps send traces)
      from {
        namespace_selector {}
      }

      ports {
        protocol = "TCP"
        port     = "4317" # OTLP gRPC
      }

      ports {
        protocol = "TCP"
        port     = "4318" # OTLP HTTP
      }
    }
  }
}

# Policy 2: Allow OTel Collector → Tempo Distributor
resource "kubernetes_network_policy" "allow_otel_to_tempo" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-otel-to-tempo"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "tempo"
      "app.kubernetes.io/component"  = "network-policy"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name"      = "tempo"
        "app.kubernetes.io/component" = "distributor"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "opentelemetry-collector"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "3100" # Tempo HTTP endpoint
      }

      ports {
        protocol = "TCP"
        port     = "4317" # OTLP gRPC
      }
    }
  }
}

# Policy 3: Allow Grafana → Tempo Query Frontend
resource "kubernetes_network_policy" "allow_grafana_to_tempo" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-grafana-to-tempo"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "tempo"
      "app.kubernetes.io/component"  = "network-policy"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name"      = "tempo"
        "app.kubernetes.io/component" = "query-frontend"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "grafana"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "3100" # Tempo query endpoint
      }
    }
  }
}

# Policy 4: Allow Tempo → S3 Egress (HTTPS)
resource "kubernetes_network_policy" "allow_tempo_to_s3" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-tempo-to-s3"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "tempo"
      "app.kubernetes.io/component"  = "network-policy"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "tempo"
      }
    }

    policy_types = ["Egress"]

    # Allow egress to S3 (HTTPS)
    egress {
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    # Allow DNS queries
    egress {
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    # Allow egress to kube-system (CoreDNS)
    egress {
      to {
        namespace_selector {
          match_labels = {
            "name" = "kube-system"
          }
        }
      }
    }
  }
}
