# RDS Monitoring Module

Comprehensive CloudWatch monitoring for RDS PostgreSQL instances with SNS alerting.

## Purpose

Prevent silent database outages by monitoring RDS instance availability, performance, and resource utilization.

**Context:** GitLab webservice was stuck in Init:2/3 state because the RDS instance was stopped and there was no alerting. This module ensures operations teams are immediately notified when RDS stops or experiences issues.

## Features

### Critical Availability Monitoring
- **RDS Instance Stopped Alert** (CRITICAL): Detects when instance is stopped (manual or FinOps automation)
- **RDS Event Subscription**: Lifecycle events (start, stop, failover, failure, backup, maintenance)

### Performance Monitoring (Optional)
- **High CPU Utilization** (WARNING): >80% CPU for 5 minutes
- **High Database Connections** (WARNING): >80% of max_connections
- **Low Free Storage** (WARNING): <20% free disk space
- **High Read/Write Latency** (WARNING): >50ms for 5 minutes

### Notification System
- **SNS Topic**: Encrypted topic for alert distribution
- **Email Subscriptions**: Configurable list of email addresses
- **Integration Ready**: SNS ARN output for Slack/PagerDuty/etc.

## Architecture

```
RDS Instance (k8s-platform-prod-postgresql)
    ↓ CloudWatch Metrics
CloudWatch Alarms (6 alerts)
    ↓ SNS Publish
SNS Topic (staging-rds-alerts)
    ↓ Subscriptions
Email / Slack / PagerDuty
```

**Multi-Layer Detection:**
1. **CloudWatch (this module)**: Direct RDS instance monitoring (AWS native)
2. **Prometheus**: Application-level connectivity alerts (K8s native)
3. **Grafana**: Unified dashboard combining both sources

## Usage

### Basic Configuration (Availability Only)

```hcl
module "rds_monitoring" {
  source = "../../modules/rds-monitoring"

  environment             = "staging"
  rds_instance_identifier = "k8s-platform-prod-postgresql"
  alert_emails            = ["devops@example.com", "sre@example.com"]

  # Disable performance alerts (availability only)
  enable_performance_alerts = false

  tags = {
    Environment = "staging"
    Team        = "platform-sre"
  }
}
```

### Full Monitoring (Availability + Performance)

```hcl
module "rds_monitoring" {
  source = "../../modules/rds-monitoring"

  environment             = "staging"
  rds_instance_identifier = "k8s-platform-prod-postgresql"
  alert_emails            = ["devops@example.com", "sre@example.com"]

  # Enable all monitoring
  enable_performance_alerts = true

  # Customize thresholds
  cpu_threshold            = 80    # Alert at 80% CPU
  max_connections_override = 147   # db.t3.medium max_connections
  storage_threshold_gb     = 20    # Alert when <20GB free
  latency_threshold_ms     = 50    # Alert at 50ms latency

  # KMS encryption for SNS (optional)
  kms_key_id = aws_kms_key.monitoring.id

  # Runbook URL (used in alarm descriptions)
  runbook_base_url = "https://github.com/my-org/my-repo/docs/runbooks"

  tags = local.common_tags
}

# Output SNS ARN for integration with Slack/PagerDuty
output "rds_alerts_sns_topic" {
  value = module.rds_monitoring.sns_topic_arn
}
```

## CloudWatch Alarms

| Alarm Name | Severity | Threshold | Evaluation | Description |
|------------|----------|-----------|------------|-------------|
| `staging-rds-instance-stopped` | **CRITICAL** | DatabaseConnections = 0 | 1 min | RDS instance stopped (manual or FinOps) |
| `staging-rds-high-cpu` | WARNING | CPUUtilization > 80% | 2 × 5 min | Sustained high CPU usage |
| `staging-rds-high-connections` | WARNING | Connections > 117 (80%) | 5 min | Connection pool exhaustion risk |
| `staging-rds-low-storage` | WARNING | FreeStorage < 20GB | 5 min | Disk space running low |
| `staging-rds-high-read-latency` | WARNING | ReadLatency > 50ms | 2 × 5 min | Slow read operations |
| `staging-rds-high-write-latency` | WARNING | WriteLatency > 50ms | 2 × 5 min | Slow write operations |

