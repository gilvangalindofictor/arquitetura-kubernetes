# -----------------------------------------------------------------------------
# External Secrets Operator Module Outputs
# -----------------------------------------------------------------------------

output "namespace" {
  description = "External Secrets Operator namespace"
  value       = kubernetes_namespace.external_secrets.metadata[0].name
}

output "cluster_secret_store_name" {
  description = "ClusterSecretStore name for Vault backend"
  value       = "vault-backend"
}

output "service_account_name" {
  description = "ServiceAccount name for Vault authentication"
  value       = kubernetes_service_account.external_secrets_vault.metadata[0].name
}
