# -----------------------------------------------------------------------------
# Keycloak Module Outputs
# -----------------------------------------------------------------------------

output "namespace" {
  description = "Keycloak namespace"
  value       = kubernetes_namespace.keycloak.metadata[0].name
}

output "keycloak_url" {
  description = "Keycloak URL (internal cluster DNS)"
  value       = "http://keycloak-keycloakx-http.${kubernetes_namespace.keycloak.metadata[0].name}.svc.cluster.local/auth"
}

output "keycloak_admin_url" {
  description = "Keycloak admin console URL"
  value       = "http://keycloak-keycloakx-http.${kubernetes_namespace.keycloak.metadata[0].name}.svc.cluster.local/auth/admin"
}

output "admin_password_secret" {
  description = "Keycloak admin password Kubernetes secret name (V-006: migrado para ESO)"
  value       = "keycloak-admin-credentials"  # ExternalSecret synced from Vault
  sensitive   = true
}

output "realm_url" {
  description = "Keycloak master realm URL (for OIDC issuer configuration)"
  value       = "http://keycloak-keycloakx-http.${kubernetes_namespace.keycloak.metadata[0].name}.svc.cluster.local/auth/realms/master"
}
