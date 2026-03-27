# Health Audit P1 GAP Fixes (2026-03-26)

## Summary

Fixes for 3 P1 GAPs identified in the cluster health audit, plus Phase 2 Prometheus analysis.

---

## GAP-HEALTH-004: OTel HPA targets wrong deployment name -- RESOLVED

**Root cause**: HPA template `hpa.yaml` used `${name}-opentelemetry-collector` for scaleTargetRef,
producing `opentelemetry-collector-opentelemetry-collector`. The Helm chart's `_helpers.tpl` fullname
template deduplicates when release name contains the chart name, so the actual deployment is just
`opentelemetry-collector`.

**Impact**: 6,419 FailedGetScale events in 27h. HPA showed `<unknown>` for CPU target and 0 replicas
(autoscaling completely non-functional).

**Fixes applied**:
1. **Cluster patch** (immediate): `kubectl patch hpa opentelemetry-collector -n staging-observability-monitoring --type=merge -p '{"spec":{"scaleTargetRef":{"name":"opentelemetry-collector"}}}'`
2. **IaC fix**: `modules/opentelemetry-collector/hpa.yaml` L13 changed from `${name}-opentelemetry-collector` to `${name}`

**Verification post-patch**:
- Reference: `Deployment/opentelemetry-collector` (correct)
- AbleToScale: True / ReadyForNewScale
- ScalingActive: True / ValidMetricFound
- CPU: 1% / 70% target
- Replicas: 2/2

**File**: `platform-provisioning/aws/kubernetes/terraform/modules/opentelemetry-collector/hpa.yaml`

**TF apply needed**: Yes (staging) -- next `terraform apply` will reconcile the HPA manifest.

---

## GAP-HEALTH-005: Keycloak backup CronJob prod never executed -- RESOLVED (2026-03-26)

**Root cause**: **Keycloak admin password mismatch** (GAP-TF-PASSWORD-DRIFT confirmed in practice).

The backup script authenticates via `POST /auth/realms/master/protocol/openid-connect/token`
with `grant_type=password`. Keycloak returns `HTTP 401: {"error":"invalid_grant","error_description":"Invalid user credentials"}`.

### Password Drift Timeline

| Event | Date | Password Source | Value |
|-------|------|-----------------|-------|
| Admin user created in Keycloak DB | 2026-02-18 21:17 | Initial bootstrap | Unknown (original) |
| Admin password changed (Keycloak UI/DB) | 2026-03-15 21:13 | Manual change in Keycloak | Unknown (current DB value) |
| Vault v1 `secret/keycloak/admin` created | 2026-03-19 04:15 | Terraform `random_password` | `K%QpR*u>xg<$O+yS}M>C%Gq9[7x9=J#0` |
| Vault v2 `secret/keycloak/admin` created | 2026-03-19 11:20 | Terraform re-apply | `9xzTfFkg2gEwMa3GERAkg6CNLfvKe078` |
| K8s secret `keycloak-admin-credentials` | Current (ESO synced) | Vault v2 | `9xzTfFkg2gEwMa3GERAkg6CNLfvKe078` |
| Actual Keycloak DB admin password | Unknown | Set 2026-03-15 | **MISMATCH -- neither Vault v1 nor v2** |

**Key fact**: `KEYCLOAK_ADMIN_PASSWORD` env var only creates the admin user on FIRST boot.
If the admin already exists in the DB, the env var is completely ignored. The DB password was set
on 2026-03-15 (before Vault secrets were created on 2026-03-19), so ALL Vault versions are wrong.

### Additional Finding: PostgreSQL Password Drift

The `keycloak-postgresql-credentials` K8s secret also has a drifted password:
- **Vault v4** (current, synced to K8s): `kvZbav+EvnJ+XdApE4OeyytMpZvCqRu3sXATa9SUZEk=` -- FAILS auth to RDS
- **Vault v3**: `%c04x4t87(y0ENt-L<-Vw(8O]1Pg}BX<` -- this is the ACTUAL RDS password (Keycloak pod has it cached)
- **Running Keycloak pods** were started before the ESO sync, so they still have the v3 password and work fine
- **RISK**: If Keycloak pods restart, they will pick up the v4 password and FAIL to connect to the DB

### Debug Job Evidence

```
# Job: keycloak-backup-debug (created 2026-03-26T19:42:17Z)
# Pod: keycloak-backup-debug-fk6qj
# Exit Code: 1

(71/71) Installing tar (1.35-r4)
OK: 196.9 MiB in 109 packages              <-- apk install OK (~4s)
Keycloak Backup started at 20260326-194231
  -> Authenticating with Keycloak...
ERROR: Authentication failed                <-- HTTP 401 invalid_grant
```

