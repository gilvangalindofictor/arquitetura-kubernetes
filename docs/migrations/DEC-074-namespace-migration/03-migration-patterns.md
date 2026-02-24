# DEC-074: Migration Patterns & Strategies

**Purpose:** Define reusable migration patterns for each workload type, with rollback procedures.

---

## Pattern A: Stateless Services (LOW RISK)

**Use Cases:** cert-manager, external-secrets-system, kyverno, test-governance, otel-test

**Characteristics:**
- No PVCs (ephemeral storage only)
- No external databases
- Helm-managed deployments
- Quick recovery from failure

**Migration Strategy:**
```
1. Export current Helm values: helm get values <release> -n <old-ns> > values.yaml
2. Export CRDs/CRs (if operator): kubectl get <crd> -n <old-ns> -o yaml > crs-backup.yaml
3. Create new namespace with labels
4. Deploy Helm chart to new namespace
5. Validate pods Running + service endpoints
6. Update ingress DNS (if applicable)
7. Delete old namespace after 7d validation
```

**Downtime:** 5-10 minutes (DNS propagation)

**Rollback:**
```bash
kubectl delete namespace <new-ns>
# Old namespace still exists, no action needed
```

**Success Criteria:**
- All pods Running in new namespace
- Service endpoints responding (curl)
- CRDs/CRs reconciled (kubectl get <crd>)

---

## Pattern B: Stateful Services with External Storage (MEDIUM RISK)

**Use Cases:** argocd, keycloak, sonarqube, harbor-system (partial)

**Characteristics:**
- External PostgreSQL RDS (no PVC for database)
- Application state in RDS
- May have small PVCs (cache, plugins)
- Requires connection string updates

**Migration Strategy:**
```
1. Export Helm values
2. Export RDS connection secrets (not from Vault, from K8s)
3. Snapshot small PVCs (if exist): cache, plugins
4. Create new namespace
5. Recreate ExternalSecrets in new namespace (ESO will sync from Vault)
6. Deploy Helm chart with same RDS endpoint
7. Validate database connectivity: kubectl exec <pod> -- psql -h <rds-endpoint>
8. Test application functionality
9. Update ingress DNS
10. Delete old namespace after 7d
```

**Downtime:** 10-20 minutes (RDS connection switch + DNS)

**Rollback:**
```bash
# 1. Delete new namespace
kubectl delete namespace <new-ns>

# 2. Old namespace still operational
kubectl get pods -n <old-ns>
```

**Success Criteria:**
- RDS connection successful (no authentication errors)
- Application data intact (row count validation)
- Ingress responding HTTP 200
- ExternalSecrets synced (SecretSynced status)

---

## Pattern C: StatefulSets with PVCs (HIGH RISK)

**Use Cases:** gitlab-staging (50GB gitaly), harbor-system (5GB registry), monitoring (94GB stack), vault-system (15GB), data-services (6GB)

**Characteristics:**
- Large PVCs (>1GB, up to 50GB)
- Data loss = critical incident
- Long migration time (EBS snapshot + restore)
- Requires data integrity validation

**Migration Strategy:**
```
1. BACKUP FIRST:
   - Export Helm values
   - Create VolumeSnapshots (all PVCs in namespace)
   - Wait for snapshots readyToUse
   - Document PVC sizes, mount paths

2. CREATE NEW NAMESPACE:
   - kubectl create namespace <new-ns>
   - Apply same labels (CostCenter, Environment, etc)

3. RESTORE PVCs FROM SNAPSHOTS:
   - For each PVC:
     * Create PVC in new namespace with dataSource=VolumeSnapshot
     * Wait for PVC Bound
     * Validate size matches original

4. DEPLOY APPLICATION:
   - helm install <release> -n <new-ns> -f values.yaml
   - Application will claim existing PVCs by name

5. VALIDATION:
   - Pods Running (may take 5-10min for large PVCs)
   - Data integrity check:
     * GitLab: git clone test repository
     * Harbor: docker pull test image
     * Vault: vault kv get test/secret
     * Monitoring: Prometheus query returns data
   - Check logs for errors

6. DNS CUTOVER:
   - Update ingress to new namespace
   - Test ingress endpoints (HTTP 200)

7. KEEP OLD NAMESPACE 14 DAYS (extended retention for CRITICAL data)
```

**Downtime:** 30-120 minutes (depends on PVC size)
- 1GB PVC: 30min
- 10GB PVC: 45min
- 50GB PVC: 90-120min

**Rollback (BEFORE old namespace deletion):**
```bash
# 1. Delete new namespace (keeps old intact)
kubectl delete namespace <new-ns>

# 2. Old namespace still operational
kubectl get pods -n <old-ns>

# 3. Delete VolumeSnapshots (optional, to save costs)
kubectl delete volumesnapshot -n <old-ns> --all
```

