# Runbook: RDS PostgreSQL Emergency Start

**Purpose:** Quickly start stopped RDS PostgreSQL instance to restore GitLab platform
**Severity:** P1 Critical - Platform-wide outage
**MTTR Target:** 15 minutes

---

## Quick Start (Executive Summary)

**Symptom:** GitLab pods stuck in Init:2/3, cannot connect to database

**Fix:** Start RDS instance `k8s-platform-prod-postgresql` in AWS Console

**Steps:**
1. Open AWS Console → RDS
2. Select `k8s-platform-prod-postgresql`
3. Actions → Start
4. Wait 10 minutes
5. Validate GitLab pods recover

---

## Detection

### Symptoms
- GitLab webservice pods: `0/2 Init:2/3` for extended period (>10 min)
- GitLab sidekiq pods: `0/1 Init:2/3`
- GitLab runner: High restart count (crashloop)
- GitLab WebUI: HTTP 503 or unreachable

### Quick Diagnostic
```bash
# Check pod status
kubectl get pods -n staging-platform-gitlab

# Expected if RDS stopped:
# gitlab-webservice-* 0/2 Init:2/3 (stuck)
# gitlab-sidekiq-*    0/1 Init:2/3 (stuck)
# gitlab-runner-*     0/1 Running  (high restarts)

# Check init container logs
kubectl logs -n staging-platform-gitlab -l app=webservice -c dependencies --tail=20

# Expected output: Config file writes, then silence (waiting for DB)
```

### Connectivity Test
```bash
# Test RDS connectivity from pod
POD=$(kubectl get pod -n staging-platform-gitlab -l app=webservice -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n staging-platform-gitlab $POD -c dependencies -- \
  timeout 10 ruby -rsocket -e "TCPSocket.new('k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com', 5432).close; puts 'OK'"

# Exit Code 124 = TIMEOUT = RDS not responding (likely stopped)
# Exit Code 0 + "OK" = RDS responding (check security groups/network)
```

---

## Resolution

### Option A: AWS Console (FASTEST - Recommended)

**Time Required:** 2 minutes manual + 10 minutes RDS startup

**Steps:**
1. **Navigate to RDS Console:**
   - URL: https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1
   - Or: AWS Console → Services → RDS → Databases

2. **Locate Instance:**
   - Find: `k8s-platform-prod-postgresql`
   - Check Status column (should show "Stopped")

3. **Start Instance:**
   - Select checkbox next to instance
   - Click **Actions** dropdown (top right)
   - Select **Start**
   - Confirm in dialog

4. **Monitor Progress:**
   - Status changes: Stopped → Starting → Available
   - Estimated time: 5-10 minutes
   - Refresh page every 30 seconds

5. **Verify Endpoint:**
   - Click instance name
   - Check "Connectivity & security" tab
   - Endpoint should be: `k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com`
   - Status: Available

### Option B: AWS CLI (If Credentials Available)

**Time Required:** 1 minute command + 10 minutes RDS startup

**Prerequisites:**
```bash
# Check AWS CLI configured
aws sts get-caller-identity

# If not configured, set up:
aws configure
# Enter: Access Key ID, Secret Access Key
# Region: us-east-1
# Output: json
```

**Commands:**
```bash
# 1. Verify RDS status
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text

# Expected output: stopped

# 2. Start RDS instance
aws rds start-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1

# Expected output: JSON with "DBInstanceStatus": "starting"

# 3. Wait for availability (blocks until ready or 10min timeout)
aws rds wait db-instance-available \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --cli-read-timeout 600

# No output = success
# Error = timeout or failure

# 4. Verify endpoint accessible
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "RDS Endpoint: $RDS_ENDPOINT"
# Should output: k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com
```

---

## Validation

### Phase 1: RDS Health (Immediate)
```bash
# Check RDS status via CLI
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,AvailabilityZone]' \
  --output table

# Expected output:
# | available | k8s-platform-prod-postgresql.cw9k... | us-east-1a |
```

### Phase 2: GitLab Pod Recovery (5-10 minutes after RDS available)
```bash
# Watch pod status (Ctrl+C to exit)
kubectl get pods -n staging-platform-gitlab -w

# Expected progression:
# Time 0:  gitlab-webservice-* 0/2 Init:2/3 (stuck)
# Time 2m: gitlab-webservice-* 0/2 PodInitializing (init completing)
# Time 5m: gitlab-webservice-* 2/2 Running (success!)

# Check specific pods
kubectl get pods -n staging-platform-gitlab -l app=webservice
kubectl get pods -n staging-platform-gitlab -l app=sidekiq
kubectl get pods -n staging-platform-gitlab -l app=gitlab-runner

# All should show: X/X Running with 0 recent restarts
```

### Phase 3: Dependencies Init Container Completion
```bash
# Check init container completed
POD=$(kubectl get pod -n staging-platform-gitlab -l app=webservice -o jsonpath='{.items[0].metadata.name}')

kubectl get pod -n staging-platform-gitlab $POD -o json | \
  jq -r '.status.initContainerStatuses[] | select(.name=="dependencies") | .state'

# Expected output:
# { "terminated": { "exitCode": 0, "reason": "Completed", ... } }
```

### Phase 4: GitLab Service Health (15 minutes total)
```bash
# 1. Check webservice responds
kubectl port-forward -n staging-platform-gitlab svc/gitlab-webservice-default 8080:8080 &
sleep 5
curl -I http://localhost:8080
pkill -f "port-forward.*gitlab"

# Expected: HTTP/1.1 200 OK or HTTP/1.1 302 (redirect to login)

# 2. Check GitLab runner registered
kubectl logs -n staging-platform-gitlab -l app=gitlab-runner --tail=20 | grep -i registered

# Expected: "Runner registered successfully"

# 3. Check sidekiq processing jobs
kubectl logs -n staging-platform-gitlab -l app=sidekiq --tail=20 | grep -i "done:"

# Expected: Job completion messages
```

