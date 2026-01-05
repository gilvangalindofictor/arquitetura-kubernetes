# IAM Module for Observability Platform
# IRSA (IAM Roles for Service Accounts) for namespace isolation
# Follows ADR-002: IAM roles per namespace (dev/hml/prd)

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "observability"
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider"
  type        = string
}

variable "s3_bucket_arns" {
  description = "Map of S3 bucket ARNs (metrics, logs, traces, backups)"
  type        = map(string)
}

variable "namespaces" {
  description = "Kubernetes namespaces for observability workloads"
  type        = list(string)
  default     = ["observability-dev", "observability-hml", "observability-prd"]
}

# IAM Policy for S3 Access (Prometheus, Loki, Tempo)
resource "aws_iam_policy" "s3_access" {
  name        = "${var.project_name}-s3-access-policy"
  description = "Policy for observability components to access S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = flatten([
          for arn in values(var.s3_bucket_arns) : [
            arn,
            "${arn}/*"
          ]
        ])
      }
    ]
  })

  tags = {
    Name      = "${var.project_name}-s3-access-policy"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# IAM Roles for Service Accounts (IRSA) per namespace
resource "aws_iam_role" "namespace_sa" {
  for_each = toset(var.namespaces)

  name = "${var.project_name}-${each.value}-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${each.value}:*"
          "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name      = "${var.project_name}-${each.value}-sa-role"
    Project   = var.project_name
    ManagedBy = "terraform"
    Namespace = each.value
  }
}

# Attach S3 Access Policy to namespace roles
resource "aws_iam_role_policy_attachment" "namespace_s3" {
  for_each = toset(var.namespaces)

  role       = aws_iam_role.namespace_sa[each.value].name
  policy_arn = aws_iam_policy.s3_access.arn
}

# IAM Policy for CloudWatch Logs (optional for EKS control plane logs)
resource "aws_iam_policy" "cloudwatch_logs" {
  name        = "${var.project_name}-cloudwatch-logs-policy"
  description = "Policy for reading EKS control plane logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ]
      Resource = "*"
    }]
  })

  tags = {
    Name      = "${var.project_name}-cloudwatch-logs-policy"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# Outputs
output "namespace_role_arns" {
  description = "Map of namespace names to IAM role ARNs"
  value       = { for k, v in aws_iam_role.namespace_sa : k => v.arn }
}

output "s3_access_policy_arn" {
  description = "ARN of the S3 access policy"
  value       = aws_iam_policy.s3_access.arn
}

output "cloudwatch_logs_policy_arn" {
  description = "ARN of the CloudWatch logs policy"
  value       = aws_iam_policy.cloudwatch_logs.arn
}
