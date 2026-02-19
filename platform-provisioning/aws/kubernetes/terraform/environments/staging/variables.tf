# STAGING Environment Variables Definition

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
  default     = "db.t3.micro"
}

variable "postgresql_allocated_storage" {
  description = "Initial storage allocation in GB"
  type        = number
  default     = 20
}

variable "postgresql_max_allocated_storage" {
  description = "Maximum storage allocation in GB"
  type        = number
  default     = 50
}

#------------------------------------------------------------------------------
# Redis Variables
#------------------------------------------------------------------------------

variable "redis_replicas" {
  description = "Number of Redis replicas"
  type        = number
  default     = 1
}

variable "redis_pvc_size" {
  description = "PVC size for Redis"
  type        = string
  default     = "5Gi"
}

#------------------------------------------------------------------------------
# RabbitMQ Variables
#------------------------------------------------------------------------------

variable "rabbitmq_replicas" {
  description = "Number of RabbitMQ replicas"
  type        = number
  default     = 1
}

variable "rabbitmq_pvc_size" {
  description = "PVC size for RabbitMQ"
  type        = string
  default     = "5Gi"
}

#------------------------------------------------------------------------------
# FinOps Variables
#------------------------------------------------------------------------------

variable "finops_alert_email" {
  description = "Email for FinOps alerts"
  type        = string
}

#------------------------------------------------------------------------------
# Vault Variables
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

# Grafana OIDC — migrado de hardcode para Vault KV (P0-A ESO gap, 2026-02-19)
variable "grafana_oidc_client_secret" {
  description = "Keycloak client secret for Grafana OIDC (migrated from hardcode to Vault KV secret/grafana/oidc)"
  type        = string
  sensitive   = true
  default     = ""
}

# SonarQube PostgreSQL — resolve TODO sonarqube/main.tf (P0-B ESO gap, 2026-02-19)
variable "sonarqube_postgresql_password" {
  description = "SonarQube PostgreSQL user password (from SM staging/postgresql/sonarqube-password)"
  type        = string
  sensitive   = true
  default     = ""
}

# Harbor PostgreSQL — migrado de AWS SM para Vault KV (P1 ESO gap, 2026-02-19)
variable "harbor_postgresql_password" {
  description = "Harbor PostgreSQL user password (migrated from AWS SM staging/postgresql/gitlab-password to Vault KV secret/harbor/postgresql)"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# Keycloak Variables
#------------------------------------------------------------------------------

variable "keycloak_postgresql_password" {
  description = "Keycloak PostgreSQL password (stored in Vault)"
  type        = string
  sensitive   = true
  default     = "" # If empty, random password will be generated
}
