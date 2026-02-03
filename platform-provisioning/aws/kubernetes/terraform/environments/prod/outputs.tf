# PROD Environment Outputs

#------------------------------------------------------------------------------
# PostgreSQL RDS Outputs
#------------------------------------------------------------------------------

output "postgresql_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = module.postgresql_prod.endpoint
}

output "postgresql_service_name" {
  description = "PostgreSQL Kubernetes service name"
  value       = module.postgresql_prod.service_name
}

output "postgresql_database_name" {
  description = "PostgreSQL database name"
  value       = module.postgresql_prod.database_name
}

output "postgresql_instance_id" {
  description = "RDS instance ID"
  value       = module.postgresql_prod.db_instance_id
}

#------------------------------------------------------------------------------
# Redis Operator Outputs
#------------------------------------------------------------------------------

output "redis_master_service" {
  description = "Redis master service name"
  value       = module.redis_prod.redis_master_service
}

output "redis_port" {
  description = "Redis port"
  value       = module.redis_prod.redis_port
}

output "redis_namespace" {
  description = "Redis namespace"
  value       = module.redis_prod.namespace
}

output "redis_password_secret_name" {
  description = "Redis password Kubernetes secret name"
  value       = module.redis_prod.redis_password_secret_name
}

#------------------------------------------------------------------------------
# RabbitMQ Operator Outputs
#------------------------------------------------------------------------------

output "rabbitmq_service" {
  description = "RabbitMQ service name"
  value       = module.rabbitmq_prod.rabbitmq_service
}

output "rabbitmq_namespace" {
  description = "RabbitMQ namespace"
  value       = module.rabbitmq_prod.namespace
}

#------------------------------------------------------------------------------
# S3 Buckets Outputs
#------------------------------------------------------------------------------

output "gitlab_artifacts_bucket" {
  description = "GitLab artifacts S3 bucket name"
  value       = module.s3_buckets_prod.gitlab_artifacts_bucket_name
}

output "gitlab_uploads_bucket" {
  description = "GitLab uploads S3 bucket name"
  value       = module.s3_buckets_prod.gitlab_artifacts_bucket_name
}

output "gitlab_s3_policy_arn" {
  description = "IAM policy ARN for GitLab S3 access"
  value       = module.s3_buckets_prod.gitlab_s3_policy_arn
}

#------------------------------------------------------------------------------
# GitLab Outputs (SHARED)
#------------------------------------------------------------------------------

output "gitlab_url" {
  description = "GitLab URL (LoadBalancer)"
  value       = module.gitlab.gitlab_url
}

output "gitlab_namespace" {
  description = "GitLab namespace"
  value       = module.gitlab.namespace
}

output "gitlab_service_name" {
  description = "GitLab webservice service name"
  value       = module.gitlab.webservice_service_name
}

output "gitlab_runner_token_secret" {
  description = "GitLab Runner registration token secret name"
  value       = module.gitlab.runner_token_secret_name
}

output "gitlab_postgresql_database" {
  description = "GitLab PostgreSQL database name"
  value       = "gitlab"
}

output "gitlab_redis_service" {
  description = "GitLab Redis service (PROD)"
  value       = "${module.redis_prod.redis_master_service}.${module.redis_prod.namespace}.svc.cluster.local"
}

#------------------------------------------------------------------------------
# Environment Info
#------------------------------------------------------------------------------

output "environment" {
  description = "Environment name"
  value       = "prod"
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = local.cluster_name
}

output "tags" {
  description = "Common tags applied to resources"
  value       = local.common_tags
}
