# -----------------------------------------------------------------------------
# VPA (Vertical Pod Autoscaler) Module
# Fairwinds VPA Helm chart - Recommendation mode for rightsizing
# FinOps P1.5: Enables R$ 8.712/ano savings via 30d metrics collection
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# -----------------------------------------------------------------------------
# VPA Helm Release
# Chart: fairwinds/vpa v4.4.6
# Components: recommender (enabled), updater (disabled), admissionController (disabled)
# -----------------------------------------------------------------------------

resource "helm_release" "vpa" {
  name       = var.release_name
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  version    = var.chart_version
  namespace  = var.namespace
  timeout    = 300

  values = [templatefile("${path.module}/values.yaml.tpl", {
    recommender_enabled          = var.recommender_enabled
    updater_enabled              = var.updater_enabled
    admission_controller_enabled = var.admission_controller_enabled
    prometheus_address           = var.prometheus_address
  })]
}
