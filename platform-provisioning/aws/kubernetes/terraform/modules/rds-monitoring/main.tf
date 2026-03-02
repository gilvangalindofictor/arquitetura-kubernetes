# =============================================================================
# RDS Monitoring Module: CloudWatch Alarms for PostgreSQL Availability
# =============================================================================
# Purpose: Prevent silent outages by alerting when RDS instance stops/fails
# Critical Dependencies: GitLab, Keycloak, SonarQube, ArgoCD
#
# Context: GitLab webservice was stuck in Init:2/3 state because RDS was stopped
#          and there was no alerting. This module implements multi-layer monitoring.
#
# Architecture:
#   - CloudWatch Alarms: Direct RDS instance status monitoring
#   - SNS Topic: Notification distribution (email, Slack)
#   - Prometheus Alerts: Application-level connectivity detection (complementary)
#
# Related:
#   - ADR-089: RDS Availability Monitoring
#   - Runbook: docs/runbooks/rds-monitoring-alerts-response.md
#   - Prometheus: domains/observability/infra/alerts/rds-connectivity-alerts.yaml
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  alarm_prefix = "${var.environment}-rds"

  # Calculate connection threshold (80% of max_connections)
  # db.t3.medium default max_connections = 147 (PostgreSQL 16)
  connection_threshold = var.max_connections_override != null ? var.max_connections_override * 0.80 : 117

  # Storage threshold in bytes (20% of allocated storage)
  storage_threshold_bytes = var.storage_threshold_gb * 1024 * 1024 * 1024

  common_alarm_tags = merge(var.tags, {
    Module      = "rds-monitoring"
    ManagedBy   = "Terraform"
    Alert       = "true"
    RDSInstance = var.rds_instance_identifier
  })
}

# =============================================================================
# SNS Topic: RDS Alerts
# =============================================================================

resource "aws_sns_topic" "rds_alerts" {
  name         = "${var.environment}-rds-alerts"
  display_name = "RDS PostgreSQL Alerts - ${upper(var.environment)}"

  # Enable encryption at rest (LGPD compliance)
  kms_master_key_id = var.kms_key_id != "" ? var.kms_key_id : null

  tags = merge(local.common_alarm_tags, {
    Name        = "${var.environment}-rds-alerts"
    Purpose     = "RDS availability and performance alerts"
    Subscribers = join(",", var.alert_emails)
  })
}

# -----------------------------------------------------------------------------
# SNS Topic Policy: Allow CloudWatch Alarms
# -----------------------------------------------------------------------------

resource "aws_sns_topic_policy" "rds_alerts" {
  arn = aws_sns_topic.rds_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.rds_alerts.arn
      },
      {
        Sid    = "AllowRDSEventsPublish"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.rds_alerts.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SNS Email Subscriptions
# -----------------------------------------------------------------------------

resource "aws_sns_topic_subscription" "email" {
  count = length(var.alert_emails)

  topic_arn = aws_sns_topic.rds_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]

  # Prevent Terraform from waiting for email confirmation
  endpoint_auto_confirms = false
}

# =============================================================================
# CloudWatch Alarm: RDS Instance Stopped
# =============================================================================
# CRITICAL: Detects when RDS instance is stopped (manual or FinOps automation)
# Impact: GitLab, Keycloak, SonarQube, ArgoCD will fail database connections
#
# Detection: DatabaseConnections metric will be 0 when instance is stopped
# Note: treat_missing_data = "breaching" ensures alarm fires even if no data
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_stopped" {
  alarm_name          = "${local.alarm_prefix}-instance-stopped"
  alarm_description   = "CRITICAL: RDS instance is stopped. GitLab/Keycloak/SonarQube will fail. See runbook: ${var.runbook_base_url}/rds-monitoring-alerts-response.md"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  treat_missing_data  = "breaching" # Treat no data as alarm (instance stopped)
  datapoints_to_alarm = 1

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }

  alarm_actions = [aws_sns_topic.rds_alerts.arn]
  ok_actions    = [aws_sns_topic.rds_alerts.arn]

  tags = merge(local.common_alarm_tags, {
    Severity  = "critical"
    Impact    = "platform"
    AlertName = "RDSInstanceStopped"
  })
}

# =============================================================================
# CloudWatch Alarm: High CPU Utilization
# =============================================================================
# WARNING: Detects sustained high CPU usage (>80% for 5 minutes)
# Impact: Query performance degradation, potential connection timeouts
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  count = var.enable_performance_alerts ? 1 : 0

  alarm_name          = "${local.alarm_prefix}-high-cpu"
  alarm_description   = "WARNING: RDS CPU >${var.cpu_threshold}% for 5 minutes. Check slow queries and consider vertical scaling."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_threshold
  datapoints_to_alarm = 2

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }

  alarm_actions = [aws_sns_topic.rds_alerts.arn]
  ok_actions    = [aws_sns_topic.rds_alerts.arn]

  tags = merge(local.common_alarm_tags, {
    Severity  = "warning"
    Impact    = "performance"
    AlertName = "RDSHighCPU"
  })
}

