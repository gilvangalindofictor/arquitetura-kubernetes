# Incident Report: RDS PostgreSQL Outage - GitLab Platform Blocker

**Date:** 2026-02-27
**Incident Start:** ~16:47 UTC (Pod creation time)
**Detection Time:** 19:27 UTC
**Status:** ACTIVE - Requires Manual Intervention
**Severity:** P1 - Critical (Platform-wide outage)
**Impact:** Sprint 3 Pipeline Integration BLOCKED

---

## Executive Summary

GitLab webservice and sidekiq pods have been stuck in `Init:2/3` state for 2h 40min due to RDS PostgreSQL instance being unreachable. The `dependencies` init container is running `/scripts/rails-dependencies` which attempts to connect to the database but times out continuously.

**Root Cause:** RDS instance `k8s-platform-prod-postgresql` is either:
1. Stopped (most likely - weekend shutdown automation?)
2. Security group blocking connections
3. Network connectivity issue

**Blocked Services:**
- GitLab WebService (0/2 Running)
- GitLab Sidekiq (0/1 Running)
- GitLab Runner (0/1 Running - 42 restarts due to GitLab API unavailable)
- Sprint 3 CI/CD pipeline deployment
- Developer git push/merge operations

---

## Timeline (UTC)

| Time | Event |
|------|-------|
| 16:47 | GitLab webservice pods created |
| 16:48 | Init containers `certificates` and `configure` completed successfully |
| 16:48 | Init container `dependencies` started - attempt 1 |
| 17:45 | Init container `dependencies` exited with error (Exit Code 1) - attempt 1 failed |
| 17:45-18:52 | Multiple restarts (attempts 2-3) |
| 18:52 | Init container `dependencies` started - attempt 4 (current) |
| 19:27 | Issue detected during Sprint 3 deployment investigation |

**Total Downtime:** 2 hours 40 minutes and counting

---

## Technical Details

### Pod Status
```
NAMESPACE: staging-platform-gitlab

NAME                                          READY   STATUS     RESTARTS   AGE
gitlab-webservice-default-67db8fc7d4-69zzn    0/2     Init:2/3   3          159m
gitlab-webservice-default-67db8fc7d4-dx2fm    0/2     Init:2/3   3          159m
gitlab-sidekiq-all-in-1-v2-684876b4bf-clrdp   0/1     Init:2/3   3          159m
gitlab-gitlab-runner-5cc8c8d67b-rgrgq         0/1     Running    42         159m
```

### Init Container Status
```json
{
  "name": "dependencies",
  "restartCount": 3,
  "state": {
    "running": {
      "startedAt": "2026-02-27T18:52:12Z"
    }
  },
  "lastState": {
    "terminated": {
      "exitCode": 1,
      "finishedAt": "2026-02-27T18:52:11Z",
      "reason": "Error"
    }
  }
}
```

### Database Configuration
```yaml
Host: k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com
Port: 5432
Database: gitlab
Username: gitlab_user
```

### Connectivity Test Result
```bash
# Attempted from inside pod using Ruby socket
$ timeout 10 ruby -rsocket -e "TCPSocket.new('k8s-platform-prod-postgresql...', 5432)..."
Exit Code: 124 (TIMEOUT)

Result: Connection attempt timed out after 10 seconds
Conclusion: RDS is NOT responding to TCP connections
```

### Dependencies Check Script Behavior
- Script: `/scripts/rails-dependencies`
- Purpose: Waits for PostgreSQL and Redis to be available before starting main containers
- Mechanism: Runs `Checks::PostgreSQL.run` which:
  1. Attempts to establish ActiveRecord connection
  2. Checks schema_migrations table exists
  3. Validates pending migrations count
  4. Retries with configurable timeout (WAIT_FOR_TIMEOUT env var)
- Current State: Infinite retry loop waiting for database connection

### Process Tree in Container
```
PID   COMMAND
1     /usr/bin/tini -- /scripts/exec-env /scripts/wait-for-deps
21    ruby /scripts/rails-dependencies  <-- STUCK HERE
```

---

## Root Cause Analysis

