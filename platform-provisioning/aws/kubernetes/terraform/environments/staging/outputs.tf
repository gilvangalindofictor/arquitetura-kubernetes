# STAGING Environment Outputs

#------------------------------------------------------------------------------
# PostgreSQL RDS Outputs
#------------------------------------------------------------------------------

output "postgresql_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = module.postgresql_staging.rds_endpoint
}

# TODO: Commented - service_name output not available in postgresql module
# output "postgresql_service_name" {
#   description = "PostgreSQL Kubernetes service name"
#   value       = module.postgresql_staging.service_name
# }

output "postgresql_address" {
  description = "PostgreSQL RDS address (for direct connection)"
  value       = module.postgresql_staging.rds_address
}

output "postgresql_database_name" {
  description = "PostgreSQL database name"
  value       = module.postgresql_staging.rds_database_name
}

output "postgresql_instance_id" {
  description = "RDS instance ID for FinOps automation"
  value       = module.postgresql_staging.db_instance_id
}

#------------------------------------------------------------------------------
# Redis Operator Outputs
#------------------------------------------------------------------------------

output "redis_master_service" {
  description = "Redis master service name"
  value       = module.redis_staging.redis_master_service
}

output "redis_port" {
  description = "Redis port"
  value       = module.redis_staging.redis_port
}

output "redis_namespace" {
  description = "Redis namespace"
  value       = module.redis_staging.namespace
}

output "redis_password_secret_name" {
  description = "Redis password Kubernetes secret name"
  value       = module.redis_staging.redis_password_secret_name
}

#------------------------------------------------------------------------------
# RabbitMQ Operator Outputs
#------------------------------------------------------------------------------

output "rabbitmq_service" {
  description = "RabbitMQ service name"
  value       = module.rabbitmq_staging.rabbitmq_service_internal
}

output "rabbitmq_cluster_name" {
  description = "RabbitMQ cluster name"
  value       = module.rabbitmq_staging.rabbitmq_cluster_name
}

#------------------------------------------------------------------------------
# S3 Buckets Outputs
#------------------------------------------------------------------------------

output "gitlab_artifacts_bucket" {
  description = "GitLab artifacts S3 bucket name"
  value       = module.s3_buckets_staging.gitlab_artifacts_bucket_name
}

output "gitlab_uploads_bucket" {
  description = "GitLab uploads S3 bucket name"
  value       = module.s3_buckets_staging.gitlab_artifacts_bucket_name
}

output "gitlab_s3_policy_arn" {
  description = "IAM policy ARN for GitLab S3 access"
  value       = module.s3_buckets_staging.gitlab_s3_policy_arn
}

#------------------------------------------------------------------------------
# Vault + External Secrets Outputs
#------------------------------------------------------------------------------

# output "vault_k8s_auth_path" {
#   description = "Vault Kubernetes auth mount path"
#   value       = module.vault_config_staging.vault_k8s_auth_path
# }
#
# output "vault_eso_reader_role" {
#   description = "Vault role for ESO authentication"
#   value       = module.vault_config_staging.eso_reader_role
# }
#
# output "vault_keycloak_secret_path" {
#   description = "Vault path for Keycloak PostgreSQL credentials"
#   value       = module.vault_config_staging.keycloak_secret_path
# }

#------------------------------------------------------------------------------
# Keycloak SSO Platform Outputs
#------------------------------------------------------------------------------

output "keycloak_url" {
  description = "Keycloak URL for OIDC integration"
  value       = module.keycloak_staging.keycloak_url
}

output "keycloak_realm_url" {
  description = "Keycloak master realm URL (OIDC issuer)"
  value       = module.keycloak_staging.realm_url
}

output "keycloak_namespace" {
  description = "Keycloak namespace"
  value       = module.keycloak_staging.namespace
}

output "keycloak_admin_password_secret" {
  description = "Keycloak admin password K8s secret name"
  value       = module.keycloak_staging.admin_password_secret
  sensitive   = true
}

#------------------------------------------------------------------------------
# FinOps Automation Outputs
#------------------------------------------------------------------------------

output "finops_lambda_start_function_name" {
  description = "FinOps Lambda start function name"
  value       = module.finops_automation_staging.lambda_start_function_name
}

output "finops_lambda_stop_function_name" {
  description = "FinOps Lambda stop function name"
  value       = module.finops_automation_staging.lambda_stop_function_name
}

output "finops_eventbridge_startup_rule" {
  description = "EventBridge startup rule ARN"
  value       = module.finops_automation_staging.eventbridge_rule_startup_arn
}

output "finops_eventbridge_shutdown_rule" {
  description = "EventBridge shutdown rule ARN"
  value       = module.finops_automation_staging.eventbridge_rule_shutdown_arn
}

output "finops_sns_topic_arn" {
  description = "SNS topic ARN for FinOps alerts"
  value       = aws_sns_topic.finops_alerts_staging.arn
}

#------------------------------------------------------------------------------
# Environment Info
#------------------------------------------------------------------------------

output "environment" {
  description = "Environment name"
  value       = "staging"
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = local.cluster_name
}

output "tags" {
  description = "Common tags applied to resources"
  value       = local.common_tags
}

#------------------------------------------------------------------------------
# Velero DR Outputs (V-008)
#------------------------------------------------------------------------------

output "velero_bucket_name" {
  description = "Velero backup S3 bucket name"
  value       = module.velero_dr_staging.bucket_name
}

output "velero_role_arn" {
  description = "IAM role ARN for Velero service account (IRSA)"
  value       = module.velero_dr_staging.velero_role_arn
}
