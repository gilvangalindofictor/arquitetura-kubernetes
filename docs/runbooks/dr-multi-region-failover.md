# DR Multi-Region Failover Runbook

**Severity:** P0 — Platform Down
**Scope:** us-east-1 region outage → us-west-2 failover
**RTO Target:** 4 hours (Phase 1: Velero restore) | 10 minutes (Phase 2: RDS promotion + Velero)
**RPO Target:** 1 hour (hourly backups) | 15 minutes (S3 RTC replication)
**Owner:** Platform Team On-Call

---

## Quick Reference

**Primary Region:** us-east-1 (production cluster)
**DR Region:** us-west-2 (failover target)

**S3 Buckets:**
- Primary: `velero-backups-staging-891377105802-us-east-1`
- Replica: `velero-backups-staging-891377105802-us-west-2`

**RDS Instances:**
- Primary: `k8s-platform-prod-postgresql` (us-east-1)
- Replica: `k8s-platform-prod-postgresql-replica-us-west-2` (us-west-2, IF ENABLED)

**IAM Role (Velero IRSA):**
- `arn:aws:iam::891377105802:role/k8s-platform-prod-velero-dr-role`

**CloudWatch Alarms:**
- `velero-s3-crr-replication-failed-staging` (us-east-1)
- `velero-s3-crr-pending-bytes-high-staging` (us-east-1)
- `k8s-platform-prod-postgresql-replica-us-west-2-replication-lag-high` (us-west-2, IF ENABLED)

**PagerDuty Escalation Policy:** platform-team-on-call

---

## Scenario 1: Total us-east-1 Region Outage

**Trigger:** PagerDuty alert from Route53 health check failure + AWS Health Dashboard red status

**Decision Criteria:**
- us-east-1 EKS cluster unreachable for > 15 minutes
- AWS Health Dashboard confirms us-east-1 service degradation
- Business impact: All staging services down (GitLab, Harbor, Keycloak, ArgoCD, SonarQube, Vault)

---

### Phase 1: Confirm Outage (T+0 to T+15min)

**Objective:** Validate us-east-1 is truly down, not transient network issue

**Commands:**

```bash
# 1. Test us-east-1 AWS API reachability
timeout 10 aws ec2 describe-availability-zones --region us-east-1 \
  --profile k8s-platform-staging 2>&1
# Expected on outage: timeout or connection error

# 2. Check AWS Service Health Dashboard
curl -s https://health.aws.amazon.com/health/status | \
  jq '.services[] | select(.region == "us-east-1" and .service == "ec2")' 2>/dev/null
# Expected on outage: status != "operational"

# 3. Test EKS cluster API
timeout 10 kubectl cluster-info --context=arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod 2>&1
# Expected on outage: timeout or connection refused

# 4. Confirm replica bucket is accessible and up-to-date
aws s3 ls s3://velero-backups-staging-891377105802-us-west-2/backups/ \
  --region us-west-2 --profile k8s-platform-staging | tail -10
# Expected: Recent backup objects (< 1 hour old if hourly schedule active)

# 5. Check S3 replication lag (pre-outage metrics)
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name BytesPendingReplication \
  --dimensions \
    Name=SourceBucket,Value=velero-backups-staging-891377105802-us-east-1 \
    Name=DestinationBucket,Value=velero-backups-staging-891377105802-us-west-2 \
    Name=RuleId,Value=velero-backup-replication \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 --statistics Maximum \
  --region us-east-1 --profile k8s-platform-staging 2>/dev/null
# Expected on healthy replication: values near 0
# If us-east-1 API down: command will fail, assume last known good state
```

**Decision Point:**
- **IF** us-east-1 API timeout AND AWS Health Dashboard confirms issue → PROCEED to Phase 2
- **ELSE** → ESCALATE to AWS Support, wait for status update

---

### Phase 2: Promote RDS Read Replica (T+15min to T+30min)

**CONDITIONAL:** Only if `dr_enable_rds_replica = true` (RDS replica exists in us-west-2)

**Objective:** Promote read replica to standalone primary (RPO = last committed transaction)

**Pre-Check:**

