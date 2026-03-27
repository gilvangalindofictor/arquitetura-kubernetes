# =============================================================================
# FinOps Automation — Produção
# =============================================================================
# Strategy:
#   PROD does NOT scale node groups (cluster is SHARED with staging services).
#   Instead, prod-specific workloads (Deployments + StatefulSets) in prod-*
#   namespaces are scaled to 0 replicas on shutdown and restored on startup.
#
# Key constraints:
#   - Node groups: NOT scaled (system/workloads/critical nodes serve staging too)
#   - RDS: NOT stopped (k8s-platform-prod-postgresql is shared by both envs)
#   - Shared namespaces: harbor-system, staging-platform-*, monitoring — NEVER touched
#   - Only prod-exclusive namespaces are managed
#
# Estimated savings:
#   Savings come from pod resource reservation release + reduced EKS API costs.
#   Primary savings still come from staging node group scale-down (already running).
#   Prod contribution: pod CPU/memory reservation freed on workload nodes (~10-15%)
#   enabling better bin-packing and potentially fewer workload nodes needed at night.
#
# Schedule (same as staging for operational consistency):
#   UP:   cron(30 10 ? * MON-FRI *) = 10:30 UTC / 07:30 BRT
#   DOWN: cron(0 23 ? * MON-FRI *)  = 23:00 UTC / 20:00 BRT
#   Sat:  cron(0 3 ? * SAT *)       = 03:00 UTC / 00:00 BRT
#   Sun:  cron(0 23 ? * SUN *)      = 23:00 UTC / 20:00 BRT
#
# Author: FinOps Team
# Date: 2026-03-24
# Framework: executor-terraform.md
# =============================================================================

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

data "aws_caller_identity" "finops_prod" {}
data "aws_region" "finops_prod" {}

# ---------------------------------------------------------------------------
# Local Variables
# ---------------------------------------------------------------------------

locals {
  finops_prod_environment = "prod"
  finops_prod_cluster     = local.cluster_name  # "k8s-platform-prod" from main.tf

  # prod-exclusive namespaces that CAN be scaled down
  # These do NOT include shared namespaces (harbor-system, staging-*, etc.)
  # REMOVED 2026-03-24:
  #   - prod-security-vault: Vault is CRITICAL infra (KMS auto-unseal, ESO backend) — moved to EXCLUDED
  #   - prod-platform-argocd: Critical platform tool for emergency hotfixes/rollbacks — moved to EXCLUDED
  finops_prod_target_namespaces = join(",", [
    "prod-platform-keycloak",
    # ADR-050 (2026-03-27): prod-platform-sonarqube removido — SonarQube reclassificado PLATFORM-SHARED, namespace esvaziado
    # GAP-LAMBDA-002 (2026-03-26): prod-platform-backstage removido — namespace vazio, Lambda HTTP 404
    "prod-platform-harbor",
    "prod-platform-externaldns",
    # prod-platform-argocd REMOVED — see EXCLUDED below
    "prod-observability-monitoring",
    # prod-security-vault REMOVED — see EXCLUDED below
    "prod-data-hatch-etl",
    "prod-data-vemsoft-etl",
    "prod-data-services",
    "prod-data-rabbitmq",
    "prod-data-redis-operator",
    "prod-data-ipaas",
  ])

  # Namespaces NEVER to touch (shared infrastructure safety guard)
  # 2026-03-24: Added prod-security-vault and prod-platform-argocd
  finops_prod_excluded_namespaces = join(",", [
    "harbor-system",
    "staging-platform-gitlab",
    "staging-platform-argocd",
    "staging-platform-keycloak",
    "staging-platform-harbor",
    "staging-platform-backstage",
    "staging-platform-sonarqube",
    "staging-platform-externaldns",
    "staging-security-vault",
    "staging-security-externalsecrets",
    "staging-observability-monitoring",
    "monitoring",
    "kube-system",
    "kube-public",
    "kube-node-lease",
    "linkerd",
    "linkerd-cni",
    "linkerd-viz",
    # FIX (2026-03-27): "cert-manager" is legacy empty namespace; real workloads in staging-security-certmanager
    # Both retained: cert-manager (legacy guard) + staging-security-certmanager (active workloads)
    "cert-manager",
    "staging-security-certmanager",
    "external-secrets-system",
    "prod-security-externalsecrets",
    # CRITICAL: Vault prod — KMS auto-unseal + ESO backend; scaling to 0 would break secret injection
    "prod-security-vault",
    # CRITICAL: ArgoCD prod — must stay UP for emergency hotfixes/rollbacks on weekends
    "prod-platform-argocd",
    "calico-system",
    "calico-apiserver",
    "velero",
    # FIX (2026-03-27): "kyverno" never matched — real namespace is staging-governance-kyverno
    "staging-governance-kyverno",
  ])

  finops_prod_common_tags = merge(local.common_tags, {
    Component  = "finops-automation-prod"
    Automation = "lambda-scheduler"
    Strategy   = "deployment-scale-only"  # vs staging which scales node groups
  })
}

