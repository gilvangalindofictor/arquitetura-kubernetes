# =============================================================================
# Main: FinOps Scheduler Module - Lambda + EventBridge
# =============================================================================
# Purpose: Automated start/stop of EKS nodes + RDS for cost optimization
# Architecture: EventBridge → Lambda → ASG/RDS/DynamoDB
# Savings: $177.61/month (25.9% cost reduction - validated 2026-01-30)
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# -----------------------------------------------------------------------------
# Lambda Deployment Package (ZIP)
# -----------------------------------------------------------------------------

data "archive_file" "lambda_start" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_start.py"
  output_path = "${path.module}/lambda_start.zip"
}

data "archive_file" "lambda_stop" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_stop.py"
  output_path = "${path.module}/lambda_stop.zip"
}

# -----------------------------------------------------------------------------
# Lambda Function: START Environment
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "finops_start" {
  function_name    = "finops-scheduler-start-${var.environment}"
  description      = "FinOps automation: Start EKS nodes + RDS for ${var.environment}"
  filename         = data.archive_file.lambda_start.output_path
  source_code_hash = data.archive_file.lambda_start.output_base64sha256

  runtime     = var.lambda_runtime
  handler     = "lambda_start.lambda_handler"
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory

  role        = aws_iam_role.lambda_role.arn
  kms_key_arn = aws_kms_key.dynamodb_finops.arn

  environment {
    variables = local.lambda_env_vars
  }

  # No VPC (ADR-024 decision: reduce NAT costs + latency)
  # vpc_config is intentionally omitted

  tags = merge(local.security_tags, {
    Name     = "finops-scheduler-start-${var.environment}"
    Function = "startup-automation"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda_start
  ]
}

resource "aws_lambda_function" "finops_stop" {
  function_name    = "finops-scheduler-stop-${var.environment}"
  description      = "FinOps automation: Stop EKS nodes + RDS for ${var.environment}"
  filename         = data.archive_file.lambda_stop.output_path
  source_code_hash = data.archive_file.lambda_stop.output_base64sha256

  runtime     = var.lambda_runtime
  handler     = "lambda_stop.lambda_handler"
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory

  role        = aws_iam_role.lambda_role.arn
  kms_key_arn = aws_kms_key.dynamodb_finops.arn

  environment {
    variables = local.lambda_env_vars
  }

  # No VPC (ADR-024 decision: reduce NAT costs + latency)

  tags = merge(local.security_tags, {
    Name     = "finops-scheduler-stop-${var.environment}"
    Function = "shutdown-automation"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda_stop
  ]
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups (Retention: 14 days)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda_start" {
  name              = "/aws/lambda/finops-scheduler-start-${var.environment}"
  retention_in_days = 14
  # KMS encryption removed - operational logs don't require KMS

  tags = local.security_tags
}

resource "aws_cloudwatch_log_group" "lambda_stop" {
  name              = "/aws/lambda/finops-scheduler-stop-${var.environment}"
  retention_in_days = 14
  # KMS encryption removed - operational logs don't require KMS

  tags = local.security_tags
}

# -----------------------------------------------------------------------------
# EventBridge Rules: Scheduled Start/Stop
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "startup" {
  name                = "finops-startup-${var.environment}"
  description         = "Start ${var.environment} environment at 8 AM BRT (11:00 UTC Mon-Fri)"
  schedule_expression = var.startup_schedule
  state               = var.enable_automation ? "ENABLED" : "DISABLED" # Disabled by default

  tags = merge(local.security_tags, {
    Name     = "finops-startup-${var.environment}"
    Schedule = "08:00 BRT Mon-Fri"
  })
}

resource "aws_cloudwatch_event_target" "startup_target" {
  rule      = aws_cloudwatch_event_rule.startup.name
  target_id = "lambda-finops-start"
  arn       = aws_lambda_function.finops_start.arn

  input = jsonencode({
    action       = "start"
    environment  = var.environment
    triggered_by = "eventbridge-scheduler"
  })
}

resource "aws_cloudwatch_event_rule" "shutdown" {
  name                = "finops-shutdown-${var.environment}"
  description         = "Stop ${var.environment} environment at 6 PM BRT (21:00 UTC Mon-Fri)"
  schedule_expression = var.shutdown_schedule
  state               = var.enable_automation ? "ENABLED" : "DISABLED" # Disabled by default

  tags = merge(local.security_tags, {
    Name     = "finops-shutdown-${var.environment}"
    Schedule = "18:00 BRT Mon-Fri"
  })
}

resource "aws_cloudwatch_event_target" "shutdown_target" {
  rule      = aws_cloudwatch_event_rule.shutdown.name
  target_id = "lambda-finops-stop"
  arn       = aws_lambda_function.finops_stop.arn

  input = jsonencode({
    action       = "stop"
    environment  = var.environment
    triggered_by = "eventbridge-scheduler"
  })
}

# GAP-009: Weekend Shutdown (Identified 2026-02-09)
# Purpose: Ensure nodes are off during weekends (Sat-Sun)
# Savings: $8-10/month ($96-120/year)
resource "aws_cloudwatch_event_rule" "weekend_shutdown" {
  name                = "finops-weekend-shutdown-${var.environment}"
  description         = "Stop ${var.environment} environment on Saturday midnight BRT (03:00 UTC Sat)"
  schedule_expression = var.weekend_shutdown_schedule
  state               = var.enable_automation ? "ENABLED" : "DISABLED"

  tags = merge(local.security_tags, {
    Name     = "finops-weekend-shutdown-${var.environment}"
    Schedule = "00:00 BRT Saturday"
    Purpose  = "GAP-009-weekend-cost-optimization"
  })
}

resource "aws_cloudwatch_event_target" "weekend_shutdown_target" {
  rule      = aws_cloudwatch_event_rule.weekend_shutdown.name
  target_id = "lambda-finops-weekend-stop"
  arn       = aws_lambda_function.finops_stop.arn

  input = jsonencode({
    action       = "stop"
    environment  = var.environment
    triggered_by = "eventbridge-weekend-scheduler"
  })
}

# -----------------------------------------------------------------------------
# Lambda Permissions for EventBridge
# -----------------------------------------------------------------------------

resource "aws_lambda_permission" "allow_eventbridge_start" {
  statement_id  = "AllowExecutionFromEventBridgeStartup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_start.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.startup.arn
}

resource "aws_lambda_permission" "allow_eventbridge_stop" {
  statement_id  = "AllowExecutionFromEventBridgeShutdown"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.shutdown.arn
}

resource "aws_lambda_permission" "allow_eventbridge_weekend_stop" {
  statement_id  = "AllowExecutionFromEventBridgeWeekendShutdown"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekend_shutdown.arn
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms (Monitoring - ADR-024 requirement)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "startup_duration_high" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "finops-${var.environment}-startup-duration-high"
  alarm_description   = "Startup taking > ${var.startup_duration_threshold}s (${var.startup_duration_threshold / 60} min)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.startup_duration_threshold * 1000 # milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.finops_start.function_name
  }

  alarm_actions = local.sns_alarm_actions

  tags = local.security_tags
}

resource "aws_cloudwatch_metric_alarm" "startup_failures" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "finops-${var.environment}-startup-failures"
  alarm_description   = "Startup Lambda errors (circuit breaker risk)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0 # Any error triggers alarm
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.finops_start.function_name
  }

  alarm_actions = local.sns_alarm_actions

  tags = local.security_tags
}

resource "aws_cloudwatch_metric_alarm" "shutdown_failures" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "finops-${var.environment}-shutdown-failures"
  alarm_description   = "Shutdown Lambda errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.finops_stop.function_name
  }

  alarm_actions = local.sns_alarm_actions

  tags = local.security_tags
}
