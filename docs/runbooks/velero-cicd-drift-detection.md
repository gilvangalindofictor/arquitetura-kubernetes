# Velero CI/CD Drift Detection Integration

**Created**: 2026-02-26
**Owner**: Platform Team
**Runbook**: Operational guide for Velero configuration drift detection automation

---

## 📋 Overview

Automated drift detection para Velero configuration, integrado ao GitLab CI/CD e Kubernetes CronJob runtime monitoring.

**Purpose**: Prevent configuration drift in Velero (IRSA role, bucket name) que pode causar backup failures.

**Integration Points**:
1. **GitLab CI**: Pre/post deployment validation, scheduled audits
2. **Kubernetes CronJob**: Daily runtime monitoring (2 AM UTC)
3. **Alerting**: Slack notifications on drift detected

---

## 🏗️ Components

### 1. GitLab CI Template

**File**: `domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-velero-drift-template.yml`

**Jobs**:
- `velero:drift:pre-deploy`: Run before Helm upgrade (manual trigger)
- `velero:drift:post-deploy`: Run after Helm upgrade (automatic)
- `velero:drift:scheduled`: Daily audit via GitLab Schedules
- `velero:drift:auto-fix`: Manual remediation (never automatic)

**Features**:
- JSON output (CI/CD ready, machine-readable)
- Slack integration (webhook notifications)
- Artifacts (drift reports, 7-day retention)
- Exit codes: 0=OK, 1=drift detected, 2=error

### 2. Kubernetes CronJob

**File**: `domains/security/velero/manifests/drift-detection-cronjob.yaml`

**Schedule**: `0 2 * * *` (daily at 2 AM UTC)
**RBAC**: ServiceAccount + Role + RoleBinding
**Alert**: Slack webhook on drift detected

**Components**:
- CronJob: velero-drift-detection
- ServiceAccount: velero-drift-checker
- Role: Read serviceaccounts, backupstoragelocations
- RoleBinding: Bind ServiceAccount to Role

### 3. Drift Detection Script

**File**: `scripts/velero/check-velero-drift.sh`

**Validates**:
- ServiceAccount IRSA annotation (IAM role ARN)
- BackupStorageLocation bucket name
- Velero deployment replicas

**Output Formats**:
- Human-readable (default): Text summary
- JSON (--json flag): Machine-readable, CI/CD ready

**Exit Codes**:
- `0`: No drift detected
- `1`: Drift detected
- `2`: Error running script

### 4. Remediation Script

**File**: `scripts/velero/update-velero-values.sh`

**Features**:
- Dry-run mode (preview changes)
- Terraform output integration
- Pre/post validation
- Helm upgrade with templated values

---

## 🚀 Integration Methods

### Method 1: GitLab CI Pipeline

**Use case**: Development workflow, pre/post deployment validation

#### Step 1: Include Template

```yaml
# .gitlab-ci.yml
include:
  - project: 'platform/ci-templates'
    file: '/domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-velero-drift-template.yml'

stages:
  - validate
  - pre-deploy
  - deploy
  - post-deploy
  - audit

variables:
  CLUSTER_NAME: "k8s-platform-prod"
  VELERO_NAMESPACE: "velero"
```

#### Step 2: Use Drift Detection Jobs

```yaml
# Pre-deployment validation (manual trigger)
velero:drift:pre-deploy:
  extends: .velero_drift_check
  stage: pre-deploy
  when: manual

# Deployment
velero:deploy:
  stage: deploy
  script:
    - terraform apply -target=module.velero_staging
  dependencies:
    - velero:drift:pre-deploy

# Post-deployment verification (automatic)
velero:drift:post-deploy:
  extends: .velero_drift_check
  stage: post-deploy
  needs: ["velero:deploy"]
```

#### Step 3: Configure GitLab Schedule

**Path**: GitLab > CI/CD > Schedules > New Schedule

| Field | Value |
|-------|-------|
| **Description** | Velero Drift Detection Daily Audit |
| **Interval Pattern** | `0 2 * * *` |
| **Target branch** | main |
| **Active** | ✅ Yes |

**Job**: `velero:drift:scheduled` will run automatically

---

### Method 2: Kubernetes CronJob

**Use case**: Runtime monitoring, detect unauthorized changes

#### Step 1: Create Secret for Slack Webhook

```bash
kubectl create secret generic monitoring-webhooks \
  -n velero \
  --from-literal=slack-webhook-url='https://hooks.slack.com/services/T00/B00/XXXX'
```

