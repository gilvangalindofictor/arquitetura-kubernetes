# =============================================================================
# Velero DR Multi-Region Module - GAP-012
# =============================================================================
# Implements Disaster Recovery with:
#   - S3 Cross-Region Replication (us-east-1 → us-west-2)
#   - Replication Time Control (RTC, 15min SLA)
#   - Velero Backup Storage Locations (primary + replica)
#   - IAM role for Velero IRSA with cross-region S3 access
#
# ADR Reference: GAP-012 — DR Multi-Region (SLA 99.9% iPaaS)
# RTO target: 4h  |  RPO target: 24h (daily) / 1h (hourly ipaas-*)
# =============================================================================

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "primary" {}

# ---------------------------------------------------------------------------
# Local values
# ---------------------------------------------------------------------------

locals {
  account_id = data.aws_caller_identity.current.account_id

  primary_bucket_name = "velero-backups-${var.environment}-${local.account_id}-${var.primary_region}"
  replica_bucket_name = "velero-backups-${var.environment}-${local.account_id}-${var.replica_region}"

  common_tags = merge(var.common_tags, {
    Module    = "velero-dr"
    GAP       = "GAP-012"
    ManagedBy = "terraform"
  })
}

# =============================================================================
# PRIMARY BUCKET (us-east-1) — source of replication
# =============================================================================

resource "aws_s3_bucket" "velero_primary" {
  bucket = local.primary_bucket_name

  tags = merge(local.common_tags, {
    Name   = local.primary_bucket_name
    Region = var.primary_region
    Role   = "velero-backup-primary"
  })
}

