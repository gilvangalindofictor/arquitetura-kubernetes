# =============================================================================
# Velero DR Multi-Region Module — Variables
# GAP-012: Disaster Recovery Multi-Region
# =============================================================================

# ---------------------------------------------------------------------------
# Cluster / environment identity
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster (used to scope IAM resource names)"
  type        = string
}

variable "environment" {
  description = "Environment name (staging, production). Used in S3 bucket names and tags."
  type        = string
}

# ---------------------------------------------------------------------------
# Region configuration
# ---------------------------------------------------------------------------

variable "primary_region" {
  description = "AWS region for the primary Velero backup bucket (source of CRR)"
  type        = string
  default     = "us-east-1"
}

variable "replica_region" {
  description = "AWS region for the replica Velero backup bucket (CRR destination, DR site)"
  type        = string
  default     = "us-west-2"
}

# ---------------------------------------------------------------------------
# S3 retention
# ---------------------------------------------------------------------------

variable "retention_days_primary" {
  description = "Number of days to retain backup objects in the primary bucket before expiration"
  type        = number
  default     = 30
}

variable "retention_days_replica" {
  description = "Number of days to retain backup objects in the replica bucket (longer for DR compliance)"
  type        = number
  default     = 90
}

# ---------------------------------------------------------------------------
# S3 Cross-Region Replication
# ---------------------------------------------------------------------------

variable "enable_replication_time_control" {
  description = "Enable S3 Replication Time Control (RTC) for a guaranteed 15-minute replication SLA. Adds ~$0.015/GB replicated cost."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Velero IRSA
# ---------------------------------------------------------------------------

variable "velero_namespace" {
  description = "Kubernetes namespace where Velero is installed"
  type        = string
  default     = "velero"
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (for IRSA trust policy)"
  type        = string
}

variable "oidc_provider_url" {
  description = "HTTPS URL of the EKS OIDC issuer (for IRSA trust policy condition)"
  type        = string
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

variable "enable_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for S3 replication failures and pending bytes"
  type        = bool
  default     = true
}

variable "create_sns_topic" {
  description = "When true, creates a dedicated SNS topic for Velero DR alerts. When false, uses existing_sns_topic_arn."
  type        = bool
  default     = true
}

variable "existing_sns_topic_arn" {
  description = "ARN of an existing SNS topic to use for DR alerts. Only used when create_sns_topic = false."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources created by this module"
  type        = map(string)
  default     = {}
}
