# DEC-074: Execution Plan with Parallelization

**Target Start Date:** 2026-02-25 (Tuesday)
**Target Completion:** 2026-03-05 (Wednesday) - 7 working days
**Total Namespaces:** 16 (excluding cicd-argocd deprecation)
**Execution Mode:** Staged waves with parallelization

---

## Wave 1: Foundation Layer (Stateless + Low Risk)

**Date:** 2026-02-25 (Tuesday) 09:00-12:00
**Duration:** 3 hours (parallelized from 6h serial)
**Namespaces:** 6 (cert-manager, external-secrets-system, redis-operator, test-governance, otel-test, argocd-test)

### Execution Timeline

#### 09:00-10:30 - Parallel Group 1 (3 agents)
```
Agent-1: cert-manager → staging-security-certmanager
  Pattern: A (Stateless)
  PVCs: 0
  Downtime: 10min
  Validation: curl https://cert-manager.staging.internal (if ingress exists)

Agent-2: external-secrets-system → staging-security-externalsecrets
  Pattern: A (Stateless)
  PVCs: 0
  Downtime: 10min
  Critical: Validate ESO syncing secrets after migration
  Validation: kubectl get externalsecrets -A (all SecretSynced)

Agent-3: redis-operator → staging-data-redis-operator
  Pattern: A (Stateless operator)
  PVCs: 0
  Downtime: 5min
  Validation: kubectl get redis -n data-services (CR still reconciled)
```

**Go/No-Go Checkpoint 1 (10:30):**
- All 3 namespaces: pods Running
- ESO critical: 7 ExternalSecrets show SecretSynced=True
- Redis operator: data-services/redis CR status Ready
- **Decision:** If GO → proceed to Parallel Group 2, if NO-GO → rollback Agent-X

---

#### 10:30-12:00 - Parallel Group 2 (3 agents)
```
Agent-4: test-governance → staging-governance-test
  Pattern: A (Stateless testing)
  PVCs: 0
  Downtime: 5min
  Validation: kubectl get pods -n staging-governance-test

Agent-5: otel-test → staging-observability-otel-test
  Pattern: A (Stateless testing)
  PVCs: 0
  Downtime: 5min
  Validation: kubectl get pods -n staging-observability-otel-test

Agent-6: argocd-test → staging-platform-argocd-test
  Pattern: A (Stateless testing)
  PVCs: 0
  Downtime: 10min
  Validation: ArgoCD UI accessible (if configured)
```

**Go/No-Go Checkpoint 2 (12:00):**
- All 6 namespaces operational
- Zero rollbacks in Wave 1
- **Decision:** If GO → proceed to Wave 2 (afternoon), if NO-GO → investigate patterns

---

## Wave 2: Operators & Governance

**Date:** 2026-02-25 (Tuesday) 14:00-17:00
**Duration:** 3 hours (sequential, operator dependencies)
**Namespaces:** 2 (rabbitmq-system, kyverno)

### Execution Timeline

#### 14:00-15:30 - RabbitMQ Operator
```
Namespace: rabbitmq-system → staging-data-rabbitmq
  Pattern: A (Stateless operator, CR in data-services)
  PVCs: 0 (operator only, no data)
  Downtime: 5min (operator reconciliation pause)

Steps:
  1. Export operator deployment YAML
  2. Create staging-data-rabbitmq namespace
  3. Deploy RabbitMQ Cluster Operator
  4. Validate: kubectl get rabbitmqclusters -n data-services (CR still managed)
  5. Test: RabbitMQ management UI (rabbitmq.staging.internal)

Validation:
  - Operator logs show reconciliation: kubectl logs -n staging-data-rabbitmq deployment/rabbitmq-cluster-operator
  - data-services/k8s-platform-prod-rabbitmq CR status Ready
  - Management UI HTTP 200
```

**Go/No-Go Checkpoint 3 (15:30):**
- RabbitMQ operator operational
- data-services CR still reconciled
- **Decision:** If GO → proceed to Kyverno, if NO-GO → rollback (recreate in old namespace)

---