### Alarm States

- **OK**: Metric within threshold (green email notification)
- **ALARM**: Metric exceeded threshold (red email notification)
- **INSUFFICIENT_DATA**: Not enough data to evaluate (gray, no notification)

### Email Notifications

**Subject Format:**
- **ALARM**: `ALARM: "staging-rds-instance-stopped" in US East (N. Virginia)`
- **OK**: `OK: "staging-rds-instance-stopped" in US East (N. Virginia)`

**Email Body Includes:**
- Alarm description with runbook link
- Current metric value
- Threshold configuration
- AWS Console link to alarm

## RDS Event Subscription

Receives SNS notifications for instance lifecycle events:

- **Availability**: start, stop, failover, reboot
- **Failure**: instance failure, storage failure
- **Maintenance**: scheduled maintenance start/complete
- **Backup**: automated backup start/complete
- **Configuration Change**: parameter group changes
- **Deletion**: instance deletion

## Integration with Prometheus

This module provides **CloudWatch-based** monitoring. For **application-level** connectivity detection, use the complementary Prometheus alerts:

**File:** `domains/observability/infra/alerts/rds-connectivity-alerts.yaml`

```yaml
# Alert when GitLab webservice stuck in Init state (DB connection failure)
- alert: GitLabRDSConnectivityFailure
  expr: kube_pod_container_status_waiting_reason{pod=~"gitlab-webservice-.*", reason="PodInitializing"} > 0
  for: 5m
```

**Benefits of Dual Monitoring:**
- CloudWatch: Detects RDS-level issues (stopped, failover, hardware failure)
- Prometheus: Detects application-level issues (network, credentials, DNS)

## Testing

### Test SNS Notifications

```bash
# Manually trigger alarm to test email delivery
aws cloudwatch set-alarm-state \
  --alarm-name staging-rds-instance-stopped \
  --state-value ALARM \
  --state-reason "Manual test of RDS monitoring alerts" \
  --region us-east-1

# Check alarm history
aws cloudwatch describe-alarm-history \
  --alarm-name staging-rds-instance-stopped \
  --max-records 5 \
  --region us-east-1
```

### Verify Email Subscription

```bash
# List SNS subscriptions (check for PendingConfirmation)
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw rds_monitoring_sns_topic_arn) \
  --region us-east-1
```

**Action Required:** Recipients must click confirmation link in SNS subscription email.

### Query Current RDS Status

```bash
# Check RDS instance status
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text \
  --region us-east-1

# Check current metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=k8s-platform-prod-postgresql \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-east-1
```

## Cost Impact

**CloudWatch Alarms:**
- First 10 alarms: Free (AWS Free Tier)
- Additional alarms: $0.10/alarm/month
- **This module:** 1-6 alarms = **$0.00 - $0.00/month** (within free tier)

**SNS Topics:**
- First 1,000 email notifications: Free
- Additional emails: $2.00 per 100,000 emails
- **Expected cost:** $0.00/month (typical alert volume <1,000/month)

**RDS Event Subscriptions:**
- Free (no additional cost)

**Total Monthly Cost:** **$0.00** (within AWS Free Tier limits)

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `environment` | string | Yes | - | Environment name (staging/production) |
| `rds_instance_identifier` | string | Yes | - | RDS instance identifier to monitor |
| `alert_emails` | list(string) | Yes | - | Email addresses for alert notifications |
| `enable_performance_alerts` | bool | No | `true` | Enable CPU/connections/storage/latency alerts |
| `cpu_threshold` | number | No | `80` | CPU utilization threshold percentage |
| `max_connections_override` | number | No | `null` | Override max_connections (auto-detect if null) |
| `storage_threshold_gb` | number | No | `20` | Free storage threshold in GB |
| `latency_threshold_ms` | number | No | `50` | Read/write latency threshold in milliseconds |
| `kms_key_id` | string | No | `""` | KMS key ID for SNS encryption (optional) |
| `runbook_base_url` | string | No | `"https://..."` | Base URL for runbook documentation |
| `tags` | map(string) | No | `{}` | Tags to apply to all resources |

