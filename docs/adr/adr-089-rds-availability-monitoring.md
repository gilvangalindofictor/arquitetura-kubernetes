# ADR-089: RDS Availability Monitoring

**Status:** Accepted
**Date:** 2026-02-27
**Decision Makers:** Platform SRE Team
**Context:** GitLab webservice stuck in Init:2/3 state when RDS stopped without alerting

---

## Context

### Problem Statement

**Incident:** GitLab webservice pods were stuck in Init:2/3 state, blocking all CI/CD operations. Investigation revealed the root cause was RDS PostgreSQL instance stopped (likely by FinOps automation), but **no monitoring alerts fired**.

**Impact:**
- Platform-wide database outage (silent)
- GitLab CI/CD unavailable (4+ hours)
- Keycloak SSO unavailable (authentication blocked)
- SonarQube code scans unavailable
- ArgoCD GitOps sync delayed

**Root Cause Analysis:**
1. RDS instance was stopped (manual or FinOps Lambda)
2. No CloudWatch alarms configured for RDS instance state
3. No Prometheus alerts for application-level database connectivity
4. GitLab Helm chart does not include database health checks in init containers

**Business Risk:**
- Silent database outages can persist for hours undetected
- Development workflows blocked during outages
- No proactive alerting before resource exhaustion (connections, storage, CPU)

### Current State (Before ADR)

**Monitoring Gaps:**
- ✗ No alerts when RDS instance stops
- ✗ No alerts for RDS performance issues (CPU, connections, storage)
- ✗ No alerts for application-level database connectivity failures
- ✗ No unified dashboard showing RDS health + dependent services
- ✓ Basic data-services alerts exist (PostgreSQL exporter metrics) but don't detect RDS stopped state

**Existing Monitoring:**
- `domains/observability/infra/alerts/data-services-alerts.yaml`: PostgreSQL connection pool, slow queries, PostgreSQL down (exporter-based)
- PostgreSQL exporter scraping RDS metrics (only works when RDS is running)
- Grafana dashboards for PostgreSQL performance (but no RDS availability panel)

**Why Existing Monitoring Failed:**
- PostgreSQL exporter cannot scrape metrics when RDS is stopped → no alert
- Prometheus `pg_up` metric goes stale/absent instead of firing `PostgreSQLDown` alert
- No CloudWatch-based monitoring (RDS instance-level state)

---

## Decision

We will implement **multi-layer monitoring** for RDS PostgreSQL availability combining:

