# -----------------------------------------------------------------------------
# Linkerd mTLS Phase 2 Module - Provider Version Constraints
# Fase 6a: ServerPolicy enforcement for mTLS across namespaces
# GAP-011 Phase 2: BACEN BCB 85/2021 Compliance
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}
