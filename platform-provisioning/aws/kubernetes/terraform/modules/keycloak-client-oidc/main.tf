# =============================================================================
# Reusable OIDC Client Module — Main
# Module: keycloak-client-oidc
# Purpose: Standardised wrapper for creating OIDC clients in the platform realm
#
# This module enforces platform conventions:
#   - Standard flow only (no implicit, no direct grants by default)
#   - CONFIDENTIAL access type (client secret required)
#   - PKCE configurable per client (default: enabled, S256)
#   - prevent_destroy = true on all clients (safety)
#   - client_secret NOT managed here (use ESO → Vault KV pattern)
#
# client_secret management:
#   After import/creation, read the secret via:
#     kcadm.sh get clients/{UUID}/client-secret -r platform
#   Store it in Vault KV: secret/{client_id}/oidc
#   ESO ExternalSecret syncs it to K8s secret in the app namespace.
#   Never store client_secret in TF state or git.
#
# ADR: TASK-002
# =============================================================================

locals {
  # Resolve root_url: use explicit var or fall back to first web_origin
  resolved_root_url = var.root_url != "" ? var.root_url : (
    length(var.web_origins) > 0 ? var.web_origins[0] : ""
  )

  # Resolve base_url: use explicit var or fall back to root_url
  resolved_base_url = var.base_url != "" ? var.base_url : local.resolved_root_url
}

resource "keycloak_openid_client" "this" {
  realm_id    = var.realm_id
  client_id   = var.client_id
  name        = var.client_name
  description = var.description

  enabled = true

  # Authorization Code Flow: the standard browser-based SSO pattern
  standard_flow_enabled        = var.standard_flow_enabled
  implicit_flow_enabled        = false
  direct_access_grants_enabled = var.direct_access_grants_enabled
  service_accounts_enabled     = var.service_accounts_enabled

  # CONFIDENTIAL: server-side apps with a client secret
  access_type = "CONFIDENTIAL"

  valid_redirect_uris = var.redirect_uris
  web_origins         = var.web_origins

  # PKCE: S256 when enabled, empty string to disable
  # S256 is the only secure method; "plain" must never be used
  pkce_code_challenge_method = var.enable_pkce ? "S256" : ""

  # Backchannel logout (optional)
  backchannel_logout_url                     = var.backchannel_logout_url != "" ? var.backchannel_logout_url : null
  backchannel_logout_session_required        = var.backchannel_logout_url != "" ? var.backchannel_logout_session_required : false
  backchannel_logout_revoke_offline_sessions = false

  root_url = local.resolved_root_url
  base_url = local.resolved_base_url

  lifecycle {
    # Safety: never destroy — accidental destroy breaks SSO for all users
    prevent_destroy = true

    # client_secret is not a field on keycloak_openid_client.
    # Secrets are read via kcadm.sh and stored in Vault KV → ESO.
    ignore_changes = []
  }
}