```bash
# Verify replica exists and is healthy
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql-replica-us-west-2 \
  --region us-west-2 --profile k8s-platform-staging \
  --query 'DBInstances[0].[DBInstanceIdentifier,DBInstanceStatus,ReadReplicaSourceDBInstanceIdentifier]' \
  --output table

# Expected:
# k8s-platform-prod-postgresql-replica-us-west-2 | available | arn:aws:rds:us-east-1:891377105802:db:k8s-platform-prod-postgresql
```

**Replication Lag Check (CRITICAL — determines RPO):**

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=k8s-platform-prod-postgresql-replica-us-west-2 \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Average,Maximum \
  --region us-west-2 --profile k8s-platform-staging

# Acceptable lag: < 300 seconds (5 minutes)
# IF lag > 300s: DATA LOSS RISK — inform stakeholders before promotion
```

**Promotion (IRREVERSIBLE ACTION — requires approval):**

```bash
# CRITICAL: This breaks replication permanently. Cannot rollback.
# Confirm with Platform Lead before executing.

echo "⚠️  WARNING: Promoting RDS replica breaks replication. Type 'PROMOTE' to confirm:"
read CONFIRM
if [ "$CONFIRM" != "PROMOTE" ]; then
  echo "Aborted."
  exit 1
fi

# Promote replica to standalone instance
aws rds promote-read-replica \
  --db-instance-identifier k8s-platform-prod-postgresql-replica-us-west-2 \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --region us-west-2 --profile k8s-platform-staging

echo "Promotion initiated. Monitoring status..."

# Wait for promotion to complete (5-10 minutes)
while true; do
  STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier k8s-platform-prod-postgresql-replica-us-west-2 \
    --region us-west-2 --profile k8s-platform-staging \
    --query 'DBInstances[0].DBInstanceStatus' --output text)

  echo "[$(date +%H:%M:%S)] RDS Status: $STATUS"

  if [ "$STATUS" = "available" ]; then
    echo "✅ RDS promotion complete"
    break
  elif [ "$STATUS" = "failed" ]; then
    echo "❌ RDS promotion FAILED — escalate to AWS Support"
    exit 1
  fi

  sleep 30
done

# Capture new standalone endpoint
NEW_RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql-replica-us-west-2 \
  --region us-west-2 --profile k8s-platform-staging \
  --query 'DBInstances[0].Endpoint.Address' --output text)

echo "New RDS endpoint: ${NEW_RDS_ENDPOINT}"
echo "Save this endpoint for Phase 3 (application config updates)"
```

**Rollback (if promotion fails):**
- RDS promotion is irreversible once started
- IF promotion fails: Restore from latest Velero backup (includes database dumps if configured)
- Estimated data loss: up to last hourly backup (1 hour RPO)

---

### Phase 3: Provision DR Cluster in us-west-2 (T+30min to T+2h)

**PREREQUISITE:** EKS cluster pre-provisioned in us-west-2 OR use existing us-east-1 cluster if partially accessible

**Assumption:** For staging, we will restore to the SAME us-east-1 cluster if region recovers, or to a temporary namespace if full DR cluster needed.

**3.1 List Available Backups**

```bash
# Configure kubectl for Velero operations
export KUBECONFIG=~/.kube/config
kubectl config use-context arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod

# If us-east-1 cluster is down, skip to 3.2 (manual S3 exploration)

# List backups in replica storage location
velero backup get --storage-location aws-us-west-2

# Identify most recent successful backup
LATEST_BACKUP=$(velero backup get --storage-location aws-us-west-2 -o json | \
  jq -r '[.items[] | select(.status.phase=="Completed")] | sort_by(.metadata.creationTimestamp) | reverse | .[0].metadata.name')

echo "Latest backup: ${LATEST_BACKUP}"
velero backup describe ${LATEST_BACKUP} --details
```

**3.2 Manual S3 Exploration (if Velero CLI unavailable)**

```bash
# List backup manifests in replica bucket
aws s3 ls s3://velero-backups-staging-891377105802-us-west-2/backups/ \
  --region us-west-2 --profile k8s-platform-staging --recursive | \
  grep -E 'backup.json|backup-version.txt' | sort -k1,2 | tail -10

# Download latest backup metadata
LATEST_BACKUP_NAME="daily-full-backup-20260226020000"  # Example
aws s3 cp s3://velero-backups-staging-891377105802-us-west-2/backups/${LATEST_BACKUP_NAME}/velero-backup.json \
  /tmp/backup-metadata.json --region us-west-2 --profile k8s-platform-staging

