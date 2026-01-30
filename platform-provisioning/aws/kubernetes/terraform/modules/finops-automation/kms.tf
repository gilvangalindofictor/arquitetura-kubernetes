# 🔐 KMS Key for DynamoDB Encryption at Rest
# Security Specialist requirement: S-019.1 DynamoDB encryption (+$1/mês)

resource "aws_kms_key" "dynamodb" {
  description             = "KMS key for FinOps ${var.environment} DynamoDB circuit breaker encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-dynamodb-key"
      Component = "Encryption"
      Cost      = "1.00-USD-month"
    }
  )
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${local.name_prefix}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}

# KMS key policy for DynamoDB service
resource "aws_kms_key_policy" "dynamodb" {
  key_id = aws_kms_key.dynamodb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow DynamoDB to use the key"
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "dynamodb.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}
