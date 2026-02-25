# Velero Disaster Recovery Runbook

**Version**: 1.0
**Last Updated**: 2026-02-25
**Owner**: Platform Team / SRE
**Status**: Production Ready (Post V-008 IRSA Implementation)

---

## Quick Reference

**RTO (Recovery Time Objective)**: 1 hour
**RPO (Recovery Point Objective)**: 24 hours (daily), 1 hour (critical namespaces)
**Cluster**: k8s-platform-prod (EKS 1.34)
**Region**: us-east-1
**S3 Bucket**: k8s-platform-prod-velero-backups
**Authentication**: IRSA (no static credentials)

---

## Table of Contents

1. [Emergency Response](#emergency-response)
2. [Prerequisites](#prerequisites)
3. [Disaster Scenarios](#disaster-scenarios)
4. [Restore Procedures](#restore-procedures)
5. [Validation](#validation)
6. [Troubleshooting](#troubleshooting)
7. [Post-Incident](#post-incident)

---

## Emergency Response

### Immediate Actions (First 5 Minutes)

```bash
# 1. Assess cluster accessibility
kubectl cluster-info
kubectl get nodes

# 2. Check Velero status
kubectl get pods -n velero
velero backup get | head -20

# 3. Identify scope of disaster
kubectl get namespaces
kubectl get deployments --all-namespaces | grep "0/" | wc -l

# 4. Alert team
# - Notify Platform Team lead
# - Create incident channel: #incident-YYYY-MM-DD-HHmm
# - Document start time for RTO tracking
```

### Decision Tree

```
Is entire cluster down?
├─ YES → [Full Cluster Restore](#full-cluster-restore) (60 min)
└─ NO
   └─ Is single namespace missing?
      ├─ YES → [Namespace Restore](#namespace-restore) (15 min)
      └─ NO
         └─ Is single application corrupted?
            ├─ YES → [Application Restore](#application-restore) (10 min)
            └─ NO → [Selective Resource Restore](#selective-resource-restore) (5-10 min)
```

---

## Prerequisites

### Required Access

```bash
# 1. AWS SSO Login (15-minute session)
aws sso login --profile k8s-platform-staging
export AWS_PROFILE=k8s-platform-staging

# Verify AWS access
aws sts get-caller-identity
# Expected output:
# {
#   "UserId": "AROAXXXXXXXXXXXXXXXXX:user@example.com",
#   "Account": "891377105802",
#   "Arn": "arn:aws:sts::891377105802:assumed-role/..."
# }

# 2. Kubernetes Cluster Access
aws eks update-kubeconfig \
  --name k8s-platform-prod \
  --region us-east-1 \
  --profile k8s-platform-staging

kubectl config current-context
# Expected: arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod

# 3. Verify kubectl access
kubectl auth can-i '*' '*' --all-namespaces
# Expected: yes (cluster-admin required for restore)
```

### Required Tools

```bash
# Check tool versions
kubectl version --client --short
# Expected: v1.34+

velero version --client-only
# Expected: v1.15.0+

aws --version
# Expected: aws-cli/2.x

jq --version
# Expected: jq-1.6+

# Install Velero CLI if missing (macOS/Linux)
curl -L https://github.com/vmware-tanzu/velero/releases/download/v1.15.0/velero-v1.15.0-linux-amd64.tar.gz | tar -xz
sudo mv velero-v1.15.0-linux-amd64/velero /usr/local/bin/
```

### Environment Setup

```bash
# Export constants for all commands
export CLUSTER_NAME="k8s-platform-prod"
export VELERO_NAMESPACE="velero"
export VELERO_BUCKET="k8s-platform-prod-velero-backups"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="891377105802"

# Save to temporary file for session persistence
cat > /tmp/velero-env.sh <<EOF
export CLUSTER_NAME="${CLUSTER_NAME}"
export VELERO_NAMESPACE="${VELERO_NAMESPACE}"
export VELERO_BUCKET="${VELERO_BUCKET}"
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
EOF

# Source in new terminals: source /tmp/velero-env.sh
```

---

## Disaster Scenarios

### Scenario 1: Complete Cluster Loss

**Symptoms**:
- EKS control plane unreachable (HTTP 503/504)
- All worker nodes terminated or unavailable
- `kubectl cluster-info` fails with connection refused/timeout
- AWS Console shows cluster in FAILED state

**Root Causes**:
- AWS region outage (rare but possible)
- Accidental cluster deletion via Terraform/Console
- VPC/subnet/security group misconfiguration breaking cluster networking
- Control plane upgrade failure rendering cluster unusable

**Impact**:
- All applications unavailable
- Data loss risk if PVs deleted
- Complete service outage

**Recovery**: [Full Cluster Restore](#full-cluster-restore)
**Estimated RTO**: 60 minutes

---

### Scenario 2: Namespace Deletion

**Symptoms**:
- `kubectl get namespace <name>` returns "NotFound"
- All workloads in namespace gone (deployments, pods, services)
- Application-specific URLs return 404/502
- ArgoCD shows "OutOfSync" or "Missing" for applications in that namespace

**Root Causes**:
- Accidental `kubectl delete namespace` command
- Automation script error (e.g., cleanup job bug)
- ArgoCD prune operation misconfigured
- Kyverno policy accidentally enforcing namespace deletion

**Impact**:
- Single application/service unavailable
- Potential data loss if PVCs deleted with namespace

**Recovery**: [Namespace Restore](#namespace-restore)
**Estimated RTO**: 15 minutes

---

### Scenario 3: Application Corruption

**Symptoms**:
- Application returns 500 errors or crashes continuously
- Deployment shows incorrect image tag or broken configuration
- ConfigMap/Secret contains invalid values
- Application logs show unexpected errors post-deployment

**Root Causes**:
- Bad GitOps commit deployed via ArgoCD
- Manual `kubectl edit` mistake
- Helm upgrade with incorrect values
- External secrets sync error populating wrong credentials

**Impact**:
- Single application degraded or unavailable
- Users may see errors or unexpected behavior

**Recovery**: [Application Restore](#application-restore)
**Estimated RTO**: 10 minutes

---

### Scenario 4: Persistent Volume Data Loss

**Symptoms**:
- Application reports database connection error or missing files
- PVC shows status "Lost" or "Pending" (re-created but not bound)
- `kubectl describe pvc` shows "ProvisioningFailed" or missing volume
- EBS volume accidentally deleted from AWS Console

**Root Causes**:
- PVC deleted accidentally
- PV ReclaimPolicy=Delete and PVC deleted (cascading delete)
- EBS volume manually deleted from AWS Console
- Storage class misconfiguration causing volume deletion

**Impact**:
- Data loss (database, uploaded files, git repositories)
- Application unable to start (waiting for PVC)

**Recovery**: [Volume Restore](#volume-restore)
**Estimated RTO**: 20 minutes (depends on volume size)

---

### Scenario 5: Cross-Region/Cross-Cluster Migration

**Symptoms**:
- Need to migrate entire cluster to new region (DR exercise)
- Need to migrate specific namespaces to new cluster
- Compliance requirement to replicate production to DR cluster

**Root Causes**:
- Regional disaster recovery test
- Multi-cluster strategy implementation
- Cost optimization (migrating to cheaper region)

**Impact**:
- Planned downtime (if migration in-place)
- Zero downtime (if blue-green migration)

**Recovery**: [Cross-Cluster Migration](#cross-cluster-migration)
**Estimated RTO**: 90 minutes (full cluster), 30 minutes (single namespace)

---

## Restore Procedures

### Full Cluster Restore

**Use Case**: Cluster completely destroyed, need to rebuild from scratch
**Prerequisites**: AWS credentials, Terraform state intact, S3 backups accessible
**Estimated Time**: 60 minutes

#### Step 1: Provision New EKS Cluster (30 min)

```bash
# Navigate to Terraform directory
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging

# Verify Terraform state backend accessible
terraform init
terraform state list | head -10

# Plan cluster creation (or re-creation if destroyed)
terraform plan -target=module.eks

# Apply EKS cluster (creates control plane + node groups)
terraform apply -target=module.eks -auto-approve

# Wait for cluster ready (~15-20 minutes)
aws eks wait cluster-active \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION}

# Update kubeconfig
aws eks update-kubeconfig \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION}

# Verify nodes ready
kubectl get nodes
# Expected: 8 nodes (2 system t3.medium, 3 workloads t3.large, 3 critical t3.xlarge)
```

#### Step 2: Install Core Infrastructure (10 min)

```bash
# Apply Velero module to get IAM role + S3 access
terraform apply -target=module.velero_dr_staging -auto-approve

# Extract Terraform outputs
export VELERO_ROLE_ARN=$(terraform output -raw velero_role_arn)
export VELERO_BUCKET=$(terraform output -raw velero_bucket_name)

echo "Velero IAM Role: ${VELERO_ROLE_ARN}"
echo "Velero S3 Bucket: ${VELERO_BUCKET}"

# Install Velero via Helm with IRSA
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

helm install velero vmware-tanzu/velero \
  --namespace ${VELERO_NAMESPACE} \
  --create-namespace \
  --version 8.1.0 \
  --set credentials.useSecret=false \
  --set serviceAccount.server.annotations."eks\.amazonaws\.com/role-arn"="${VELERO_ROLE_ARN}" \
  --set configuration.backupStorageLocation[0].name=default \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].bucket="${VELERO_BUCKET}" \
  --set configuration.backupStorageLocation[0].config.region="${AWS_REGION}" \
  --set configuration.volumeSnapshotLocation[0].name=default \
  --set configuration.volumeSnapshotLocation[0].provider=aws \
  --set configuration.volumeSnapshotLocation[0].config.region="${AWS_REGION}" \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.11.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins

# Wait for Velero ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=velero \
  -n ${VELERO_NAMESPACE} \
  --timeout=300s

# Verify Velero IRSA authentication
kubectl exec -n ${VELERO_NAMESPACE} deploy/velero -- aws sts get-caller-identity
# Expected: "Arn": "arn:aws:sts::891377105802:assumed-role/k8s-platform-prod-velero-role/..."
```

#### Step 3: Verify Backup Sync from S3 (5 min)

```bash
# Check BackupStorageLocation status
kubectl get backupstoragelocation -n ${VELERO_NAMESPACE}
# Expected: default   Available

# Wait for backups to sync from S3 (Velero polls every 1 minute)
echo "Waiting for backup sync from S3... (max 2 minutes)"
for i in {1..12}; do
  COUNT=$(velero backup get --output json | jq '.items | length')
  echo "Attempt $i: Found $COUNT backups"
  if [ "$COUNT" -gt 0 ]; then
    echo "Backups synced successfully!"
    break
  fi
  sleep 10
done

# List available backups
velero backup get
# Expected: daily-full-backup-YYYYMMDDHHMMSS, hourly-critical-backup-*, etc.
```

#### Step 4: Select Latest Successful Backup (2 min)

```bash
# Find latest completed daily backup (best for full restore)
LATEST_BACKUP=$(velero backup get \
  --selector backup-schedule=daily-full \
  --output json | \
  jq -r '.items |
    map(select(.status.phase == "Completed")) |
    sort_by(.status.completionTimestamp) |
    reverse |
    .[0].metadata.name')

echo "Selected backup: ${LATEST_BACKUP}"

# Verify backup details
velero backup describe ${LATEST_BACKUP} --details

# Check backup age (should be < 24 hours for RPO compliance)
BACKUP_AGE=$(velero backup get ${LATEST_BACKUP} -o json | \
  jq -r '.status.completionTimestamp')
echo "Backup completed at: ${BACKUP_AGE}"
```

#### Step 5: Execute Full Cluster Restore (10 min)

```bash
# Create restore with timestamp identifier
RESTORE_NAME="full-cluster-restore-$(date +%Y%m%d%H%M%S)"

velero restore create ${RESTORE_NAME} \
  --from-backup ${LATEST_BACKUP} \
  --wait

# Monitor restore progress in separate terminal
watch -n 5 "velero restore describe ${RESTORE_NAME} --details | tail -30"

# Check restore logs for errors
velero restore logs ${RESTORE_NAME} | grep -i error

# Wait for restore completion
velero restore get ${RESTORE_NAME} -o jsonpath='{.status.phase}'
# Expected: Completed (or PartiallyFailed with non-critical errors)
```

#### Step 6: Post-Restore Validation (3 min)

```bash
# 1. Verify all namespaces restored
kubectl get namespaces | wc -l
# Expected: ~17 namespaces (excluding kube-system which was excluded)

# 2. Check critical namespaces exist
CRITICAL_NS="staging-security-vault argocd monitoring harbor-system staging-platform-gitlab staging-platform-keycloak sonarqube"
for ns in $CRITICAL_NS; do
  if kubectl get namespace $ns >/dev/null 2>&1; then
    echo "✓ $ns"
  else
    echo "✗ $ns MISSING!"
  fi
done

# 3. Check deployments ready
kubectl get deployments --all-namespaces -o json | \
  jq -r '.items[] |
    select(.status.readyReplicas != .status.replicas) |
    "\(.metadata.namespace)/\(.metadata.name): \(.status.readyReplicas // 0)/\(.status.replicas)"'
# Expected: Empty (all deployments ready) or only non-critical pods pending

# 4. Check PVC status
kubectl get pvc --all-namespaces | grep -v Bound
# Expected: No Pending/Lost PVCs (volumes restored from EBS snapshots)

# 5. Test critical application endpoints
curl -I https://grafana.${CLUSTER_NAME}.example.com/api/health
curl -I https://argocd.${CLUSTER_NAME}.example.com/healthz
curl -I https://harbor.${CLUSTER_NAME}.example.com/api/v2.0/health

# Jump to Validation section for comprehensive checks
```

**Total Time**: ~60 minutes (30 Terraform + 10 Velero install + 5 sync + 2 backup select + 10 restore + 3 validate)

---

### Namespace Restore

**Use Case**: Single namespace accidentally deleted
**Prerequisites**: Velero installed, backups available, namespace currently missing
**Estimated Time**: 15 minutes

#### Step 1: Identify Target Namespace and Backup (3 min)

```bash
# Define namespace to restore
export TARGET_NAMESPACE="staging-platform-gitlab"

# Verify namespace is actually missing
kubectl get namespace ${TARGET_NAMESPACE}
# Expected: Error from server (NotFound): namespaces "..." not found

# Find latest backup containing this namespace
LATEST_BACKUP=$(velero backup get \
  --selector backup-schedule=daily-full \
  --output json | \
  jq -r '.items |
    map(select(.status.phase == "Completed")) |
    sort_by(.status.completionTimestamp) |
    reverse |
    .[0].metadata.name')

echo "Using backup: ${LATEST_BACKUP}"

# Verify namespace exists in backup
velero backup describe ${LATEST_BACKUP} --details | \
  grep -A 5 "Included namespaces" | \
  grep ${TARGET_NAMESPACE}
```

#### Step 2: Execute Namespace Restore (10 min)

```bash
# Create restore for single namespace
RESTORE_NAME="${TARGET_NAMESPACE}-restore-$(date +%Y%m%d%H%M%S)"

velero restore create ${RESTORE_NAME} \
  --from-backup ${LATEST_BACKUP} \
  --include-namespaces ${TARGET_NAMESPACE} \
  --wait

# Monitor restore progress
velero restore describe ${RESTORE_NAME}

# Check for errors
velero restore logs ${RESTORE_NAME} | grep -E "error|warning" -i
```

#### Step 3: Validate Namespace Restore (2 min)

```bash
# 1. Namespace exists
kubectl get namespace ${TARGET_NAMESPACE}
# Expected: Active

# 2. All resources restored
kubectl get all,pvc,secret,configmap,ingress,networkpolicy -n ${TARGET_NAMESPACE}

# 3. Pods running
kubectl get pods -n ${TARGET_NAMESPACE} \
  --field-selector=status.phase!=Running,status.phase!=Succeeded
# Expected: Empty (all pods running)

# 4. External secrets synced (if ESO used)
kubectl get externalsecrets -n ${TARGET_NAMESPACE} -o json | \
  jq -r '.items[] |
    select(.status.conditions[0].status != "True") |
    .metadata.name'
# Expected: Empty (all synced)

# 5. Test application endpoint
APP_URL=$(kubectl get ingress -n ${TARGET_NAMESPACE} -o jsonpath='{.items[0].spec.rules[0].host}')
curl -I https://${APP_URL}
# Expected: 200 or 302 (application accessible)
```

**Total Time**: ~15 minutes (3 identify + 10 restore + 2 validate)

---

### Application Restore

**Use Case**: Single application corrupted, need rollback to previous state
**Prerequisites**: Velero backups, know timestamp before corruption
**Estimated Time**: 10 minutes

#### Step 1: Identify Backup Before Incident (3 min)

```bash
# Define application details
export TARGET_NAMESPACE="sonarqube"
export APP_LABEL="app.kubernetes.io/name=sonarqube"

# List backups with timestamps
velero backup get -o json | \
  jq -r '.items[] |
    "\(.metadata.name) - \(.status.completionTimestamp) - \(.status.phase)"' | \
  sort -r | \
  head -20

# Select backup BEFORE incident occurred
# Example: Incident at 2026-02-25 14:30, use backup from 2026-02-25 02:00
export BACKUP_NAME="daily-full-backup-20260225020000"

# Verify backup contains target namespace
velero backup describe ${BACKUP_NAME} | grep ${TARGET_NAMESPACE}
```

#### Step 2: Scale Down Current Application (2 min)

```bash
# Scale deployments to zero (preserves resources, stops traffic)
kubectl scale deployment -n ${TARGET_NAMESPACE} \
  --all \
  --replicas=0

# Wait for pods to terminate
kubectl wait --for=delete pod \
  -n ${TARGET_NAMESPACE} \
  -l ${APP_LABEL} \
  --timeout=120s

# Alternative: Delete corrupted resources (more aggressive)
# kubectl delete deployment,service,configmap,secret \
#   -n ${TARGET_NAMESPACE} \
#   -l ${APP_LABEL}
```

#### Step 3: Restore Application Resources (3 min)

```bash
# Restore only application-related resources
RESTORE_NAME="app-restore-${TARGET_NAMESPACE}-$(date +%Y%m%d%H%M%S)"

velero restore create ${RESTORE_NAME} \
  --from-backup ${BACKUP_NAME} \
  --include-namespaces ${TARGET_NAMESPACE} \
  --include-resources deployments,services,configmaps,secrets,ingresses \
  --selector ${APP_LABEL} \
  --wait

# Check restore status
velero restore describe ${RESTORE_NAME} --details
```

#### Step 4: Validate Application Recovery (2 min)

```bash
# 1. Deployment rollout status
kubectl rollout status deployment -n ${TARGET_NAMESPACE} -l ${APP_LABEL}
# Expected: successfully rolled out

# 2. Pods running
kubectl get pods -n ${TARGET_NAMESPACE} -l ${APP_LABEL}
# Expected: All Running

# 3. Check application logs
kubectl logs -n ${TARGET_NAMESPACE} -l ${APP_LABEL} --tail=50
# Expected: No error logs, startup successful

# 4. Test endpoint
APP_URL=$(kubectl get ingress -n ${TARGET_NAMESPACE} -o jsonpath='{.items[0].spec.rules[0].host}')
curl -I https://${APP_URL}
# Expected: 200 OK

# 5. Application-specific health check (example: SonarQube)
curl https://${APP_URL}/api/system/health
# Expected: {"health":"GREEN"}
```

**Total Time**: ~10 minutes (3 identify + 2 scale down + 3 restore + 2 validate)

---

### Volume Restore

**Use Case**: PVC/PV deleted or corrupted, data loss
**Prerequisites**: Velero volume snapshots enabled (EBS snapshots exist)
**Estimated Time**: 20 minutes

#### Step 1: Identify PVC and Backup (3 min)

```bash
# Define PVC details
export TARGET_NAMESPACE="staging-platform-gitlab"
export PVC_NAME="gitaly-data"

# Check current PVC status
kubectl get pvc ${PVC_NAME} -n ${TARGET_NAMESPACE}
# If exists: status Pending/Lost
# If deleted: Error from server (NotFound)

# Find latest backup with volume snapshots
LATEST_BACKUP=$(velero backup get \
  --selector backup-schedule=weekly-pvc \
  --output json | \
  jq -r '.items |
    map(select(.status.phase == "Completed")) |
    sort_by(.status.completionTimestamp) |
    reverse |
    .[0].metadata.name')

echo "Using backup: ${LATEST_BACKUP}"

# Verify backup includes volume snapshots
velero backup describe ${LATEST_BACKUP} --details | \
  grep -A 10 "Volume Snapshots"
```

#### Step 2: Scale Down Workload Using PVC (2 min)

```bash
# Find deployments using this PVC
kubectl get deployment -n ${TARGET_NAMESPACE} -o json | \
  jq -r --arg pvc "$PVC_NAME" '.items[] |
    select(.spec.template.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) |
    .metadata.name'

# Scale down deployment (example: Gitaly)
kubectl scale deployment gitaly -n ${TARGET_NAMESPACE} --replicas=0

# Wait for pods to terminate
kubectl wait --for=delete pod \
  -n ${TARGET_NAMESPACE} \
  -l app=gitaly \
  --timeout=120s
```

#### Step 3: Delete Corrupted PVC (1 min)

```bash
# Delete PVC (will delete PV if ReclaimPolicy=Delete)
kubectl delete pvc ${PVC_NAME} -n ${TARGET_NAMESPACE}

# Verify PVC deleted
kubectl get pvc ${PVC_NAME} -n ${TARGET_NAMESPACE}
# Expected: NotFound
```

#### Step 4: Restore PVC from Snapshot (10 min)

```bash
# Restore PVC only (EBS snapshot will be used to create new volume)
RESTORE_NAME="pvc-restore-${PVC_NAME}-$(date +%Y%m%d%H%M%S)"

velero restore create ${RESTORE_NAME} \
  --from-backup ${LATEST_BACKUP} \
  --include-namespaces ${TARGET_NAMESPACE} \
  --include-resources persistentvolumeclaims,persistentvolumes \
  --selector app=gitaly \
  --wait

# Monitor restore progress
velero restore describe ${RESTORE_NAME} --details

# Check PVC status (may take 5-10 min for EBS snapshot restore)
watch -n 10 kubectl get pvc ${PVC_NAME} -n ${TARGET_NAMESPACE}
# Expected: Bound (after EBS volume created from snapshot)

# Verify EBS volume created
PV_NAME=$(kubectl get pvc ${PVC_NAME} -n ${TARGET_NAMESPACE} -o jsonpath='{.spec.volumeName}')
kubectl describe pv ${PV_NAME} | grep VolumeHandle
# Expected: vol-XXXXXXXXXXXXXXXXX (EBS volume ID)
```

#### Step 5: Scale Up Workload and Validate (4 min)

```bash
# Scale deployment back up
kubectl scale deployment gitaly -n ${TARGET_NAMESPACE} --replicas=2

# Wait for pods ready
kubectl wait --for=condition=ready pod \
  -n ${TARGET_NAMESPACE} \
  -l app=gitaly \
  --timeout=300s

# Verify pod mounted PVC
kubectl get pods -n ${TARGET_NAMESPACE} -l app=gitaly -o json | \
  jq -r '.items[0].spec.volumes[] |
    select(.persistentVolumeClaim) |
    .persistentVolumeClaim.claimName'
# Expected: gitaly-data

# Test data integrity (example: GitLab Gitaly check)
kubectl exec -n ${TARGET_NAMESPACE} deployment/gitaly -- \
  df -h /home/git/data
# Expected: Volume mounted, data present

# Application-specific validation
kubectl logs -n ${TARGET_NAMESPACE} -l app=gitaly --tail=50 | grep -i error
# Expected: No critical errors
```

**Total Time**: ~20 minutes (3 identify + 2 scale down + 1 delete + 10 restore + 4 validate)

---

### Cross-Cluster Migration

**Use Case**: Migrate workloads to new cluster (DR, region migration)
**Prerequisites**: Two clusters accessible, Velero on both, S3 accessible from both
**Estimated Time**: 30 minutes (namespace), 90 minutes (full cluster)

#### Option A: Same S3 Bucket (Easiest)

```bash
# SOURCE CLUSTER CONTEXT
kubectl config use-context arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod

# Create backup on source cluster
SOURCE_BACKUP="migration-backup-$(date +%Y%m%d%H%M%S)"
velero backup create ${SOURCE_BACKUP} \
  --include-namespaces staging-platform-gitlab \
  --wait

# Verify backup in S3
aws s3 ls s3://${VELERO_BUCKET}/backups/${SOURCE_BACKUP}/

# TARGET CLUSTER CONTEXT
kubectl config use-context arn:aws:eks:us-west-2:891377105802:cluster/k8s-platform-prod-dr

# Install Velero on target cluster (pointing to SAME S3 bucket)
# (follow Step 2 from Full Cluster Restore, use same bucket)

# Wait for backup to sync (1-2 minutes)
velero backup get | grep ${SOURCE_BACKUP}

# Create restore on target cluster
TARGET_RESTORE="migration-restore-$(date +%Y%m%d%H%M%S)"
velero restore create ${TARGET_RESTORE} \
  --from-backup ${SOURCE_BACKUP} \
  --wait

# Validate resources on target cluster
kubectl get all -n staging-platform-gitlab
```

#### Option B: Cross-Bucket Migration (Different S3 Buckets)

```bash
# SOURCE CLUSTER: Create backup
SOURCE_BACKUP="migration-backup-$(date +%Y%m%d%H%M%S)"
velero backup create ${SOURCE_BACKUP} \
  --include-namespaces staging-platform-gitlab \
  --wait

# Download backup from source S3 to local
aws s3 sync \
  s3://k8s-platform-prod-velero-backups/backups/${SOURCE_BACKUP}/ \
  /tmp/velero-migration/${SOURCE_BACKUP}/ \
  --profile k8s-platform-staging

# Upload backup to target S3
aws s3 sync \
  /tmp/velero-migration/${SOURCE_BACKUP}/ \
  s3://k8s-platform-dr-velero-backups/backups/${SOURCE_BACKUP}/ \
  --profile k8s-platform-dr

# TARGET CLUSTER: Wait for sync, then restore
# (follow same restore steps as Option A)
```

**Total Time**: 30 minutes (single namespace), 90 minutes (full cluster with all PVCs)

---

### Selective Resource Restore

**Use Case**: Restore specific resources (ConfigMap, Secret) without full restore
**Estimated Time**: 5 minutes

```bash
# Example: Restore only ConfigMaps and Secrets for ArgoCD
BACKUP_NAME="daily-full-backup-20260225020000"
RESTORE_NAME="selective-restore-$(date +%Y%m%d%H%M%S)"

velero restore create ${RESTORE_NAME} \
  --from-backup ${BACKUP_NAME} \
  --include-namespaces argocd \
  --include-resources configmaps,secrets \
  --selector app.kubernetes.io/name=argocd-cm \
  --wait

# Verify resources restored
kubectl get configmap,secret -n argocd -l app.kubernetes.io/name=argocd-cm
```

---

## Validation

### Automated Validation Script

```bash
#!/bin/bash
# File: /tmp/velero-post-restore-validation.sh

set -euo pipefail

echo "=== Velero Post-Restore Validation ==="
echo "Started at: $(date)"
echo

# 1. Cluster accessibility
echo "1. Cluster Accessibility"
kubectl cluster-info --request-timeout=10s
echo "✓ Cluster accessible"
echo

# 2. Namespace count
echo "2. Namespace Count"
NS_COUNT=$(kubectl get namespaces --no-headers | wc -l)
echo "Total namespaces: ${NS_COUNT}"
if [ ${NS_COUNT} -lt 10 ]; then
  echo "⚠ WARNING: Low namespace count (expected ~17)"
fi
echo

# 3. Deployment readiness
echo "3. Deployment Readiness"
NOT_READY=$(kubectl get deployments --all-namespaces -o json | \
  jq -r '.items[] |
    select(.status.readyReplicas != .status.replicas) |
    "\(.metadata.namespace)/\(.metadata.name): \(.status.readyReplicas // 0)/\(.status.replicas)"')

if [ -z "$NOT_READY" ]; then
  echo "✓ All deployments ready"
else
  echo "⚠ Deployments not ready:"
  echo "$NOT_READY"
fi
echo

# 4. PVC status
echo "4. PVC Status"
NOT_BOUND=$(kubectl get pvc --all-namespaces --field-selector=status.phase!=Bound --no-headers 2>/dev/null || true)
if [ -z "$NOT_BOUND" ]; then
  echo "✓ All PVCs bound"
else
  echo "⚠ PVCs not bound:"
  echo "$NOT_BOUND"
fi
echo

# 5. Pod status
echo "5. Pod Status"
NOT_RUNNING=$(kubectl get pods --all-namespaces \
  --field-selector=status.phase!=Running,status.phase!=Succeeded \
  --no-headers 2>/dev/null | wc -l)
echo "Pods not running/succeeded: ${NOT_RUNNING}"
if [ ${NOT_RUNNING} -gt 5 ]; then
  echo "⚠ WARNING: Many pods not running"
  kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded
fi
echo

# 6. External Secrets (if ESO installed)
echo "6. External Secrets Sync"
if kubectl get crd externalsecrets.external-secrets.io >/dev/null 2>&1; then
  NOT_SYNCED=$(kubectl get externalsecrets --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] |
      select(.status.conditions[0].status != "True") |
      "\(.metadata.namespace)/\(.metadata.name)"' || true)

  if [ -z "$NOT_SYNCED" ]; then
    echo "✓ All External Secrets synced"
  else
    echo "⚠ External Secrets not synced:"
    echo "$NOT_SYNCED"
  fi
else
  echo "⊘ External Secrets Operator not installed"
fi
echo

# 7. Critical endpoints
echo "7. Critical Service Endpoints"
CRITICAL_INGRESSES=$(kubectl get ingress --all-namespaces -o json | \
  jq -r '.items[] |
    select(.metadata.labels.critical == "true") |
    "\(.metadata.namespace) \(.spec.rules[0].host)"' || true)

if [ -n "$CRITICAL_INGRESSES" ]; then
  while IFS= read -r line; do
    NS=$(echo $line | awk '{print $1}')
    HOST=$(echo $line | awk '{print $2}')
    STATUS=$(curl -o /dev/null -s -w "%{http_code}" -k https://${HOST} --max-time 10 || echo "TIMEOUT")
    if [[ "$STATUS" =~ ^(200|302|401)$ ]]; then
      echo "✓ ${NS}/${HOST}: ${STATUS}"
    else
      echo "✗ ${NS}/${HOST}: ${STATUS}"
    fi
  done <<< "$CRITICAL_INGRESSES"
else
  echo "⊘ No critical ingresses labeled"
fi
echo

echo "=== Validation Complete ==="
echo "Completed at: $(date)"
```

**Usage**:
```bash
bash /tmp/velero-post-restore-validation.sh | tee /tmp/validation-results-$(date +%Y%m%d%H%M%S).log
```

### Manual Critical Path Validation

```bash
# 1. Vault unsealed and accessible
kubectl exec -n staging-security-vault vault-0 -- vault status
# Expected: Sealed: false

# 2. External Secrets Operator syncing
kubectl get externalsecrets --all-namespaces | grep -v SecretSynced
# Expected: Empty (all synced)

# 3. Keycloak admin accessible
KEYCLOAK_POD=$(kubectl get pods -n staging-platform-keycloak -l app=keycloak -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n staging-platform-keycloak ${KEYCLOAK_POD} -- \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password $(kubectl get secret keycloak-admin-credentials -n staging-platform-keycloak -o jsonpath='{.data.password}' | base64 -d)
# Expected: Logged into 'http://localhost:8080' in realm 'master'

# 4. ArgoCD applications synced
kubectl exec -n argocd deployment/argocd-server -- \
  argocd app list -o json | \
  jq -r '.[] | select(.status.sync.status != "Synced") | .metadata.name'
# Expected: Empty (all apps synced)

# 5. Grafana datasources connected
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring ${GRAFANA_POD} -- \
  curl -s http://localhost:3000/api/datasources | jq -r '.[] | "\(.name): \(.type)"'
# Expected: Prometheus: prometheus, Loki: loki

# 6. Harbor registry push/pull test
docker login harbor.${CLUSTER_NAME}.example.com -u admin
docker pull alpine:3.19
docker tag alpine:3.19 harbor.${CLUSTER_NAME}.example.com/library/alpine:test
docker push harbor.${CLUSTER_NAME}.example.com/library/alpine:test
# Expected: Push successful

# 7. GitLab SSH clone test
git clone git@gitlab.${CLUSTER_NAME}.example.com:platform/test-repo.git /tmp/test-repo
# Expected: Repository cloned

# 8. SonarQube project scan
curl -u admin:admin https://sonarqube.${CLUSTER_NAME}.example.com/api/projects/search
# Expected: {"paging":{"pageIndex":1,...},"components":[...]}
```

---

## Troubleshooting

### Velero Pod CrashLoopBackOff

```bash
# Symptoms
kubectl get pods -n velero
# velero-xxxxx   0/1     CrashLoopBackOff

# Diagnosis
kubectl logs -n velero deploy/velero --tail=100

# Common causes and fixes:

# 1. IRSA role not attached
kubectl get sa velero-server -n velero -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
# Expected: arn:aws:iam::891377105802:role/k8s-platform-prod-velero-role
# Fix: Annotate service account
kubectl annotate sa velero-server -n velero \
  eks.amazonaws.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-velero-role \
  --overwrite

# 2. S3 bucket access denied
kubectl exec -n velero deploy/velero -- aws s3 ls s3://${VELERO_BUCKET}/
# Fix: Verify IAM role trust policy includes OIDC provider
aws iam get-role --role-name ${CLUSTER_NAME}-velero-role | \
  jq '.Role.AssumeRolePolicyDocument'

# 3. Plugin not loaded
kubectl logs -n velero deploy/velero -c velero-plugin-for-aws
# Fix: Reinstall Helm chart with initContainer for AWS plugin

# 4. Incorrect region configuration
kubectl get backupstoragelocation default -n velero -o yaml | grep region
# Fix: Must match S3 bucket region (us-east-1)
```

### Restore Stuck in "InProgress"

```bash
# Symptoms
velero restore get
# restore-xyz   InProgress   10 minutes ago

# Diagnosis
velero restore describe restore-xyz --details
velero restore logs restore-xyz | tail -100

# Common causes:

# 1. Resource conflicts (already exists)
# Error: "Deployment 'app' already exists"
# Fix: Delete existing resource or add --preserve-node-ports flag
kubectl delete deployment app -n namespace
velero restore delete restore-xyz --confirm
# Retry restore

# 2. PVC pending (StorageClass missing)
kubectl get pvc -n namespace
# Fix: Ensure StorageClass exists on target cluster
kubectl get storageclass
# Create if missing:
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
EOF

# 3. Namespace stuck in "Terminating"
kubectl get namespace namespace -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw "/api/v1/namespaces/namespace/finalize" -f -

# 4. VolumeSnapshot restore timeout
# Increase timeout in BackupStorageLocation
kubectl edit backupstoragelocation default -n velero
# Add: spec.config.resticTimeout: 4h
```

### S3 Access Denied Errors

```bash
# Symptoms
velero backup logs backup-xyz
# Error: "Access Denied" or "403 Forbidden"

# Diagnosis

# 1. Verify IRSA role ARN format (slash, not colon!)
kubectl get sa velero-server -n velero -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
# CORRECT: arn:aws:iam::891377105802:role/k8s-platform-prod-velero-role
# WRONG:   arn:aws:iam::891377105802:role:k8s-platform-prod-velero-role
#                                         ^
# Fix:
kubectl annotate sa velero-server -n velero \
  eks.amazonaws.com/role-arn=arn:aws:iam::891377105802:role/${CLUSTER_NAME}-velero-role \
  --overwrite
kubectl rollout restart deployment velero -n velero

# 2. Verify OIDC thumbprint
OIDC_URL=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.identity.oidc.issuer' --output text)
OIDC_ID=$(echo $OIDC_URL | sed 's/https:\/\///')

# Get current thumbprint
CURRENT_THUMBPRINT=$(aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ID} \
  --query 'ThumbprintList[0]' --output text)

echo "Current OIDC Thumbprint: ${CURRENT_THUMBPRINT}"

# Get real certificate thumbprint
REAL_THUMBPRINT=$(openssl s_client -connect ${OIDC_ID}:443 -servername ${OIDC_ID} -showcerts </dev/null 2>/dev/null | \
  openssl x509 -fingerprint -sha1 -noout | \
  cut -d'=' -f2 | \
  tr -d ':' | \
  tr '[:upper:]' '[:lower:]')

echo "Real Certificate Thumbprint: ${REAL_THUMBPRINT}"

# If different, update
if [ "${CURRENT_THUMBPRINT}" != "${REAL_THUMBPRINT}" ]; then
  echo "Thumbprints don't match! Updating..."
  aws iam update-open-id-connect-provider-thumbprint \
    --open-id-connect-provider-arn arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ID} \
    --thumbprint-list ${REAL_THUMBPRINT}
fi

# 3. Test IAM assume role from pod
kubectl exec -n velero deploy/velero -- aws sts get-caller-identity
# Expected: "Arn": "arn:aws:sts::891377105802:assumed-role/k8s-platform-prod-velero-role/..."
# If shows wrong identity, IRSA not working

# 4. Verify IAM policy permissions
aws iam get-role-policy \
  --role-name ${CLUSTER_NAME}-velero-role \
  --policy-name VeleroBackupPolicy
# Expected: s3:GetObject, s3:PutObject, s3:DeleteObject on bucket
```

### Backup Taking Too Long

```bash
# Symptoms
velero backup get
# backup-xyz   InProgress   45 minutes (normally 5-10 min)

# Diagnosis
velero backup logs backup-xyz --tail=50

# Common causes:

# 1. Large PVCs (100GB+) taking time to snapshot
# Check EBS snapshot progress in AWS Console:
# EC2 > Snapshots > Filter by "velero"
# Normal: 50GB = ~10 minutes, 500GB = ~1 hour

# 2. Too many resources
velero backup describe backup-xyz --details | grep "Total items"
# Fix: Exclude non-critical namespaces
velero backup create backup-selective \
  --include-namespaces staging-security-vault,argocd,staging-platform-gitlab \
  --exclude-resources events,endpoints

# 3. API rate limiting
kubectl logs -n velero deploy/velero | grep -i "rate limit"
# Fix: Reduce concurrent backups (--parallel-files-upload=1)

# 4. Network issues to S3
kubectl exec -n velero deploy/velero -- \
  aws s3 cp /tmp/test.txt s3://${VELERO_BUCKET}/test.txt --debug
# Check upload speed, adjust timeout if needed
```

### Cross-AZ Volume Restore Failures

```bash
# Symptoms
# Error: "PVC pending - volume zone mismatch"

# Diagnosis
kubectl describe pvc pvc-name -n namespace
# Events: "Failed to provision volume: zone mismatch"

# Root cause: EBS snapshots restored to wrong AZ

# Fix: Use StorageClass with volumeBindingMode: WaitForFirstConsumer
kubectl get storageclass gp3 -o yaml
# Ensure:
# volumeBindingMode: WaitForFirstConsumer
# allowedTopologies: (optional, can restrict to specific AZs)

# If StorageClass uses "Immediate", PVC may bind before pod scheduled
# Recreate PVC after pod scheduled to correct AZ
```

### Restore Fails with "Resource Already Exists"

```bash
# Symptoms
velero restore logs restore-xyz
# Error: "Deployment 'app' already exists in namespace 'ns'"

# Fix Options:

# Option 1: Delete existing resources first
kubectl delete deployment app -n namespace
velero restore delete restore-xyz --confirm
velero restore create restore-xyz-retry --from-backup backup-xyz --wait

# Option 2: Use restore with existing resource policy
velero restore create restore-xyz-update \
  --from-backup backup-xyz \
  --existing-resource-policy=update \
  --wait
# WARNING: Will overwrite existing resources!

# Option 3: Restore to different namespace
velero restore create restore-xyz-new \
  --from-backup backup-xyz \
  --include-namespaces original-namespace \
  --namespace-mappings original-namespace:new-namespace \
  --wait
```

---

## Post-Incident

### Incident Report Template

```markdown
# Incident Report: Velero Disaster Recovery

**Incident ID**: INC-YYYY-MM-DD-NNNN
**Date**: YYYY-MM-DD
**Duration**: X hours Y minutes
**RTO Achieved**: X minutes (target: 60 min)
**RPO Achieved**: X hours (target: 24 hours)
**Impact**: [P0/P1/P2] - [Service/Namespace] unavailable

---

## Summary

[1-2 sentence summary of what happened]

---

## Timeline

| Time (UTC) | Event |
|------------|-------|
| HH:MM | Incident detected (monitoring alert / user report) |
| HH:MM | Incident acknowledged, DR procedure initiated |
| HH:MM | Velero backup identified: `backup-name` |
| HH:MM | Restore started: `restore-name` |
| HH:MM | Restore completed (Phase: Completed/PartiallyFailed) |
| HH:MM | Validation started |
| HH:MM | Critical services accessible |
| HH:MM | All services restored, incident resolved |
| HH:MM | Post-incident review scheduled |

**Total Incident Duration**: X hours Y minutes
**Actual RTO**: X minutes (Y% of target)

---

## Root Cause

**Primary Cause**: [e.g., Accidental namespace deletion via `kubectl delete`]

**Contributing Factors**:
- [e.g., No confirmation prompt in kubectl]
- [e.g., Insufficient RBAC restrictions on production namespaces]
- [e.g., No pre-delete validation webhook]

**Detection**: [How was incident detected? Monitoring, user report, etc.]

---

## Impact Assessment

**Affected Services**:
- Service 1: [unavailable/degraded] - X users impacted
- Service 2: [unavailable/degraded] - Y requests failed

**Data Loss**:
- RPO: [X hours] - Data between [last backup time] and [incident time] lost
- PVCs: [N] persistent volumes restored from snapshots
- Databases: [RDS/External] - separate backup system, no data loss

**Business Impact**:
- Revenue: $X estimated (if applicable)
- SLA: [met/breached] - [service] SLA is 99.9% uptime
- Customer impact: [N] users unable to access service

---

## Resolution Steps

1. **Backup Selection**:
   - Backup used: `${LATEST_BACKUP}`
   - Backup age: X hours
   - Backup size: X GB
   - Restore time: Y minutes

2. **Restore Procedure**:
   - Restore type: [Full Cluster / Namespace / Application / Volume]
   - Velero restore command: `velero restore create ...`
   - Errors encountered: [None / List errors]
   - Workarounds applied: [None / Describe]

3. **Validation**:
   - Namespaces restored: X/X
   - Deployments ready: X/X
   - PVCs bound: X/X
   - External Secrets synced: X/X
   - Critical endpoints accessible: X/X

---

## Lessons Learned

### What Went Well
- [e.g., Velero backups were recent (< 6 hours)]
- [e.g., IRSA authentication worked without credential issues]
- [e.g., Restore completed within RTO target]
- [e.g., Team responded quickly, followed runbook]

### What Could Be Improved
- [e.g., Detection took 15 minutes - need better monitoring]
- [e.g., Runbook had outdated backup names - needs maintenance]
- [e.g., Validation script failed on non-critical resources]

### Action Items

| Action | Owner | Due Date | Status |
|--------|-------|----------|--------|
| [e.g., Add `kubectl delete` confirmation alias] | Platform Team | YYYY-MM-DD | Open |
| [e.g., Implement admission webhook to block namespace deletion] | Security Team | YYYY-MM-DD | Open |
| [e.g., Increase backup frequency to hourly for all namespaces] | SRE | YYYY-MM-DD | Open |
| [e.g., Schedule DR drill for full cluster restore] | Platform Team | YYYY-MM-DD | Open |

---

## Attachments

- Velero backup logs: `backup-xyz.log`
- Velero restore logs: `restore-xyz.log`
- Validation results: `validation-results-YYYYMMDDHHMMSS.log`
- Incident Slack thread: [Link to #incident-YYYY-MM-DD]

---

**Report Author**: [Name]
**Reviewed By**: [CTO/Platform Lead]
**Date**: YYYY-MM-DD
```

### DR Testing Schedule

```bash
# Quarterly DR drill to validate restore procedures

# Q1 2026 (March): Namespace restore drill
# - Target: staging-platform-gitlab
# - Duration: 15 minutes
# - Success criteria: All resources restored, CI/CD functional

# Q2 2026 (June): Application corruption scenario
# - Target: SonarQube (intentional bad config)
# - Duration: 10 minutes
# - Success criteria: Application rolled back, scans functional

# Q3 2026 (September): Volume restore drill
# - Target: Gitaly PVC (50GB)
# - Duration: 20 minutes
# - Success criteria: Data restored, git clone functional

# Q4 2026 (December): Full cluster restore drill (NEW CLUSTER)
# - Target: Create dr-cluster, restore from prod backups
# - Duration: 90 minutes
# - Success criteria: All services functional, <2 hour RTO
```

### Runbook Maintenance

```bash
# Update runbook after each incident or DR drill

# 1. Update timestamps
sed -i 's/Last Updated: .*/Last Updated: '$(date +%Y-%m-%d)'/' velero-disaster-recovery.md

# 2. Add new troubleshooting section (if new issue discovered)
# 3. Update estimated times (if actual times differ significantly)
# 4. Add new disaster scenarios (if new incident type)
# 5. Update cluster configuration (if infrastructure changes)

# 6. Commit changes
git add docs/runbooks/velero-disaster-recovery.md
git commit -m "docs: update Velero DR runbook after INC-YYYY-MM-DD"
```

---

## Appendix

### Backup Schedule Reference

| Schedule | Cron | Retention | Namespaces | Purpose |
|----------|------|-----------|------------|---------|
| `daily-full-backup` | `0 2 * * *` | 7 days | All (except kube-system) | Daily full cluster backup |
| `weekly-pvc-backup` | `0 3 * * 0` | 30 days | All PVCs | Long-term volume backup |
| `hourly-critical-backup` | `0 * * * *` | 24 hours | staging-security-vault, argocd, keycloak, gitlab-staging | Critical namespace backup (1h RPO) |
| `monthly-archive-backup` | `0 4 1 * *` | 365 days | All (including kube-system) | Compliance archive |

### S3 Bucket Structure

```
s3://k8s-platform-prod-velero-backups/
├── backups/
│   ├── daily-full-backup-20260225020000/
│   │   ├── velero-backup.json
│   │   ├── <resource>.json.gz
│   │   └── <resource>-volumesnapshots.json.gz
│   ├── hourly-critical-backup-20260225100000/
│   └── ...
├── restores/
│   ├── full-cluster-restore-20260225143022/
│   └── ...
└── metadata/
    └── ...

# Lifecycle:
# - Standard storage: First 14 days
# - Glacier storage: After 14 days (transition rule)
# - Deletion: After 365 days (compliance archives retained)
```

### IAM Role Reference

```json
{
  "RoleName": "k8s-platform-prod-velero-role",
  "AssumeRolePolicyDocument": {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::891377105802:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/XXXXXXXX"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-east-1.amazonaws.com/id/XXXXXXXX:sub": "system:serviceaccount:velero:velero-server"
        }
      }
    }]
  },
  "Policies": ["VeleroBackupPolicy"]
}
```

### Useful Links

- **Velero Documentation**: https://velero.io/docs/v1.15/
- **AWS IRSA Guide**: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
- **Velero GitHub Issues**: https://github.com/vmware-tanzu/velero/issues
- **Velero Slack**: https://kubernetes.slack.com/messages/velero
- **Internal Docs**:
  - ADR-079: Velero IRSA Migration
  - Logbook: 2026-02-25-v008-velero-irsa.md
  - Troubleshooting: velero-irsa-solution-2026-02-25.md

---

**Document Version**: 1.0
**Last Tested**: 2026-02-25
**Next Review**: 2026-03-25
**Next DR Drill**: 2026-03 (Quarterly)
