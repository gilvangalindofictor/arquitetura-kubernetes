# =============================================================================
# Keycloak OIDC Client: GitLab
# Realm: platform | Client ID: gitlab
# Access type: CONFIDENTIAL | Standard Flow: enabled
# PKCE: S256 (GitLab 8.x supports PKCE)
#
# Import:
#   terraform import 'keycloak_openid_client.gitlab' "platform/{UUID}"
#   UUID from: kubectl exec -n keycloak <pod> -- /opt/keycloak/bin/kcadm.sh \
#     get clients -r platform --fields id,clientId | jq '.[] | select(.clientId=="gitlab") | .id'
#
# Logbook: 2026-02-12-keycloak-oidc-integration-troubleshooting.md
# History: Created manually via SQL (2026-02-11) → migrated to TF (TASK-002)
# =============================================================================

resource "keycloak_openid_client" "gitlab" {
  count = var.gitlab_enabled ? 1 : 0

  realm_id    = keycloak_realm.platform.id
  client_id   = "gitlab"
  name        = "GitLab OIDC"
  description = "GitLab CE OIDC authentication via Keycloak platform realm"

  enabled = true

  # Standard Authorization Code Flow (browser-based SSO)
  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  # CONFIDENTIAL = has client secret (required for server-side auth)
  access_type = "CONFIDENTIAL"

  # Redirect URIs: GitLab OmniAuth OIDC callback
  valid_redirect_uris = [
    "http://gitlab.${var.domain_suffix}/users/auth/openid_connect/callback",
    "http://gitlab.${var.domain_suffix}/*",
  ]

  # Web origins: CORS allowlist
  web_origins = [
    "http://gitlab.${var.domain_suffix}",
  ]

  # PKCE S256 — GitLab 8.x (CE) supports PKCE via OmniAuth
  pkce_code_challenge_method = "S256"

  # Root URL (optional but helpful for Keycloak admin console links)
  root_url = "http://gitlab.${var.domain_suffix}"

  # Base URL (Keycloak "Home URL" in admin console)
  base_url = "http://gitlab.${var.domain_suffix}"

  lifecycle {
    # Safety: never destroy — would break GitLab SSO for all users
    prevent_destroy = true

    # NÃO regenerar client_secret via TF (import-only mode)
    # client_secret managed by ESO: Vault → keycloak/oidc → K8s Secret
    ignore_changes = [
      # client_secret is not a direct field on keycloak_openid_client;
      # it lives in keycloak_openid_client_secret data source.
      # No ignore_changes needed here for secret — handled separately.
    ]
  }
}

# Read existing client secret (no rotation — import-only)
# Used to populate Vault KV via vault_config module
data "keycloak_openid_client_service_account_user" "gitlab" {
  count     = 0 # Not a service account client — skip
  realm_id  = keycloak_realm.platform.id
  client_id = keycloak_openid_client.gitlab[0].id
}
