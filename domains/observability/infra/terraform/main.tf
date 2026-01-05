# Observability Domain - Cloud-Agnostic Terraform
# 
# Este módulo ASSUME que o cluster Kubernetes já existe (provisionado por /platform-provisioning/)
# e CONSOME outputs como variables.
#
# Conformidade: ADR-003 (Cloud-Agnostic), ADR-020 (Provisionamento de Clusters)

terraform {
  required_version = ">= 1.5"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Backend configuration (uncomment when ready for remote state)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "domains/observability/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# Kubernetes Provider
# Configurado para usar cluster existente (via kubeconfig ou outputs do platform-provisioning)
provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  
  # Autenticação via AWS EKS (se usar AWS)
  # exec {
  #   api_version = "client.authentication.k8s.io/v1beta1"
  #   command     = "aws"
  #   args = [
  #     "eks",
  #     "get-token",
  #     "--cluster-name",
  #     var.cluster_name
  #   ]
  # }
}

# Helm Provider
provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  }
}

# =============================================================================
# NAMESPACES
# =============================================================================

resource "kubernetes_namespace" "observability" {
  for_each = toset(var.environments)

  metadata {
    name = "observability-${each.key}"
    
    labels = {
      name        = "observability-${each.key}"
      environment = each.key
      domain      = "observability"
      managed-by  = "terraform"
    }
  }
}

# =============================================================================
# HELM RELEASES
# =============================================================================

# Kube-Prometheus-Stack (Prometheus + Alertmanager + Grafana)
resource "helm_release" "kube_prometheus_stack" {
  for_each = toset(var.environments)

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "54.0.0"
  namespace  = kubernetes_namespace.observability[each.key].metadata[0].name

  values = [
    templatefile("${path.module}/../helm/kube-prometheus-stack/values.yaml", {
      environment        = each.key
      storage_class_name = var.storage_class_name
      s3_bucket_metrics  = var.s3_bucket_metrics
      s3_endpoint        = var.object_storage_endpoint
    })
  ]

  depends_on = [kubernetes_namespace.observability]
}

# Loki (Logs aggregation)
resource "helm_release" "loki" {
  for_each = toset(var.environments)

  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "5.41.0"
  namespace  = kubernetes_namespace.observability[each.key].metadata[0].name

  values = [
    templatefile("${path.module}/../helm/loki/values.yaml", {
      environment        = each.key
      storage_class_name = var.storage_class_name
      s3_bucket_logs     = var.s3_bucket_logs
      s3_endpoint        = var.object_storage_endpoint
    })
  ]

  depends_on = [kubernetes_namespace.observability]
}

# Tempo (Traces)
resource "helm_release" "tempo" {
  for_each = toset(var.environments)

  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.7.0"
  namespace  = kubernetes_namespace.observability[each.key].metadata[0].name

  values = [
    templatefile("${path.module}/../helm/tempo/values.yaml", {
      environment        = each.key
      storage_class_name = var.storage_class_name
      s3_bucket_traces   = var.s3_bucket_traces
      s3_endpoint        = var.object_storage_endpoint
    })
  ]

  depends_on = [kubernetes_namespace.observability]
}

# OpenTelemetry Collector
resource "helm_release" "otel_collector" {
  for_each = toset(var.environments)

  name       = "opentelemetry-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = "0.71.0"
  namespace  = kubernetes_namespace.observability[each.key].metadata[0].name

  values = [
    templatefile("${path.module}/../helm/opentelemetry-collector/values.yaml", {
      environment = each.key
    })
  ]

  depends_on = [
    kubernetes_namespace.observability,
    helm_release.kube_prometheus_stack,
    helm_release.loki,
    helm_release.tempo
  ]
}
