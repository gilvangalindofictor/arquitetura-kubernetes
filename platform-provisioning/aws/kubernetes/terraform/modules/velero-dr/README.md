# Velero DR Multi-Region — Terraform Module

**GAP-012: Disaster Recovery Multi-Region**
Terraform module that upgrades the single-region Velero backup (GAP-003) to a
full multi-region DR architecture, enabling SLA 99.9% for the iPaaS platform.

---

## Architecture Overview

```text
us-east-1 (PRIMARY)                    us-west-2 (DR SITE)
┌─────────────────────────────┐        ┌─────────────────────────────┐
│  EKS k8s-platform-prod      │        │  EKS k8s-platform-dr        │
│  ┌────────────┐             │        │  (provisioned on failover)  │
│  │  Velero    │──backup──►  │        │                             │
│  │  server    │             │        │                             │
│  └──────┬─────┘             │        │                             │
│         │ IRSA              │        │                             │
│  ┌──────▼─────────────────┐ │  CRR   │ ┌─────────────────────────┐ │
│  │ S3: velero-backups-    │─┼──────►─┼─│ S3: velero-backups-     │ │
│  │     staging-{acct}-    │ │ RTC    │ │     staging-{acct}-     │ │
│  │     us-east-1          │ │ 15min  │ │     us-west-2           │ │
│  └────────────────────────┘ │  SLA   │ └─────────────────────────┘ │
│                             │        │                             │
│  RDS PostgreSQL (primary)   │        │  RDS Read Replica           │
│  ipaas-postgres-primary     │──────►─│  ipaas-postgres-replica-   │
│  Multi-AZ: true             │        │  us-west-2                  │
└─────────────────────────────┘        └─────────────────────────────┘
```

### What this module provisions

| Resource | Details |
| --- | --- |
| `aws_s3_bucket.velero_primary` | Primary backup bucket (us-east-1, versioning + SSE-S3) |
| `aws_s3_bucket.velero_replica` | Replica bucket (us-west-2, versioning + SSE-S3) |
| `aws_s3_bucket_replication_configuration` | CRR rule with optional RTC (15-min SLA) |
| `aws_iam_role.velero_s3_crr` | IAM role for S3 replication service |
| `aws_iam_role.velero_dr` | IRSA role for Velero pod (primary + replica read) |
| `aws_cloudwatch_metric_alarm` (x2) | Replication failure + pending bytes alarms |
| `aws_sns_topic.velero_dr_alerts` | SNS topic for DR alerts (optional) |

---

## RTO / RPO Targets

| Metric | Target | Mechanism |
| --- | --- | --- |
| **RPO** (Recovery Point Objective) | 1 hour | Hourly incremental backup to S3 primary |
| **RPO** (critical namespaces) | 15 min | S3 CRR with RTC replicates to us-west-2 within 15 min |
| **RTO** (Recovery Time Objective) | 4 hours | Velero restore from replica + DNS cutover |
| **SLA** | 99.9% | ~8.7h downtime budget/year; DR mitigates region-level outage |

---

## Usage

### Calling module from staging environment

```hcl
# environments/staging/main.tf

# Provider alias for DR region
provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"
}

module "velero_dr_staging" {
  source = "../../modules/velero-dr"

  # Required provider aliases
  providers = {
    aws         = aws
    aws.replica = aws.us-west-2
  }

  cluster_name      = local.cluster_name
  environment       = local.environment
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn
  oidc_provider_url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer

  # Region configuration
  primary_region = "us-east-1"
  replica_region = "us-west-2"

  # Retention
  retention_days_primary = 30
  retention_days_replica = 90

  # RTC: 15-min replication SLA (~$0.015/GB additional cost)
  enable_replication_time_control = true

  # Monitoring
  enable_cloudwatch_alarms = true
  create_sns_topic         = false
  existing_sns_topic_arn   = aws_sns_topic.finops_alerts_staging.arn

  common_tags = local.common_tags
}
```

### Helm values for Velero (after terraform apply)