# =============================================================================
# Lambda Deployment Packages (ZIP)
# =============================================================================

data "archive_file" "lambda_start_prod" {
  type             = "zip"
  source_file      = "${path.module}/../../modules/finops-automation/lambda/lambda_start_prod.py"
  output_path      = "${path.module}/lambda_start_prod.zip"
  output_file_mode = "0666"
}

data "archive_file" "lambda_stop_prod" {
  type             = "zip"
  source_file      = "${path.module}/../../modules/finops-automation/lambda/lambda_stop_prod.py"
  output_path      = "${path.module}/lambda_stop_prod.zip"
  output_file_mode = "0666"
}

# =============================================================================
# KMS Key for DynamoDB Encryption
# =============================================================================

resource "aws_kms_key" "finops_prod_dynamodb" {
  description             = "KMS key for finops-scheduler-state-prod DynamoDB table (LGPD compliance)"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(local.finops_prod_common_tags, {
    Name    = "finops-scheduler-dynamodb-prod"
    Purpose = "DynamoDB encryption for FinOps prod circuit breaker state"
  })
}

resource "aws_kms_alias" "finops_prod_dynamodb" {
  name          = "alias/finops-scheduler-dynamodb-prod"
  target_key_id = aws_kms_key.finops_prod_dynamodb.key_id
}

# =============================================================================
# DynamoDB Table — Circuit Breaker State
# =============================================================================

resource "aws_dynamodb_table" "finops_state_prod" {
  name         = "finops-scheduler-state-prod"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "environment"

  attribute {
    name = "environment"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.finops_prod_dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    # Prevent accidental deletion — contains circuit breaker state + previous replica counts
    prevent_destroy = true
    # Do NOT overwrite runtime state on re-apply (previous_replicas field managed by Lambda)
    ignore_changes = [tags]
  }

  tags = merge(local.finops_prod_common_tags, {
    Name       = "finops-scheduler-state-prod"
    Purpose    = "Circuit breaker state and previous replica state for prod FinOps"
    Compliance = "LGPD-OK"
    Encryption = "KMS-managed"
  })
}

# Initialize DynamoDB with default circuit breaker state
# lifecycle.ignore_changes prevents overwriting runtime Lambda updates
resource "aws_dynamodb_table_item" "finops_state_prod_initial" {
  table_name = aws_dynamodb_table.finops_state_prod.name
  hash_key   = aws_dynamodb_table.finops_state_prod.hash_key

  item = jsonencode({
    environment = {
      S = "prod"
    }
    startup_failures = {
      N = "0"
    }
    shutdown_failures = {
      N = "0"
    }
    circuit_breaker_state = {
      S = "CLOSED"
    }
    last_startup = {
      S = "never"
    }
    last_shutdown = {
      S = "never"
    }
    previous_replicas = {
      S = "{}"
    }
  })

  lifecycle {
    ignore_changes = [item] # Don't overwrite runtime Lambda state
  }
}

