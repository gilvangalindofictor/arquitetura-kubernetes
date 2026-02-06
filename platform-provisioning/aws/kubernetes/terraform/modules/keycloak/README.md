# Keycloak SSO Platform Module

## Overview

This module deploys **Keycloak** as a centralized SSO (Single Sign-On) platform for OIDC authentication across the platform components (ArgoCD, SonarQube, GitLab, Grafana).

**Key Features:**
- ✅ High Availability (2 replicas with anti-affinity)
- ✅ External PostgreSQL (RDS integration)
- ✅ AWS Secrets Manager integration (R-029 technical debt)
- ✅ Prometheus ServiceMonitor (ADR-006)
- ✅ System node tolerations (ADR-042)
- ✅ Health probes (liveness, readiness, startup)
- ✅ Pod Disruption Budget (minAvailable: 1)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  OIDC Clients (Applications)                            │
│  • ArgoCD                                               │
│  • SonarQube                                            │
│  • GitLab                                               │
│  • Grafana                                              │
└────────────────────┬────────────────────────────────────┘
                     │ OIDC Authentication
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Keycloak HA (2 replicas)                               │
│  • Master Realm                                         │
│  • Groups: argocd-admins, developers, platform-admins   │
│  • ServiceMonitor → Prometheus                          │
└────────────────────┬────────────────────────────────────┘
                     │ JDBC Connection
                     ▼
┌─────────────────────────────────────────────────────────┐
│  PostgreSQL RDS (External Database)                     │
│  • Database: keycloak                                   │
│  • User: keycloak_user                                  │
│  • Password: AWS Secrets Manager                        │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. AWS Secrets Manager Secret

Create the PostgreSQL password secret **before** running terraform:

```bash
# Create secret
aws secretsmanager create-secret \
  --name staging/postgresql/keycloak-password \
  --description "PostgreSQL password for keycloak_user (RDS database)" \
  --secret-string "$(openssl rand -base64 32)" \
  --region us-east-1

# Verify secret created
aws secretsmanager describe-secret \
  --secret-id staging/postgresql/keycloak-password \
  --query 'ARN' --output text
```

### 2. PostgreSQL Database Bootstrap

Add `keycloak` database to the PostgreSQL module's `additional_databases` parameter:

```hcl
module "postgresql_staging" {
  source = "../../modules/postgresql"

  additional_databases = [
    {
      name     = "keycloak"
      username = "keycloak_user"
      password = data.aws_secretsmanager_secret_version.keycloak_db_password.secret_string
    }
  ]
}
```

## Usage

### Basic Configuration

```hcl
module "keycloak_staging" {
  source = "../../modules/keycloak"

  # Cluster info
  cluster_name = local.cluster_name
  aws_region   = "us-east-1"
  namespace    = "keycloak"

  # Keycloak configuration
  keycloak_chart_version = "18.4.0"
  replicas               = 2  # HA for critical SSO service

  # PostgreSQL (external - RDS via module)
  postgresql_host     = module.postgresql_staging.service_name
  postgresql_port     = 5432
  postgresql_database = "keycloak"
  postgresql_username = "keycloak_user"

  # Monitoring
  enable_monitoring = true

  # Tags
  common_tags = local.common_tags
}
```

### With Dependencies

```hcl
module "keycloak_staging" {
  source = "../../modules/keycloak"

  depends_on = [
    module.postgresql_staging
  ]

  # ... configuration
}
```

## Outputs

| Output | Description | Sensitive |
|--------|-------------|-----------|
| `namespace` | Keycloak Kubernetes namespace | No |
| `keycloak_url` | Internal cluster DNS URL | No |
| `keycloak_admin_url` | Admin console URL | No |
| `admin_password_secret` | K8s secret name containing admin password | Yes |
| `realm_url` | Master realm URL (OIDC issuer) | No |

### Accessing Outputs

```bash
# Get Keycloak URL
terraform output keycloak_url

# Get admin password
kubectl get secret keycloak-admin-password -n keycloak \
  -o jsonpath='{.data.password}' | base64 -d
```

## Post-Deployment Configuration

### 1. Access Admin Console

```bash
# Port-forward to access locally
kubectl port-forward -n keycloak svc/keycloak-http 8080:8080

# Browser: http://localhost:8080/admin
# Login: admin / <password from secret>
```

### 2. Create OIDC Clients

#### ArgoCD Client

1. Navigate to: **Clients** → **Create Client**
2. Configuration:
   - **Client ID**: `argocd`
   - **Client Protocol**: `openid-connect`
   - **Access Type**: `confidential`
   - **Valid Redirect URIs**: `https://argocd.example.com/*`
   - **Web Origins**: `https://argocd.example.com`
3. **Save** → Navigate to **Credentials** tab
4. **Copy Client Secret** → Store in Kubernetes secret:

```bash
kubectl create secret generic argocd-oidc-secret \
  -n argocd \
  --from-literal=clientSecret=<keycloak-argocd-client-secret>
```

#### SonarQube Client

1. **Client ID**: `sonarqube`
2. **Access Type**: `confidential`
3. **Valid Redirect URIs**: `https://sonarqube.example.com/*`
4. Copy client secret and store:

