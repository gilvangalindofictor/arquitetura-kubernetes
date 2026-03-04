# =============================================================================
# Terraform: IAM Role for YACE CloudWatch Exporter (IRSA)
# GAP-010: YACE needs read access to CloudWatch (WAFV2) metrics
#
# Creates:
#   - IAM Policy: k8s-platform-yace-cloudwatch-policy
#   - IAM Role:   k8s-platform-yace-cloudwatch-role (IRSA trust → OIDC)
#   - Attachment: policy → role
#
# Usage:
#   Place this file in: platform-provisioning/aws/kubernetes/terraform/environments/staging/
#   OR include as module call from root staging.tf
#
#   terraform init && terraform apply -target=aws_iam_role.yace_cloudwatch
#
# OIDC values from cluster:
#   aws eks describe-cluster --name k8s-platform-prod --query "cluster.identity.oidc.issuer" --output text
# =============================================================================

locals {
  # EKS cluster OIDC issuer — strip "https://" prefix to get the provider identifier
  # Example: oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE
  yace_oidc_provider_url = replace(data.aws_eks_cluster.current.identity[0].oidc[0].issuer, "https://", "")
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------
data "aws_eks_cluster" "current" {
  name = "k8s-platform-prod"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# IAM Policy — minimal CloudWatch + WAFV2 read permissions
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "yace_cloudwatch" {
  name        = "k8s-platform-yace-cloudwatch-policy"
  description = "GAP-010: YACE CloudWatch Exporter read access to WAFV2 metrics"
  path        = "/k8s-platform/"

  policy = file("${path.module}/iam-policy.json")

  tags = {
    Name        = "k8s-platform-yace-cloudwatch-policy"
    Environment = "staging"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
    Gap         = "GAP-010"
    Component   = "yace-cloudwatch-exporter"
  }
}

# ---------------------------------------------------------------------------
# IAM Role — IRSA trust relationship with EKS OIDC provider
# The ServiceAccount "yace-cloudwatch-exporter" in namespace
# "staging-observability-monitoring" is authorized to assume this role.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "yace_cloudwatch" {
  name        = "k8s-platform-yace-cloudwatch-role"
  description = "GAP-010: IRSA role for YACE CloudWatch Exporter pod"
  path        = "/k8s-platform/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSOIDCTrustYACE"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::891377105802:oidc-provider/${local.yace_oidc_provider_url}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.yace_oidc_provider_url}:sub" = "system:serviceaccount:staging-observability-monitoring:yace-cloudwatch-exporter"
            "${local.yace_oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "k8s-platform-yace-cloudwatch-role"
    Environment = "staging"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
    Gap         = "GAP-010"
    Component   = "yace-cloudwatch-exporter"
    # Role purpose annotation for AWS Console visibility
    Purpose     = "IRSA for YACE CloudWatch Exporter - reads WAFV2 metrics from CloudWatch"
  }
}

# ---------------------------------------------------------------------------
# Policy attachment
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "yace_cloudwatch" {
  role       = aws_iam_role.yace_cloudwatch.name
  policy_arn = aws_iam_policy.yace_cloudwatch.arn
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "yace_cloudwatch_role_arn" {
  description = "ARN of the IRSA role for YACE — use in Helm values serviceAccount.annotations"
  value       = aws_iam_role.yace_cloudwatch.arn
}

output "yace_cloudwatch_policy_arn" {
  description = "ARN of the IAM policy for YACE CloudWatch access"
  value       = aws_iam_policy.yace_cloudwatch.arn
}
