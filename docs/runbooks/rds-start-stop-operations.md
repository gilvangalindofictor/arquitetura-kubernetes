# RDS PostgreSQL Start/Stop Operations Runbook

## Overview

This runbook provides comprehensive procedures for managing RDS PostgreSQL instance start/stop operations in the staging environment for cost optimization while maintaining availability during business hours.

### Current Configuration

| Parameter | Value |
|-----------|-------|
| **RDS Instance ID** | `k8s-platform-prod-postgresql` |
| **Instance Type** | `db.t3.medium` |
| **Engine** | PostgreSQL 16.4 |
| **Storage** | 20 GB gp3 |
| **Region** | us-east-1 |
| **Endpoint** | `k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432` |
| **Multi-AZ** | No (staging single-AZ) |
| **Publicly Accessible** | No (private subnet only) |

### Cost Model

| Scenario | Monthly Cost (USD) | Monthly Cost (BRL @ R$6.00) | Annual Savings (BRL) |
|----------|-------------------|----------------------------|---------------------|
| **Running 24/7** | ~$100 | R$ 600 | Baseline |
| **Business Hours Only** | ~$40 | R$ 240 | R$ 4,320 |
| **Current Manual Ops** | ~$70 | R$ 420 | R$ 2,160 |
| **Projected with Automation** | ~$40 | R$ 240 | **R$ 4,320** |

**Business Hours Schedule:**
- Start: 8:00 AM BRT (11:00 UTC) Monday-Friday
- Stop: 6:00 PM BRT (21:00 UTC) Monday-Friday
- Weekend: Stopped (manual start on-demand if needed)
- Uptime: ~40% (50 hours/week vs 168 hours/week)

**Projected Savings:** ~R$ 360/month (~R$ 4,320/year)

## Dependencies Impact Matrix

| Service | Namespace | Impact When RDS Stopped | Recovery Time | Pod Behavior |
|---------|-----------|------------------------|---------------|-------------|
| **GitLab WebService** | `staging-platform-gitlab` | CrashLoopBackOff (webservice, sidekiq, migrations) | ~5 min after RDS start | Init containers timeout waiting for DB |
| **GitLab Workhorse** | `staging-platform-gitlab` | Operational (no direct DB dependency) | N/A | Continues running |
| **Keycloak** | `keycloak-system` | CrashLoopBackOff (database connection errors) | ~2 min | Pods restart automatically |
| **SonarQube** | `sonarqube` | CrashLoopBackOff (JDBC connection timeout) | ~3 min | Web server fails health checks |
| **ArgoCD** | `staging-platform-argocd` | Degraded (session persistence lost, metadata unavailable) | ~2 min | API server degraded, UI limited |
| **Harbor** | `harbor-system` | Minimal (uses internal PostgreSQL HA) | N/A | No impact (separate DB) |
| **Grafana** | `monitoring` | Minimal (uses internal SQLite for dashboards) | N/A | No impact |

### Service Recovery Sequence

When RDS starts, services recover in this order:

1. **RDS Instance** (5-10 minutes): `stopped` → `starting` → `available`
2. **Keycloak** (~2 min): Pods restart and connect to DB
3. **ArgoCD** (~2 min): API server reconnects, sessions restored
4. **SonarQube** (~3 min): Web server health checks pass
5. **GitLab** (~5 min): Init containers complete → webservice/sidekiq start

**Total Recovery Time:** ~10-15 minutes (RDS startup + service restarts)

## Manual Operations

### A. Emergency Start (Incident Response)

**Use Case:** RDS is stopped and services are down, need immediate recovery.

**Prerequisites:**
- AWS CLI configured with appropriate credentials
- IAM permissions: `rds:DescribeDBInstances`, `rds:StartDBInstance`

**Procedure:**

