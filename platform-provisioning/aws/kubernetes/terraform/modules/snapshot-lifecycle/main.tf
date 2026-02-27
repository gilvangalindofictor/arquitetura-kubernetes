# Snapshot Lifecycle Management Module
# Automates EBS snapshot retention using AWS Data Lifecycle Manager (DLM)
# Savings: R$ 252/ano (30% reduction post-stabilization, 3 months)
# Impact: 22 snapshots (213 GB) → automated retention (Velero 30d, Manual 14d, Migration 7d)

#------------------------------------------------------------------------------
# DLM Lifecycle Policy — Velero Backups (30 days retention)
#------------------------------------------------------------------------------

resource "aws_dlm_lifecycle_policy" "velero_backups" {
  description        = "DLM policy for Velero backup snapshots - 30 days retention"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "VeleroSnapshotRetention"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"] # 03:00 UTC = 00:00 BRT (midnight)
      }

      retain_rule {
        count = var.velero_retention_days
      }

      tags_to_add = {
        ManagedBy       = "DLM"
        RetentionPolicy = "velero-backups"
      }

      copy_tags = true
    }

    target_tags = {
      "velero.io/backup" = "*" # Matches any Velero backup snapshot
    }
  }

  tags = merge(var.common_tags, {
    Name          = "velero-snapshot-lifecycle"
    Purpose       = "Automated retention for Velero EBS backups"
    Criticality   = "High"
    RetentionDays = var.velero_retention_days
  })
}

#------------------------------------------------------------------------------
# DLM Lifecycle Policy — Manual Snapshots (14 days retention)
#------------------------------------------------------------------------------

resource "aws_dlm_lifecycle_policy" "manual_snapshots" {
  description        = "DLM policy for manual snapshots - 14 days retention"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "ManualSnapshotRetention"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:30"] # 03:30 UTC = 00:30 BRT
      }

      retain_rule {
        count = var.manual_retention_days
      }

      tags_to_add = {
        ManagedBy       = "DLM"
        RetentionPolicy = "manual-snapshots"
      }

      copy_tags = true
    }

    target_tags = {
      Type = "manual-snapshot"
    }
  }

  tags = merge(var.common_tags, {
    Name          = "manual-snapshot-lifecycle"
    Purpose       = "Automated retention for manually created snapshots"
    Criticality   = "Medium"
    RetentionDays = var.manual_retention_days
  })
}

#------------------------------------------------------------------------------
# DLM Lifecycle Policy — Migration Snapshots (7 days retention)
#------------------------------------------------------------------------------

resource "aws_dlm_lifecycle_policy" "migration_snapshots" {
  description        = "DLM policy for migration snapshots - 7 days retention"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "MigrationSnapshotRetention"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["04:00"] # 04:00 UTC = 01:00 BRT
      }

      retain_rule {
        count = var.migration_retention_days
      }

      tags_to_add = {
        ManagedBy       = "DLM"
        RetentionPolicy = "migration-snapshots"
      }

      copy_tags = true
    }

    target_tags = {
      Purpose = "migration"
    }
  }

  tags = merge(var.common_tags, {
    Name          = "migration-snapshot-lifecycle"
    Purpose       = "Automated retention for migration-related snapshots"
    Criticality   = "Low"
    RetentionDays = var.migration_retention_days
  })
}