```yaml
# helm-values/velero/staging-dr.yaml
configuration:
  backupStorageLocation:
    - name: aws-us-east-1
      provider: velero.io/aws
      bucket: <primary_bucket_name>  # from terraform output velero_primary_bucket_name
      config:
        region: us-east-1
      default: true

    - name: aws-us-west-2
      provider: velero.io/aws
      bucket: <replica_bucket_name>  # from terraform output velero_replica_bucket_name
      config:
        region: us-west-2
      accessMode: ReadOnly            # Read-only in normal operation, writable during DR

serviceAccount:
  server:
    annotations:
      eks.amazonaws.com/role-arn: <velero_role_arn>  # from terraform output velero_role_arn

schedules:
  daily-full-backup:
    schedule: "0 2 * * *"
    template:
      ttl: "720h"
      includedNamespaces:
        - "*"
      excludedNamespaces:
        - kube-system
        - kube-public
      storageLocation: aws-us-east-1

  hourly-incremental:
    schedule: "0 * * * *"
    template:
      ttl: "168h"
      includedNamespaces:
        - ipaas-staging
        - gitlab
        - argocd
      storageLocation: aws-us-east-1
```

---

## Inputs

| Name | Type | Default | Required | Description |
| --- | --- | --- | --- | --- |
| `cluster_name` | string | — | yes | EKS cluster name (used in IAM resource names) |
| `environment` | string | — | yes | Environment label (staging, production) |
| `oidc_provider_arn` | string | — | yes | EKS OIDC provider ARN for IRSA |
| `oidc_provider_url` | string | — | yes | EKS OIDC issuer URL for IRSA |
| `primary_region` | string | `"us-east-1"` | no | Primary backup region |
| `replica_region` | string | `"us-west-2"` | no | DR replica region |
| `retention_days_primary` | number | `30` | no | Backup retention in primary bucket (days) |
| `retention_days_replica` | number | `90` | no | Backup retention in replica bucket (days) |
| `enable_replication_time_control` | bool | `true` | no | Enable S3 RTC (15-min replication SLA) |
| `velero_namespace` | string | `"velero"` | no | Kubernetes namespace for Velero |
| `enable_cloudwatch_alarms` | bool | `true` | no | Create CloudWatch alarms for replication |
| `create_sns_topic` | bool | `true` | no | Create dedicated SNS topic for DR alerts |
| `existing_sns_topic_arn` | string | `""` | no | Existing SNS ARN (when create_sns_topic = false) |
| `common_tags` | map(string) | `{}` | no | Tags applied to all resources |

---

## Outputs

| Name | Description |
| --- | --- |
| `primary_bucket_arn` | ARN of primary S3 bucket |
| `primary_bucket_name` | Name of primary S3 bucket |
| `replica_bucket_arn` | ARN of replica S3 bucket (DR site) |
| `replica_bucket_name` | Name of replica S3 bucket |
| `replication_role_arn` | ARN of S3 CRR IAM role |
| `velero_role_arn` | ARN of Velero IRSA role (for Helm annotation) |
| `velero_policy_arn` | ARN of Velero IAM policy |
| `sns_topic_arn` | ARN of SNS topic for DR alerts |
| `cloudwatch_alarm_replication_failed_arn` | ARN of replication failure alarm |
| `cloudwatch_alarm_replication_pending_arn` | ARN of pending bytes alarm |

---

## Cost Estimation

### Monthly cost breakdown (staging, ~50 GB backup data)

| Component | Unit | Qty | Unit Price | Monthly |
| --- | --- | --- | --- | --- |
| S3 Standard — primary (30-day retention) | GB-month | ~70 | $0.023 | $1.61 |
| S3 Standard — replica (90-day retention) | GB-month | ~150 | $0.023 | $3.45 |
| S3 PUT requests (backup writes) | per 1K | ~500 | $0.005 | $2.50 |
| S3 CRR data transfer | GB | ~50 | $0.02 | $1.00 |
| S3 RTC surcharge | GB | ~50 | $0.015 | $0.75 |
| CloudWatch alarms (2x) | alarm/month | 2 | $0.10 | $0.20 |
| SNS notifications | per 1K | ~1 | $0.50 | $0.50 |
| **Velero DR S3 subtotal** | | | | **~$10/month** |

