# =============================================================================
# Reusable OIDC Client Module — Provider Requirements
# Module: keycloak-client-oidc
# Purpose: Standardised wrapper for creating new OIDC clients in Keycloak
#
# Usage:
#   module "myapp_oidc" {
#     source = "../../modules/keycloak-client-oidc"
#
#     realm_id      = module.keycloak_clients_staging.realm_id
#     client_id     = "myapp"
#     client_name   = "My Application OIDC"
#     redirect_uris = ["http://myapp.staging.internal/callback"]
#     web_origins   = ["http://myapp.staging.internal"]
#     enable_pkce   = true  # check app PKCE support first
#   }
#
# PKCE decision matrix:
#   enable_pkce = true   → gitlab, grafana, harbor, vault (and any new browser-based app)
#   enable_pkce = false  → argocd (upgrade pending TASK-001), legacy apps
#   N/A (SAML)          → sonarqube (use keycloak_saml_client directly)
#
# Provider: mrparkers/keycloak ~> 4.4.0
# Keycloak: 26.5.1 (codecentric/keycloakx 7.1.7)
# ADR: TASK-002
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    keycloak = {
      source  = "mrparkers/keycloak"
      version = "~> 4.4.0"
    }
  }
}