## Outputs

| Name | Description |
|------|-------------|
| `sns_topic_arn` | SNS Topic ARN (use for Slack/PagerDuty integration) |
| `sns_topic_name` | SNS Topic name |
| `alarm_arns` | Map of CloudWatch alarm ARNs by type |
| `alarm_names` | List of alarm names (for CLI queries) |
| `event_subscription_arn` | RDS event subscription ARN |
| `monitoring_summary` | Summary of configured monitoring |

## Related Documentation

- **ADR-089**: RDS Availability Monitoring
- **Runbook**: `docs/runbooks/rds-monitoring-alerts-response.md`
- **Prometheus Alerts**: `domains/observability/infra/alerts/rds-connectivity-alerts.yaml`
- **Grafana Dashboard**: `domains/observability/infra/grafana/rds-monitoring-dashboard-configmap.yaml`

## Troubleshooting

### Email Notifications Not Received

**Symptom:** Alarm fires but no email received

**Causes:**
1. Email subscription pending confirmation
2. Emails going to spam folder
3. SNS topic policy misconfiguration

**Solutions:**
```bash
# Check subscription status
aws sns list-subscriptions-by-topic \
  --topic-arn <sns-topic-arn> \
  --region us-east-1

# Resend confirmation email
aws sns subscribe \
  --topic-arn <sns-topic-arn> \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --region us-east-1
```

### Alarm Not Triggering

**Symptom:** RDS stopped but alarm doesn't fire

**Causes:**
1. Alarm in INSUFFICIENT_DATA state (not enough evaluation periods)
2. Wrong RDS instance identifier in alarm dimensions
3. CloudWatch metrics delayed (up to 5 minutes)

**Solutions:**
```bash
# Check alarm state
aws cloudwatch describe-alarms \
  --alarm-names staging-rds-instance-stopped \
  --region us-east-1

# Verify metric data availability
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=k8s-platform-prod-postgresql \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average \
  --region us-east-1
```

### False Positives

**Symptom:** Alarm fires but RDS is running fine

**Causes:**
1. Threshold too sensitive for workload
2. Normal maintenance window activity
3. Monitoring system clock skew

**Solutions:**
- Adjust thresholds via module variables
- Add alarm suppression during maintenance windows
- Review alarm history for patterns

## Security Considerations

- **SNS Topic Encryption**: Optional KMS encryption for SNS topic (LGPD compliance)
- **Email Addresses**: Stored in Terraform state (use encrypted backend)
- **IAM Permissions**: CloudWatch service principal can publish to SNS
- **Topic Policy**: Restricts publishers to CloudWatch and RDS services only

## Maintenance

### Update Alert Email List

```hcl
# Modify module configuration
module "rds_monitoring" {
  # ...
  alert_emails = [
    "devops@example.com",
    "sre@example.com",
    "new-email@example.com"  # Add new email
  ]
}

# Apply changes
terraform apply
```

**Note:** New subscribers must confirm subscription via email.

### Adjust Thresholds

```hcl
# Reduce false positives by increasing thresholds
module "rds_monitoring" {
  # ...
  cpu_threshold         = 90   # Was 80
  storage_threshold_gb  = 10   # Was 20
  latency_threshold_ms  = 100  # Was 50
}

terraform apply
```

### Disable Performance Alerts (Keep Availability Only)

```hcl
module "rds_monitoring" {
  # ...
  enable_performance_alerts = false  # Keep only RDS stopped alert
}

terraform apply
```

## License

Managed by Platform SRE Team. See repository LICENSE file.
