# 🔄 DynamoDB Circuit Breaker State Table
# Terraform Specialist requirement: prevent_destroy = true (T-005)
# Security Specialist requirement: KMS encryption enabled (S-019.1)

resource "aws_dynamodb_table" "circuit_breaker" {
  name         = "${local.name_prefix}-circuit-breaker"
  billing_mode = "PAY_PER_REQUEST" # On-demand pricing (FinOps approved: $0.03/mês)
  hash_key     = "environment"
  range_key    = "timestamp"

  attribute {
    name = "environment"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  # Security Specialist: KMS encryption at rest
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # TTL for automatic cleanup of old records (30 days retention)
  ttl {
    attribute_name = "expiration_time"
    enabled        = true
  }

  # Terraform Specialist: Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-circuit-breaker"
      Component   = "StateManagement"
      Criticality = "High"
      Cost        = "0.03-USD-month"
    }
  )
}

# DynamoDB table for tracking RDS last_stop_time
# AWS Specialist requirement: T-025 RDS 7-day auto-start mitigation
resource "aws_dynamodb_table" "rds_state" {
  name         = "${local.name_prefix}-rds-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "instance_id"

  attribute {
    name = "instance_id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "expiration_time"
    enabled        = true
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-rds-state"
      Component = "StateManagement"
      Purpose   = "RDS-AutoStart-Mitigation"
      Cost      = "0.02-USD-month"
    }
  )
}
