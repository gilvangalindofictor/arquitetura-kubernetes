# ADR-088: RDS PostgreSQL Scheduler Automation for Staging Cost Optimization

## Status
**Proposed** (2026-02-27)

## Context

### Current Situation

The staging environment runs a PostgreSQL RDS instance (`k8s-platform-prod-postgresql`) 24/7 to support development and testing activities. This results in:

- **Cost:** ~R$ 300/month (~R$ 3,600/year) for RDS compute running continuously
- **Utilization:** Staging is primarily used during business hours (8 AM - 6 PM BRT, Mon-Fri)
- **Waste:** RDS runs ~118 hours/week (70% of time) when not needed (nights, weekends, holidays)

### Business Requirements

1. **Cost Optimization:** FinOps mandate to reduce staging costs by 40-60%
2. **Availability During Business Hours:** Developers need access 8 AM - 6 PM BRT, Mon-Fri
3. **Weekend Access:** Optional on-demand access for critical work
4. **Service Dependencies:** GitLab, Keycloak, SonarQube, ArgoCD all require PostgreSQL

### Technical Constraints

- **RDS Start/Stop Limitations:**
  - RDS can be stopped for maximum 7 days (AWS auto-starts after 7 days)
  - Start operation takes 5-10 minutes
  - Stop operation takes 2-5 minutes
  - No automated start/stop built into AWS RDS (requires Lambda/EventBridge)

- **Dependent Services Impact:**
  - GitLab webservice enters `Init:2/3` state (waiting for DB)
  - Keycloak pods enter `CrashLoopBackOff`
  - SonarQube web server health checks fail
  - ArgoCD API server degraded (no session persistence)

- **Recovery Time:**
  - Total downtime when starting: ~10-15 minutes (RDS start + pod restarts)

### Current FinOps Automation

We have existing FinOps Lambda automation (`finops-automation` module) that:
- ✅ Scales EKS node groups (start/stop) on business hours schedule
- ✅ Includes circuit breaker protection (DynamoDB state tracking)
- ✅ Sends SNS notifications for operations
- ✅ Has monitoring (CloudWatch alarms, logs)
- ⚠️ **RDS start/stop code exists in Lambda functions BUT is not actively configured**

**Key Finding:** The `lambda_start.py` and `lambda_stop.py` already have RDS start/stop logic:
- Reads `RDS_INSTANCE_ID` environment variable
- Calls `rds.start_db_instance()` / `rds.stop_db_instance()`
- Handles RDS status transitions (`stopped` → `starting` → `available`)
- **Issue:** Variable is currently empty/not configured in Terraform

## Decision

**We will enable RDS start/stop automation by configuring the existing FinOps Lambda functions to manage the staging RDS instance.**

### Implementation Strategy

1. **Configuration (No New Module Required):**
   - Update existing `finops-automation` module instantiation in `environments/staging/`
   - Set `rds_instance_id = "k8s-platform-prod-postgresql"` in Terraform variables
   - Lambda functions already have IAM permissions for RDS operations

2. **Schedule (Reuse Existing EventBridge Rules):**
   - **Start:** 8:00 AM BRT (11:00 UTC) Mon-Fri → Lambda already triggered
   - **Stop:** 6:00 PM BRT (21:00 UTC) Mon-Fri → Lambda already triggered
   - **Weekend:** Stopped (Saturday 12:00 AM BRT / 3:00 AM UTC) → Lambda already triggered

3. **Safety Mechanisms (Already Implemented):**
   - ✅ Circuit breaker (DynamoDB): Opens after 3 consecutive failures
   - ✅ SNS notifications: Success/failure alerts to ops team
   - ✅ CloudWatch alarms: Startup duration, Lambda errors
   - ✅ Manual override: AWS CLI commands for emergency start/stop

4. **Validation & Testing:**
   - Create comprehensive runbook (`docs/runbooks/rds-start-stop-operations.md`)
   - Create validation script (`scripts/finops/validate-rds-scheduler.sh`)
   - Test manual Lambda invocation (dry-run → actual)
   - Monitor first week: Validate recovery times, cost savings

5. **Rollback Plan:**
   - Disable EventBridge rules via AWS Console (instant)
   - Update Terraform: `enable_automation = false`
   - Start RDS manually if stopped