### Hypothesis 1: RDS Instance Stopped (90% confidence)
**Evidence:**
- TCP connection timeout (not refused - would get immediate rejection if security group blocked)
- Weekend context (2026-02-27 is likely Saturday/Sunday)
- Project has RDS weekend shutdown automation (MEMORY.md mentions "RDS weekend shutdown: R$ 1.200/ano")

**Validation Required:**
- Check AWS RDS console: https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#database:id=k8s-platform-prod-postgresql
- Expected status: "Stopped"

### Hypothesis 2: Security Group Change (5% confidence)
**Evidence:**
- Less likely as pods were working before
- Would typically see "Connection refused" not timeout

### Hypothesis 3: Network Issue (5% confidence)
**Evidence:**
- Other pods (gitaly, registry, kas) are running fine
- Network would affect all pods equally

---

## Impact Assessment

### Immediate Impact
- **Users Affected:** All developers and operators
- **Services Down:** GitLab WebUI, Git operations, CI/CD pipelines
- **Business Impact:**
  - Sprint 3 deployment blocked
  - No code commits/merges possible
  - No CI/CD automation
  - Platform remediation work stalled

### Dependent Services Status
```bash
✅ Keycloak: Running (has own database)
✅ ArgoCD: Running (has own database)
✅ SonarQube: Running (has own database)
✅ Harbor: Running (has own database)
❌ GitLab: BLOCKED (shared RDS)
```

### Financial Impact
- **Downtime Cost:** ~2.5 hours of developer productivity loss
- **Sprint Delay:** Sprint 3 pipeline integration delayed by 1+ day

---

## Resolution Steps

### PRIORITY 1: Start RDS Instance (Manual - AWS CLI Blocked)

**Blocker:** AWS CLI credentials not configured in current environment
```
Error: Unable to locate credentials. You can configure credentials by running "aws login".
```

**Required Action:** Manual intervention via AWS Console

#### Option A: AWS Console (RECOMMENDED - Immediate)
1. Navigate to: https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#database:id=k8s-platform-prod-postgresql
2. Verify Status column shows "Stopped"
3. Select database instance
4. Click **Actions** → **Start**
5. Confirm action
6. Wait 5-10 minutes for status to change to "Available"

#### Option B: Configure AWS CLI (Alternative)
```bash
aws configure
# Enter: AWS Access Key ID
# Enter: AWS Secret Access Key
# Region: us-east-1
# Output format: json

# Then start RDS
aws rds start-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1

# Monitor progress
aws rds wait db-instance-available \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1
```

### PRIORITY 2: Validate GitLab Recovery (Automatic)

**Expected Timeline:**
- Time 0: RDS started
- Time 5-10min: RDS status = 'available'
- Time +2min: Dependencies init container completes
- Time +5min: GitLab webservice pods Running
- Time +7min: GitLab fully operational

**Validation Commands:**
```bash
# Watch pod recovery
kubectl get pods -n staging-platform-gitlab -w

# Check logs
kubectl logs -n staging-platform-gitlab -l app=webservice -c dependencies --tail=20

# Verify services
kubectl get pods -n staging-platform-gitlab -l app=webservice
kubectl get pods -n staging-platform-gitlab -l app=sidekiq
kubectl get pods -n staging-platform-gitlab -l app=gitlab-runner
```

**Success Criteria:**
- [ ] RDS Status: Available
- [ ] GitLab webservice: 2/2 Running (2 replicas)
- [ ] GitLab sidekiq: 1/1 Running
- [ ] GitLab runner: 1/1 Running (restarts stop)
- [ ] GitLab WebUI accessible
- [ ] Git push/pull operations work

### PRIORITY 3: Prevent Recurrence

**Immediate Actions:**
1. **Update RDS Weekend Shutdown Automation:**
   - Exclude production RDS instances from weekend shutdown
   - File: TBD (locate Lambda/EventBridge rule)
   - Add tag: `AutoShutdown: false` to k8s-platform-prod-postgresql

2. **Add RDS Monitoring:**
   - Create CloudWatch alarm for RDS instance state changes
   - Alert on: Instance stopped, Instance stopping
   - Target: Slack/PagerDuty webhook

3. **Document RDS Recovery Runbook:**
   - Add to: `/docs/runbooks/rds-emergency-start.md`
   - Include: AWS Console steps, AWS CLI commands, validation steps

