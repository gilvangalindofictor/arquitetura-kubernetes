# STAGING Environment Outputs

#------------------------------------------------------------------------------
# PostgreSQL RDS Outputs
#------------------------------------------------------------------------------

output "postgresql_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = module.postgresql_staging.rds_endpoint
}

# NOTE: postgresql_service_name output is not exposed here because the postgresql
# module does not export a service_name output (outputs.tf:38 is commented out).
# RDS is accessed directly via postgresql_address (CNAME) — no K8s service wrapper needed.

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
  description = "Velero primary backup S3 bucket name (us-east-1)"
  value       = module.velero_dr_staging.bucket_name
}

output "velero_role_arn" {
  description = "IAM role ARN for Velero service account (IRSA) — has R/W on primary and R/O on replica"
  value       = module.velero_dr_staging.velero_role_arn
}

#------------------------------------------------------------------------------
# GAP-012: DR Multi-Region Outputs
#------------------------------------------------------------------------------

output "velero_primary_bucket_name" {
  description = "GAP-012: Velero primary S3 bucket name (us-east-1, source of CRR)"
  value       = module.velero_dr_staging.primary_bucket_name
}

output "velero_primary_bucket_arn" {
  description = "GAP-012: Velero primary S3 bucket ARN"
  value       = module.velero_dr_staging.primary_bucket_arn
}

output "velero_replica_bucket_name" {
  description = "GAP-012: Velero replica S3 bucket name (us-west-2, CRR destination)"
  value       = module.velero_dr_staging.replica_bucket_name
}

output "velero_replica_bucket_arn" {
  description = "GAP-012: Velero replica S3 bucket ARN"
  value       = module.velero_dr_staging.replica_bucket_arn
}

output "velero_replication_role_arn" {
  description = "GAP-012: IAM role ARN used by S3 CRR for replication"
  value       = module.velero_dr_staging.replication_role_arn
}

output "rds_replica_endpoint" {
  description = "GAP-012: PostgreSQL DR replica endpoint (us-west-2). Available after dr_enable_rds_replica = true."
  value       = var.dr_enable_rds_replica ? module.rds_replica_staging[0].replica_endpoint : "not-provisioned"
}

output "rds_replica_instance_id" {
  description = "GAP-012: RDS read replica instance identifier. Use in 'aws rds promote-read-replica' during failover."
  value       = var.dr_enable_rds_replica ? module.rds_replica_staging[0].replica_instance_id : "not-provisioned"
}

output "rds_replica_cloudwatch_alarms" {
  description = "GAP-012: Map of CloudWatch alarm ARNs for the RDS read replica (replication_lag, storage_space_low, replica_unavailable)"
  value       = var.dr_enable_rds_replica ? module.rds_replica_staging[0].cloudwatch_alarm_arns : {}
}

#------------------------------------------------------------------------------
# WAF v2 + DDoS Protection Outputs (GAP-010)
#------------------------------------------------------------------------------

output "waf_web_acl_arn" {
  description = "ARN of the WAF v2 WebACL protecting the iPaaS ALB. Use this for cross-account sharing or additional resource associations."
  value       = module.waf_staging.waf_web_acl_arn
}

output "waf_web_acl_id" {
  description = "UUID of the WAF v2 WebACL. Required for AWS Console navigation and CLI queries."
  value       = module.waf_staging.waf_web_acl_id
}

output "waf_web_acl_capacity" {
  description = "Current WCU (WAF Capacity Units) used by the WebACL. Default account limit: 1500 WCU. Alert if >80%."
  value       = module.waf_staging.waf_web_acl_capacity
}

output "waf_log_bucket_name" {
  description = "S3 bucket name receiving WAF access logs (aws-waf-logs-* prefix)."
  value       = module.waf_staging.waf_log_bucket_name
}

output "waf_log_bucket_arn" {
  description = "S3 bucket ARN for WAF logs. Use to configure S3 event notifications or Athena queries."
  value       = module.waf_staging.waf_log_bucket_arn
}

output "waf_cloudwatch_metric_name" {
  description = "CloudWatch metric namespace for WAF WebACL. Use to build dashboards in the observability module."
  value       = module.waf_staging.waf_cloudwatch_metric_name
}

output "waf_rules_summary" {
  description = "Map of active WAF rules and their configuration (for audit and documentation)."
  value       = module.waf_staging.waf_rules_summary
}

output "waf_additional_alb_association_ids" {
  description = "Map of WAF WebACL association IDs for additional ALBs (GitLab, Keycloak). Codified from CLI associations (2026-03-18)."
  value       = module.waf_staging.waf_additional_alb_association_ids
}

#------------------------------------------------------------------------------
# GAP-011: Linkerd Service Mesh Outputs
# RE-ENABLED (2026-03-03) — dashboard blocker resolved, module uncommented
#------------------------------------------------------------------------------

output "linkerd_namespace" {
  description = "Kubernetes namespace where the Linkerd control plane is deployed."
  value       = module.linkerd.linkerd_namespace
}

output "linkerd_viz_url" {
  description = "Internal cluster URL for the Linkerd dashboard (port-forward to access)."
  value       = module.linkerd.linkerd_viz_url
}

output "linkerd_tap_api_url" {
  description = "Internal cluster URL for the Linkerd Tap API (real-time L7 traffic inspection)."
  value       = module.linkerd.linkerd_tap_api_url
}

output "linkerd_proxy_injector_webhook_url" {
  description = "Internal URL of the Linkerd proxy-injector MutatingWebhookConfiguration endpoint."
  value       = module.linkerd.linkerd_proxy_injector_webhook_url
}

output "linkerd_trust_anchor_certificate" {
  description = "PEM-encoded Linkerd trust anchor certificate. SENSITIVE — store in Vault at secret/linkerd/pki."
  value       = module.linkerd.trust_anchor_certificate
  sensitive   = true
}

output "linkerd_control_plane_version" {
  description = "Deployed Linkerd control-plane Helm chart version."
  value       = module.linkerd.linkerd_control_plane_version
}

output "linkerd_proxy_injected_namespaces" {
  description = "List of namespaces annotated for automatic Linkerd proxy injection."
  value       = module.linkerd.proxy_injected_namespaces
}

#------------------------------------------------------------------------------
# Argo Rollouts Outputs (CICD-005)
# TEMPORARILY DISABLED (2026-02-26) — module.argo_rollouts_staging commented in main.tf
#------------------------------------------------------------------------------
#
# output "argo_rollouts_release_name" {
#   description = "Helm release name for Argo Rollouts"
#   value       = module.argo_rollouts_staging.release_name
# }
#
# output "argo_rollouts_release_status" {
#   description = "Argo Rollouts Helm release status"
#   value       = module.argo_rollouts_staging.release_status
# }
#
# output "argo_rollouts_version" {
#   description = "Argo Rollouts Helm chart version deployed"
#   value       = module.argo_rollouts_staging.release_version
# }
#
# output "argo_rollouts_namespace" {
#   description = "Namespace where Argo Rollouts is deployed"
#   value       = module.argo_rollouts_staging.namespace
# }
#
# output "argo_rollouts_dashboard_access" {
#   description = "Command to access Argo Rollouts Dashboard via port-forward"
#   value       = module.argo_rollouts_staging.dashboard_access_command
# }
#
# output "argo_rollouts_analysis_templates_guide" {
#   description = "Instructions for deploying AnalysisTemplate library to application namespaces"
#   value       = module.argo_rollouts_staging.analysis_templates_deploy_guide
# }