# Versioning — MANDATORY for S3 CRR source bucket
resource "aws_s3_bucket_versioning" "velero_primary" {
  bucket = aws_s3_bucket.velero_primary.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption — SSE-S3 (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "velero_primary" {
  bucket = aws_s3_bucket.velero_primary.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "velero_primary" {
  bucket = aws_s3_bucket.velero_primary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle — primary: 30-day retention + noncurrent version cleanup
resource "aws_s3_bucket_lifecycle_configuration" "velero_primary" {
  # Must wait for versioning to be fully enabled before creating lifecycle rules
  depends_on = [aws_s3_bucket_versioning.velero_primary]

  bucket = aws_s3_bucket.velero_primary.id

  rule {
    id     = "velero-primary-retention"
    status = "Enabled"

    filter {}

    expiration {
      days = var.retention_days_primary
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    # Clean up incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "velero-delete-markers-cleanup"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }
}

# =============================================================================
# REPLICA BUCKET (us-west-2) — destination of replication
# Uses the provider alias passed in from the root module / environment
# =============================================================================

resource "aws_s3_bucket" "velero_replica" {
  provider = aws.replica
  bucket   = local.replica_bucket_name

  tags = merge(local.common_tags, {
    Name   = local.replica_bucket_name
    Region = var.replica_region
    Role   = "velero-backup-replica"
  })
}

# Versioning — MANDATORY for S3 CRR destination bucket
resource "aws_s3_bucket_versioning" "velero_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.velero_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption — SSE-S3 (AES256) on replica
resource "aws_s3_bucket_server_side_encryption_configuration" "velero_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.velero_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access on replica
resource "aws_s3_bucket_public_access_block" "velero_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.velero_replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle — replica: 90-day retention (longer for DR compliance)
resource "aws_s3_bucket_lifecycle_configuration" "velero_replica" {
  provider = aws.replica

  depends_on = [aws_s3_bucket_versioning.velero_replica]

  bucket = aws_s3_bucket.velero_replica.id

  rule {
    id     = "velero-replica-retention"
    status = "Enabled"

    filter {}

    expiration {
      days = var.retention_days_replica
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "velero-replica-delete-markers-cleanup"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }
}

# =============================================================================
# S3 CROSS-REGION REPLICATION (CRR)
# =============================================================================

# IAM Role — grants S3 service permission to replicate objects
resource "aws_iam_role" "velero_s3_crr" {
  name        = "velero-s3-crr-role-${var.environment}"
  description = "IAM role for Velero S3 Cross-Region Replication (GAP-012)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3CRRAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "velero-s3-crr-role-${var.environment}"
  })
}

# IAM Policy — S3 replication permissions (source + destination)
resource "aws_iam_role_policy" "velero_s3_crr" {
  name = "velero-s3-crr-policy-${var.environment}"
  role = aws_iam_role.velero_s3_crr.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSourceBucketRead"
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [aws_s3_bucket.velero_primary.arn]
      },
      {
        Sid    = "AllowSourceObjectRead"
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = ["${aws_s3_bucket.velero_primary.arn}/*"]
      },
      {
        Sid    = "AllowDestinationBucketWrite"
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = ["${aws_s3_bucket.velero_replica.arn}/*"]
      }
    ]
  })
}

# Replication Configuration — attaches CRR rule to primary bucket
resource "aws_s3_bucket_replication_configuration" "velero_crr" {
  # Must wait for versioning on both buckets before enabling replication
  depends_on = [
    aws_s3_bucket_versioning.velero_primary,
    aws_s3_bucket_versioning.velero_replica,
  ]

  bucket = aws_s3_bucket.velero_primary.id
  role   = aws_iam_role.velero_s3_crr.arn

  rule {
    id       = "velero-backup-replication"
    status   = "Enabled"
    priority = 1

    # Empty filter = replicate ALL objects
    filter {}

    destination {
      bucket        = aws_s3_bucket.velero_replica.arn
      storage_class = "STANDARD"

      # Replication Time Control (RTC) — 15-minute SLA for replication
      dynamic "replication_time" {
        for_each = var.enable_replication_time_control ? [1] : []
        content {
          status = "Enabled"
          time {
            minutes = 15
          }
        }
      }

      # Metrics — track replication progress (required alongside RTC)
      dynamic "metrics" {
        for_each = var.enable_replication_time_control ? [1] : []
        content {
          status = "Enabled"
          event_threshold {
            minutes = 15
          }
        }
      }
    }

    # Replicate delete markers to keep replica in sync
    delete_marker_replication {
      status = "Enabled"
    }
  }
}

# =============================================================================
# IAM ROLE FOR VELERO (IRSA) — primary region permissions
# Extended to include replica bucket for cross-region restore operations
# =============================================================================

resource "aws_iam_policy" "velero_dr" {
  name        = "${var.cluster_name}-velero-dr-policy"
  description = "IAM policy for Velero DR — access to primary + replica S3 buckets (GAP-012)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Primary bucket — full R/W for backup/restore
      {
        Sid    = "VeleroPrimaryBucketObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = ["${aws_s3_bucket.velero_primary.arn}/*"]
      },
      {
        Sid      = "VeleroPrimaryBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.velero_primary.arn]
      },
      # Replica bucket — read-only for DR restore from us-west-2
      {
        Sid    = "VeleroReplicaBucketObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListMultipartUploadParts"
        ]
        Resource = ["${aws_s3_bucket.velero_replica.arn}/*"]
      },
      {
        Sid      = "VeleroReplicaBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.velero_replica.arn]
      },
      # EC2 volume snapshots (cross-region)
      {
        Sid    = "VeleroEBSSnapshots"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:CopySnapshot"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-velero-dr-policy"
  })
}

# Velero IRSA role — federated identity via OIDC (no static credentials)
resource "aws_iam_role" "velero_dr" {
  name        = "${var.cluster_name}-velero-dr-role"
  description = "IRSA role for Velero DR service account (GAP-012)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowVeleroIRSA"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.velero_namespace}:velero-server"
            "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-velero-dr-role"
  })
}

resource "aws_iam_role_policy_attachment" "velero_dr" {
  role       = aws_iam_role.velero_dr.name
  policy_arn = aws_iam_policy.velero_dr.arn
}

# =============================================================================
# CLOUDWATCH MONITORING — replication lag and failures
# =============================================================================

# SNS Topic for DR alerts (created if not provided externally)
resource "aws_sns_topic" "velero_dr_alerts" {
  count = var.create_sns_topic ? 1 : 0
  name  = "velero-dr-alerts-${var.environment}"

  tags = merge(local.common_tags, {
    Name = "velero-dr-alerts-${var.environment}"
  })
}

locals {
  sns_topic_arn = var.create_sns_topic ? aws_sns_topic.velero_dr_alerts[0].arn : var.existing_sns_topic_arn
}

# Alarm — replication failures in last hour
resource "aws_cloudwatch_metric_alarm" "velero_replication_failed" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "velero-s3-crr-replication-failed-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "OperationFailedReplication"
  namespace           = "AWS/S3"
  period              = 3600
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "GAP-012: Velero S3 CRR replication failures detected in ${var.environment}. DR integrity at risk."
  treat_missing_data  = "notBreaching"

  dimensions = {
    SourceBucket      = aws_s3_bucket.velero_primary.id
    DestinationBucket = aws_s3_bucket.velero_replica.id
    RuleId            = "velero-backup-replication"
  }

  alarm_actions = [local.sns_topic_arn]
  ok_actions    = [local.sns_topic_arn]

  tags = local.common_tags
}

# Alarm — bytes pending replication (data at risk if primary fails)
resource "aws_cloudwatch_metric_alarm" "velero_replication_pending" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "velero-s3-crr-pending-bytes-high-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BytesPendingReplication"
  namespace           = "AWS/S3"
  period              = 900 # 15 min — aligned with RTC SLA
  statistic           = "Maximum"
  threshold           = 1073741824 # 1 GB pending = alert
  alarm_description   = "GAP-012: >1GB pending replication in Velero S3 CRR. RTC SLA may be breached."
  treat_missing_data  = "notBreaching"

  dimensions = {
    SourceBucket      = aws_s3_bucket.velero_primary.id
    DestinationBucket = aws_s3_bucket.velero_replica.id
    RuleId            = "velero-backup-replication"
  }

  alarm_actions = [local.sns_topic_arn]

  tags = local.common_tags
}
