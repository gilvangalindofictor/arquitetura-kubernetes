# =============================================================================
# DynamoDB Table: Circuit Breaker State + Holiday Cache
# =============================================================================
# Purpose: Store FinOps scheduler state for circuit breaker logic
# Encryption: KMS managed (LGPD compliance)
# Destroy Protection: Enabled (prevent accidental data loss)
# =============================================================================

# -----------------------------------------------------------------------------
# KMS Key for DynamoDB Encryption
# -----------------------------------------------------------------------------

resource "aws_kms_key" "dynamodb_finops" {
  description             = "KMS key for DynamoDB finops-scheduler-state encryption (LGPD compliance)"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = local.security_tags
}

resource "aws_kms_alias" "dynamodb_finops" {
  name          = "alias/finops-scheduler-dynamodb-${var.environment}"
  target_key_id = aws_kms_key.dynamodb_finops.key_id
}

# -----------------------------------------------------------------------------
# DynamoDB Table
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "scheduler_state" {
  name         = "finops-scheduler-state-${var.environment}"
  billing_mode = "PAY_PER_REQUEST" # On-demand (cost: ~$0.25/month)
  hash_key     = "environment"

  attribute {
    name = "environment"
    type = "S"
  }

  # TTL for holiday cache (30 days)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Server-side encryption with KMS (LGPD compliance)
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_finops.arn
  }

  # Point-in-time recovery (best practice)
  point_in_time_recovery {
    enabled = true
  }

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.security_tags, {
    Name        = "finops-scheduler-state-${var.environment}"
    Purpose     = "Circuit breaker state and holiday cache"
    Compliance  = "LGPD-OK"
    Encryption  = "KMS-managed"
  })
}

# -----------------------------------------------------------------------------
# Initialize State Table (Circuit Breaker Defaults)
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table_item" "initial_state" {
  table_name = aws_dynamodb_table.scheduler_state.name
  hash_key   = aws_dynamodb_table.scheduler_state.hash_key

  item = jsonencode({
    environment = {
      S = var.environment
    }
    startup_failures = {
      N = "0"
    }
    shutdown_failures = {
      N = "0"
    }
    circuit_breaker_state = {
      S = "CLOSED"
    }
    last_startup = {
      S = "never"
    }
    last_shutdown = {
      S = "never"
    }
    last_stop_time = {
      S = "1970-01-01T00:00:00Z" # Epoch - for RDS 7-day check
    }
    holidays_cache = {
      M = {}
    }
    ttl = {
      N = tostring(timeadd(timestamp(), "720h")) # 30 days from now (720 hours)
    }
  })

  lifecycle {
    ignore_changes = [
      item # Don't overwrite runtime state on re-apply
    ]
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "dynamodb_table_name" {
  description = "DynamoDB table name for circuit breaker state"
  value       = aws_dynamodb_table.scheduler_state.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.scheduler_state.arn
}

output "kms_key_id" {
  description = "KMS key ID for DynamoDB encryption"
  value       = aws_kms_key.dynamodb_finops.id
}

output "kms_key_arn" {
  description = "KMS key ARN for DynamoDB encryption"
  value       = aws_kms_key.dynamodb_finops.arn
}
