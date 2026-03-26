# =============================================================================
# S3 Buckets Module - Marco 3 Data Services
# Buckets:
#   1. gitlab-artifacts - CI/CD build artifacts
#   2. harbor-images - Container registry images
#   3. keycloak-backups - Keycloak realm backups (TASK-003)
#   4. fct-proposals - ETL unified storage (TASK-004)
# =============================================================================

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.sa_east_1]
    }
  }
}

# -----------------------------------------------------------------------------
# GitLab Artifacts Bucket
# -----------------------------------------------------------------------------

# DEC-2026-03-24: gitlab_artifacts resources are now conditional via enable_gitlab_artifacts.
# Staging sets enable_gitlab_artifacts = false (bucket is shared, managed by prod state).
# Prod keeps default = true (single source of truth).

resource "aws_s3_bucket" "gitlab_artifacts" {
  count  = var.enable_gitlab_artifacts ? 1 : 0
  bucket = "k8s-platform-gitlab-artifacts-${var.aws_account_id}"

  tags = merge(var.common_tags, {
    Name    = "GitLab Artifacts"
    Purpose = "CI/CD artifacts storage"
    Service = "GitLab"
  })
}

resource "aws_s3_bucket_versioning" "gitlab_artifacts" {
  count  = var.enable_gitlab_artifacts ? 1 : 0
  bucket = aws_s3_bucket.gitlab_artifacts[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab_artifacts" {
  count  = var.enable_gitlab_artifacts ? 1 : 0
  bucket = aws_s3_bucket.gitlab_artifacts[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "gitlab_artifacts" {
  count  = var.enable_gitlab_artifacts ? 1 : 0
  bucket = aws_s3_bucket.gitlab_artifacts[0].id

  # Rule 1: Intelligent-Tiering for active artifacts (auto-optimize costs)
  rule {
    id     = "intelligent-tiering"
    status = "Enabled"

    filter {
      and {
        prefix = ""
        tags = {
          "Tiering" = "auto"
        }
      }
    }

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  # Rule 2: Expire old artifacts (cleanup)
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
  count  = var.enable_gitlab_artifacts ? 1 : 0
  bucket = aws_s3_bucket.gitlab_artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Intelligent-Tiering Configuration (Archive Access tiers)
resource "aws_s3_bucket_intelligent_tiering_configuration" "gitlab_artifacts" {
  count  = var.enable_gitlab_artifacts ? 1 : 0
  bucket = aws_s3_bucket.gitlab_artifacts[0].id
  name   = "EntireBucket"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
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

  # Rule 1: Intelligent-Tiering for container images (auto-optimize)
  rule {
    id     = "intelligent-tiering-images"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  # Rule 2: Additional transitions for long-term storage (compliance)
  rule {
    id     = "transition-old-layers"
    status = "Enabled"

    filter {
      prefix = "docker/registry/v2/blobs/"
    }

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

# Intelligent-Tiering Configuration (Archive Access tiers)
resource "aws_s3_bucket_intelligent_tiering_configuration" "harbor_images" {
  bucket = aws_s3_bucket.harbor_images.id
  name   = "EntireBucket"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

# -----------------------------------------------------------------------------
# Keycloak Backups Bucket (TASK-003)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "keycloak_backups" {
  bucket = "k8s-platform-keycloak-backups-${var.aws_account_id}"

  # NOTE: Using provider default_tags only due to Terraform/AWS provider tag handling issue
  # Tags will be applied via provider default_tags in environments/staging/main.tf
  # Specific tags (Name, Purpose, Service) applied manually via AWS CLI

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_s3_bucket_versioning" "keycloak_backups" {
  bucket = aws_s3_bucket.keycloak_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "keycloak_backups" {
  bucket = aws_s3_bucket.keycloak_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "keycloak_backups" {
  bucket = aws_s3_bucket.keycloak_backups.id

  # Rule: Expire old backups after 30 days (DR compliance)
  # Note: Backups are kept in STANDARD storage class for full 30 days
  # (STANDARD_IA transition requires minimum 30 days, which equals our expiration)
  rule {
    id     = "retain-30-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "keycloak_backups" {
  bucket = aws_s3_bucket.keycloak_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# IAM Policy for GitLab S3 Access (IRSA)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "gitlab_s3" {
  count = var.enable_gitlab_artifacts ? 1 : 0

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
      aws_s3_bucket.gitlab_artifacts[0].arn,
      "${aws_s3_bucket.gitlab_artifacts[0].arn}/*"
    ]
  }
}

resource "aws_iam_policy" "gitlab_s3" {
  count       = var.enable_gitlab_artifacts ? 1 : 0
  name_prefix = "${var.cluster_name}-gitlab-s3-"
  description = "IAM policy for GitLab to access S3 artifacts bucket"
  policy      = data.aws_iam_policy_document.gitlab_s3[0].json

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
# IAM Policy for Keycloak Backup S3 Access (IRSA)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "keycloak_backup_s3" {
  statement {
    sid    = "AllowKeycloakBackupS3Access"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      aws_s3_bucket.keycloak_backups.arn,
      "${aws_s3_bucket.keycloak_backups.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "keycloak_backup_s3" {
  name_prefix = "${var.cluster_name}-keycloak-backup-s3-"
  description = "IAM policy for Keycloak backup job to access S3 backups bucket"
  policy      = data.aws_iam_policy_document.keycloak_backup_s3.json

  tags = merge(var.common_tags, {
    Service = "Keycloak"
    Purpose = "IRSA-Backup"
  })
}

# -----------------------------------------------------------------------------
# IAM Roles for Service Accounts (IRSA) - To be used by GitLab/Harbor Helm
# -----------------------------------------------------------------------------

# Note: The actual IRSA role creation will be done in the GitLab/Harbor modules
# where we have access to the OIDC provider ARN. These policies will be attached
# to those roles.

# Export policy ARNs for use in other modules

# -----------------------------------------------------------------------------
# FCT Proposals Bucket (ETL Unified Storage) - TASK-004
# Cross-region deployment: sa-east-1 (LGPD compliance)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "fct_proposals" {
  count    = var.enable_fct_proposals ? 1 : 0
  provider = aws.sa_east_1

  bucket = "k8s-platform-fct-proposals-${var.aws_account_id}"

  # NOTE: Tags applied via provider default_tags only
  # Manual tags (Name, Purpose, etc.) must be applied via AWS CLI after creation
  # Reason: Terraform/AWS provider tag conflict (InvalidTag error)

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_s3_bucket_public_access_block" "fct_proposals" {
  count    = var.enable_fct_proposals ? 1 : 0
  provider = aws.sa_east_1
  bucket   = aws_s3_bucket.fct_proposals[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "fct_proposals" {
  count    = var.enable_fct_proposals ? 1 : 0
  provider = aws.sa_east_1
  bucket   = aws_s3_bucket.fct_proposals[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "fct_proposals" {
  count    = var.enable_fct_proposals ? 1 : 0
  provider = aws.sa_east_1
  bucket   = aws_s3_bucket.fct_proposals[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "fct_proposals" {
  count    = var.enable_fct_proposals ? 1 : 0
  provider = aws.sa_east_1
  bucket   = aws_s3_bucket.fct_proposals[0].id
  name     = "proposals-tiering"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "fct_proposals" {
  count    = var.enable_fct_proposals ? 1 : 0
  provider = aws.sa_east_1
  bucket   = aws_s3_bucket.fct_proposals[0].id

  rule {
    id     = "cleanup-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 2555 # 7 years (LGPD retention)
    }
  }
}

# -----------------------------------------------------------------------------
# IAM Policy: hatch-etl-s3-fct-proposals
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "hatch_etl_fct_proposals" {
  count = var.enable_fct_proposals ? 1 : 0

  statement {
    sid    = "ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      aws_s3_bucket.fct_proposals[0].arn
    ]
  }

  statement {
    sid    = "ObjectOperations"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObjectTagging",
      "s3:GetObjectTagging"
    ]
    resources = [
      "${aws_s3_bucket.fct_proposals[0].arn}/*"
    ]
  }
}

resource "aws_iam_policy" "hatch_etl_fct_proposals" {
  count       = var.enable_fct_proposals ? 1 : 0
  name        = "hatch-etl-s3-fct-proposals"
  description = "IAM policy for Hatch ETL to access S3 fct-proposals bucket"
  policy      = data.aws_iam_policy_document.hatch_etl_fct_proposals[0].json

  tags = merge(var.common_tags, {
    Service = "Hatch-ETL"
    Purpose = "S3-Access"
  })
}

# -----------------------------------------------------------------------------
# IAM Policy: bucketconnector-s3-fct-proposals
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "bucketconnector_fct_proposals" {
  count = var.enable_fct_proposals ? 1 : 0

  statement {
    sid    = "FullBucketAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObjectTagging",
      "s3:GetObjectTagging"
    ]
    resources = [
      aws_s3_bucket.fct_proposals[0].arn,
      "${aws_s3_bucket.fct_proposals[0].arn}/*"
    ]
  }
}

resource "aws_iam_policy" "bucketconnector_fct_proposals" {
  count       = var.enable_fct_proposals ? 1 : 0
  name        = "bucketconnector-s3-fct-proposals"
  description = "IAM policy for BucketConnector CLI to manage fct-proposals bucket"
  policy      = data.aws_iam_policy_document.bucketconnector_fct_proposals[0].json

  tags = merge(var.common_tags, {
    Service = "BucketConnector"
    Purpose = "S3-Admin"
  })
}

# -----------------------------------------------------------------------------
# Backstage TechDocs Bucket
# Armazena HTMLs gerados pelo mkdocs (pipeline GitLab CI via @techdocs/cli)
# IRSA: backstage-irsa-role tem PutObject/GetObject/DeleteObject/ListBucket
# Acesso: apenas backstage-irsa-role (sem acesso público)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "backstage_techdocs" {
  bucket = "backstage-techdocs-${var.aws_account_id}"

  tags = merge(var.common_tags, {
    Name    = "Backstage TechDocs"
    Purpose = "TechDocs static HTML storage - Backstage IDP"
    Service = "Backstage"
    ADR     = "ADR-055"
  })
}

resource "aws_s3_bucket_versioning" "backstage_techdocs" {
  bucket = aws_s3_bucket.backstage_techdocs.id
  versioning_configuration {
    status = "Disabled"  # TechDocs regenera completo, versioning desnecessário
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backstage_techdocs" {
  bucket = aws_s3_bucket.backstage_techdocs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "backstage_techdocs" {
  bucket                  = aws_s3_bucket.backstage_techdocs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backstage_techdocs" {
  bucket = aws_s3_bucket.backstage_techdocs.id

  rule {
    id     = "noncurrent-cleanup"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