```bash
# Step 1: Check current RDS status
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,AvailabilityZone:AvailabilityZone}' \
  --output table

# Expected output:
# -----------------------------------------------
# |          DescribeDBInstances               |
# +------------------+-------------------------+
# | AvailabilityZone |  us-east-1a            |
# | Endpoint         |  k8s-platform-prod-... |
# | Status           |  stopped               |
# +------------------+-------------------------+

# Step 2: Start RDS instance
aws rds start-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1

# Expected output:
# {
#     "DBInstance": {
#         "DBInstanceStatus": "starting",
#         ...
#     }
# }

# Step 3: Wait for RDS to become available (5-10 minutes)
# Option A: Wait command (recommended)
echo "Waiting for RDS to become available (this may take 5-10 minutes)..."
aws rds wait db-instance-available \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1

echo "RDS is now available!"

# Option B: Monitor status manually
watch -n 10 'aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text'

# Step 4: Validate connectivity from within cluster
kubectl run -it --rm pg-test \
  --image=postgres:13 \
  --restart=Never \
  --namespace=staging-platform-gitlab \
  -- psql -h k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com \
        -U <username> \
        -d gitlab \
        -c "SELECT 1 as healthy, current_database(), version();"

# Expected output:
#  healthy | current_database |                     version
# ---------+------------------+-------------------------------------------------
#        1 | gitlab           | PostgreSQL 16.4 on x86_64-pc-linux-gnu...

# Step 5: Watch GitLab pods recover
kubectl get pods -n staging-platform-gitlab -w

# Expected progression:
# gitlab-webservice-default-xxx   0/3   Init:2/3    (waiting for DB)
# gitlab-webservice-default-xxx   3/3   Running     (DB connected)

# Step 6: Verify all dependent services
kubectl get pods -n keycloak-system -l app.kubernetes.io/name=keycloak
kubectl get pods -n sonarqube -l app=sonarqube
kubectl get pods -n staging-platform-argocd -l app.kubernetes.io/name=argocd-server

# All pods should be Running within 5 minutes
```

**Success Criteria:**
- RDS status: `available`
- GitLab webservice pods: `Running` (3/3 containers ready)
- Keycloak pods: `Running`
- SonarQube pods: `Running`
- ArgoCD API server: `Running`

**Troubleshooting:**

| Issue | Diagnosis | Resolution |
|-------|-----------|------------|
| RDS stuck in `starting` | Check CloudWatch Logs for errors | Wait 15 min, if still starting contact AWS Support |
| RDS start fails with `InvalidDBInstanceState` | RDS in unsupported state (e.g., `modifying`) | Wait for current operation to complete |
| Pods not recovering | Network connectivity issue | Verify security group rules, VPC routing |
| Connection timeout from pods | Security group misconfigured | Verify RDS SG allows ingress from private subnets |

### B. Planned Stop (Maintenance Window)

**Use Case:** End of business day, proactively stop RDS to save costs.

**Prerequisites:**
- Verify no active users (check GitLab sessions, ArgoCD syncs, SonarQube scans)
- Notify team in Slack `#platform-staging` channel

**Procedure:**

```bash
# Step 1: Verify current activity
# Check GitLab active sessions
kubectl logs -n staging-platform-gitlab deployment/gitlab-webservice-default --tail=100 | grep "Started GET"

# Check ArgoCD active syncs
kubectl get applications -A --field-selector status.sync.status=Syncing

# Check SonarQube active scans
kubectl logs -n sonarqube deployment/sonarqube --tail=50 | grep "Analysis"

# Step 2: Notify team
# Post in Slack: "Stopping staging RDS at [TIME] for cost optimization. Services will be unavailable until tomorrow 8 AM BRT."

# Step 3: Verify RDS current status
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text

# Step 4: Stop RDS instance
aws rds stop-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1

# Expected output:
# {
#     "DBInstance": {
#         "DBInstanceStatus": "stopping",
#         ...
#     }
# }

# Step 5: Monitor stop progress (2-5 minutes)
watch -n 10 'aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text'

# Expected progression: available → stopping → stopped

# Step 6: Verify expected pod states
kubectl get pods -n staging-platform-gitlab -l app=webservice

# Expected states:
# gitlab-webservice-default-xxx   0/3   Init:2/3    (dependencies timeout)

kubectl get pods -n keycloak-system -l app.kubernetes.io/name=keycloak

# Expected states:
# keycloak-0   0/1   CrashLoopBackOff   (database connection refused)

kubectl get pods -n sonarqube -l app=sonarqube

# Expected states:
# sonarqube-xxx   0/1   CrashLoopBackOff   (JDBC connection timeout)

# Step 7: Document stop time
echo "RDS stopped at $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
```

