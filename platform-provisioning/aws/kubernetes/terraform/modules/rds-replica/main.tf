# =============================================================================
# RDS Cross-Region Read Replica Module — GAP-012
# =============================================================================
# Creates a PostgreSQL read replica in us-west-2 from a primary RDS instance
# in us-east-1. Provides:
#   - Automated replication lag monitoring (CloudWatch alarm > 60s)
#   - Storage utilisation alarm (> 80%)
#   - SNS alerting (PagerDuty integration via existing topic)
#   - Dedicated DB subnet group and security group in us-west-2
#
# ADR Reference: GAP-012 — DR Multi-Region (SLA 99.9% iPaaS)
# RTO target: 10 min (replica promotion)  |  RPO: last committed replication
# =============================================================================

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "replica" {}

# Lookup the primary instance to inherit engine/version/storage details
data "aws_db_instance" "primary" {
  db_instance_identifier = var.source_db_identifier
}

# ---------------------------------------------------------------------------
# Local values
# ---------------------------------------------------------------------------

locals {
  common_tags = merge(var.common_tags, {
    Module    = "rds-replica"
    GAP       = "GAP-012"
    ManagedBy = "terraform"
    Role      = "rds-read-replica-dr"
  })

  replica_identifier = "${var.source_db_identifier}-replica-${var.replica_region}"
}

# =============================================================================
# NETWORKING — subnet group + security group in replica region
# =============================================================================

# DB Subnet Group — must use subnets in the replica region (us-west-2)
resource "aws_db_subnet_group" "replica" {
  name        = "${var.cluster_name}-postgresql-replica"
  description = "Subnet group for PostgreSQL DR read replica (GAP-012, ${var.replica_region})"
  subnet_ids  = var.replica_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-postgresql-replica-subnet-group"
  })
}

# Security Group — restricts access to VPC CIDR only (no public access)
resource "aws_security_group" "replica" {
  name_prefix = "${var.cluster_name}-postgresql-replica-"
  description = "Security group for PostgreSQL DR read replica — private VPC access only (GAP-012)"
  vpc_id      = var.replica_vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.replica_allowed_cidrs
    description = "PostgreSQL from DR VPC private subnets"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-postgresql-replica-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# RDS READ REPLICA — cross-region PostgreSQL replica
# =============================================================================

resource "aws_db_instance" "replica" {
  # Cross-region replica: reference the primary instance by ARN
  identifier          = local.replica_identifier
  replicate_source_db = data.aws_db_instance.primary.db_instance_arn

  # Instance sizing
  instance_class = var.replica_instance_class

  # Storage — inherits size from primary; use gp3 for cost/performance
  storage_type          = "gp3"
  storage_encrypted     = true
  max_allocated_storage = var.max_allocated_storage

  # Network
  db_subnet_group_name   = aws_db_subnet_group.replica.name
  vpc_security_group_ids = [aws_security_group.replica.id]
  publicly_accessible    = false
  multi_az               = false # Single-AZ replica; promote to Multi-AZ after failover if needed

  # Maintenance — manual control over minor version upgrades in DR
  auto_minor_version_upgrade = false
  maintenance_window         = "sun:05:00-sun:06:00"

  # Backups on replica — enabled to allow point-in-time restore post-promotion
  backup_retention_period = var.backup_retention_period
  backup_window           = "04:00-05:00"

  # Monitoring — Enhanced Monitoring for replication lag visibility
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_replica_monitoring.arn

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # CloudWatch logs
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Deletion protection — false on replica (it can be destroyed and re-created)
  deletion_protection       = false
  skip_final_snapshot       = true # Replica: no final snapshot on destroy
  apply_immediately         = false

  tags = merge(local.common_tags, {
    Name                  = local.replica_identifier
    PromotionReadiness    = "ready"
    ReplicationSource     = var.source_db_identifier
  })

  lifecycle {
    # Allow instance class changes in-place without forced replacement
    ignore_changes = [replicate_source_db]
  }
}

# =============================================================================
# IAM — Enhanced Monitoring role for replica
# =============================================================================

resource "aws_iam_role" "rds_replica_monitoring" {
  name_prefix = "${var.cluster_name}-rds-replica-mon-"
  description = "IAM role for RDS Enhanced Monitoring on DR replica (GAP-012)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-rds-replica-monitoring-role"
  })
}

resource "aws_iam_role_policy_attachment" "rds_replica_monitoring" {
  role       = aws_iam_role.rds_replica_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# =============================================================================
# SNS TOPIC — DR alerts for this module
# =============================================================================

resource "aws_sns_topic" "rds_replica_alerts" {
  count = var.create_sns_topic ? 1 : 0
  name  = "${var.cluster_name}-rds-replica-alerts-${var.replica_region}"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-rds-replica-alerts"
  })
}

locals {
  sns_topic_arn = var.create_sns_topic ? aws_sns_topic.rds_replica_alerts[0].arn : var.existing_sns_topic_arn
}

# Optional: email subscription (convenient for first-time setup)
resource "aws_sns_topic_subscription" "rds_replica_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = local.sns_topic_arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# =============================================================================
# CLOUDWATCH ALARMS
# =============================================================================

# Alarm 1: Replication lag > 60 seconds
# Trigger: lag exceeds SLA threshold — indicates risk of data loss at failover
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.replica_identifier}-replication-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.replication_lag_threshold_seconds
  alarm_description   = "GAP-012: RDS replication lag on ${local.replica_identifier} exceeds ${var.replication_lag_threshold_seconds}s. RPO SLA at risk."
  treat_missing_data  = "breaching" # Missing data = assume replication stalled

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.replica.identifier
  }

  alarm_actions = [local.sns_topic_arn]
  ok_actions    = [local.sns_topic_arn]

  tags = local.common_tags
}

# Alarm 2: Free storage space < 20% (storage full = replication stops)
resource "aws_cloudwatch_metric_alarm" "storage_space_low" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.replica_identifier}-storage-space-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Minimum"
  # Threshold: 20% of allocated storage in bytes
  # data.aws_db_instance.primary.allocated_storage returns GB; convert to bytes
  threshold           = var.storage_free_threshold_bytes
  alarm_description   = "GAP-012: RDS DR replica ${local.replica_identifier} free storage below threshold. Replication may stop if storage fills."
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.replica.identifier
  }

  alarm_actions = [local.sns_topic_arn]
  ok_actions    = [local.sns_topic_arn]

  tags = local.common_tags
}

# Alarm 3: Replica is unavailable (connection count drops to 0 and CPU is 0)
resource "aws_cloudwatch_metric_alarm" "replica_unavailable" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.replica_identifier}-unavailable"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "SampleCount"
  threshold           = 1
  alarm_description   = "GAP-012: DR replica ${local.replica_identifier} appears unavailable (no connection metrics). Investigate immediately."
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.replica.identifier
  }

  alarm_actions = [local.sns_topic_arn]

  tags = local.common_tags
}
