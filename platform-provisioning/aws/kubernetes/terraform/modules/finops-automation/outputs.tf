# 📤 Module Outputs
# Terraform Specialist requirement: Export ARNs for integration (T-002)

output "lambda_function_arn" {
  description = "ARN of the FinOps automation Lambda function"
  value       = aws_lambda_function.finops_automation.arn
}

output "lambda_function_name" {
  description = "Name of the FinOps automation Lambda function"
  value       = aws_lambda_function.finops_automation.function_name
}

output "lambda_function_url" {
  description = "Function URL for manual testing (IAM authenticated)"
  value       = aws_lambda_function_url.finops_automation.function_url
}

output "dynamodb_circuit_breaker_table_name" {
  description = "Name of the DynamoDB circuit breaker table"
  value       = aws_dynamodb_table.circuit_breaker.name
}

output "dynamodb_circuit_breaker_table_arn" {
  description = "ARN of the DynamoDB circuit breaker table"
  value       = aws_dynamodb_table.circuit_breaker.arn
}

output "dynamodb_rds_state_table_name" {
  description = "Name of the DynamoDB RDS state table"
  value       = aws_dynamodb_table.rds_state.name
}

output "kms_key_id" {
  description = "KMS key ID for DynamoDB encryption"
  value       = aws_kms_key.dynamodb.id
}

output "kms_key_arn" {
  description = "KMS key ARN for DynamoDB encryption"
  value       = aws_kms_key.dynamodb.arn
}

output "shutdown_schedule_rule_arn" {
  description = "ARN of the EventBridge shutdown schedule rule"
  value       = aws_cloudwatch_event_rule.shutdown_schedule.arn
}

output "startup_schedule_rule_arn" {
  description = "ARN of the EventBridge startup schedule rule"
  value       = aws_cloudwatch_event_rule.startup_schedule.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarms"
  value       = aws_sns_topic.finops_alerts.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch Dashboard"
  value       = aws_cloudwatch_dashboard.finops_monitoring.dashboard_name
}

output "iam_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution.arn
}

# Cost tracking outputs (FinOps requirement)
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD"
  value = {
    lambda_compute    = "0.15"
    eventbridge_rules = "1.00"
    dynamodb_ondemand = "0.05"
    cloudwatch_logs   = "0.05"
    kms_key           = "1.00"
    cloudwatch_alarms = "0.20"
    sns_topic         = "0.00"
    total             = "2.45"
  }
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}