#### 15:30-17:00 - Kyverno Policy Engine
```
Namespace: kyverno → staging-governance-kyverno
  Pattern: A (Stateless admission controller)
  PVCs: 0
  Downtime: 15min (webhook registration)

Steps:
  1. Export ClusterPolicies: kubectl get clusterpolicy -o yaml > policies-backup.yaml
  2. Export Helm values
  3. Create staging-governance-kyverno namespace
  4. Deploy Kyverno Helm chart
  5. Validate: ClusterPolicies reconciled
  6. Test: Create test pod (policy enforcement)

Critical:
  - Admission webhook MUST register: kubectl get validatingwebhookconfigurations
  - Test policy: kubectl run test-pod --image=nginx -n staging-integration-test
    (should enforce GAP-009 namespace naming policy)

Validation:
  - All ClusterPolicies show Ready=True
  - Test pod creation enforces policy (if GAP-009 active)
  - No webhook timeout errors in logs
```

**Go/No-Go Checkpoint 4 (17:00):**
- Kyverno webhook operational
- Policies enforced
- **Decision:** If GO → Wave 2 complete, prepare Wave 3

---

## Wave 3: Security & Data Layer (CRITICAL Path)

**Date:** 2026-02-26 (Wednesday) 09:00-16:00
**Duration:** 7 hours (sequential, dependencies)
**Namespaces:** 2 (vault-system, data-services)

### Execution Timeline

#### 09:00-13:00 - Vault (CRITICAL)
```
Namespace: vault-system → staging-security-vault
  Pattern: C (StatefulSet + PVCs, HIGH risk)
  PVCs: 2 (data-vault-0: 10Gi, audit-vault-0: 5Gi)
  Downtime: 60min (PVC restore + unseal)

Pre-Migration (08:00-09:00):
  1. Backup Vault: vault operator raft snapshot save /tmp/vault-backup-2026-02-26.snap
  2. Copy backup to S3: aws s3 cp /tmp/vault-backup-*.snap s3://k8s-platform-backups/vault/
  3. Document unseal keys (CRITICAL - store securely)
  4. Export Helm values

Steps:
  1. Create VolumeSnapshots (data-vault-0, audit-vault-0)
  2. Wait for snapshots readyToUse (~15min for 15GB)
  3. Create staging-security-vault namespace
  4. Restore PVCs from snapshots
  5. Deploy Vault Helm chart
  6. Unseal Vault: vault operator unseal (3 key shards)
  7. Validate: vault status (sealed=false)
  8. Test KV read: vault kv get secret/grafana/oidc

Critical Validation:
  - Vault unsealed successfully
  - All 7 KV paths accessible:
    * secret/grafana/oidc
    * secret/sonarqube/postgresql
    * secret/sonarqube/saml
    * secret/harbor/postgresql
    * secret/harbor/oidc
    * secret/keycloak/postgresql
    * secret/gitlab/ci-variables
  - ESO reconnects: kubectl get externalsecrets -A (all SecretSynced)

Rollback Trigger:
  - Unseal fails after 30min
  - KV paths inaccessible
  - ESO fails to sync (check after 10min)
```

**Go/No-Go Checkpoint 5 (13:00):**
- Vault unsealed and operational
- All ExternalSecrets synced from new Vault
- **Decision:** If GO → proceed to data-services, if NO-GO → ROLLBACK (restore from S3 backup)

---

#### 13:00-16:00 - Data Infrastructure
```
Namespace: data-services → staging-data-infrastructure
  Pattern: D (Operator-managed CRs: Redis, RabbitMQ)
  PVCs: 2 (redis-redis-0: 1Gi, rabbitmq persistence: 5Gi)
  Downtime: 45min (CR recreation + PVC restore)

Pre-Migration (12:30-13:00):
  1. Export RabbitMQ definitions:
     kubectl exec -n data-services k8s-platform-prod-rabbitmq-server-0 -- \
       rabbitmqadmin export /tmp/definitions.json
     kubectl cp data-services/k8s-platform-prod-rabbitmq-server-0:/tmp/definitions.json \
       ./rabbitmq-definitions-backup.json
  2. Export Redis keys (if persistence needed):
     kubectl exec -n data-services redis-0 -- redis-cli SAVE
  3. Export CRs: kubectl get redis,rabbitmqclusters -n data-services -o yaml > crs-backup.yaml

Steps:
  1. Create VolumeSnapshots (redis-redis-0, rabbitmq persistence PVC)
  2. Create staging-data-infrastructure namespace
  3. Restore PVCs from snapshots
  4. Recreate CRs in new namespace:
     - Edit crs-backup.yaml: metadata.namespace=staging-data-infrastructure
     - Apply: kubectl apply -f crs-backup.yaml
  5. Operators reconcile (rabbitmq-system, redis-operator watch all namespaces)
  6. Wait for StatefulSets Running (~20min)
  7. Validate:
     - Redis: kubectl exec -n staging-data-infrastructure redis-0 -- redis-cli PING
     - RabbitMQ: curl http://rabbitmq.staging.internal:15672/api/overview
  8. Import RabbitMQ definitions (if needed):
     kubectl exec -n staging-data-infrastructure k8s-platform-prod-rabbitmq-server-0 -- \
       rabbitmqadmin import /tmp/definitions.json

Critical Validation:
  - Redis PING → PONG
  - RabbitMQ management UI HTTP 200
  - RabbitMQ queues/exchanges exist (count matches backup)
  - Ingress: rabbitmq.staging.internal resolves
```

