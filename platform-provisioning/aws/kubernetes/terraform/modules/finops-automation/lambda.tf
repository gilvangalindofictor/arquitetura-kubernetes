# 🔧 Lambda Function for FinOps Automation
# Terraform Specialist requirement: archive_file data source for automatic packaging (T-004)

# Package Lambda deployment with dependencies
data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.terraform/lambda-${var.environment}.zip"

  excludes = [
    "__pycache__",
    "*.pyc",
    ".pytest_cache",
    "tests"
  ]
}

# Lambda function
resource "aws_lambda_function" "finops_automation" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = "${local.name_prefix}-scheduler"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "finops_handler.lambda_handler"
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  environment {
    variables = {
      ENVIRONMENT               = var.environment
      CLUSTER_NAME              = var.cluster_name
      RDS_INSTANCE_ID           = var.rds_instance_identifier
      ASG_NAMES                 = join(",", var.asg_names)
      CIRCUIT_BREAKER_TABLE     = aws_dynamodb_table.circuit_breaker.name
      RDS_STATE_TABLE           = aws_dynamodb_table.rds_state.name
      CIRCUIT_BREAKER_THRESHOLD = var.circuit_breaker_threshold
      ENABLE_BRASILAPI          = tostring(var.enable_brasilapi_holidays)
      HEALTH_CHECK_ENABLED      = tostring(var.health_check_enabled)
      LOG_LEVEL                 = "INFO"
    }
  }

  # Security Specialist: Lambda VPC configuration validation (S-019.2)
  # Decision: NO VPC attachment (Lambda needs internet for BrasilAPI)
  # Alternative: VPC + NAT Gateway ($32/mês) rejected by FinOps
  # vpc_config is intentionally not set

  # Dead letter queue for failed invocations
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  # Tracing for observability
  tracing_config {
    mode = "Active" # X-Ray tracing
  }

  depends_on = [
    aws_iam_role_policy.lambda_logging,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-scheduler"
      Component = "Compute"
      Runtime   = var.lambda_runtime
      Cost      = "0.15-USD-month"
    }
  )
}

# Dead Letter Queue for failed Lambda invocations
resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${local.name_prefix}-lambda-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-lambda-dlq"
      Component = "Messaging"
    }
  )
}

# Lambda function URL (optional - for manual testing)
resource "aws_lambda_function_url" "finops_automation" {
  function_name      = aws_lambda_function.finops_automation.function_name
  authorization_type = "AWS_IAM" # Require IAM authentication

  cors {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    max_age       = 300
  }
}

# Lambda permission for EventBridge to invoke
resource "aws_lambda_permission" "allow_eventbridge_shutdown" {
  statement_id  = "AllowExecutionFromEventBridgeShutdown"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_automation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.shutdown_schedule.arn
}

resource "aws_lambda_permission" "allow_eventbridge_startup" {
  statement_id  = "AllowExecutionFromEventBridgeStartup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_automation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.startup_schedule.arn
}
