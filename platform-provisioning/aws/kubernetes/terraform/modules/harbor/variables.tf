# Harbor Module Variables

variable "cluster_name" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "namespace" {
  type    = string
  default = "harbor"
}

variable "oidc_provider_arn" {
  type = string
}

variable "harbor_chart_version" {
  type    = string
  default = "1.14.0"
}

variable "s3_bucket_name" {
  description = "S3 bucket for Harbor images"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN for Harbor images"
  type        = string
}

variable "postgresql_host" {
  type = string
}

variable "postgresql_port" {
  type    = number
  default = 5432
}

variable "postgresql_database" {
  type    = string
  default = "harbor"
}

variable "postgresql_username" {
  type    = string
  default = "harbor_user"
}

variable "postgresql_password" {
  description = "Harbor PostgreSQL password (from Vault KV secret/harbor/postgresql via vault-config module)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "redis_host" {
  type = string
}

variable "redis_port" {
  type    = number
  default = 6379
}

variable "redis_password_secret" {
  description = "K8s secret name containing Redis password"
  type        = string
}

variable "storage_class" {
  type    = string
  default = "gp2"
}

variable "enable_trivy" {
  type    = bool
  default = true
}

variable "enable_monitoring" {
  type    = bool
  default = true
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

# -----------------------------------------------------------------------------
# Ingress
# -----------------------------------------------------------------------------

variable "ingress_enabled" {
  description = "Habilitar ALB Ingress para o Harbor"
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Hostname para o Ingress do Harbor (e.g., harbor.staging.internal)"
  type        = string
  default     = ""
}

variable "ingress_group_name" {
  description = "ALB Ingress group name para compartilhar ALB entre serviços"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# OIDC / SSO (Keycloak)
# -----------------------------------------------------------------------------

variable "enable_oidc" {
  description = "Enable OIDC authentication via Keycloak"
  type        = bool
  default     = false
}

variable "oidc_endpoint" {
  description = "Keycloak OIDC endpoint (realm URL, cluster-internal)"
  type        = string
  default     = ""
}

variable "oidc_admin_group" {
  description = "OIDC group mapped to Harbor admin role"
  type        = string
  default     = "harbor-admins"
}

# ECR Pull-Through Cache
variable "ecr_registry" {
  description = "ECR registry prefix for pull-through cache (e.g. 891377105802.dkr.ecr.us-east-1.amazonaws.com). Empty string uses upstream registries."
  type        = string
  default     = ""
}
