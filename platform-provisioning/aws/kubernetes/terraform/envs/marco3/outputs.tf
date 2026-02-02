# PostgreSQL Outputs
output "postgresql_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = module.postgresql.rds_endpoint
}

output "postgresql_port" {
  description = "PostgreSQL RDS port"
  value       = module.postgresql.rds_port
}

output "postgresql_password_secret_arn" {
  description = "PostgreSQL master password secret ARN"
  value       = module.postgresql.master_password_secret_arn
  sensitive   = true
}

output "postgresql_service_internal_dns" {
  description = "PostgreSQL internal Kubernetes DNS name"
  value       = module.postgresql.service_internal_dns
}

# Redis Outputs
output "redis_master_service" {
  description = "Redis master service name"
  value       = module.redis.redis_master_service
}

output "redis_password_secret" {
  description = "Redis password secret name"
  value       = module.redis.redis_password_secret_name
}

output "redis_namespace" {
  description = "Redis namespace"
  value       = module.redis.namespace
}

output "redis_connection_string" {
  description = "Redis connection string (internal)"
  value       = module.redis.redis_connection_string_internal
  sensitive   = true
}

# RabbitMQ Outputs
output "rabbitmq_cluster_name" {
  description = "RabbitMQ cluster CR name"
  value       = module.rabbitmq.rabbitmq_cluster_name
}

output "rabbitmq_management_url" {
  description = "RabbitMQ Management UI URL"
  value       = module.rabbitmq.rabbitmq_management_url
}

output "rabbitmq_external_hostname" {
  description = "RabbitMQ NLB hostname for external access"
  value       = module.rabbitmq.rabbitmq_external_hostname
}

output "rabbitmq_default_user_secret" {
  description = "RabbitMQ default user secret name"
  value       = module.rabbitmq.rabbitmq_default_user_secret
}

# S3 Outputs
output "gitlab_artifacts_bucket" {
  description = "GitLab artifacts S3 bucket name"
  value       = module.s3_buckets.gitlab_artifacts_bucket_name
}

output "gitlab_artifacts_bucket_arn" {
  description = "GitLab artifacts S3 bucket ARN"
  value       = module.s3_buckets.gitlab_artifacts_bucket_arn
}

output "harbor_images_bucket" {
  description = "Harbor images S3 bucket name"
  value       = module.s3_buckets.harbor_images_bucket_name
}

output "harbor_images_bucket_arn" {
  description = "Harbor images S3 bucket ARN"
  value       = module.s3_buckets.harbor_images_bucket_arn
}

output "gitlab_s3_policy_arn" {
  description = "IAM policy ARN for GitLab S3 access"
  value       = module.s3_buckets.gitlab_s3_policy_arn
}

output "harbor_s3_policy_arn" {
  description = "IAM policy ARN for Harbor S3 access"
  value       = module.s3_buckets.harbor_s3_policy_arn
}
