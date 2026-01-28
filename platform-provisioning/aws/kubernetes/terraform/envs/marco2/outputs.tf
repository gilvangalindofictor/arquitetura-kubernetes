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

# -----------------------------------------------------------------------------
# Loki Outputs
# -----------------------------------------------------------------------------

output "loki_s3_bucket" {
  description = "Nome do S3 bucket do Loki"
  value       = module.loki.s3_bucket_name
}

output "loki_iam_role_arn" {
  description = "ARN da IAM Role do Loki (IRSA)"
  value       = module.loki.iam_role_arn
}

output "loki_gateway_endpoint" {
  description = "Endpoint do Loki Gateway"
  value       = module.loki.loki_gateway_endpoint
}

output "loki_push_endpoint" {
  description = "Endpoint para push de logs (usado pelo Fluent Bit)"
  value       = module.loki.loki_push_endpoint
}

# -----------------------------------------------------------------------------
# Fluent Bit Outputs
# -----------------------------------------------------------------------------

output "fluent_bit_daemonset" {
  description = "Nome do DaemonSet do Fluent Bit"
  value       = module.fluent_bit.daemonset_name
}

output "fluent_bit_namespace" {
  description = "Namespace do Fluent Bit"
  value       = module.fluent_bit.namespace
}

# -----------------------------------------------------------------------------
# Network Policies Outputs (Marco 2 Fase 5)
# -----------------------------------------------------------------------------

output "network_policies_applied" {
  description = "Lista de Network Policies aplicadas"
  value       = module.network_policies.policies_applied
}

output "network_policies_namespaces" {
  description = "Namespaces com Network Policies configuradas"
  value       = module.network_policies.namespaces_with_policies
}

output "network_policies_default_deny_enabled" {
  description = "Se default deny-all está habilitado"
  value       = module.network_policies.default_deny_enabled
}

output "network_policies_calico_version" {
  description = "Versão do Calico instalada"
  value       = module.network_policies.calico_version
}

# -----------------------------------------------------------------------------
# Cluster Autoscaler Outputs (Marco 2 Fase 6)
# -----------------------------------------------------------------------------

output "cluster_autoscaler_iam_role_arn" {
  description = "ARN da IAM Role do Cluster Autoscaler"
  value       = module.cluster_autoscaler.iam_role_arn
}

output "cluster_autoscaler_service_account" {
  description = "Nome da Service Account do Cluster Autoscaler"
  value       = module.cluster_autoscaler.service_account_name
}

output "cluster_autoscaler_namespace" {
  description = "Namespace do Cluster Autoscaler"
  value       = module.cluster_autoscaler.namespace
}

output "cluster_autoscaler_configuration" {
  description = "Configuração do Cluster Autoscaler"
  value       = module.cluster_autoscaler.configuration_summary
}
