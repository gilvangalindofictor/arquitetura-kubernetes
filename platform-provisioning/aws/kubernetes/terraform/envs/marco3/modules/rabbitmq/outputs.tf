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

output "rabbitmq_external_hostname" {
  description = "RabbitMQ LoadBalancer hostname for external access"
  value       = try(kubernetes_service.rabbitmq_management_external.status[0].load_balancer[0].ingress[0].hostname, "")
}

output "rabbitmq_external_ip" {
  description = "RabbitMQ LoadBalancer IP for external access (if available)"
  value       = try(kubernetes_service.rabbitmq_management_external.status[0].load_balancer[0].ingress[0].ip, "")
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
  description = "RabbitMQ Management UI URL (after LoadBalancer is provisioned)"
  value       = "http://${try(kubernetes_service.rabbitmq_management_external.status[0].load_balancer[0].ingress[0].hostname, "<pending>")}:15672"
}

output "rabbitmq_connection_string_internal" {
  description = "RabbitMQ connection string for internal cluster access"
  value       = "amqp://${var.cluster_name}-rabbitmq.${var.namespace}.svc.cluster.local:5672"
}