# =============================================================================
# SNS Topic — FinOps Prod Alerts
# =============================================================================

resource "aws_sns_topic" "finops_alerts_prod" {
  name = "k8s-platform-prod-finops-alerts-prod"

  tags = merge(local.finops_prod_common_tags, {
    Name    = "k8s-platform-prod-finops-alerts-prod"
    Purpose = "FinOps prod shutdown/startup notifications"
  })
}

# =============================================================================
# IAM Role — Lambda Execution (Prod)
# =============================================================================

resource "aws_iam_role" "finops_lambda_prod" {
  name        = "finops-automation-prod"
  description = "Execution role for FinOps prod scheduler Lambda (deployment scale strategy)"

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

  tags = merge(local.finops_prod_common_tags, {
    Name    = "finops-automation-prod"
    Purpose = "Lambda IAM role for prod FinOps workload scaling"
  })
}

# CloudWatch Logs (AWS Managed Policy)
resource "aws_iam_role_policy_attachment" "finops_prod_lambda_logs" {
  role       = aws_iam_role.finops_lambda_prod.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# EKS — Read cluster endpoint (for K8s API auth) + STS token generation
resource "aws_iam_role_policy" "finops_prod_eks_policy" {
  name = "finops-prod-eks-policy-v1"
  role = aws_iam_role.finops_lambda_prod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSDescribeCluster"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListNodegroups",
        ]
        # Scoped to this cluster only
        Resource = "arn:aws:eks:${data.aws_region.finops_prod.name}:${data.aws_caller_identity.finops_prod.account_id}:cluster/${local.finops_prod_cluster}"
      },
      {
        # Required to generate STS presigned token for K8s API authentication
        # (equivalent to `aws eks get-token` — used by lambda_start_prod + lambda_stop_prod)
        Sid    = "STSGetCallerIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      }
    ]
  })
}

# DynamoDB — Circuit breaker state + previous replica counts
resource "aws_iam_role_policy" "finops_prod_dynamodb_policy" {
  name = "finops-prod-dynamodb-policy-v1"
  role = aws_iam_role.finops_lambda_prod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CircuitBreakerAndReplicaState"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
        ]
        Resource = aws_dynamodb_table.finops_state_prod.arn
      },
      {
        Sid    = "DecryptDynamoDB"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = aws_kms_key.finops_prod_dynamodb.arn
      }
    ]
  })
}

# SNS — Publish notifications
resource "aws_iam_role_policy" "finops_prod_sns_policy" {
  name = "finops-prod-sns-policy-v1"
  role = aws_iam_role.finops_lambda_prod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "PublishFinOpsNotifications"
      Effect = "Allow"
      Action = ["sns:Publish"]
      Resource = aws_sns_topic.finops_alerts_prod.arn
    }]
  })
}

# CloudWatch — Custom metrics + log streams
resource "aws_iam_role_policy" "finops_prod_cloudwatch_policy" {
  name = "finops-prod-cloudwatch-policy-v1"
  role = aws_iam_role.finops_lambda_prod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PutCustomMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
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
          "logs:PutLogEvents",
        ]
        Resource = [
          aws_cloudwatch_log_group.finops_start_prod.arn,
          aws_cloudwatch_log_group.finops_stop_prod.arn,
          "${aws_cloudwatch_log_group.finops_start_prod.arn}:*",
          "${aws_cloudwatch_log_group.finops_stop_prod.arn}:*",
        ]
      }
    ]
  })
}

# =============================================================================
# CloudWatch Log Groups
# =============================================================================

resource "aws_cloudwatch_log_group" "finops_start_prod" {
  name              = "/aws/lambda/finops-scheduler-start-prod"
  retention_in_days = 14

  tags = local.finops_prod_common_tags
}

