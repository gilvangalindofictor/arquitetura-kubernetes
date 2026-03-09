# -----------------------------------------------------------------------------
# Backstage IDP Module Outputs
# ADR-055
# -----------------------------------------------------------------------------

output "namespace" {
  description = "Backstage Kubernetes namespace"
  value       = kubernetes_namespace.backstage.metadata[0].name
}

output "backstage_url" {
  description = "Backstage internal URL (cluster DNS)"
  value       = "http://backstage.${kubernetes_namespace.backstage.metadata[0].name}.svc.cluster.local:7007"
}

output "backstage_external_url" {
  description = "Backstage external URL (ALB ingress)"
  value       = "https://backstage.staging.internal"
}

output "cluster_role_name" {
  description = "ClusterRole name for Backstage Kubernetes plugin"
  value       = kubernetes_cluster_role.backstage_kubernetes_reader.metadata[0].name
}

output "vault_policy_name" {
  description = "Vault policy name for Backstage"
  value       = vault_policy.backstage.name
}

output "vault_auth_role" {
  description = "Vault Kubernetes auth role for Backstage"
  value       = vault_kubernetes_auth_backend_role.backstage.role_name
}

output "externalsecret_name" {
  description = "ExternalSecret name syncing Vault secrets to K8s"
  value       = "backstage-secrets"
}

output "helm_release_version" {
  description = "Backstage Helm chart version deployed"
  value       = helm_release.backstage.version
}