**Rollback (AFTER old namespace deletion - DISASTER RECOVERY):**
```bash
# 1. Restore from VolumeSnapshots (must keep snapshots!)
for snapshot in $(kubectl get volumesnapshot -n <old-ns> -o name); do
  SNAPSHOT_NAME=$(echo $snapshot | cut -d'/' -f2)
  PVC_NAME=$(echo $SNAPSHOT_NAME | sed 's/-snapshot$//')

  # Recreate PVC from snapshot
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: <old-ns>
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: <SIZE>
  storageClassName: gp3
  dataSource:
    name: $SNAPSHOT_NAME
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF
done

# 2. Redeploy application to old namespace
helm install <release> -n <old-ns> -f values.yaml
```

**Success Criteria:**
- All PVCs Bound in new namespace
- Data integrity validated:
  - File count matches: `find /data -type f | wc -l`
  - Checksum validation (if applicable)
  - Application-level validation (git clone, docker pull, query)
- No pod CrashLoopBackOff
- Logs show normal operation (no I/O errors)

---

## Pattern D: Operator-Managed CRDs (MEDIUM RISK)

**Use Cases:** rabbitmq-system (RabbitmqCluster CR), redis-operator (Redis CR)

**Characteristics:**
- Operator watches cluster-scoped or all namespaces
- CRs (Custom Resources) define workload spec
- StatefulSets managed by operator (not directly editable)
- Modifying StatefulSet is reverted by operator reconciliation

**Migration Strategy:**
```
1. IDENTIFY CR PARENT:
   - kubectl get <sts> -n <old-ns> -o jsonpath='{.metadata.ownerReferences}'
   - Note CRD kind + name (e.g., RabbitmqCluster/k8s-platform-prod-rabbitmq)

2. EXPORT CR DEFINITION:
   - kubectl get <crd-kind> <cr-name> -n <old-ns> -o yaml > cr-backup.yaml
   - Remove metadata.uid, resourceVersion, status sections

3. SNAPSHOT PVCS (if StatefulSet has storage):
   - Create VolumeSnapshots for all PVCs

4. CREATE NEW NAMESPACE:
   - kubectl create namespace <new-ns>

5. RECREATE CR IN NEW NAMESPACE:
   - Edit cr-backup.yaml: change metadata.namespace to <new-ns>
   - kubectl apply -f cr-backup.yaml
   - Operator will create StatefulSet + PVCs in new namespace

6. RESTORE DATA (if needed):
   - If CR creates new PVCs (not from snapshot):
     * Scale StatefulSet to 0: kubectl scale sts <name> -n <new-ns> --replicas=0
     * Delete new PVCs
     * Create PVCs from snapshots (with same name)
     * Scale StatefulSet to original replicas

7. VALIDATION:
   - CR status: kubectl get <crd-kind> <cr-name> -n <new-ns> -o jsonpath='{.status}'
   - Pods Running
   - Test service connectivity

8. DELETE OLD CR (not namespace):
   - kubectl delete <crd-kind> <cr-name> -n <old-ns>
   - Operator will clean up StatefulSet + PVCs in old namespace

9. KEEP OLD NAMESPACE 7d (for CR history)
```

**Downtime:** 15-30 minutes (CR recreation + operator reconciliation)

**Rollback:**
```bash
# 1. Delete CR in new namespace
kubectl delete <crd-kind> <cr-name> -n <new-ns>

# 2. Recreate CR in old namespace (if deleted)
kubectl apply -f cr-backup.yaml -n <old-ns>

# 3. Wait for operator to reconcile
kubectl wait --for=condition=Ready <crd-kind>/<cr-name> -n <old-ns>
```

**Success Criteria:**
- CR status.conditions shows Ready=True
- StatefulSet replicas match CR spec
- Service endpoints responding
- Data intact (for RabbitMQ: queues/exchanges exist, Redis: keys exist)

---

## Special Case: GitLab Multi-PVC Migration (CRITICAL RISK)

**Challenge:** GitLab has 1 StatefulSet (gitaly) with 50GB PVC, but also multiple Deployments with PVCs

**GitLab PVC Inventory:**
```
1. repo-data-gitlab-gitaly-0 (50Gi) - Git repository storage (CRITICAL)
```

