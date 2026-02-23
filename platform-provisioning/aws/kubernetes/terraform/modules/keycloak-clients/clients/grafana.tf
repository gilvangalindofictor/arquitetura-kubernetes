# =============================================================================
# Keycloak OIDC Client: Grafana
# Realm: platform | Client ID: grafana
# Access type: CONFIDENTIAL | Standard Flow: enabled
# PKCE: S256 (Grafana 10+ supports PKCE via generic_oauth)
#
# Import:
#   terraform import 'keycloak_openid_client.grafana' "platform/{UUID}"
#   UUID from: kubectl exec -n keycloak <pod> -- /opt/keycloak/bin/kcadm.sh \
#     get clients -r platform --fields id,clientId | jq '.[] | select(.clientId=="grafana") | .id'
#
# Groups mapper: oidc-group-membership-mapper (claim "groups")
#   Was: null_resource.keycloak_grafana_admins_group (Python port-forward hack)
#   Now: keycloak_generic_protocol_mapper.grafana_groups (native provider)
#
# grafana-admins group:
#   Was: null_resource.keycloak_grafana_admins_group (Python port-forward hack)
#   Now: keycloak_group.grafana_admins (native provider)
#
# Client secret path: Vault KV secret/grafana/oidc (ESO grafana-oidc-credentials)
# Grafana ini: GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET via envValueFrom (NOT grafana.ini)
#
# MEMORY.md: "Grafana OIDC — Email Obrigatório no Keycloak"
#   Every OIDC user MUST have email set in Keycloak profile
#
# ADR: TASK-002, GAP-001 (grafana-admins group), V-001
# =============================================================================

resource "keycloak_openid_client" "grafana" {
  count = var.grafana_enabled ? 1 : 0

  realm_id  = keycloak_realm.platform.id
  client_id = "grafana"
  name      = "Grafana OIDC"
  description = "Grafana observability OIDC authentication via Keycloak platform realm"

  enabled = true

  # Standard Authorization Code Flow
  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  # CONFIDENTIAL = has client secret
  access_type = "CONFIDENTIAL"

  # Redirect URIs: Grafana generic_oauth callback
  valid_redirect_uris = [
    "http://grafana.${var.domain_suffix}/login/generic_oauth",
    "http://grafana.${var.domain_suffix}/*",
  ]

  # Web origins: CORS allowlist
  web_origins = [
    "http://grafana.${var.domain_suffix}",
  ]

  # PKCE S256 — Grafana 10+ supports PKCE natively
  pkce_code_challenge_method = "S256"

  # Root URL for Keycloak admin console links
  root_url = "http://grafana.${var.domain_suffix}"
  base_url = "http://grafana.${var.domain_suffix}"

  lifecycle {
    # Safety: never destroy — would break Grafana OIDC SSO
    prevent_destroy = true

    ignore_changes = []
  }
}

# =============================================================================
# Protocol Mapper: oidc-group-membership-mapper (claim "groups")
# Replaces Python port-forward hack in null_resource.keycloak_grafana_admins_group
# Required for Grafana role_attribute_path: contains(groups[*], 'grafana-admins')
# =============================================================================

resource "keycloak_generic_protocol_mapper" "grafana_groups" {
  count = var.grafana_enabled && var.grafana_admins_group_enabled ? 1 : 0

  realm_id        = keycloak_realm.platform.id
  client_id       = keycloak_openid_client.grafana[0].id
  name            = "groups"
  protocol        = "openid-connect"
  protocol_mapper = "oidc-group-membership-mapper"

  config = {
    # Include in all token types
    "id.token.claim"       = "true"
    "access.token.claim"   = "true"
    "userinfo.token.claim" = "true"

    # Claim name in JWT
    "claim.name" = "groups"

    # Use short group names (not full path /parent/child)
    "full.path" = "false"
  }

  lifecycle {
    # Safety: never destroy — would break Grafana admin role assignment
    prevent_destroy = true
  }
}

# =============================================================================
# Group: grafana-admins (realm: platform)
# Replaces Python port-forward hack in null_resource.keycloak_grafana_admins_group
# Users in this group get Grafana Admin role via:
#   grafana.ini: role_attribute_path = contains(groups[*], 'grafana-admins') && 'Admin' || 'Viewer'
#
# Import:
#   terraform import 'keycloak_group.grafana_admins' "platform/{GROUP_UUID}"
#   UUID from: Admin API GET /auth/admin/realms/platform/groups?search=grafana-admins
# =============================================================================

resource "keycloak_group" "grafana_admins" {
  count = var.grafana_admins_group_enabled ? 1 : 0

  realm_id = keycloak_realm.platform.id
  name     = "grafana-admins"

  lifecycle {
    # Safety: never destroy — would remove Grafana Admin access for all members
    prevent_destroy = true
  }
}