1. **CloudWatch Alarms** (AWS native, RDS instance-level)
2. **Prometheus Alerts** (K8s native, application-level)
3. **Grafana Dashboard** (unified observability)

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1: CloudWatch Alarms (Direct RDS Monitoring)             │
│                                                                 │
│  RDS Instance (k8s-platform-prod-postgresql)                    │
│      ↓ CloudWatch Metrics (AWS API)                             │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Alarms:                                                   │  │
│  │ - RDS Instance Stopped (DatabaseConnections = 0)         │  │
│  │ - High CPU (>80% for 5min)                               │  │
│  │ - High Connections (>117/147)                            │  │
│  │ - Low Storage (<20GB)                                    │  │
│  │ - High Read/Write Latency (>50ms)                        │  │
│  └──────────────────────────────────────────────────────────┘  │
│      ↓ SNS Topic (staging-rds-alerts)                           │
│  Email / Slack / PagerDuty                                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Layer 2: Prometheus Alerts (App-Level Connectivity)            │
│                                                                 │
│  Kubernetes Pods (GitLab, Keycloak, SonarQube, ArgoCD)         │
│      ↓ kube-state-metrics (Pod status)                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Alerts:                                                   │  │
│  │ - GitLabRDSConnectivityFailure (Init >5min)              │  │
│  │ - KeycloakRDSConnectivityFailure (CrashLoop >3min)       │  │
│  │ - SonarQubeRDSConnectivityFailure (CrashLoop >5min)      │  │
│  │ - RDSPostgreSQLPlatformWideOutage (2+ services failing)  │  │
│  │ - PostgreSQLExporterDown (monitoring gap)                │  │
│  └──────────────────────────────────────────────────────────┘  │
│      ↓ Alertmanager                                             │
│  Slack / Email                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Layer 3: Grafana Dashboard (Unified Observability)             │
│                                                                 │
│  Data Sources: CloudWatch + Prometheus                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Panels:                                                   │  │
│  │ - RDS Status (running/stopped)                           │  │
│  │ - Database Connections (current vs max)                  │  │
│  │ - CPU/Storage Utilization                                │  │
│  │ - Read/Write Latency                                     │  │
│  │ - GitLab/Keycloak/SonarQube Health                       │  │
│  │ - Active Alerts                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│  Auto-refresh: 30s | Links: AWS Console, Runbook              │
└─────────────────────────────────────────────────────────────────┘
```

### Components

#### 1. Terraform Module: `rds-monitoring`

**Location:** `platform-provisioning/aws/kubernetes/terraform/modules/rds-monitoring/`

**Resources:**
- `aws_sns_topic`: Notification topic for RDS alerts
- `aws_sns_topic_subscription`: Email subscriptions (expandable to Slack, PagerDuty)
- `aws_cloudwatch_metric_alarm` (6 alarms):
  - `staging-rds-instance-stopped` (CRITICAL)
  - `staging-rds-high-cpu` (WARNING)
  - `staging-rds-high-connections` (WARNING)
  - `staging-rds-low-storage` (WARNING)
  - `staging-rds-high-read-latency` (WARNING)
  - `staging-rds-high-write-latency` (WARNING)
- `aws_db_event_subscription`: RDS lifecycle events (start, stop, failover, backup)

**Key Features:**
- **Instance Stopped Detection:** `treat_missing_data = "breaching"` ensures alarm fires even when no metrics
- **Configurable Thresholds:** Variables for CPU, connections, storage, latency
- **Cost Optimization:** Within AWS Free Tier (10 alarms free)
- **Integration Ready:** SNS topic ARN output for third-party integrations

**Usage:**

```hcl
module "rds_monitoring_staging" {
  source = "../../modules/rds-monitoring"

  environment             = "staging"
  rds_instance_identifier = "k8s-platform-prod-postgresql"
  alert_emails            = ["devops@example.com"]

  enable_performance_alerts = true
  cpu_threshold            = 80
  max_connections_override = 147  # db.t3.medium
  storage_threshold_gb     = 20
  latency_threshold_ms     = 50

