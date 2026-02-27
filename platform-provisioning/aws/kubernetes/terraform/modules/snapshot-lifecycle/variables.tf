variable "policy_name_prefix" {
  description = "Prefix for IAM role and policy names (e.g., 'staging', 'production')"
  type        = string
  default     = "k8s-platform"
}

variable "velero_retention_days" {
  description = "Retention period for Velero backup snapshots (days)"
  type        = number
  default     = 30

  validation {
    condition     = var.velero_retention_days >= 7 && var.velero_retention_days <= 365
    error_message = "Velero retention must be between 7 and 365 days."
  }
}

variable "manual_retention_days" {
  description = "Retention period for manual snapshots (days)"
  type        = number
  default     = 14

  validation {
    condition     = var.manual_retention_days >= 1 && var.manual_retention_days <= 180
    error_message = "Manual snapshot retention must be between 1 and 180 days."
  }
}

variable "migration_retention_days" {
  description = "Retention period for migration snapshots (days)"
  type        = number
  default     = 7

  validation {
    condition     = var.migration_retention_days >= 1 && var.migration_retention_days <= 30
    error_message = "Migration snapshot retention must be between 1 and 30 days."
  }
}

variable "common_tags" {
  description = "Common tags applied to all DLM policies and IAM resources"
  type        = map(string)
  default     = {}
}