### RDS cross-region replica (module: rds-replica)

| Component | Unit | Qty | Unit Price | Monthly |
| --- | --- | --- | --- | --- |
| RDS db.t4g.medium — us-west-2 | hour | 730 | $0.065 | $47.45 |
| RDS storage gp3 — 20 GB replica | GB-month | 20 | $0.115 | $2.30 |
| RDS data transfer (replication) | GB | ~10 | $0.02 | $0.20 |
| CloudWatch alarms (2x) | alarm/month | 2 | $0.10 | $0.20 |
| **RDS replica subtotal** | | | | **~$50/month** |

### Total GAP-012 additional cost

| Scope | Monthly | Annual |
| --- | --- | --- |
| Velero DR (S3 CRR + RTC) | ~$10 | ~$120 |
| RDS cross-region replica | ~$50 | ~$600 |
| Data transfer overhead | ~$5 | ~$60 |
| **Total GAP-012** | **~$65/month** | **~$780/year** |

> Note: Costs are estimates for the staging environment. Production costs will be higher
> proportional to data volume and instance size. RTC can be disabled to save ~$0.75/month
> if 15-min SLA is not required (set `enable_replication_time_control = false`).

---

## DR Runbook

### Scenario 1: us-east-1 Total Region Outage

**Severity:** P0 — Platform down
**On-call trigger:** PagerDuty alert from Route53 health check
**Estimated RTO:** 4 hours from detection

#### Phase 1: Confirm outage (T+0 to T+15min)

```bash
# Verify us-east-1 is truly down (not a transient blip)
aws ec2 describe-availability-zones --region us-east-1 2>&1
# Expected on outage: connection timeout or service unavailable

# Check AWS Service Health Dashboard
curl -s https://health.aws.amazon.com/health/status | jq '.services[] | select(.region == "us-east-1")'

# Confirm replica bucket is accessible and up-to-date
aws s3 ls s3://velero-backups-staging-${AWS_ACCOUNT_ID}-us-west-2 \
  --region us-west-2 | tail -5
```

#### Phase 2: Promote RDS Read Replica (T+15min to T+30min)

**RPO:** Last committed replication (check lag in CloudWatch before promoting)

```bash
# 1. Check replication lag before promoting
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=ipaas-postgres-replica-us-west-2 \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --region us-west-2

# 2. Promote replica to standalone (IRREVERSIBLE — confirm with team lead)
aws rds promote-read-replica \
  --db-instance-identifier ipaas-postgres-replica-us-west-2 \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --region us-west-2

# 3. Wait for promotion to complete (~5-10 minutes)
aws rds wait db-instance-available \
  --db-instance-identifier ipaas-postgres-replica-us-west-2 \
  --region us-west-2

# 4. Capture new endpoint
NEW_RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier ipaas-postgres-replica-us-west-2 \
  --region us-west-2 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
echo "New RDS endpoint: ${NEW_RDS_ENDPOINT}"
```

#### Phase 3: Restore Velero Backup in DR cluster (T+30min to T+2h)

```bash
# Prerequisites: kubectl configured for dr cluster in us-west-2

# 1. List available backups in replica storage location
velero backup get --storage-location aws-us-west-2

# 2. Identify most recent successful daily backup
LATEST_BACKUP=$(velero backup get \
  --storage-location aws-us-west-2 \
  -o json | jq -r '.items | sort_by(.metadata.creationTimestamp) | reverse | .[0].metadata.name')
echo "Restoring from: ${LATEST_BACKUP}"

# 3. Restore all namespaces (exclude system namespaces)
velero restore create dr-restore-$(date +%Y%m%d%H%M) \
  --from-backup "${LATEST_BACKUP}" \
  --storage-location aws-us-west-2 \
  --exclude-namespaces kube-system,kube-public,kube-node-lease \
  --wait

# 4. Monitor restore progress
velero restore describe dr-restore-$(date +%Y%m%d) --details

# 5. Validate pods
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed
```

