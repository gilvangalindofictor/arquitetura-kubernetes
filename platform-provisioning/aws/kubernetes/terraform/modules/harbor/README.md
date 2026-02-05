# Harbor Container Registry Module

Private container registry with Trivy scanning and S3 storage (IRSA).

## Features

- **S3 Storage Backend**: IRSA-enabled (no credentials in cluster)
- **External PostgreSQL**: Shared RDS (cost-optimized)
- **External Redis**: Spotahome Operator
- **Trivy Scanner**: Disabled (PVC issue, enable when gp3 available)
- **Metrics**: ServiceMonitor enabled for Prometheus

## Robot Accounts (CI/CD)

Harbor robot accounts provide least-privilege credentials for CI/CD pipelines.

### Creating a Robot Account

⚠️ **Known Issue (ADR-045):** Harbor v2.10.0 API robot creation returns 401 Unauthorized. Use **UI workaround** below.

#### Option 1: UI Creation (Recommended)

See detailed guide: [scripts/create-robot-manual-steps.md](scripts/create-robot-manual-steps.md)

**Quick Steps:**
```bash
# 1. Port-forward Harbor UI
kubectl port-forward -n harbor-system svc/harbor 8080:80

# 2. Browser: http://localhost:8080
# Login: admin / <password from secret>

# 3. Projects → library → Robot Accounts → + NEW ROBOT ACCOUNT
# Name: gitlab-ci
# Permissions: push, pull, delete artifact
# Expiration: Never (or 365 days)

# 4. Copy token (shown once!)
```

#### Option 2: API Creation (Blocked - see ADR-045)

```bash
# ⚠️ Currently failing with HTTP 401 Unauthorized
# Root cause under investigation (PostgreSQL sysadmin_flag or session auth)

# 1. Get Harbor admin password
export HARBOR_ADMIN_PASSWORD=$(kubectl get secret harbor-admin-password \
  -n harbor-system -o jsonpath='{.data.password}' | base64 -d)

# 2. Run the creation script
export HARBOR_URL="http://harbor-core.harbor-system.svc.cluster.local"
export ROBOT_NAME="gitlab-ci"
export PROJECT_NAME="library"

bash scripts/create-robot-account.sh  # ← Expected to fail
```

**Troubleshooting:** See [Known Issues](#harbor-robot-account-api-issue-adr-045) below.

### Using Robot Account in GitLab CI

Add to GitLab project CI/CD variables:

```yaml
# .gitlab-ci.yml
variables:
  HARBOR_REGISTRY: harbor-core.harbor-system.svc.cluster.local
  HARBOR_PROJECT: library
  HARBOR_USER: robot$gitlab-ci  # From script output
  HARBOR_PASSWORD: <robot-secret>  # From script output (CI/CD variable)

build:
  script:
    - docker login $HARBOR_REGISTRY -u "$HARBOR_USER" -p "$HARBOR_PASSWORD"
    - docker build -t $HARBOR_REGISTRY/$HARBOR_PROJECT/myapp:$CI_COMMIT_SHA .
    - docker push $HARBOR_REGISTRY/$HARBOR_PROJECT/myapp:$CI_COMMIT_SHA
```

### Security Best Practices

- **Scope**: Limit robot account to specific project
- **Permissions**: Only push/pull/delete (no admin)
- **Expiration**: Set duration (e.g., 365 days) and rotate
- **Secrets**: Store in GitLab CI/CD variables (masked)

## Known Issues

### Harbor Robot Account API Issue (ADR-045)

**Problem**: Harbor v2.10.0 API `/projects/{project}/robots` returns HTTP 401 Unauthorized.

**Symptoms:**
```bash
# Working (public endpoint)
curl -u admin:password http://harbor/api/v2.0/systeminfo  # → 200 ✅

# Failing (write operations)
curl -u admin:password -X POST http://harbor/api/v2.0/projects/library/robots  # → 401 ❌
curl -u admin:password http://harbor/api/v2.0/users/current  # → 401 ❌
```

**Root Cause Hypotheses:**
1. Admin user `sysadmin_flag=false` in PostgreSQL (unconfirmed - pg_hba.conf blocks investigation)
2. Harbor v2.10.0 requires session-based auth (not Basic Auth) for write endpoints
3. Password hash mismatch between Kubernetes secret and PostgreSQL DB

**Workaround:**
- ✅ Use Harbor Web UI for robot account creation (5min manual process)
- ✅ Detailed guide: [scripts/create-robot-manual-steps.md](scripts/create-robot-manual-steps.md)
- ✅ Tested and working for `robot$gitlab-ci` (library project)

**Investigation Backlog:**
- [ ] Query PostgreSQL `harbor_user.sysadmin_flag` via RDS bastion
- [ ] Test cookie/session-based auth with `/c/login` endpoint
- [ ] Review Harbor v2.10.0 release notes for auth changes

**References:**
- [ADR-045: Harbor Robot Accounts UI Workaround](../../../docs/context/decisions.md#adr-045)
- [Logbook 2026-02-05](../../../docs/logbook/2026-02-05-harbor-robot-accounts.md)

---

### Harbor Jobservice PVC (ADR-039)

**Problem**: jobservice uses RWO PVC, limiting to 1 replica.

**Current**: `replicas: 1` in values.yaml.tpl

**Production Fix Options**:
1. **EFS + ReadWriteMany**: Multi-replica HA (cost: ~$3.60/month)
2. **emptyDir**: Remove PVC, ephemeral storage (job logs lost on restart)
3. **S3 logs**: Custom solution (requires chart fork)

**Recommendation**: Keep replicas=1 for staging, use EFS in prod if HA required.

## Outputs

- `harbor_url`: Internal cluster URL
- `admin_password_secret_name`: K8s secret with admin password
- `namespace`: Harbor namespace