jq '.' /tmp/backup-metadata.json
# Review: .status.phase == "Completed", .status.errors == 0
```

---

**3.3 Restore Backup to DR Cluster**

**Option A: Restore to Same Cluster (if us-east-1 recovered)**

```bash
# Create restore request
velero restore create dr-restore-$(date +%Y%m%d%H%M) \
  --from-backup ${LATEST_BACKUP} \
  --storage-location aws-us-west-2 \
  --exclude-namespaces kube-system,kube-public,kube-node-lease \
  --wait

# Monitor restore progress
velero restore describe dr-restore-$(date +%Y%m%d%H%M) --details

# Expected output:
# Phase: Completed
# Errors: 0
# Warnings: <N> (review warnings, typically non-critical PVC issues)
```

**Option B: Restore to DR Cluster (us-west-2 EKS)**

```bash
# Switch kubectl context to DR cluster
kubectl config use-context arn:aws:eks:us-west-2:891377105802:cluster/k8s-platform-dr

# Install Velero in DR cluster (if not pre-installed)
helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero --create-namespace \
  --set credentials.useSecret=false \
  --set "serviceAccount.server.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::891377105802:role/k8s-platform-prod-velero-dr-role" \
  --set "configuration.backupStorageLocation[0].name=aws-us-west-2" \
  --set "configuration.backupStorageLocation[0].provider=velero.io/aws" \
  --set "configuration.backupStorageLocation[0].bucket=velero-backups-staging-891377105802-us-west-2" \
  --set "configuration.backupStorageLocation[0].config.region=us-west-2" \
  --set "configuration.backupStorageLocation[0].default=true" \
  --wait --timeout 5m

# Verify Velero pod running
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=velero -n velero --timeout=300s

# List backups (should auto-discover from S3)
velero backup get

# Create restore
velero restore create dr-restore-$(date +%Y%m%d%H%M) \
  --from-backup ${LATEST_BACKUP} \
  --exclude-namespaces kube-system,kube-public,kube-node-lease \
  --wait

# Monitor restore
watch kubectl get pods --all-namespaces | grep -v Running | grep -v Completed
```

---

**3.4 Update Database Connection Strings (if RDS promoted)**

**Affected Namespaces:**
- `staging-platform-gitlab`
- `harbor-system`
- `staging-platform-keycloak`
- `sonarqube`

**Method 1: Update Vault Secrets (if External Secrets Operator restored)**

```bash
# Update RDS endpoint in Vault
vault kv put secret/postgresql host="${NEW_RDS_ENDPOINT}" port=5432

# Trigger ESO refresh (restart ESO pods)
kubectl rollout restart deployment external-secrets -n external-secrets-system
kubectl rollout restart deployment external-secrets-webhook -n external-secrets-system

# Wait for ExternalSecrets to sync
kubectl get externalsecrets --all-namespaces -w
# Expected: All ExternalSecrets show SecretSynced=True within 60 seconds
```

**Method 2: Direct Kubernetes Secret Update (if Vault unreachable)**

```bash
# Update GitLab PostgreSQL secret
kubectl patch secret gitlab-postgresql-password -n staging-platform-gitlab \
  -p '{"stringData":{"host":"'${NEW_RDS_ENDPOINT}'"}}'

# Update Harbor PostgreSQL secret
kubectl patch secret harbor-postgresql-credentials -n harbor-system \
  -p '{"stringData":{"host":"'${NEW_RDS_ENDPOINT}'"}}'

# Update Keycloak PostgreSQL secret
kubectl patch secret keycloak-postgresql-credentials -n staging-platform-keycloak \
  -p '{"stringData":{"host":"'${NEW_RDS_ENDPOINT}'"}}'

# Update SonarQube PostgreSQL secret
kubectl patch secret sonarqube-postgresql -n sonarqube \
  -p '{"stringData":{"host":"'${NEW_RDS_ENDPOINT}'"}}'

# Restart affected workloads to reload secrets
kubectl rollout restart deployment -n staging-platform-gitlab
kubectl rollout restart deployment -n harbor-system
kubectl rollout restart statefulset -n staging-platform-keycloak
kubectl rollout restart deployment -n sonarqube
```

---

**3.5 Validate Restored Workloads**

```bash
# Check all pods are Running or Completed
kubectl get pods --all-namespaces | grep -v -E 'Running|Completed|Succeeded' | grep -v NAME