Or use ExternalSecret (Vault):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: monitoring-webhooks
  namespace: velero
spec:
  refreshInterval: 24h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: monitoring-webhooks
    creationPolicy: Owner
  data:
  - secretKey: slack-webhook-url
    remoteRef:
      key: secret/data/monitoring/webhooks
      property: slack_url
```

#### Step 2: Deploy CronJob

```bash
kubectl apply -f domains/security/velero/manifests/drift-detection-cronjob.yaml
```

**Output**:
```
cronjob.batch/velero-drift-detection created
serviceaccount/velero-drift-checker created
role.rbac.authorization.k8s.io/velero-drift-checker created
rolebinding.rbac.authorization.k8s.io/velero-drift-checker created
```

#### Step 3: Verify CronJob

```bash
# List CronJob
kubectl get cronjobs -n velero

# View schedule
kubectl get cronjob velero-drift-detection -n velero -o yaml | grep schedule

# View last run
kubectl get jobs -n velero -l app=velero-drift-detection --sort-by=.metadata.creationTimestamp

# View logs
kubectl logs -n velero -l app=velero-drift-detection --tail=100
```

---

## 📊 Configuration

### GitLab CI Variables

**Path**: GitLab > Settings > CI/CD > Variables

| Variable | Description | Example | Protected | Masked |
|----------|-------------|---------|-----------|--------|
| `SLACK_WEBHOOK_URL` | Slack webhook for alerts | `https://hooks.slack.com/...` | ✅ | ✅ |
| `CLUSTER_NAME` | Kubernetes cluster name | `k8s-platform-prod` | ❌ | ❌ |
| `VELERO_NAMESPACE` | Velero namespace | `velero` | ❌ | ❌ |
| `AWS_REGION` | AWS region | `us-east-1` | ❌ | ❌ |

### Expected Configuration Values

**ServiceAccount IRSA Annotation**:
```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::891377105802:role/k8s-platform-prod-velero-dr-role
```

**BackupStorageLocation Bucket**:
```yaml
spec:
  objectStorage:
    bucket: velero-backups-staging-891377105802-us-east-1
```

**Terraform Outputs** (used by scripts):
```hcl
output "velero_irsa_role_arn" {
  value = module.velero_dr_staging.velero_role_arn
}

output "velero_primary_bucket_name" {
  value = module.velero_dr_staging.primary_bucket_name
}
```

---

## 📈 Expected Outcomes

| Scenario | Exit Code | Action | Alert |
|----------|-----------|--------|-------|
| **No drift** | 0 | ✅ Pass pipeline | No (optional success notification) |
| **Drift detected** | 1 | ❌ Fail pipeline, require manual review | ✅ Slack alert |
| **Script error** | 2 | ❌ Fail pipeline, investigate | ✅ Slack alert |

### Drift Report Example (JSON)

```json
{
  "status": "drift_detected",
  "timestamp": "2026-02-26T19:30:28Z",
  "cluster": "k8s-platform-prod",
  "namespace": "velero",
  "drifts": [
    {
      "field": "serviceaccount.velero-server.annotations[eks.amazonaws.com/role-arn]",
      "expected": "arn:aws:iam::891377105802:role/k8s-platform-prod-velero-dr-role",
      "actual": "arn:aws:iam::891377105802:role/k8s-platform-prod-velero-role",
      "severity": "critical"
    },
    {
      "field": "backupstoragelocation.default.spec.objectStorage.bucket",
      "expected": "velero-backups-staging-891377105802-us-east-1",
      "actual": "k8s-platform-prod-velero-backups",
      "severity": "critical"
    }
  ],
  "drift_count": 2
}
```

---

## 🔧 Troubleshooting

### Pipeline Fails with Exit 1 (Drift Detected)

**Cause**: Configuration drift detected between expected and actual values

**Investigation**:
1. Review drift report artifact (`/tmp/drift-report.json`)
2. Compare expected vs actual values
3. Identify root cause (manual change, Helm upgrade failure, etc.)

**Resolution**:
```bash
# Option 1: Manual fix
kubectl patch serviceaccount velero-server -n velero \
  --type merge \
  -p '{"metadata":{"annotations":{"eks.amazonaws.com/role-arn":"arn:aws:iam::891377105802:role/k8s-platform-prod-velero-dr-role"}}}'

# Option 2: Auto-fix (GitLab CI)
# Go to failed pipeline > velero:drift:auto-fix > Click "Play"

# Option 3: Auto-fix (manual script)
scripts/velero/update-velero-values.sh --auto-fix
```

