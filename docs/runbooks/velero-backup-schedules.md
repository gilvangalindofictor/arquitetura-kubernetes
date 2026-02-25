# Velero Backup Schedules

This directory contains Velero backup schedule configurations for automated cluster backups.

## Overview

Two backup schedules are configured:

1. **Daily Backups**: Every day at 2 AM UTC, 7-day retention
2. **Weekly Backups**: Every Sunday at 3 AM UTC, 30-day retention

Both schedules:
- Include all namespaces except `kube-system`, `kube-public`, `kube-node-lease`
- Include cluster-scoped resources (CRDs, PVs, etc.)
- Enable volume snapshots via CSI
- Use Restic for file-level backup (`defaultVolumesToFsBackup: true`)
- Store backups in S3 bucket `k8s-platform-staging-velero-backups`

## Prerequisites

Ensure Velero is installed and configured:

```bash
# Check Velero installation
kubectl get deployment -n velero velero

# Verify backup storage location
kubectl get backupstoragelocation -n velero
```

## Apply Backup Schedules

```bash
# Apply the schedules
kubectl apply -f kubectl-manifests/velero/backup-schedules.yaml

# Verify schedules are created
kubectl get schedules -n velero
```

Expected output:
```
NAME                     STATUS    CREATED AT
daily-cluster-backup     Enabled   <timestamp>
weekly-cluster-backup    Enabled   <timestamp>
```

## Monitor Backup Status

### Check Schedule Status

```bash
# List all schedules
kubectl get schedules -n velero

# Describe a specific schedule
kubectl describe schedule daily-cluster-backup -n velero
```

### View Backup History

```bash
# List all backups
kubectl get backups -n velero

# Show recent backups sorted by creation time
kubectl get backups -n velero --sort-by=.metadata.creationTimestamp

# Filter by schedule
kubectl get backups -n velero -l velero.io/schedule-name=daily-cluster-backup
```

### Check Backup Details

```bash
# Describe a specific backup
kubectl describe backup <backup-name> -n velero

# View backup logs
velero backup logs <backup-name>

# Check backup phase (should be "Completed")
kubectl get backup <backup-name> -n velero -o jsonpath='{.status.phase}'
```

### Monitor with Velero CLI

```bash
# Get backup details
velero backup get

# Describe backup
velero backup describe <backup-name>

# View backup logs
velero backup logs <backup-name>

# Check for backup failures
velero backup get --status Failed
```

## Verify S3 Storage

```bash
# List backups in S3
aws s3 ls s3://k8s-platform-staging-velero-backups/backups/ --recursive

# Check bucket size
aws s3 ls s3://k8s-platform-staging-velero-backups/backups/ --recursive \
  --summarize --human-readable
```

## Modify Retention Policies

To change retention periods, edit `backup-schedules.yaml`:

```yaml
spec:
  template:
    ttl: 168h0m0s  # Change this value
```

Retention examples:
- 7 days: `168h0m0s`
- 14 days: `336h0m0s`
- 30 days: `720h0m0s`
- 90 days: `2160h0m0s`

After editing, reapply:
```bash
kubectl apply -f kubectl-manifests/velero/backup-schedules.yaml
```

**Note**: Changing retention only affects NEW backups. Existing backups retain their original TTL.

## Modify Backup Schedule

To change backup times, edit the `schedule` field (cron format):

```yaml
spec:
  schedule: "0 2 * * *"  # minute hour day month weekday
```

Examples:
- Daily at 2 AM: `"0 2 * * *"`
- Every 6 hours: `"0 */6 * * *"`
- Every Monday at 3 AM: `"0 3 * * 1"`
- Twice daily (2 AM, 2 PM): `"0 2,14 * * *"`

## Pause/Resume Schedules

### Pause a schedule

```bash
# Pause daily backups
kubectl patch schedule daily-cluster-backup -n velero \
  --type merge -p '{"spec":{"paused":true}}'
```

### Resume a schedule

```bash
# Resume daily backups
kubectl patch schedule daily-cluster-backup -n velero \
  --type merge -p '{"spec":{"paused":false}}'
```

## Trigger Manual Backup

```bash
# Create backup from schedule template
velero backup create manual-backup-$(date +%Y%m%d-%H%M%S) \
  --from-schedule daily-cluster-backup

# Or create ad-hoc backup
velero backup create adhoc-backup --include-namespaces staging-*
```

## Troubleshooting

### Backup is stuck in "InProgress"

```bash
# Check backup status
kubectl describe backup <backup-name> -n velero

# Check Velero pod logs
kubectl logs -n velero deployment/velero

# Common causes:
# - Large PVCs taking time to snapshot
# - Network issues with S3
# - Restic backup timeout (check restic pods)
```

### Backup failed with "PartiallyFailed"

```bash
# View backup errors
velero backup describe <backup-name> --details

# Check for:
# - Resources that couldn't be backed up
# - Volume snapshot failures
# - Namespace/resource exclusions
```

### No backups are created

```bash
# Verify schedule is enabled
kubectl get schedule daily-cluster-backup -n velero -o yaml

# Check Velero controller logs
kubectl logs -n velero deployment/velero --tail=100

# Verify IAM permissions for S3 and EBS snapshots
```

## Disaster Recovery

For restore procedures, see:
- `docs/runbooks/velero-disaster-recovery.md` (planned V-012)
- RTO target: 1 hour
- RPO: 24 hours (daily backup schedule)

## Monitoring and Alerts

Velero exposes Prometheus metrics via ServiceMonitor in the `velero` namespace:

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n velero

# Key metrics:
# - velero_backup_success_total
# - velero_backup_failure_total
# - velero_backup_duration_seconds
# - velero_backup_items_total
# - velero_volume_snapshot_success_total
```

Grafana dashboard (planned V-011):
- Backup success/failure rates
- Backup duration trends
- S3 storage usage
- Volume snapshot status

## Cost Optimization

Current configuration uses:
- S3 Intelligent-Tiering for automatic cost optimization
- 7-day daily retention (balance between cost and recoverability)
- 30-day weekly retention (long-term recovery points)

Estimated costs (staging cluster):
- Daily backups: ~7 copies × ~50GB = 350GB
- Weekly backups: ~4 copies × ~50GB = 200GB
- Total S3 storage: ~550GB/month
- With Intelligent-Tiering: automatically moves to cheaper tiers after access patterns

## References

- [Velero Documentation](https://velero.io/docs/v1.15/)
- [Velero Schedule API](https://velero.io/docs/v1.15/api-types/schedule/)
- [AWS EBS CSI Snapshots](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/README.md)
- Logbook: `docs/logbook/2026-02-25-v008-velero-irsa.md`
