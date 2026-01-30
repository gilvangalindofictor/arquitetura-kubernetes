output "lambda_function_arn" {
  description = "ARN of the FinOps Lambda function"
  value       = module.finops_automation.lambda_function_arn
}

output "lambda_function_url" {
  description = "Function URL for manual testing"
  value       = module.finops_automation.lambda_function_url
  sensitive   = true
}

output "circuit_breaker_table" {
  description = "DynamoDB circuit breaker table name"
  value       = module.finops_automation.dynamodb_circuit_breaker_table_name
}

output "sns_topic_arn" {
  description = "SNS topic for CloudWatch alarms"
  value       = module.finops_automation.sns_topic_arn
}

output "cloudwatch_dashboard" {
  description = "CloudWatch Dashboard name"
  value       = module.finops_automation.cloudwatch_dashboard_name
}

output "estimated_monthly_cost" {
  description = "Estimated monthly operational cost"
  value       = module.finops_automation.estimated_monthly_cost_usd
}
