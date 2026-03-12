# =============================================================================
# RabbitMQ Module Outputs
# =============================================================================

output "rabbitmq_cluster_name" {
  description = "RabbitMQ cluster CR name"
  value       = "${var.cluster_name}-rabbitmq"
}

output "rabbitmq_service_internal" {
  description = "RabbitMQ service name for internal cluster access"
  value       = "${var.cluster_name}-rabbitmq"
}

output "rabbitmq_management_service_name" {
  description = "RabbitMQ Management ClusterIP service name for internal access"
  value       = kubernetes_service.rabbitmq_management_internal.metadata[0].name
}

output "rabbitmq_amqp_port" {
  description = "RabbitMQ AMQP port"
  value       = 5672
}

output "rabbitmq_management_port" {
  description = "RabbitMQ Management UI port"
  value       = 15672
}

output "rabbitmq_default_user_secret" {
  description = "Kubernetes secret name containing default RabbitMQ user credentials"
  value       = "${var.cluster_name}-rabbitmq-default-user"
}

output "rabbitmq_management_url" {
  description = "RabbitMQ Management UI URL (internal cluster access via port-forward or Ingress)"
  value       = "http://${kubernetes_service.rabbitmq_management_internal.metadata[0].name}.${var.namespace}.svc.cluster.local:15672"
}

output "rabbitmq_connection_string_internal" {
  description = "RabbitMQ connection string for internal cluster access"
  value       = "amqp://${var.cluster_name}-rabbitmq.${var.namespace}.svc.cluster.local:5672"
}
