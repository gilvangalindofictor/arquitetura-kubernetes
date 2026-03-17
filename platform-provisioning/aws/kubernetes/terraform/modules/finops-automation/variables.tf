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

variable "weekend_shutdown_schedule" {
  description = "Cron expression for weekend shutdown (UTC) - Default: 12:00 AM BRT Saturday (03:00 UTC)"
  type        = string
  default     = "cron(0 3 ? * SAT *)"
}

variable "sunday_shutdown_schedule" {
  description = "Cron expression for Sunday shutdown (UTC) - Default: 20:00 BRT Sunday (23:00 UTC) — prevents manual START residual cost (GAP-LAMBDA-RC2 fix, 2026-03-17)"
  type        = string
  default     = "cron(0 23 ? * SUN *)"
}

variable "enable_automation" {
  description = "Enable EventBridge rules (disable for testing)"
  type        = bool
  default     = false # Disabled by default - enable after manual validation
}

# -----------------------------------------------------------------------------
# FinOps Protection Configuration
# -----------------------------------------------------------------------------

variable "excluded_node_groups" {
  description = "Node groups excluded from scaling to 0 — critical removed to enable weekend scale-to-0 (2026-03-11)"
  type        = list(string)
  default     = ["system"]
}

variable "suspend_autoscaler_on_stop" {
  description = "Suspend Cluster Autoscaler ASG processes during shutdown to prevent DaemonSet re-scaling"
  type        = bool
  default     = true
}

variable "min_system_nodes" {
  description = "Minimum system nodes to keep running (never scale below this)"
  type        = number
  default     = 2

  validation {
    condition     = var.min_system_nodes >= 0 && var.min_system_nodes <= 10
    error_message = "min_system_nodes must be between 0 and 10."
  }
}

variable "min_critical_nodes" {
  description = "Minimum critical nodes to keep running (never scale below this)"
  type        = number
  default     = 2

  validation {
    condition     = var.min_critical_nodes >= 0 && var.min_critical_nodes <= 10
    error_message = "min_critical_nodes must be between 0 and 10."
  }
}

variable "enable_scaling_protection" {
  description = "Enable protection for system/critical node groups (recommended: true)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Lambda Configuration
# -----------------------------------------------------------------------------

variable "lambda_timeout" {
  description = "Lambda timeout in seconds — must be >= 900 for full health-check cycle (NODE_READY + LINKERD + WORKLOAD = up to 1080s worst case, capped at Lambda max of 900s)"
  type        = number
  default     = 900 # 15 minutes (Lambda max) — required for NODE_READY+LINKERD+WORKLOAD health check (was 300)

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

variable "workload_timeout_sec" {
  description = "Seconds to wait for critical workloads (gitlab-webservice, vault) to become Ready in Step 8 health check"
  type        = number
  default     = 480
}

variable "lambda_runtime" {
  description = "Lambda Python runtime version"
  type        = string
  default     = "python3.11"
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
      desired_size = 3  # startup target (autoscaler manages live desired; node-groups.tf max=6)
      max_size     = 6  # aligned with node-groups.tf (was 4, increased 2026-03-05)
    }
    workloads = {
      min_size     = 0  # allows scale-to-zero on shutdown (was 2)
      desired_size = 2  # startup baseline (was 3; autoscaler scales up as needed; node-groups.tf max=9)
      max_size     = 9  # aligned with node-groups.tf (was 6)
    }
    critical = {
      min_size     = 2
      desired_size = 2
      max_size     = 4  # unchanged — correct
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
    Project   = "k8s-platform"
    ManagedBy = "terraform"
    Component = "finops-automation"
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
  # Note: AWS_REGION is automatically provided by Lambda runtime (reserved key)
  lambda_env_vars = {
    ENVIRONMENT               = var.environment
    CLUSTER_NAME              = var.cluster_name
    RDS_INSTANCE_ID           = var.rds_instance_id
    ASG_NAMES                 = join(",", var.asg_names)
    DYNAMODB_TABLE_NAME       = aws_dynamodb_table.scheduler_state.name
    BRASIL_API_URL            = "https://brasilapi.com.br/api/feriados/v1"
    LOG_LEVEL                 = "INFO"
    SNS_TOPIC_ARN             = var.enable_sns_notifications && length(aws_sns_topic.finops_notifications) > 0 ? aws_sns_topic.finops_notifications[0].arn : var.sns_topic_arn
    CIRCUIT_BREAKER_THRESHOLD = tostring(var.circuit_breaker_threshold)
    # FinOps Protection (2026-02-27)
    EXCLUDED_NODE_GROUPS      = join(",", var.excluded_node_groups)
    MIN_SYSTEM_NODES          = tostring(var.min_system_nodes)
    MIN_CRITICAL_NODES        = tostring(var.min_critical_nodes)
    ENABLE_SCALING_PROTECTION   = tostring(var.enable_scaling_protection)
    SUSPEND_AUTOSCALER_ON_STOP  = tostring(var.suspend_autoscaler_on_stop)
    # Node Group startup targets (2026-03-13) — used by lambda_start to restore desired counts post-shutdown
    SYSTEM_DESIRED            = tostring(var.node_groups_config["system"].desired_size)
    WORKLOADS_DESIRED         = tostring(var.node_groups_config["workloads"].desired_size)
    CRITICAL_DESIRED          = tostring(var.node_groups_config["critical"].desired_size)
    NODE_GROUP_NAMES          = join(",", keys(var.node_groups_config))
    # Health check timeouts — gitlab-webservice needs >300s to become Ready from cold start
    WORKLOAD_TIMEOUT_SEC      = tostring(var.workload_timeout_sec)
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
