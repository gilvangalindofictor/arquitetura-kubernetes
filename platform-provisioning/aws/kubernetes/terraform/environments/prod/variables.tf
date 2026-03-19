# PROD Environment Variables Definition

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for resources"
  type        = string
}

variable "state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs for security group rules"
  type        = list(string)
}

variable "base_tags" {
  description = "Base tags applied to all resources"
  type        = map(string)
}

#------------------------------------------------------------------------------
# PostgreSQL RDS Variables
#------------------------------------------------------------------------------

variable "postgresql_instance_class" {
  description = "RDS instance class for PostgreSQL"
  type        = string
  default     = "db.t3.medium"
}

variable "postgresql_allocated_storage" {
  description = "Initial storage allocation in GB"
  type        = number
  default     = 100
}

variable "postgresql_max_allocated_storage" {
  description = "Maximum storage allocation in GB"
  type        = number
  default     = 500
}

#------------------------------------------------------------------------------
# Redis Variables
#------------------------------------------------------------------------------

variable "redis_replicas" {
  description = "Number of Redis replicas"
  type        = number
  default     = 3
}

variable "redis_pvc_size" {
  description = "PVC size for Redis"
  type        = string
  default     = "10Gi"
}

#------------------------------------------------------------------------------
# RabbitMQ Variables
#------------------------------------------------------------------------------

variable "rabbitmq_replicas" {
  description = "Number of RabbitMQ replicas"
  type        = number
  default     = 3
}

variable "rabbitmq_pvc_size" {
  description = "PVC size for RabbitMQ"
  type        = string
  default     = "10Gi"
}

#------------------------------------------------------------------------------
# GitLab Variables
#------------------------------------------------------------------------------

variable "gitlab_replicas" {
  description = "Number of GitLab webservice replicas"
  type        = number
  default     = 2
}

variable "gitlab_runner_replicas" {
  description = "Number of GitLab Runner replicas"
  type        = number
  default     = 2
}

#------------------------------------------------------------------------------
# Vault Variables (P0-07: equalizados com staging)
#------------------------------------------------------------------------------

variable "vault_root_token" {
  description = "Vault root token for initial configuration (from init or K8s secret)"
  type        = string
  sensitive   = true
}

variable "vault_oidc_client_secret" {
  description = "Keycloak client secret for Vault OIDC SSO (from Keycloak vault client)"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# Keycloak Variables (P0-07: equalizados com staging)
#------------------------------------------------------------------------------

variable "keycloak_postgresql_password" {
  description = "Keycloak PostgreSQL password (stored in Vault)"
  type        = string
  sensitive   = true
  default     = "" # If empty, random password will be generated
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password for mrparkers/keycloak provider"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# Grafana Variables (P0-07: equalizados com staging)
#------------------------------------------------------------------------------

variable "grafana_oidc_client_secret" {
  description = "Keycloak client secret for Grafana OIDC (Vault KV secret/grafana/oidc)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_admin_password" {
  description = "Grafana admin password (seeds Vault KV secret/grafana/admin)"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# Harbor Variables (P0-07: equalizados com staging)
#------------------------------------------------------------------------------

variable "harbor_postgresql_password" {
  description = "Harbor PostgreSQL user password (Vault KV secret/harbor/postgresql)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "harbor_admin_password" {
  description = "Harbor admin password (Vault KV secret/harbor/admin)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "harbor_redis_password" {
  description = "Harbor Redis password (Vault KV secret/harbor/redis)"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# ArgoCD Variables (P0-07: equalizados com staging)
#------------------------------------------------------------------------------

variable "argocd_postgresql_password" {
  description = "ArgoCD PostgreSQL user password (Vault KV secret/argocd/postgresql)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "argocd_oidc_client_secret" {
  description = "Keycloak client secret for ArgoCD OIDC (Vault KV secret/argocd/oidc)"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# SonarQube Variables (P0-07: equalizados com staging)
#------------------------------------------------------------------------------

variable "sonarqube_postgresql_password" {
  description = "SonarQube PostgreSQL user password"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# FinOps Variables (P0-07: equalizados com staging)
#------------------------------------------------------------------------------

variable "finops_alert_email" {
  description = "Email for FinOps alerts"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# WAF v2 + DDoS Protection Variables (P0-07: equalizados com staging)
#------------------------------------------------------------------------------

variable "waf_alb_arn" {
  description = "ARN of the ALB to associate with WAF. Leave empty to auto-resolve via data.aws_lb tag lookup."
  type        = string
  default     = ""
}

variable "waf_rate_limit" {
  description = "Maximum requests per IP per 5-minute window before WAF rate-limit (BLOCK 429). Production: 500."
  type        = number
  default     = 500
}

variable "waf_enable_geo_blocking" {
  description = "Enable WAF geographic blocking rule"
  type        = bool
  default     = true
}

variable "waf_blocked_countries" {
  description = "ISO 3166-1 alpha-2 country codes to block at WAF layer"
  type        = list(string)
  default     = ["CN", "RU", "KP"]
}

variable "waf_log_retention_days" {
  description = "Number of days to retain WAF log objects in the S3 bucket"
  type        = number
  default     = 90
}