### Phase 5: Dependent Services (Optional)
```bash
# Verify other services still healthy
kubectl get pods -n keycloak-system -l app.kubernetes.io/name=keycloak
kubectl get pods -n sonarqube -l app=sonarqube
kubectl get pods -n staging-platform-argocd -l app.kubernetes.io/name=argocd-server

# All should be: Running
```

---

## Success Criteria Checklist

- [ ] RDS instance status: "Available"
- [ ] RDS endpoint accessible: `k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432`
- [ ] GitLab webservice pods: 2/2 Running
- [ ] GitLab sidekiq pods: 1/1 Running
- [ ] GitLab runner: 1/1 Running (restarts stopped)
- [ ] Init container `dependencies` status: Completed (exitCode 0)
- [ ] GitLab WebUI accessible via port-forward
- [ ] GitLab runner registered
- [ ] No error logs in webservice/sidekiq

**Total Recovery Time:** 15-20 minutes from RDS start initiation

---

## Common Issues

### Issue 1: RDS Starts But GitLab Pods Still Stuck

**Symptoms:**
- RDS status: Available
- Pods still: Init:2/3 after 10+ minutes

**Possible Causes:**
1. Security group blocking cluster → RDS traffic
2. Database credentials mismatch
3. Database schema migration pending

**Diagnostic:**
```bash
# Test connectivity from pod
POD=$(kubectl get pod -n staging-platform-gitlab -l app=webservice -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n staging-platform-gitlab $POD -c dependencies -- \
  timeout 5 ruby -rsocket -e "TCPSocket.new('k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com', 5432).close; puts 'OK'"

# Exit 0 + "OK" = connectivity good, check logs for schema/auth errors
# Exit 124 = timeout = security group or network issue
```

**Resolution:**
- Check RDS security group allows traffic from EKS cluster security group
- Check database credentials in GitLab secret match RDS master user
- Check init container logs for specific error: `kubectl logs ... -c dependencies`

### Issue 2: RDS Won't Start (CloudWatch Shows Errors)

**Symptoms:**
- Start command accepted but status stays "Stopped" or fails

**Possible Causes:**
- Insufficient DB instance capacity in availability zone
- Automated backup in progress
- IAM permissions insufficient

**Resolution:**
- Check CloudWatch Logs for RDS instance for specific error
- Wait 15 minutes for automated backup to complete
- Contact AWS support if capacity issue
- Verify IAM permissions include `rds:StartDBInstance`

### Issue 3: GitLab Runner Still Crashlooping After Recovery

**Symptoms:**
- Webservice/sidekiq Running
- Runner still restarting

**Cause:**
- Runner cache/state corruption from extended outage

**Resolution:**
```bash
# Delete runner pod to force clean restart
kubectl delete pod -n staging-platform-gitlab -l app=gitlab-runner

# Wait for new pod
kubectl wait --for=condition=Ready pod -n staging-platform-gitlab -l app=gitlab-runner --timeout=120s

# Verify registration
kubectl logs -n staging-platform-gitlab -l app=gitlab-runner --tail=20
```

---

## Root Cause Prevention

### Immediate (This Week)
1. **Exclude Production RDS from Weekend Shutdown:**
   ```bash
   # Add tag to RDS instance
   aws rds add-tags-to-resource \
     --resource-name arn:aws:rds:us-east-1:ACCOUNT_ID:db:k8s-platform-prod-postgresql \
     --tags Key=AutoShutdown,Value=false

   # Update Lambda function to check tag before shutdown
   ```

2. **Add CloudWatch Alarm:**
   - Metric: Custom (EventBridge rule on RDS StateChange)
   - Condition: Instance stopped/stopping
   - Action: SNS → Slack/PagerDuty
   - Target: Platform team on-call

### Strategic (Next 2 Weeks)
1. **Separate Staging/Production RDS:**
   - Create new RDS instance: `k8s-platform-staging-postgresql`
   - Migrate staging GitLab to new instance
   - Keep production RDS dedicated, tagged appropriately

2. **Add Pre-Deployment Checks:**
   - GitLab Helm chart: Add init script to check RDS availability before creating pods
   - Fail deployment with clear error if RDS stopped
   - Sample script:
     ```bash
     #!/bin/bash
     # Check RDS available before deploying GitLab
     if ! aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE --query 'DBInstances[0].DBInstanceStatus' --output text | grep -q 'available'; then
       echo "ERROR: RDS instance $DB_INSTANCE is not available. Start it before deploying GitLab."
       exit 1
     fi
     ```

3. **Improve Pod Failure Visibility:**
   - Add liveness probe to init containers with shorter timeout
   - Surface clear error message in pod events: "Database unreachable - check RDS status"
   - Create PrometheusRule alert: `GitLabInitContainerStuck{container="dependencies"}`

---

## Related Incidents

- **2026-02-27:** First occurrence - RDS weekend shutdown affected production
- **Future:** Track similar incidents here

---

## Contacts

- **AWS Admin:** (TBD - add contact)
- **Platform Team Lead:** (TBD)
- **On-Call Rotation:** (TBD - PagerDuty schedule)

---

## References

- Incident Report: `/docs/logbook/2026-02-27-rds-postgresql-outage-incident.md`
- GitLab Dependencies Check Script: `/scripts/rails-dependencies` (inside pod)
- PostgreSQL Check Logic: `/scripts/lib/checks/postgresql.rb` (inside pod)
- AWS RDS Console: https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1

---

**Runbook Version:** 1.0
**Last Updated:** 2026-02-27
**Next Review:** 2026-03-10 (after prevention measures implemented)
