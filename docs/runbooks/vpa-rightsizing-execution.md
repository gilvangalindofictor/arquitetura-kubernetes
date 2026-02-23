# VPA Rightsizing Execution Runbook

**Version:** 1.0
**Date:** 2026-02-20
**Environment:** EKS 1.34 Staging
**Target Savings:** R$ 19.118,50/year
**Execution Start:** 2026-03-18+ (após 30 dias VPA data collection)

---

## 📊 Executive Summary

This runbook provides a **phased, risk-mitigated approach** to applying VPA (Vertical Pod Autoscaler) rightsizing recommendations across 12 critical workloads in staging environment.

### Key Principles
- **Gradual rollout:** 3 waves (P2 → P1 → P0) with stability gates
- **Conservative approach:** Apply reduced targets first, validate, then optimize
- **Continuous monitoring:** SLI tracking + automated rollback triggers
- **Data-driven:** 30-day VPA baseline + AWS Cost Explorer validation

### Workload Prioritization
| Priority | Count | Risk Level | Timeline | Strategy |
|----------|-------|------------|----------|----------|
| **P2**   | 4     | Low        | Day 1    | Full VPA targets (uncapped) |
| **P1**   | 4     | Medium     | Day 3    | 50% reduction (conservative) |
| **P0**   | 4     | High       | Day 7    | 20% incremental (ultra-conservative) |

---

## 🔍 Pre-Execution Checklist

**Execute this section 24h BEFORE Wave 1 deployment.**

### 1. VPA Data Validation

```bash
# Verify VPA collection completeness (minimum 30 days)
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/modules/vpa/vpa-objects
./calculate-savings.sh

# Expected output:
# ✅ Collection progress: GOOD (≥8/12 have data)
# 📊 VPAs with recommendations: 8+ / 12
```

**Checkpoint:** If <8 VPAs have data, ABORT and wait additional 7 days.

---

### 2. Baseline Savings Calculation

```bash
# Export current VPA state (baseline for comparison)
BASELINE_FILE="/tmp/vpa-baseline-$(date +%Y%m%d).json"
kubectl get vpa -A -o json > "$BASELINE_FILE"

echo "✅ Baseline saved to: $BASELINE_FILE"

# Generate CSV for analysis
CSV_FILE="/tmp/vpa-recommendations-baseline.csv"
kubectl get vpa -A -o json | jq -r '.items[] |
  .metadata.namespace as $ns |
  .metadata.name as $name |
  (.status.recommendation.containerRecommendations // []) | .[] |
  [
    $ns,
    $name,
    .containerName,
    .target.cpu // "N/A",
    .target.memory // "N/A",
    .lowerBound.cpu // "N/A",
    .lowerBound.memory // "N/A",
    .upperBound.cpu // "N/A",
    .upperBound.memory // "N/A"
  ] | @csv' > "$CSV_FILE"

echo "📄 CSV baseline: $CSV_FILE"
```

**Checkpoint:** Open CSV in spreadsheet, validate all P0 workloads have non-N/A targets.

---

### 3. Terraform State Backup

```bash
# Backup current Terraform state
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/terraform/environments/staging

# S3 backend backup
aws s3 cp \
  s3://terraform-state-marco0-891377105802/k8s-platform/staging/terraform.tfstate \
  /tmp/terraform-state-backup-$(date +%Y%m%d-%H%M%S).tfstate

# Local state backup (if using local backend)
cp terraform.tfstate /tmp/terraform-state-backup-$(date +%Y%m%d-%H%M%S).tfstate

echo "✅ Terraform state backed up"
```

---

### 4. Monitoring Setup

#### 4.1 Alertmanager Silence Configuration

```bash
# Silence non-critical alerts during rightsizing windows
# Duration: 4h for P2, 24h for P1, 7d for P0

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: vpa-rightsizing-silences
  namespace: monitoring
data:
  silences.yaml: |
    # Silence PodCPUThrottling during rightsizing
    - matchers:
        - name: alertname
          value: PodCPUThrottling
          isRegex: false
      startsAt: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      endsAt: "$(date -u -d '+4 hours' +%Y-%m-%dT%H:%M:%SZ)"
      createdBy: "vpa-rightsizing-automation"
      comment: "Wave 1 P2 rightsizing in progress"

    # Silence PodMemoryPressure during rightsizing
    - matchers:
        - name: alertname
          value: PodMemoryPressure
          isRegex: false
      startsAt: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      endsAt: "$(date -u -d '+4 hours' +%Y-%m-%dT%H:%M:%SZ)"
      createdBy: "vpa-rightsizing-automation"
      comment: "Wave 1 P2 rightsizing in progress"
EOF

# Apply silences via Alertmanager API
ALERTMANAGER_URL="http://alertmanager.monitoring.svc.cluster.local:9093"
kubectl run -n monitoring curl-temp --rm -i --restart=Never --image=curlimages/curl -- \
  curl -XPOST "$ALERTMANAGER_URL/api/v2/silences" \
  -H "Content-Type: application/json" \
  -d @/tmp/silences.json
```

---

#### 4.2 Grafana Dashboards Preparation

```bash
# Import VPA Rightsizing Dashboard
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: vpa-rightsizing-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  vpa-rightsizing.json: |
    {
      "dashboard": {
        "title": "VPA Rightsizing Execution",
        "panels": [
          {
            "title": "CPU Usage vs VPA Target (P2 Workloads)",
            "targets": [
              {
                "expr": "rate(container_cpu_usage_seconds_total{namespace=~\"gitlab-staging|monitoring\",pod=~\"gitlab-sidekiq.*|gitlab-gitaly.*|loki-write.*|tempo-ingester.*\"}[5m])"
              }
            ]
          },
          {
            "title": "Memory Usage vs VPA Target (P2 Workloads)",
            "targets": [
              {
                "expr": "container_memory_working_set_bytes{namespace=~\"gitlab-staging|monitoring\",pod=~\"gitlab-sidekiq.*|gitlab-gitaly.*|loki-write.*|tempo-ingester.*\"}"
              }
            ]
          },
          {
            "title": "Pod Restart Count (4h window)",
            "targets": [
              {
                "expr": "increase(kube_pod_container_status_restarts_total{namespace=~\"gitlab-staging|monitoring|harbor-system|argocd|vault-system|keycloak\"}[4h])"
              }
            ]
          }
        ]
      }
    }
EOF
```

**Dashboard URL:** http://grafana.staging.internal/d/vpa-rightsizing/vpa-rightsizing-execution

---

### 5. Rollback Plan Documentation

