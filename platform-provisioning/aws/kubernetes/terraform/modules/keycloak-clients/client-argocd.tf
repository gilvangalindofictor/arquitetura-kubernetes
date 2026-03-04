# =============================================================================
# Keycloak OIDC Client: ArgoCD
# Realm: platform | Client ID: argocd
# Access type: CONFIDENTIAL | Standard Flow: enabled
# PKCE: ENABLED — S256 (ArgoCD v2.10.9 / chart argo-cd-6.7.18, enabled 2026-03-04)
# ArgoCD values: enablePKCEAuthentication: true in oidc.config
#
# Import:
#   terraform import 'keycloak_openid_client.argocd' "platform/{UUID}"
#   UUID from: kubectl exec -n keycloak <pod> -- /opt/keycloak/bin/kcadm.sh \
#     get clients -r platform --fields id,clientId | jq '.[] | select(.clientId=="argocd") | .id'
#
# V-002 Remediation (2026-02-20):
#   Vault KV: secret/argocd/oidc → ESO ExternalSecret: argocd-oidc-credentials
#   Client secret NOT managed here — managed by vault-config module
#
# ADR: TASK-002, V-002 (docs/context/decisions.md)
# =============================================================================

resource "keycloak_openid_client" "argocd" {
  count = var.argocd_enabled ? 1 : 0

  realm_id    = keycloak_realm.platform.id
  client_id   = "argocd"
  name        = "ArgoCD OIDC"
  description = "ArgoCD GitOps OIDC authentication via Keycloak platform realm"

  enabled = true

  # Standard Authorization Code Flow (browser-based SSO)
  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  # CONFIDENTIAL = has client secret
  access_type = "CONFIDENTIAL"

  # Redirect URIs: ArgoCD OIDC callback
  valid_redirect_uris = [
    "http://argocd.${var.domain_suffix}/auth/callback",
    "http://localhost:8080/auth/callback",
  ]

  # Web origins: CORS allowlist
  web_origins = [
    "http://argocd.${var.domain_suffix}",
  ]

  # PKCE: ENABLED — S256 method (ArgoCD v2.10.9 + chart argo-cd-6.7.18, enabled 2026-03-04)
  pkce_code_challenge_method = "S256"

  # Backchannel logout — ArgoCD supports it
  backchannel_logout_session_required        = true
  backchannel_logout_revoke_offline_sessions = false

  # Root URL for Keycloak admin console
  root_url = "http://argocd.${var.domain_suffix}"
  base_url = "http://argocd.${var.domain_suffix}"

  lifecycle {
    # Safety: never destroy — would break ArgoCD OIDC for all platform engineers
    prevent_destroy = true

    ignore_changes = []
  }
}