**Go/No-Go Checkpoint 6 (16:00):**
- Redis + RabbitMQ operational
- Data integrity validated (queues exist)
- **Decision:** If GO → Wave 3 complete, if NO-GO → rollback CRs to old namespace

---

## Wave 4: Platform Core (SSO + GitOps)

**Date:** 2026-02-27 (Thursday) 09:00-16:00
**Duration:** 7 hours (sequential, SSO dependency)
**Namespaces:** 3 (keycloak, argocd, sonarqube)

### Execution Timeline

#### 09:00-11:00 - Keycloak (SSO Provider)
```
Namespace: keycloak → staging-platform-keycloak
  Pattern: B (External RDS, stateless pods)
  PVCs: 0
  Downtime: 20min (RDS connection + DNS)

Steps:
  1. Export Helm values
  2. Backup RDS: AWS Console → manual snapshot (keycloak-pre-migration-2026-02-27)
  3. Create staging-platform-keycloak namespace
  4. Deploy Helm chart (same RDS endpoint)
  5. Wait for pods Running (~5min)
  6. Validate:
     - RDS connection: kubectl logs -n staging-platform-keycloak keycloak-keycloakx-0 | grep "Database"
     - Admin console: https://keycloak.staging.internal/auth/admin
     - OIDC endpoint: curl https://keycloak.staging.internal/auth/realms/master/.well-known/openid-configuration
  7. Test SSO login: Grafana login (OIDC), SonarQube login (SAML)

Critical Validation:
  - All 5 SSO clients operational:
    * Grafana (OIDC)
    * ArgoCD (OIDC)
    * Harbor (OIDC)
    * GitLab (OIDC)
    * SonarQube (SAML 2.0)
  - Realm export matches pre-migration state
```

**Go/No-Go Checkpoint 7 (11:00):**
- Keycloak operational, all SSO clients work
- **Decision:** If GO → proceed to ArgoCD, if NO-GO → rollback (delete new namespace)

---

#### 11:00-13:00 - ArgoCD (GitOps Controller)
```
Namespace: argocd → staging-platform-argocd
  Pattern: B (External RDS, stateless)
  PVCs: 0
  Downtime: 15min

Steps:
  1. Export applications: argocd app list -o yaml > apps-backup.yaml
  2. Pause auto-sync: for app in $(argocd app list -o name); do argocd app set $app --sync-policy none; done
  3. Backup RDS: AWS Console snapshot
  4. Create staging-platform-argocd namespace
  5. Deploy Helm chart
  6. Validate:
     - ArgoCD UI: https://argocd.staging.internal
     - Application sync status: argocd app list
     - Test manual sync: argocd app sync <test-app>
  7. Re-enable auto-sync: argocd app set <app> --sync-policy automated

Critical Validation:
  - All applications visible in UI
  - Application count matches backup
  - Git repository connections OK
```

**Go/No-Go Checkpoint 8 (13:00):**
- ArgoCD operational, all apps synced
- **Decision:** If GO → proceed to SonarQube

---

