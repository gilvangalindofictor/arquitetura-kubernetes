# -----------------------------------------------------------------------------
# Outputs - Promtail Module
# -----------------------------------------------------------------------------

output "release_name" {
  description = "Nome do Helm release do Promtail"
  value       = helm_release.promtail.name
}

output "namespace" {
  description = "Namespace Kubernetes onde o Promtail esta deployado"
  value       = helm_release.promtail.namespace
}

output "chart_version" {
  description = "Versao do Helm chart deployada"
  value       = helm_release.promtail.version
}

output "status" {
  description = "Status atual do Helm release"
  value       = helm_release.promtail.status
}