  tags = local.common_tags
}
```

#### 2. Prometheus Alerts: `rds-connectivity-alerts.yaml`

**Location:** `domains/observability/infra/alerts/rds-connectivity-alerts.yaml`

**PrometheusRule CRD:**
- `GitLabRDSConnectivityFailure`: GitLab webservice Init >5min (CRITICAL)
- `KeycloakRDSConnectivityFailure`: Keycloak CrashLoopBackOff >3min (CRITICAL)
- `SonarQubeRDSConnectivityFailure`: SonarQube CrashLoopBackOff >5min (WARNING)
- `ArgoCDRDSConnectivityIssue`: ArgoCD controller restarts ≥3 in 10min (WARNING)
- `RDSPostgreSQLPlatformWideOutage`: 2+ services failing (CRITICAL, pager=true)
- `PostgreSQLExporterDown`: Metrics scraping failing (WARNING)

**Key Features:**
- Detects application-level failures (pod state watching)
- Complementary to CloudWatch (catches network/credential issues)
- Rich alert descriptions with runbook links and remediation steps
- Severity levels: CRITICAL (immediate), WARNING (proactive)

**Deployment:**

```bash
kubectl apply -f domains/observability/infra/alerts/rds-connectivity-alerts.yaml
```

#### 3. Grafana Dashboard: `rds-monitoring-dashboard-configmap.yaml`

**Location:** `domains/observability/infra/grafana/rds-monitoring-dashboard-configmap.yaml`

**Dashboard Panels:**
1. RDS Status (Stat): Running/Stopped indicator
2. Database Connections (Time series): Current vs max (147)
3. Current Connections (Gauge): Visual threshold display
4. GitLab Health (Stat): Healthy/Failing based on pod state
5. CPU Utilization (Time series): 0-100% with 80% threshold
6. Free Storage (Time series): Bytes remaining, 20GB threshold
7. Read/Write Latency (Time series): Dual metric, 50ms threshold
8. Active Alerts (Table): RDS-related Prometheus alerts

**Data Sources:**
- CloudWatch: RDS metrics (CPU, connections, storage, latency)
- Prometheus: Pod health, alerts

**Features:**
- Auto-refresh: 30 seconds
- Alert annotations on graphs
- Direct links: AWS Console, runbook
- GitOps deployment: `grafana_dashboard: "1"` label for auto-import

**Deployment:**

```bash
kubectl apply -f domains/observability/infra/grafana/rds-monitoring-dashboard-configmap.yaml
```

#### 4. Runbook: `rds-monitoring-alerts-response.md`

**Location:** `docs/runbooks/rds-monitoring-alerts-response.md`

**Sections:**
- Critical alerts: RDS stopped, platform outage, GitLab/Keycloak connectivity
- Warning alerts: High CPU, connections, storage, latency
- Diagnostic decision trees
- Step-by-step remediation procedures
- Escalation matrix (5min → Database Team → AWS Support)
- Post-incident actions

**Key Procedures:**
- **RDS Stopped Response:** 5-minute SLA (verify status → start instance → verify pod recovery)
- **Network Connectivity Test:** kubectl run postgres-test with pg_isready
- **Force Pod Restart:** Delete stuck pods after RDS recovery

---

## Rationale

### Why Multi-Layer Monitoring?

**CloudWatch Alone (Insufficient):**
- ✓ Detects RDS instance-level issues (stopped, hardware failure)
- ✗ Cannot detect application-level issues (network, credentials, DNS)
- ✗ Requires AWS console access for investigation
- ✗ Not integrated with K8s-native workflows

**Prometheus Alone (Insufficient):**
- ✓ Detects application-level issues (pod failures, connectivity)
- ✗ Cannot detect RDS instance stopped (exporter cannot scrape)
- ✗ Delayed detection (waits for pod to fail, 5+ minutes)
- ✗ Indirect RDS status (inferred from pod state)

**Multi-Layer (Comprehensive):**
- ✓ Detects both RDS instance-level AND application-level issues
- ✓ Faster detection (CloudWatch alarms fire immediately when RDS stops)
- ✓ Root cause clarity (distinguish between RDS stopped vs network issue)
- ✓ Integrated with existing workflows (Prometheus/Grafana for K8s, CloudWatch for AWS)

### Design Decisions

#### 1. SNS Topic Instead of Direct Slack Integration

**Decision:** Use SNS topic + email subscriptions (expandable to Slack/PagerDuty)

**Rationale:**
- SNS provides abstraction layer (change notification targets without Terraform changes)
- Email subscriptions work immediately (no Slack app configuration required)
- SNS → Slack integration can be added later via AWS Chatbot
- Cost-effective (1,000 free emails/month)

**Alternative Considered:** Direct CloudWatch → Slack (Lambda)
- Rejected: Additional Lambda maintenance, cost, complexity

#### 2. Threshold Values

| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| CPU | 80% for 5min | db.t3.medium has burstable CPU, 80% sustained indicates resource pressure |
| Connections | 117 (80% of 147) | Leave 20% headroom before max_connections rejection |
| Storage | 20GB | 20% of 100GB allocated storage, time to act before full |
| Latency | 50ms | PostgreSQL on gp3 EBS should have <10ms, 50ms indicates IOPS throttling |

**Rationale:**
- Conservative thresholds to avoid false positives
- 5-minute evaluation for transient spike filtering
- Aligned with SRE best practices (80/20 rule for resource headroom)

#### 3. Alert Severity Levels

**CRITICAL (Immediate Response, 5-minute SLA):**
- RDS instance stopped
- Platform-wide outage (2+ services failing)
- GitLab connectivity failure (blocks CI/CD)
- Keycloak connectivity failure (blocks SSO)

**WARNING (Proactive Response, 30-minute SLA):**
- High CPU, connections, storage, latency
- SonarQube connectivity failure (non-blocking)
- ArgoCD connectivity issues (GitOps delayed)

**Rationale:**
- Severity based on business impact (user-facing vs internal)
- SLA based on time-to-outage (immediate vs preventive)

#### 4. No Auto-Remediation (Manual Response Required)

**Decision:** Alerts notify humans, no automated RDS restart

**Rationale:**
- **Safety:** Auto-restarting RDS without understanding root cause could mask issues
- **Investigation:** Need to determine why RDS stopped (FinOps, billing, failure)
- **Accountability:** Manual response ensures incident is tracked and learned from
- **Cost Control:** Prevent infinite restart loops if underlying issue persists

**Alternative Considered:** Lambda auto-remediation (detect stopped → start RDS)
- Rejected: Risk of masking systemic issues, no incident learning

#### 5. RDS Event Subscription

**Decision:** Include RDS event subscription in addition to metric alarms

**Rationale:**
- CloudWatch alarms are metric-based (poll every 1-5 minutes)
- RDS events are real-time (instance start, stop, failover, backup)
- Events provide additional context (maintenance windows, automatic backups)
- No additional cost (RDS event subscriptions are free)

**Events Monitored:**
- Availability: start, stop, failover, reboot
- Failure: instance failure, storage failure
- Maintenance: scheduled maintenance start/complete
- Backup: automated backup start/complete

---

## Consequences

### Benefits

**Operational:**
- ✅ **Immediate Outage Detection:** CloudWatch alarms fire within 1 minute when RDS stops
- ✅ **Root Cause Clarity:** Distinguish between RDS stopped vs network vs credentials
- ✅ **Proactive Alerts:** Warn before resource exhaustion (CPU, connections, storage)
- ✅ **Unified Observability:** Single Grafana dashboard for RDS + dependent services
- ✅ **Incident Response:** Comprehensive runbook with 5-minute response SLA

**Business:**
- ✅ **Reduced MTTR:** Mean Time To Resolve drops from 4+ hours to <15 minutes (target)
- ✅ **Reduced MTTD:** Mean Time To Detect drops from hours to <2 minutes
- ✅ **Cost Avoidance:** Prevent extended outages (lost developer productivity)
- ✅ **Compliance:** SRE monitoring requirements met (availability, performance)

**Cost:**
- ✅ **Free Tier:** 6 CloudWatch alarms (within 10 free), SNS emails <1,000/month
- ✅ **No Infrastructure:** No additional Lambda, EC2, or third-party tools
- ✅ **Estimated Monthly Cost:** $0.00 (within AWS Free Tier)

### Drawbacks

**Complexity:**
- ⚠️ **Multiple Systems:** Requires understanding of CloudWatch + Prometheus + Grafana
- ⚠️ **Email Fatigue:** Warning alerts may be noisy if thresholds too sensitive
- ⚠️ **Manual Response:** Requires on-call engineer to respond (no auto-remediation)

**Mitigations:**
- Comprehensive runbook with step-by-step procedures
- Tunable thresholds (adjust based on actual workload patterns)
- Alertmanager silences during planned maintenance
- Consider PagerDuty integration for on-call rotation management

**Maintenance:**
- ⚠️ **Threshold Tuning:** May need adjustment after initial deployment (reduce false positives)
- ⚠️ **Runbook Updates:** Must update after each incident with new learnings
- ⚠️ **Email List Management:** Add/remove recipients as team changes

**Mitigations:**
- Quarterly review of alert history (identify false positives)
- Post-incident reviews always update runbook
- Terraform-managed email subscriptions (GitOps process)

### Risks

**Risk 1: Alert Fatigue (Warning Alerts Too Noisy)**
- **Likelihood:** Medium
- **Impact:** Low (ignoring warnings, missing real issues)
- **Mitigation:** Start conservative (80% thresholds), tune down if needed, use Alertmanager silences

**Risk 2: Email Delivery Failure (SNS Subscription Unconfirmed)**
- **Likelihood:** High (first deployment)
- **Impact:** High (no notifications)
- **Mitigation:** Test email delivery during deployment, require confirmation tracking

**Risk 3: CloudWatch Alarm Doesn't Fire (Misconfiguration)**
- **Likelihood:** Low
- **Impact:** Critical (silent outage)
- **Mitigation:** Manual testing (trigger test alarm), quarterly alarm verification

**Risk 4: Prometheus Alerts False Positives (Pod Restarts During Deploy)**
- **Likelihood:** Medium
- **Impact:** Low (unnecessary pages)
- **Mitigation:** `for: 5m` evaluation period, Alertmanager inhibition rules

---

## Implementation Plan

### Phase 1: Terraform Module Deployment (Week 1)

**Tasks:**
1. Review Terraform module code: `modules/rds-monitoring/`
2. Configure staging environment: `environments/staging/rds-monitoring.tf`
3. Add alert email to `terraform.tfvars`
4. Run `terraform plan` to preview changes
5. Run `terraform apply` to deploy CloudWatch alarms + SNS topic
6. **Confirm SNS email subscriptions** (critical step!)
7. Test alarm firing (manual trigger)

**Validation:**
```bash
# Verify alarms created
aws cloudwatch describe-alarms --alarm-name-prefix staging-rds --region us-east-1