```bash
# Create rollback script
cat > /tmp/vpa-rollback.sh <<'ROLLBACK'
#!/bin/bash
# VPA Rightsizing Rollback Script
# Usage: ./vpa-rollback.sh <wave_number>

WAVE=$1

if [ -z "$WAVE" ]; then
  echo "Usage: $0 <1|2|3>"
  exit 1
fi

case $WAVE in
  1)
    echo "🔄 Rolling back Wave 1 (P2 workloads)..."
    WORKLOADS="gitlab-sidekiq gitlab-gitaly loki-write tempo-ingester"
    ;;
  2)
    echo "🔄 Rolling back Wave 2 (P1 workloads)..."
    WORKLOADS="harbor-core harbor-jobservice grafana argocd-server"
    ;;
  3)
    echo "🔄 Rolling back Wave 3 (P0 workloads)..."
    WORKLOADS="vault keycloak gitlab-webservice prometheus"
    ;;
  *)
    echo "❌ Invalid wave number. Use 1, 2, or 3."
    exit 1
    ;;
esac

# Restore Terraform state from backup
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/terraform/environments/staging
LATEST_BACKUP=$(ls -t /tmp/terraform-state-backup-*.tfstate | head -1)
cp "$LATEST_BACKUP" terraform.tfstate
echo "✅ Terraform state restored from: $LATEST_BACKUP"

# Revert Terraform changes
terraform plan -out=/tmp/rollback.tfplan
terraform apply /tmp/rollback.tfplan

# Force pod restart with old configs
for workload in $WORKLOADS; do
  echo "🔄 Restarting $workload..."

  # Determine namespace
  case $workload in
    gitlab-*) NS="gitlab-staging" ;;
    harbor-*) NS="harbor-system" ;;
    grafana) NS="monitoring" ;;
    loki-*|tempo-*) NS="monitoring" ;;
    argocd-*) NS="argocd" ;;
    vault) NS="vault-system" ;;
    keycloak) NS="keycloak" ;;
    prometheus) NS="monitoring" ;;
  esac

  # Rollout restart
  kubectl rollout restart deployment "$workload" -n "$NS" 2>/dev/null || \
  kubectl rollout restart statefulset "$workload" -n "$NS"
done

echo "✅ Rollback complete. Monitor pods: kubectl get pods -A | grep -v Running"
ROLLBACK

chmod +x /tmp/vpa-rollback.sh
echo "✅ Rollback script ready: /tmp/vpa-rollback.sh"
```

---

### 6. Change Window Confirmation

**Business Hours (BRT):**
- **Start:** 09:00 BRT (12:00 UTC)
- **End:** 17:00 BRT (20:00 UTC)

```bash
# Verify current time is within change window
CURRENT_HOUR=$(TZ='America/Sao_Paulo' date +%H)

if [ "$CURRENT_HOUR" -ge 9 ] && [ "$CURRENT_HOUR" -lt 17 ]; then
  echo "✅ Within change window (BRT business hours)"
else
  echo "❌ OUTSIDE change window. Current BRT time: $(TZ='America/Sao_Paulo' date)"
  echo "   Abort execution and reschedule."
  exit 1
fi
```

---

### 7. Pre-Execution Checklist Summary

- [ ] VPA data collection ≥30 days (verify via calculate-savings.sh)
- [ ] Baseline saved: `/tmp/vpa-baseline-$(date +%Y%m%d).json`
- [ ] CSV analysis complete: all P0 workloads have targets
- [ ] Terraform state backed up: `/tmp/terraform-state-backup-*.tfstate`
- [ ] Alertmanager silences configured (4h for Wave 1)
- [ ] Grafana dashboard imported and accessible
- [ ] Rollback script tested: `/tmp/vpa-rollback.sh`
- [ ] Change window confirmed: 09:00-17:00 BRT
- [ ] Incident response team notified (Slack/email)

**⚠️ STOP:** If ANY checkbox is unchecked, DO NOT proceed to Wave 1.

---

## 🚀 Wave 1: P2 Workloads (Low Risk)

**Timeline:** Day 1 (2h execution + 4h monitoring)
**Workloads:** 4 non-critical services
**Strategy:** Apply full VPA target recommendations (uncapped)
**Risk:** Low (non-critical, can tolerate brief downtime)

---

### Workloads in Scope

| Workload | Namespace | Type | Current Role | Downtime Impact |
|----------|-----------|------|--------------|-----------------|
| **gitlab-sidekiq** | gitlab-staging | Deployment | Background jobs | Low (jobs queued) |
| **gitlab-gitaly** | gitlab-staging | StatefulSet | Git storage | Low (read-only fallback) |
| **loki-write** | monitoring | StatefulSet | Log ingestion | Low (buffer exists) |
| **tempo-ingester** | monitoring | StatefulSet | Trace ingestion | Low (buffer exists) |

---

### Step 1.1: Export Current Configurations

```bash
# Create backup directory
BACKUP_DIR="/tmp/vpa-wave1-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Export P2 workload configs
for workload in gitlab-sidekiq:gitlab-staging:deployment \
                gitlab-gitaly:gitlab-staging:statefulset \
                loki-write:monitoring:statefulset \
                tempo-ingester:monitoring:statefulset; do

  NAME=$(echo "$workload" | cut -d: -f1)
  NS=$(echo "$workload" | cut -d: -f2)
  TYPE=$(echo "$workload" | cut -d: -f3)

  kubectl get "$TYPE" "$NAME" -n "$NS" -o yaml > "$BACKUP_DIR/${NAME}-${NS}.yaml"

  echo "✅ Backed up: $NAME ($NS)"
done

echo "📁 Backups saved to: $BACKUP_DIR"
```

---

### Step 1.2: Calculate Target Resources

```bash
# Extract VPA recommendations for P2 workloads
echo "📊 VPA Recommendations for Wave 1 (P2):"
echo "========================================"

for workload in gitlab-sidekiq:gitlab-staging \
                gitlab-gitaly:gitlab-staging \
                loki-write:monitoring \
                tempo-ingester:monitoring; do

  NAME=$(echo "$workload" | cut -d: -f1)
  NS=$(echo "$workload" | cut -d: -f2)

  echo ""
  echo "[$NAME @ $NS]"

  # Get VPA target
  TARGET=$(kubectl get vpa "$NAME" -n "$NS" -o jsonpath='{.status.recommendation.containerRecommendations[0].target}' 2>/dev/null)

  if [ -z "$TARGET" ]; then
    echo "  ❌ ERROR: No VPA recommendation available!"
    echo "  Action: SKIP this workload, investigate missing data"
    continue
  fi

  TARGET_CPU=$(echo "$TARGET" | jq -r '.cpu')
  TARGET_MEM=$(echo "$TARGET" | jq -r '.memory')

  # Get current resources
  POD=$(kubectl get pods -n "$NS" -l "app=$NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD" ]; then
    CURRENT=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].resources.requests}')
    CURRENT_CPU=$(echo "$CURRENT" | jq -r '.cpu // "N/A"')
    CURRENT_MEM=$(echo "$CURRENT" | jq -r '.memory // "N/A"')
  else
    CURRENT_CPU="N/A"
    CURRENT_MEM="N/A"
  fi

  echo "  Current:  CPU=$CURRENT_CPU, Memory=$CURRENT_MEM"
  echo "  VPA Target: CPU=$TARGET_CPU, Memory=$TARGET_MEM"

  # Calculate change percentage
  if [ "$TARGET_CPU" != "N/A" ] && [ "$CURRENT_CPU" != "N/A" ]; then
    # Convert to millicores for comparison
    TARGET_MILLI=$(echo "$TARGET_CPU" | sed 's/m$//')
    CURRENT_MILLI=$(echo "$CURRENT_CPU" | sed 's/m$//')

    DIFF=$(( TARGET_MILLI - CURRENT_MILLI ))
    PERCENT=$(( (DIFF * 100) / CURRENT_MILLI ))

    echo "  Change: ${PERCENT}% (${DIFF}m)"

    if [ $DIFF -lt 0 ]; then
      echo "  💰 Savings opportunity: DOWNSIZE"
    else
      echo "  ⚡ Performance need: UPSIZE"
    fi
  fi

  # Save for Terraform update
  echo "${NAME},${NS},${TARGET_CPU},${TARGET_MEM}" >> /tmp/wave1-targets.csv
done

echo ""
echo "✅ Targets saved to: /tmp/wave1-targets.csv"
```

