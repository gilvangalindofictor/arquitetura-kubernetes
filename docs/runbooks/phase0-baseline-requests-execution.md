# PHASE 0: Baseline Resource Requests Execution Runbook

**Status:** Ready for Execution
**Owner:** SRE Team
**Last Updated:** 2026-02-20
**Estimated Duration:** 6-8 hours (including monitoring)
**Risk Level:** MEDIUM (Zero downtime target, rollback automation available)

---

## Objective

Apply VPA lowerBound recommendations as baseline resource requests for 11 critical workloads to prevent pod evictions and OOMKilled events while maintaining zero downtime.

## Prerequisites

### Required Access
- [x] kubectl access to staging cluster (EKS 1.34)
- [x] Terraform access to staging environment
- [x] AWS CLI configured with k8s-platform-staging profile
- [x] Alertmanager access for silence configuration
- [x] Emergency contacts available

### Required Tools
```bash
# Verify tools installed
kubectl version --client
terraform version
aws --version
jq --version
curl --version
```

### Scripts Location
- Pre-check: `/tmp/phase0-pre-check.sh`
- Monitor: `/tmp/phase0-monitor.sh`
- Health checks: `/tmp/phase0-health-checks.sh`

---

## Execution Waves

### Wave 1: Low-Risk Observability Stack (30min monitoring each)
**Rationale:** Start with non-critical services that have health endpoints

1. **Loki Write** (`monitoring/loki-write`)
2. **Tempo Distributor** (`monitoring/tempo-distributor`)
3. **Grafana** (`monitoring/grafana`)

### Wave 2: Data Services (60min monitoring each)
**Rationale:** Backend services with minimal user-facing impact

4. **Redis** (`data-services/redis`)
5. **RabbitMQ** (`data-services/rabbitmq`)

### Wave 3: Platform Core (120min monitoring each)
**Rationale:** Critical platform services requiring extended monitoring

6. **Vault** (`vault-system/vault`)
7. **Keycloak** (`keycloak/keycloak`)
8. **Harbor Core** (`harbor-system/harbor-core`)

### Wave 4: CI/CD & Monitoring Critical (240min monitoring each)
**Rationale:** Most critical services - full 4h observation window

9. **GitLab WebService** (`gitlab-staging/gitlab-webservice`)
10. **GitLab Sidekiq** (`gitlab-staging/gitlab-sidekiq`)
11. **Prometheus** (`monitoring/prometheus`)
12. **ArgoCD Server** (`argocd/argocd-server`)

---

## Pre-Execution Checklist

### 1. Run Pre-Check Script
```bash
/tmp/phase0-pre-check.sh
```

**Expected Output:**
```
✓ CLUSTER READY FOR PHASE 0 EXECUTION
```

**If warnings appear:** Review and document before proceeding
**If errors appear:** STOP - fix errors before continuing

### 2. Create Terraform State Backup
```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/environments/staging

# Backup created automatically by pre-check script
# Manual backup if needed:
terraform state pull > /tmp/phase0-tfstate-backup-$(date +%Y%m%d-%H%M%S).json
```

### 3. Configure Alertmanager Silence (4-hour window)
```bash
# Get Alertmanager pod
AM_POD=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')

# Create silence
kubectl exec -n monitoring $AM_POD -c alertmanager -- amtool silence add \
  alertname=~".+" \
  --duration=4h \
  --comment="PHASE 0 VPA baseline apply - planned maintenance" \
  --author="sre-team@example.com"

# Verify silence
kubectl exec -n monitoring $AM_POD -c alertmanager -- amtool silence query
```

### 4. Notify Stakeholders
```bash
# Slack/Teams notification template
Subject: PHASE 0 Execution - Baseline Resource Requests
Duration: 6-8 hours
Impact: None expected (zero downtime target)
Rollback: Automated triggers configured
Status updates: Every 2 hours
```

### 5. Verify VPA Recommendations Snapshot
```bash
kubectl get vpa -A -o json > /tmp/vpa-snapshot-$(date +%Y%m%d-%H%M%S).json
```

---

## Execution Procedure (Per Workload)

### Step 1: Identify Target Workload
```bash
# Example: Loki Write
NAMESPACE="monitoring"
RESOURCE_TYPE="statefulset"  # or "deployment"
RESOURCE_NAME="loki-write"
MONITOR_DURATION=30  # minutes (adjust per wave)
```

### Step 2: Get Current State
```bash
# Capture current resource configuration
kubectl get $RESOURCE_TYPE $RESOURCE_NAME -n $NAMESPACE -o yaml > \
  /tmp/phase0-backup-${NAMESPACE}-${RESOURCE_NAME}-$(date +%Y%m%d-%H%M%S).yaml

# Get VPA recommendation
kubectl get vpa $RESOURCE_NAME -n $NAMESPACE -o yaml
```

