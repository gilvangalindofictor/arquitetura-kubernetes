# =============================================================================
# Reusable OIDC Client Module — Outputs
# =============================================================================

output "client_uuid" {
  description = "Keycloak internal UUID for this OIDC client. Use this for terraform import and API calls."
  value       = keycloak_openid_client.this.id
}

output "client_id" {
  description = "OIDC client_id string (the value set in var.client_id). Used in app configuration."
  value       = keycloak_openid_client.this.client_id
}

output "realm_id" {
  description = "Realm ID where this client was created."
  value       = keycloak_openid_client.this.realm_id
}

output "pkce_enabled" {
  description = "Whether PKCE S256 is enabled for this client."
  value       = var.enable_pkce
}

output "issuer_url" {
  description = "OIDC issuer URL for this realm. Constructed from the provider URL — update base if Keycloak URL changes."
  value       = "http://keycloak.staging.internal/auth/realms/platform"
}

# NOTE: client_secret is intentionally NOT output here.
# After creation, retrieve via:
#   kubectl exec -n keycloak <pod> -- /opt/keycloak/bin/kcadm.sh \
#     get clients/{UUID}/client-secret -r platform
# Then store in Vault KV: secret/{client_id}/oidc
# ESO ExternalSecret will sync to Kubernetes secret in the app namespace.
