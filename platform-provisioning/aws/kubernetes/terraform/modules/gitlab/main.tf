# =============================================================================
# GitLab Module - Marco 3 Fase 2
# Helm Chart: gitlab/gitlab 8.7.0 (GitLab CE)
# IRSA: IAM Role for S3 access (artifacts + uploads)
# ADR-021: No-Domain Phase 1 Strategy (HTTP-only ALB)
# =============================================================================

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "gitlab" {
  metadata {
    name = var.namespace

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"             = "gitlab"
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
      "kubernetes.io/metadata.name"        = var.namespace
    })
  }
}

# -----------------------------------------------------------------------------
# GitLab Root Password
# -----------------------------------------------------------------------------

resource "random_password" "gitlab_root" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "kubernetes_secret" "gitlab_root_password" {
  metadata {
    name      = "gitlab-root-password"
    namespace = kubernetes_namespace.gitlab.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "gitlab"
      "app.kubernetes.io/instance" = "${var.cluster_name}-gitlab"
    })
  }

  data = {
    password = random_password.gitlab_root.result
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# GitLab Object Storage Connection Secret (IRSA)
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "gitlab_object_storage" {
  metadata {
    name      = "gitlab-object-storage"
    namespace = kubernetes_namespace.gitlab.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "gitlab"
      "app.kubernetes.io/instance" = "${var.cluster_name}-gitlab"
    })
  }

  data = {
    connection = yamlencode({
      provider        = "AWS"
      use_iam_profile = true
      region          = var.aws_region
    })
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# IRSA: IAM Role for GitLab ServiceAccount
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "gitlab_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/id/${replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:gitlab"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

resource "aws_iam_role" "gitlab_sa" {
  name               = "${var.cluster_name}-gitlab-sa-role"
  assume_role_policy = data.aws_iam_policy_document.gitlab_assume_role.json

  tags = merge(var.common_tags, {
    Name           = "${var.cluster_name}-gitlab-sa-role"
    ServiceAccount = "gitlab"
    Namespace      = var.namespace
  })
}

# Attach S3 policy (created by s3-buckets module)
resource "aws_iam_role_policy_attachment" "gitlab_s3" {
  role       = aws_iam_role.gitlab_sa.name
  policy_arn = var.s3_policy_arn
}

# -----------------------------------------------------------------------------
# Kubernetes ServiceAccount with IRSA annotation
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "gitlab" {
  metadata {
    name      = "gitlab"
    namespace = kubernetes_namespace.gitlab.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"       = "gitlab"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-gitlab"
      "app.kubernetes.io/managed-by" = "terraform"
    })

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.gitlab_sa.arn
    }
  }

  automount_service_account_token = true
}

# -----------------------------------------------------------------------------
# GitLab Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "gitlab" {
  name       = "gitlab"
  namespace  = kubernetes_namespace.gitlab.metadata[0].name
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  version    = var.gitlab_version

  timeout         = 1200 # 20 minutes for GitLab deployment
  cleanup_on_fail = true
  atomic          = false # GitLab deployment is complex, allow manual intervention
  wait            = true
  wait_for_jobs   = true

  depends_on = [
    kubernetes_service_account.gitlab,
    kubernetes_secret.gitlab_root_password,
    kubernetes_secret.gitlab_object_storage
  ]

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      # General
      edition         = var.gitlab_edition
      replicas        = var.gitlab_replicas
      runner_replicas = var.gitlab_runner_replicas

      # ServiceAccount (IRSA)
      service_account_name = kubernetes_service_account.gitlab.metadata[0].name

      # PostgreSQL (external)
      postgresql_host            = var.postgresql_host
      postgresql_port            = var.postgresql_port
      postgresql_database        = var.postgresql_database
      postgresql_username        = var.postgresql_username
      postgresql_password_secret = var.postgresql_password_secret

      # Redis (external)
      redis_host            = var.redis_host
      redis_port            = var.redis_port
      redis_password_secret = var.redis_password_secret

      # S3 (IRSA)
      s3_region           = var.aws_region
      s3_artifacts_bucket = var.s3_artifacts_bucket
      s3_uploads_bucket   = var.s3_uploads_bucket

      # TLS (ADR-021 Fase 1: disabled)
      enable_tls  = var.enable_tls
      domain_name = var.domain_name

      # Root password
      root_password_secret = kubernetes_secret.gitlab_root_password.metadata[0].name

      # Monitoring
      enable_monitoring = var.enable_monitoring

      # Authentication (OIDC)
      enable_oidc        = var.enable_oidc
      
      # ALB Ingress Group (consolidation)
      ingress_group_name = var.ingress_group_name
    })
  ]
}

# -----------------------------------------------------------------------------
# ServiceMonitor for Prometheus (if enabled)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "gitlab_service_monitor" {
  count = var.enable_monitoring ? 1 : 0

  depends_on = [helm_release.gitlab]

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"

    metadata = {
      name      = "gitlab"
      namespace = "monitoring"

      labels = {
        prometheus = "kube-prometheus-stack"
        app        = "gitlab"
      }
    }

    spec = {
      selector = {
        matchLabels = {
          "app" = "gitlab"
        }
      }

      namespaceSelector = {
        matchNames = [kubernetes_namespace.gitlab.metadata[0].name]
      }

      endpoints = [
        {
          port     = "metrics"
          interval = "30s"
          path     = "/-/metrics"
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}