**Checkpoint:** Review `/tmp/wave1-targets.csv`. If any workload shows >50% increase, investigate before proceeding.

---

### Step 1.3: Update Terraform Configurations

**Example for gitlab-sidekiq (adjust per workload):**

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/terraform/environments/staging

# Edit GitLab Helm values
# Locate gitlab-sidekiq resources block in main.tf or separate gitlab.tf

# BEFORE (example current state):
# resources:
#   requests:
#     cpu: "500m"
#     memory: "1Gi"

# AFTER (apply VPA target - example):
# resources:
#   requests:
#     cpu: "300m"      # ← from VPA recommendation
#     memory: "768Mi"  # ← from VPA recommendation
```

**Terraform snippet pattern:**

```hcl
# In terraform/environments/staging/gitlab.tf
resource "helm_release" "gitlab" {
  # ... existing config ...

  values = [<<-YAML
    gitlab:
      sidekiq:
        resources:
          requests:
            cpu: "${var.gitlab_sidekiq_cpu}"      # Read from /tmp/wave1-targets.csv
            memory: "${var.gitlab_sidekiq_memory}"

      gitaly:
        resources:
          requests:
            cpu: "${var.gitlab_gitaly_cpu}"
            memory: "${var.gitlab_gitaly_memory}"
  YAML
  ]
}

# In terraform/environments/staging/monitoring.tf
resource "helm_release" "loki" {
  # ... existing config ...

  values = [<<-YAML
    write:
      resources:
        requests:
          cpu: "${var.loki_write_cpu}"
          memory: "${var.loki_write_memory}"
  YAML
  ]
}

resource "helm_release" "tempo" {
  # ... existing config ...

  values = [<<-YAML
    ingester:
      resources:
        requests:
          cpu: "${var.tempo_ingester_cpu}"
          memory: "${var.tempo_ingester_memory}"
  YAML
  ]
}
```

**Variables file (terraform.tfvars):**

```hcl
# P2 Wave 1 - VPA Targets (example values - use actual from CSV)
gitlab_sidekiq_cpu        = "300m"
gitlab_sidekiq_memory     = "768Mi"
gitlab_gitaly_cpu         = "800m"
gitlab_gitaly_memory      = "2Gi"
loki_write_cpu            = "200m"
loki_write_memory         = "512Mi"
tempo_ingester_cpu        = "250m"
tempo_ingester_memory     = "1Gi"
```

---

### Step 1.4: Terraform Plan Validation

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/terraform/environments/staging

# Export AWS credentials (WSL2 workaround)
eval $(aws configure export-credentials --profile k8s-platform-staging --format env)
unset AWS_PROFILE
export AWS_DEFAULT_REGION=us-east-1

# Terraform plan (target P2 resources only for safety)
terraform plan \
  -target=helm_release.gitlab \
  -target=helm_release.loki \
  -target=helm_release.tempo \
  -out=/tmp/wave1.tfplan

# Review plan output
echo ""
echo "⚠️  REVIEW TERRAFORM PLAN:"
echo "=========================="
echo "1. Verify ONLY resource.requests changes (CPU/Memory)"
echo "2. Confirm NO resource deletions"
echo "3. Check NO unrelated changes (PVC, Services, etc.)"
echo ""
read -p "Does plan look safe? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "❌ Aborted by user. Review plan and retry."
  exit 1
fi
```

---

### Step 1.5: Apply Changes

```bash
# Apply Terraform changes
terraform apply /tmp/wave1.tfplan

# Verify Helm release updates
helm list -n gitlab-staging | grep gitlab
helm list -n monitoring | grep -E "loki|tempo"

echo "✅ Helm releases updated"
```

---

### Step 1.6: Force Pod Restart (if needed)

**Note:** Terraform Helm provider may auto-restart pods. Check first:

```bash
# Check if pods are already restarting
kubectl get pods -n gitlab-staging -l app=sidekiq --watch
kubectl get pods -n gitlab-staging -l app=gitaly --watch
kubectl get pods -n monitoring -l app=loki-write --watch
kubectl get pods -n monitoring -l app=tempo-ingester --watch
```

**If pods are NOT restarting automatically:**

```bash
# Force rollout restart
kubectl rollout restart deployment gitlab-sidekiq -n gitlab-staging
kubectl rollout restart statefulset gitlab-gitaly -n gitlab-staging
kubectl rollout restart statefulset loki-write -n monitoring
kubectl rollout restart statefulset tempo-ingester -n monitoring

# Wait for rollout completion
kubectl rollout status deployment gitlab-sidekiq -n gitlab-staging --timeout=300s
kubectl rollout status statefulset gitlab-gitaly -n gitlab-staging --timeout=300s
kubectl rollout status statefulset loki-write -n monitoring --timeout=300s
kubectl rollout status statefulset tempo-ingester -n monitoring --timeout=300s
```

---

### Step 1.7: Immediate Health Checks (T+5min)

```bash
# Pod status check
echo "📊 Pod Status (Wave 1 - P2):"
kubectl get pods -n gitlab-staging -l app=sidekiq
kubectl get pods -n gitlab-staging -l app=gitaly
kubectl get pods -n monitoring -l app=loki-write
kubectl get pods -n monitoring -l app=tempo-ingester

# Verify NO CrashLoopBackOff or OOMKilled
FAILED_PODS=$(kubectl get pods -n gitlab-staging,monitoring -o json | \
  jq -r '.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.name')

if [ -n "$FAILED_PODS" ]; then
  echo "❌ FAILED PODS DETECTED:"
  echo "$FAILED_PODS"
  echo ""
  echo "🔄 Execute rollback: /tmp/vpa-rollback.sh 1"
  exit 1
fi

echo "✅ All pods Running"
```

---

### Step 1.8: Extended Monitoring (4h window)

**Monitoring checklist (execute every 30min for 4 hours):**

