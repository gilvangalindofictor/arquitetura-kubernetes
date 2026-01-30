# 📊 CloudWatch Logs and Alarms
# AWS Specialist requirement: Proactive alarms for startup duration (T-003)

# CloudWatch Log Group for Lambda logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-scheduler"
  retention_in_days = var.cloudwatch_logs_retention_days

  # Note: Using AWS managed encryption (default) instead of custom KMS
  # CloudWatch Logs has encryption at rest enabled by default

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-lambda-logs"
      Component = "Logging"
      Cost      = "0.05-USD-month"
    }
  )
}

# CloudWatch Alarm: Startup Duration High
# Triggers if startup takes longer than threshold (default: 10 minutes)
resource "aws_cloudwatch_metric_alarm" "startup_duration_high" {
  alarm_name          = "${local.name_prefix}-startup-duration-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.alarm_startup_duration_threshold * 1000 # Convert to milliseconds
  alarm_description   = "Alert when FinOps ${var.environment} startup duration exceeds ${var.alarm_startup_duration_threshold}s"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.finops_automation.function_name
  }

  alarm_actions = [aws_sns_topic.finops_alerts.arn]
  ok_actions    = [aws_sns_topic.finops_alerts.arn]

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-startup-duration-high"
      Component = "Monitoring"
      Severity  = "Medium"
      Cost      = "0.10-USD-month"
    }
  )
}

# CloudWatch Alarm: Lambda Errors (Failure Count)
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name_prefix}-failure-count"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = var.circuit_breaker_threshold
  alarm_description   = "Alert when FinOps ${var.environment} has ${var.circuit_breaker_threshold}+ failures"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.finops_automation.function_name
  }

  alarm_actions = [aws_sns_topic.finops_alerts.arn]

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-failure-count"
      Component = "Monitoring"
      Severity  = "High"
      Cost      = "0.10-USD-month"
    }
  )
}

# CloudWatch Alarm: Lambda Throttles
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${local.name_prefix}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alert when FinOps ${var.environment} Lambda is throttled"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.finops_automation.function_name
  }

  alarm_actions = [aws_sns_topic.finops_alerts.arn]

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-throttles"
      Component = "Monitoring"
      Severity  = "Medium"
    }
  )
}

# SNS Topic for CloudWatch Alarms
resource "aws_sns_topic" "finops_alerts" {
  name              = "${local.name_prefix}-alerts"
  display_name      = "FinOps ${var.environment} Automation Alerts"
  kms_master_key_id = aws_kms_key.dynamodb.id # Encryption for SNS messages

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-alerts"
      Component = "Notifications"
    }
  )
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "finops_alerts" {
  arn = aws_sns_topic.finops_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.finops_alerts.arn
      },
      {
        Sid    = "AllowLambdaToPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.finops_alerts.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_lambda_function.finops_automation.arn
          }
        }
      }
    ]
  })
}

# CloudWatch Dashboard for FinOps monitoring
resource "aws_cloudwatch_dashboard" "finops_monitoring" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", { stat = "Average", label = "Avg Duration" }],
            ["...", { stat = "Maximum", label = "Max Duration" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Execution Duration"
          yAxis = {
            left = {
              label = "Milliseconds"
            }
          }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { stat = "Sum", label = "Invocations" }],
            [".", "Errors", { stat = "Sum", label = "Errors" }],
            [".", "Throttles", { stat = "Sum", label = "Throttles" }]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Lambda Invocations & Errors"
        }
      },
      {
        type = "log"
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.lambda_logs.name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          region = data.aws_region.current.name
          title  = "Recent Errors"
        }
      }
    ]
  })
}