**Success Criteria:**
- RDS status: `stopped`
- GitLab webservice: `Init:2/3` or `Init:Error` (waiting for DB)
- Keycloak: `CrashLoopBackOff` (database unreachable)
- SonarQube: `CrashLoopBackOff` (connection timeout)
- No data loss (connections gracefully closed)

**Expected Pod Behavior When RDS Stopped:**

```yaml
# GitLab WebService Pod Status
Name:         gitlab-webservice-default-xxx
Status:       Pending
Init Containers:
  configure:              Completed
  dependencies:           Running (timeout waiting for postgresql:5432)
Containers:
  webservice:             Waiting (PodInitializing)
Events:
  Warning  Unhealthy  5m (x10 over 10m)  kubelet  Readiness probe failed: dial tcp: i/o timeout
```

### C. Scheduled Automation (Business Hours)

**Automated Schedule (EventBridge + Lambda):**

| Event | Time (BRT) | Time (UTC) | Cron Expression | Lambda Function |
|-------|-----------|-----------|-----------------|----------------|
| **Morning Startup** | 8:00 AM Mon-Fri | 11:00 AM | `cron(0 11 ? * MON-FRI *)` | `finops-scheduler-start-staging` |
| **Evening Shutdown** | 6:00 PM Mon-Fri | 9:00 PM | `cron(0 21 ? * MON-FRI *)` | `finops-scheduler-stop-staging` |
| **Weekend Shutdown** | 12:00 AM Sat | 3:00 AM | `cron(0 3 ? * SAT *)` | `finops-scheduler-stop-staging` |

**Manual Override (On-Demand):**

```bash
# Start RDS outside business hours (e.g., weekend debugging)
aws lambda invoke \
  --function-name finops-scheduler-start-staging \
  --payload '{"action":"start","environment":"staging","triggered_by":"manual-override"}' \
  --region us-east-1 \
  /tmp/lambda-response.json

cat /tmp/lambda-response.json | jq

# Expected output:
# {
#   "statusCode": 200,
#   "body": {
#     "timestamp": "2026-02-27T14:30:00Z",
#     "environment": "staging",
#     "rds": {
#       "instance": "k8s-platform-prod-postgresql",
#       "status": "start_initiated"
#     }
#   }
# }

# Stop RDS manually (emergency cost control)
aws lambda invoke \
  --function-name finops-scheduler-stop-staging \
  --payload '{"action":"stop","environment":"staging","triggered_by":"manual-override"}' \
  --region us-east-1 \
  /tmp/lambda-response.json

cat /tmp/lambda-response.json | jq
```

**Check Lambda Execution Logs:**

```bash
# View start Lambda logs
aws logs tail /aws/lambda/finops-scheduler-start-staging --follow --region us-east-1

# View stop Lambda logs
aws logs tail /aws/lambda/finops-scheduler-stop-staging --follow --region us-east-1

# Query last 10 executions
aws logs filter-log-events \
  --log-group-name /aws/lambda/finops-scheduler-start-staging \
  --filter-pattern "RDS" \
  --max-items 10 \
  --region us-east-1
```

## Automated Operations Architecture

### Lambda Function Flow

```
┌─────────────────┐
│ EventBridge     │
│ Cron Schedule   │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ Lambda: finops-scheduler-start-staging  │
│                                         │
│ 1. Check circuit breaker (DynamoDB)    │
│ 2. Check RDS status (describe-db)      │
│ 3. Start RDS if stopped                │
│ 4. Scale EKS node groups (parallel)     │
│ 5. Update DynamoDB state                │
│ 6. Send SNS notification                │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐         ┌──────────────┐
│ RDS Instance    │         │ EKS Node     │
│ started → avail │         │ Groups scaled│
└─────────────────┘         └──────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│ Dependent Services Auto-Recover        │
│ - GitLab webservice (5 min)            │
│ - Keycloak (2 min)                     │
│ - SonarQube (3 min)                    │
│ - ArgoCD (2 min)                       │
└─────────────────────────────────────────┘
```