# =============================================================================
# CloudWatch Alarm: High Database Connections
# =============================================================================
# WARNING: Detects connection pool exhaustion (>80% of max_connections)
# Impact: New connection requests will be rejected
# Note: db.t3.medium max_connections = 147 (PostgreSQL 16)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_high_connections" {
  count = var.enable_performance_alerts ? 1 : 0

  alarm_name          = "${local.alarm_prefix}-high-connections"
  alarm_description   = "WARNING: RDS connections >${local.connection_threshold} (80% max_connections). Check for connection leaks."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = local.connection_threshold
  datapoints_to_alarm = 1

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }

  alarm_actions = [aws_sns_topic.rds_alerts.arn]
  ok_actions    = [aws_sns_topic.rds_alerts.arn]

  tags = merge(local.common_alarm_tags, {
    Severity  = "warning"
    Impact    = "availability"
    AlertName = "RDSHighConnections"
  })
}

# =============================================================================
# CloudWatch Alarm: Low Free Storage
# =============================================================================
# WARNING: Detects low disk space (<20% free)
# Impact: Database writes will fail when storage is full
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  count = var.enable_performance_alerts ? 1 : 0

  alarm_name          = "${local.alarm_prefix}-low-storage"
  alarm_description   = "WARNING: RDS free storage <${var.storage_threshold_gb}GB (20%). Review disk usage and enable storage autoscaling."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = local.storage_threshold_bytes
  datapoints_to_alarm = 1

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }

  alarm_actions = [aws_sns_topic.rds_alerts.arn]
  ok_actions    = [aws_sns_topic.rds_alerts.arn]

  tags = merge(local.common_alarm_tags, {
    Severity  = "warning"
    Impact    = "availability"
    AlertName = "RDSLowStorage"
  })
}

# =============================================================================
# CloudWatch Alarm: Read/Write Latency High
# =============================================================================
# WARNING: Detects sustained high I/O latency (>50ms for 5 minutes)
# Impact: Slow application response times, poor user experience
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_high_read_latency" {
  count = var.enable_performance_alerts ? 1 : 0

  alarm_name          = "${local.alarm_prefix}-high-read-latency"
  alarm_description   = "WARNING: RDS read latency >${var.latency_threshold_ms}ms for 5 minutes. Check disk IOPS and consider provisioned IOPS storage."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.latency_threshold_ms / 1000 # Convert ms to seconds
  datapoints_to_alarm = 2

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }

  alarm_actions = [aws_sns_topic.rds_alerts.arn]
  ok_actions    = [aws_sns_topic.rds_alerts.arn]

  tags = merge(local.common_alarm_tags, {
    Severity  = "warning"
    Impact    = "performance"
    AlertName = "RDSHighReadLatency"
  })
}

resource "aws_cloudwatch_metric_alarm" "rds_high_write_latency" {
  count = var.enable_performance_alerts ? 1 : 0

  alarm_name          = "${local.alarm_prefix}-high-write-latency"
  alarm_description   = "WARNING: RDS write latency >${var.latency_threshold_ms}ms for 5 minutes. Check disk IOPS and transaction log volume."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteLatency"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.latency_threshold_ms / 1000 # Convert ms to seconds
  datapoints_to_alarm = 2

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }

  alarm_actions = [aws_sns_topic.rds_alerts.arn]
  ok_actions    = [aws_sns_topic.rds_alerts.arn]

  tags = merge(local.common_alarm_tags, {
    Severity  = "warning"
    Impact    = "performance"
    AlertName = "RDSHighWriteLatency"
  })
}

# =============================================================================
# RDS Event Subscription: Instance State Changes
# =============================================================================
# Purpose: Receive SNS notifications for RDS instance lifecycle events
# Events: start, stop, failover, failure, backup, maintenance
# -----------------------------------------------------------------------------

resource "aws_db_event_subscription" "rds_instance_events" {
  name      = "${var.environment}-rds-instance-events"
  sns_topic = aws_sns_topic.rds_alerts.arn

  source_type = "db-instance"
  source_ids  = [var.rds_instance_identifier]

  event_categories = [
    "availability", # Instance start/stop/failover
    "failure",      # Instance failure events
    "maintenance",  # Scheduled maintenance
    "backup",       # Backup events
    "configuration change",
    "deletion"
  ]

  enabled = true

  tags = merge(local.common_alarm_tags, {
    Name        = "${var.environment}-rds-instance-events"
    Description = "RDS instance lifecycle event notifications"
  })
}