```bash
#!/bin/bash
# Save as: /tmp/wave1-monitor.sh
# Usage: watch -n 1800 /tmp/wave1-monitor.sh  # runs every 30min

echo "🔍 Wave 1 Monitoring - $(date)"
echo "================================"

# 1. CPU Usage (should be <80% P95)
echo ""
echo "📈 CPU Usage (P95 - last 30min):"
kubectl top pods -n gitlab-staging --containers | grep -E "sidekiq|gitaly"
kubectl top pods -n monitoring --containers | grep -E "loki-write|tempo-ingester"

# 2. Memory Usage (should be <80% P95)
echo ""
echo "📊 Memory Usage (P95 - last 30min):"
kubectl top pods -n gitlab-staging --containers | grep -E "sidekiq|gitaly" | awk '{print $1, $4}'
kubectl top pods -n monitoring --containers | grep -E "loki-write|tempo-ingester" | awk '{print $1, $4}'

# 3. Restart count (should be ZERO unexpected restarts)
echo ""
echo "🔄 Pod Restarts (last 4h):"
kubectl get pods -n gitlab-staging -l app=sidekiq -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'
kubectl get pods -n gitlab-staging -l app=gitaly -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'
kubectl get pods -n monitoring -l app=loki-write -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'
kubectl get pods -n monitoring -l app=tempo-ingester -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'

# 4. OOM events check
echo ""
echo "💥 OOMKilled Events (last 4h):"
kubectl get events -n gitlab-staging --field-selector reason=OOMKilled --sort-by='.lastTimestamp' | tail -5
kubectl get events -n monitoring --field-selector reason=OOMKilled --sort-by='.lastTimestamp' | tail -5

# 5. CPU Throttling check (Prometheus query via kubectl port-forward)
echo ""
echo "⚡ CPU Throttling Rate (should be <5%):"
# Requires prometheus port-forward: kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Query: rate(container_cpu_cfs_throttled_seconds_total{pod=~"gitlab-sidekiq.*|gitlab-gitaly.*|loki-write.*|tempo-ingester.*"}[5m])

echo ""
echo "================================"
echo "✅ Monitoring cycle complete"
```

**Make executable and run:**

```bash
chmod +x /tmp/wave1-monitor.sh

# Run every 30min for 4 hours (8 cycles)
for i in {1..8}; do
  /tmp/wave1-monitor.sh
  echo ""
  echo "⏰ Next check in 30min... (cycle $i/8)"
  sleep 1800  # 30min
done

echo "🎯 4-hour monitoring complete for Wave 1"
```

---

### Step 1.9: Success Criteria Validation

**After 4h monitoring, verify ALL criteria are met:**

- [ ] CPU Usage <80% P95 (all 4 workloads)
- [ ] Memory Usage <80% P95 (all 4 workloads)
- [ ] Zero unexpected pod restarts (restartCount unchanged from baseline)
- [ ] Zero OOMKilled events in last 4h
- [ ] CPU throttling rate <5% (via Prometheus)
- [ ] Application functionality verified:
  - [ ] GitLab background jobs processing (check Sidekiq queue)
  - [ ] GitLab git clone/push operations working (test via git clone)
  - [ ] Loki logs ingesting (verify recent logs in Grafana)
  - [ ] Tempo traces visible (verify recent traces in Grafana)

**If ANY criteria FAILS:**

```bash
# Execute immediate rollback
/tmp/vpa-rollback.sh 1

# Investigate root cause:
# - Check Prometheus metrics for CPU/Memory spikes
# - Review pod logs: kubectl logs -n <namespace> <pod> --tail=100
# - Analyze VPA recommendations: may need 60-day data for accuracy
```

---

### Step 1.10: Wave 1 Completion Checklist

- [ ] All 4 P2 workloads applied with VPA targets
- [ ] 4-hour stability window passed
- [ ] All success criteria validated
- [ ] No rollback executed
- [ ] Alertmanager silences removed/expired
- [ ] Grafana dashboard shows healthy metrics
- [ ] Documentation updated: commit Terraform changes

**⚠️ GATE:** Wave 2 can ONLY start 48h AFTER Wave 1 success validation.

---

## 🚀 Wave 2: P1 Workloads (Medium Risk)

**Timeline:** Day 3 (3h execution + 24h monitoring)
**Workloads:** 4 important services
**Strategy:** Conservative 50% reduction vs VPA recommendation
**Risk:** Medium (user-facing, limited blast radius)

---

### Workloads in Scope

| Workload | Namespace | Type | Current Role | Downtime Impact |
|----------|-----------|------|--------------|-----------------|
| **harbor-core** | harbor-system | Deployment | Registry API | Medium (image push/pull fails) |
| **harbor-jobservice** | harbor-system | Deployment | Image scanning | Low (async jobs delayed) |
| **grafana** | monitoring | Deployment | Dashboards UI | Medium (monitoring blind spot) |
| **argocd-server** | argocd | Deployment | GitOps UI/API | Medium (deployment delays) |

---

### Step 2.1: Pre-Wave Validation

**Execute 24h BEFORE Wave 2 start:**

```bash
# Verify Wave 1 stability (48h post-completion)
echo "🔍 Wave 1 Stability Check (48h post-completion):"

# Check restart counts (should be unchanged from 4h mark)
for workload in gitlab-sidekiq:gitlab-staging \
                gitlab-gitaly:gitlab-staging \
                loki-write:monitoring \
                tempo-ingester:monitoring; do

  NAME=$(echo "$workload" | cut -d: -f1)
  NS=$(echo "$workload" | cut -d: -f2)

  RESTARTS=$(kubectl get pods -n "$NS" -l "app=$NAME" -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')

  echo "  [$NAME]: $RESTARTS restarts"
done

echo ""
read -p "Wave 1 still stable after 48h? (yes/no): " STABLE

if [ "$STABLE" != "yes" ]; then
  echo "❌ Wave 1 instability detected. DO NOT proceed to Wave 2."
  echo "   Investigate and stabilize before continuing."
  exit 1
fi

echo "✅ Wave 1 stable. Proceeding to Wave 2 preparation."
```

---

### Step 2.2: Calculate Conservative Targets

**Strategy:** Apply 50% of VPA recommendation (conservative approach)