### Circuit Breaker Protection

**DynamoDB State Table:**

```json
{
  "environment": "staging",
  "last_startup": "2026-02-27T11:00:00Z",
  "last_shutdown": "2026-02-26T21:00:00Z",
  "startup_failures": 0,
  "shutdown_failures": 0,
  "circuit_breaker_state": "CLOSED"
}
```

**Circuit Breaker Logic:**

| Condition | Action | State Transition |
|-----------|--------|-----------------|
| **3 consecutive startup failures** | Open circuit → disable automation | `CLOSED` → `OPEN` |
| **Circuit OPEN** | Skip scheduled starts, send alert to ops | Stay `OPEN` |
| **Manual reset** | Close circuit after root cause fixed | `OPEN` → `CLOSED` |
| **Successful start** | Reset failure counter to 0 | Stay `CLOSED` |

**Manual Circuit Breaker Reset:**

```bash
# Check current state
aws dynamodb get-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment":{"S":"staging"}}' \
  --region us-east-1 | jq

# Reset circuit breaker to CLOSED (after fixing root cause)
aws dynamodb update-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment":{"S":"staging"}}' \
  --update-expression "SET circuit_breaker_state = :closed, startup_failures = :zero, shutdown_failures = :zero" \
  --expression-attribute-values '{":closed":{"S":"CLOSED"},":zero":{"N":"0"}}' \
  --region us-east-1
```

### SNS Notifications

**Notification Channels:**

| Event | Subject | Recipients |
|-------|---------|-----------|
| **Successful Start** | `EKS Start - staging - SUCCESS` | devops-team@company.com, Slack #platform-staging |
| **Successful Stop** | `EKS Stop - staging - SUCCESS` | devops-team@company.com, Slack #platform-staging |
| **Startup Failure** | `EKS Start - staging - FAILED` | devops-team@company.com (PagerDuty escalation) |
| **Circuit Breaker Opened** | `ALERT: FinOps Circuit Breaker OPEN` | devops-leads@company.com (critical) |

**Sample Notification (Successful Start):**

```
Subject: EKS Start - staging - SUCCESS

Environment: staging
Cluster: k8s-platform-prod
Timestamp: 2026-02-27T11:00:00Z

Node Groups:
  - system: initiated (update_id: abc123, desired: 2)
  - workloads: initiated (update_id: def456, desired: 3)
  - critical: initiated (update_id: ghi789, desired: 2)

RDS:
  - k8s-platform-prod-postgresql: start_initiated (previous: stopped)

Expected Recovery Time: 10-15 minutes
```

## Troubleshooting

### Issue 1: RDS Start Fails

**Symptoms:**
```bash
aws rds start-db-instance ...
# Error: InvalidDBInstanceState
```

**Diagnosis:**
```bash
# Check detailed RDS status
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --query 'DBInstances[0].{Status:DBInstanceStatus,PendingModifiedValues:PendingModifiedValues}'

# Check CloudWatch Logs
aws logs tail /aws/rds/instance/k8s-platform-prod-postgresql/postgresql --follow
```

**Resolution:**
- If status is `modifying`, `backing-up`, `upgrading`: Wait for operation to complete (10-30 min)
- If status is `failed`: Check RDS Events for root cause, may require manual intervention
- If status is `storage-full`: Increase storage before starting

### Issue 2: RDS Stuck in "Starting" State

**Symptoms:**
```bash
# Status remains "starting" for > 15 minutes
DBInstanceStatus: starting
```

**Diagnosis:**
```bash
# Check RDS Events
aws rds describe-events \
  --source-type db-instance \
  --source-identifier k8s-platform-prod-postgresql \
  --duration 60 \
  --region us-east-1

# Check CloudWatch metrics
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

**Resolution:**
- Wait 20 minutes total (normal for large instances)
- If > 20 min: Open AWS Support ticket
- Check AWS Service Health Dashboard for regional issues

### Issue 3: Pods Not Recovering After RDS Start

**Symptoms:**
```bash
# RDS status: available
# GitLab pods still in Init:2/3 or CrashLoopBackOff
```

**Diagnosis:**
```bash
# Check pod logs
kubectl logs -n staging-platform-gitlab deployment/gitlab-webservice-default -c dependencies

