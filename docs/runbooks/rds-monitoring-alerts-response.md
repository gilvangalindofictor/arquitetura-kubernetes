# RDS Monitoring: Alert Response Runbook

**Version:** 1.0
**Last Updated:** 2026-02-27
**Owner:** Platform SRE Team
**Severity:** CRITICAL (P1)

## Table of Contents

1. [Overview](#overview)
2. [Alert Index](#alert-index)
3. [Critical Alerts](#critical-alerts)
   - [RDS Instance Stopped](#rds-instance-stopped)
   - [Platform-Wide Outage](#platform-wide-outage)
   - [GitLab Connectivity Failure](#gitlab-connectivity)
   - [Keycloak Connectivity Failure](#keycloak-connectivity)
4. [Warning Alerts](#warning-alerts)
   - [High CPU](#high-cpu)
   - [High Connections](#high-connections)
   - [Low Storage](#low-storage)
   - [High Latency](#high-latency)
5. [Escalation Matrix](#escalation-matrix)
6. [Post-Incident Actions](#post-incident-actions)

---

## Overview

### Purpose

This runbook provides step-by-step response procedures for RDS PostgreSQL monitoring alerts.

**Context:** GitLab webservice was stuck in Init:2/3 state when RDS was stopped without alerting, causing platform-wide failures. This monitoring system prevents silent database outages.

### Architecture

**Multi-Layer Monitoring:**

1. **CloudWatch Alarms** (AWS native): Direct RDS instance monitoring
   - RDS instance stopped/started
   - CPU, memory, connections, storage, latency
   - RDS lifecycle events (failover, maintenance, backups)

2. **Prometheus Alerts** (K8s native): Application-level connectivity detection
   - GitLab webservice Init state
   - Keycloak CrashLoopBackOff
   - SonarQube database errors
   - ArgoCD controller restarts

3. **Grafana Dashboard**: Unified view combining CloudWatch + Prometheus
   - Real-time RDS status
   - Dependent service health
   - Alert history

### Critical Dependencies

RDS PostgreSQL (`k8s-platform-prod-postgresql`) is a single point of failure for:

| Service | Impact if RDS Down | Recovery Time |
|---------|-------------------|---------------|
| GitLab | CI/CD halted, Git push/pull failing | 5-7 minutes |
| Keycloak | SSO unavailable, no authentication | 3-5 minutes |
| SonarQube | Code scans unavailable | 5-10 minutes |
| ArgoCD | GitOps sync delayed (PostgreSQL backend) | 3-5 minutes |

**RDS Startup Time:** 3-5 minutes (from stopped state)

### Response SLA

| Severity | Response Time | Resolution Target |
|----------|---------------|-------------------|
| CRITICAL | 5 minutes | 15 minutes |
| WARNING | 30 minutes | 4 hours |

---

## Alert Index

### Critical Alerts (Immediate Response)

| Alert Name | Source | Trigger | Impact |
|------------|--------|---------|--------|
| `staging-rds-instance-stopped` | CloudWatch | RDS stopped | Platform-wide outage |
| `RDSPostgreSQLPlatformWideOutage` | Prometheus | 2+ services failing | Platform-wide outage |
| `GitLabRDSConnectivityFailure` | Prometheus | GitLab Init >5min | CI/CD unavailable |
| `KeycloakRDSConnectivityFailure` | Prometheus | Keycloak CrashLoop >3min | SSO unavailable |

### Warning Alerts (Proactive Response)

| Alert Name | Source | Trigger | Impact |
|------------|--------|---------|--------|
| `staging-rds-high-cpu` | CloudWatch | CPU >80% for 5min | Performance degradation |
| `staging-rds-high-connections` | CloudWatch | Connections >117 (80%) | Connection exhaustion risk |
| `staging-rds-low-storage` | CloudWatch | Free storage <20GB | Disk full risk |
| `staging-rds-high-read-latency` | CloudWatch | Read latency >50ms | Slow queries |
| `staging-rds-high-write-latency` | CloudWatch | Write latency >50ms | Slow transactions |

---

## Critical Alerts

### RDS Instance Stopped

**Alert:** `staging-rds-instance-stopped` (CloudWatch)
**Severity:** CRITICAL (P1)
**Response SLA:** 5 minutes

#### Symptoms

- Email notification: "ALARM: staging-rds-instance-stopped in US East (N. Virginia)"
- CloudWatch metric: `DatabaseConnections = 0`
- Platform-wide database connection failures
- GitLab webservice stuck in Init:2/3
- Keycloak pods in CrashLoopBackOff

#### Root Causes

1. **Manual stop** (AWS console, CLI)
2. **FinOps automation** (Lambda auto-shutdown)
3. **Billing issues** (AWS account suspended)
4. **RDS failover** (Multi-AZ failover in progress)

#### Immediate Response (5 minutes)

**Step 1: Verify RDS Status**

```bash
# Check RDS instance status
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,AvailabilityZone]' \
  --output table \
  --region us-east-1
```

**Expected Output:**
- `stopped` → Proceed to Step 2
- `available` → False alarm, check network/credentials
- `starting` → RDS already starting, monitor progress
- `failing-over` → Multi-AZ failover, wait 5 minutes

**Step 2: Start RDS Instance**

```bash
# Start RDS instance
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
```

**Step 3: Monitor RDS Startup**

```bash
# Monitor status (refresh every 30 seconds)
watch -n 30 'aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query "DBInstances[0].[DBInstanceStatus,Endpoint.Address]" \
  --output table \
  --region us-east-1'

# RDS startup timeline:
# starting (0-2 min) → modifying (2-3 min) → available (3-5 min)
```

**Step 4: Verify Pod Recovery**

```bash
# Watch dependent service pods (refresh every 5 seconds)
watch -n 5 'kubectl get pods -A | grep -E "gitlab-webservice|keycloak|sonarqube|argocd-application-controller"'

# Expected recovery:
# - GitLab webservice: Init:2/3 → Running (30-60s after RDS available)
# - Keycloak: CrashLoopBackOff → Running (30-60s)
# - SonarQube: CrashLoopBackOff → Running (1-2min)
# - ArgoCD: Restarts stop, stable Running
```

**Step 5: Test Application Connectivity**

```bash
# Test GitLab (should return HTTP 200)
curl -I https://gitlab.staging.internal

# Test Keycloak (should return HTTP 200)
curl -I https://keycloak.staging.internal/auth/realms/platform

# Test SonarQube (should return HTTP 200)
curl -I https://sonarqube.staging.internal
```

#### Communication

**Slack Notification Template (#platform-alerts):**

```
🚨 INCIDENT: RDS PostgreSQL Stopped

Status: INVESTIGATING / MITIGATING / RESOLVED
RDS Instance: k8s-platform-prod-postgresql
Started At: <timestamp>
Impact: Platform-wide database outage (GitLab, Keycloak, SonarQube, ArgoCD)

Actions Taken:
- [ ] RDS instance started (ETA: 3-5 minutes)
- [ ] Monitoring pod recovery
- [ ] Verified application connectivity

ETA to Resolution: <X minutes>

On-Call Engineer: @<your-name>
```

#### Post-Incident Actions

1. **Identify root cause:**
   - Check CloudTrail for manual stop events
   - Review FinOps Lambda logs for auto-shutdown
   - Verify RDS protection status in DynamoDB

2. **Prevent recurrence:**
   - Add RDS to FinOps Lambda exclusion list
   - Update DynamoDB protection state: `PROTECTED`
   - Review RDS tags (ensure `FinOps=exclude`)

3. **Update monitoring:**
   - Verify CloudWatch alarm fired correctly
   - Test SNS email delivery
   - Check Prometheus alert fired

**Script: Enable RDS Protection**

```bash
# Run protection script (created in 2026-02-27 session)
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes
./scripts/finops/enable-protection.sh \
  --resource-type rds \
  --resource-id k8s-platform-prod-postgresql \
  --environment staging

# Verify protection
./scripts/finops/validate-node-protection.sh
```

---

### Platform-Wide Outage

**Alert:** `RDSPostgreSQLPlatformWideOutage` (Prometheus)
**Severity:** CRITICAL (P1)
**Response SLA:** 5 minutes

#### Symptoms

- **Prometheus Alert:** 2+ services failing database connections simultaneously
- GitLab webservice: Init:2/3 (Pending)
- Keycloak: CrashLoopBackOff
- SonarQube: CrashLoopBackOff
- ArgoCD: Frequent restarts

#### Diagnostic Decision Tree

```
START: Multiple services failing database connections
  ↓
Is RDS instance status = "stopped"?
  ├─ YES → Follow "RDS Instance Stopped" runbook (above)
  └─ NO → Continue to next check
      ↓
Is RDS instance status = "available"?
  ├─ NO (failing-over, modifying, etc.) → Wait 5 minutes, monitor RDS events
  └─ YES → Continue to next check
      ↓
Can EKS pods reach RDS endpoint (network test)?
  ├─ NO → Check security groups, NACLs, route tables
  └─ YES → Continue to next check
      ↓
Are database credentials valid (Secret rotation issue)?
  ├─ NO → Rollback Secret rotation, restart pods
  └─ YES → Escalate to database team (RDS internal issue)
```

#### Network Connectivity Test

```bash
# Test from temporary pod in EKS cluster
kubectl run -n default postgres-test --rm -it --image=postgres:16 --restart=Never -- \
  pg_isready -h k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com -p 5432

# Expected output:
# k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432 - accepting connections
```

**If connection fails (timeout):**

```bash
# Check RDS security group rules
aws ec2 describe-security-groups \
  --group-ids sg-0e9ceb3811de9e8c7 \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`]' \
  --region us-east-1

# Expected: Allow port 5432 from EKS security group
```

**If connection refused:**

```bash
# Check RDS events for failures
aws rds describe-events \
  --source-identifier k8s-platform-prod-postgresql \
  --source-type db-instance \
  --duration 60 \
  --region us-east-1
```

#### Escalation Path

| Time Elapsed | Action | Contact |
|--------------|--------|---------|
| 0-5 min | Self-service RDS restart | Platform SRE (on-call) |
| 5-15 min | Database team investigation | database-team@example.com |
| 15-30 min | AWS Support case (Premium Support) | AWS TAM |
| 30+ min | Leadership notification | CTO, VP Engineering |

---

### GitLab Connectivity

**Alert:** `GitLabRDSConnectivityFailure` (Prometheus)
**Severity:** CRITICAL (P1)
**Response SLA:** 5 minutes

#### Symptoms

- GitLab webservice pod stuck in Init:2/3 state for >5 minutes
- Pod phase: Pending
- Init container: `configure-secrets` waiting

#### Diagnostic Steps

**Step 1: Check GitLab Init Container Logs**

```bash
# Get failing pod name
GITLAB_POD=$(kubectl get pods -n staging-platform-gitlab -l app=webservice,component=webservice -o jsonpath='{.items[?(@.status.phase=="Pending")].metadata.name}' | head -1)

# Check init container logs
kubectl logs -n staging-platform-gitlab $GITLAB_POD -c configure-secrets --tail=50

# Look for errors:
# - "could not connect to server" → RDS stopped/unreachable
# - "password authentication failed" → Credential issue
# - "timeout" → Network issue
```

**Step 2: Verify RDS Status**

```bash
# Check if RDS is running
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text \
  --region us-east-1

# If stopped → Start RDS (see "RDS Instance Stopped" section)
```

**Step 3: Verify GitLab Database Secret**

```bash
# Get Secret data
kubectl get secret -n staging-platform-gitlab gitlab-postgresql-secret -o yaml

# Decode credentials
echo "<base64-password>" | base64 -d

# Test connection manually
kubectl run -n staging-platform-gitlab psql-test --rm -it --image=postgres:16 --restart=Never -- \
  psql -h k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com \
       -U gitlab \
       -d gitlabhq_production \
       -c "SELECT version();"
```

**Step 4: Force Pod Restart (After RDS Available)**

```bash
# Delete stuck pods to trigger recreation
kubectl delete pod -n staging-platform-gitlab -l app=webservice,component=webservice

# Monitor new pods
kubectl get pods -n staging-platform-gitlab -l app=webservice -w
```

#### Impact Assessment

**Services Affected:**
- GitLab web UI (unavailable)
- Git push/pull operations (failing)
- CI/CD pipelines (not starting)
- Merge requests (blocked)
- Container registry (degraded)

**Business Impact:**
- Development workflows blocked
- Deployments halted
- Code reviews paused

#### Recovery Validation

```bash
# Test GitLab web UI
curl -I https://gitlab.staging.internal
# Expected: HTTP/2 200

# Test Git operations
git clone https://gitlab.staging.internal/test/repo.git
# Expected: Successful clone

# Test CI/CD
# Trigger a pipeline in GitLab UI, verify it starts
```

---

### Keycloak Connectivity

**Alert:** `KeycloakRDSConnectivityFailure` (Prometheus)
**Severity:** CRITICAL (P1)
**Response SLA:** 5 minutes

#### Symptoms

- Keycloak pods in CrashLoopBackOff for >3 minutes
- SSO login failing across all services
- OIDC flows returning errors

#### Diagnostic Steps

**Step 1: Check Keycloak Pod Logs**

```bash
# Get crashing pod logs
kubectl logs -n staging-keycloak-system -l app=keycloak --tail=100 | grep -i "database\|connection\|sql"

# Common errors:
# - "Unable to connect to database" → RDS stopped/unreachable
# - "Connection refused" → Network/security group issue
# - "Authentication failed" → Credential issue
# - "Liquibase migration failed" → Schema version mismatch
```

**Step 2: Verify RDS Status**

```bash
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text \
  --region us-east-1

# If stopped → Start RDS
```

**Step 3: Verify Keycloak Database Secret**

```bash
# Check Secret
kubectl get secret -n staging-keycloak-system keycloak-db-secret -o yaml

# Test connection
kubectl run -n staging-keycloak-system psql-test --rm -it --image=postgres:16 --restart=Never -- \
  psql -h k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com \
       -U keycloak \
       -d keycloak \
       -c "SELECT count(*) FROM realm;"
```

**Step 4: Monitor Keycloak Recovery**

```bash
# Watch pod restart cycle
kubectl get pods -n staging-keycloak-system -l app=keycloak -w

# Recovery timeline:
# CrashLoopBackOff → Running (30-60s after RDS available)
# Keycloak startup: 20-30s (schema migration + cache warm-up)
```

#### Impact Assessment

**Services Affected (SSO Unavailable):**
- Grafana (cannot login)
- ArgoCD (cannot login)
- Harbor (cannot login)
- GitLab (OIDC login fails, local root works)
- Vault (OIDC auth method unavailable)
- SonarQube (SAML login fails)

**Business Impact:**
- Users cannot authenticate to any platform service
- New user onboarding blocked
- Password resets failing

#### Recovery Validation

```bash
# Test Keycloak health endpoint
curl https://keycloak.staging.internal/auth/realms/platform/.well-known/openid-configuration
# Expected: JSON configuration (HTTP 200)

# Test SSO login to Grafana
# 1. Open https://grafana.staging.internal
# 2. Click "Sign in with Keycloak"
# 3. Should redirect to Keycloak, authenticate, redirect back
```

---

## Warning Alerts

### High CPU

**Alert:** `staging-rds-high-cpu` (CloudWatch)
**Severity:** WARNING (P3)
**Response SLA:** 30 minutes

#### Symptoms

- CPU utilization >80% for 5 minutes (sustained)
- Application response times slower than normal
- Database query latency increasing

#### Diagnostic Steps

**Step 1: Identify Top Queries**

```bash
# Connect to RDS via bastion host or psql pod
kubectl run -n default psql-client --rm -it --image=postgres:16 --restart=Never -- \
  psql -h k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com \
       -U postgres_admin \
       -d platform

# Query: Top 10 queries by CPU time
SELECT
  pid,
  now() - pg_stat_activity.query_start AS duration,
  state,
  query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC
LIMIT 10;
```

**Step 2: Check for Lock Contention**

```sql
-- Check for blocked queries
SELECT
  blocked_locks.pid AS blocked_pid,
  blocking_locks.pid AS blocking_pid,
  blocked_activity.query AS blocked_query,
  blocking_activity.query AS blocking_query
FROM pg_locks blocked_locks
JOIN pg_stat_activity blocked_activity ON blocked_locks.pid = blocked_activity.pid
JOIN pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
JOIN pg_stat_activity blocking_activity ON blocking_locks.pid = blocking_activity.pid
WHERE NOT blocked_locks.granted;
```

**Step 3: Terminate Slow Queries (If Safe)**

```sql
-- Kill long-running query (CAUTION: verify it's safe to kill)
SELECT pg_terminate_backend(<pid>);
```

#### Resolution Actions

**Short-term:**
1. Terminate slow/stuck queries
2. Add missing indexes (if identified)
3. Review recent application deployments for N+1 query issues

**Long-term:**
1. Upgrade instance class: `db.t3.medium` → `db.t3.large` (2 vCPU → 2 vCPU + more credits)
2. Enable Performance Insights for query analysis
3. Implement query optimization (application-side)

---

### High Connections

**Alert:** `staging-rds-high-connections` (CloudWatch)
**Severity:** WARNING (P3)
**Response SLA:** 30 minutes

#### Symptoms

- Database connections >117 (80% of max_connections=147)
- New connection attempts slow or failing
- Application logs show connection pool exhaustion

#### Diagnostic Steps

**Step 1: Check Connection Distribution**

```sql
-- Count connections by database and application
SELECT
  datname,
  application_name,
  state,
  count(*)
FROM pg_stat_activity
GROUP BY datname, application_name, state
ORDER BY count DESC;
```

**Step 2: Identify Idle Connections**

```sql
-- Count idle connections by age
SELECT
  count(*) AS idle_count,
  application_name
FROM pg_stat_activity
WHERE state = 'idle'
  AND query_start < now() - interval '10 minutes'
GROUP BY application_name
ORDER BY idle_count DESC;
```

**Step 3: Kill Idle Connections (If Safe)**

```sql
-- Kill idle connections older than 10 minutes
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
  AND query_start < now() - interval '10 minutes'
  AND application_name != 'pg_dump';  -- Don't kill backups
```

#### Resolution Actions

**Short-term:**
1. Terminate idle connections
2. Identify applications with connection leaks
3. Restart leaky application pods

**Long-term:**
1. Implement connection pooling (PgBouncer)
2. Tune application connection pool settings
3. Review `max_connections` parameter (increase if needed)
4. Upgrade instance class if connection limit too low

---

### Low Storage

**Alert:** `staging-rds-low-storage` (CloudWatch)
**Severity:** WARNING (P3)
**Response SLA:** 4 hours

#### Symptoms

- Free storage space <20GB
- Database writes may start failing soon
- Transaction logs accumulating

#### Diagnostic Steps

**Step 1: Check Storage Breakdown**

```sql
-- Database sizes
SELECT
  datname,
  pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;

-- Largest tables
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;
```

**Step 2: Check for Bloat**

```sql
-- Table bloat (requires pg_stat_statements extension)
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS external_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
```

#### Resolution Actions

**Short-term:**
1. **Vacuum old data:**
   ```sql
   VACUUM ANALYZE;  -- Reclaim dead tuple space
   ```

2. **Delete old backups/logs (if applicable):**
   ```sql
   -- Example: Delete old audit logs older than 90 days
   DELETE FROM audit_logs WHERE created_at < now() - interval '90 days';
   ```

3. **Enable storage autoscaling:**
   ```bash
   aws rds modify-db-instance \
     --db-instance-identifier k8s-platform-prod-postgresql \
     --max-allocated-storage 200 \
     --apply-immediately \
     --region us-east-1
   ```

**Long-term:**
1. Implement data retention policies
2. Archive old data to S3 (pg_dump + compress + upload)
3. Partition large tables (time-series data)

---

### High Latency

**Alert:** `staging-rds-high-read-latency` / `staging-rds-high-write-latency` (CloudWatch)
**Severity:** WARNING (P3)
**Response SLA:** 1 hour

#### Symptoms

- Read/Write latency >50ms for 5 minutes
- Application response times degraded
- Users reporting slow page loads

#### Diagnostic Steps

**Step 1: Check I/O Metrics**

```bash
# CloudWatch: Check IOPS burst balance
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name BurstBalance \
  --dimensions Name=DBInstanceIdentifier,Value=k8s-platform-prod-postgresql \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-east-1

# Low burst balance (<20%) = IOPS throttling
```

**Step 2: Identify Slow Queries**

```sql
-- Requires pg_stat_statements extension
SELECT
  query,
  calls,
  total_time,
  mean_time,
  max_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 20;
```

#### Resolution Actions

**Short-term:**
1. Optimize slow queries (add indexes)
2. Reduce application query frequency (caching)
3. Wait for IOPS burst balance to recover

**Long-term:**
1. Migrate to Provisioned IOPS storage (io1/io2)
2. Upgrade instance class (better baseline IOPS)
3. Implement query result caching (Redis)

---

## Escalation Matrix

### Response Team

| Role | Responsibilities | Contact | Hours |
|------|-----------------|---------|-------|
| Platform SRE (On-Call) | First responder, RDS restarts, initial triage | #platform-alerts Slack | 24/7 |
| Database Team | Schema issues, performance tuning, backups | database-team@example.com | Business hours |
| Security Team | Credential rotation, Secret issues | security-team@example.com | Business hours |
| AWS Support | RDS infrastructure issues, hardware failures | AWS Premium Support case | 24/7 |

### Escalation Timeline

**CRITICAL Alerts (RDS Stopped, Platform Outage):**

| Time | Action |
|------|--------|
| T+0 | Platform SRE notified (Slack, email, PagerDuty) |
| T+5 min | If not resolved, page Database Team lead |
| T+15 min | If not resolved, open AWS Support case (Severity: Urgent) |
| T+30 min | Notify VP Engineering, CTO |
| T+1 hour | Activate disaster recovery plan (RDS failover to DR region) |

**WARNING Alerts (Performance Issues):**

| Time | Action |
|------|--------|
| T+0 | Platform SRE investigates (async, during business hours) |
| T+4 hours | If worsening, escalate to Database Team |
| T+1 day | If unresolved, schedule capacity planning meeting |

### Communication Channels

- **#platform-alerts** (Slack): Real-time incident updates
- **status.internal**: External status page for users
- **incidents@example.com**: Post-incident reports

---

## Post-Incident Actions

### Immediate (Within 1 hour of resolution)

1. **Update status page:**
   - Mark incident as RESOLVED
   - Provide summary of impact and resolution

2. **Clear alerts:**
   - Verify all CloudWatch alarms returned to OK state
   - Verify Prometheus alerts no longer firing

3. **Document timeline:**
   - Record incident start time, detection time, resolution time
   - Calculate MTTD (Mean Time To Detect), MTTR (Mean Time To Resolve)

### Short-term (Within 24 hours)

1. **Root cause analysis:**
   - Why did RDS stop? (FinOps automation, manual error, AWS issue)
   - Why didn't alerts fire earlier? (monitoring gap)
   - Why was recovery delayed? (process gap, knowledge gap)

2. **Prevent recurrence:**
   - Add RDS to FinOps exclusion list (if FinOps-related)
   - Update runbooks with new learnings
   - Improve monitoring (add missing alerts)

3. **Communication:**
   - Send incident report to stakeholders
   - Thank responders in team channel

### Long-term (Within 1 week)

1. **Post-mortem meeting:**
   - Invite: Platform SRE, Database Team, affected service owners
   - Agenda: Timeline review, root cause, action items
   - Output: Postmortem document with action owners

2. **Action items:**
   - Example: "Enable Multi-AZ for RDS to prevent single-point-of-failure"
   - Example: "Implement automated RDS protection tagging"
   - Example: "Add RDS connectivity health checks to GitLab Helm chart"

3. **Update documentation:**
   - Update this runbook with new procedures
   - Update architecture diagrams
   - Update training materials

### Metrics to Track

- **MTTD** (Mean Time To Detect): Time from incident start to alert firing
  - Target: <2 minutes for CRITICAL alerts

- **MTTR** (Mean Time To Resolve): Time from alert to full service restoration
  - Target: <15 minutes for RDS stopped incidents

- **Incident Frequency**: Number of RDS-related incidents per month
  - Target: <1 CRITICAL incident/month

---

## Additional Resources

### Documentation

- **ADR-089**: RDS Availability Monitoring (decision rationale)
- **Terraform Module**: `platform-provisioning/.../modules/rds-monitoring/`
- **Grafana Dashboard**: https://grafana.staging.internal/d/rds-monitoring
- **AWS Console**: https://console.aws.amazon.com/rds/home?region=us-east-1#database:id=k8s-platform-prod-postgresql

### Scripts

- **Enable RDS Protection**: `scripts/finops/enable-protection.sh`
- **Validate Protection**: `scripts/finops/validate-node-protection.sh`
- **RDS Health Check**: (TODO: create automated health check script)

### Training

- AWS RDS Operations: https://docs.aws.amazon.com/rds/
- PostgreSQL Administration: https://www.postgresql.org/docs/16/admin.html
- Prometheus Alerting: https://prometheus.io/docs/alerting/

---

**Document Control:**

- **Version History:**
  - v1.0 (2026-02-27): Initial version (comprehensive RDS monitoring)
- **Review Cycle:** Quarterly (or after every major incident)
- **Next Review:** 2026-05-27