resource "aws_cloudwatch_log_group" "finops_stop_prod" {
  name              = "/aws/lambda/finops-scheduler-stop-prod"
  retention_in_days = 14

  tags = local.finops_prod_common_tags
}

# =============================================================================
# Lambda Functions
# =============================================================================

resource "aws_lambda_function" "finops_start_prod" {
  function_name    = "finops-scheduler-start-prod"
  description      = "FinOps prod: scale up deployments in prod-* namespaces (nodes NOT touched — shared cluster)"
  filename         = data.archive_file.lambda_start_prod.output_path
  source_code_hash = data.archive_file.lambda_start_prod.output_base64sha256

  runtime     = "python3.11"
  handler     = "lambda_start_prod.lambda_handler"
  timeout     = 300  # 5min — no node provisioning wait (nodes always running)
  memory_size = 256  # Lower than staging — no node health polling overhead

  role = aws_iam_role.finops_lambda_prod.arn

  environment {
    variables = {
      ENVIRONMENT               = local.finops_prod_environment
      CLUSTER_NAME              = local.finops_prod_cluster
      TARGET_NAMESPACES         = local.finops_prod_target_namespaces
      EXCLUDED_NAMESPACES       = local.finops_prod_excluded_namespaces
      DYNAMODB_TABLE_NAME       = aws_dynamodb_table.finops_state_prod.name
      SNS_TOPIC_ARN             = aws_sns_topic.finops_alerts_prod.arn
      CIRCUIT_BREAKER_THRESHOLD = "3"
      HEALTH_CHECK_ENABLED      = "true"
      WORKLOAD_TIMEOUT_SEC      = "300"
      LOG_LEVEL                 = "INFO"
      DRY_RUN                   = "false"
    }
  }

  # No VPC — consistent with staging decision (ADR-024: reduce NAT costs + latency)

  tags = merge(local.finops_prod_common_tags, {
    Name     = "finops-scheduler-start-prod"
    Function = "startup-automation"
  })

  depends_on = [
    aws_iam_role_policy_attachment.finops_prod_lambda_logs,
    aws_cloudwatch_log_group.finops_start_prod,
  ]
}

resource "aws_lambda_function" "finops_stop_prod" {
  function_name    = "finops-scheduler-stop-prod"
  description      = "FinOps prod: scale down deployments in prod-* namespaces (nodes NOT touched — shared cluster)"
  filename         = data.archive_file.lambda_stop_prod.output_path
  source_code_hash = data.archive_file.lambda_stop_prod.output_base64sha256

  runtime     = "python3.11"
  handler     = "lambda_stop_prod.lambda_handler"
  timeout     = 180  # 3min — only K8s API patch calls, no node drain wait
  memory_size = 256

  role = aws_iam_role.finops_lambda_prod.arn

  environment {
    variables = {
      ENVIRONMENT               = local.finops_prod_environment
      CLUSTER_NAME              = local.finops_prod_cluster
      TARGET_NAMESPACES         = local.finops_prod_target_namespaces
      EXCLUDED_NAMESPACES       = local.finops_prod_excluded_namespaces
      DYNAMODB_TABLE_NAME       = aws_dynamodb_table.finops_state_prod.name
      SNS_TOPIC_ARN             = aws_sns_topic.finops_alerts_prod.arn
      CIRCUIT_BREAKER_THRESHOLD = "3"
      LOG_LEVEL                 = "INFO"
      DRY_RUN                   = "false"
    }
  }

  tags = merge(local.finops_prod_common_tags, {
    Name     = "finops-scheduler-stop-prod"
    Function = "shutdown-automation"
  })

  depends_on = [
    aws_iam_role_policy_attachment.finops_prod_lambda_logs,
    aws_cloudwatch_log_group.finops_stop_prod,
  ]
}

# =============================================================================
# EventBridge Rules — Scheduled Start/Stop
# Schedules match staging for operational consistency (same office hours)
# =============================================================================

