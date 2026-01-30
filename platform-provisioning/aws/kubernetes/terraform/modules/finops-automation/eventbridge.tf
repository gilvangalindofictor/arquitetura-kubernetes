# ⏰ EventBridge Scheduler Rules for Automated Start/Stop
# AWS Specialist requirement: Timezone-aware scheduling (BRT = UTC-3)

# Shutdown rule (18:00 BRT = 21:00 UTC Monday-Friday)
resource "aws_cloudwatch_event_rule" "shutdown_schedule" {
  name                = "${local.name_prefix}-shutdown"
  description         = "Trigger FinOps ${var.environment} shutdown at ${var.shutdown_schedule}"
  schedule_expression = var.shutdown_schedule

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-shutdown"
      Component = "Scheduling"
      Action    = "Shutdown"
      Cost      = "1.00-USD-month"
    }
  )
}

resource "aws_cloudwatch_event_target" "shutdown_lambda" {
  rule      = aws_cloudwatch_event_rule.shutdown_schedule.name
  target_id = "FinOpsShutdownLambda"
  arn       = aws_lambda_function.finops_automation.arn

  input = jsonencode({
    action       = "shutdown"
    environment  = var.environment
    triggered_by = "eventbridge_scheduler"
  })

  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_dlq.arn
  }
}

# Startup rule (08:00 BRT = 11:00 UTC Monday-Friday)
resource "aws_cloudwatch_event_rule" "startup_schedule" {
  name                = "${local.name_prefix}-startup"
  description         = "Trigger FinOps ${var.environment} startup at ${var.startup_schedule}"
  schedule_expression = var.startup_schedule

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-startup"
      Component = "Scheduling"
      Action    = "Startup"
      Cost      = "1.00-USD-month"
    }
  )
}

resource "aws_cloudwatch_event_target" "startup_lambda" {
  rule      = aws_cloudwatch_event_rule.startup_schedule.name
  target_id = "FinOpsStartupLambda"
  arn       = aws_lambda_function.finops_automation.arn

  input = jsonencode({
    action       = "startup"
    environment  = var.environment
    triggered_by = "eventbridge_scheduler"
  })

  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_dlq.arn
  }
}

# Dead Letter Queue for EventBridge failures
resource "aws_sqs_queue" "eventbridge_dlq" {
  name                      = "${local.name_prefix}-eventbridge-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-eventbridge-dlq"
      Component = "Messaging"
    }
  )
}

# Optional: Manual trigger rule (for testing and emergency overrides)
resource "aws_cloudwatch_event_rule" "manual_trigger" {
  name        = "${local.name_prefix}-manual-trigger"
  description = "Manual trigger for FinOps ${var.environment} (testing/emergency)"
  event_pattern = jsonencode({
    source      = ["custom.finops"]
    detail-type = ["FinOps Manual Trigger"]
    detail = {
      environment = [var.environment]
    }
  })

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-manual-trigger"
      Component = "Scheduling"
      Purpose   = "Manual-Override"
    }
  )
}

resource "aws_cloudwatch_event_target" "manual_trigger_lambda" {
  rule      = aws_cloudwatch_event_rule.manual_trigger.name
  target_id = "FinOpsManualTriggerLambda"
  arn       = aws_lambda_function.finops_automation.arn
}

resource "aws_lambda_permission" "allow_eventbridge_manual" {
  statement_id  = "AllowExecutionFromEventBridgeManual"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_automation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.manual_trigger.arn
}
