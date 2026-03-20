#------------------------------------------------------------------------------
# ECR Pull-Through Cache Module
#
# Purpose: Cache upstream container images (ECR Public, Quay, GHCR, K8s Registry)
#          in private ECR to eliminate Docker Hub rate limits (429 errors).
# Pattern: Pull-through cache rules + repository creation templates
# Registries: ecr-public, quay, ghcr, registry.k8s.io
# GAP: GAP-SEC-REGISTRY-03
#------------------------------------------------------------------------------

locals {
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 30 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# ECR Public (public.ecr.aws)
#------------------------------------------------------------------------------

resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  count = var.enable_ecr_public ? 1 : 0

  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}

resource "aws_ecr_repository_creation_template" "ecr_public" {
  count = var.enable_ecr_public ? 1 : 0

  prefix      = "ecr-public"
  description = "Pull-through cache template for ECR Public"
  applied_for = ["PULL_THROUGH_CACHE"]

  image_tag_mutability = "MUTABLE"
  custom_role_arn      = aws_iam_role.ecr_template_custom.arn

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy = local.lifecycle_policy

  resource_tags = merge(var.common_tags, {
    Source    = "public.ecr.aws"
    ManagedBy = "Terraform"
  })

  depends_on = [aws_ecr_pull_through_cache_rule.ecr_public]
}

#------------------------------------------------------------------------------
# Quay.io
#------------------------------------------------------------------------------

resource "aws_ecr_pull_through_cache_rule" "quay" {
  count = var.enable_quay ? 1 : 0

  ecr_repository_prefix = "quay"
  upstream_registry_url = "quay.io"
}

resource "aws_ecr_repository_creation_template" "quay" {
  count = var.enable_quay ? 1 : 0

  prefix      = "quay"
  description = "Pull-through cache template for Quay.io"
  applied_for = ["PULL_THROUGH_CACHE"]

  image_tag_mutability = "MUTABLE"
  custom_role_arn      = aws_iam_role.ecr_template_custom.arn

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy = local.lifecycle_policy

  resource_tags = merge(var.common_tags, {
    Source    = "quay.io"
    ManagedBy = "Terraform"
  })

  depends_on = [aws_ecr_pull_through_cache_rule.quay]
}

#------------------------------------------------------------------------------
# GitHub Container Registry (ghcr.io)
#------------------------------------------------------------------------------

resource "aws_ecr_pull_through_cache_rule" "ghcr" {
  count = var.enable_ghcr ? 1 : 0

  ecr_repository_prefix = "ghcr"
  upstream_registry_url = "ghcr.io"
}

resource "aws_ecr_repository_creation_template" "ghcr" {
  count = var.enable_ghcr ? 1 : 0

  prefix      = "ghcr"
  description = "Pull-through cache template for GitHub Container Registry"
  applied_for = ["PULL_THROUGH_CACHE"]

  image_tag_mutability = "MUTABLE"
  custom_role_arn      = aws_iam_role.ecr_template_custom.arn

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy = local.lifecycle_policy

  resource_tags = merge(var.common_tags, {
    Source    = "ghcr.io"
    ManagedBy = "Terraform"
  })

  depends_on = [aws_ecr_pull_through_cache_rule.ghcr]
}

#------------------------------------------------------------------------------
# Kubernetes Registry (registry.k8s.io)
#------------------------------------------------------------------------------

resource "aws_ecr_pull_through_cache_rule" "k8s" {
  count = var.enable_k8s ? 1 : 0

  ecr_repository_prefix = "k8s"
  upstream_registry_url = "registry.k8s.io"
}

resource "aws_ecr_repository_creation_template" "k8s" {
  count = var.enable_k8s ? 1 : 0

  prefix      = "k8s"
  description = "Pull-through cache template for Kubernetes Registry"
  applied_for = ["PULL_THROUGH_CACHE"]

  image_tag_mutability = "MUTABLE"
  custom_role_arn      = aws_iam_role.ecr_template_custom.arn

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy = local.lifecycle_policy

  resource_tags = merge(var.common_tags, {
    Source    = "registry.k8s.io"
    ManagedBy = "Terraform"
  })

  depends_on = [aws_ecr_pull_through_cache_rule.k8s]
}

#------------------------------------------------------------------------------
# Docker Hub (registry-1.docker.io) — requires credentials in Secrets Manager
#------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "docker_hub" {
  count = var.enable_docker_hub ? 1 : 0

  name        = "ecr-pullthroughcache/docker-hub"
  description = "Docker Hub credentials for ECR pull-through cache"

  tags = merge(var.common_tags, {
    Name      = "ecr-pullthroughcache/docker-hub"
    Purpose   = "ECR pull-through cache Docker Hub authentication"
    ManagedBy = "Terraform"
  })
}

resource "aws_secretsmanager_secret_version" "docker_hub" {
  count = var.enable_docker_hub ? 1 : 0

  secret_id = aws_secretsmanager_secret.docker_hub[0].id
  secret_string = jsonencode({
    username    = var.docker_hub_username
    accessToken = var.docker_hub_access_token
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_ecr_pull_through_cache_rule" "docker_hub" {
  count = var.enable_docker_hub ? 1 : 0

  ecr_repository_prefix = "docker-hub"
  upstream_registry_url = "registry-1.docker.io"
  credential_arn        = aws_secretsmanager_secret.docker_hub[0].arn
}

resource "aws_ecr_repository_creation_template" "docker_hub" {
  count = var.enable_docker_hub ? 1 : 0

  prefix      = "docker-hub"
  description = "Pull-through cache template for Docker Hub"
  applied_for = ["PULL_THROUGH_CACHE"]

  image_tag_mutability = "MUTABLE"
  custom_role_arn      = aws_iam_role.ecr_template_custom.arn

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy = local.lifecycle_policy

  resource_tags = merge(var.common_tags, {
    Source    = "registry-1.docker.io"
    ManagedBy = "Terraform"
  })

  depends_on = [aws_ecr_pull_through_cache_rule.docker_hub]
}
