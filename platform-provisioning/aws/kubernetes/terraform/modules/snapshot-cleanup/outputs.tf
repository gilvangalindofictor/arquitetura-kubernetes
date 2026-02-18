output "lambda_function_name" {
  description = "Name of the snapshot cleanup Lambda function"
  value       = aws_lambda_function.snapshot_cleanup.function_name
}

output "lambda_function_arn" {
  description = "ARN of the snapshot cleanup Lambda function"
  value       = aws_lambda_function.snapshot_cleanup.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cleanup alerts"
  value       = aws_sns_topic.alerts.arn
}

output "schedule_rule_name" {
  description = "Name of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.schedule.name
}