### Step 3: Calculate Baseline Requests
```bash
# Extract lowerBound from VPA
LOWER_CPU=$(kubectl get vpa $RESOURCE_NAME -n $NAMESPACE \
  -o jsonpath='{.status.recommendation.containerRecommendations[0].lowerBound.cpu}')

LOWER_MEM=$(kubectl get vpa $RESOURCE_NAME -n $NAMESPACE \
  -o jsonpath='{.status.recommendation.containerRecommendations[0].lowerBound.memory}')

echo "Baseline Requests: CPU=$LOWER_CPU, MEM=$LOWER_MEM"
```

### Step 4: Update Terraform Configuration
```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/environments/staging

# Edit appropriate .tf file (e.g., monitoring.tf, data-services.tf, etc.)
# Add resources.requests block with lowerBound values

# Example for Loki:
# resources:
#   requests:
#     cpu: "500m"      # from VPA lowerBound
#     memory: "1Gi"    # from VPA lowerBound
```

### Step 5: Terraform Plan & Review
```bash
# Set credentials
eval $(aws configure export-credentials --profile k8s-platform-staging --format env)
unset AWS_PROFILE && export AWS_DEFAULT_REGION=us-east-1

# Plan
terraform plan -out=/tmp/phase0-plan-${RESOURCE_NAME}.tfplan

# Review changes - should only show resource requests addition
# Verify NO other changes are included
```

### Step 6: Apply & Start Monitoring
```bash
# Apply in one terminal
terraform apply /tmp/phase0-plan-${RESOURCE_NAME}.tfplan

# Start monitoring in parallel terminal (IMMEDIATELY after apply)
/tmp/phase0-monitor.sh $NAMESPACE $RESOURCE_TYPE $RESOURCE_NAME $MONITOR_DURATION
```

### Step 7: Monitor Output Interpretation

**Success Indicators:**
```
[✓] No new container restarts
[✓] Pods: Running=X, Pending=0, Failed=0
[✓] Service health: OK
[✓] No OOMKilled events
Progress: [████████████████████] 100% (30/30 min)
✓ MONITORING COMPLETED SUCCESSFULLY
```

**Failure Indicators (Auto-Rollback):**
```
[✗] CrashLoopBackOff detected
[✗] OOMKilled event detected
[✗] Pod not Ready for >5min
[✗] Service health check failed 3 times consecutively
✗ ROLLBACK REQUIRED
```

### Step 8: Rollback Procedure (if monitoring script exits 1)
```bash
# Restore from backup
kubectl apply -f /tmp/phase0-backup-${NAMESPACE}-${RESOURCE_NAME}-*.yaml

# OR revert Terraform
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/environments/staging
git diff HEAD -- *.tf  # Review changes
git checkout -- *.tf   # Revert uncommitted changes

# Re-apply previous state
terraform apply

# Verify rollback
/tmp/phase0-health-checks.sh
```

### Step 9: Success Validation
```bash
# Run full health check
/tmp/phase0-health-checks.sh

# Verify resource requests applied
kubectl get $RESOURCE_TYPE $RESOURCE_NAME -n $NAMESPACE \
  -o jsonpath='{.spec.template.spec.containers[0].resources.requests}'

# Verify pods stable
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$RESOURCE_NAME
```

### Step 10: Proceed to Next Workload
- Document results in execution log
- Wait minimum 15 minutes between workloads
- Repeat Steps 1-9 for next workload in wave

---

## Auto-Rollback Decision Matrix

| Condition | Detection Time | Severity | Action | Trigger Location |
|-----------|---------------|----------|--------|------------------|
| CrashLoopBackOff | Immediate | CRITICAL | Rollback immediately | Monitor script |
| OOMKilled event | Immediate | CRITICAL | Rollback immediately | Monitor script |
| Pod not Ready >5min | 5 minutes | HIGH | Rollback after 5min | Monitor script |
| Service health fail >3min | 3 minutes | HIGH | Rollback after 3min | Monitor script |
| CPU throttle >10% | 2 minutes | MEDIUM | Alert only, no rollback | Monitor script |
| Restart count >0 | 2 minutes | LOW | Log and monitor | Monitor script |

---

## Emergency Contacts

| Role | Contact | Availability |
|------|---------|--------------|
| SRE Lead | @sre-lead | 24/7 on-call |
| Platform Architect | @platform-arch | Business hours |
| DevOps Team | #devops-oncall | 24/7 Slack channel |
| AWS Support | Enterprise Support | 24/7 phone |

---

## Success Criteria

### Per-Workload Success
- [x] Monitoring completed without auto-rollback trigger
- [x] No OOMKilled events during observation window
- [x] Zero container restarts
- [x] Service health checks passing
- [x] Resource usage within expected bounds
- [x] No new firing Prometheus alerts

### PHASE 0 Overall Success
- [x] 11/11 workloads successfully updated
- [x] Zero downtime incidents
- [x] All services healthy post-execution
- [x] Terraform state consistent
- [x] Documentation updated with actual applied values

