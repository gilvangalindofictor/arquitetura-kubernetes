# 💰 FinOps Automation - Variables
# Multi-agent validated: AWS, Terraform, FinOps, Security specialists

variable "environment" {
  description = "Environment name (staging or production)"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be staging or production"
  }
}

variable "cluster_name" {
  description = "EKS cluster name to manage"
  type        = string
}

variable "rds_instance_identifier" {
  description = "RDS instance identifier to start/stop"
  type        = string
}

variable "asg_names" {
  description = "List of Auto Scaling Group names to scale"
  type        = list(string)
}

variable "shutdown_schedule" {
  description = "Cron expression for shutdown (e.g., 'cron(0 21 ? * MON-FRI *)'  = 18h BRT)"
  type        = string
}

variable "startup_schedule" {
  description = "Cron expression for startup (e.g., 'cron(0 11 ? * MON-FRI *)' = 8h BRT)"
  type        = string
}

variable "circuit_breaker_threshold" {
  description = "Number of consecutive failures before circuit opens"
  type        = number
  default     = 3
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds (recommend 15 min = 900s for RDS startup)"
  type        = number
  default     = 900
}

variable "lambda_memory" {
  description = "Lambda memory in MB"
  type        = number
  default     = 512
}

variable "lambda_runtime" {
  description = "Lambda Python runtime version"
  type        = string
  default     = "python3.12"
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period"
  type        = number
  default     = 30
}

variable "alarm_startup_duration_threshold" {
  description = "CloudWatch Alarm threshold for startup duration (seconds)"
  type        = number
  default     = 600 # 10 minutes
}

variable "enable_brasilapi_holidays" {
  description = "Enable BrasilAPI integration for Brazilian holidays detection"
  type        = bool
  default     = true
}

variable "health_check_enabled" {
  description = "Enable health checks post-startup (DB connections, GitLab jobs)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources (Security compliance: 8 mandatory tags)"
  type        = map(string)
  default = {
    Project            = "FinOps-Automation"
    ManagedBy          = "Terraform"
    SecurityReview     = "2026-01-30"
    Compliance         = "LGPD-OK"
    DataClassification = "Internal"
  }
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
}