# Expected error if RDS unreachable:
# Error: could not connect to server: Connection refused
#         Is the server running on host "k8s-platform-prod-postgresql..." and accepting
#         TCP/IP connections on port 5432?

# Check network connectivity from pod
kubectl run -it --rm debug \
  --image=nicolaka/netshoot \
  --namespace=staging-platform-gitlab \
  -- bash

# Inside pod:
nc -zv k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com 5432
# Expected: succeeded!
```

**Resolution:**

| Root Cause | Fix |
|-----------|-----|
| **Security group rules** | Add private subnet CIDR to RDS SG ingress (port 5432) |
| **DNS resolution failure** | Verify VPC DNS settings (`enableDnsHostnames`, `enableDnsSupport`) |
| **Incorrect credentials** | Rotate password in Secrets Manager, update K8s secrets |
| **RDS endpoint changed** | Update ExternalName service if RDS was recreated |

### Issue 4: Connection Timeout from Pods

**Symptoms:**
```bash
# Pod logs show timeout errors
could not connect to server: Connection timed out
```

**Diagnosis:**
```bash
# Verify RDS security group allows pod CIDR
aws ec2 describe-security-groups \
  --group-ids <RDS-SG-ID> \
  --query 'SecurityGroups[0].IpPermissions[]' \
  --region us-east-1

# Check VPC route tables
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<VPC-ID>" \
  --query 'RouteTables[*].Routes[*]' \
  --region us-east-1

# Test from bastion/EC2 in same VPC
psql -h k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com \
     -U <username> -d postgres
```

**Resolution:**
- Update RDS security group ingress rules to allow:
  - Private subnet CIDRs (where pods run)
  - VPC CIDR (for VPC CNI secondary IP ranges)
- Verify no Network ACLs blocking PostgreSQL port 5432

### Issue 5: Lambda Function Timeout

**Symptoms:**
```bash
# Lambda logs show timeout after 5 minutes
Task timed out after 300.00 seconds
```

**Diagnosis:**
```bash
# Check Lambda execution duration
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=finops-scheduler-start-staging \
  --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Maximum,Average \
  --region us-east-1
```

**Resolution:**
- RDS start is asynchronous (Lambda doesn't wait for `available` state)
- If timeout occurs:
  - Check DynamoDB for circuit breaker trips
  - Increase Lambda timeout in Terraform (current: 300s)
  - Review Lambda code for synchronous waits (should be async)

## Rollback Procedures

### Disable Automation (Return to 24/7 Availability)

**Use Case:** Automation causing issues, revert to always-on RDS.

**Procedure:**

```bash
# Step 1: Disable EventBridge rules (stops scheduled triggers)
aws events disable-rule \
  --name finops-startup-staging \
  --region us-east-1

aws events disable-rule \
  --name finops-shutdown-staging \
  --region us-east-1

aws events disable-rule \
  --name finops-weekend-shutdown-staging \
  --region us-east-1

# Step 2: Start RDS manually (if currently stopped)
aws rds start-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1

# Wait for available
aws rds wait db-instance-available \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1

# Step 3: Verify RDS is running
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text

# Step 4: Update Terraform to disable automation
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform apply -var="enable_automation=false"

# Step 5: Notify team
echo "FinOps RDS automation disabled. RDS will remain running 24/7 until further notice."
```

**Success Criteria:**
- EventBridge rules: `DISABLED`
- RDS status: `available`
- No scheduled start/stop events triggered
- Services: `Running` (stable)

### Re-enable Automation (After Fix)

```bash
# Step 1: Verify issues resolved
# - Check circuit breaker: CLOSED
# - Test manual Lambda invocation
# - Verify SNS notifications working

