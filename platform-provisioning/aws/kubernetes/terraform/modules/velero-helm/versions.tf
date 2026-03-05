# =============================================================================
# Velero Helm Release Module — Provider Requirements
# Manages ONLY the helm_release resource for Velero.
# IAM/IRSA and S3 are managed by the velero-dr module.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}
