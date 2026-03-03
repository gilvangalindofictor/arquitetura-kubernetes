# Next Actions - 2026-02-27

**Updated**: 2026-02-27 02:20 BRT
**Status**: 4/4 Actions Complete, Ready for Deployment
**Previous Session**: SESSION-SUMMARY-2026-02-27.md

---

## ✅ Completed This Session

| Action | Status | Deliverables |
|--------|--------|--------------|
| AÇÃO-004: DaemonSets Kyverno | ✅ | 100% compliance (20/20 pods labeled) |
| AÇÃO-005: Terraform modules labels | ✅ | 258 lines, 5 files (ready for apply) |
| AÇÃO-006: Velero drift detection | ✅ | 790 lines, GitLab CI + K8s CronJob |
| AÇÃO-007: WAF dashboard & alerts | ✅ | 1,390 lines, dashboard + 3 alerts + runbook |

---

## 🎯 Immediate Next Steps (When Environment Online)

### 1. Apply Terraform Changes (AÇÃO-005)

**Priority**: HIGH
**Duration**: ~10 minutes
**Impact**: Corporate labels on Loki StatefulSets, OpenTelemetry, Tempo

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging

# Plan (verify changes)
terraform plan \
  -target=module.kube_prometheus_stack_staging \
  -target=module.loki

# Expected changes:
# - kube-prometheus-stack: 27 set blocks with corporate labels
# - loki: 34 set blocks with corporate labels
# - Pods will restart with new labels

# Apply
terraform apply \
  -target=module.kube_prometheus_stack_staging \
  -target=module.loki

# Verify 100% compliance
kubectl get pods -n staging-observability-monitoring -o json | \
  jq '[.items[] | select(.metadata.labels.domain == "operations")] | length'
# Expected: 49/49 (100%)
```

**Post-Apply Validation**:
- [ ] Loki backend StatefulSet pods restarted with labels
- [ ] OpenTelemetry pods have domain/owner/environment labels
- [ ] Tempo pods have domain/owner/environment labels
- [ ] Kyverno compliance: 100% (49/49 pods)
- [ ] No pod restarts failures (check Events)

---

### 2. Deploy WAF Dashboard & Alerts (AÇÃO-007)

**Priority**: MEDIUM
**Duration**: ~5 minutes
**Impact**: WAF observability automation, security monitoring

```bash
# Deploy dashboard ConfigMap
kubectl apply -f domains/observability/infra/grafana/waf-dashboard-configmap.yaml

# Deploy PrometheusRule alerts
kubectl apply -f domains/observability/infra/prometheus/waf-prometheus-rules.yaml

# Verify Grafana dashboard imported (sidecar auto-import ~60s)
kubectl logs -n staging-observability-monitoring \
  -l app.kubernetes.io/name=grafana \
  -c grafana-sc-dashboard | grep "waf-security-dashboard"

# Verify PrometheusRule active
kubectl get prometheusrule -n staging-observability-monitoring waf-security-alerts
```

**Post-Deploy Validation**:
- [ ] Dashboard visible in Grafana UI: `/d/waf-security-dashboard`
- [ ] CloudWatch datasource configured (may need manual setup)
- [ ] 3 alerts active in Alertmanager: WAFHighBlockRate, WAFGeoBlockSpike, WAFSQLInjectionAttempts
- [ ] Alert routing to Slack configured (#security-incidents, #platform-alerts)

**CloudWatch Datasource Setup** (if not configured):
1. Grafana UI → Configuration → Data Sources → Add CloudWatch
2. Authentication: Access & Secret Key OR IAM Role (IRSA)
3. Default Region: us-east-1
4. Test connection → Save

---

### 3. Test Velero Drift Detection (AÇÃO-006)

**Priority**: LOW
**Duration**: ~15 minutes
**Impact**: Validate drift detection automation

**GitLab CI Test** (manual trigger):
```bash
# Navigate to GitLab pipeline for domains/security/velero
# Trigger job: velero:drift:pre-deploy (manual)
# Check artifact: drift-report.json (7-day retention)
# Expected: exit 0 (no drift) OR exit 1 (drift detected) with details
```

**K8s CronJob Test** (wait for scheduled run):
```bash
# CronJob schedule: 0 2 * * * (2 AM UTC daily)
# Next run: Check CronJob status
kubectl get cronjob -n velero velero-drift-detection

# View last job logs
kubectl logs -n velero \
  $(kubectl get pods -n velero -l job-name -o jsonpath='{.items[0].metadata.name}')

