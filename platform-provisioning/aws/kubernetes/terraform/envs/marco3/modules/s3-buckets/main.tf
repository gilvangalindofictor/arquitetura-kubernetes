# =============================================================================
# S3 Buckets Module - Marco 3 Data Services
# Buckets:
#   1. gitlab-artifacts - CI/CD build artifacts
#   2. harbor-images - Container registry images
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# GitLab Artifacts Bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "gitlab_artifacts" {
  bucket = "k8s-platform-gitlab-artifacts-${var.aws_account_id}"

  tags = merge(var.common_tags, {
    Name    = "GitLab Artifacts"
    Purpose = "CI/CD artifacts storage"
    Service = "GitLab"
  })
}

resource "aws_s3_bucket_versioning" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Harbor Images Bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "harbor_images" {
  bucket = "k8s-platform-harbor-images-${var.aws_account_id}"

  tags = merge(var.common_tags, {
    Name    = "Harbor Container Images"
    Purpose = "OCI image storage"
    Service = "Harbor"
  })
}

resource "aws_s3_bucket_versioning" "harbor_images" {
  bucket = aws_s3_bucket.harbor_images.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "harbor_images" {
  bucket = aws_s3_bucket.harbor_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "harbor_images" {
  bucket = aws_s3_bucket.harbor_images.id

  rule {
    id     = "transition-old-layers"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER_IR"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "harbor_images" {
  bucket = aws_s3_bucket.harbor_images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# IAM Policy for GitLab S3 Access (IRSA)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "gitlab_s3" {
  statement {
    sid    = "AllowGitLabS3Access"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:AbortMultipartUpload"
    ]

    resources = [
      aws_s3_bucket.gitlab_artifacts.arn,
      "${aws_s3_bucket.gitlab_artifacts.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "gitlab_s3" {
  name_prefix = "${var.cluster_name}-gitlab-s3-"
  description = "IAM policy for GitLab to access S3 artifacts bucket"
  policy      = data.aws_iam_policy_document.gitlab_s3.json

  tags = merge(var.common_tags, {
    Service = "GitLab"
    Purpose = "IRSA"
  })
}

# -----------------------------------------------------------------------------
# IAM Policy for Harbor S3 Access (IRSA)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "harbor_s3" {
  statement {
    sid    = "AllowHarborS3Access"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:AbortMultipartUpload"
    ]

    resources = [
      aws_s3_bucket.harbor_images.arn,
      "${aws_s3_bucket.harbor_images.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "harbor_s3" {
  name_prefix = "${var.cluster_name}-harbor-s3-"
  description = "IAM policy for Harbor to access S3 images bucket"
  policy      = data.aws_iam_policy_document.harbor_s3.json

  tags = merge(var.common_tags, {
    Service = "Harbor"
    Purpose = "IRSA"
  })
}

# -----------------------------------------------------------------------------
# IAM Roles for Service Accounts (IRSA) - To be used by GitLab/Harbor Helm
# -----------------------------------------------------------------------------

# Note: The actual IRSA role creation will be done in the GitLab/Harbor modules
# where we have access to the OIDC provider ARN. These policies will be attached
# to those roles.

# Export policy ARNs for use in other modules