```bash
kubectl create secret generic sonarqube-oidc \
  -n sonarqube \
  --from-literal=clientId=sonarqube \
  --from-literal=clientSecret=<keycloak-sonarqube-secret>
```

#### GitLab Client (Optional)

1. **Client ID**: `gitlab`
2. **Access Type**: `confidential`
3. **Valid Redirect URIs**: `https://gitlab.example.com/*`

### 3. Create Groups and Users

#### Groups

Navigate to: **Master realm** → **Groups** → **Create Group**

Required groups:
- `argocd-admins` - Full ArgoCD access
- `developers` - Standard developer access
- `sonarqube-users` - SonarQube access
- `platform-admins` - Platform administrator access

#### Test User

1. Navigate to: **Users** → **Add user**
2. Configuration:
   - **Username**: `admin.platform`
   - **Email**: `admin@example.com`
   - **Email Verified**: ON
3. **Credentials** tab → Set password
4. **Groups** tab → Join groups: `argocd-admins`, `platform-admins`

### 4. Verify OIDC Configuration

```bash
# Test OIDC discovery endpoint
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -- \
  curl -s http://keycloak-http.keycloak.svc.cluster.local:8080/realms/master/.well-known/openid-configuration | jq .

# Expected: JSON with issuer, authorization_endpoint, token_endpoint, etc.
```

## Monitoring

### ServiceMonitor

The module automatically creates a ServiceMonitor for Prometheus scraping:

```bash
# Verify ServiceMonitor
kubectl get servicemonitor -n keycloak

# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Browser: http://localhost:9090/targets
# Filter: keycloak
```

### Key Metrics

```promql
# Keycloak health status
up{job="keycloak"}

# HTTP requests
keycloak_http_requests_total

# Active sessions
keycloak_sessions

# Login failures
keycloak_failed_login_attempts_total
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n keycloak

# Check logs
kubectl logs -n keycloak keycloak-0 --tail=100

# Check events
kubectl get events -n keycloak --sort-by='.lastTimestamp'
```

### Database Connection Issues

```bash
# Verify PostgreSQL secret exists
aws secretsmanager describe-secret --secret-id staging/postgresql/keycloak-password

# Test database connectivity
kubectl run -it --rm psql-test --image=postgres:15 --restart=Never -- \
  psql -h <rds-endpoint> -U keycloak_user -d keycloak -c "SELECT version();"
```

### Admin Password Not Working

```bash
# Get password from Kubernetes secret
kubectl get secret keycloak-admin-password -n keycloak \
  -o jsonpath='{.data.password}' | base64 -d

# Check Terraform output
terraform output -json | jq '.keycloak_admin_password_secret'
```

## Cost Estimation

**Infrastructure Costs:**
- 2 Keycloak replicas: ~2 vCPU, 4GB RAM
- Fits in existing system nodes (toleration pattern ADR-042)
- **Incremental cost**: $0 (uses provisioned capacity)

**AWS Services:**
- AWS Secrets Manager: 1 secret × $0.40/month = **$0.40/month**
- PostgreSQL database: Shared RDS instance = **$0/month** (incremental)

**Total Estimated Cost**: **~$0.40/month**

## Technical Decisions

### R-029: AWS Secrets Manager Technical Debt

**Decision**: Use AWS Secrets Manager data sources instead of ExternalSecrets Operator (ESO) + Vault.

**Rationale**:
- ✅ Unblocks Keycloak deployment immediately
- ✅ Follows established pattern (Harbor, GitLab)
- ✅ Minimal cost ($0.40/month)
- ⚠️ Technical debt: Not cloud-agnostic

**Migration Plan (Sprint+1)**:
1. Configure Vault Kubernetes auth method
2. Create ExternalSecret CRDs for Keycloak secrets
3. Migrate `staging/postgresql/keycloak-password` → Vault KV
4. Update module to use ESO instead of data sources
5. Deprecate AWS SM secrets after 30-day validation period

### ADR-042: Tolerations for Critical Workloads

**Decision**: Apply system node tolerations to Keycloak pods.

**Rationale**:
- ✅ Keycloak is critical for authentication (OIDC provider)
- ✅ System nodes have better SLA guarantees
- ✅ Prevents scheduling on ephemeral worker nodes
- ✅ Consistent with Vault, Harbor, Redis pattern

## Dependencies

- **PostgreSQL Module**: Database must exist before Keycloak deployment
- **AWS Secrets Manager**: Secret `staging/postgresql/keycloak-password` must exist
- **Kube-Prometheus-Stack**: Required for ServiceMonitor (if `enable_monitoring=true`)

## Version Compatibility

| Component | Version | Notes |
|-----------|---------|-------|
| Keycloak | 21.1.2 | Latest stable Keycloak 21.x |
| Helm Chart (codecentric) | 18.4.0 | Chart version |
| PostgreSQL | 11+ | RDS or operator |
| Kubernetes | 1.24+ | Tested on EKS 1.27 |

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Codecentric Helm Chart](https://github.com/codecentric/helm-charts/tree/master/charts/keycloak)
- [OIDC Specification](https://openid.net/specs/openid-connect-core-1_0.html)
- [ADR-042: Tolerations Pattern](../../../docs/context/decisions.md)
- [R-029: AWS SM Technical Debt](../../../docs/context/risks.md)
