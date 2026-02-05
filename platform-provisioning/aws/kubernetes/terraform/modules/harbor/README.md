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

```bash
# 1. Get Harbor admin password
export HARBOR_ADMIN_PASSWORD=$(kubectl get secret harbor-admin-password \
  -n harbor-system -o jsonpath='{.data.password}' | base64 -d)

# 2. Run the creation script
export HARBOR_URL="http://harbor-core.harbor-system.svc.cluster.local"
export ROBOT_NAME="gitlab-ci"
export PROJECT_NAME="library"

bash scripts/create-robot-account.sh
```

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
