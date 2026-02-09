# =============================================================================
# Redis Module Outputs
# COMPATÍVEL COM VERSÃO BITNAMI (zero breaking changes)
# =============================================================================

output "redis_master_service" {
  description = "Redis master service name (internal access)"
  value       = "rfrm-redis" # RedisFailover naming convention (master)
}

output "redis_replicas_service" {
  description = "Redis replicas service name (internal read access)"
  value       = "rfr-redis"
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
  value       = "redis://:password@rfr-redis.${var.namespace}.svc.cluster.local:6379"
  sensitive   = true
}

output "operator_namespace" {
  description = "Namespace where Redis Operator is deployed"
  value       = kubernetes_namespace.redis_operator.metadata[0].name
}

output "redis_failover_name" {
  description = "RedisFailover CR name"
  value       = "redis"
}

output "namespace" {
  description = "Namespace where Redis is deployed"
  value       = kubernetes_namespace.data_services.metadata[0].name
}
