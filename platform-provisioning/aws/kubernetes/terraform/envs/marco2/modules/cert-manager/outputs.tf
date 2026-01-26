# -----------------------------------------------------------------------------
# Outputs - Cert-Manager Module
# -----------------------------------------------------------------------------

output "namespace" {
  description = "Namespace onde o Cert-Manager foi instalado"
  value       = kubernetes_namespace.cert_manager.metadata[0].name
}

output "helm_release_name" {
  description = "Nome do Helm release"
  value       = helm_release.cert_manager.name
}

output "helm_release_version" {
  description = "Versão do Helm chart instalado"
  value       = helm_release.cert_manager.version
}

output "cluster_issuers_created" {
  description = "Lista de ClusterIssuers criados"
  value = var.create_cluster_issuers ? [
    "letsencrypt-staging",
    "letsencrypt-production"
  ] : []
}
