# -----------------------------------------------------------------------------
# External Secrets Operator Module Outputs
# -----------------------------------------------------------------------------

output "namespace" {
  description = "External Secrets Operator namespace"
  value       = kubernetes_namespace.external_secrets.metadata[0].name
}

output "cluster_secret_store_name" {
  description = "ClusterSecretStore name for Vault backend (GAP-SEC-ESO-001: env-specific)"
  value       = var.cluster_secret_store_name
}

output "service_account_name" {
  description = "ServiceAccount name for Vault authentication"
  value       = "external-secrets" # Created automatically by Helm chart
}
