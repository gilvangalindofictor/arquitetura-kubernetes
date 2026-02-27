# =============================================================================
# RDS Monitoring: CloudWatch Alarms for PostgreSQL Availability
# =============================================================================
# Purpose: Prevent silent database outages (GitLab stuck in Init state)
# Context: RDS was stopped without alerting, causing platform-wide failures
#
# This module provides:
#   - CloudWatch alarm when RDS instance is stopped (CRITICAL)
#   - Performance alerts (CPU, connections, storage, latency)
#   - SNS topic for email/Slack notifications
#   - RDS event subscription (lifecycle events)
#
# Complementary Monitoring:
#   - Prometheus: domains/observability/infra/alerts/rds-connectivity-alerts.yaml
#   - Grafana: domains/observability/infra/grafana/rds-monitoring-dashboard-configmap.yaml
# =============================================================================

module "rds_monitoring_staging" {
  source = "../../modules/rds-monitoring"

  environment             = local.environment
  rds_instance_identifier = "k8s-platform-prod-postgresql"

  # Alert notification configuration
  alert_emails = [
    var.finops_alert_email,  # Reuse FinOps email for RDS alerts
    # Add additional emails here:
    # "sre-team@example.com",
    # "database-team@example.com"
  ]

  # Enable all monitoring (availability + performance)
  enable_performance_alerts = true

  # Threshold configuration (adjusted for db.t3.medium)
  cpu_threshold            = 80    # Alert at 80% CPU (sustained 5min)
  max_connections_override = 147   # db.t3.medium PostgreSQL 16 max_connections
  storage_threshold_gb     = 20    # Alert when free storage <20GB
  latency_threshold_ms     = 50    # Alert at 50ms read/write latency

  # KMS encryption for SNS topic (reuse FinOps KMS key if available)
  kms_key_id = ""  # Optional: add KMS key ID for SNS encryption

  # Runbook base URL (update with your GitHub org/repo)
  runbook_base_url = "https://github.com/fctconsig/k8s-platform/docs/runbooks"

  tags = merge(local.common_tags, {
    Module      = "rds-monitoring"
    CostCenter  = "platform-infrastructure"
    Compliance  = "SRE-monitoring"
    Alert       = "true"
    Criticality = "high"
  })
}

# =============================================================================
# Outputs
# =============================================================================

output "rds_monitoring_sns_topic_arn" {
  description = "SNS Topic ARN for RDS alerts (use for Slack/PagerDuty integration)"
  value       = module.rds_monitoring_staging.sns_topic_arn
}

output "rds_monitoring_alarm_arns" {
  description = "CloudWatch alarm ARNs (for CLI queries)"
  value       = module.rds_monitoring_staging.alarm_arns
}

output "rds_monitoring_summary" {
  description = "RDS monitoring configuration summary"
  value       = module.rds_monitoring_staging.monitoring_summary
}