# Monday-Friday startup: 10:30 UTC = 07:30 BRT
resource "aws_cloudwatch_event_rule" "finops_startup_prod" {
  name                = "finops-startup-prod"
  description         = "Start prod workloads at 07:30 BRT (10:30 UTC) Mon-Fri"
  schedule_expression = "cron(30 10 ? * MON-FRI *)"
  state               = "ENABLED"

  tags = merge(local.finops_prod_common_tags, {
    Name     = "finops-startup-prod"
    Schedule = "07:30 BRT Mon-Fri"
  })
}

resource "aws_cloudwatch_event_target" "finops_startup_prod_target" {
  rule      = aws_cloudwatch_event_rule.finops_startup_prod.name
  target_id = "lambda-finops-start-prod"
  arn       = aws_lambda_function.finops_start_prod.arn

  input = jsonencode({
    action       = "start"
    environment  = "prod"
    triggered_by = "eventbridge-scheduler"
  })
}

resource "aws_lambda_permission" "finops_startup_prod_allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeStartupProd"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_start_prod.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.finops_startup_prod.arn
}

# Monday-Friday shutdown: 23:00 UTC = 20:00 BRT
resource "aws_cloudwatch_event_rule" "finops_shutdown_prod" {
  name                = "finops-shutdown-prod"
  description         = "Stop prod workloads at 20:00 BRT (23:00 UTC) Mon-Fri"
  schedule_expression = "cron(0 23 ? * MON-FRI *)"
  state               = "ENABLED"

  tags = merge(local.finops_prod_common_tags, {
    Name     = "finops-shutdown-prod"
    Schedule = "20:00 BRT Mon-Fri"
  })
}

resource "aws_cloudwatch_event_target" "finops_shutdown_prod_target" {
  rule      = aws_cloudwatch_event_rule.finops_shutdown_prod.name
  target_id = "lambda-finops-stop-prod"
  arn       = aws_lambda_function.finops_stop_prod.arn

  input = jsonencode({
    action       = "stop"
    environment  = "prod"
    triggered_by = "eventbridge-scheduler"
  })
}

resource "aws_lambda_permission" "finops_shutdown_prod_allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeShutdownProd"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_stop_prod.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.finops_shutdown_prod.arn
}

# Saturday shutdown: 03:00 UTC = 00:00 BRT Saturday
resource "aws_cloudwatch_event_rule" "finops_weekend_shutdown_prod" {
  name                = "finops-weekend-shutdown-prod"
  description         = "Stop prod workloads Saturday 00:00 BRT (03:00 UTC)"
  schedule_expression = "cron(0 3 ? * SAT *)"
  state               = "ENABLED"

  tags = merge(local.finops_prod_common_tags, {
    Name     = "finops-weekend-shutdown-prod"
    Schedule = "00:00 BRT Saturday"
  })
}

resource "aws_cloudwatch_event_target" "finops_weekend_shutdown_prod_target" {
  rule      = aws_cloudwatch_event_rule.finops_weekend_shutdown_prod.name
  target_id = "lambda-finops-weekend-stop-prod"
  arn       = aws_lambda_function.finops_stop_prod.arn

  input = jsonencode({
    action       = "stop"
    environment  = "prod"
    triggered_by = "eventbridge-weekend-scheduler"
  })
}

resource "aws_lambda_permission" "finops_weekend_shutdown_prod_allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeWeekendShutdownProd"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_stop_prod.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.finops_weekend_shutdown_prod.arn
}

# Sunday preventive shutdown: 23:00 UTC = 20:00 BRT Sunday
# Prevents residual billing if Lambda START is invoked manually on weekends (GAP-LAMBDA-RC2 pattern)
resource "aws_cloudwatch_event_rule" "finops_sunday_shutdown_prod" {
  name                = "finops-sunday-shutdown-prod"
  description         = "Preventive stop prod workloads Sunday 20:00 BRT (23:00 UTC) — GAP-LAMBDA-RC2 pattern"
  schedule_expression = "cron(0 23 ? * SUN *)"
  state               = "ENABLED"

  tags = merge(local.finops_prod_common_tags, {
    Name     = "finops-sunday-shutdown-prod"
    Schedule = "20:00 BRT Sunday"
    Purpose  = "GAP-LAMBDA-RC2-pattern-prod"
  })
}