# If any pods are not Running:
kubectl describe pod <POD_NAME> -n <NAMESPACE>
kubectl logs <POD_NAME> -n <NAMESPACE> --tail=100

# Health check critical services
for ns in staging-platform-gitlab harbor-system staging-platform-keycloak argocd sonarqube; do
  echo "=== Namespace: $ns ==="
  kubectl get pods -n $ns -o wide
  echo ""
done

# Test database connectivity from a pod
kubectl run pg-test --rm -it --image=postgres:17 \
  --env="PGHOST=${NEW_RDS_ENDPOINT}" \
  --env="PGUSER=postgres_admin" \
  --env="PGPASSWORD=${DB_PASSWORD}" \
  -- psql -d platform -c "SELECT version();"
# Expected: PostgreSQL version output
```

---

### Phase 4: Update DNS (T+2h to T+2h30min)

**Objective:** Point staging services DNS to DR cluster ALB (us-west-2)

**4.1 Identify DR Cluster ALB**

```bash
# Get ALB DNS name in us-west-2
kubectl get ingress --all-namespaces -o wide | grep staging

# Example output:
# staging-platform-gitlab   gitlab.staging.internal   k8s-staging-dr-alb-1234567890.us-west-2.elb.amazonaws.com   80, 443   10m

DR_ALB_DNS="k8s-staging-dr-alb-1234567890.us-west-2.elb.amazonaws.com"
```

**4.2 Update Route53 DNS Records**

```bash
# Get Route53 hosted zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --profile k8s-platform-staging \
  --query 'HostedZones[?Name==`staging.internal.`].Id' --output text | cut -d'/' -f3)

echo "Hosted Zone ID: ${HOSTED_ZONE_ID}"

# Create Route53 change batch JSON
cat > /tmp/dns-failover.json <<EOF
{
  "Comment": "DR failover: us-east-1 -> us-west-2 ($(date))",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.staging.internal",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "${DR_ALB_DNS}"}]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "gitlab.staging.internal",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "${DR_ALB_DNS}"}]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "harbor.staging.internal",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "${DR_ALB_DNS}"}]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "keycloak.staging.internal",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "${DR_ALB_DNS}"}]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "argocd.staging.internal",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "${DR_ALB_DNS}"}]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "sonarqube.staging.internal",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "${DR_ALB_DNS}"}]
      }
    }
  ]
}
EOF

# Apply DNS changes
CHANGE_ID=$(aws route53 change-resource-record-sets \
  --hosted-zone-id ${HOSTED_ZONE_ID} \
  --change-batch file:///tmp/dns-failover.json \
  --profile k8s-platform-staging \
  --query 'ChangeInfo.Id' --output text)

echo "DNS change submitted: ${CHANGE_ID}"

# Wait for DNS propagation
aws route53 wait resource-record-sets-changed --id ${CHANGE_ID} --profile k8s-platform-staging
echo "✅ DNS changes propagated"

# Verify DNS resolution (may take 60s due to TTL)
sleep 60
dig +short gitlab.staging.internal @8.8.8.8
# Expected: ${DR_ALB_DNS}
```

---

### Phase 5: Post-Failover Validation (T+2h30min to T+3h)

**Objective:** Confirm all services accessible and functional

**5.1 HTTP Health Checks**

```bash
# Test each service endpoint (use curl with timeout)
for svc in gitlab harbor keycloak argocd sonarqube; do
  echo "Testing ${svc}.staging.internal..."
  curl -o /dev/null -w "%{http_code} %{time_total}s\n" \
    --max-time 10 \
    -k https://${svc}.staging.internal/
done

# Expected: HTTP 200 or 302 (redirect), response time < 5s
```

**5.2 Login Tests**

```bash
# Keycloak admin login
curl -X POST https://keycloak.staging.internal/auth/realms/master/protocol/openid-connect/token \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" | jq -r '.access_token' | head -c 20
# Expected: JWT token prefix (e.g., eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIi...)

# GitLab health check
curl -k https://gitlab.staging.internal/-/health
# Expected: {"status":"ok"}

