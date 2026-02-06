# -----------------------------------------------------------------------------
# Vault Configuration Module Outputs
# -----------------------------------------------------------------------------

output "vault_k8s_auth_path" {
  description = "Vault Kubernetes auth mount path"
  value       = vault_auth_backend.kubernetes.path
}

output "eso_reader_role" {
  description = "Vault role for ESO authentication"
  value       = vault_kubernetes_auth_backend_role.eso_reader.role_name
}

output "eso_reader_policy" {
  description = "Vault policy for ESO read access"
  value       = vault_policy.eso_reader.name
}

output "keycloak_secret_path" {
  description = "Vault KV v2 path for Keycloak PostgreSQL credentials"
  value       = "secret/data/keycloak/postgresql"
}
