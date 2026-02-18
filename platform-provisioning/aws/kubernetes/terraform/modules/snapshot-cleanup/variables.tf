variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge schedule expression"
  type        = string
  default     = "cron(0 3 ? * MON *)" # Every Monday 03:00 UTC (midnight BRT)
}

variable "retention_days" {
  description = "Delete snapshots older than this many days"
  type        = number
  default     = 30
}

variable "dry_run" {
  description = "If true, report candidates but do NOT delete (safe for first run)"
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address for SNS alerts (empty = no email subscription)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 7
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