**Enhanced Strategy:**
```
1. MAINTENANCE WINDOW REQUIRED (Friday 18:00-22:00)

2. PRE-MIGRATION (1 week before):
   - Notify users: "GitLab downtime on 2026-02-28 18:00-22:00"
   - Test migration in argocd-test namespace (similar StatefulSet pattern)
   - Document current state:
     * Repository count: curl https://gitlab.staging.internal/api/v4/projects | jq length
     * Gitaly storage: kubectl exec gitlab-gitaly-0 -n gitlab-staging -- du -sh /home/git/repositories
     * CI runner jobs: kubectl get jobs -n gitlab-staging

3. MIGRATION DAY:
   - 17:30: Pause CI/CD pipelines (disable runners)
   - 17:45: Backup RDS database (AWS console snapshot)
   - 18:00: START MIGRATION
     a. Create VolumeSnapshot (repo-data-gitlab-gitaly-0)
     b. Wait for snapshot readyToUse (~10min for 50GB)
     c. Create new namespace (staging-platform-gitlab)
     d. Restore PVC from snapshot
     e. Deploy Helm chart
     f. Wait for pods Running (~20min, large PVC)
     g. Validate data integrity:
        - Repository count matches
        - Git clone test repository
        - CI variables accessible
     h. Update ingress DNS (gitlab.staging.internal)
     i. Test ingress (HTTP 200)
   - 20:00: Enable CI/CD runners (test pipelines)
   - 21:00: Monitor for errors
   - 22:00: END MIGRATION

4. POST-MIGRATION:
   - Keep old namespace 14 days (extended retention)
   - Monitor GitLab logs for 48h
   - Delete VolumeSnapshots after 14d
```

**Rollback Trigger:**
- Repository count mismatch
- Git clone fails
- RDS connection errors
- Ingress returns 502/503 after 30min

**Rollback Procedure:**
```bash
# 1. Immediate rollback (within 4h window)
kubectl delete namespace staging-platform-gitlab

# 2. DNS cutover to old namespace
kubectl patch ingress gitlab-webservice-default -n gitlab-staging --type=merge -p '{"spec":{"rules":[...]}}'

# 3. Re-enable runners in old namespace
kubectl scale deployment gitlab-runner -n gitlab-staging --replicas=3

# 4. Notify users: "Migration rolled back, GitLab operational on old namespace"
```

---

## Monitoring During Migration

**Required Metrics:**
1. Pod Status: `kubectl get pods -n <new-ns> -w`
2. PVC Bind Status: `kubectl get pvc -n <new-ns> -w`
3. Events: `kubectl get events -n <new-ns> --sort-by='.lastTimestamp'`
4. Logs: `kubectl logs -n <new-ns> <pod-name> -f`

**Slack Alerts:**
```bash
# Success notification
curl -X POST https://hooks.slack.com/services/XXX \
  -d '{"text":"✅ Migration complete: <old-ns> → <new-ns> (15min downtime)"}'

# Failure notification
curl -X POST https://hooks.slack.com/services/XXX \
  -d '{"text":"❌ Migration FAILED: <old-ns> → <new-ns> (rolling back)"}'
```

---

## Decision Matrix: Which Pattern to Use?

| Namespace | Pattern | Rationale |
|-----------|---------|-----------|
| argocd | B | External RDS, no PVCs |
| argocd-test | A | Stateless testing |
| cert-manager | A | Stateless cert issuance |
| data-services | D | Operator-managed CRs (Redis, RabbitMQ) |
| external-secrets-system | A | Stateless ESO operator |
| gitlab-staging | C (Special) | 50GB PVC, multi-ingress, critical |
| harbor-system | C | 5GB PVC (OCI blobs) |
| keycloak | B | External RDS, stateless pods |
| kyverno | A | Stateless admission controller |
| monitoring | C | 94GB PVCs (9 PVCs, multiple StatefulSets) |
| otel-test | A | Stateless testing |
| rabbitmq-system | D | Operator (manages CR in data-services) |
| redis-operator | A | Stateless operator |
| sonarqube | C | 20GB PVC (plugins + cache) + external RDS |
| test-governance | A | Stateless testing |
| vault-system | C | 15GB PVCs (data + audit) |

---

## Risk Mitigation Checklist (ALL Patterns)

**Pre-Migration (Mandatory):**
- [ ] Export Helm values: `helm get values <release> -n <old-ns> > values.yaml`
- [ ] Export manifests: `kubectl get all -n <old-ns> -o yaml > backup.yaml`
- [ ] Document current state (pod count, PVC sizes, service endpoints)
- [ ] Snapshot all PVCs (Pattern C only)
- [ ] Notify stakeholders (Slack #platform-ops)

**During Migration:**
- [ ] Create new namespace with labels
- [ ] Restore PVCs from snapshots (Pattern C)
- [ ] Deploy Helm chart / Apply manifests
- [ ] Wait for pods Running (timeout: 30min)
- [ ] Validate data integrity
- [ ] Update ingress DNS

**Post-Migration:**
- [ ] Monitor logs for errors (24h)
- [ ] Validate metrics in Prometheus
- [ ] Test user workflows (git clone, docker pull, login)
- [ ] Update documentation (namespace names)
- [ ] Schedule old namespace deletion (+7d or +14d)

**Rollback Decision (Go/No-Go):**
- **GO (Continue):** All pods Running, data validated, ingress HTTP 200
- **NO-GO (Rollback):** Any pod CrashLoopBackOff, data missing, ingress 502/503 after 30min

---

## Next: Review Execution Plan
→ `/04-execution-plan.md`
