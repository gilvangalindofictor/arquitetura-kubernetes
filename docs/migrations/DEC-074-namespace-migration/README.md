# DEC-074: Namespace Migration Master Plan

**Status:** PROPOSED (2026-02-24)
**Target Execution:** 2026-02-25 to 2026-03-05 (7 working days)
**Total Namespaces:** 16 migrations + 1 deprecation

---

## Quick Links

| Document | Purpose | For |
|----------|---------|-----|
| [01-namespace-mapping.md](./01-namespace-mapping.md) | Complete mapping: old → new names | All stakeholders |
| [02-dependency-graph.md](./02-dependency-graph.md) | Service dependencies & migration order | Architects, SREs |
| [03-migration-patterns.md](./03-migration-patterns.md) | Migration strategies by workload type | Engineers executing migrations |
| [04-execution-plan.md](./04-execution-plan.md) | Detailed timeline, waves, validation | Project managers, engineers |
| [05-risk-register.md](./05-risk-register.md) | Risk assessment & mitigation | Risk managers, leadership |
| [06-ADR-074.md](./06-ADR-074.md) | Architectural Decision Record | Architects, compliance |
| [scripts/](./scripts/) | Automated migration scripts | Engineers executing migrations |

---

## Executive Summary

### Problem

**17 of 18 namespaces (94%)** in the EKS staging cluster do not conform to GAP-009 Kyverno governance policy for deterministic naming.

**Required Pattern:** `{env}-{domain}-{product}`
**Example:** `staging-platform-argocd` (not `argocd`)

