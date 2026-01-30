# =============================================================================
# SNS Topic: FinOps Notifications
# =============================================================================
# Purpose: Send alerts for Lambda executions (success/failure)
# Subscribers: DevOps team emails
# =============================================================================

resource "aws_sns_topic" "finops_notifications" {
  count = var.enable_sns_notifications ? 1 : 0

  name         = "finops-automation-${var.environment}"
  display_name = "FinOps Automation Notifications - ${upper(var.environment)}"

  # Enable encryption at rest (LGPD compliance)
  kms_master_key_id = aws_kms_key.dynamodb_finops.id

  tags = merge(local.security_tags, {
    Name        = "finops-automation-${var.environment}"
    Purpose     = "Lambda execution notifications"
    Subscribers = "DevOps Team"
  })
}

# -----------------------------------------------------------------------------
# SNS Topic Policy: Allow CloudWatch Alarms to publish
# -----------------------------------------------------------------------------

resource "aws_sns_topic_policy" "finops_notifications" {
  count = var.enable_sns_notifications ? 1 : 0

  arn = aws_sns_topic.finops_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.finops_notifications[0].arn
      },
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.finops_notifications[0].arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [
              aws_lambda_function.finops_start.arn,
              aws_lambda_function.finops_stop.arn
            ]
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SNS Email Subscriptions
# -----------------------------------------------------------------------------

resource "aws_sns_topic_subscription" "devops_team_email" {
  count = var.enable_sns_notifications && length(var.notification_emails) > 0 ? length(var.notification_emails) : 0

  topic_arn = aws_sns_topic.finops_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_emails[count.index]

  # Prevent Terraform from failing if subscription is not confirmed
  endpoint_auto_confirms = false
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "SNS Topic ARN for FinOps notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.finops_notifications[0].arn : ""
}

output "sns_topic_name" {
  description = "SNS Topic name"
  value       = var.enable_sns_notifications ? aws_sns_topic.finops_notifications[0].name : ""
}
