#------------------------------------------------------------------------------
# IAM Policy — ECR Pull-Through Cache (Node Role)
#
# Purpose: Allow EKS node role to pull images via pull-through cache
# Actions: BatchImportUpstreamImage (pull from upstream), CreateRepository (auto-create)
# Scope: Restricted to pull-through cache prefixes only
#------------------------------------------------------------------------------

resource "aws_iam_policy" "ecr_pull_through_cache" {
  name        = "${var.cluster_name}-ecr-pull-through-cache-policy"
  description = "Allow EKS nodes to use ECR pull-through cache for upstream registries"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPullThroughCache"
        Effect = "Allow"
        Action = [
          "ecr:BatchImportUpstreamImage",
          "ecr:CreateRepository",
          "ecr:TagResource"
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/ecr-public/*",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/docker-hub/*",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/quay/*",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/ghcr/*",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/k8s/*"
        ]
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name      = "${var.cluster_name}-ecr-pull-through-cache-policy"
    ManagedBy = "Terraform"
  })
}

resource "aws_iam_role_policy_attachment" "ecr_pull_through_cache" {
  role       = var.node_role_name
  policy_arn = aws_iam_policy.ecr_pull_through_cache.arn
}

#------------------------------------------------------------------------------
# IAM Role — ECR Repository Creation Template (Custom Role)
#
# Purpose: Custom role assumed by ECR service when creating repositories via
#          pull-through cache with repository creation templates.
# Root cause: The default AWSServiceRoleForECRTemplate only has ecr:CreateRepository
#             but NOT ecr:TagResource. When templates include resource_tags, the
#             service-linked role fails with AccessDenied on ecr:TagResource,
#             causing pull-through cache to silently return 404 on all pulls.
# Fix: This custom role grants ecr:CreateRepository + ecr:TagResource +
#      ecr:ReplicateImage, allowing templates with resource_tags to work.
# Ref: CloudTrail event ECRPullThroughCacheWithTemplate AccessDenied ecr:TagResource
#------------------------------------------------------------------------------

resource "aws_iam_role" "ecr_template_custom" {
  name = "${var.cluster_name}-ecr-template-role"
  description = "Custom role for ECR repository creation templates (pull-through cache with tags)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECRServiceAssume"
        Effect = "Allow"
        Principal = {
          Service = "ecr.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name      = "${var.cluster_name}-ecr-template-role"
    Purpose   = "ECR pull-through cache repository creation with tags"
    ManagedBy = "Terraform"
  })
}

resource "aws_iam_role_policy" "ecr_template_custom" {
  name = "${var.cluster_name}-ecr-template-policy"
  role = aws_iam_role.ecr_template_custom.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRepoCreationWithTags"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:TagResource",
          "ecr:ReplicateImage",
          "ecr:PutLifecyclePolicy",
          "ecr:SetRepositoryPolicy"
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/ecr-public/*",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/docker-hub/*",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/quay/*",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/ghcr/*",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/k8s/*"
        ]
      }
    ]
  })
}
