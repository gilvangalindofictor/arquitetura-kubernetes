# Session Summary: Keycloak + GitLab OIDC Deployment
**Date**: 2026-02-12 18:30 BRT
**Duration**: ~3h (session continuation)
**Status**: ⚠️ PARTIALLY COMPLETE - 3 Critical Issues Pending

---

## ✅ Completed Tasks

### 1. GitLab Ingress Migration (.example.com → .staging.internal)
- **Updated Resources**:
  - `gitlab-webservice-default`: gitlab.example.com → gitlab.staging.internal
  - `gitlab-registry`: registry.example.com → registry.staging.internal
  - `gitlab-kas`: kas.example.com → kas.staging.internal
- **ALB**: k8s-gitlabst-gitlabwe-8e0cbdff6f-189286430.us-east-1.elb.amazonaws.com
- **IP**: 98.87.249.125
- **Status**: ✅ Ingress operational, GitLab UI accessible

### 2. Keycloak 26.5.1 Deployment
- **Method**: Manual kubectl apply (StatefulSet + Service + Ingress)
- **Chart Alternative Abandoned**: codecentric/keycloakx Helm chart failed due to `extraEnv` schema issues
- **Runtime**: Quarkus 3.27.1
- **Database**: PostgreSQL RDS 16.4 (database: keycloak, user: postgres_admin)
- **Configuration**:
  - `--http-relative-path=/auth` (backward compatibility)
  - `--http-enabled=true`
  - `KC_HTTP_MANAGEMENT_HEALTH_ENABLED=false` (critical for health probes)
- **Health Probes**: `/auth/health/ready`, `/auth/health/live` on port 8080
- **Pod Status**: 1/1 Running
- **Ingress**: keycloak.staging.internal (ALB: k8s-platformstaging-00e0ecf3b4-279144409)
- **IP**: 34.230.141.109

### 3. Prometheus Alerts Deployment
- **Resource**: PrometheusRule `prometheus-alert-init-crashloop`
- **Namespace**: monitoring
- **Alerts**:
  1. `InitContainerCrashLoop` - 3+ restarts in 5min (severity: warning)
  2. `InitContainerHighRestartRate` - rate >0.1/sec (severity: critical)
  3. `GitLabInitContainerFailing` - GitLab-specific init failures (severity: critical, oncall: platform-team)
- **Status**: ✅ Deployed and active

### 4. Windows Hosts File Update
- **File**: `/tmp/windows-hosts-final-2026-02-12.txt`
- **Entries**:
  ```
  # GitLab Services (ALB: k8s-gitlabst-gitlabwe-8e0cbdff6f-189286430)
  98.87.249.125   gitlab.staging.internal
  98.87.249.125   registry.staging.internal
  98.87.249.125   kas.staging.internal

  # Platform Services (ALB: k8s-platformstaging-00e0ecf3b4-279144409)
  34.230.141.109  argocd.staging.internal
  34.230.141.109  keycloak.staging.internal
  ```
- **Status**: ✅ Generated, user must copy to `C:\Windows\System32\drivers\etc\hosts`

---

## ❌ Pending Issues (STOP-AND-FIX Protocol)

### Issue #1: Keycloak Admin User Missing
**Severity**: 🔴 CRITICAL
**URL**: http://keycloak.staging.internal/auth
**Error**: "Local access required - You will need local access to create the administrative user"

**Root Cause**:
- Keycloak 26.x `KEYCLOAK_ADMIN_PASSWORD` env var only works on fresh database
- Migration from 17→26 preserves existing users but password hash incompatible
- Current deployment has NO admin user bootstrapped

**Impact**: Cannot manage realms, clients, or users via Admin Console

**Fix Options**:
1. **Exec into pod + kcadm.sh** (recommended):
   ```bash
   kubectl exec -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh config credentials \
     --server http://localhost:8080/auth --realm master --user admin --password <new-pass>
   kubectl exec -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh create users \
     -r master -s username=admin -s enabled=true
   ```

2. **PostgreSQL direct insert** (used previously for clients):
   - Create user in `user_entity` table
   - Hash password with PBKDF2-SHA256
   - Grant admin roles in `user_role_mapping`

3. **Delete database + fresh deploy** (nuclear option):
   - DROP DATABASE keycloak; CREATE DATABASE keycloak;
   - Redeploy StatefulSet with `KEYCLOAK_ADMIN_PASSWORD` env var
   - Recreate all realms/clients from scratch

**Recommended**: Option #1 (exec + kcadm.sh)

---

### Issue #2: ArgoCD OIDC Issuer Using Internal DNS
**Severity**: 🔴 CRITICAL
**URL**: http://argocd.staging.internal
**Redirect Target**: `http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform/protocol/openid-connect/auth?client_id=argocd&...`

**Root Cause**:
- ArgoCD OIDC config has issuer pointing to Kubernetes internal DNS
- Browser cannot resolve `.svc.cluster.local` domains (only resolvable inside cluster)

**Current Config** (incorrect):
```yaml
oidc.config: |
  issuer: http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform
```

