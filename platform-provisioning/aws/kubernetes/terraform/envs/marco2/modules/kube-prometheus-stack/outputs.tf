# -----------------------------------------------------------------------------
# Outputs - Kube-Prometheus-Stack Module
# -----------------------------------------------------------------------------

output "namespace" {
  description = "Namespace onde o stack de monitoramento foi instalado"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "helm_release_name" {
  description = "Nome do Helm release"
  value       = helm_release.kube_prometheus_stack.name
}

output "helm_release_version" {
  description = "Versão do Helm chart instalado"
  value       = helm_release.kube_prometheus_stack.version
}

output "prometheus_service" {
  description = "Nome do serviço do Prometheus"
  value       = "kube-prometheus-stack-prometheus"
}

output "grafana_service" {
  description = "Nome do serviço do Grafana"
  value       = "kube-prometheus-stack-grafana"
}

output "alertmanager_service" {
  description = "Nome do serviço do Alertmanager"
  value       = "kube-prometheus-stack-alertmanager"
}
