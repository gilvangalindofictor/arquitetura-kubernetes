# =============================================================================
# RDS Cross-Region Read Replica Module — Outputs
# GAP-012: Disaster Recovery Multi-Region
# =============================================================================

# ---------------------------------------------------------------------------
# Replica instance
# ---------------------------------------------------------------------------

output "replica_instance_id" {
  description = "RDS instance identifier of the read replica. Use in 'aws rds promote-read-replica --db-instance-identifier' during failover."
  value       = aws_db_instance.replica.identifier
}

output "replica_endpoint" {
  description = "Connection endpoint of the read replica (host:port). Available for read-only queries or after promotion."
  value       = aws_db_instance.replica.endpoint
}

output "replica_address" {
  description = "Hostname of the read replica (without port). Use when constructing connection strings."
  value       = aws_db_instance.replica.address
}

output "replica_port" {
  description = "Port of the read replica (always 5432 for PostgreSQL)"
  value       = aws_db_instance.replica.port
}

output "replica_arn" {
  description = "ARN of the read replica RDS instance. Required as the source ARN when promoting across regions."
  value       = aws_db_instance.replica.arn
}

output "replica_availability_zone" {
  description = "Availability zone where the read replica is deployed"
  value       = aws_db_instance.replica.availability_zone
}

output "replica_engine_version" {
  description = "PostgreSQL engine version running on the replica"
  value       = aws_db_instance.replica.engine_version_actual
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

output "replica_security_group_id" {
  description = "Security group ID attached to the read replica. Add inbound rules here if adding DR workloads."
  value       = aws_security_group.replica.id
}

output "replica_subnet_group_name" {
  description = "DB subnet group name used by the read replica"
  value       = aws_db_subnet_group.replica.name
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for replica CloudWatch alarms. Empty string when create_sns_topic = false."
  value       = var.create_sns_topic ? aws_sns_topic.rds_replica_alerts[0].arn : var.existing_sns_topic_arn
}

output "cloudwatch_alarm_arns" {
  description = "Map of CloudWatch alarm ARNs created by this module. Empty map when enable_cloudwatch_alarms = false."
  value = var.enable_cloudwatch_alarms ? {
    replication_lag    = aws_cloudwatch_metric_alarm.replication_lag[0].arn
    storage_space_low  = aws_cloudwatch_metric_alarm.storage_space_low[0].arn
    replica_unavailable = aws_cloudwatch_metric_alarm.replica_unavailable[0].arn
  } : {}
}

output "cloudwatch_alarm_replication_lag_arn" {
  description = "ARN of the replication lag CloudWatch alarm (fires when lag > threshold seconds)"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.replication_lag[0].arn : ""
}

output "cloudwatch_alarm_storage_low_arn" {
  description = "ARN of the storage space CloudWatch alarm (fires when free space < threshold bytes)"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.storage_space_low[0].arn : ""
}
