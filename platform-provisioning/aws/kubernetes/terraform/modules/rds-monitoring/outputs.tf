# =============================================================================
# RDS Monitoring Module: Outputs
# =============================================================================

output "sns_topic_arn" {
  description = "SNS Topic ARN for RDS alerts (use for integration with other monitoring)"
  value       = aws_sns_topic.rds_alerts.arn
}

output "sns_topic_name" {
  description = "SNS Topic name"
  value       = aws_sns_topic.rds_alerts.name
}

output "alarm_arns" {
  description = "Map of CloudWatch alarm ARNs by alarm type"
  value = merge(
    {
      rds_stopped = aws_cloudwatch_metric_alarm.rds_stopped.arn
    },
    var.enable_performance_alerts ? {
      rds_high_cpu           = try(aws_cloudwatch_metric_alarm.rds_high_cpu[0].arn, null)
      rds_high_connections   = try(aws_cloudwatch_metric_alarm.rds_high_connections[0].arn, null)
      rds_low_storage        = try(aws_cloudwatch_metric_alarm.rds_low_storage[0].arn, null)
      rds_high_read_latency  = try(aws_cloudwatch_metric_alarm.rds_high_read_latency[0].arn, null)
      rds_high_write_latency = try(aws_cloudwatch_metric_alarm.rds_high_write_latency[0].arn, null)
    } : {}
  )
}

output "alarm_names" {
  description = "List of CloudWatch alarm names (for CLI queries)"
  value = concat(
    [aws_cloudwatch_metric_alarm.rds_stopped.alarm_name],
    var.enable_performance_alerts ? [
      aws_cloudwatch_metric_alarm.rds_high_cpu[0].alarm_name,
      aws_cloudwatch_metric_alarm.rds_high_connections[0].alarm_name,
      aws_cloudwatch_metric_alarm.rds_low_storage[0].alarm_name,
      aws_cloudwatch_metric_alarm.rds_high_read_latency[0].alarm_name,
      aws_cloudwatch_metric_alarm.rds_high_write_latency[0].alarm_name
    ] : []
  )
}

output "event_subscription_arn" {
  description = "RDS event subscription ARN (receives instance lifecycle events)"
  value       = aws_db_event_subscription.rds_instance_events.arn
}

output "monitoring_summary" {
  description = "Summary of configured monitoring (for documentation)"
  value = {
    environment        = var.environment
    rds_instance       = var.rds_instance_identifier
    alert_emails       = var.alert_emails
    performance_alerts = var.enable_performance_alerts
    alarms_count       = var.enable_performance_alerts ? 6 : 1
    sns_topic          = aws_sns_topic.rds_alerts.name
    event_subscription = aws_db_event_subscription.rds_instance_events.name
  }
}
