# Disaster Recovery Runbook - Velero Backup/Restore

**Version**: 1.0
**Last Updated**: 2026-02-25
**Owner**: Platform Team
**Escalation**: CTO

---

## Overview

This runbook provides step-by-step procedures for disaster recovery using Velero backup/restore.

**SLA Targets**:
- **RTO (Recovery Time Objective)**: 1 hour
- **RPO (Recovery Point Objective)**: 24 hours (daily backups)
- **RPO (Critical Namespaces)**: 1 hour (hourly backups)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Backup Verification](#backup-verification)
3. [Disaster Scenarios](#disaster-scenarios)
4. [Restore Procedures](#restore-procedures)
5. [Validation](#validation)
6. [Rollback](#rollback)
7. [Post-Incident](#post-incident)

---

## Prerequisites

### Required Access

```bash
# AWS SSO authentication
aws sso login --profile k8s-platform-staging

# Kubernetes cluster access
kubectl cluster-info
kubectl get nodes

# Velero CLI installation
velero version
# Expected: Client v1.15.1, Server v1.15.1
```

### Required Tools

- `kubectl` v1.34+
- `velero` CLI v1.15+
- `aws` CLI v2.x
- `jq` for JSON parsing

### Environment Variables

```bash
export AWS_PROFILE=k8s-platform-staging
export KUBECONFIG=~/.kube/config
export VELERO_NAMESPACE=velero
```

---

## Backup Verification

### Check Backup Schedules

```bash
# List all backup schedules
kubectl get schedules -n velero

# Expected output:
# NAME                      STATUS    SCHEDULE      PAUSED
# daily-full-backup         Enabled   0 2 * * *     false
# weekly-pvc-backup         Enabled   0 3 * * 0     false
# hourly-critical-backup    Enabled   0 * * * *     false
# monthly-archive-backup    Enabled   0 4 1 * *     false
```

### List Available Backups

```bash
# List all backups
velero backup get

# Filter by schedule
velero backup get --selector backup-schedule=daily-full

# Get backup details
velero backup describe <backup-name> --details
```

### Verify Backup Completion

```bash
# Check backup status
velero backup get <backup-name> -o jsonpath='{.status.phase}'
# Expected: Completed

# Check backup expiration
velero backup get <backup-name> -o jsonpath='{.status.expiration}'

# Check backup size and duration
velero backup logs <backup-name> | grep -E "Backup completed|errors encountered"
```

### S3 Bucket Verification

```bash
# List backups in S3
aws s3 ls s3://k8s-platform-staging-velero-backups-891377105802/ --recursive | grep backups

# Check backup metadata
aws s3api head-object \
  --bucket k8s-platform-staging-velero-backups-891377105802 \
  --key backups/<backup-name>/velero-backup.json
```

---

## Disaster Scenarios

### Scenario 1: Complete Cluster Loss

**Symptoms**:
- Cluster unreachable
- All nodes down
- Control plane unavailable

**Recovery Procedure**: [Full Cluster Restore](#full-cluster-restore)

**Estimated RTO**: 60 minutes

---

### Scenario 2: Namespace Deletion

**Symptoms**:
- Namespace accidentally deleted
- All resources in namespace lost
- Applications unavailable

**Recovery Procedure**: [Namespace Restore](#namespace-restore)

**Estimated RTO**: 15 minutes

---

### Scenario 3: Single Application Failure

**Symptoms**:
- Application misconfigured
- Deployment corrupted
- Need to rollback to previous state

**Recovery Procedure**: [Application Restore](#application-restore)

**Estimated RTO**: 10 minutes

---

### Scenario 4: Persistent Volume Data Loss

**Symptoms**:
- PVC deleted
- Volume data corrupted
- Storage failure

**Recovery Procedure**: [Volume Restore](#volume-restore)

**Estimated RTO**: 20 minutes

---

## Restore Procedures

### Full Cluster Restore

**Use Case**: Complete cluster rebuild after catastrophic failure

**Steps**:

1. **Provision New Cluster** (if needed)

```bash
# Apply Terraform to create new EKS cluster
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform
terraform plan
terraform apply
```

2. **Install Velero on New Cluster**

```bash
# Add Helm repo
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Get IAM role ARN from Terraform
VELERO_ROLE_ARN=$(terraform output -raw velero_role_arn)
VELERO_BUCKET=$(terraform output -raw velero_bucket_name)

# Install Velero
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set credentials.useSecret=false \
  --set serviceAccount.server.annotations."eks\.amazonaws\.com/role-arn"=${VELERO_ROLE_ARN} \
  --set configuration.backupStorageLocation[0].bucket=${VELERO_BUCKET} \
  --set configuration.backupStorageLocation[0].config.region=us-east-1 \
  --set configuration.volumeSnapshotLocation[0].config.region=us-east-1 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.11.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins

# Wait for Velero to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n velero --timeout=300s
```

3. **Verify Backup Sync**

```bash
# Check backup storage location
velero backup-location get

# List available backups (should sync from S3)
velero backup get

# Wait for backups to appear (may take 1-2 minutes)
watch -n 10 velero backup get
```

4. **Select Backup to Restore**

```bash
# Find latest successful daily backup
LATEST_BACKUP=$(velero backup get --selector backup-schedule=daily-full -o json | \
  jq -r '.items | sort_by(.status.completionTimestamp) | reverse | .[0].metadata.name')

echo "Latest backup: ${LATEST_BACKUP}"

# Verify backup is complete
velero backup describe ${LATEST_BACKUP}
```

5. **Create Restore**

```bash
# Create restore from backup
velero restore create full-cluster-restore \
  --from-backup ${LATEST_BACKUP} \
  --wait

# Monitor restore progress
velero restore describe full-cluster-restore --details

# Watch restore logs
velero restore logs full-cluster-restore
```

6. **Verify Restore**

```bash
# Check all namespaces restored
kubectl get namespaces

# Check critical deployments
kubectl get deployments --all-namespaces

# Check PVCs restored
kubectl get pvc --all-namespaces

# Check pods running
kubectl get pods --all-namespaces --field-selector=status.phase!=Running
```

**Estimated Time**: 60 minutes

---

### Namespace Restore

**Use Case**: Restore a single deleted namespace

**Steps**:

1. **Identify Backup**

```bash
# Find latest backup containing the namespace
NAMESPACE_TO_RESTORE="gitlab-staging"

velero backup get --selector backup-schedule=daily-full
```

2. **Create Restore for Specific Namespace**

```bash
# Create restore for single namespace
velero restore create ${NAMESPACE_TO_RESTORE}-restore \
  --from-backup ${LATEST_BACKUP} \
  --include-namespaces ${NAMESPACE_TO_RESTORE} \
  --wait

# Monitor restore
velero restore describe ${NAMESPACE_TO_RESTORE}-restore
```

3. **Verify Namespace Resources**

```bash
# Check namespace exists
kubectl get namespace ${NAMESPACE_TO_RESTORE}

# Check all resources restored
kubectl get all -n ${NAMESPACE_TO_RESTORE}

# Check PVCs
kubectl get pvc -n ${NAMESPACE_TO_RESTORE}

# Check secrets
kubectl get secrets -n ${NAMESPACE_TO_RESTORE}
```

**Estimated Time**: 15 minutes

---

### Application Restore

**Use Case**: Rollback application to previous state

**Steps**:

1. **Identify Backup Before Incident**

```bash
# List backups with timestamps
velero backup get -o json | jq -r '.items[] | "\(.metadata.name) - \(.status.completionTimestamp)"'

# Select backup before incident
BACKUP_NAME="daily-full-backup-20260224020000"
```

2. **Delete Current Application** (optional)

```bash
# Scale down deployment first
kubectl scale deployment <app-deployment> -n <namespace> --replicas=0

# Or delete resources
kubectl delete deployment <app-deployment> -n <namespace>
```

3. **Restore Specific Resources**

```bash
# Restore only specific resources (e.g., deployments, services)
velero restore create app-restore-$(date +%s) \
  --from-backup ${BACKUP_NAME} \
  --include-namespaces <namespace> \
  --include-resources deployments,services,configmaps,secrets \
  --selector app=<app-label> \
  --wait
```

4. **Verify Application**

```bash
# Check deployment status
kubectl rollout status deployment/<app-deployment> -n <namespace>

# Check pod logs
kubectl logs -n <namespace> -l app=<app-label> --tail=50

# Test application endpoint
curl https://<app-url>/health
```

**Estimated Time**: 10 minutes

---

### Volume Restore

**Use Case**: Restore persistent volume data

**Steps**:

1. **Identify Backup with Volume**

```bash
# Find backup with PVC
PVC_NAME="gitlab-data"
NAMESPACE="gitlab-staging"

velero backup get --selector backup-schedule=weekly-pvc
```

2. **Delete Existing PVC** (if corrupted)

```bash
# Scale down workload using PVC
kubectl scale deployment <deployment> -n ${NAMESPACE} --replicas=0

# Delete PVC (will delete PV if ReclaimPolicy=Delete)
kubectl delete pvc ${PVC_NAME} -n ${NAMESPACE}
```

3. **Restore PVC from Backup**

```bash
# Restore PVC only
velero restore create pvc-restore-$(date +%s) \
  --from-backup ${BACKUP_NAME} \
  --include-namespaces ${NAMESPACE} \
  --include-resources persistentvolumeclaims,persistentvolumes \
  --selector app=gitlab \
  --wait

# Monitor EBS snapshot restore
kubectl describe pvc ${PVC_NAME} -n ${NAMESPACE}
```

4. **Scale Up Workload**

```bash
# Scale deployment back up
kubectl scale deployment <deployment> -n ${NAMESPACE} --replicas=2

# Verify pod mounts PVC
kubectl get pods -n ${NAMESPACE} -o jsonpath='{.items[*].spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}'
```

**Estimated Time**: 20 minutes

---

## Validation

### Post-Restore Validation Checklist

```bash
# 1. All namespaces present
kubectl get namespaces | wc -l
# Expected: ~15-20 namespaces

# 2. All deployments ready
kubectl get deployments --all-namespaces -o json | \
  jq -r '.items[] | select(.status.readyReplicas != .status.replicas) | "\(.metadata.namespace)/\(.metadata.name)"'
# Expected: empty output (all deployments ready)

# 3. All PVCs bound
kubectl get pvc --all-namespaces --field-selector=status.phase!=Bound
# Expected: empty output (all PVCs bound)

# 4. All pods running
kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded
# Expected: only jobs/completed pods

# 5. Critical services accessible
kubectl get svc --all-namespaces -l critical=true

# 6. External secrets synced
kubectl get externalsecrets --all-namespaces -o json | \
  jq -r '.items[] | select(.status.conditions[0].status != "True") | "\(.metadata.namespace)/\(.metadata.name)"'
# Expected: empty output (all secrets synced)

# 7. Database connectivity
kubectl exec -n gitlab-staging deployment/gitlab-sidekiq -- \
  gitlab-rake gitlab:db:check
# Expected: Database available

# 8. SSO integration
curl -I https://keycloak.example.com/realms/platform/.well-known/openid-configuration
# Expected: 200 OK
```

### Application-Specific Validation

```bash
# Grafana
curl -I https://grafana.example.com/api/health
# Expected: 200 OK

# ArgoCD
kubectl exec -n argocd deployment/argocd-server -- argocd app list
# Expected: List of applications

# Harbor
curl -I https://harbor.example.com/api/v2.0/health
# Expected: 200 OK

# GitLab
curl -I https://gitlab.example.com/-/health
# Expected: 200 OK

# Vault
kubectl exec -n staging-security-vault vault-0 -- vault status
# Expected: Sealed: false
```

---

## Rollback

### Rollback Failed Restore

If restore causes issues, rollback:

```bash
# 1. Delete restored resources
velero restore delete <restore-name> --confirm

# 2. Manually delete restored namespace (if needed)
kubectl delete namespace <namespace> --force --grace-period=0

# 3. Restore from different backup
velero restore create rollback-restore \
  --from-backup <previous-backup> \
  --include-namespaces <namespace> \
  --wait

# 4. Verify rollback successful
kubectl get all -n <namespace>
```

---

## Post-Incident

### Documentation

1. **Create Incident Report**

```markdown
# Incident Report

**Date**: YYYY-MM-DD
**Duration**: X hours
**Impact**: <namespaces/services affected>
**Root Cause**: <cause of disaster>
**Backup Used**: <backup-name>
**RTO Achieved**: X minutes
**RPO Achieved**: X hours

## Timeline
- HH:MM - Incident detected
- HH:MM - DR procedure initiated
- HH:MM - Backup selected
- HH:MM - Restore started
- HH:MM - Restore completed
- HH:MM - Validation completed
- HH:MM - Services restored

## Lessons Learned
- <what went well>
- <what could be improved>
- <action items>
```

2. **Update Runbook**

- Document any deviations from procedure
- Add new troubleshooting steps
- Update estimated times based on actual

3. **Test Restore Procedure**

- Schedule restore test within 1 week
- Use test namespace to avoid production impact
- Validate all steps still accurate

---

## Troubleshooting

### Velero Pod Not Running

```bash
# Check pod status
kubectl get pods -n velero

# Check logs
kubectl logs -n velero deployment/velero -f

# Common issues:
# - IRSA role not attached: Check serviceAccount annotations
# - S3 bucket access denied: Verify IAM policy
# - Plugin not loaded: Check init container logs
```

### Backup Not Completing

```bash
# Check backup status
velero backup describe <backup-name> --details

# Check backup logs
velero backup logs <backup-name>

# Common issues:
# - Volume snapshot timeout: Increase timeout in schedule
# - Resource too large: Exclude large resources
# - API rate limiting: Reduce concurrent backups
```

### Restore Stuck

```bash
# Check restore status
velero restore describe <restore-name> --details

# Check restore logs
velero restore logs <restore-name>

# Common issues:
# - Resource conflicts: Delete existing resources first
# - PVC pending: Check storage class exists
# - Namespace in Terminating state: Force delete finalizers
```

### S3 Access Denied

```bash
# Verify IRSA role
kubectl get sa velero-server -n velero -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Test IAM assume role
aws sts assume-role --role-arn <velero-role-arn> --role-session-name test

# Verify S3 permissions
aws s3 ls s3://<velero-bucket>/ --profile k8s-platform-staging

# Common issues:
# - IRSA trust policy incorrect: Update OIDC provider condition
# - S3 bucket policy blocking: Check bucket policy
# - IAM policy missing permissions: Add required S3 actions
```

---

## Contact Information

**Primary Contact**: Platform Team
**Escalation**: CTO
**Velero Support**: VMware Tanzu Community

**Useful Links**:
- Velero Documentation: https://velero.io/docs/
- GitHub Issues: https://github.com/vmware-tanzu/velero/issues
- Slack Community: https://kubernetes.slack.com/messages/velero

---

**Document Version**: 1.0
**Last Tested**: 2026-02-25
**Next Review**: 2026-03-25
