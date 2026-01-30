# =============================================================================
# Variables: FinOps Scheduler Module
# =============================================================================
# Author: DevOps Team
# Date: 2026-01-30
# Framework: executor-terraform.md (Multi-Agent Validation)
# =============================================================================

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "k8s-platform-prod"
}

variable "rds_instance_id" {
  description = "RDS instance identifier"
  type        = string
  default     = "k8s-platform-prod-postgresql"
}

variable "asg_names" {
  description = "Auto Scaling Group names (regular nodes)"
  type        = list(string)
  default     = ["eks-k8s-platform-prod-regular-*"]
}

# -----------------------------------------------------------------------------
# Schedule Configuration
# -----------------------------------------------------------------------------

variable "startup_schedule" {
  description = "Cron expression for startup (UTC) - Default: 8:00 AM BRT (11:00 UTC)"
  type        = string
  default     = "cron(0 11 ? * MON-FRI *)"
}

variable "shutdown_schedule" {
  description = "Cron expression for shutdown (UTC) - Default: 6:00 PM BRT (21:00 UTC)"
  type        = string
  default     = "cron(0 21 ? * MON-FRI *)"
}

variable "enable_automation" {
  description = "Enable EventBridge rules (disable for testing)"
  type        = bool
  default     = false # Disabled by default - enable after manual validation
}

# -----------------------------------------------------------------------------
# Lambda Configuration
# -----------------------------------------------------------------------------

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 300 # 5 minutes

  validation {
    condition     = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory" {
  description = "Lambda memory in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory >= 128 && var.lambda_memory <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda Python runtime version"
  type        = string
  default     = "python3.12"
}

# -----------------------------------------------------------------------------
# Node Groups Configuration
# -----------------------------------------------------------------------------

variable "node_groups_config" {
  description = "Node groups scaling configuration"
  type = map(object({
    min_size     = number
    desired_size = number
    max_size     = number
  }))
  default = {
    system = {
      min_size     = 2
      desired_size = 2
      max_size     = 4
    }
    workloads = {
      min_size     = 2
      desired_size = 3
      max_size     = 6
    }
    critical = {
      min_size     = 2
      desired_size = 2
      max_size     = 4
    }
  }
}

# -----------------------------------------------------------------------------
# Circuit Breaker Configuration
# -----------------------------------------------------------------------------

variable "circuit_breaker_threshold" {
  description = "Number of consecutive failures before opening circuit breaker"
  type        = number
  default     = 3

  validation {
    condition     = var.circuit_breaker_threshold >= 1 && var.circuit_breaker_threshold <= 10
    error_message = "Circuit breaker threshold must be between 1 and 10."
  }
}

variable "circuit_breaker_reset_hours" {
  description = "Hours to wait before attempting to close circuit breaker"
  type        = number
  default     = 24
}

# -----------------------------------------------------------------------------
# Monitoring Configuration
# -----------------------------------------------------------------------------

variable "sns_topic_arn" {
  description = "SNS topic ARN for notifications (optional, leave empty to create one)"
  type        = string
  default     = ""
}

variable "enable_sns_notifications" {
  description = "Enable SNS topic creation and notifications"
  type        = bool
  default     = false # Disabled by default - enable when ready for notifications
}

variable "notification_emails" {
  description = "List of email addresses to receive FinOps notifications"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.notification_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All notification_emails must be valid email addresses."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for startup/shutdown failures"
  type        = bool
  default     = true
}

variable "startup_duration_threshold" {
  description = "Alarm threshold for startup duration in seconds"
  type        = number
  default     = 600 # 10 minutes
}

# -----------------------------------------------------------------------------
# Tags (Base + Security)
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Base tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "k8s-platform"
    ManagedBy   = "terraform"
    Component   = "finops-automation"
  }
}

variable "owner_email" {
  description = "Owner email for operational contact"
  type        = string
  default     = "devops-team@company.com"
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = "Infrastructure-Optimization"
}

# -----------------------------------------------------------------------------
# Local Variables (Security Tags - Compliance Requirement)
# -----------------------------------------------------------------------------

locals {
  # Security tags (mandatory for compliance - ADR-024)
  security_tags = merge(var.tags, {
    Environment        = var.environment
    SecurityReview     = "2026-01-30" # Multi-agent validation date
    Compliance         = "LGPD-OK"    # LGPD compliance validated
    DataClassification = "Internal"   # Circuit breaker state = internal data
    CriticalityTier    = "Tier3"      # Non-critical automation (can fail gracefully)
    Owner              = var.owner_email
    CostCenter         = var.cost_center
    Framework          = "executor-terraform.md" # Multi-agent framework used
  })

  # SNS alarm actions (use created topic or external topic ARN)
  sns_alarm_actions = var.enable_sns_notifications && length(aws_sns_topic.finops_notifications) > 0 ? [aws_sns_topic.finops_notifications[0].arn] : (var.sns_topic_arn != "" ? [var.sns_topic_arn] : [])

  # Lambda common environment variables
  lambda_env_vars = {
    ENVIRONMENT           = var.environment
    CLUSTER_NAME          = var.cluster_name
    RDS_INSTANCE_ID       = var.rds_instance_id
    ASG_NAMES             = join(",", var.asg_names)
    DYNAMODB_TABLE_NAME   = aws_dynamodb_table.scheduler_state.name
    BRASIL_API_URL        = "https://brasilapi.com.br/api/feriados/v1"
    LOG_LEVEL             = "INFO"
    SNS_TOPIC_ARN         = var.enable_sns_notifications && length(aws_sns_topic.finops_notifications) > 0 ? aws_sns_topic.finops_notifications[0].arn : var.sns_topic_arn
    CIRCUIT_BREAKER_THRESHOLD = tostring(var.circuit_breaker_threshold)
    AWS_REGION            = data.aws_region.current.name
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Outputs (for debugging)
# -----------------------------------------------------------------------------

output "security_tags" {
  description = "Security tags applied to all resources"
  value       = local.security_tags
}

output "lambda_env_vars" {
  description = "Lambda environment variables (sensitive values redacted)"
  value = {
    for k, v in local.lambda_env_vars : k => (
      contains(["SNS_TOPIC_ARN", "RDS_INSTANCE_ID"], k) ? "REDACTED" : v
    )
  }
}
