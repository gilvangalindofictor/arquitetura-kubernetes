# =============================================================================
# Keycloak SAML Client: SonarQube
# Realm: platform | Client ID: sonarqube
# Protocol: SAML 2.0 (NOT OpenID Connect)
# PKCE: N/A — SAML protocol does not use PKCE
#
# CRITICAL — Protocol Difference:
#   SonarQube uses SAML SP-initiated SSO (not OIDC).
#   This uses keycloak_saml_client, NOT keycloak_openid_client.
#   SSO Status (2026-02-18): ✅ SAML 2.0 via GitLab Social IdP federation
#
# Import:
#   terraform import 'keycloak_saml_client.sonarqube' "platform/{UUID}"
#   UUID from: kubectl exec -n keycloak <pod> -- /opt/keycloak/bin/kcadm.sh \
#     get clients -r platform --fields id,clientId | jq '.[] | select(.clientId=="sonarqube") | .id'
#
# ESO Integration:
#   Vault KV: secret/sonarqube/saml → ESO ExternalSecret: sonarqube-sp-saml
#   Namespace: sonarqube
#   Keys: sp_certificate, sp_private_key_pkcs8
#
# SonarQube SAML Config (set via sonarqube-sp-saml secret.properties):
#   sonar.auth.saml.enabled=true
#   sonar.auth.saml.applicationId=sonarqube
#   sonar.auth.saml.providerName=Keycloak
#   sonar.auth.saml.providerId=http://keycloak.staging.internal/auth/realms/platform
#   sonar.auth.saml.loginUrl=http://keycloak.staging.internal/auth/realms/platform/...
#
# SP Certificate: stored in Vault KV secret/sonarqube/saml → sp_certificate
# IDP Certificate: exported from Keycloak realm keys → stored in sonarqube SAML config
#
# ADR: TASK-002
# History: Created manually 2026-02-18 → migrated to TF (TASK-002)
# Logbook: 2026-02-12-keycloak-oidc-integration-troubleshooting.md (SAML setup notes)
# =============================================================================

resource "keycloak_saml_client" "sonarqube" {
  count = var.sonarqube_enabled ? 1 : 0

  realm_id    = keycloak_realm.platform.id
  client_id   = "sonarqube"
  name        = "SonarQube SAML"
  description = "SonarQube code quality SAML 2.0 authentication via Keycloak platform realm"

  enabled = true

  # SP-initiated SSO (SonarQube redirects to Keycloak IdP)
  # IDP-initiated is disabled (security best practice)

  # SAML Assertion Consumer Service (ACS) URL — SonarQube SAML callback
  valid_redirect_uris = [
    "http://sonarqube.${var.domain_suffix}/oauth2/callback/saml",
    "http://sonarqube.${var.domain_suffix}/*",
  ]

  # SonarQube ACS endpoint (POST binding — standard for SAML SP)
  assertion_consumer_post_url = "http://sonarqube.${var.domain_suffix}/oauth2/callback/saml"

  # SonarQube Single Logout endpoint (optional but recommended)
  logout_service_post_binding_url = "http://sonarqube.${var.domain_suffix}/oauth2/callback/saml"

  # SAML signing — sign assertions (required by SonarQube SAML SP)
  sign_documents     = true
  sign_assertions    = true
  encrypt_assertions = false

  # Client signature validation — SonarQube signs AuthnRequests with SP key
  # SP certificate loaded from: Vault KV secret/sonarqube/saml → sp_certificate
  client_signature_required = true

  # Name ID format: email (SonarQube uses email as user identifier)
  name_id_format = "email"

  # Root URL for Keycloak admin console links
  root_url = "http://sonarqube.${var.domain_suffix}"
  base_url = "http://sonarqube.${var.domain_suffix}"

  lifecycle {
    # Safety: never destroy — would break SonarQube SSO for all engineers
    prevent_destroy = true

    # SP certificates change rarely; ignore to prevent force-recreate
    ignore_changes = [
      # signing_certificate and encryption_certificate are set externally
      # via Vault KV → sonarqube-sp-saml → SonarQube SAML config
    ]
  }
}

# =============================================================================
# SAML Property Mapper: email
# Required: SonarQube maps user identity from SAML attribute "email"
# NOTE: uses keycloak_saml_user_property_protocol_mapper (not attribute mapper)
# because Keycloak stores this as protocolMapper: "saml-user-property-mapper"
# (maps built-in user property "email", not a custom attribute)
# Fix: 2026-03-04 — changed from user_attribute_protocol_mapper to user_property_protocol_mapper
# =============================================================================

resource "keycloak_saml_user_property_protocol_mapper" "sonarqube_email" {
  count = var.sonarqube_enabled ? 1 : 0

  realm_id  = keycloak_realm.platform.id
  client_id = keycloak_saml_client.sonarqube[0].id
  name      = "email"

  user_property       = "email"
  saml_attribute_name = "email"

  # BASIC attribute name format (SonarQube expects plain attribute name)
  saml_attribute_name_format = "Basic"

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# SAML Attribute Mapper: name (display name)
# SonarQube uses "name" attribute for user display name
# =============================================================================

resource "keycloak_saml_user_property_protocol_mapper" "sonarqube_name" {
  count = var.sonarqube_enabled ? 1 : 0

  realm_id  = keycloak_realm.platform.id
  client_id = keycloak_saml_client.sonarqube[0].id
  name      = "name"

  user_property       = "username"
  saml_attribute_name = "name"

  # BASIC attribute name format
  saml_attribute_name_format = "Basic"

  lifecycle {
    prevent_destroy = true
  }
}
