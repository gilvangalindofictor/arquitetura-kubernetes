# =============================================================================
# WAF Module Variables
# GAP-010: AWS WAF v2 + DDoS Protection for iPaaS ALB
# =============================================================================

#------------------------------------------------------------------------------
# Core / Identity
#------------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment (staging, production). Used for resource naming and tags."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be one of: staging, production."
  }
}

variable "cluster_name" {
  description = "EKS cluster name. Used for resource naming and tags."
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to all resources in the module."
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# ALB Association
#------------------------------------------------------------------------------

variable "alb_arn" {
  description = "ARN of the Application Load Balancer (ALB Ingress Controller) to associate with WAF WebACL. Format: arn:aws:elasticloadbalancing:<region>:<account>:loadbalancer/app/<name>/<id>"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:elasticloadbalancing:", var.alb_arn))
    error_message = "alb_arn must be a valid ALB ARN starting with arn:aws:elasticloadbalancing:."
  }
}

#------------------------------------------------------------------------------
# Additional ALB Associations
#------------------------------------------------------------------------------

variable "additional_alb_arns" {
  description = "Map of additional ALB ARNs to associate with the same WAF WebACL. Key = logical name (for Terraform addressing), Value = ALB ARN. Example: { gitlab = \"arn:aws:elasticloadbalancing:...\" }"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.additional_alb_arns : can(regex("^arn:aws:elasticloadbalancing:", v))])
    error_message = "All values in additional_alb_arns must be valid ALB ARNs starting with arn:aws:elasticloadbalancing:."
  }
}

#------------------------------------------------------------------------------
# Rate Limiting (Rule Priority 10)
#------------------------------------------------------------------------------

variable "rate_limit" {
  description = "Maximum number of requests allowed per IP within a 5-minute evaluation window before the rule BLOCK action triggers. AWS WAF minimum is 100."
  type        = number
  default     = 1000

  validation {
    condition     = var.rate_limit >= 100
    error_message = "rate_limit must be >= 100 (AWS WAF v2 minimum for RateBasedStatement)."
  }
}

#------------------------------------------------------------------------------
# Geographic Blocking (Rule Priority 20)
#------------------------------------------------------------------------------

variable "blocked_countries" {
  description = "List of ISO 3166-1 alpha-2 country codes to block at the WAF layer (GeoMatchStatement). Default: CN (China), RU (Russia), KP (North Korea) — historically high volume of malicious traffic."
  type        = list(string)
  default     = ["CN", "RU", "KP"]

  validation {
    condition     = length(var.blocked_countries) > 0
    error_message = "blocked_countries must contain at least one country code. Use an empty list to disable geo-blocking by setting enable_geo_blocking = false instead."
  }
}

variable "enable_geo_blocking" {
  description = "Toggle geographic blocking rule. Set to false to disable country-based blocking without removing the variable configuration."
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Managed Rule Groups (Priorities 30-50)
#------------------------------------------------------------------------------

variable "enable_owasp_common_ruleset" {
  description = "Enable AWS Managed Rules - Common Rule Set (OWASP Top 10 protections: XSS, LFI, RFI, SSRF, size restrictions). Priority 30."
  type        = bool
  default     = true
}

variable "enable_sqli_ruleset" {
  description = "Enable AWS Managed Rules - SQL Database Rule Set (SQLi protection for all SQL engines). Priority 40."
  type        = bool
  default     = true
}

variable "enable_known_bad_inputs_ruleset" {
  description = "Enable AWS Managed Rules - Known Bad Inputs Rule Set (Log4SHELL, SSRF, traversal patterns). Priority 50."
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# WAF Logging
#------------------------------------------------------------------------------

variable "enable_logging" {
  description = "Enable WAF logging to S3. Required for audit trails, incident response, and cost anomaly analysis."
  type        = bool
  default     = true
}

variable "log_destination_arn" {
  description = "S3 bucket ARN for WAF logs. Required when enable_logging = true. Format: arn:aws:s3:::bucket-name. Note: WAF v2 requires the bucket name to start with 'aws-waf-logs-'."
  type        = string
  default     = ""
}

variable "create_log_bucket" {
  description = "Create a dedicated S3 bucket for WAF logs. When true, the bucket is named 'aws-waf-logs-<cluster_name>-<environment>' and log_destination_arn is ignored."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "S3 lifecycle expiration in days for WAF log objects. Applies only when create_log_bucket = true."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 7, 14, 30, 60, 90, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be one of: 1, 3, 7, 14, 30, 60, 90, 180, 365."
  }
}

#------------------------------------------------------------------------------
# WAF Capacity / Sampling
#------------------------------------------------------------------------------

variable "enable_sampled_requests" {
  description = "Enable sampling of web requests that match WAF rules. Useful for CloudWatch metrics and threat analytics. Has no cost impact."
  type        = bool
  default     = true
}

variable "cloudwatch_metrics_enabled" {
  description = "Enable CloudWatch metrics for the WebACL and each rule. Enables dashboards and alarms."
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# IP Allowlist (Priority 0 — evaluated before all other rules)
#------------------------------------------------------------------------------

variable "enable_ip_allowlist" {
  description = "Enable IP-based access restriction. When true, default_action becomes BLOCK and only office_ip_cidrs are ALLOWed (before managed rules). When false, default_action remains ALLOW (current behavior)."
  type        = bool
  default     = false
}

variable "office_ip_cidrs" {
  description = "List of office IP CIDRs allowed access when enable_ip_allowlist is true. Example: [\"201.28.188.130/32\"]"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.office_ip_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All entries in office_ip_cidrs must be valid CIDR blocks (e.g., 201.28.188.130/32)."
  }
}
