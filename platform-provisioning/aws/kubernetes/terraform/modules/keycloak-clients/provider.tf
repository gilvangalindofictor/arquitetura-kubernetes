# =============================================================================
# Keycloak Provider Configuration
# WSL-safe pattern: uses localhost URL via kubectl port-forward
#
# USAGE (before terraform init/plan/apply):
#   kubectl port-forward svc/keycloak-keycloakx-http 18080:80 -n keycloak &
#
# The provider connects to http://localhost:18080/auth
# keycloak.staging.internal does NOT resolve from WSL2 (CoreDNS cluster-only)
#
# Authentication flow:
#   1. admin-cli client (master realm) with admin password
#   2. Password retrieved from K8s secret: keycloak-admin-password (namespace: keycloak)
#
# CRITICAL — Keycloak 26.5.1 (keycloakx chart) still uses /auth prefix:
#   Token endpoint: /auth/realms/master/protocol/openid-connect/token
#   Admin API:      /auth/admin/realms/...
#   Provider URL:   http://localhost:18080/auth  ← includes /auth
#
# See MEMORY.md: "Keycloak 26 Admin REST API Endpoints"
# =============================================================================

provider "keycloak" {
  # localhost URL: requires port-forward to be active before any TF operation
  # kubectl port-forward svc/keycloak-keycloakx-http 18080:80 -n keycloak &
  url = var.keycloak_url

  # client_credentials grant (service account) — avoids password special char encoding issues
  # Client: terraform-admin (master realm), with admin role
  # Created: 2026-03-06 to bypass URL encoding issue with admin password containing ?, =, > chars
  # Secret is static (not sensitive — Keycloak master realm service account for IaC only)
  client_id     = "terraform-admin"
  client_secret = var.keycloak_client_secret

  # Realm for admin operations (always master for admin-cli)
  realm = "master"

  # Disable TLS verification (HTTP, no TLS in cluster-internal traffic)
  tls_insecure_skip_verify = false

  # Base path includes /auth (keycloakx legacy config still enables it)
  # keycloakx 7.1.7 / Keycloak 26.5.1 still serves /auth prefix (legacy mode)
  # Without this, provider appends /realms/... → 404
  # With base_path="/auth", provider uses: http://localhost:18080/auth/realms/...
  base_path = "/auth"

  initial_login = true
}