resource "aws_cloudwatch_event_target" "finops_sunday_shutdown_prod_target" {
  rule      = aws_cloudwatch_event_rule.finops_sunday_shutdown_prod.name
  target_id = "lambda-finops-sunday-stop-prod"
  arn       = aws_lambda_function.finops_stop_prod.arn

  input = jsonencode({
    action       = "stop"
    environment  = "prod"
    triggered_by = "eventbridge-sunday-scheduler"
  })
}

resource "aws_lambda_permission" "finops_sunday_shutdown_prod_allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridgeSundayShutdownProd"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finops_stop_prod.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.finops_sunday_shutdown_prod.arn
}

# =============================================================================
# CloudWatch Alarms
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "finops_prod_startup_failures" {
  alarm_name          = "finops-prod-startup-failures"
  alarm_description   = "FinOps prod START Lambda errors (circuit breaker risk)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.finops_start_prod.function_name
  }

  alarm_actions = [aws_sns_topic.finops_alerts_prod.arn]
  ok_actions    = [aws_sns_topic.finops_alerts_prod.arn]

  tags = local.finops_prod_common_tags
}

resource "aws_cloudwatch_metric_alarm" "finops_prod_shutdown_failures" {
  alarm_name          = "finops-prod-shutdown-failures"
  alarm_description   = "FinOps prod STOP Lambda errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.finops_stop_prod.function_name
  }

  alarm_actions = [aws_sns_topic.finops_alerts_prod.arn]
  ok_actions    = [aws_sns_topic.finops_alerts_prod.arn]

  tags = local.finops_prod_common_tags
}

# =============================================================================
# Outputs
# =============================================================================

output "finops_prod_lambda_start_arn" {
  description = "ARN of the FinOps prod START Lambda function"
  value       = aws_lambda_function.finops_start_prod.arn
}

output "finops_prod_lambda_stop_arn" {
  description = "ARN of the FinOps prod STOP Lambda function"
  value       = aws_lambda_function.finops_stop_prod.arn
}

output "finops_prod_dynamodb_table" {
  description = "DynamoDB table name for prod circuit breaker state"
  value       = aws_dynamodb_table.finops_state_prod.name
}

output "finops_prod_sns_topic_arn" {
  description = "SNS topic ARN for prod FinOps alerts"
  value       = aws_sns_topic.finops_alerts_prod.arn
}

# =============================================================================
# GAP-LAMBDA-001 (2026-03-26): RBAC IaC parity — ClusterRole + ClusterRoleBinding
# ClusterRole já existia no cluster (drift); codificado aqui para zero-drift.
# CRB: kind=User (Lambda IAM role → aws-auth → k8s user finops-automation-prod)
# =============================================================================
resource "kubectl_manifest" "finops_prod_clusterrole" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: finops-automation-prod
      labels:
        app: finops-automation
        environment: prod
    rules:
      - apiGroups: ["apps"]
        resources: ["deployments", "statefulsets"]
        verbs: ["get", "list", "patch", "update"]
      - apiGroups: [""]
        resources: ["pods", "namespaces"]
        verbs: ["get", "list"]
      - apiGroups: ["rabbitmq.com"]
        resources: ["rabbitmqclusters"]
        verbs: ["get", "list", "watch"]
  YAML
}

resource "kubectl_manifest" "finops_prod_clusterrolebinding" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: finops-automation-prod
      labels:
        app: finops-automation
        environment: prod
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: finops-automation-prod
    subjects:
      - kind: User
        name: finops-automation-prod
        apiGroup: rbac.authorization.k8s.io
  YAML
  depends_on = [kubectl_manifest.finops_prod_clusterrole]
}
