variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "orphan-resource-detector"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "schedule_expression" {
  description = "CloudWatch Events schedule expression (cron or rate)"
  type        = string
  default     = "cron(0 12 * * ? *)" # Daily at 9am BRT (12pm UTC)
}

variable "alert_email" {
  description = "Email address for orphan resource alerts"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
