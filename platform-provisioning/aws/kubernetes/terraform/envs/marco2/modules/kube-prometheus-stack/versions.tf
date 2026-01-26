# -----------------------------------------------------------------------------
# Provider Requirements - Kube-Prometheus-Stack Module
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.14"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}
