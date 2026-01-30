# =============================================================================
# Outputs: FinOps Staging Environment
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda Functions
# -----------------------------------------------------------------------------

output "lambda_start_function_name" {
  description = "Name of the Lambda startup function"
  value       = module.finops_automation.lambda_start_function_name
}

output "lambda_start_function_arn" {
  description = "ARN of the Lambda startup function"
  value       = module.finops_automation.lambda_start_function_arn
}

output "lambda_stop_function_name" {
  description = "Name of the Lambda shutdown function"
  value       = module.finops_automation.lambda_stop_function_name
}

output "lambda_stop_function_arn" {
  description = "ARN of the Lambda shutdown function"
  value       = module.finops_automation.lambda_stop_function_arn
}

# -----------------------------------------------------------------------------
# EventBridge Rules
# -----------------------------------------------------------------------------

output "eventbridge_rules_enabled" {
  description = "Whether EventBridge rules are enabled (automation active)"
  value       = module.finops_automation.eventbridge_rules_enabled
}

output "eventbridge_rule_startup_arn" {
  description = "ARN of the EventBridge startup rule"
  value       = module.finops_automation.eventbridge_rule_startup_arn
}

output "eventbridge_rule_shutdown_arn" {
  description = "ARN of the EventBridge shutdown rule"
  value       = module.finops_automation.eventbridge_rule_shutdown_arn
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

output "cloudwatch_log_group_start" {
  description = "CloudWatch Log Group for Lambda start function"
  value       = module.finops_automation.cloudwatch_log_group_start
}

output "cloudwatch_log_group_stop" {
  description = "CloudWatch Log Group for Lambda stop function"
  value       = module.finops_automation.cloudwatch_log_group_stop
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms created (if enabled)"
  value       = module.finops_automation.cloudwatch_alarms
}

# -----------------------------------------------------------------------------
# Manual Testing Commands
# -----------------------------------------------------------------------------

output "manual_invocation_commands" {
  description = "AWS CLI commands for manual Lambda invocation (testing)"
  value       = module.finops_automation.manual_invocation_commands
}

# -----------------------------------------------------------------------------
# Cost Savings
# -----------------------------------------------------------------------------

output "cost_savings_estimation" {
  description = "Estimated cost savings with automation"
  value       = module.finops_automation.cost_savings_estimation
}

# -----------------------------------------------------------------------------
# Next Steps
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Post-deployment actions required"
  value       = module.finops_automation.next_steps
}