### CronJob Fails (Exit 2)

**Possible Causes**:
- RBAC permissions missing
- Script URL unreachable (check `SCRIPT_BASE_URL`)
- Velero namespace doesn't exist
- kubectl auth fails

**Investigation**:
```bash
# Check CronJob logs
kubectl logs -n velero -l app=velero-drift-detection --tail=100

# Check ServiceAccount
kubectl get sa velero-drift-checker -n velero

# Check RBAC
kubectl auth can-i get serviceaccounts --as=system:serviceaccount:velero:velero-drift-checker -n velero
kubectl auth can-i get backupstoragelocations --as=system:serviceaccount:velero:velero-drift-checker -n velero

# Check script download
SCRIPT_URL="https://raw.githubusercontent.com/yourorg/platform/main/scripts/velero/check-velero-drift.sh"
curl -I $SCRIPT_URL  # Should return 200 OK
```

**Resolution**:
1. Verify RBAC: `kubectl apply -f drift-detection-cronjob.yaml` (reapply)
2. Update `SCRIPT_BASE_URL` to correct repository URL
3. Check network policies (allow CronJob to reach GitHub/GitLab)

### Slack Alerts Not Received

**Possible Causes**:
- Secret `monitoring-webhooks` doesn't exist
- Webhook URL invalid or expired
- Network policy blocking outbound HTTPS

**Investigation**:
```bash
# Check secret exists
kubectl get secret monitoring-webhooks -n velero

# Decode webhook URL
kubectl get secret monitoring-webhooks -n velero -o jsonpath='{.data.slack-webhook-url}' | base64 -d

# Test webhook manually
curl -X POST "$WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test alert from kubectl"}'
```

**Resolution**:
1. Create secret with valid webhook URL
2. Regenerate webhook URL in Slack if expired
3. Check NetworkPolicy allows egress to `hooks.slack.com:443`

---

## 📚 References

### Scripts

- `scripts/velero/check-velero-drift.sh` - Drift detection
- `scripts/velero/update-velero-values.sh` - Remediation

### Runbooks

- `docs/runbooks/velero-deployment-drift-prevention.md` - Deployment guide

### ADRs

- `docs/adr/adr-XXX-velero-drift-detection.md` - Architecture decision (to be created)

### Terraform Modules

- `modules/velero-dr/` - Velero DR infrastructure

---

## 🎯 Maintenance

### Weekly

- ✅ Review drift detection results (GitLab Schedules logs)
- ✅ Verify Slack alerts are being received
- ✅ Check for false positives (adjust expected values if needed)

### Monthly

- ✅ Review drift detection accuracy
- ✅ Update expected configuration values in scripts (if Velero upgraded)
- ✅ Test auto-remediation end-to-end

### Quarterly

- ✅ Test restore from replica bucket (DR drill)
- ✅ Review and update runbook
- ✅ Audit RBAC permissions (least privilege)

---

## 📝 Example Workflows

### Workflow 1: Pre-Deployment Validation

```bash
# Developer workflow (MR)
1. Create MR with Velero changes
2. GitLab CI runs velero:validate (automatic)
3. If drift detected → Fix before merge
4. If no drift → Approve MR

# Deployment workflow (main branch)
1. Trigger velero:drift:pre-deploy (manual)
2. If drift detected → Block deployment
3. If no drift → Proceed with velero:deploy
4. velero:drift:post-deploy runs automatically
5. If post-deploy fails → Rollback or manual fix
```

### Workflow 2: Daily Audit

```bash
# GitLab CI Schedule (2 AM UTC daily)
1. velero:drift:scheduled runs automatically
2. If drift detected:
   - Slack alert sent to #platform-alerts
   - On-call engineer investigates
   - Decision: auto-fix or manual investigation
3. If no drift → No action needed (silent)
```

### Workflow 3: Auto-Remediation

```bash
# When drift detected
1. Review drift report (artifact or Slack alert)
2. Decide: auto-fix or manual investigation
3. If auto-fix approved:
   - GitLab CI: Trigger velero:drift:auto-fix (manual)
   - Kubernetes: Run scripts/velero/update-velero-values.sh --auto-fix
4. Verify: velero:drift:post-deploy passes
5. Document: Add to incident log
```

---

**Last Updated**: 2026-02-26
**Runbook Version**: 1.0
**Owner**: Platform Team
**Contact**: #platform-team (Slack)