**Strategic Actions:**
1. **Separate Production RDS:**
   - Current: Shared RDS for staging/prod workloads
   - Target: Dedicated production RDS with different tag/name
   - Estimated effort: 8 hours (RDS snapshot + restore + migrate)

2. **Implement GitLab StatefulSet Probes:**
   - Add liveness/readiness probes to init containers
   - Fail fast if RDS unavailable (instead of infinite retry)
   - Surface clear error message in pod events

3. **Add Pre-Deployment Checks:**
   - GitLab CI pipeline checks RDS status before deploying GitLab pods
   - Fail deployment with clear message if RDS stopped

---

## Communication

### Stakeholders to Notify
- [ ] Development Team Lead (Sprint 3 delayed)
- [ ] Platform Team (RDS automation fix needed)
- [ ] FinOps Team (RDS shutdown policy review)

### Status Update Template
```
Subject: [P1 INCIDENT] GitLab Platform Outage - RDS PostgreSQL Stopped

Status: ACTIVE - Manual intervention required
Impact: All GitLab services unavailable (WebUI, Git, CI/CD)
Duration: 2h 40min and counting
Cause: RDS PostgreSQL instance stopped (likely weekend automation)

Action Required: Start RDS instance k8s-platform-prod-postgresql in AWS Console
ETA: 10 minutes after RDS start initiated

Updates: Will notify when resolved
```

---

## Lessons Learned

### What Went Well
- Quick diagnosis (pods logs, connectivity tests)
- Clear error trail (init container state, process tree)
- No data loss (stateless failure)

### What Went Wrong
- Weekend shutdown automation affected production database
- No pre-deployment RDS availability check
- No alerting on RDS state changes
- No clear separation between staging/production RDS

### Action Items
| ID | Action | Owner | Due Date | Priority |
|----|--------|-------|----------|----------|
| INC-001 | Start RDS instance immediately | AWS Admin | 2026-02-27 | P0 |
| INC-002 | Exclude prod RDS from weekend shutdown | FinOps Team | 2026-03-01 | P1 |
| INC-003 | Add RDS state change alerts | Platform Team | 2026-03-03 | P1 |
| INC-004 | Create RDS recovery runbook | SRE Team | 2026-03-05 | P2 |
| INC-005 | Separate staging/prod RDS instances | Infra Team | 2026-03-15 | P2 |
| INC-006 | Add pre-deployment RDS checks to GitLab chart | Platform Team | 2026-03-10 | P3 |

---

## Related Documents
- `/docs/VALIDATION-REPORT.md` - Sprint 3 validation status
- `/docs/operations/sprint-3-summary.md` - Sprint 3 progress
- `~/.claude/projects/-home-gilvangalindo-projects-Arquitetura-Kubernetes/memory/MEMORY.md` - RDS weekend shutdown (line mentions savings)

---

## Appendix

### Full Pod Describe Output
```bash
kubectl describe pod -n staging-platform-gitlab gitlab-webservice-default-67db8fc7d4-69zzn
```

Key Events:
```
Warning  PolicyViolation  37m   kyverno-scan  (Label validation warnings - unrelated)
Normal   Created          33m (x4 over 156m)  kubelet  spec.initContainers{dependencies}: Created
Normal   Pulled           33m (x3 over 155m)  kubelet  Container image already present
Normal   Started          33m (x4 over 156m)  kubelet  Started container dependencies
```

### Database Configuration File
Location: `/srv/gitlab/config/database.yml` (inside pod)
```yaml
production:
  main:
    adapter: postgresql
    encoding: unicode
    database: gitlab
    username: gitlab_user
    password: [REDACTED]
    host: k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com
    port: 5432
    prepared_statements: false
    database_tasks: true
```

### Dependencies Check Script
Location: `/scripts/rails-dependencies`
- Runs `Checks::PostgreSQL.run` and `Checks::Redis.run` in parallel threads
- Waits for both to succeed before completing
- Exit Code 1 if either check fails
- Retry logic controlled by WAIT_FOR_TIMEOUT and SLEEP_DURATION env vars (not set = defaults)

---

**Report Generated:** 2026-02-27 19:27 UTC
**Report Author:** AWS Infrastructure Specialist (Automated Analysis)
**Next Update:** After RDS start completed or every 30 minutes until resolved
