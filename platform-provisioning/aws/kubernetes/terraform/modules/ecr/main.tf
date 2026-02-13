# ECR Repository Module - Auto-Delete Untagged Images >7 Days
#
# Purpose: Manage ECR repositories with lifecycle policies for cost optimization
# Pattern: Time-based expiration (7 days) for untagged images
# Savings: ~$0.10/GB/month ECR storage cost reduction

resource "aws_ecr_repository" "repositories" {
  for_each = var.repositories

  name                 = each.key
  image_tag_mutability = each.value.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  encryption_configuration {
    encryption_type = each.value.encryption_type
    kms_key         = each.value.kms_key_arn
  }

  tags = merge(
    var.common_tags,
    {
      Name        = each.key
      ManagedBy   = "Terraform"
      Module      = "ecr"
      Environment = var.environment
    }
  )
}

resource "aws_ecr_lifecycle_policy" "cleanup_untagged" {
  for_each = var.repositories

  repository = aws_ecr_repository.repositories[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiration_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only last ${var.tagged_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = var.tagged_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Optional: Repository policy for cross-account access
resource "aws_ecr_repository_policy" "cross_account" {
  for_each = {
    for k, v in var.repositories : k => v
    if v.allow_cross_account_pull && length(v.trusted_account_ids) > 0
  }

  repository = aws_ecr_repository.repositories[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountPull"
        Effect = "Allow"
        Principal = {
          AWS = [
            for account_id in each.value.trusted_account_ids :
            "arn:aws:iam::${account_id}:root"
          ]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}