```bash
echo "📊 VPA Recommendations for Wave 2 (P1) - CONSERVATIVE 50%:"
echo "==========================================================="

for workload in harbor-core:harbor-system \
                harbor-jobservice:harbor-system \
                grafana:monitoring \
                argocd-server:argocd; do

  NAME=$(echo "$workload" | cut -d: -f1)
  NS=$(echo "$workload" | cut -d: -f2)

  echo ""
  echo "[$NAME @ $NS]"

  # Get VPA target
  TARGET=$(kubectl get vpa "$NAME" -n "$NS" -o jsonpath='{.status.recommendation.containerRecommendations[0].target}' 2>/dev/null)

  if [ -z "$TARGET" ]; then
    echo "  ❌ ERROR: No VPA recommendation available!"
    continue
  fi

  TARGET_CPU=$(echo "$TARGET" | jq -r '.cpu' | sed 's/m$//')
  TARGET_MEM=$(echo "$TARGET" | jq -r '.memory' | sed 's/Mi$//')

  # Get current resources
  POD=$(kubectl get pods -n "$NS" -l "app=$NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  CURRENT=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].resources.requests}')
  CURRENT_CPU=$(echo "$CURRENT" | jq -r '.cpu' | sed 's/m$//')
  CURRENT_MEM=$(echo "$CURRENT" | jq -r '.memory' | sed 's/Mi$//')

  # Calculate 50% conservative target
  DIFF_CPU=$(( TARGET_CPU - CURRENT_CPU ))
  CONSERVATIVE_CPU=$(( CURRENT_CPU + (DIFF_CPU / 2) ))

  DIFF_MEM=$(( TARGET_MEM - CURRENT_MEM ))
  CONSERVATIVE_MEM=$(( CURRENT_MEM + (DIFF_MEM / 2) ))

  echo "  Current:      CPU=${CURRENT_CPU}m, Memory=${CURRENT_MEM}Mi"
  echo "  VPA Target:   CPU=${TARGET_CPU}m, Memory=${TARGET_MEM}Mi"
  echo "  Conservative: CPU=${CONSERVATIVE_CPU}m, Memory=${CONSERVATIVE_MEM}Mi (50% reduction)"

  # Save for Terraform
  echo "${NAME},${NS},${CONSERVATIVE_CPU}m,${CONSERVATIVE_MEM}Mi" >> /tmp/wave2-targets.csv
done

echo ""
echo "✅ Conservative targets saved to: /tmp/wave2-targets.csv"
```

---

### Step 2.3: Update Terraform (P1 Workloads)

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/terraform/environments/staging

# Update terraform.tfvars with conservative targets
cat >> terraform.tfvars <<EOF

# P1 Wave 2 - Conservative Targets (50% of VPA recommendation)
harbor_core_cpu           = "400m"   # Example - use actual from CSV
harbor_core_memory        = "1Gi"
harbor_jobservice_cpu     = "300m"
harbor_jobservice_memory  = "768Mi"
grafana_cpu               = "200m"
grafana_memory            = "512Mi"
argocd_server_cpu         = "350m"
argocd_server_memory      = "896Mi"
EOF
```

**Terraform plan:**

```bash
terraform plan \
  -target=helm_release.harbor \
  -target=helm_release.grafana \
  -target=helm_release.argocd \
  -out=/tmp/wave2.tfplan

# Review and apply
terraform apply /tmp/wave2.tfplan
```

---

### Step 2.4: Rollout and Monitor

```bash
# Force restart (if needed)
kubectl rollout restart deployment harbor-core -n harbor-system
kubectl rollout restart deployment harbor-jobservice -n harbor-system
kubectl rollout restart deployment grafana -n monitoring
kubectl rollout restart deployment argocd-server -n argocd

# Wait for rollout
kubectl rollout status deployment harbor-core -n harbor-system --timeout=300s
kubectl rollout status deployment harbor-jobservice -n harbor-system --timeout=300s
kubectl rollout status deployment grafana -n monitoring --timeout=300s
kubectl rollout status deployment argocd-server -n argocd --timeout=300s
```

---

### Step 2.5: Extended Monitoring (24h window)

**Monitoring script (run every 1h for 24h):**

```bash
#!/bin/bash
# Save as: /tmp/wave2-monitor.sh

echo "🔍 Wave 2 Monitoring - $(date)"
echo "================================"

# 1. Service-specific health checks
echo ""
echo "🏥 Service Health Checks:"

# Harbor API
HARBOR_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://harbor.staging.internal/api/v2.0/ping)
echo "  Harbor API: HTTP $HARBOR_STATUS (expect 200)"

# Grafana UI
GRAFANA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://grafana.staging.internal/api/health)
echo "  Grafana API: HTTP $GRAFANA_STATUS (expect 200)"

# ArgoCD API
ARGOCD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://argocd.staging.internal/api/version)
echo "  ArgoCD API: HTTP $ARGOCD_STATUS (expect 200)"

# 2. Response time checks (P95 latency)
echo ""
echo "⏱️  Response Time (P95 - last 1h):"
# Prometheus query via kubectl exec
kubectl exec -n monitoring prometheus-0 -- \
  promtool query instant http://localhost:9090 \
  'histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job=~"harbor|grafana|argocd"}[1h]))'

# 3. Resource usage
echo ""
echo "📊 Resource Usage:"
kubectl top pods -n harbor-system --containers | grep harbor
kubectl top pods -n monitoring --containers | grep grafana
kubectl top pods -n argocd --containers | grep server

# 4. Error logs check
echo ""
echo "🔥 Error Logs (last 1h):"
kubectl logs -n harbor-system -l app=harbor-core --since=1h | grep -i error | tail -5
kubectl logs -n monitoring -l app=grafana --since=1h | grep -i error | tail -5
kubectl logs -n argocd -l app=argocd-server --since=1h | grep -i error | tail -5

echo "================================"
```

**Execute monitoring:**

```bash
chmod +x /tmp/wave2-monitor.sh

# Run every 1h for 24h (24 cycles)
for i in {1..24}; do
  /tmp/wave2-monitor.sh
  echo "⏰ Next check in 1h... (cycle $i/24)"
  sleep 3600
done
```

---

### Step 2.6: Success Criteria (24h validation)

- [ ] Harbor image push/pull operations working (test: docker push/pull)
- [ ] Grafana dashboards loading <1s P95
- [ ] ArgoCD sync operations completing successfully
- [ ] CPU Usage <80% P95 (all 4 workloads)
- [ ] Memory Usage <80% P95 (all 4 workloads)
- [ ] Zero unexpected restarts (24h window)
- [ ] Service response times within SLO:
  - [ ] Harbor API <200ms P95
  - [ ] Grafana UI <500ms P95
  - [ ] ArgoCD UI <500ms P95

**If FAILS:** Execute `/tmp/vpa-rollback.sh 2`

---

### Step 2.7: Wave 2 Completion Checklist

- [ ] All 4 P1 workloads applied with conservative targets
- [ ] 24-hour stability window passed
- [ ] All success criteria validated
- [ ] No service degradation detected
- [ ] Terraform changes committed

**⚠️ GATE:** Wave 3 can ONLY start 72h AFTER Wave 2 success validation.

---

## 🚀 Wave 3: P0 Workloads (High Risk)

**Timeline:** Day 7 (incremental over 3 weeks)
**Workloads:** 4 critical services
**Strategy:** Ultra-conservative 20% incremental steps
**Risk:** HIGH (critical infrastructure, zero tolerance for downtime)

---

### Workloads in Scope

| Workload | Namespace | Type | Current Role | Downtime Impact |
|----------|-----------|------|--------------|-----------------|
| **vault** | vault-system | StatefulSet | Secrets backend | CRITICAL (all SSO/secrets fail) |
| **keycloak** | keycloak | StatefulSet | SSO IdP | CRITICAL (no authentication) |
| **gitlab-webservice** | gitlab-staging | Deployment | GitLab UI/API | HIGH (CI/CD pipeline stops) |
| **prometheus** | monitoring | StatefulSet | Metrics store | HIGH (monitoring blind) |

---

### Incremental Approach (3-week timeline)

**Week 1:** -20% reduction (apply + monitor 7 days)
**Week 2:** -40% additional (if Week 1 stable)
**Week 3:** -60% target (full VPA recommendation)

---

### Step 3.1: Pre-Wave Validation

**Execute 72h BEFORE Week 1 start:**

```bash
# Verify Wave 2 stability (72h post-completion)
echo "🔍 Wave 2 Stability Check (72h post-completion):"

