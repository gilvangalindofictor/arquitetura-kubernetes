# 🔐 IAM Roles and Policies (Least Privilege Pattern)
# Security Specialist requirement: Resource-specific ARNs, no wildcards (S-019.3-v1)

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-role-v1" # Versioned for rollback support

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.name_prefix}-lambda-role"
      Component = "IAM"
      Version   = "v1"
    }
  )
}

# CloudWatch Logs policy (least privilege)
resource "aws_iam_role_policy" "lambda_logging" {
  name = "${local.name_prefix}-lambda-logging-v1"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "CreateLogStreamAndPutLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
      }
    ]
  })
}

# RDS start/stop policy (resource-specific)
resource "aws_iam_role_policy" "lambda_rds" {
  name = "${local.name_prefix}-lambda-rds-v1"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RDSStartStop"
        Effect = "Allow"
        Action = [
          "rds:StartDBInstance",
          "rds:StopDBInstance",
          "rds:DescribeDBInstances"
        ]
        Resource = "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:${var.rds_instance_identifier}"
      }
    ]
  })
}

# Auto Scaling policy (resource-specific ASGs)
resource "aws_iam_role_policy" "lambda_autoscaling" {
  name = "${local.name_prefix}-lambda-autoscaling-v1"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AutoScalingGroupUpdate"
        Effect = "Allow"
        Action = [
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = [
          for asg_name in var.asg_names :
          "arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${asg_name}"
        ]
      },
      {
        Sid    = "EC2DescribeInstances"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*" # DescribeInstances doesn't support resource-level permissions
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      }
    ]
  })
}

# DynamoDB policy (resource-specific tables)
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${local.name_prefix}-lambda-dynamodb-v1"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBCircuitBreaker"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.circuit_breaker.arn,
          aws_dynamodb_table.rds_state.arn
        ]
      }
    ]
  })
}

# SQS Dead Letter Queue policy
resource "aws_iam_role_policy" "lambda_sqs" {
  name = "${local.name_prefix}-lambda-sqs-v1"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSSendMessage"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.lambda_dlq.arn,
          aws_sqs_queue.eventbridge_dlq.arn
        ]
      }
    ]
  })
}

# X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
