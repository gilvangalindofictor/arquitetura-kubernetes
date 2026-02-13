# Orphan Resource Detector Module
# Scans for orphaned AWS resources (EBS volumes, Elastic IPs, Snapshots)
# and sends daily alerts via SNS

#------------------------------------------------------------------------------
# Lambda Function Package
#------------------------------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/orphan_detector.py"
  output_path = "${path.module}/lambda/orphan_detector.zip"
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
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.function_name}:*"]
  }

  # EC2 Read permissions for resource scanning
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeAddresses",
      "ec2:DescribeSnapshots",
      "ec2:DescribeImages",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeNetworkInterfaces"
    ]
    resources = ["*"]
  }

  # SNS Publish for alerts
  statement {
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_policy" "lambda" {
  name        = "${var.function_name}-policy"
  description = "Permissions for orphan resource detector Lambda"
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

resource "aws_lambda_function" "orphan_detector" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "orphan_detector.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 300 # 5 minutes
  memory_size      = 256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
      REGION        = var.aws_region
    }
  }

  tags = merge(var.common_tags, {
    Name        = var.function_name
    Purpose     = "Orphan resource detector"
    Criticality = "Medium"
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
# EventBridge (CloudWatch Events) Trigger
#------------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.function_name}-schedule"
  description         = "Trigger orphan detector Lambda on schedule"
  schedule_expression = var.schedule_expression

  tags = merge(var.common_tags, {
    Name = "${var.function_name}-schedule"
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "OrphanDetectorLambda"
  arn       = aws_lambda_function.orphan_detector.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orphan_detector.function_name
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
    Purpose = "Orphan resource notifications"
  })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
