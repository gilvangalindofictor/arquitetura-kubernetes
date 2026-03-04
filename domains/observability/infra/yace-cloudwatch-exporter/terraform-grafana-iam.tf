# =============================================================================
# Terraform: IAM Role for Grafana ServiceAccount (IRSA)
# GAP-010: Grafana needs read access to CloudWatch for WAF dashboard
#
# Creates:
#   - IAM Policy: k8s-platform-grafana-cloudwatch-policy
#   - IAM Role:   k8s-platform-grafana-cloudwatch-role (IRSA trust → OIDC)
#   - Attachment: policy → role
#
# The Grafana pod uses authType=default in the CloudWatch datasource,
# which resolves credentials via the AWS credential chain. With IRSA,
# the chain finds the projected ServiceAccount token and calls
# sts:AssumeRoleWithWebIdentity automatically.
#
# Apply:
#   terraform apply -target=aws_iam_role.grafana_cloudwatch
#   kubectl patch sa kube-prometheus-stack-grafana -n staging-observability-monitoring \
#     -p '{"metadata":{"annotations":{"eks.amazonaws.com/role-arn":"arn:aws:iam::891377105802:role/k8s-platform-grafana-cloudwatch-role"}}}'
#   kubectl rollout restart deployment/kube-prometheus-stack-grafana -n staging-observability-monitoring
# =============================================================================

# ---------------------------------------------------------------------------
# IAM Policy — Grafana CloudWatch read-only (metrics + logs dimensions)
# Grafana needs ListMetrics + GetMetricData to populate the dashboard query builder.
# It does NOT need wafv2:* since it reads from CloudWatch, not the WAF API directly.
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "grafana_cloudwatch" {
  name        = "k8s-platform-grafana-cloudwatch-policy"
  description = "GAP-010: Grafana read access to CloudWatch metrics for WAF dashboard"
  path        = "/k8s-platform/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GrafanaCloudWatchReadMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport"
        ]
        Resource = "*"
      },
      {
        Sid    = "GrafanaCloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "GrafanaEC2TagsForDimensions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "k8s-platform-grafana-cloudwatch-policy"
    Environment = "staging"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
    Gap         = "GAP-010"
    Component   = "grafana"
  }
}

# ---------------------------------------------------------------------------
# IAM Role — IRSA trust for Grafana SA
# ---------------------------------------------------------------------------
resource "aws_iam_role" "grafana_cloudwatch" {
  name        = "k8s-platform-grafana-cloudwatch-role"
  description = "GAP-010: IRSA role for Grafana pod to read CloudWatch WAF metrics"
  path        = "/k8s-platform/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSOIDCTrustGrafana"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::891377105802:oidc-provider/${local.yace_oidc_provider_url}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.yace_oidc_provider_url}:sub" = "system:serviceaccount:staging-observability-monitoring:kube-prometheus-stack-grafana"
            "${local.yace_oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "k8s-platform-grafana-cloudwatch-role"
    Environment = "staging"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
    Gap         = "GAP-010"
    Component   = "grafana"
    Purpose     = "IRSA for Grafana - CloudWatch datasource for WAF dashboard"
  }
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  role       = aws_iam_role.grafana_cloudwatch.name
  policy_arn = aws_iam_policy.grafana_cloudwatch.arn
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "grafana_cloudwatch_role_arn" {
  description = "ARN of the IRSA role for Grafana — use in grafana-sa-irsa-patch.yaml"
  value       = aws_iam_role.grafana_cloudwatch.arn
}
