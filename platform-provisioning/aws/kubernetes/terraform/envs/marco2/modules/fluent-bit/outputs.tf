# -----------------------------------------------------------------------------
# Outputs - Fluent Bit Module
# -----------------------------------------------------------------------------

output "helm_release_name" {
  description = "Nome do Helm release"
  value       = helm_release.fluent_bit.name
}

output "helm_release_version" {
  description = "Versão do Helm chart instalado"
  value       = helm_release.fluent_bit.version
}

output "namespace" {
  description = "Namespace onde o Fluent Bit foi instalado"
  value       = var.namespace
}

output "daemonset_name" {
  description = "Nome do DaemonSet criado pelo Helm chart"
  value       = "fluent-bit"
}

output "service_account_name" {
  description = "Nome da Service Account criada"
  value       = var.service_account_name
}

output "loki_endpoint" {
  description = "Endpoint do Loki configurado no Fluent Bit"
  value       = var.loki_endpoint
}