# Harbor health
curl -k https://harbor.staging.internal/api/v2.0/health
# Expected: {"status":"healthy"}
```

**5.3 Database Connectivity Test**

```bash
# Run psql test from inside cluster
kubectl run psql-test --rm -it --image=postgres:17 \
  --env="PGHOST=${NEW_RDS_ENDPOINT}" \
  --env="PGUSER=postgres_admin" \
  --env="PGPASSWORD=${DB_PASSWORD}" \
  -- psql -d platform -c "\l"

# Expected: List of databases (gitlab, harbor, keycloak, sonarqube)
```

**5.4 Monitoring & Alerts**

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &
PF_PID=$!
sleep 2

curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up") | {job: .labels.job, health: .health}'
# Expected: Empty (all targets up)

kill $PF_PID

# Check Grafana dashboards accessible
curl -o /dev/null -w "%{http_code}\n" --max-time 10 -k https://grafana.staging.internal/
# Expected: 200 or 302
```

---

**5.5 Stakeholder Communication**

```bash
# Send completion notification
cat > /tmp/dr-completion-email.txt <<EOF
Subject: ✅ DR Failover Complete — Staging Platform Restored

Team,

DR failover to us-west-2 completed at $(date).

TIMELINE:
- T+0: us-east-1 outage detected
- T+15min: Outage confirmed, RDS replica promoted
- T+2h: Velero restore completed (${LATEST_BACKUP})
- T+2h30min: DNS updated, services accessible
- T+3h: Post-failover validation passed

CURRENT STATE:
- Platform: us-west-2 DR cluster
- Database: ${NEW_RDS_ENDPOINT} (promoted replica)
- DNS: All *.staging.internal pointing to us-west-2 ALB
- Services: GitLab, Harbor, Keycloak, ArgoCD, SonarQube — ALL UP

DATA LOSS:
- RPO achieved: < 15 minutes (last Velero backup replicated via S3 RTC)
- No user action required

NEXT STEPS:
- Monitor for 24 hours
- When us-east-1 recovers: Evaluate reverse failover vs new primary in us-west-2

Contact platform-team@company.com for questions.
EOF

# Send email (adjust command for your email system)
mail -s "DR Failover Complete" stakeholders@company.com < /tmp/dr-completion-email.txt
```

---

## Scenario 2: Partial Failure (Velero Only)

**Trigger:** Velero backup failing, but EKS/RDS healthy

**Symptoms:**
- `velero backup get` shows `PartiallyFailed` or `Failed` status
- CloudWatch alarm `velero-s3-crr-replication-failed-staging` firing
- Primary S3 bucket us-east-1 unreachable (but EKS cluster accessible)

**Root Cause Examples:**
- S3 service degradation in us-east-1
- IAM role permission issue
- Network connectivity problem

**Remediation:**

```bash
# 1. Check Velero server logs
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100

# 2. Check backup storage location status
velero backup-location get
# If aws-us-east-1 shows "Unavailable", proceed to failover

# 3. Switch Velero to write to replica bucket (us-west-2)
velero backup-location set aws-us-east-1 --access-mode ReadOnly
velero backup-location set aws-us-west-2 --access-mode ReadWrite --default

# 4. Verify new default
velero backup-location get
# Expected: aws-us-west-2 shows "ReadWrite" and "Default: true"

# 5. Trigger immediate test backup
velero backup create emergency-backup-$(date +%Y%m%d-%H%M) \
  --storage-location aws-us-west-2 \
  --include-namespaces cert-manager \
  --wait

# 6. Verify backup succeeded
velero backup describe emergency-backup-$(date +%Y%m%d-%H%M) --details
# Expected: Phase: Completed, Errors: 0

# 7. Update backup schedules to use us-west-2
kubectl patch schedule daily-full-backup -n velero -p '{"spec":{"template":{"storageLocation":"aws-us-west-2"}}}'
kubectl patch schedule hourly-incremental -n velero -p '{"spec":{"template":{"storageLocation":"aws-us-west-2"}}}'

# 8. Monitor for us-east-1 S3 recovery
# When recovered: Reverse steps 3-7 to restore primary backup location
```

---

## Scenario 3: Monthly DR Drill (Test Restore)

**Schedule:** First Sunday of each month, 09:00 BRT
**Duration:** ~1 hour
**Responsible:** Platform Team On-Call
**Objective:** Validate DR procedures without impacting production

**Drill Procedure:**