#### 13:00-16:00 - SonarQube (Code Quality)
```
Namespace: sonarqube → staging-platform-sonarqube
  Pattern: C (PVC + External RDS)
  PVCs: 1 (sonarqube-sonarqube: 20Gi, plugins + cache)
  Downtime: 45min

Steps:
  1. Export Helm values
  2. Backup RDS: AWS Console snapshot
  3. Create VolumeSnapshot (sonarqube-sonarqube PVC)
  4. Create staging-platform-sonarqube namespace
  5. Restore PVC from snapshot
  6. Deploy Helm chart
  7. Wait for pod Running (~15min, large PVC)
  8. Validate:
     - SonarQube UI: https://sonarqube.staging.internal
     - SAML login: Test Keycloak federation
     - Project count: curl -u admin:admin https://sonarqube.staging.internal/api/projects/search | jq .paging.total
     - Analysis history: Check recent scan results

Critical Validation:
  - All projects visible
  - Quality gates intact
  - SAML login works (Keycloak SSO)
```

**Go/No-Go Checkpoint 9 (16:00):**
- SonarQube operational, data validated
- **Decision:** Wave 4 complete

---

## Wave 5: Platform Services + Observability (HIGH PVC Count)

**Date:** 2026-02-28 (Friday) 09:00-18:00
**Duration:** 9 hours (sequential, large PVCs)
**Namespaces:** 2 (harbor-system, monitoring)

### Execution Timeline

#### 09:00-13:00 - Harbor (Container Registry)
```
Namespace: harbor-system → staging-platform-harbor
  Pattern: C (PVCs: registry OCI blobs)
  PVCs: 2 (harbor-jobservice: 1Gi, harbor-registry: 5Gi)
  Downtime: 60min

Pre-Migration (08:00-09:00):
  1. Backup RDS: AWS Console snapshot
  2. Test registry pull: docker pull harbor.staging.internal/library/nginx
  3. Document image count: curl -u admin:Harbor12345 https://harbor.staging.internal/api/v2.0/projects | jq length

Steps:
  1. Create VolumeSnapshots (harbor-jobservice, harbor-registry)
  2. Create staging-platform-harbor namespace
  3. Restore PVCs from snapshots
  4. Deploy Helm chart
  5. Wait for pods Running (~20min)
  6. Validate:
     - Harbor UI: https://harbor.staging.internal
     - OIDC login: Test Keycloak SSO
     - Docker pull: docker pull harbor.staging.internal/library/nginx
     - Image count matches backup
     - Registry API: curl https://harbor.staging.internal/v2/_catalog

Critical Validation:
  - All projects visible
  - OCI blobs accessible (docker pull works)
  - GitLab CI can push/pull images
```

**Go/No-Go Checkpoint 10 (13:00):**
- Harbor operational, docker pull/push works
- **Decision:** If GO → proceed to monitoring (LUNCH BREAK 13:00-14:00)

---

#### 14:00-18:00 - Monitoring Stack (LARGEST PVCs)
```
Namespace: monitoring → staging-observability-monitoring
  Pattern: C (9 PVCs, 94Gi total, multiple StatefulSets)
  PVCs: 9 (Prometheus: 20Gi, Grafana: 5Gi, Loki: 40Gi, Tempo: 20Gi, Alertmanager: 2Gi)
  Downtime: 90min (longest migration)

Pre-Migration (13:00-14:00):
  1. Backup Grafana dashboards:
     for dashboard in $(curl -H "Authorization: Bearer $TOKEN" https://grafana.staging.internal/api/search | jq -r '.[].uid'); do
       curl -H "Authorization: Bearer $TOKEN" https://grafana.staging.internal/api/dashboards/uid/$dashboard > grafana-backup-$dashboard.json
     done
  2. Export Prometheus rules: kubectl get prometheusrules -n monitoring -o yaml > prometheus-rules-backup.yaml
  3. Accept metrics gap during migration (Prometheus will rebuild from targets)

Steps:
  1. Create VolumeSnapshots (all 9 PVCs) - PARALLEL
  2. Wait for snapshots readyToUse (~30min for 94GB total)
  3. Create staging-observability-monitoring namespace
  4. Restore PVCs from snapshots (PARALLEL)
  5. Deploy Helm chart (kube-prometheus-stack)
  6. Wait for pods Running (~30min, large PVCs)
     Priority order: Prometheus → Grafana → Loki → Tempo
  7. Validate:
     - Prometheus UI: http://prometheus.staging.internal:9090
     - Grafana UI: https://grafana.staging.internal
     - Grafana OIDC login: Test Keycloak SSO
     - Prometheus targets: All UP
     - Grafana dashboards: Count matches backup
     - Loki query: Log lines visible
     - Tempo query: Traces visible

Critical Validation:
  - Prometheus scraping all targets (no DOWN targets)
  - Grafana dashboards rendered (not empty)
  - Loki + Tempo ingesting new data
  - OIDC login works
```

