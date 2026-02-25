# =============================================================================
# Keycloak OIDC Client: Vault
# Realm: platform | Client ID: vault
# Access type: CONFIDENTIAL | Standard Flow: enabled
# PKCE: S256 (Vault 1.15+ OIDC auth method supports PKCE)
#
# Import:
#   terraform import 'keycloak_openid_client.vault' "platform/{UUID}"
#   UUID from: kubectl exec -n keycloak <pod> -- /opt/keycloak/bin/kcadm.sh \
#     get clients -r platform --fields id,clientId | jq '.[] | select(.clientId=="vault") | .id'
#
# ESO Integration:
#   Vault KV: secret/vault/oidc → ESO ExternalSecret: vault-oidc-credentials
#   Namespace: staging-security-vault
#
# Vault OIDC Auth Method Config (managed via vault-config Terraform module):
#   vault write auth/oidc/config \
#     oidc_discovery_url="http://keycloak.staging.internal/auth/realms/platform" \
#     oidc_client_id="vault" \
#     oidc_client_secret="<secret>" \
#     default_role="default"
#
# Allowed redirect URIs (must match this resource's valid_redirect_uris):
#   http://vault.staging.internal/ui/vault/auth/oidc/oidc/callback
#   http://localhost:8250/oidc/callback   (Vault CLI OIDC login)
#
# ADR: TASK-002
# History: Created manually 2026-02-18 → migrated to TF (TASK-002)
# =============================================================================

resource "keycloak_openid_client" "vault" {
  count = var.vault_enabled ? 1 : 0

  realm_id    = keycloak_realm.platform.id
  client_id   = "vault"
  name        = "Vault OIDC"
  description = "HashiCorp Vault OIDC authentication via Keycloak platform realm"

  enabled = true

  # Standard Authorization Code Flow (browser-based SSO via Vault UI)
  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  # CONFIDENTIAL = has client secret (required for server-side OIDC)
  access_type = "CONFIDENTIAL"

  # Redirect URIs: Vault UI callback + CLI OIDC login (localhost)
  valid_redirect_uris = [
    "http://vault.${var.domain_suffix}/ui/vault/auth/oidc/oidc/callback",
    "http://vault.${var.domain_suffix}/*",
    "http://localhost:8250/oidc/callback",
  ]

  # Web origins: CORS allowlist
  web_origins = [
    "http://vault.${var.domain_suffix}",
    "http://localhost:8250",
  ]

  # PKCE S256 — Vault 1.15+ OIDC auth method supports PKCE natively
  pkce_code_challenge_method = "S256"

  # Root URL for Keycloak admin console links
  root_url = "http://vault.${var.domain_suffix}"
  base_url = "http://vault.${var.domain_suffix}"

  lifecycle {
    # Safety: never destroy — would break Vault OIDC login for all operators
    prevent_destroy = true

    ignore_changes = []
  }
}