```bash
# 1. Create isolated test namespace
kubectl create ns dr-drill-$(date +%Y%m)

# 2. Identify most recent completed backup in replica
BACKUP_TO_TEST=$(velero backup get --storage-location aws-us-west-2 -o json | \
  jq -r '[.items[] | select(.status.phase=="Completed")] | sort_by(.metadata.creationTimestamp) | reverse | .[0].metadata.name')

echo "Testing backup: ${BACKUP_TO_TEST}"
velero backup describe ${BACKUP_TO_TEST}

# 3. Restore to test namespace (namespace mapping)
velero restore create dr-drill-$(date +%Y%m%d) \
  --from-backup ${BACKUP_TO_TEST} \
  --storage-location aws-us-west-2 \
  --namespace-mappings staging-platform-gitlab:dr-drill-$(date +%Y%m),harbor-system:dr-drill-$(date +%Y%m),staging-platform-keycloak:dr-drill-$(date +%Y%m) \
  --wait

# 4. Wait for restore completion
velero restore describe dr-drill-$(date +%Y%m%d) --details

# 5. Validate restored pods
echo "=== Pods in dr-drill-$(date +%Y%m) ==="
kubectl get pods -n dr-drill-$(date +%Y%m)

echo "=== Non-Running Pods (should be empty) ==="
kubectl get pods -n dr-drill-$(date +%Y%m) | grep -v -E 'Running|Completed' | grep -v NAME

# 6. Test database connectivity (if RDS replica enabled)
if [ -n "${NEW_RDS_ENDPOINT}" ]; then
  kubectl run psql-test -n dr-drill-$(date +%Y%m) --rm -it --image=postgres:17 \
    --env="PGHOST=${NEW_RDS_ENDPOINT}" \
    --env="PGUSER=postgres_admin" \
    --env="PGPASSWORD=${DB_PASSWORD}" \
    -- psql -d platform -c "SELECT COUNT(*) FROM pg_database;"
fi

# 7. Record drill results
cat > /tmp/dr-drill-$(date +%Y%m%d).log <<EOF
DR Drill Results — $(date)
=========================

Backup Tested: ${BACKUP_TO_TEST}
Storage Location: aws-us-west-2 (replica)
Restore Phase: $(velero restore get dr-drill-$(date +%Y%m%d) -o json | jq -r '.status.phase')
Restore Errors: $(velero restore get dr-drill-$(date +%Y%m%d) -o json | jq -r '.status.errors // 0')
Restore Warnings: $(velero restore get dr-drill-$(date +%Y%m%d) -o json | jq -r '.status.warnings // 0')

Pods Running: $(kubectl get pods -n dr-drill-$(date +%Y%m) | grep Running | wc -l)
Pods Failed: $(kubectl get pods -n dr-drill-$(date +%Y%m) | grep -v -E 'Running|Completed' | grep -v NAME | wc -l)

Database Connectivity: $([ -n "${NEW_RDS_ENDPOINT}" ] && echo "TESTED (replica)" || echo "NOT TESTED (no replica)")

PASS/FAIL: $([ $(kubectl get pods -n dr-drill-$(date +%Y%m) | grep -v -E 'Running|Completed' | grep -v NAME | wc -l) -eq 0 ] && echo "PASS" || echo "FAIL")

Notes:
- [Add any observations, issues, or follow-up actions here]
EOF

cat /tmp/dr-drill-$(date +%Y%m%d).log

# 8. Cleanup test namespace
kubectl delete ns dr-drill-$(date +%Y%m) --wait=true

echo "✅ DR drill complete — results saved to /tmp/dr-drill-$(date +%Y%m%d).log"
echo "Upload results to: docs/logbook/dr-drills/"
```

**Drill Success Criteria:**
- ✅ Restore Phase: Completed
- ✅ Restore Errors: 0
- ✅ All pods in dr-drill namespace reach Running state within 10 minutes
- ✅ Database connectivity test passes (if RDS replica enabled)

**Drill Failure Actions:**
- Document failure in drill log
- Create JIRA ticket with "DR-drill-failure" label
- Escalate to Platform Lead for root cause analysis
- Re-run drill after remediation

---

## Appendix A: Contact Information

**Platform Team:**
- Primary On-Call: PagerDuty rotation (platform-team-on-call)
- Platform Lead: [Name] <email>
- DevOps Lead: [Name] <email>

