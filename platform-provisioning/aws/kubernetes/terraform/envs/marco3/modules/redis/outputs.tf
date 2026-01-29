# =============================================================================
# Redis Module Outputs
# =============================================================================

output "redis_master_service" {
  description = "Redis master service name (internal access)"
  value       = "${helm_release.redis.name}-master"
}

output "redis_replicas_service" {
  description = "Redis replicas service name (internal read access)"
  value       = "${helm_release.redis.name}-replicas"
}

output "redis_external_hostname" {
  description = "Redis LoadBalancer hostname for external access"
  value       = try(kubernetes_service.redis_external.status[0].load_balancer[0].ingress[0].hostname, "")
}

output "redis_external_ip" {
  description = "Redis LoadBalancer IP for external access (if available)"
  value       = try(kubernetes_service.redis_external.status[0].load_balancer[0].ingress[0].ip, "")
}

output "redis_password_secret_name" {
  description = "Kubernetes secret name containing Redis password"
  value       = kubernetes_secret.redis_password.metadata[0].name
}

output "redis_port" {
  description = "Redis port"
  value       = 6379
}

output "redis_connection_string_internal" {
  description = "Redis connection string for internal cluster access"
  value       = "redis://:password@${helm_release.redis.name}-master.${var.namespace}.svc.cluster.local:6379"
  sensitive   = true
}