for workload in harbor-core:harbor-system \
                harbor-jobservice:harbor-system \
                grafana:monitoring \
                argocd-server:argocd; do

  NAME=$(echo "$workload" | cut -d: -f1)
  NS=$(echo "$workload" | cut -d: -f2)

  # Check restarts
  RESTARTS=$(kubectl get pods -n "$NS" -l "app=$NAME" -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')

  # Check uptime
  START_TIME=$(kubectl get pods -n "$NS" -l "app=$NAME" -o jsonpath='{.items[0].status.startTime}')
  UPTIME=$(( ($(date +%s) - $(date -d "$START_TIME" +%s)) / 3600 ))

  echo "  [$NAME]: $RESTARTS restarts, ${UPTIME}h uptime"
done

echo ""
read -p "Wave 2 still stable after 72h? (yes/no): " STABLE

if [ "$STABLE" != "yes" ]; then
  echo "❌ Wave 2 instability detected. DO NOT proceed to Wave 3."
  exit 1
fi
```

---

### Step 3.2: Week 1 - 20% Reduction

**Calculate 20% conservative targets:**

```bash
echo "📊 VPA Recommendations for Wave 3 Week 1 (P0) - ULTRA-CONSERVATIVE 20%:"
echo "======================================================================="

for workload in vault:vault-system \
                keycloak:keycloak \
                gitlab-webservice:gitlab-staging \
                prometheus:monitoring; do

  NAME=$(echo "$workload" | cut -d: -f1)
  NS=$(echo "$workload" | cut -d: -f2)

  echo ""
  echo "[$NAME @ $NS]"

  # Get VPA target
  TARGET=$(kubectl get vpa "$NAME" -n "$NS" -o jsonpath='{.status.recommendation.containerRecommendations[0].target}' 2>/dev/null)

  TARGET_CPU=$(echo "$TARGET" | jq -r '.cpu' | sed 's/m$//')
  TARGET_MEM=$(echo "$TARGET" | jq -r '.memory' | sed 's/Mi$//')

  # Get current
  POD=$(kubectl get pods -n "$NS" -l "app=$NAME" -o jsonpath='{.items[0].metadata.name}')
  CURRENT=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].resources.requests}')
  CURRENT_CPU=$(echo "$CURRENT" | jq -r '.cpu' | sed 's/m$//')
  CURRENT_MEM=$(echo "$CURRENT" | jq -r '.memory' | sed 's/Mi$//')

  # Calculate 20% reduction
  DIFF_CPU=$(( TARGET_CPU - CURRENT_CPU ))
  WEEK1_CPU=$(( CURRENT_CPU + (DIFF_CPU / 5) ))  # 20% = 1/5

  DIFF_MEM=$(( TARGET_MEM - CURRENT_MEM ))
  WEEK1_MEM=$(( CURRENT_MEM + (DIFF_MEM / 5) ))

  echo "  Current:     CPU=${CURRENT_CPU}m, Memory=${CURRENT_MEM}Mi"
  echo "  VPA Target:  CPU=${TARGET_CPU}m, Memory=${TARGET_MEM}Mi"
  echo "  Week 1 (-20%): CPU=${WEEK1_CPU}m, Memory=${WEEK1_MEM}Mi"

  echo "${NAME},${NS},${WEEK1_CPU}m,${WEEK1_MEM}Mi" >> /tmp/wave3-week1-targets.csv
done

echo "✅ Week 1 targets saved to: /tmp/wave3-week1-targets.csv"
```

---

### Step 3.3: Apply Week 1 Changes

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/terraform/environments/staging

# Update terraform.tfvars
cat >> terraform.tfvars <<EOF

# P0 Wave 3 Week 1 - Ultra-Conservative Targets (20% of VPA recommendation)
vault_cpu                 = "450m"  # Example - use actual from CSV
vault_memory              = "896Mi"
keycloak_cpu              = "550m"
keycloak_memory           = "1.2Gi"
gitlab_webservice_cpu     = "900m"
gitlab_webservice_memory  = "2.4Gi"
prometheus_cpu            = "1.2"
prometheus_memory         = "4Gi"
EOF

# Terraform apply
terraform plan -target=helm_release.vault \
               -target=helm_release.keycloak \
               -target=helm_release.gitlab \
               -target=helm_release.prometheus \
               -out=/tmp/wave3-week1.tfplan

terraform apply /tmp/wave3-week1.tfplan
```

---

### Step 3.4: Critical Monitoring (7 days)

**Monitoring SLIs (check every 2h for 7 days):**

```bash
#!/bin/bash
# Save as: /tmp/wave3-monitor.sh

echo "🔍 Wave 3 Critical Monitoring - $(date)"
echo "========================================"

# 1. Vault Status
echo ""
echo "🔐 Vault Health:"
VAULT_STATUS=$(kubectl exec -n vault-system vault-0 -- vault status -format=json 2>/dev/null | jq -r '.sealed')
echo "  Sealed: $VAULT_STATUS (expect: false)"

VAULT_LATENCY=$(kubectl exec -n vault-system vault-0 -- \
  sh -c 'time vault read sys/health 2>&1' | grep real | awk '{print $2}')
echo "  Response time: $VAULT_LATENCY (expect: <100ms)"

# 2. Keycloak SSO
echo ""
echo "🔑 Keycloak Health:"
KC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://keycloak.staging.internal/auth/realms/platform)
echo "  Realm endpoint: HTTP $KC_STATUS (expect: 200)"

KC_LOGIN_TIME=$(curl -s -o /dev/null -w "%{time_total}" http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/auth)
echo "  Login page load: ${KC_LOGIN_TIME}s (expect: <0.5s)"

# 3. GitLab UI
echo ""
echo "🦊 GitLab Health:"
GL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://gitlab.staging.internal/-/health)
echo "  Health endpoint: HTTP $GL_STATUS (expect: 200)"

GL_LATENCY=$(curl -s -o /dev/null -w "%{time_total}" http://gitlab.staging.internal/projects)
echo "  Projects page: ${GL_LATENCY}s (expect: <1s)"

# 4. Prometheus
echo ""
echo "📊 Prometheus Health:"
PROM_STATUS=$(kubectl exec -n monitoring prometheus-0 -- \
  wget -qO- http://localhost:9090/-/healthy 2>/dev/null)
echo "  Health: $PROM_STATUS (expect: Healthy)"

PROM_QUERY_TIME=$(kubectl exec -n monitoring prometheus-0 -- \
  promtool query instant http://localhost:9090 'up' 2>&1 | grep 'query time' | awk '{print $3}')
echo "  Query latency: ${PROM_QUERY_TIME} (expect: <1s)"

# 5. Resource usage
echo ""
echo "📈 Resource Usage (P95):"
kubectl top pods -n vault-system --containers | grep vault
kubectl top pods -n keycloak --containers | grep keycloak
kubectl top pods -n gitlab-staging --containers | grep webservice
kubectl top pods -n monitoring --containers | grep prometheus

# 6. Critical alerts
echo ""
echo "🚨 Critical Alerts (last 2h):"
kubectl exec -n monitoring alertmanager-0 -- \
  amtool alert query 'severity=critical' --alertmanager.url=http://localhost:9093 2>/dev/null | tail -10

echo "========================================"
```