**Go/No-Go Checkpoint 11 (18:00):**
- Monitoring stack operational
- **Decision:** Wave 5 complete, prepare for GitLab (CRITICAL)

---

## Wave 6: GitLab (CRITICAL - Dedicated Maintenance Window)

**Date:** 2026-02-28 (Friday) 18:00-22:00
**Duration:** 4 hours (dedicated maintenance window)
**Namespaces:** 1 (gitlab-staging)

### Pre-Migration Communications

**1 Week Before (2026-02-21):**
```
Subject: [ACTION REQUIRED] GitLab Maintenance Window - 2026-02-28 18:00-22:00

Team,

We will migrate GitLab to a new namespace on 2026-02-28 (Friday) 18:00-22:00 EST.

IMPACT:
- GitLab UI unavailable (4h window)
- Git clone/push unavailable
- CI/CD pipelines paused
- Container Registry read-only

ACTION REQUIRED:
- Merge all critical MRs before 17:00
- Avoid scheduling CI jobs after 17:30
- Pull required container images before 18:00

Rollback plan: If migration fails, old GitLab will be restored by 22:00.

Questions: Slack #platform-ops
```

**1 Day Before (2026-02-27 17:00):**
```
Reminder: GitLab migration TOMORROW 18:00-22:00.
Last chance to merge critical work.
```

**1 Hour Before (2026-02-28 17:00):**
```
GitLab migration starts in 1 hour.
Pausing CI runners at 17:30.
```

---

### Execution Timeline

#### 17:00-18:00 - Pre-Migration Prep
```
17:00: Start pre-migration checklist
  - Backup RDS: AWS Console → manual snapshot (gitlab-pre-migration-2026-02-28)
  - Document current state:
    * Repository count: curl https://gitlab.staging.internal/api/v4/projects | jq length
    * Gitaly storage: kubectl exec gitlab-gitaly-0 -n gitlab-staging -- du -sh /home/git/repositories
    * CI runner jobs: kubectl get jobs -n gitlab-staging
    * Users count: curl https://gitlab.staging.internal/api/v4/users | jq length

17:30: Pause CI/CD
  - Scale runners to 0: kubectl scale deployment gitlab-runner -n gitlab-staging --replicas=0
  - Wait for running jobs to complete: kubectl wait --for=condition=complete job --all -n gitlab-staging --timeout=10m

17:45: Export Helm values
  - helm get values k8s-platform-prod-gitlab -n gitlab-staging > gitlab-values-backup.yaml

17:50: Slack notification
  - "GitLab migration starting in 10 minutes. UI will be unavailable until 22:00."
```

---

