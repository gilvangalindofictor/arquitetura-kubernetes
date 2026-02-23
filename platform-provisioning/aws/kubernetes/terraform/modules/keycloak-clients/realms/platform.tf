# =============================================================================
# Keycloak Realm: platform
# Import: terraform import 'keycloak_realm.platform' platform
#
# IMPORTANT — import-only mode:
#   This realm already exists in Keycloak. Do NOT destroy.
#   lifecycle { prevent_destroy = true } enforces safety.
#
# Realm settings validated against actual Keycloak 26.5.1 state.
# SSO Status (2026-02-18): Grafana, ArgoCD, Harbor, GitLab, Vault ✅
# =============================================================================

resource "keycloak_realm" "platform" {
  realm        = var.realm
  enabled      = true
  display_name = "Platform Services"

  # Login page settings
  registration_allowed          = false
  registration_email_as_username = false
  remember_me                   = false
  verify_email                  = false
  login_with_email_allowed      = true
  duplicate_emails_allowed      = false
  reset_password_allowed        = false
  edit_username_allowed         = false

  # Session settings (defaults for platform realm)
  sso_session_idle_timeout = "30m"
  sso_session_max_lifespan = "10h"

  # Access token lifespan (5min default, clients override per use-case)
  access_token_lifespan = "5m"

  lifecycle {
    # Safety: never destroy existing realm — would break ALL SSO integrations
    prevent_destroy = true

    # Ignore attributes not controlled by TF (Keycloak sets many internally)
    ignore_changes = [
      display_name_html,
      attributes,
      internationalization,
      security_defenses,
      web_authn_policy,
      web_authn_passwordless_policy,
    ]
  }
}