**Execute 7-day monitoring:**

```bash
chmod +x /tmp/wave3-monitor.sh

# Run every 2h for 7 days (84 cycles)
for i in {1..84}; do
  /tmp/wave3-monitor.sh | tee -a /tmp/wave3-week1-log.txt
  echo "⏰ Next check in 2h... (cycle $i/84)"
  sleep 7200
done
```

---

### Step 3.5: Week 1 Success Criteria

**After 7 days, verify ALL criteria:**

- [ ] Vault seal status = false (unsealed) for 7 days
- [ ] Vault response time <100ms P95
- [ ] Keycloak SSO login latency <500ms P95
- [ ] Zero SSO authentication failures
- [ ] GitLab web UI response <1s P95
- [ ] GitLab CI/CD pipelines queue time <5min
- [ ] Prometheus query latency <1s P99
- [ ] Prometheus scrape success rate >99%
- [ ] CPU Usage <80% P95 (all 4 workloads)
- [ ] Memory Usage <80% P95 (all 4 workloads)
- [ ] Zero unexpected restarts (7-day window)
- [ ] Zero critical alerts fired

**If ANY criteria FAILS:**

```bash
# Immediate rollback
/tmp/vpa-rollback.sh 3

# DO NOT proceed to Week 2
# Investigate root cause and wait additional 14 days before retry
```

---

### Step 3.6: Week 2 - Additional 40% Reduction

**Only proceed if Week 1 = 100% success**

```bash
# Calculate Week 2 targets (40% total = current + 20% more)
# Logic: Week 1 was 20%, Week 2 adds another 20% = 40% total progress

# Repeat Step 3.2 calculation with 40% instead of 20%
# Repeat Steps 3.3-3.5 with Week 2 targets

# Monitor for another 7 days with same SLIs
```

---

### Step 3.7: Week 3 - Full VPA Target (60% total)

**Only proceed if Week 2 = 100% success**

```bash
# Apply full VPA recommendation targets
# Repeat Steps 3.2-3.5 with 100% VPA targets (no reduction)

# Extended monitoring: 14 days (vs 7 days for Weeks 1-2)
# Rationale: Final state needs longer validation before production
```

---

### Step 3.8: Wave 3 Completion Checklist

- [ ] Week 1 complete (20% reduction, 7-day stable)
- [ ] Week 2 complete (40% total reduction, 7-day stable)
- [ ] Week 3 complete (60% VPA target, 14-day stable)
- [ ] All SLIs maintained throughout 28-day period
- [ ] Zero rollbacks executed
- [ ] Terraform changes committed for all 3 weeks
- [ ] MEMORY.md updated with realized savings

---

## 📊 Post-Execution: Savings Validation (Day 30)

**Execute 30 days after Wave 3 Week 3 completion.**

---

### Step 4.1: Re-run Savings Calculator

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/modules/vpa/vpa-objects

# Generate post-execution report
./calculate-savings.sh > /tmp/vpa-post-execution-$(date +%Y%m%d).txt

# Compare with baseline
echo "📊 Baseline vs Post-Execution Comparison:"
echo "========================================="

BASELINE_FILE="/tmp/vpa-baseline-*.json"
CURRENT_FILE="/tmp/vpa-analysis-*.json"

# Calculate resource delta (manual comparison via CSV exports)
```

---

### Step 4.2: AWS Cost Explorer Validation

```bash
# Access AWS Cost Explorer
# Compare last 30 days (post-execution) vs 30 days prior (baseline)

# Filter by:
# - Service: Amazon Elastic Kubernetes Service
# - Tag: Environment=staging
# - Granularity: Daily
# - Group by: Resource

echo "💰 Expected Savings Validation:"
echo "================================"
echo "Target:       R$ 19.118,50/year"
echo "Monthly:      R$ 1.593,21/month"
echo ""
echo "Cost Explorer comparison:"
echo "  Baseline month:     R$ XXXX"
echo "  Post-execution month: R$ XXXX"
echo "  Actual savings:     R$ XXXX (-XX%)"
```

**Acceptance threshold:** Realized savings ≥80% of target (R$ 15.294/year minimum)

---

### Step 4.3: Update MEMORY.md

```bash
cd /home/gilvangalindo/.claude/projects/-home-gilvangalindo-projects-Arquitetura-Kubernetes/memory

# Add to MEMORY.md under Realizados por categoria:
# VPA rightsizing (12 workloads) | R$ 19.118,50 |

# Update Estado Geral section:
# Savings Realizados: R$ XX.XXX,XX/ano (YY% roadmap)
```

---

### Step 4.4: Lessons Learned Documentation

```bash
# Create lessons learned document
cat > /tmp/vpa-rightsizing-lessons-$(date +%Y%m%d).md <<'LESSONS'
# VPA Rightsizing Execution - Lessons Learned

**Date:** $(date +%Y-%m-%d)
**Environment:** Staging

## What Went Well
- [ ] List successful strategies
- [ ] Document effective monitoring techniques
- [ ] Note workloads that rightsized smoothly

## Challenges Encountered
- [ ] List unexpected issues
- [ ] Document workarounds applied
- [ ] Note workloads that required rollback

## Recommendations for Production
- [ ] Adjustments to timeline
- [ ] Modified conservative percentages
- [ ] Additional monitoring requirements

## VPA Recommendation Accuracy
- [ ] Which workloads had accurate VPA recommendations?
- [ ] Which needed manual tuning?
- [ ] Should collection period be extended (60 days)?

## Cost Savings Analysis
- Projected: R$ 19.118,50/year
- Realized:  R$ XXXXX/year
- Variance:  XX%

## Next Steps
- [ ] Apply to production environment (if staging successful)
- [ ] Implement automated VPA policy updates
- [ ] Set up continuous rightsizing reviews (quarterly)
LESSONS

