# =============================================================================
# Keycloak Clients Module — Provider Requirements
# Provider: mrparkers/keycloak ~> 4.4.0
# Keycloak version: 26.5.1 (codecentric/keycloakx 7.1.7)
# Pattern: import-only mode (prevent_destroy = true on all clients)
# WSL-safe: provider URL uses localhost + port-forward (see provider.tf)
# ADR: TASK-002 (docs/tasks/TASK-002-terraform-keycloak-provider.md)
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    keycloak = {
      source  = "mrparkers/keycloak"
      version = "~> 4.4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