#### 18:00-20:00 - Migration Execution
```
18:00: START MIGRATION

18:00-18:15: Create VolumeSnapshot
  - kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: gitlab-gitaly-snapshot-2026-02-28
  namespace: gitlab-staging
spec:
  volumeSnapshotClassName: ebs-csi-snapshot-class
  source:
    persistentVolumeClaimName: repo-data-gitlab-gitaly-0
EOF
  - Wait for readyToUse: kubectl wait --for=condition=readyToUse volumesnapshot/gitlab-gitaly-snapshot-2026-02-28 -n gitlab-staging --timeout=20m
  - Expected: ~15min for 50GB PVC

18:15-18:20: Create new namespace
  - kubectl create namespace staging-platform-gitlab
  - kubectl label namespace staging-platform-gitlab \
      environment=staging \
      domain=platform \
      product=gitlab \
      CostCenter=development \
      ManagedBy=terraform

18:20-18:35: Restore PVC from snapshot
  - kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: repo-data-gitlab-gitaly-0
  namespace: staging-platform-gitlab
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 50Gi
  storageClassName: gp3
  dataSource:
    name: gitlab-gitaly-snapshot-2026-02-28
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF
  - Wait for Bound: kubectl wait --for=condition=bound pvc/repo-data-gitlab-gitaly-0 -n staging-platform-gitlab --timeout=20m

18:35-19:00: Deploy GitLab Helm chart
  - helm upgrade --install k8s-platform-prod-gitlab gitlab/gitlab \
      -n staging-platform-gitlab \
      -f gitlab-values-backup.yaml \
      --timeout 30m
  - Wait for pods Running: kubectl wait --for=condition=Ready pod --all -n staging-platform-gitlab --timeout=30m
  - Expected: ~25min for StatefulSet + large PVC

19:00-19:30: Data Integrity Validation (CRITICAL)
  1. Repository count:
     NEW_COUNT=$(curl https://gitlab.staging.internal/api/v4/projects | jq length)
     if [ "$NEW_COUNT" != "$OLD_COUNT" ]; then echo "ROLLBACK TRIGGER"; exit 1; fi

  2. Git clone test:
     git clone https://gitlab.staging.internal/platform-team/test-repo.git /tmp/test-clone
     if [ $? -ne 0 ]; then echo "ROLLBACK TRIGGER"; exit 1; fi

  3. Gitaly storage validation:
     NEW_SIZE=$(kubectl exec gitlab-gitaly-0 -n staging-platform-gitlab -- du -sh /home/git/repositories | awk '{print $1}')
     if [ "$NEW_SIZE" != "$OLD_SIZE" ]; then echo "ROLLBACK TRIGGER"; exit 1; fi

  4. RDS connection:
     kubectl logs -n staging-platform-gitlab gitlab-webservice-default-xxx | grep "Database"
     # Should show: "Database connection established"

  5. CI variables accessible:
     curl https://gitlab.staging.internal/api/v4/projects/1/variables | jq .
     # Should return CI variables (from ExternalSecret)

19:30-19:45: Update Ingress DNS
  - Verify ingress created: kubectl get ingress -n staging-platform-gitlab
  - Test ALB endpoint: curl -I https://gitlab.staging.internal
  - Expected: HTTP 200

19:45-20:00: Enable CI/CD Runners
  - Scale runners: kubectl scale deployment gitlab-runner -n staging-platform-gitlab --replicas=3
  - Test CI pipeline: Trigger test job in test-repo
  - Validate: Job completes successfully
```

**Go/No-Go Decision (20:00):**
- **GO:** Repository count matches, git clone works, CI pipeline runs
- **NO-GO (ROLLBACK):** Repository count mismatch, git clone fails, RDS errors

---

#### 20:00-22:00 - Post-Migration Validation + Monitoring
```
20:00-21:00: Extended Validation
  - Test user workflows:
    * Git push: git push origin test-branch
    * Merge request: Create + merge MR
    * CI/CD: Trigger pipeline (docker build + push to Harbor)
    * Container Registry: docker pull registry.staging.internal/<image>
  - Monitor logs for errors:
    * GitLab webservice: kubectl logs -n staging-platform-gitlab deployment/gitlab-webservice-default --tail=100 -f
    * Gitaly: kubectl logs -n staging-platform-gitlab statefulset/gitlab-gitaly --tail=100 -f
  - Check metrics in Grafana:
    * GitLab request rate
    * Gitaly RPC latency
    * Redis cache hit rate

21:00-21:30: Stress Test
  - Simulate concurrent git clones (10 users)
  - Trigger 5 CI pipelines simultaneously
  - Monitor resource usage (CPU, memory, disk I/O)

21:30-22:00: Final Validation + Communication
  - All tests passed → Migration SUCCESS
  - Slack notification:
    "✅ GitLab migration COMPLETE. UI operational at https://gitlab.staging.internal.
     All repositories migrated (count: $NEW_COUNT). CI/CD runners active.
     Old namespace (gitlab-staging) will be deleted on 2026-03-14 (+14 days)."
  - Update documentation:
    * Namespace inventory: gitlab-staging → staging-platform-gitlab
    * Ingress endpoints (already same DNS, no doc change)
    * Backup procedures (update namespace name)

22:00: END MIGRATION WINDOW
```

---

