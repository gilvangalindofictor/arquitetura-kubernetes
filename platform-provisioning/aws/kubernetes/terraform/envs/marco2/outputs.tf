# -----------------------------------------------------------------------------
# Outputs - Marco 2
# -----------------------------------------------------------------------------

output "aws_load_balancer_controller_role_arn" {
  description = "ARN da IAM Role do AWS Load Balancer Controller"
  value       = module.aws_load_balancer_controller.iam_role_arn
}

output "aws_load_balancer_controller_service_account" {
  description = "Nome da Service Account do AWS Load Balancer Controller"
  value       = module.aws_load_balancer_controller.service_account_name
}

output "aws_load_balancer_controller_namespace" {
  description = "Namespace do AWS Load Balancer Controller"
  value       = module.aws_load_balancer_controller.namespace
}

# -----------------------------------------------------------------------------
# Cert-Manager Outputs
# -----------------------------------------------------------------------------

output "cert_manager_namespace" {
  description = "Namespace do Cert-Manager"
  value       = module.cert_manager.namespace
}

output "cert_manager_cluster_issuers" {
  description = "ClusterIssuers criados pelo Cert-Manager"
  value       = module.cert_manager.cluster_issuers_created
}

# -----------------------------------------------------------------------------
# Kube-Prometheus-Stack Outputs
# -----------------------------------------------------------------------------

output "monitoring_namespace" {
  description = "Namespace do stack de monitoramento"
  value       = module.kube_prometheus_stack.namespace
}

output "prometheus_service" {
  description = "Nome do serviço do Prometheus"
  value       = module.kube_prometheus_stack.prometheus_service
}

output "grafana_service" {
  description = "Nome do serviço do Grafana"
  value       = module.kube_prometheus_stack.grafana_service
}

output "alertmanager_service" {
  description = "Nome do serviço do Alertmanager"
  value       = module.kube_prometheus_stack.alertmanager_service
}
