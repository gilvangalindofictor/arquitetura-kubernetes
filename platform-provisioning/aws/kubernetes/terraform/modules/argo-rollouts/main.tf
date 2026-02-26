# -----------------------------------------------------------------------------
# Argo Rollouts Module
# Progressive Delivery: Canary and Blue-Green strategies
# Demand: CICD-005
# ADR: ADR-085
# Chart: argoproj/argo-rollouts v2.35.0
# Namespace: argocd (co-located with ArgoCD per ADR-085)
# -----------------------------------------------------------------------------

terraform {
  required_providers {
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
# Argo Rollouts Helm Release
# Deployed in argocd namespace — namespace already exists (created by argocd module)
# create_namespace = false per project pattern (namespace pre-exists)
# -----------------------------------------------------------------------------

resource "helm_release" "argo_rollouts" {
  name       = "argo-rollouts"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = false # Namespace managed by argocd module

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name       = var.cluster_name
    controller_replicas = var.controller_replicas
    metrics_enabled    = var.metrics_enabled
    prometheus_url     = var.prometheus_url
    dashboard_enabled  = var.dashboard_enabled
    dashboard_port     = var.dashboard_port
    metrics_port       = var.metrics_port
  })]

  timeout = 300 # 5 minutes
}

# -----------------------------------------------------------------------------
# AnalysisTemplates — Library of reusable analysis templates
# Applied via kubectl_manifest after Helm release (CRDs available)
# Location: same namespace as Rollouts, but templates are namespace-scoped
# Application teams reference these via their Rollout spec
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "analysis_templates" {
  metadata {
    name      = "argo-rollouts-analysis-templates-index"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "argo-rollouts"
      "app.kubernetes.io/component"  = "analysis-templates"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "progressive-delivery"
      "demand"                       = "CICD-005"
    }
    annotations = {
      "description" = "Index of AnalysisTemplate library. Templates deployed per-namespace via kubectl apply."
    }
  }

  data = {
    "templates-path"   = "domains/apps/manifests/analysis-templates/"
    "templates-count"  = "4"
    "templates-list"   = "success-rate.yaml, latency-p95.yaml, error-rate-4xx.yaml, error-rate-5xx.yaml"
    "deploy-command"   = "kubectl apply -f domains/apps/manifests/analysis-templates/ -n <APP_NAMESPACE>"
    "prometheus-url"   = var.prometheus_url
  }

  depends_on = [helm_release.argo_rollouts]
}

# -----------------------------------------------------------------------------
# ServiceMonitor — Prometheus scraping for Argo Rollouts metrics
# Requires: kube-prometheus-stack installed (monitoring namespace)
# Metrics exposed: argo_rollout_*, argo_analysis_*
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "service_monitor" {
  count = var.metrics_enabled ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "argo-rollouts-metrics"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/name"       = "argo-rollouts"
        "app.kubernetes.io/component"  = "metrics"
        "app.kubernetes.io/managed-by" = "terraform"
        "release"                      = "kube-prometheus-stack"
        "demand"                       = "CICD-005"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"      = "argo-rollouts-metrics"
          "app.kubernetes.io/component" = "server"
        }
      }
      namespaceSelector = {
        matchNames = [var.namespace]
      }
      endpoints = [
        {
          port     = "metrics"
          interval = "30s"
          path     = "/metrics"
        }
      ]
    }
  }

  depends_on = [helm_release.argo_rollouts]
}