echo "📝 Lessons learned template: /tmp/vpa-rightsizing-lessons-*.md"
```

---

## 🚨 Emergency Procedures

### Immediate Rollback Triggers

**Execute rollback IMMEDIATELY if ANY of these occur:**

1. **Pod CrashLoopBackOff**
   ```bash
   # Symptom: Pod restart loop
   kubectl get pods -A | grep CrashLoopBackOff

   # Action: Rollback affected wave
   /tmp/vpa-rollback.sh <wave_number>
   ```

2. **OOMKilled Events**
   ```bash
   # Symptom: Out of memory kills
   kubectl get events -A --field-selector reason=OOMKilled

   # Action: Immediate rollback + increase memory requests +50%
   ```

3. **CPU Throttling >5%**
   ```bash
   # Symptom: Container CPU throttled
   # Prometheus query:
   # rate(container_cpu_cfs_throttled_seconds_total[5m]) > 0.05

   # Action: Rollback + increase CPU requests +30%
   ```

4. **SLI Breach**
   ```bash
   # Symptoms:
   # - Vault response time >100ms P95
   # - Keycloak login >500ms P95
   # - GitLab UI >1s P95
   # - Prometheus query >1s P99

   # Action: Rollback immediately
   ```

5. **Service Unavailability**
   ```bash
   # Symptom: HTTP 5xx errors or timeouts
   # Action: Rollback + incident investigation
   ```

---

### Rollback Procedure

```bash
#!/bin/bash
# /tmp/vpa-rollback.sh <wave_number>

WAVE=$1

echo "🔄 EMERGENCY ROLLBACK - Wave $WAVE"
echo "===================================="
echo "Initiated at: $(date)"

case $WAVE in
  1)
    NAMESPACES="gitlab-staging monitoring"
    WORKLOADS="gitlab-sidekiq gitlab-gitaly loki-write tempo-ingester"
    ;;
  2)
    NAMESPACES="harbor-system monitoring argocd"
    WORKLOADS="harbor-core harbor-jobservice grafana argocd-server"
    ;;
  3)
    NAMESPACES="vault-system keycloak gitlab-staging monitoring"
    WORKLOADS="vault keycloak gitlab-webservice prometheus"
    ;;
esac

# Step 1: Restore Terraform state
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/terraform/environments/staging
LATEST_BACKUP=$(ls -t /tmp/terraform-state-backup-*.tfstate | head -1)
cp "$LATEST_BACKUP" terraform.tfstate
echo "✅ State restored from: $LATEST_BACKUP"

# Step 2: Terraform apply (reverts to backup config)
terraform plan -out=/tmp/rollback-wave${WAVE}.tfplan
terraform apply /tmp/rollback-wave${WAVE}.tfplan

# Step 3: Force pod restart
for ns in $NAMESPACES; do
  for workload in $WORKLOADS; do
    kubectl rollout restart deployment "$workload" -n "$ns" 2>/dev/null || \
    kubectl rollout restart statefulset "$workload" -n "$ns" 2>/dev/null || \
    echo "  ⚠️  $workload not found in $ns"
  done
done

# Step 4: Verify rollback success
sleep 60
echo ""
echo "📊 Post-Rollback Status:"
for ns in $NAMESPACES; do
  kubectl get pods -n "$ns" -o wide
done

echo ""
echo "✅ Rollback complete at: $(date)"
echo "📝 Investigate root cause before retrying."
```

---

### Post-Rollback Investigation

**Required actions after ANY rollback:**

1. **Export logs (5min before rollback)**
   ```bash
   for pod in $(kubectl get pods -n <namespace> -l app=<workload> -o name); do
     kubectl logs -n <namespace> "$pod" --since=5m > /tmp/rollback-logs-$(basename $pod).txt
   done
   ```

2. **Export Prometheus metrics snapshot**
   ```bash
   # CPU usage
   kubectl exec -n monitoring prometheus-0 -- \
     promtool query instant http://localhost:9090 \
     'rate(container_cpu_usage_seconds_total{pod="<workload>"}[5m])' \
     > /tmp/rollback-cpu-snapshot.txt

   # Memory usage
   kubectl exec -n monitoring prometheus-0 -- \
     promtool query instant http://localhost:9090 \
     'container_memory_working_set_bytes{pod="<workload>"}' \
     > /tmp/rollback-memory-snapshot.txt
   ```

3. **Root cause analysis checklist**
   - [ ] Was VPA recommendation inaccurate? (check lowerBound vs target)
   - [ ] Did traffic pattern change during execution?
   - [ ] Were there external dependencies (DB, API) causing resource spikes?
   - [ ] Is 30-day VPA collection period insufficient? (consider 60 days)
   - [ ] Was conservative percentage (50%/20%) too aggressive?

4. **Re-evaluation decision**
   - If VPA inaccurate: Extend collection period to 60 days
   - If traffic spike: Apply during low-traffic window
   - If dependencies: Optimize dependencies first, retry later
   - If conservative % too aggressive: Reduce to 10% increments

---

## 📋 Execution Timeline Summary

| Phase | Duration | Stability Gate | Risk | Action |
|-------|----------|----------------|------|--------|
| **Pre-Execution** | 1 day | VPA 30d complete | Low | Validation + backups |
| **Wave 1 (P2)** | 2h + 4h monitoring | 48h stable | Low | Full VPA targets |
| **Wave 2 (P1)** | 3h + 24h monitoring | 72h stable | Medium | 50% conservative |
| **Wave 3 Week 1 (P0)** | 1h + 7d monitoring | 7d stable | High | 20% incremental |
| **Wave 3 Week 2** | 1h + 7d monitoring | 7d stable | High | 40% total |
| **Wave 3 Week 3** | 1h + 14d monitoring | 14d stable | High | 60% VPA target |
| **Validation** | 30 days post-execution | - | - | Cost Explorer + MEMORY.md |

**Total Execution Time:** ~35 days (from Wave 1 start to final validation)

---

## 📞 Support Contacts

**During execution, notify:**
- DevOps Team Lead: [email/Slack]
- SRE On-Call: [PagerDuty rotation]
- Platform Engineering: [Slack #platform-team]

**Incident escalation:**
- P0 incidents (Vault/Keycloak down): Immediate escalation to CTO
- P1 incidents (GitLab/Prometheus degraded): Escalate to Engineering Manager
- P2 incidents (Harbor/Grafana issues): Handle via SRE on-call

---

## ✅ Final Checklist

**Before marking execution as complete:**

- [ ] All 3 waves executed successfully
- [ ] No rollbacks in last 30 days
- [ ] Cost Explorer confirms ≥80% savings target
- [ ] MEMORY.md updated with realized savings
- [ ] Terraform state clean (no drift)
- [ ] Lessons learned documented
- [ ] Grafana dashboards show healthy metrics for 30 days
- [ ] VPA recommendations re-evaluated (should converge to applied values)
- [ ] Alertmanager silences removed
- [ ] Team retrospective scheduled

---

**END OF RUNBOOK**

*Last updated: 2026-02-20*
*Version: 1.0*
*Author: SRE Agent - Claude Code*