---

## Post-Execution Tasks

### 1. Remove Alertmanager Silences
```bash
AM_POD=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}')

# List active silences
kubectl exec -n monitoring $AM_POD -c alertmanager -- amtool silence query

# Expire silence
kubectl exec -n monitoring $AM_POD -c alertmanager -- amtool silence expire <silence-id>
```

### 2. Update Documentation
```bash
# Update MEMORY.md with actual applied values
# Path: /home/gilvangalindo/.claude/projects/-home-gilvangalindo-projects-Arquitetura-Kubernetes/memory/MEMORY.md

# Add to PHASE 0 section:
# - Applied values per workload
# - Observation results
# - Any deviations from plan
# - Lessons learned
```

### 3. Git Commit
```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/environments/staging

git add *.tf
git commit -m "feat(capacity): PHASE 0 baseline resource requests applied

Applied VPA lowerBound as baseline requests for 11 workloads:
- Wave 1 (observability): loki-write, tempo-distributor, grafana
- Wave 2 (data services): redis, rabbitmq
- Wave 3 (platform): vault, keycloak, harbor-core
- Wave 4 (critical): gitlab-webservice, gitlab-sidekiq, prometheus, argocd-server

Monitoring: Zero downtime, no rollbacks triggered
Savings impact: TBD after 30d VPA re-collection

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin main
```

### 4. Start VPA Re-Collection Period
```bash
# VPA will collect new metrics with updated requests
# Wait 30 days before PHASE 1 (conservative rightsizing)
# Mark in calendar: Next review date = 2026-03-22
```

### 5. Stakeholder Notification
```bash
# Send completion notification
Subject: PHASE 0 Complete - Baseline Resource Requests Applied
Status: SUCCESS
Workloads updated: 11/11
Downtime: 0 minutes
Rollbacks: 0
Next phase: PHASE 1 (30 days - 2026-03-22)
```

---

## Lessons Learned Template

### What Went Well
-

### What Could Be Improved
-

### Action Items
-

---

## Reference Links

- VPA Recommendations Snapshot: `/tmp/vpa-snapshot-*.json`
- Terraform Backups: `/tmp/phase0-terraform-backup-*/`
- Execution Logs: `/tmp/phase0-execution-log-*.txt`
- Rollback Configs: `/tmp/phase0-backup-*.yaml`

---

## Appendix A: Wave Timing Breakdown

| Wave | Workloads | Monitor/Workload | Total Time |
|------|-----------|------------------|------------|
| 1 | 3 | 30 min | 1.5 hours |
| 2 | 2 | 60 min | 2 hours |
| 3 | 3 | 120 min | 6 hours |
| 4 | 4 | 240 min | 16 hours |

**Total Sequential:** 25.5 hours
**Optimized (parallel within waves):** 6-8 hours

---

## Appendix B: Terraform Files by Workload

| Workload | Namespace | TF File | Resource Type |
|----------|-----------|---------|---------------|
| loki-write | monitoring | `monitoring.tf` | StatefulSet |
| tempo-distributor | monitoring | `monitoring.tf` | Deployment |
| grafana | monitoring | `monitoring.tf` | Deployment |
| redis | data-services | `data-services.tf` | StatefulSet |
| rabbitmq | data-services | `data-services.tf` | StatefulSet |
| vault | vault-system | `vault.tf` | StatefulSet |
| keycloak | keycloak | `keycloak.tf` | StatefulSet |
| harbor-core | harbor-system | `harbor.tf` | Deployment |
| gitlab-webservice | gitlab-staging | `gitlab.tf` | Deployment |
| gitlab-sidekiq | gitlab-staging | `gitlab.tf` | Deployment |
| prometheus | monitoring | `monitoring.tf` | StatefulSet |
| argocd-server | argocd | `argocd.tf` | Deployment |

---

## Appendix C: Expected VPA LowerBound Ranges (Reference)

Based on 30-day observation (from MEMORY.md):

| Workload | Expected CPU | Expected Memory |
|----------|--------------|-----------------|
| vault | ~200m | ~512Mi |
| keycloak | ~300m | ~768Mi |
| gitlab-webservice | ~500m | ~1.5Gi |
| gitlab-sidekiq | ~300m | ~1Gi |
| harbor-core | ~250m | ~512Mi |
| argocd-server | ~200m | ~384Mi |
| prometheus | ~1000m | ~4Gi |
| grafana | ~150m | ~256Mi |
| loki-write | ~500m | ~1Gi |
| tempo-distributor | ~300m | ~512Mi |
| rabbitmq | ~400m | ~1Gi |
| redis | ~200m | ~256Mi |

**Note:** Actual values may vary - ALWAYS use current VPA recommendations from cluster.

---

**Document Version:** 1.0
**Next Review:** After PHASE 0 completion
**Approval:** SRE Lead signature required before execution