# Verify SNS topic
aws sns list-subscriptions-by-topic --topic-arn <sns-topic-arn> --region us-east-1

# Test email delivery
aws cloudwatch set-alarm-state \
  --alarm-name staging-rds-instance-stopped \
  --state-value ALARM \
  --state-reason "Test notification delivery" \
  --region us-east-1
```

### Phase 2: Prometheus Alerts Deployment (Week 1)

**Tasks:**
1. Review Prometheus alerts: `rds-connectivity-alerts.yaml`
2. Deploy to cluster: `kubectl apply -f ...`
3. Verify PrometheusRule loaded: `kubectl get prometheusrules -n staging-observability-monitoring`
4. Check Prometheus UI for rule errors
5. Test alert firing (create test pod stuck in Init)

**Validation:**
```bash
# Check PrometheusRule
kubectl get prometheusrules -n staging-observability-monitoring rds-connectivity-alerts -o yaml

# Access Prometheus UI
kubectl port-forward -n staging-observability-monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Navigate to: http://localhost:9090/alerts
# Search: GitLabRDSConnectivityFailure
```

### Phase 3: Grafana Dashboard Deployment (Week 1)

**Tasks:**
1. Review dashboard ConfigMap: `rds-monitoring-dashboard-configmap.yaml`
2. Deploy ConfigMap: `kubectl apply -f ...`
3. Verify Grafana auto-imported dashboard (label `grafana_dashboard: "1"`)
4. Configure CloudWatch datasource in Grafana (if not exists)
5. Test dashboard panels loading data

**Validation:**
```bash
# Check ConfigMap deployed
kubectl get configmap -n staging-observability-monitoring rds-monitoring-dashboard