**Escalation:**
- L1: Platform Team On-Call (PagerDuty)
- L2: Platform Lead + DevOps Lead
- L3: CTO + AWS TAM (Technical Account Manager)

**AWS Support:**
- Account ID: 891377105802
- Support Plan: Business (4-hour response SLA for production-down)
- TAM: [Name] <email> (if Enterprise Support)

---

## Appendix B: Rollback Procedures

**Scenario:** us-east-1 recovers during/after DR failover

**Decision Matrix:**

| Time Since Failover | Primary Region Status | Action |
|---------------------|----------------------|--------|
| < 2 hours | us-east-1 restored, EKS healthy | ROLLBACK to us-east-1 (lower risk than reverse migration) |
| 2-8 hours | us-east-1 restored, EKS healthy | EVALUATE: business impact of second failover vs staying in us-west-2 |
| > 8 hours | us-east-1 restored | STAY in us-west-2 (treat as new primary), reverse-replicate RDS |

**Rollback Steps (< 2h scenario):**

```bash
# 1. Verify us-east-1 cluster healthy
kubectl cluster-info --context=arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod

# 2. Stop all workloads in us-west-2 DR cluster (prevent split-brain)
kubectl scale deployment --all --replicas=0 --all-namespaces --context=arn:aws:eks:us-west-2:891377105802:cluster/k8s-platform-dr

# 3. Revert DNS to us-east-1 ALB
# (Run Phase 4 steps in reverse, pointing DNS back to us-east-1 ALB)

# 4. De-promote RDS replica (NOT POSSIBLE — must re-create replication)
# Action: Create new RDS read replica from us-east-1 primary (10-15 min)
aws rds create-db-instance-read-replica \
  --db-instance-identifier k8s-platform-prod-postgresql-replica-us-west-2-new \
  --source-db-instance-identifier k8s-platform-prod-postgresql \
  --db-instance-class db.t4g.medium \
  --region us-west-2 --profile k8s-platform-staging

# 5. Update terraform state (destroy old promoted replica)
cd /platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform state rm 'module.rds_replica_staging[0].aws_db_instance.replica'

# 6. Revert Velero backup location to us-east-1 primary
velero backup-location set aws-us-east-1 --access-mode ReadWrite --default
velero backup-location set aws-us-west-2 --access-mode ReadOnly

# 7. Notify stakeholders
echo "Rollback to us-east-1 completed at $(date)" | \
  mail -s "DR Rollback Complete" stakeholders@company.com
```

---

## Appendix C: Lessons Learned Template

**Post-Incident Review (fill after DR event):**

```yaml
incident_id: DR-YYYY-MM-DD-NNN
incident_date: YYYY-MM-DD
incident_duration: X hours Y minutes
rto_target: 4 hours
rto_actual: X hours Y minutes
rpo_target: 1 hour
rpo_actual: X minutes (based on last backup replicated)

timeline:
  - time: "HH:MM"
    event: "us-east-1 outage detected"
    action_taken: "Confirmed via AWS Health Dashboard"
  - time: "HH:MM"
    event: "RDS replica promoted"
    action_taken: "Promotion successful, new endpoint captured"
  # ... add more timeline entries

what_went_well:
  - "S3 replication lag was < 5 minutes (RTC worked as expected)"
  - "Velero restore completed in 45 minutes (faster than 4h RTO)"

what_went_wrong:
  - "DNS propagation took 15 minutes due to stale TTL caches"
  - "GitLab pod failed to start due to missing PV in us-west-2"

action_items:
  - description: "Pre-create PVs in us-west-2 DR cluster"
    owner: "platform-team"
    due_date: "YYYY-MM-DD"
    jira_ticket: "INFRA-XXXX"
  - description: "Lower DNS TTL from 300s to 60s for *.staging.internal"
    owner: "platform-team"
    due_date: "YYYY-MM-DD"
    jira_ticket: "INFRA-YYYY"

cost_impact:
  - "Additional us-west-2 cluster runtime: $X"
  - "Increased S3 data transfer: $Y"
  - "Total incident cost: $Z"
```

---

**End of Runbook**
**Version:** 1.0
**Last Updated:** 2026-02-26 14:51 BRT
**Owner:** Platform Team
**Review Frequency:** Quarterly (or after each DR event/drill)