### Verification Commands Used

```bash
# kcadm.sh from inside the Keycloak pod -- both passwords fail
kubectl exec keycloak-keycloakx-0 -c keycloak -- \
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/auth \
  --realm master --user admin --password '9xzTfFkg2gEwMa3GERAkg6CNLfvKe078'
# Result: Invalid user credentials [invalid_grant]

# DB query confirmed admin user + password changed date
# SELECT id, username, created_timestamp FROM user_entity WHERE username='admin';
# id: 75f07deb-09c7-4f44-8976-f8adf6e743f1, created: 2026-02-18
# credential.created_date: 2026-03-15 21:13:23 (last password change)
```

### Proposed Fix (REQUIRES USER APPROVAL)

**Option A (Recommended): Reset admin password via PostgreSQL to match Vault v2**

This is the same procedure documented in `access/CREDENTIALS.md` for staging:
1. Delete the admin user credential row in the Keycloak DB
2. Restart the Keycloak pods (they will re-create the admin with `KEYCLOAK_ADMIN_PASSWORD` from the secret)
3. The new password will be `9xzTfFkg2gEwMa3GERAkg6CNLfvKe078` (Vault v2)

```bash
# Step 1: Delete admin credential (forces re-creation on restart)
kubectl run psql-kc-reset --rm -it --restart=Never \
  --image=postgres:16-alpine \
  --env="PGPASSWORD=FGhG)LWN7gP-:w3AlRmROK_=dn0DuMIN" \
  --env="PGSSLMODE=require" \
  --labels="domain=security,owner=platform-team,environment=prod,app.kubernetes.io/name=psql-reset,app.kubernetes.io/part-of=keycloak" \
  -- psql -h k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com \
  -U postgres_admin -d keycloak \
  -c "DELETE FROM credential WHERE user_id = '75f07deb-09c7-4f44-8976-f8adf6e743f1';"

# Step 2: Restart Keycloak pods
kubectl rollout restart statefulset/keycloak-keycloakx -n prod-platform-keycloak

# Step 3: Verify auth works
kubectl run debug-curl --rm -i --restart=Never \
  --image=python:3.11-alpine \
  --labels="domain=security,owner=platform-team,environment=prod,app.kubernetes.io/name=debug,app.kubernetes.io/part-of=keycloak" \
  -- /bin/sh -c 'apk add curl jq && curl -s -X POST \
  "http://keycloak-keycloakx-http.prod-platform-keycloak.svc/auth/realms/master/protocol/openid-connect/token" \
  -d "username=admin&password=9xzTfFkg2gEwMa3GERAkg6CNLfvKe078&grant_type=password&client_id=admin-cli" | jq .access_token'
```

**Option B: Update Vault to match the actual DB password**

Requires knowing the actual admin password that was set on 2026-03-15. If unknown, Option A is the only path.

### CRITICAL: Fix PostgreSQL Password Drift First

Before restarting Keycloak pods (Option A Step 2), the `keycloak-postgresql-credentials` K8s secret
must be fixed. Otherwise the restarted pods will pick up the wrong DB password and fail to start.

```bash
# Revert Vault to v3 password (the one that works)
vault kv put secret/keycloak/postgresql \
  host=k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com \
  port=5432 database=keycloak username=keycloak_user \
  password='%c04x4t87(y0ENt-L<-Vw(8O]1Pg}BX<'

# OR: Force ESO to sync after Vault is updated
kubectl annotate externalsecret keycloak-postgresql-credentials \
  -n prod-platform-keycloak force-sync=$(date +%s) --overwrite

# Wait for sync, then restart Keycloak
```

### IaC Fixes Already Applied (prior session)

1. `startingDeadlineSeconds = 600` added to prod CronJob
2. `activeDeadlineSeconds = 900` added to prod CronJob
3. `startingDeadlineSeconds = 600` added to staging CronJob for consistency

### Remaining TF Apply Needed

- Staging: `keycloak-backup.tf` (startingDeadlineSeconds)
- Prod: `keycloak-backup.tf` (startingDeadlineSeconds + activeDeadlineSeconds)
- **BLOCKER**: Password drift must be fixed BEFORE next CronJob trigger (tomorrow 11:30 UTC)

**Files**:
- `platform-provisioning/aws/kubernetes/terraform/environments/prod/keycloak-backup.tf`
- `platform-provisioning/aws/kubernetes/terraform/environments/staging/keycloak-backup.tf`

