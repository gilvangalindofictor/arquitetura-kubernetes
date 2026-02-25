# =============================================================================
# Keycloak OIDC Client: Harbor
# Realm: platform | Client ID: harbor
# Access type: CONFIDENTIAL | Standard Flow: enabled
# PKCE: S256 (Harbor 2.x supports PKCE via OpenID Connect)
#
# Import:
#   terraform import 'keycloak_openid_client.harbor' "platform/{UUID}"
#   UUID from: kubectl exec -n keycloak <pod> -- /opt/keycloak/bin/kcadm.sh \
#     get clients -r platform --fields id,clientId | jq '.[] | select(.clientId=="harbor") | .id'
#
# ESO Integration:
#   Vault KV: secret/harbor/oidc → ESO ExternalSecret: harbor-oidc-credentials
#   Namespace: harbor-system
#
# Harbor OIDC Config (set via Harbor UI/API, NOT via TF):
#   - Provider: OpenID Connect
#   - Provider URL: http://keycloak.staging.internal/auth/realms/platform
#   - Client ID: harbor
#   - Verify Cert: false (HTTP staging)
#   - Group Claim: groups (optional, for Harbor robot user management)
#
# ADR: TASK-002
# History: Created manually 2026-02-18 → migrated to TF (TASK-002)
# =============================================================================

resource "keycloak_openid_client" "harbor" {
  count = var.harbor_enabled ? 1 : 0

  realm_id    = keycloak_realm.platform.id
  client_id   = "harbor"
  name        = "Harbor OIDC"
  description = "Harbor container registry OIDC authentication via Keycloak platform realm"

  enabled = true

  # Standard Authorization Code Flow (browser-based SSO)
  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  # CONFIDENTIAL = has client secret (required for server-side OIDC)
  access_type = "CONFIDENTIAL"

  # Redirect URIs: Harbor OIDC callback
  valid_redirect_uris = [
    "http://harbor.${var.domain_suffix}/c/oidc/callback",
    "http://harbor.${var.domain_suffix}/*",
  ]

  # Web origins: CORS allowlist
  web_origins = [
    "http://harbor.${var.domain_suffix}",
  ]

  # PKCE S256 — Harbor 2.x supports PKCE via native OIDC integration
  pkce_code_challenge_method = "S256"

  # Root URL for Keycloak admin console links
  root_url = "http://harbor.${var.domain_suffix}"
  base_url = "http://harbor.${var.domain_suffix}"

  lifecycle {
    # Safety: never destroy — would break Harbor OIDC SSO for all platform engineers
    prevent_destroy = true

    ignore_changes = []
  }
}