# Check Slack notifications (#platform-alerts or configured channel)
```

**Post-Test Validation**:
- [ ] GitLab CI job runs successfully (exit 0 or 1)
- [ ] Drift report JSON artifact generated
- [ ] K8s CronJob runs on schedule (2 AM UTC)
- [ ] Slack notifications received on drift detected
- [ ] Runbook `docs/runbooks/velero-cicd-drift-detection.md` accurate

---

## 📋 Short-Term Actions (Next 7 Days)

### WAF Monitoring

**Goal**: Establish WAF baseline metrics, test alerts

1. **Baseline Metrics** (Day 1-3)
   - Monitor WAF dashboard for 3 days
   - Record baseline: AllowedRequests/min, BlockedRequests/min, Block Rate %
   - Identify false positives (legitimate traffic blocked)

2. **Alert Testing** (Day 4-5)
   - Test `WAFHighBlockRate` alert: Simulate >15% block rate (curl flood?)
   - Test `WAFGeoBlockSpike` alert: Verify geo-blocking from CN/RU/KP
   - Test `WAFSQLInjectionAttempts` alert: Simulate SQLi payload (safe test env)

3. **Runbook Validation** (Day 6-7)
   - Walk through `docs/runbooks/waf-incident-response.md` procedures
   - Verify CLI commands work (aws cloudwatch get-metric-statistics)
   - Update runbook with any corrections

### Kyverno Enforcement

**Goal**: Transition from audit to enforce mode

1. **Monitor Audit Mode** (Day 1-7)
   - Check Kyverno logs for policy violations
   - Verify 100% compliance maintained (49/49 pods)
   - Document any new workloads created without labels

2. **Enforcement Transition** (Day 8+)
   - Update Kyverno ClusterPolicy: validationFailureAction: enforce
   - Test pod creation rejection (create pod without labels)
   - Document enforcement results

### CI/CD Enhancement Deployment

**Goal**: Deploy CICD-001 to CICD-005 artifacts (from 2026-02-26 session)

**Sequence** (when environment ligar):
- **Phase 1 (Week 1-2)**: CICD-001 (SAST/DAST) + CICD-004 (Immutable Tags) parallel → CICD-002 (Quality Gate) after 001
- **Phase 2 (Week 3-4)**: CICD-003 (Secret Rotation) independent
- **Phase 3 (Week 5-6)**: CICD-005 (Argo Rollouts) after apps instrumented

**Detailed deployment guides**:
- CICD-001: `docs/logbook/2026-02-26-cicd-001-sast-dast-deployment.md`
- CICD-002: `docs/logbook/2026-02-26-cicd-002-quality-gate-deployment.md`
- CICD-003: `docs/deployments/cicd-003-secret-rotation-deployment-guide.md`
- CICD-004: `docs/logbook/2026-02-26-cicd-004-immutable-tags-deployment.md`
- CICD-005: `docs/logbook/2026-02-26-cicd-005-argo-rollouts-deployment.md`

---

## 🔄 Long-Term Actions (Next 30 Days)

### 1. GAP-010 WAF Production Rollout

**Prerequisites**:
- Staging WAF dashboard validated (7 days baseline)
- Alert thresholds tuned (no false positives)
- SOC team trained on incident response runbook

**Actions**:
1. Create production WAF module in Terraform
2. Deploy WAF to production ALB
3. Enable S3 logging (production traffic volume)
4. Configure CloudWatch Logs Insights queries
5. Train SOC on `docs/runbooks/waf-incident-response.md`

**Estimated Effort**: 16-20 hours
**Timeline**: Week 3-4 after staging validation

### 2. GAP-011 Linkerd Service Mesh (Blocked)

**Status**: BLOCKED - staging environment down (2026-02-26)
**Blocker**: System resources (Linkerd control plane requires ~2GB RAM)

**Unblock Path**:
1. Wait for environment online
2. Review `docs/adr/adr-086-linkerd-service-mesh-mtls.md`
3. Follow `docs/runbooks/gap011-linkerd-deployment-quickstart.md`

**Estimated Effort**: 24-32 hours
**Timeline**: TBD (waiting for environment)

### 3. GAP-012 DR Multi-Region (Technical Analysis Complete)

**Status**: Analysis complete, awaiting business decision
**Artifacts**:
- `docs/logbook/2026-02-26-gap012-dr-multi-region-technical-analysis.md`
- `docs/runbooks/dr-multi-region-failover.md`
- `modules/rds-replica/` (Terraform module ready)

**Business Decision Required**:
- Budget approval: ~R$ 15-20K/year (RDS replica + cross-region data transfer)
- RTO/RPO targets: Define acceptable downtime/data loss
- Compliance requirements: Data residency, audit trails

**Technical Readiness**: 90% (only requires module deployment)
**Timeline**: Awaiting business approval

### 4. VPA FASE 0 Baseline Validation (7-Day Window)

**Status**: In progress (10 workloads with updateMode:Off)
**Goal**: Validate VPA recommendations before enabling updateMode:Auto

**Day 7 Validation Checklist**:
- [ ] Review VPA recommendations for 10 workloads
- [ ] Calculate projected savings (target: R$ 15-17K/year)
- [ ] Identify over-provisioned workloads (>50% CPU/memory unused)
- [ ] Test updateMode:Auto on 1 non-critical workload
- [ ] Document savings in MEMORY.md

**Timeline**: Complete by 2026-03-06 (7 days from 2026-02-27)

---

## 📊 Metrics & Savings Tracking

### Current Savings (as of 2026-02-27)

| Category | Savings/Year | Status |
|----------|--------------|--------|
| EKS 1.34 (Extended Support avoided) | R$ 25.920 | ✅ Realized |
| FinOps FASE 2 Automation | R$ 13.596,89 | ✅ Realized |
| FinOps PDB Optimization | R$ 4.405 | ✅ Realized |
| FinOps Automation Lambda | R$ 3.744 | ✅ Realized |
| Orphan cleanup | R$ 2.106 | ✅ Realized |
| Other (ALBs, RDS, EBS, etc.) | R$ 6.653 | ✅ Realized |
| **VPA FASE 0 (projected)** | **R$ 15-17K** | **⏳ Pending** |
| **TOTAL Realized** | **R$ 56.424/year** | **90% roadmap** |

### Projected Savings (Next 30 Days)

| Initiative | Estimated Savings | Timeline |
|------------|-------------------|----------|
| VPA FASE 0 validation | R$ 15-17K/year | 2026-03-06 (7 days) |
| WAF optimization (rate limit tuning) | R$ 1-2K/year | 2026-03-15 (2 weeks) |
| Kyverno enforce mode (prevent over-provisioned pods) | R$ 3-5K/year | 2026-03-20 (3 weeks) |

---

## 🚨 Known Issues & Blockers

### 1. System Node Group FinOps Automation — ✅ RESOLVIDO (2026-02-28)

**Issue**: System node group scaled to 0 by FinOps automation (discovered 2026-02-27)
**Impact**: 15 monitoring pods Pending/Unschedulable
**Resolution**: ✅ COMPLETO (2026-02-28) — Lambda protection deployed and tested manually.
- Lambda `finops_start` + `finops_stop`: `EXCLUDED_NODE_GROUPS=system,critical`
- `terraform apply`: 2 added, 3 changed, 0 destroyed
- Logbook: `docs/logbook/2026-02-27-finops-lambda-deploy.md`

### 2. Staging Environment Down (2026-02-26) — ✅ RESOLVIDO (2026-03-02)

**Issue**: Environment offline preventing GAP-011 Linkerd deployment
**Impact**: All deployment/testing blocked
**Status**: ✅ RESOLVIDO — Ambiente online desde 2026-03-02. GAP-011 Linkerd DEPLOYED (2026-03-03).

### 3. CloudWatch Datasource for WAF Dashboard

**Issue**: CloudWatch datasource may not be configured in Grafana
**Impact**: WAF dashboard shows "No data" until datasource added
**Resolution**: Manual Grafana configuration required (see Step 2 above)

---

## 📝 Documentation Updates Needed

### High Priority

1. **Update demands-backlog.md**: Mark AÇÃO-004 to 007 as COMPLETE
2. **Update MEMORY.md**: Add Session 2026-02-27 summary (✅ DONE)
3. **Create ADR-087**: Velero drift detection automation (GitLab CI + K8s CronJob)
4. **Create ADR-088**: WAF security monitoring (dashboard + alerts + runbook)

### Medium Priority

1. **Update gaps-execution-roadmap.md**: Mark GAP-010 as "Observability Complete" (dashboard + alerts)
2. **Create Kyverno enforcement guide**: Transition from audit to enforce mode
3. **Update FinOps exclusion rules**: Document system node group protection

---

## 🎯 Success Criteria (Next 7 Days)

### Must Have
- [ ] Terraform apply AÇÃO-005: 100% Kyverno compliance (49/49 pods)
- [ ] WAF dashboard deployed and accessible in Grafana
- [ ] PrometheusRule alerts active (3 alerts)
- [ ] VPA FASE 0: 7-day validation complete, savings calculated

### Should Have
- [ ] Velero drift detection tested (GitLab CI + CronJob)
- [ ] WAF baseline metrics recorded (3 days)
- [ ] CloudWatch datasource configured in Grafana
- [ ] FinOps Lambda exclusion rules updated (system node group)

### Nice to Have
- [ ] WAF alert testing complete (all 3 alerts triggered)
- [ ] Kyverno enforcement mode planning started
- [ ] CI/CD Enhancement Phase 1 deployment planning (CICD-001, 004, 002)

---

**Next Session**: Focus on deployment validation and WAF monitoring baseline

**Updated By**: Claude Sonnet 4.5 (Session 2026-02-27)