### Cost Model

| Scenario | Uptime Hours/Month | Monthly Cost (BRL) | Annual Savings (BRL) |
|----------|-------------------|-------------------|---------------------|
| **Baseline (24/7)** | 730 | R$ 300 | - |
| **Business Hours Only** | ~217 (50h/week) | R$ 89 | **R$ 2,532** |
| **Current Manual** | ~500 (inconsistent) | R$ 205 | R$ 1,140 |

**Projected Savings:** R$ 211/month → **R$ 2,532/year**

**ROI:**
- Implementation effort: ~4 hours (configuration + testing)
- Payback period: Immediate (configuration-only, no new development)

### Dependencies Impact

| Service | Impact When RDS Stopped | Mitigation |
|---------|------------------------|-----------|
| **GitLab** | Webservice unavailable (Init containers timeout) | Acceptable for staging (not production) |
| **Keycloak** | Authentication unavailable | Developers use local accounts during outage |
| **SonarQube** | Code analysis unavailable | Queue scans until RDS available |
| **ArgoCD** | Degraded (metadata unavailable) | GitOps syncs continue (uses cluster-local state) |

**Key Insight:** All impacts are acceptable for staging environment. No production services affected.

## Alternatives Considered

### Alternative 1: Manual Start/Stop (Current State)
**Pros:**
- No automation complexity
- Full manual control

**Cons:**
- ❌ Inconsistent (often forgotten)
- ❌ Only ~50% cost reduction achieved
- ❌ Requires daily manual intervention
- ❌ No monitoring/alerting

**Verdict:** Rejected (not scalable, low savings)

### Alternative 2: AWS Instance Scheduler (Third-Party Solution)
**Pros:**
- AWS-managed solution
- Pre-built UI for scheduling

**Cons:**
- ❌ Additional cost (~$15/month)
- ❌ Duplicates existing FinOps automation
- ❌ No integration with circuit breaker
- ❌ Requires separate CloudFormation stack

**Verdict:** Rejected (over-engineered, cost overhead)

### Alternative 3: Separate RDS Scheduler Module
**Pros:**
- Clean separation of concerns
- Reusable for other environments

**Cons:**
- ❌ Unnecessary duplication (Lambda, DynamoDB, SNS)
- ❌ Higher maintenance burden
- ❌ Existing code already handles RDS

**Verdict:** Rejected (violates DRY principle)

### Alternative 4: RDS Reserved Instance
**Pros:**
- ~40% discount for 1-year commitment

**Cons:**
- ❌ Requires 24/7 usage to recoup cost
- ❌ No flexibility for staging environment
- ❌ Only ~R$ 1,080/year savings (vs R$ 2,532 with automation)

**Verdict:** Rejected (better for production, not staging)

## Consequences

### Positive

1. **Cost Savings:**
   - Immediate: R$ 211/month (~R$ 2,532/year)
   - Combined with EKS node automation: Total R$ 4,800/year staging savings

2. **No New Infrastructure:**
   - Reuse existing Lambda functions, DynamoDB table, SNS topics
   - Configuration change only (1 variable in Terraform)

3. **Operational Benefits:**
   - Automated (no daily manual work)
   - Monitored (CloudWatch alarms, SNS notifications)
   - Safe (circuit breaker prevents failure loops)

4. **Environmental Impact:**
   - Reduce idle compute by 70% (nights + weekends)
   - Align with corporate sustainability goals

### Negative

1. **Service Availability:**
   - Staging unavailable outside business hours (expected)
   - 10-15 minute recovery time when RDS starts (acceptable)

2. **Manual Override Required:**
   - Weekend/evening work requires manual RDS start
   - Adds 10 min delay for emergency debugging

3. **Monitoring Overhead:**
   - Ops team must monitor circuit breaker state
   - Weekly review of Lambda execution logs

4. **Testing Limitations:**
   - Integration tests cannot run outside business hours
   - CI/CD pipelines must schedule around availability

### Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| **RDS fails to start** | Staging unavailable for business day | Circuit breaker opens after 3 failures → manual intervention + SNS alert |
| **Lambda timeout** | Automation skipped | CloudWatch alarm → PagerDuty escalation |
| **Developer needs weekend access** | Productivity blocked | Runbook provides manual start procedure (5 min) |
| **AWS 7-day auto-start** | Unexpected cost if long holiday | EventBridge stops RDS daily (prevents auto-start) |
| **Dependent pods don't recover** | Services unavailable after RDS start | Runbook troubleshooting section + pod restart procedures |

## Implementation Checklist

### Phase 1: Documentation (Completed 2026-02-27)
- [x] Create ADR-088 (this document)
- [x] Create runbook: `docs/runbooks/rds-start-stop-operations.md`
- [x] Create validation script: `scripts/finops/validate-rds-scheduler.sh`

### Phase 2: Terraform Configuration (Pending)
- [ ] Update `environments/staging/main.tf`: Set `rds_instance_id = "k8s-platform-prod-postgresql"`
- [ ] Verify IAM permissions in `modules/finops-automation/iam.tf` (already includes RDS actions)
- [ ] Run `terraform plan` → validate no destructive changes
- [ ] Run `terraform apply` → Lambda environment variables updated

### Phase 3: Testing (Pending)
- [ ] Run validation script: `./scripts/finops/validate-rds-scheduler.sh --validate`
- [ ] Test manual Lambda invocation: `--test-start` (dry-run first)
- [ ] Test manual Lambda invocation: `--test-stop` (dry-run first)
- [ ] Verify SNS notifications delivered
- [ ] Check DynamoDB state table after test run
- [ ] Validate pod recovery after RDS start (GitLab, Keycloak, SonarQube, ArgoCD)

### Phase 4: Pilot (1 Week Monitoring)
- [ ] Enable automation: `enable_automation = true` in Terraform
- [ ] Monitor first business week (5 scheduled starts/stops)
- [ ] Track CloudWatch Lambda execution metrics
- [ ] Review circuit breaker state daily
- [ ] Measure actual vs projected savings (Cost Explorer)

### Phase 5: Production Rollout (After Pilot Success)
- [ ] Document lessons learned in runbook
- [ ] Update FinOps savings tracking in MEMORY.md
- [ ] Set up Grafana dashboard for RDS uptime/cost tracking
- [ ] Schedule monthly cost review meetings
- [ ] Announce to dev team: Staging availability hours

## Validation Criteria

**Success Metrics (After 1 Month):**
1. ✅ RDS uptime: ≤250 hours/month (target: 217 hours)
2. ✅ Cost: ≤R$ 120/month (target: R$ 89)
3. ✅ Availability: 100% during business hours (8 AM - 6 PM BRT, Mon-Fri)
4. ✅ Circuit breaker: Zero OPEN states (no automation failures)
5. ✅ Manual overrides: ≤4/month (acceptable for occasional weekend work)

**Failure Conditions (Rollback Triggers):**
1. ❌ Circuit breaker opens >2 times/month
2. ❌ RDS fails to start during business hours >1 time/month
3. ❌ Developer productivity significantly impacted (feedback from team)
4. ❌ Cost savings <R$ 150/month (not meeting 50% target)

## References

- **FinOps Module:** `platform-provisioning/aws/kubernetes/terraform/modules/finops-automation/`
- **Lambda Functions:** `modules/finops-automation/lambda/lambda_start.py`, `lambda_stop.py`
- **Runbook:** `docs/runbooks/rds-start-stop-operations.md`
- **Validation Script:** `scripts/finops/validate-rds-scheduler.sh`
- **Cost Analysis:** Marco 2 FinOps Savings Validation (2026-01-30)
- **AWS Documentation:** [Working with Amazon RDS DB instances](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_StartStop.html)

## Review & Approval

| Role | Name | Status | Date |
|------|------|--------|------|
| **Author** | FinOps Automation Team | Proposed | 2026-02-27 |
| **Reviewer** | DevOps Lead | Pending | - |
| **Approver** | Infrastructure Manager | Pending | - |

**Review Date:** 2026-03-27 (30 days after implementation)
**Next Review:** 2026-06-27 (quarterly)

---

**Document Version:** 1.0
**Last Updated:** 2026-02-27
**Classification:** Internal - FinOps Optimization
