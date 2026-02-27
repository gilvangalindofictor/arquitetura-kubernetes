# =============================================================================
# RDS Monitoring Module: Input Variables
# =============================================================================

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

variable "rds_instance_identifier" {
  description = "RDS instance identifier to monitor"
  type        = string

  validation {
    condition     = length(var.rds_instance_identifier) > 0
    error_message = "RDS instance identifier cannot be empty."
  }
}

variable "alert_emails" {
  description = "List of email addresses for alert notifications"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "At least one alert email must be provided."
  }
}

variable "kms_key_id" {
  description = "KMS key ID for SNS topic encryption (optional)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Performance Alert Thresholds
# =============================================================================

variable "enable_performance_alerts" {
  description = "Enable performance monitoring alerts (CPU, connections, storage, latency)"
  type        = bool
  default     = true
}

variable "cpu_threshold" {
  description = "CPU utilization threshold percentage (trigger alert when exceeded)"
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_threshold >= 0 && var.cpu_threshold <= 100
    error_message = "CPU threshold must be between 0 and 100."
  }
}

variable "max_connections_override" {
  description = "Override max_connections value (default: auto-detect from instance class). Alert triggers at 80% of this value."
  type        = number
  default     = null
}

variable "storage_threshold_gb" {
  description = "Free storage threshold in GB (trigger alert when below this value)"
  type        = number
  default     = 20

  validation {
    condition     = var.storage_threshold_gb > 0
    error_message = "Storage threshold must be greater than 0."
  }
}

variable "latency_threshold_ms" {
  description = "Read/Write latency threshold in milliseconds (trigger alert when exceeded)"
  type        = number
  default     = 50

  validation {
    condition     = var.latency_threshold_ms > 0
    error_message = "Latency threshold must be greater than 0."
  }
}

# =============================================================================
# Documentation & Runbooks
# =============================================================================

variable "runbook_base_url" {
  description = "Base URL for runbook documentation (used in alarm descriptions)"
  type        = string
  default     = "https://github.com/<org>/<repo>/docs/runbooks"
}
