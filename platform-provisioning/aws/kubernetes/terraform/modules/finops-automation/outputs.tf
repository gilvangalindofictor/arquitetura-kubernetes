# =============================================================================
# Outputs: FinOps Scheduler Module
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda Functions
# -----------------------------------------------------------------------------

output "lambda_start_function_name" {
  description = "Name of the Lambda function for startup"
  value       = aws_lambda_function.finops_start.function_name
}

output "lambda_start_function_arn" {
  description = "ARN of the Lambda function for startup"
  value       = aws_lambda_function.finops_start.arn
}

output "lambda_stop_function_name" {
  description = "Name of the Lambda function for shutdown"
  value       = aws_lambda_function.finops_stop.function_name
}

output "lambda_stop_function_arn" {
  description = "ARN of the Lambda function for shutdown"
  value       = aws_lambda_function.finops_stop.arn
}

# -----------------------------------------------------------------------------
# EventBridge Rules
# -----------------------------------------------------------------------------

output "eventbridge_rule_startup_arn" {
  description = "ARN of the EventBridge startup rule"
  value       = aws_cloudwatch_event_rule.startup.arn
}

output "eventbridge_rule_shutdown_arn" {
  description = "ARN of the EventBridge shutdown rule"
  value       = aws_cloudwatch_event_rule.shutdown.arn
}

output "eventbridge_rules_enabled" {
  description = "Whether EventBridge rules are enabled (automation active)"
  value       = var.enable_automation
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

output "cloudwatch_log_group_start" {
  description = "CloudWatch Log Group for Lambda start function"
  value       = aws_cloudwatch_log_group.lambda_start.name
}

output "cloudwatch_log_group_stop" {
  description = "CloudWatch Log Group for Lambda stop function"
  value       = aws_cloudwatch_log_group.lambda_stop.name
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms created (if enabled)"
  value = var.enable_cloudwatch_alarms ? {
    startup_duration  = try(aws_cloudwatch_metric_alarm.startup_duration_high[0].arn, null)
    startup_failures  = try(aws_cloudwatch_metric_alarm.startup_failures[0].arn, null)
    shutdown_failures = try(aws_cloudwatch_metric_alarm.shutdown_failures[0].arn, null)
  } : {}
}

# -----------------------------------------------------------------------------
# Manual Invocation Commands
# -----------------------------------------------------------------------------

output "manual_invocation_commands" {
  description = "AWS CLI commands for manual Lambda invocation (testing)"
  value = {
    start = "aws lambda invoke --function-name ${aws_lambda_function.finops_start.function_name} --payload '{\"action\":\"start\",\"environment\":\"${var.environment}\",\"triggered_by\":\"manual\"}' response.json"
    stop  = "aws lambda invoke --function-name ${aws_lambda_function.finops_stop.function_name} --payload '{\"action\":\"stop\",\"environment\":\"${var.environment}\",\"triggered_by\":\"manual\"}' response.json"
  }
}

# -----------------------------------------------------------------------------
# Cost Savings Estimation
# -----------------------------------------------------------------------------

output "cost_savings_estimation" {
  description = "Estimated cost savings with automation (based on Marco 2 validation)"
  value = {
    monthly_usd       = 177.61
    monthly_brl       = 177.61 * 6.0      # R$ 1,065.66
    annual_brl        = 177.61 * 6.0 * 12 # R$ 12,787.92
    reduction_percent = 25.9
    validated_date    = "2026-01-30"
  }
}

# -----------------------------------------------------------------------------
# Next Steps (Post-Deployment)
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Post-deployment actions required"
  value       = <<-EOT
    1. Validate Terraform deployment:
       terraform output

    2. Test manual invocation (BEFORE enabling automation):
       ${try(aws_lambda_function.finops_start.function_name, "N/A")}
       ${try(aws_lambda_function.finops_stop.function_name, "N/A")}

    3. Check Lambda logs:
       aws logs tail /aws/lambda/${try(aws_lambda_function.finops_start.function_name, "N/A")} --follow

    4. Enable automation (after 1 week manual testing):
       terraform apply -var="enable_automation=true"

    5. Monitor savings:
       - Cost Explorer dashboard: "FinOps Savings Real vs Projected"
       - CloudWatch namespace: FinOps/Scheduler
       - Target: R$ 1,065.66/month savings

    6. Validate circuit breaker:
       aws dynamodb get-item --table-name ${aws_dynamodb_table.scheduler_state.name} --key '{"environment":{"S":"${var.environment}"}}'
  EOT
}