**Impact:**
- Kyverno policies cannot enforce naming (audit mode only)
- Multi-cluster scaling blocked (namespace name collisions)
- Operational confusion (no environment visible in name)
- Cost allocation unclear (names don't match labels)

### Solution

**Migrate all 17 non-conformant namespaces** to deterministic pattern over **5 waves (7 working days)**.

**Key Metrics:**
- **Total Downtime:** 9 hours (staged over 7 days)
- **Total Execution Time:** 40 hours (optimized with parallelization)
- **Risk Level:** 1 CRITICAL, 4 HIGH, 4 MEDIUM, 7 LOW
- **Cost Impact:** $2,500 (dev team blocked hours)
- **Success Rate Target:** 100% (zero rollbacks)

### Timeline

```
2026-02-25 (Tue): Wave 1 + 2 (8 namespaces, 6h) - LOW risk
2026-02-26 (Wed): Wave 3 (2 namespaces, 7h) - HIGH risk (Vault + data-services)
2026-02-27 (Thu): Wave 4 (3 namespaces, 7h) - MEDIUM risk (Keycloak, ArgoCD, SonarQube)
2026-02-28 (Fri): Wave 5 + 6 (3 namespaces, 13h) - HIGH/CRITICAL risk (Harbor, Monitoring, GitLab)
2026-03-05 (Wed): Cleanup (1 namespace deprecation)
```

---

## Migration Overview

### Namespace Mapping Summary

| Domain | Namespaces | Examples |
|--------|-----------|----------|
| platform | 7 | argocd → staging-platform-argocd |
| data | 3 | data-services → staging-data-infrastructure |
| observability | 2 | monitoring → staging-observability-monitoring |
| security | 3 | vault-system → staging-security-vault |
| governance | 2 | kyverno → staging-governance-kyverno |
| **TOTAL** | **17** | |

### Risk Breakdown

| Risk Level | Count | Namespaces |
|-----------|-------|-----------|
| CRITICAL | 1 | gitlab-staging (50GB PVC, source code) |
| HIGH | 4 | vault-system, data-services, harbor-system, monitoring |
| MEDIUM | 4 | argocd, keycloak, kyverno, sonarqube, rabbitmq-system |
| LOW | 7 | cert-manager, external-secrets-system, redis-operator, tests |

### Migration Patterns

| Pattern | Description | Count | Examples |
|---------|-------------|-------|----------|
| A | Stateless services | 7 | cert-manager, kyverno, redis-operator |
| B | External RDS (stateless pods) | 2 | argocd, keycloak |
| C | StatefulSets + PVCs (HIGH RISK) | 5 | gitlab, harbor, monitoring, sonarqube, vault |
| D | Operator-managed CRDs | 2 | data-services, rabbitmq-system |

---

## Getting Started

### Prerequisites

**Tools Required:**
```bash
# Check prerequisites
kubectl version --client  # v1.28+
helm version             # v3.12+
jq --version             # 1.6+
aws --version            # awscli 2.x (for RDS snapshots)
```

**Permissions Required:**
- Cluster admin (namespace create/delete)
- VolumeSnapshot create/delete
- AWS RDS manual snapshots (for Pattern B/C with external databases)

**Verification:**
```bash
# Verify cluster access
kubectl cluster-info
kubectl get nodes

# Verify VolumeSnapshotClass
kubectl get volumesnapshotclass ebs-csi-snapshot-class

# Verify namespaces to migrate
kubectl get namespaces | grep -E "(argocd|harbor|gitlab|vault|keycloak|monitoring)"
```

---

## Execution Workflow

### Step 1: Pre-Migration Review (Day 0)

**Read Documentation:**
1. [01-namespace-mapping.md](./01-namespace-mapping.md) - Understand naming decisions
2. [02-dependency-graph.md](./02-dependency-graph.md) - Review dependencies
3. [03-migration-patterns.md](./03-migration-patterns.md) - Select pattern for namespace
4. [05-risk-register.md](./05-risk-register.md) - Understand risks

**Preparation:**
```bash
# Clone repository
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/migrations/DEC-074-namespace-migration

# Make scripts executable
chmod +x scripts/*.sh

# Test Pattern A (stateless) on low-risk namespace first
./scripts/migrate-stateless.sh test-governance staging-governance-test <helm-release> <helm-chart>
```

---

### Step 2: Wave Execution (Days 1-5)

**Wave 1: Foundation Layer (2026-02-25 AM)**
```bash
# Parallel execution (3 agents)
# Agent 1:
./scripts/migrate-stateless.sh cert-manager staging-security-certmanager cert-manager jetstack/cert-manager

# Agent 2:
./scripts/migrate-stateless.sh external-secrets-system staging-security-externalsecrets external-secrets external-secrets/external-secrets

# Agent 3:
./scripts/migrate-stateless.sh redis-operator staging-data-redis-operator redis-operator ot-helm/redis-operator

# Validate all 3 before proceeding
```

**Wave 3: Vault (CRITICAL PATH) (2026-02-26 AM)**
```bash
# HIGH RISK: Backup Vault FIRST
kubectl exec -n vault-system vault-0 -- vault operator raft snapshot save /tmp/vault-backup.snap
kubectl cp vault-system/vault-0:/tmp/vault-backup.snap ./vault-backup-$(date +%Y%m%d).snap
aws s3 cp ./vault-backup-*.snap s3://k8s-platform-backups/vault/

# Execute migration
./scripts/migrate-stateful-pvc.sh vault-system staging-security-vault vault hashicorp/vault

# CRITICAL: Unseal Vault after migration
kubectl exec -n staging-security-vault vault-0 -- vault operator unseal <key-1>
kubectl exec -n staging-security-vault vault-0 -- vault operator unseal <key-2>
kubectl exec -n staging-security-vault vault-0 -- vault operator unseal <key-3>

# Validate ESO sync
kubectl get externalsecrets -A | grep -v SecretSynced
```

**Wave 6: GitLab (CRITICAL) (2026-02-28 18:00-22:00)**
```bash
# MAINTENANCE WINDOW REQUIRED
# Notify users 1 week in advance

# Pre-migration (17:00-18:00)
# - Backup RDS: AWS Console manual snapshot
# - Pause CI runners: kubectl scale deployment gitlab-runner -n gitlab-staging --replicas=0
# - Export Helm values: helm get values k8s-platform-prod-gitlab -n gitlab-staging > gitlab-values.yaml

# Execute migration (18:00-20:00)
./scripts/migrate-stateful-pvc.sh gitlab-staging staging-platform-gitlab k8s-platform-prod-gitlab gitlab/gitlab

# Data integrity validation (20:00-21:00)
# - Git clone test: git clone https://gitlab.staging.internal/test-repo.git
# - Repository count: curl https://gitlab.staging.internal/api/v4/projects | jq length
# - CI pipeline test: Trigger test job

# If validation passes: Continue
# If validation fails: ROLLBACK
./scripts/rollback.sh staging-platform-gitlab gitlab-staging
```

---

### Step 3: Validation (Days 6-21)

**Immediate (0-1h):**
- [ ] All pods Running: `kubectl get pods -n <new-namespace>`
- [ ] PVCs Bound: `kubectl get pvc -n <new-namespace>`
- [ ] Ingress HTTP 200: `curl -I https://<ingress-endpoint>`
- [ ] Logs clean: `kubectl logs -n <new-namespace> --all-containers --tail=100`

**7-Day Validation (LOW/MEDIUM risk):**
- [ ] Zero incidents
- [ ] Application functionality validated
- [ ] Delete old namespace: `kubectl delete namespace <old-namespace>`

**14-Day Validation (HIGH/CRITICAL risk):**
- [ ] GitLab, Vault, Harbor, Monitoring validated
- [ ] Delete old namespace
- [ ] Delete VolumeSnapshots: `kubectl delete volumesnapshot -n <old-namespace> --all`

---

## Rollback Procedures

### When to Rollback

**Immediate Rollback Triggers:**
- CrashLoopBackOff pods (>5 minutes)
- Data integrity validation fails
- Ingress 502/503 (>30 minutes)
- ExternalSecrets fail to sync (Vault connection)

### How to Rollback

**Automated Rollback:**
```bash
./scripts/rollback.sh <new-namespace> <old-namespace>

# Example:
./scripts/rollback.sh staging-platform-harbor harbor-system

# With snapshot cleanup:
./scripts/rollback.sh staging-platform-harbor harbor-system delete-snapshots
```

**Manual Rollback:**
```bash
# 1. Delete new namespace
kubectl delete namespace <new-namespace>

# 2. Verify old namespace operational
kubectl get pods -n <old-namespace>

# 3. Test ingress endpoints
curl -I https://<old-ingress-endpoint>
```

---

## Troubleshooting

### Issue: VolumeSnapshot Stuck in "Pending"

**Symptom:**
```bash
kubectl get volumesnapshot -n <namespace>
NAME                     AGE   READY
gitlab-gitaly-snapshot   10m   false
```

**Solution:**
```bash
# Check VolumeSnapshotContent
kubectl describe volumesnapshot gitlab-gitaly-snapshot -n <namespace>

# Common causes:
# 1. EBS CSI driver not installed: kubectl get pods -n kube-system | grep ebs-csi
# 2. VolumeSnapshotClass missing: kubectl get volumesnapshotclass
# 3. PVC not bound: kubectl get pvc -n <namespace>

# Fix: Verify EBS CSI driver
kubectl get csidriver ebs.csi.aws.com
```

---

### Issue: Pods CrashLoopBackOff After Migration

**Symptom:**
```bash
kubectl get pods -n staging-platform-harbor
NAME                    READY   STATUS             RESTARTS
harbor-core-xxx         0/1     CrashLoopBackOff   5
```

**Solution:**
```bash
# Check logs
kubectl logs -n staging-platform-harbor harbor-core-xxx --tail=50

# Common causes:
# 1. PVC mount failure: Check PVC status (kubectl get pvc)
# 2. External RDS connection: Check connection string in ExternalSecret
# 3. Missing environment variables: Compare old vs new deployment

# Validate PVC mount
kubectl describe pod harbor-core-xxx -n staging-platform-harbor | grep -A 5 "Volumes:"

# Check ExternalSecret
kubectl get externalsecrets -n staging-platform-harbor
kubectl describe externalsecret harbor-postgresql-credentials -n staging-platform-harbor
```

---

### Issue: Ingress Returns 502 Bad Gateway

**Symptom:**
```bash
curl -I https://harbor.staging.internal
HTTP/2 502
```

**Solution:**
```bash
# Check pod status (backend must be Running)
kubectl get pods -n staging-platform-harbor

# Check service endpoints
kubectl get endpoints -n staging-platform-harbor harbor

# Check ingress configuration
kubectl describe ingress harbor -n staging-platform-harbor

# Common causes:
# 1. Pods not Running: Wait for PVC mount (large PVCs take 10-30min)
# 2. Service selector mismatch: Verify service labels match pods
# 3. DNS propagation: Wait 5-10 minutes for ALB DNS update

# Force ingress reconciliation
kubectl annotate ingress harbor -n staging-platform-harbor reconcile="$(date +%s)"
```

---

### Issue: ExternalSecrets Not Syncing

**Symptom:**
```bash
kubectl get externalsecrets -n staging-platform-harbor
NAME                    READY   STATUS
harbor-oidc-credentials False   SecretSyncError
```

**Solution:**
```bash
# Check ESO logs
kubectl logs -n staging-security-externalsecrets deployment/external-secrets -f

# Check Vault connection
kubectl exec -n staging-security-vault vault-0 -- vault status

# Common causes:
# 1. Vault sealed: Unseal Vault (vault operator unseal)
# 2. Vault path incorrect: Verify path exists (vault kv get secret/harbor/oidc)
# 3. ESO RBAC: Verify SecretStore role has read permissions

# Validate Vault path
kubectl exec -n staging-security-vault vault-0 -- vault kv get secret/harbor/oidc

# Force ExternalSecret reconciliation
kubectl annotate externalsecret harbor-oidc-credentials -n staging-platform-harbor reconcile="$(date +%s)"
```

---

## Communication Templates

### Pre-Migration Announcement (1 Week Before)

**Subject:** [ACTION REQUIRED] Namespace Migration - GitLab Downtime on 2026-02-28 18:00-22:00

```
Team,

We will migrate Kubernetes namespaces to a new naming pattern starting 2026-02-25.

WHAT: Namespace naming standardization (GAP-009 compliance)
WHEN: 2026-02-25 to 2026-02-28 (4 days, staged)
WHY: Governance policy enforcement, multi-cluster readiness

IMPACT:
- Most services: <10min downtime per service (staggered)
- GitLab: 2h downtime on 2026-02-28 18:00-22:00 (MAINTENANCE WINDOW)

ACTION REQUIRED (2026-02-28 only):
- Merge critical MRs before 17:00
- Avoid scheduling CI jobs after 17:30
- Pull required container images before 18:00

WHAT CHANGES:
- Namespace names only (e.g., harbor-system → staging-platform-harbor)
- Ingress URLs unchanged (harbor.staging.internal still works)
- No application functionality changes

QUESTIONS: Slack #platform-ops

Migration Plan: https://github.com/.../DEC-074-namespace-migration/
```

---

### Migration Status Update (During Execution)

**Slack #platform-ops:**

```
🔄 Migration Status Update - Wave 3

COMPLETED (Wave 1 + 2): 8/8 namespaces ✅
- cert-manager → staging-security-certmanager
- external-secrets-system → staging-security-externalsecrets
- redis-operator → staging-data-redis-operator
- test-governance → staging-governance-test
- otel-test → staging-observability-otel-test
- argocd-test → staging-platform-argocd-test
- rabbitmq-system → staging-data-rabbitmq
- kyverno → staging-governance-kyverno

IN PROGRESS (Wave 3): 2/2 namespaces 🚧
- vault-system → staging-security-vault (60% - PVC restore)
- data-services → staging-data-infrastructure (queued)

PENDING: 6 namespaces (Waves 4-6)

ETA: On track for 2026-03-05 completion
Rollbacks: 0 (100% success rate so far)
```

---

### Post-Migration Summary

**Slack #platform-ops:**

```
✅ Namespace Migration COMPLETE - DEC-074

MIGRATED: 16 namespaces (100% success)
DEPRECATED: 1 namespace (cicd-argocd)
DURATION: 7 days (2026-02-25 to 2026-03-05)
DOWNTIME: 9h total (staged, acceptable for staging)
ROLLBACKS: 0 (100% success rate)

NEW NAMING PATTERN:
{env}-{domain}-{product}
Example: staging-platform-argocd

WHAT'S NEXT:
- Kyverno policy enforcement: ENABLED (2026-03-15)
- Documentation updates: In progress
- Production cluster design: Using same pattern

VALIDATION PERIOD:
- Standard (7d): Completed 2026-03-12
- Extended (14d): Completed 2026-03-19
- Old namespaces: DELETED (cost savings: ~$50/month)

THANK YOU to the team for flawless execution! 🎉
```

---

## Scripts Reference

| Script | Pattern | Use Case |
|--------|---------|----------|
| [migrate-stateless.sh](./scripts/migrate-stateless.sh) | A | cert-manager, kyverno, operators |
| [migrate-stateful-pvc.sh](./scripts/migrate-stateful-pvc.sh) | C | gitlab, harbor, monitoring, vault |
| [migrate-operator-crd.sh](./scripts/migrate-operator-crd.sh) | D | data-services (Redis, RabbitMQ CRs) |
| [rollback.sh](./scripts/rollback.sh) | All | Universal rollback script |

**Script Usage:**
```bash
# Pattern A (Stateless)
./scripts/migrate-stateless.sh <old-ns> <new-ns> <helm-release> <helm-chart>

# Pattern C (StatefulSets + PVCs)
./scripts/migrate-stateful-pvc.sh <old-ns> <new-ns> <helm-release> <helm-chart>

# Pattern D (Operator CRDs)
./scripts/migrate-operator-crd.sh <old-ns> <new-ns> <crd-kind> <cr-name>

# Rollback
./scripts/rollback.sh <new-ns> <old-ns> [delete-snapshots]
```

---

## Success Criteria

**Migration Success:**
- [ ] 16 namespaces migrated (100%)
- [ ] Zero data loss incidents
- [ ] Total downtime < 10h
- [ ] Zero rollbacks

**Post-Migration (30 Days):**
- [ ] Kyverno policy in `enforce` mode
- [ ] All documentation updated
- [ ] Team trained on new pattern
- [ ] Production cluster design approved

---

## Contact & Support

**Slack Channels:**
- `#platform-ops` - Migration coordination
- `#incidents` - Emergency escalation

**On-Call Engineers (2026-02-25 to 2026-03-05):**
- Wave 1-2: Engineer A
- Wave 3: Engineer B (Vault specialist)
- Wave 4-5: Engineer C
- Wave 6: Engineer D (GitLab SME) + Engineer E (backup)

**Escalation:**
1. Slack #platform-ops (response time: 15min)
2. On-call engineer (PagerDuty)
3. Platform Lead (emergency only)

---

## License

Internal documentation - Confidential
© 2026 K8s Platform Team