#### Phase 4: Update DNS (T+2h to T+2h30min)

```bash
# Option A: If Route53 failover policy is pre-configured (recommended)
# DNS automatically fails over when primary health check fails — no action needed.

# Option B: Manual DNS update (if failover policy not configured)
HOSTED_ZONE_ID="Z1234567890ABC"  # Replace with actual hosted zone ID
DR_ALB_DNS="k8s-staging-dr-alb-xxxxx.us-west-2.elb.amazonaws.com"

aws route53 change-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.staging.internal",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "'"${DR_ALB_DNS}"'"}]
      }
    }]
  }'

# Verify DNS propagation
dig +short staging.internal @8.8.8.8
```

#### Phase 5: Post-failover validation (T+2h30min)

```bash
# Health check all critical services
for svc in argocd keycloak gitlab harbor sonarqube; do
  echo "Checking ${svc}..."
  kubectl get pods -n ${svc} -o wide
done

# Validate PostgreSQL connectivity from pods
kubectl run pg-test --rm -it --image=postgres:17 \
  --env="PGPASSWORD=${DB_PASSWORD}" -- \
  psql -h ${NEW_RDS_ENDPOINT} -U postgres_admin -d platform -c "\l"
```

---

### Scenario 2: Partial Failure (Velero only, not full region outage)

**Trigger:** Velero backup failing but EKS/RDS healthy

```bash
# 1. Check Velero backup status
velero backup get
velero schedule get

# 2. Check storage location connectivity
velero backup-location get

# 3. If primary S3 unreachable, switch Velero to use replica as write target
velero backup-location set aws-us-east-1 --access-mode ReadOnly
velero backup-location set aws-us-west-2 --access-mode ReadWrite

# 4. Trigger immediate backup to replica
velero backup create emergency-backup-$(date +%Y%m%d) \
  --storage-location aws-us-west-2 \
  --wait
```

---

### Scenario 3: Monthly DR Drill (Test Restore)

**Schedule:** First Sunday of each month, 09:00 BRT
**Duration:** ~1 hour
**Responsible:** Platform Team on-call

```bash
# 1. Create isolated test namespace
kubectl create ns dr-drill-$(date +%Y%m)

# 2. Restore specific backup to test namespace (namespace mapping)
BACKUP_TO_TEST=$(velero backup get -o json \
  | jq -r '[.items[] | select(.status.phase=="Completed")] | sort_by(.metadata.creationTimestamp) | reverse | .[0].metadata.name')

velero restore create dr-drill-$(date +%Y%m%d) \
  --from-backup "${BACKUP_TO_TEST}" \
  --storage-location aws-us-west-2 \
  --namespace-mappings ipaas-staging:dr-drill-$(date +%Y%m) \
  --wait

# 3. Validate restored workloads
echo "=== Pods ==="
kubectl get pods -n dr-drill-$(date +%Y%m)

echo "=== Expected: All pods Running ==="
kubectl get pods -n dr-drill-$(date +%Y%m) | grep -v Running | grep -v Completed | grep -v NAME

# 4. Validate persistent volume data
kubectl exec -n dr-drill-$(date +%Y%m) \
  $(kubectl get pod -n dr-drill-$(date +%Y%m) -l app=ipaas -o name | head -1) \
  -- ls /data

# 5. Record results in DR drill log
cat >> /tmp/dr-drill-$(date +%Y%m%d).log <<EOF
DR Drill Results — $(date)
Backup tested: ${BACKUP_TO_TEST}
Storage location: aws-us-west-2 (replica)
Restore status: $(velero restore get dr-drill-$(date +%Y%m%d) -o json | jq -r '.status.phase')
Pods Running: $(kubectl get pods -n dr-drill-$(date +%Y%m) | grep Running | wc -l)
Pods Failed: $(kubectl get pods -n dr-drill-$(date +%Y%m) | grep -v Running | grep -v Completed | grep -v NAME | wc -l)
EOF

# 6. Cleanup test namespace
kubectl delete ns dr-drill-$(date +%Y%m)
echo "DR drill complete — results in /tmp/dr-drill-$(date +%Y%m%d).log"
```

