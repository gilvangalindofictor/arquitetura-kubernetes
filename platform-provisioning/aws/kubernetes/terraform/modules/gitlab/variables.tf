# =============================================================================
# GitLab Module Variables - Marco 3 Fase 2
# Baseado em análise Terraform Specialist (Agent a3bcddf)
# =============================================================================

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace Kubernetes para GitLab"
  type        = string
  default     = "gitlab"
}

variable "environment" {
  description = "Environment (prod, staging, dev)"
  type        = string
  default     = "prod"
}

# =============================================================================
# GitLab Configuration
# =============================================================================

variable "gitlab_edition" {
  description = "GitLab edition (ce for Community, ee for Enterprise)"
  type        = string
  default     = "ce"

  validation {
    condition     = contains(["ce", "ee"], var.gitlab_edition)
    error_message = "GitLab edition must be 'ce' or 'ee'."
  }
}

variable "gitlab_version" {
  description = "GitLab Helm chart version"
  type        = string
  default     = "8.7.0"
}

variable "gitlab_replicas" {
  description = "Number of GitLab webservice replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.gitlab_replicas >= 1 && var.gitlab_replicas <= 10
    error_message = "GitLab replicas must be between 1 and 10."
  }
}

variable "gitlab_runner_replicas" {
  description = "Number of GitLab Runner replicas"
  type        = number
  default     = 2
}

# =============================================================================
# TLS Configuration (ADR-021 Fase 1: disabled)
# =============================================================================

variable "enable_tls" {
  description = "Enable TLS for GitLab (ADR-021 Fase 1: false)"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Domain name for GitLab (empty for Fase 1)"
  type        = string
  default     = ""
}

# =============================================================================
# External Dependencies (outputs de outros módulos)
# =============================================================================

variable "postgresql_host" {
  description = "PostgreSQL host (RDS endpoint or ExternalName service)"
  type        = string
}

variable "postgresql_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "postgresql_database" {
  description = "PostgreSQL database name"
  type        = string
  default     = "gitlab"
}

variable "postgresql_username" {
  description = "PostgreSQL username"
  type        = string
  default     = "gitlab_user"
}

variable "postgresql_password_secret" {
  description = "Kubernetes secret name containing PostgreSQL password"
  type        = string
}

variable "redis_host" {
  description = "Redis host (ClusterIP service from Redis Operator)"
  type        = string
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "redis_password_secret" {
  description = "Kubernetes secret name containing Redis password"
  type        = string
}

# =============================================================================
# S3 Configuration
# =============================================================================

variable "s3_artifacts_bucket" {
  description = "S3 bucket name for GitLab artifacts"
  type        = string
}

variable "s3_uploads_bucket" {
  description = "S3 bucket name for GitLab uploads"
  type        = string
}

variable "s3_policy_arn" {
  description = "IAM policy ARN for S3 access (from s3-buckets module)"
  type        = string
}

# =============================================================================
# Monitoring
# =============================================================================

variable "enable_monitoring" {
  description = "Enable Prometheus ServiceMonitor"
  type        = bool
  default     = true
}

# =============================================================================
# Common Tags
# =============================================================================

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
