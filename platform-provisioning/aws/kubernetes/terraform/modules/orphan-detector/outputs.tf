output "lambda_function_arn" {
  description = "ARN of the orphan detector Lambda function"
  value       = aws_lambda_function.orphan_detector.arn
}

output "lambda_function_name" {
  description = "Name of the orphan detector Lambda function"
  value       = aws_lambda_function.orphan_detector.function_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for orphan alerts"
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_event_rule_name" {
  description = "Name of the CloudWatch Event rule"
  value       = aws_cloudwatch_event_rule.schedule.name
}

output "schedule_expression" {
  description = "Schedule expression for orphan detector"
  value       = var.schedule_expression
}