# Access Grafana
kubectl port-forward -n staging-observability-monitoring svc/kube-prometheus-stack-grafana 3000:80
# Navigate to: http://localhost:3000/dashboards
# Search: "RDS PostgreSQL Monitoring"
```

### Phase 4: Runbook Distribution (Week 1)

**Tasks:**
1. Review runbook: `docs/runbooks/rds-monitoring-alerts-response.md`
2. Update runbook URLs with actual GitHub org/repo
3. Add runbook to team wiki
4. Conduct runbook walkthrough with on-call team
5. Add runbook link to on-call playbook

### Phase 5: Testing & Validation (Week 2)

**Chaos Engineering Test:**

```bash
# Test 1: Stop RDS (controlled outage)
aws rds stop-db-instance --db-instance-identifier k8s-platform-prod-postgresql --region us-east-1

# Expected:
# - CloudWatch alarm fires within 1 minute
# - Email notification received
# - Prometheus alerts fire after 3-5 minutes (pods fail)
# - Grafana dashboard shows "STOPPED"

# Recovery:
aws rds start-db-instance --db-instance-identifier k8s-platform-prod-postgresql --region us-east-1

# Expected:
# - RDS startup: 3-5 minutes
# - CloudWatch alarm clears
# - Pods recover to Running
# - Prometheus alerts clear
```

**Load Test:**

```bash
# Test 2: High Connections Alert
# Use pgbench to simulate connection surge
# Expected: staging-rds-high-connections alert fires at 117 connections
```

### Phase 6: Production Rollout (Week 3-4)

**Tasks:**
1. Duplicate module for production environment
2. Adjust thresholds for production workload (if needed)
3. Configure production email list
4. Deploy CloudWatch alarms + Prometheus alerts + Grafana dashboard
5. Test notification delivery
6. Update production runbook

---

## Alternatives Considered

### Alternative 1: Prometheus-Only Monitoring (Rejected)

**Approach:**
- Deploy postgres-exporter sidecar to scrape RDS metrics
- Use Prometheus blackbox-exporter to probe RDS port 5432
- Alert based on probe failures

**Pros:**
- Single monitoring system (Prometheus)
- K8s-native (no CloudWatch)
- Free (no AWS costs)

**Cons:**
- ❌ **Cannot detect RDS stopped** (exporter cannot scrape when RDS down)
- ❌ **Network dependency** (probe fails if K8s cluster has network issues)
- ❌ **Delayed detection** (scrape interval 30s-1min vs CloudWatch 1min)
- ❌ **No RDS lifecycle events** (start, stop, failover, maintenance)

**Decision:** Rejected. Prometheus-only monitoring has the same blind spot that caused the original incident (cannot detect RDS stopped state).

### Alternative 2: Third-Party APM (Rejected)

**Approach:**
- Use Datadog, New Relic, or Dynatrace for RDS monitoring
- Unified observability platform

**Pros:**
- All-in-one solution (metrics, logs, traces)
- Pre-built dashboards and alerts
- 24/7 monitoring from external network

**Cons:**
- ❌ **High cost** ($100-500/month per host)
- ❌ **Vendor lock-in** (proprietary agents, dashboards)
- ❌ **Data residency** (metrics sent to third-party SaaS)
- ❌ **Redundant** (already have Prometheus + Grafana)

**Decision:** Rejected. Cost and vendor lock-in not justified when CloudWatch + Prometheus can achieve same outcome.

### Alternative 3: AWS CloudWatch Synthetics (Rejected)

**Approach:**
- Use CloudWatch Synthetics canary to test database connectivity
- Run canary every 1 minute from Lambda

**Pros:**
- Proactive monitoring (simulates user workflow)
- External monitoring (detects network partition)

**Cons:**
- ❌ **High cost** ($0.0012/canary run = $52/month for 1-min interval)
- ❌ **Complex setup** (Lambda, VPC peering, IAM roles)
- ❌ **Limited value** (CloudWatch alarms + Prometheus already cover connectivity)

**Decision:** Rejected. Cost and complexity not justified for marginal benefit.

### Alternative 4: Auto-Remediation Lambda (Rejected)

**Approach:**
- CloudWatch alarm triggers Lambda function
- Lambda automatically starts RDS instance

**Pros:**
- Zero human intervention
- Fastest possible recovery (1-2 minutes)

**Cons:**
- ❌ **Masks root cause** (why did RDS stop? FinOps? Billing? Failure?)
- ❌ **No incident tracking** (auto-remediation bypasses incident process)
- ❌ **Risk of loops** (if underlying issue persists, infinite restarts)
- ❌ **Cost risk** (accidental restarts during maintenance)

**Decision:** Rejected. Manual response preferred for incident learning and root cause analysis.

---

## Related Documents

- **Runbook:** `docs/runbooks/rds-monitoring-alerts-response.md`
- **Terraform Module:** `platform-provisioning/.../modules/rds-monitoring/`
- **Prometheus Alerts:** `domains/observability/infra/alerts/rds-connectivity-alerts.yaml`
- **Grafana Dashboard:** `domains/observability/infra/grafana/rds-monitoring-dashboard-configmap.yaml`
- **ADR-050:** Shared Data Services (RDS) between Staging and Production
- **ADR-060:** PostgreSQL Governance Standards

---

## Appendix: Cost Analysis

### CloudWatch Costs

**CloudWatch Alarms:**
- First 10 alarms: Free (AWS Free Tier)
- Additional alarms: $0.10/alarm/month
- **This ADR:** 6 alarms = $0.00/month (within free tier)

**SNS Topics:**
- First 1,000 email notifications: Free
- Additional emails: $2.00 per 100,000 emails
- **Expected volume:** ~50 emails/month (alerts + OK notifications) = $0.00/month

**RDS Event Subscriptions:**
- Free (no additional cost)

**CloudWatch Metrics:**
- RDS metrics provided by AWS at no additional cost

**Total CloudWatch Cost:** $0.00/month

### Prometheus Costs

**Infrastructure:**
- Prometheus already deployed (kube-prometheus-stack)
- No additional CPU/memory resources required
- Alert evaluation overhead: <1% CPU

**Storage:**
- Alert rules: ~50KB (negligible)

**Total Prometheus Cost:** $0.00/month

### Grafana Costs

**Infrastructure:**
- Grafana already deployed (kube-prometheus-stack)
- Dashboard ConfigMap: 100KB (negligible)

**Total Grafana Cost:** $0.00/month

### Operational Costs

**On-Call Engineer Time:**
- Expected incident frequency: <1 CRITICAL/month (target)
- Average incident response time: 15 minutes
- Fully loaded engineer cost: $100/hour
- **Estimated cost:** $25/month (15min × $100/hr)

**Incident Impact Avoidance:**
- Previous outage duration: 4 hours (without monitoring)
- New outage duration: 15 minutes (with monitoring)
- **Time saved:** 3.75 hours
- Blocked developer hours (10 developers × 3.75 hours): 37.5 hours
- **Cost avoided:** $3,750/incident (37.5 hours × $100/hour)

**ROI:**
- **Investment:** $0.00/month (infrastructure) + $25/month (operational)
- **Benefit:** $3,750/incident avoided
- **Payback:** Immediate (first avoided incident covers 150 months of operational cost)

---

## Metrics & Success Criteria

### Key Performance Indicators (KPIs)

| Metric | Baseline (Before ADR) | Target (After ADR) | Measurement |
|--------|----------------------|-------------------|-------------|
| **MTTD** (Mean Time To Detect) | 4+ hours | <2 minutes | CloudWatch alarm timestamp - incident start |
| **MTTR** (Mean Time To Resolve) | 4+ hours | <15 minutes | Resolution timestamp - detection timestamp |
| **Incident Frequency** | Unknown | <1 CRITICAL/month | Count of RDS-related P1 incidents |
| **Alert Accuracy** | N/A | >90% (true positives) | True alarms / Total alarms |
| **False Positive Rate** | N/A | <10% | False alarms / Total alarms |

### Success Criteria (90 Days Post-Deployment)

- ✅ Zero silent RDS outages (all outages detected within 2 minutes)
- ✅ 100% of CRITICAL alerts have runbook procedures executed
- ✅ >80% of WARNING alerts result in proactive remediation (before CRITICAL)
- ✅ CloudWatch alarm false positive rate <10%
- ✅ Prometheus alert false positive rate <20%
- ✅ Grafana dashboard used in >90% of RDS-related incidents
- ✅ Post-incident survey: >80% of responders find runbook helpful

### Review Cadence

- **Weekly (Week 1-4):** Monitor alert volume, tune thresholds, update runbook
- **Monthly (Month 1-3):** Review incident metrics (MTTD, MTTR, false positives)
- **Quarterly:** Full ADR review, cost analysis, architecture improvements

---

**Document Control:**

- **Version:** 1.0
- **Authors:** Platform SRE Team
- **Reviewers:** Database Team, Security Team
- **Approved:** 2026-02-27
- **Next Review:** 2026-05-27 (Quarterly)
