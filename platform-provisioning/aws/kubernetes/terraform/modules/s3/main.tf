# S3 Module for Observability Platform
# Long-term storage for metrics, logs, and backups
# Follows ADR-002: S3 for retention (metrics 90d, logs 30d)

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "observability"
}

variable "buckets" {
  description = "Configuration for S3 buckets"
  type = map(object({
    versioning_enabled = bool
    lifecycle_rules = list(object({
      id                       = string
      enabled                  = bool
      transition_days          = number
      transition_storage_class = string
      expiration_days          = number
    }))
  }))
  default = {
    metrics = {
      versioning_enabled = false
      lifecycle_rules = [{
        id                       = "metrics-lifecycle"
        enabled                  = true
        transition_days          = 30
        transition_storage_class = "STANDARD_IA"
        expiration_days          = 90
      }]
    }
    logs = {
      versioning_enabled = false
      lifecycle_rules = [{
        id                       = "logs-lifecycle"
        enabled                  = true
        transition_days          = 7
        transition_storage_class = "STANDARD_IA"
        expiration_days          = 30
      }]
    }
    traces = {
      versioning_enabled = false
      lifecycle_rules = [{
        id                       = "traces-lifecycle"
        enabled                  = true
        transition_days          = 3
        transition_storage_class = "STANDARD_IA"
        expiration_days          = 7
      }]
    }
    backups = {
      versioning_enabled = true
      lifecycle_rules = [{
        id                       = "backups-lifecycle"
        enabled                  = true
        transition_days          = 90
        transition_storage_class = "GLACIER"
        expiration_days          = 365
      }]
    }
  }
}

# S3 Buckets
resource "aws_s3_bucket" "main" {
  for_each = var.buckets

  bucket = "${var.project_name}-${each.key}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name      = "${var.project_name}-${each.key}"
    Project   = var.project_name
    ManagedBy = "terraform"
    Purpose   = each.key
  }
}

# Block Public Access
resource "aws_s3_bucket_public_access_block" "main" {
  for_each = var.buckets

  bucket = aws_s3_bucket.main[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning
resource "aws_s3_bucket_versioning" "main" {
  for_each = var.buckets

  bucket = aws_s3_bucket.main[each.key].id

  versioning_configuration {
    status = each.value.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  for_each = var.buckets

  bucket = aws_s3_bucket.main[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle Rules
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  for_each = var.buckets

  bucket = aws_s3_bucket.main[each.key].id

  dynamic "rule" {
    for_each = each.value.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      transition {
        days          = rule.value.transition_days
        storage_class = rule.value.transition_storage_class
      }

      expiration {
        days = rule.value.expiration_days
      }
    }
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Outputs
output "bucket_ids" {
  description = "Map of bucket names to bucket IDs"
  value       = { for k, v in aws_s3_bucket.main : k => v.id }
}

output "bucket_arns" {
  description = "Map of bucket names to bucket ARNs"
  value       = { for k, v in aws_s3_bucket.main : k => v.arn }
}

output "bucket_domain_names" {
  description = "Map of bucket names to bucket domain names"
  value       = { for k, v in aws_s3_bucket.main : k => v.bucket_domain_name }
}