**TF apply needed**: Yes (both staging and prod) for CronJob deadline settings.

### Resolution Applied (2026-03-26 20:00-20:30 UTC)

**Executor**: Security + Database Specialist agent

#### Fix 1: PostgreSQL Password Drift (CRITICAL)

1. Confirmed Vault v4 password (`kvZbav+...`) FAILS on RDS via `psql` test pod
2. Confirmed Vault v3 password (`%c04x4t87(y0ENt-L<-Vw(8O]1Pg}BX<`) is the correct RDS password
3. Updated Vault `secret/keycloak/postgresql` to v5 with v3's correct password
4. Forced ESO sync: `kubectl annotate externalsecret keycloak-postgresql-credentials force-sync=...`
5. Verified K8s secret updated to correct password
6. Verified DB connection via psql test pod: `SELECT 1` -- SUCCESS

#### Fix 2: Admin Password Drift

1. Confirmed admin login returns HTTP 401 with Vault v2 password (`9xzTfFkg2gEwMa3GERAkg6CNLfvKe078`)
2. `kc.sh bootstrap-admin` approach failed -- Keycloak 26 only bootstraps on first DB init, not on existing DB
3. Deleted admin user_entity + credential + role_mapping from DB (FK deps verified: only 1 role mapping)
4. Restarted StatefulSet -- Keycloak 26 does NOT re-create admin from env vars on existing DB
5. Generated Argon2id hash locally (matching Keycloak 26 parameters: hashIterations=5, memory=7168, parallelism=1, type=id)
6. Re-created admin via SQL: INSERT user_entity + credential (Argon2id hash) + user_role_mapping (admin role)
7. Verified admin login: HTTP 200 with access_token -- SUCCESS

#### Fix 3: Backup CronJob Verification

1. Created manual job from CronJob: `kubectl create job keycloak-backup-verify --from=cronjob/keycloak-backup`
2. Backup completed successfully:
   - Authenticated with Keycloak -- SUCCESS
   - Exported 4 realms: platform, master, hatch, ipaas
   - Uploaded to S3: `s3://k8s-platform-keycloak-backups-891377105802/backups/keycloak-backup-20260326-202945.tar.gz`
3. Cleanup: test job deleted

#### Fix 4: CREDENTIALS.md Updated

- Keycloak PostgreSQL PROD section: password + drift history documented
- Keycloak Admin PROD section: added (did not exist before)
- Last update header updated

### Post-Fix State

| Component        | Status                   | Evidence                                    |
|------------------|--------------------------|---------------------------------------------|
| Keycloak pods    | 2/2 Running (0 restarts) | Both pods started with correct DB password   |
| Admin login      | HTTP 200                 | OIDC token obtained via admin-cli            |
| Backup CronJob   | SUCCESS                  | 4 realms exported to S3 (48KB)               |
| Vault PostgreSQL | v5 (correct)             | ESO SecretSynced=True                        |
| Vault Admin      | v2 (matches DB)          | Hash matches Argon2id credential in DB       |
| K8s secrets      | Both synced              | Both ExternalSecrets SecretSynced=True       |

---

## GAP-HEALTH-006: No promtail in production -- IaC CODIFIED

**Root cause**: Production TF environment (`environments/prod/`) had no `promtail.tf`. Promtail was
only deployed in staging (`environments/staging/promtail.tf`). Loki prod is running and receiving no
logs because there is no promtail DaemonSet shipping logs.

**Fix applied**:
1. **New file**: `environments/prod/promtail.tf` -- reuses existing `modules/promtail` module
2. Configuration: same chart version (6.16.6), same resources (10m CPU, 64Mi memory), prod namespace
3. Loki URL: `http://loki-gateway.prod-observability-monitoring.svc.cluster.local`
4. ECR registry: hardcoded `891377105802.dkr.ecr.us-east-1.amazonaws.com` (prod lacks ECR module)
5. Extra scrape configs: all namespaces (no filter, unlike staging which filters to specific namespaces)

**File**: `platform-provisioning/aws/kubernetes/terraform/environments/prod/promtail.tf`

**TF apply needed**: Yes (prod) -- will create the Helm release and deploy the DaemonSet.

**NOTE**: DO NOT deploy via kubectl. IaC only.

---

## GAP-HEALTH-001: Prometheus 99% Memory on System Node -- IaC CODIFIED

**Root cause**: Prometheus staging running on `ip-10-0-132-116` (t3.medium system node, 3.3GiB allocatable).
Actual memory usage: 2716Mi (~2.7GiB). Node at 99% memory with 229% limits overcommit. OOM/eviction risk.

