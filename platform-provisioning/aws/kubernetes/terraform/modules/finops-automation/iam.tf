# =============================================================================
# IAM: Lambda Execution Role + Policies (Least Privilege)
# =============================================================================
# Security Principle: Least privilege with resource-specific ARNs
# Framework: executor-terraform.md (Security Agent validation)
# =============================================================================

# -----------------------------------------------------------------------------
# IAM Role for Lambda Execution
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lambda_role" {
  name        = "finops-scheduler-role-${var.environment}"
  description = "Execution role for FinOps scheduler Lambda functions (${var.environment})"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = merge(local.security_tags, {
    Name    = "finops-scheduler-role-${var.environment}"
    Purpose = "Lambda execution with least privilege"
  })
}

# -----------------------------------------------------------------------------
# Policy Attachment: CloudWatch Logs (AWS Managed)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------------------------------------------------------------------------
# Policy: Auto Scaling Groups (Scale Up/Down)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "asg_policy" {
  name = "finops-scheduler-asg-policy-v1"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ManageAutoScalingGroups"
      Effect = "Allow"
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:SuspendProcesses",
        "autoscaling:ResumeProcesses"
      ]
      Resource = "arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/eks-${var.cluster_name}-*"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/Environment" = var.environment
        }
      }
    }]
  })
}

# -----------------------------------------------------------------------------
# Policy: RDS (Start/Stop Instances)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "rds_policy" {
  name = "finops-scheduler-rds-policy-v1"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeRDSInstances"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances"
        ]
        Resource = "*" # Describe is read-only, safe to allow on all resources
      },
      {
        Sid    = "ManageRDSInstance"
        Effect = "Allow"
        Action = [
          "rds:StopDBInstance",
          "rds:StartDBInstance"
        ]
        Resource = "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:${var.rds_instance_id}"
      },
      {
        Sid    = "CreateDBSnapshots"
        Effect = "Allow"
        Action = [
          "rds:CreateDBSnapshot",
          "rds:DescribeDBSnapshots"
        ]
        Resource = [
          "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:${var.rds_instance_id}",
          "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:snapshot:*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Policy: EKS (Read-Only for Health Checks)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "eks_policy" {
  name = "finops-scheduler-eks-policy-v1"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HealthChecks"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListNodegroups",
          "eks:DescribeNodegroup"
        ]
        Resource = "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
      },
      {
        Sid    = "ManageNodegroups"
        Effect = "Allow"
        Action = [
          "eks:UpdateNodegroupConfig"
        ]
        Resource = "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:nodegroup/${var.cluster_name}/*/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Policy: DynamoDB (Circuit Breaker State + Holiday Cache)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "dynamodb_policy" {
  name = "finops-scheduler-dynamodb-policy-v1"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CircuitBreakerState"
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query"
      ]
      Resource = aws_dynamodb_table.scheduler_state.arn
    }]
  })
}

# -----------------------------------------------------------------------------
# Policy: CloudWatch (Custom Metrics + Logs)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "cloudwatch_policy" {
  name = "finops-scheduler-cloudwatch-policy-v1"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PutCustomMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "FinOps/Scheduler"
          }
        }
      },
      {
        Sid    = "ManageLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.lambda_start.arn,
          aws_cloudwatch_log_group.lambda_stop.arn,
          "${aws_cloudwatch_log_group.lambda_start.arn}:*",
          "${aws_cloudwatch_log_group.lambda_stop.arn}:*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Policy: SNS (Notifications - Optional)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "sns_policy" {
  count = var.enable_sns_notifications || var.sns_topic_arn != "" ? 1 : 0 # Criar se tópico interno OU externo
  name  = "finops-scheduler-sns-policy-v1"
  role  = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "PublishNotifications"
      Effect = "Allow"
      Action = [
        "sns:Publish"
      ]
      Resource = var.sns_topic_arn != "" ? var.sns_topic_arn : "*"
    }]
  })
}

# -----------------------------------------------------------------------------
# Policy: KMS (DynamoDB + CloudWatch Logs Encryption)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "kms_policy" {
  name = "finops-scheduler-kms-policy-v1"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DecryptEncryptedResources"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.dynamodb_finops.arn
      },
      {
        Sid    = "DecryptLambdaEnvironment"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          aws_kms_key.dynamodb_finops.arn,
          "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/00aa4d95-d6d2-41db-bcd5-e409dce9f88c"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}