#### Rollback Procedure (If Triggered)
```
20:00: ROLLBACK DECISION MADE

20:00-20:15: Delete new namespace
  - kubectl delete namespace staging-platform-gitlab
  - VolumeSnapshot preserved (do not delete)

20:15-20:30: DNS cutover to old namespace
  - Verify old namespace operational: kubectl get pods -n gitlab-staging
  - Ingress should still route to old namespace (no DNS change yet in migration)

20:30-20:45: Re-enable runners in old namespace
  - kubectl scale deployment gitlab-runner -n gitlab-staging --replicas=3
  - Test CI pipeline in old namespace

20:45-21:00: Validation + Communication
  - Test git clone from old namespace
  - Slack notification:
    "⚠️ GitLab migration ROLLED BACK. UI operational at old namespace (gitlab-staging).
     All repositories intact. Migration will be rescheduled.
     Root cause: <insert reason>"

21:00: Post-Mortem
  - Document rollback reason
  - Review migration logs
  - Schedule retry (2026-03-07 +1 week)
```

---

## Wave 7: Cleanup & Deprecation

**Date:** 2026-03-05 (Wednesday)
**Duration:** 2 hours

### cicd-argocd Deprecation
```
Namespace: cicd-argocd (DEPRECATED - duplicate ArgoCD instance)

Steps:
  1. Export applications: argocd app list -o yaml > cicd-argocd-apps-backup.yaml
  2. Migrate applications to staging-platform-argocd:
     - Import apps: kubectl apply -f cicd-argocd-apps-backup.yaml -n staging-platform-argocd
     - Update sync source if needed
  3. Delete cicd-argocd namespace: kubectl delete namespace cicd-argocd
  4. Update documentation (remove references)

Rationale: Single ArgoCD instance sufficient, reduces operational complexity
```

---

## Summary: Total Execution Time

| Wave | Duration | Parallelized | Namespaces | Date |
|------|----------|--------------|------------|------|
| Wave 1 | 3h | 6 agents | 6 | 2026-02-25 |
| Wave 2 | 3h | Sequential | 2 | 2026-02-25 |
| Wave 3 | 7h | Sequential | 2 | 2026-02-26 |
| Wave 4 | 7h | Sequential | 3 | 2026-02-27 |
| Wave 5 | 9h | Sequential | 2 | 2026-02-28 |
| Wave 6 | 4h | Dedicated | 1 | 2026-02-28 |
| Wave 7 | 2h | Cleanup | 1 | 2026-03-05 |
| **TOTAL** | **35h** | **Optimized** | **17** | **7 days** |

**Serial Execution (no parallelization):** 60h (7.5 working days @ 8h/day)
**Optimized Execution (with parallelization):** 35h (4.5 working days @ 8h/day)
**Actual Timeline (staged + validation):** 7 calendar days (includes buffer)

---

## Risk Summary

| Risk Level | Namespaces | Strategy |
|------------|-----------|----------|
| CRITICAL | 1 (gitlab-staging) | Dedicated 4h window, 14d retention, double backup |
| HIGH | 4 (vault, data-services, harbor, monitoring) | VolumeSnapshots, extended validation |
| MEDIUM | 4 (argocd, keycloak, kyverno, sonarqube, rabbitmq) | Standard pattern, 7d retention |
| LOW | 7 (cert-manager, eso, redis-op, tests) | Parallel execution, minimal downtime |

---

## Success Metrics

**Post-Migration (2026-03-05):**
- [ ] 16 namespaces migrated (100% compliant with GAP-009)
- [ ] 1 namespace deprecated (cicd-argocd)
- [ ] Zero data loss incidents
- [ ] Total downtime < 8h (across all namespaces)
- [ ] Zero rollbacks (target: 100% success rate)
- [ ] All ExternalSecrets synced (7/7)
- [ ] All ingress endpoints operational
- [ ] All PVCs migrated successfully (17 PVCs, 170GB total)

**30-Day Post-Migration (2026-03-24):**
- [ ] Old namespaces deleted (saved costs: ~$50/month in etcd storage)
- [ ] VolumeSnapshots deleted (saved costs: ~$20/month)
- [ ] Documentation updated (namespace inventory, runbooks, ADRs)
- [ ] Team trained on new naming pattern

---

## Next: Review Migration Scripts
→ `/scripts/`