**Analysis**:
- System nodes are t3.medium (3.3GiB allocatable) -- Prometheus alone consumes 82% of a system node
- Workloads nodes are t3.large (8GiB total, ~7.2GiB allocatable) -- ample headroom
- Prometheus PV is zone-pinned to us-east-1a (EBS RWO), NOT node-pinned (Lesson 22)
- Retention at 15d is excessive for staging -- drives TSDB size and memory footprint

**Solution applied**: Combined Option A (move to workloads) + Option B (right-size)

| Parameter | Before | After | Rationale |
|-----------|--------|-------|-----------|
| `prometheus_node_group` | `system` (hardcoded) | `workloads` (variable) | t3.large 8GiB vs t3.medium 3.3GiB |
| `prometheus_retention` | `15d` (default) | `7d` | Staging does not need 15d of metrics |
| `prometheus_memory_request` | `2Gi` (hardcoded) | `2560Mi` (variable) | Aligned with actual ~2.7Gi usage |
| `prometheus_memory_limit` | `6Gi` (hardcoded) | `4Gi` (variable) | Cap to prevent runaway growth in staging |

**Capacity math (workloads t3.large)**:
- Node allocatable: ~7.2 GiB memory
- Prometheus request: 2.5 GiB (35% of node) -- healthy headroom vs 82% on system
- Memory overcommit: ~55% (4Gi limit / 7.2GiB) vs 229% on system -- safe
- Retention 7d: TSDB size reduction ~53% (15d -> 7d) -- lowers steady-state memory

**System node relief**:
- Removes the largest pod (~2.7GiB) from the 3.3GiB system node
- System node returns to ~30-40% memory (DaemonSets only: promtail, node-exporter, linkerd-cni, etc.)
- Eliminates OOM/eviction risk on system nodes

**IaC changes (3 files)**:
1. Module variables: 3 new variables (`prometheus_node_group`, `prometheus_memory_request`, `prometheus_memory_limit`)
2. Module main.tf: nodeSelector and resources use variables instead of hardcoded values
3. Staging main.tf: overrides to `workloads`/`7d`/`2560Mi`/`4Gi`

**Apply procedure** (lifecycle.ignore_changes=all on helm_release):
1. `terraform apply` registers the changes in TF state but does NOT propagate to cluster (ignore_changes=all)
2. Manual helm upgrade OR kubectl patch required to propagate:
   ```bash
   # Option 1: kubectl patch Prometheus CRD
   kubectl patch prometheus kube-prometheus-stack-prometheus \
     -n staging-observability-monitoring --type=merge \
     -p '{"spec":{"nodeSelector":{"eks.amazonaws.com/nodegroup":"workloads"},"retention":"7d","resources":{"requests":{"memory":"2560Mi"},"limits":{"memory":"4Gi"}}}}'

   # Option 2: helm upgrade (if helm hooks are stable)
   helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     -n staging-observability-monitoring --reuse-values \
     --set prometheus.prometheusSpec.nodeSelector."eks\.amazonaws\.com/nodegroup"=workloads \
     --set prometheus.prometheusSpec.retention=7d \
     --set prometheus.prometheusSpec.resources.requests.memory=2560Mi \
     --set prometheus.prometheusSpec.resources.limits.memory=4Gi
   ```
3. After patch: Prometheus pod will be rescheduled to a workloads node in us-east-1a (PV topology constraint)
4. Verify: `kubectl top nodes | grep system` should show all system nodes below 60% memory

**TF apply needed**: Yes (staging) -- but manual helm upgrade/kubectl patch also required due to ignore_changes=all.

---

## Files Modified

| File | Change | GAP |
|------|--------|-----|
| `modules/opentelemetry-collector/hpa.yaml` | Fix scaleTargetRef name | HEALTH-004 |
| `environments/prod/keycloak-backup.tf` | Add startingDeadlineSeconds + activeDeadlineSeconds | HEALTH-005 |
| `environments/staging/keycloak-backup.tf` | Add startingDeadlineSeconds | HEALTH-005 |
| `environments/prod/promtail.tf` | **NEW** -- promtail prod deployment | HEALTH-006 |
| `modules/kube-prometheus-stack/variables.tf` | Add prometheus_node_group, prometheus_memory_request, prometheus_memory_limit variables | HEALTH-001 |
| `modules/kube-prometheus-stack/main.tf` | Parametrize nodeSelector + resources with variables | HEALTH-001 |
| `environments/staging/main.tf` | Override: workloads, 7d, 2560Mi, 4Gi | HEALTH-001 |