---

## Post-Deployment Steps

After `terraform apply`:

### 1. Update Velero Helm values

```bash
# Get outputs
PRIMARY_BUCKET=$(terraform output -raw primary_bucket_name)
REPLICA_BUCKET=$(terraform output -raw replica_bucket_name)
VELERO_ROLE=$(terraform output -raw velero_role_arn)

# Install/upgrade Velero with DR configuration
helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set credentials.useSecret=false \
  --set "serviceAccount.server.annotations.eks\.amazonaws\.com/role-arn=${VELERO_ROLE}" \
  --set "configuration.backupStorageLocation[0].name=aws-us-east-1" \
  --set "configuration.backupStorageLocation[0].provider=velero.io/aws" \
  --set "configuration.backupStorageLocation[0].bucket=${PRIMARY_BUCKET}" \
  --set "configuration.backupStorageLocation[0].config.region=us-east-1" \
  --set "configuration.backupStorageLocation[0].default=true" \
  --set "configuration.backupStorageLocation[1].name=aws-us-west-2" \
  --set "configuration.backupStorageLocation[1].provider=velero.io/aws" \
  --set "configuration.backupStorageLocation[1].bucket=${REPLICA_BUCKET}" \
  --set "configuration.backupStorageLocation[1].config.region=us-west-2" \
  --set "configuration.backupStorageLocation[1].accessMode=ReadOnly"
```

### 2. Verify storage locations

```bash
velero backup-location get
# Expected output:
# NAME            PROVIDER          BUCKET/PREFIX                              ACCESS MODE   LAST VALIDATED
# aws-us-east-1   velero.io/aws     velero-backups-staging-ACCT-us-east-1    ReadWrite     ...
# aws-us-west-2   velero.io/aws     velero-backups-staging-ACCT-us-west-2    ReadOnly      ...
```

### 3. Create backup schedules

```bash
kubectl apply -f - <<'EOF'
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-full-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"
  template:
    ttl: 720h
    includedNamespaces:
    - '*'
    excludedNamespaces:
    - kube-system
    - kube-public
    storageLocation: aws-us-east-1
---
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: hourly-incremental
  namespace: velero
spec:
  schedule: "0 * * * *"
  template:
    ttl: 168h
    includedNamespaces:
    - ipaas-staging
    - gitlab
    - argocd
    storageLocation: aws-us-east-1
EOF
```

### 4. Verify replication is working (after first backup)

```bash
# Check replication metrics in CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name BytesPendingReplication \
  --dimensions \
    Name=SourceBucket,Value=velero-backups-staging-${ACCOUNT_ID}-us-east-1 \
    Name=DestinationBucket,Value=velero-backups-staging-${ACCOUNT_ID}-us-west-2 \
    Name=RuleId,Value=velero-backup-replication \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Maximum \
  --region us-east-1
# Expected: Values approaching 0 (all replicated within 15min with RTC)
```

---

## Related Documentation

- [GAP-012: DR Multi-Region Implementation Plan](../../../../docs/gaps/gap-012-dr-multi-region.md)
- [Module: rds-replica](../rds-replica/README.md) — PostgreSQL cross-region read replica
- [ADR-078: Velero Backup/DR Implementation](../../../../docs/adr/adr-078-velero-backup-dr-implementation.md)

---

## Requirements

- Terraform >= 1.5
- AWS Provider ~> 5.0 (with `aws.replica` provider alias configured in caller)
- EKS cluster with OIDC provider
- Velero CLI >= 1.15
- Both us-east-1 and us-west-2 enabled in the AWS account

## License

Managed by Platform Team — Internal Use Only
