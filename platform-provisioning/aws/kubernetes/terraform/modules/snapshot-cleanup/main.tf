# Snapshot Cleanup Module
# Deletes old EBS migration snapshots on a weekly schedule
# Savings: R$ 216/ano (prevent snapshot accumulation post gp2→gp3 migration)

#------------------------------------------------------------------------------
# Lambda Function Package
#------------------------------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/snapshot_cleanup.py"
  output_path = "${path.module}/lambda/snapshot_cleanup.zip"
}

#------------------------------------------------------------------------------
# IAM Role for Lambda
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(var.common_tags, {
    Name = "${var.function_name}-role"
  })
}

data "aws_iam_policy_document" "lambda_permissions" {
  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.function_name}:*"]
  }

  # EC2 Snapshot permissions
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeSnapshots",
      "ec2:DeleteSnapshot",
      "ec2:DescribeImages",
    ]
    resources = ["*"]
  }

  # SNS Publish for alerts
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_policy" "lambda" {
  name        = "${var.function_name}-policy"
  description = "Permissions for snapshot cleanup Lambda"
  policy      = data.aws_iam_policy_document.lambda_permissions.json

  tags = merge(var.common_tags, {
    Name = "${var.function_name}-policy"
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

#------------------------------------------------------------------------------
# Lambda Function
#------------------------------------------------------------------------------

resource "aws_lambda_function" "snapshot_cleanup" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "snapshot_cleanup.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 300 # 5 minutes (large accounts may have many snapshots)
  memory_size      = 128

  environment {
    variables = {
      REGION         = var.aws_region
      RETENTION_DAYS = var.retention_days
      DRY_RUN        = var.dry_run ? "true" : "false"
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
    }
  }

  tags = merge(var.common_tags, {
    Name        = var.function_name
    Purpose     = "EBS snapshot lifecycle cleanup"
    Criticality = "Low"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Logs
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.function_name}-logs"
  })
}

#------------------------------------------------------------------------------
# EventBridge (CloudWatch Events) — Weekly trigger
#------------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.function_name}-schedule"
  description         = "Trigger snapshot cleanup Lambda weekly"
  schedule_expression = var.schedule_expression

  tags = merge(var.common_tags, {
    Name = "${var.function_name}-schedule"
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "SnapshotCleanupLambda"
  arn       = aws_lambda_function.snapshot_cleanup.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snapshot_cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

#------------------------------------------------------------------------------
# SNS Topic for Alerts
#------------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.function_name}-alerts"

  tags = merge(var.common_tags, {
    Name    = "${var.function_name}-alerts"
    Purpose = "Snapshot cleanup notifications"
  })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