**Required Fix**:
```yaml
oidc.config: |
  issuer: http://keycloak.staging.internal/auth/realms/platform
  clientID: argocd
  clientSecret: <secret-from-keycloak>
  requestedScopes: ["openid", "profile", "email", "groups"]
```

**Fix Command**:
```bash
kubectl patch configmap -n argocd argocd-cm --type merge -p '{
  "data": {
    "oidc.config": "issuer: http://keycloak.staging.internal/auth/realms/platform\nclientID: argocd\nclientSecret: <secret>\nrequestedScopes: [\"openid\", \"profile\", \"email\", \"groups\"]"
  }
}'
kubectl rollout restart deployment -n argocd argocd-server
```

**Blocker**: Need Keycloak admin access (Issue #1) to create ArgoCD client + secret

---

### Issue #3: GitLab OIDC Login Failing
**Severity**: 🔴 CRITICAL
**URL**: http://gitlab.staging.internal/users/auth/openid_connect
**Error**: Unknown (user reported error, no details captured)

**Suspected Root Cause** (same as Issue #2):
- GitLab OIDC secret may have issuer pointing to internal DNS
- OR: Client credentials invalid/placeholder

**Current Secret** (from previous work):
- Namespace: `gitlab-staging`
- Secret: `gitlab-oidc-keycloak`
- Key: `provider`
- Value: YAML string with OIDC config

**Required Validation**:
```bash
kubectl get secret -n gitlab-staging gitlab-oidc-keycloak -o jsonpath='{.data.provider}' | base64 -d
```

**Expected Config**:
```yaml
name: "openid_connect"
args:
  name: "openid_connect"
  issuer: "http://keycloak.staging.internal/auth/realms/platform"
  discovery: true
  client_options:
    identifier: "gitlab"
    secret: "<real-secret-not-placeholder>"
    redirect_uri: "http://gitlab.staging.internal/users/auth/openid_connect/callback"
  args:
    pkce: true
```

**Fix Dependencies**:
1. Resolve Keycloak admin access (Issue #1)
2. Verify/create GitLab client in Keycloak with correct redirect URI
3. Update secret with real client secret
4. Restart GitLab webservice: `kubectl rollout restart deployment -n gitlab-staging gitlab-webservice-default`

---

## 📋 Next Steps (Priority Order)

### Step 1: Keycloak Admin Bootstrap (BLOCKING)
```bash
# Option A: kcadm.sh inside pod
kubectl exec -it -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080/auth --realm master --user admin --password Admin123!

# Option B: PostgreSQL direct user creation
kubectl run psql-admin -n keycloak --rm -it --restart=Never \
  --image=postgres:16.4-alpine -- \
  psql "postgresql://postgres_admin:<pass>@k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432/keycloak?sslmode=require" \
  -c "INSERT INTO user_entity (id, username, realm_id, enabled) VALUES (gen_random_uuid(), 'admin', 'master', true);"
```

**Validation**: Access http://keycloak.staging.internal/auth/admin → login successful

---

### Step 2: Create OIDC Clients in Keycloak
Once admin access restored:

**ArgoCD Client**:
- Client ID: `argocd`
- Redirect URI: `http://argocd.staging.internal/auth/callback`
- Client Secret: Generate + save to K8s secret

**GitLab Client** (verify existing or recreate):
- Client ID: `gitlab`
- Redirect URI: `http://gitlab.staging.internal/users/auth/openid_connect/callback`
- Client Secret: Update K8s secret `gitlab-oidc-keycloak`

---

### Step 3: Update OIDC Configurations

**ArgoCD**:
```bash
# Update ConfigMap with external issuer
kubectl edit configmap -n argocd argocd-cm
# Change issuer: http://keycloak-http.keycloak.svc.cluster.local → http://keycloak.staging.internal

# Restart ArgoCD
kubectl rollout restart deployment -n argocd argocd-server
```

**GitLab**:
```bash
# Verify secret has correct issuer
kubectl get secret -n gitlab-staging gitlab-oidc-keycloak -o jsonpath='{.data.provider}' | base64 -d

# If incorrect, patch with correct issuer
kubectl create secret generic gitlab-oidc-keycloak -n gitlab-staging \
  --from-literal=provider="<correct-yaml>" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart webservice
kubectl rollout restart deployment -n gitlab-staging gitlab-webservice-default
```

---

### Step 4: End-to-End OIDC Testing

**Test Matrix**:
| Application | Login URL | Expected Result |
|-------------|-----------|-----------------|
| Keycloak | http://keycloak.staging.internal/auth/admin | Admin Console accessible |
| ArgoCD | http://argocd.staging.internal → Login with SSO | Redirect to Keycloak → callback to ArgoCD |
| GitLab | http://gitlab.staging.internal → Sign in with OpenID Connect | Redirect to Keycloak → callback to GitLab |

**Success Criteria**:
- ✅ Keycloak admin login works
- ✅ ArgoCD OIDC redirect stays in `.staging.internal` domain (no `.svc.cluster.local`)
- ✅ GitLab OIDC login completes full flow (authenticate → redirect → auto-create user)

---

## 🔍 Technical Insights (Lessons Learned)

### Keycloak Helm Chart Pitfall
**Problem**: codecentric/keycloakx chart requires `extraEnv` as STRING type (pipe literal `|`), not ARRAY
**Attempts**: 8+ failed Helm installations with different values.yaml formats
**Resolution**: Abandoned Helm, used kubectl apply with raw StatefulSet YAML
**Lesson**: For critical services, validate chart schema constraints BEFORE deployment

### Health Probe Path with http-relative-path
**Problem**: Health probes returned 404 even with `KC_HTTP_ENABLED=true`
**Root Cause**: When `--http-relative-path=/auth` is set, ALL endpoints inherit `/auth` prefix
**Fix**: Probes MUST use `/auth/health/ready` and `/auth/health/live` (not `/health/ready`)
**Critical Env Var**: `KC_HTTP_MANAGEMENT_HEALTH_ENABLED=false` (expose health on HTTP port 8080, not mgmt port 9000)
**Reference**: [docs/logbook/2026-02-11-keycloak-26-deployment-final.md](../logbook/2026-02-11-keycloak-26-deployment-final.md) L40-139

### OIDC Issuer DNS Resolution
**Problem**: OIDC redirects fail when issuer uses internal cluster DNS (`.svc.cluster.local`)
**Cause**: Browser cannot resolve Kubernetes internal DNS, only accessible inside cluster
**Solution**: ALWAYS use external domains in OIDC issuer URLs (e.g., `keycloak.staging.internal`)
**Pattern**: Internal services → external DNS → Ingress → internal Service → Pod

---

## 📊 Deployment Summary

### Infrastructure
- **Cluster**: k8s-platform-staging (EKS 1.34)
- **Region**: us-east-1
- **ALBs**: 2 (gitlab-staging, platform-staging)
- **Database**: PostgreSQL RDS 16.4 (k8s-platform-prod-postgresql)
- **Keycloak Version**: 26.5.1 (Quarkus 3.27.1)
- **GitLab Version**: (check gitlab-webservice image tag)

### Services Status
| Service | Namespace | Pods | Ingress | Status |
|---------|-----------|------|---------|--------|
| Keycloak | keycloak | 1/1 Running | keycloak.staging.internal | ⚠️ Admin missing |
| GitLab Webservice | gitlab-staging | ?/? | gitlab.staging.internal | ⚠️ OIDC broken |
| ArgoCD | argocd | ?/? | argocd.staging.internal | ⚠️ OIDC broken |
| Prometheus | monitoring | ?/? | - | ✅ Alerts deployed |

### Files Generated
1. `/tmp/windows-hosts-final-2026-02-12.txt` - Windows hosts file (user must apply)
2. `/tmp/keycloak-statefulset.yaml` - Keycloak StatefulSet (applied)
3. `/tmp/keycloak-ingress.yaml` - Keycloak Ingress (applied)
4. `/tmp/prometheus-alert-init-crashloop.yaml` - PrometheusRule (applied)

---

## 🎯 Success Metrics

**Completed**:
- ✅ GitLab Ingress migrated to .staging.internal (3 resources)
- ✅ Keycloak deployed and Running (1/1 pods)
- ✅ Prometheus init-container alerts deployed (3 alerts)
- ✅ Windows hosts file generated with correct IPs

**Pending**:
- ❌ Keycloak admin user creation
- ❌ ArgoCD OIDC configuration fix
- ❌ GitLab OIDC end-to-end test
- ❌ Terraform migration (blocked by WSL2 RDS connectivity)

**Effort**: ~3h (troubleshooting Helm chart issues, health probe debugging)

---

## 💾 Backup/Recovery

**Critical Resources to Backup**:
1. Keycloak database `keycloak` (RDS snapshot before any admin changes)
2. K8s secrets:
   - `keycloak-db-secret` (keycloak namespace)
   - `gitlab-oidc-keycloak` (gitlab-staging namespace)
   - `argocd-secret` (argocd namespace - if exists)

**Recovery Procedure**:
```bash
# Snapshot RDS before Keycloak admin changes
aws rds create-db-snapshot \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --db-snapshot-identifier keycloak-pre-admin-fix-2026-02-12

# Backup K8s secrets
kubectl get secret -n keycloak keycloak-db-secret -o yaml > /tmp/keycloak-db-secret-backup.yaml
kubectl get secret -n gitlab-staging gitlab-oidc-keycloak -o yaml > /tmp/gitlab-oidc-backup.yaml
```

---

## 📚 References

- [Keycloak 26 Deployment Final](../logbook/2026-02-11-keycloak-26-deployment-final.md)
- [PostgreSQL Database Provisioning Fix](../logbook/2026-02-12-postgresql-database-provisioning-fix.md)
- [Executor Terraform Prompt](../prompts/executor-terraform.md)
- [Init Container CrashLoop Alert](../../platform-provisioning/aws/kubernetes/terraform/modules/observability/prometheus-alerts/init-containers-crashloop.yaml)

---

**Document Status**: 🔴 DRAFT - Issues pending resolution
**Next Review**: After Keycloak admin access restored
**Owner**: Platform Team
**Incident Tracking**: N/A (planned maintenance)