# Step 2: Enable EventBridge rules
aws events enable-rule \
  --name finops-startup-staging \
  --region us-east-1

aws events enable-rule \
  --name finops-shutdown-staging \
  --region us-east-1

aws events enable-rule \
  --name finops-weekend-shutdown-staging \
  --region us-east-1

# Step 3: Update Terraform
terraform apply -var="enable_automation=true"

# Step 4: Monitor first automated cycle
# - Check logs after next scheduled event
# - Verify SNS notifications sent
# - Confirm services recover as expected
```

## Cost Validation

### Track Monthly Savings

```bash
# Get RDS runtime hours for current month
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=k8s-platform-prod-postgresql \
  --start-time $(date -u -d 'first day of this month' +%Y-%m-%dT00:00:00) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum \
  --region us-east-1 \
  --query 'Datapoints[?Sum>`0`] | length(@)'

# Calculate cost savings
# Baseline: 730 hours/month * $0.0685/hour = $50/month
# Actual: [HOURS] * $0.0685/hour = $X/month
# Savings: $50 - $X = $Y/month

# Query AWS Cost Explorer API
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d 'first day of this month' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter file://<(cat <<EOF
{
  "Dimensions": {
    "Key": "SERVICE",
    "Values": ["Amazon Relational Database Service"]
  },
  "Tags": {
    "Key": "Name",
    "Values": ["k8s-platform-prod-postgresql"]
  }
}
EOF
) \
  --region us-east-1
```

### Grafana Dashboard

**Cost Savings Dashboard Panel:**

```json
{
  "title": "RDS FinOps Savings (Monthly)",
  "targets": [
    {
      "datasource": "CloudWatch",
      "namespace": "AWS/RDS",
      "metricName": "DatabaseConnections",
      "dimensions": {
        "DBInstanceIdentifier": "k8s-platform-prod-postgresql"
      },
      "statistic": "Sum",
      "period": "3600"
    }
  ],
  "fieldConfig": {
    "overrides": [
      {
        "matcher": { "id": "byName", "options": "Uptime Hours" },
        "properties": [
          {
            "id": "unit",
            "value": "hours"
          }
        ]
      }
    ]
  },
  "transformations": [
    {
      "id": "calculateField",
      "options": {
        "alias": "Monthly Savings (BRL)",
        "binary": {
          "left": "Baseline Cost",
          "operator": "-",
          "right": "Actual Cost"
        }
      }
    }
  ]
}
```

## Maintenance

### Weekly Review Checklist

- [ ] Check circuit breaker state (should be `CLOSED`)
- [ ] Review CloudWatch alarms (no failures)
- [ ] Verify SNS notifications delivered
- [ ] Check Lambda execution logs for errors
- [ ] Validate cost savings in Cost Explorer
- [ ] Review pod recovery times (should be < 15 min)

### Monthly Audit

- [ ] Calculate actual savings vs projected
- [ ] Review DynamoDB state table for anomalies
- [ ] Update cost model if RDS instance type changed
- [ ] Test manual override procedures
- [ ] Verify EventBridge schedules still aligned with business hours
- [ ] Check for AWS service updates (RDS engine version, Lambda runtime)

## References

- **FinOps Module Source:** `platform-provisioning/aws/kubernetes/terraform/modules/finops-automation/`
- **Lambda Functions:** `lambda/lambda_start.py`, `lambda/lambda_stop.py`
- **ADR-088:** RDS Scheduler Automation Decision Record
- **Cost Analysis:** Marco 2 FinOps Savings Validation (2026-01-30)
- **AWS Documentation:** [Working with Amazon RDS DB instances](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithDBInstances.html)

## Emergency Contacts

| Role | Contact | Escalation Path |
|------|---------|----------------|
| **Primary On-Call** | DevOps Team | Slack #platform-staging → PagerDuty |
| **FinOps Lead** | devops-team@company.com | Email → Phone |
| **AWS Support** | Enterprise Support | AWS Console → Open Case (Severity: High) |

---

**Document Version:** 1.0
**Last Updated:** 2026-02-27
**Author:** FinOps Automation Team
**Review Date:** 2026-03-27
