# OIDC Integration Quick Reference

**Last Updated**: 2026-02-11
**Category**: Quick Reference

---

## CoreDNS Configuration

### Add New Service to Split-Horizon DNS

```bash
# 1. Edit CoreDNS ConfigMap
kubectl edit configmap -n kube-system coredns

# 2. Add rewrite rule in staging.internal zone:
rewrite name <service>.staging.internal <service-name>.<namespace>.svc.cluster.local

# 3. Reload CoreDNS
kubectl rollout restart deployment -n kube-system coredns

# 4. Test resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <service>.staging.internal
```

---

## Keycloak OIDC Client Creation

### Option A: Via Database (Workaround)

```sql
-- Connect to Keycloak database
kubectl exec -n keycloak keycloak-0 -- psql \
  -h postgresql-external.default.svc.cluster.local \
  -U keycloak_user \
  -d keycloak

-- Insert client
INSERT INTO client (id, client_id, realm_id, enabled, protocol, public_client)
VALUES (
  '<uuid>',
  '<client-name>',
  'platform',
  true,
  'openid-connect',
  false
);

-- Insert client secret
INSERT INTO client_credentials (client_id, type, value)
VALUES ('<uuid>', 'secret', '<client-secret>');

-- Insert redirect URI
INSERT INTO redirect_uris (client_id, value)
VALUES ('<uuid>', 'http://<service>.staging.internal/callback');
```

**Generate Client Secret**:
```bash
openssl rand -base64 32
```

### Option B: Via Admin UI (When Available)

```
1. Login to Keycloak admin: http://keycloak.staging.internal/auth/admin
2. Select realm: platform
3. Clients → Create
   - Client ID: <service-name>
   - Client Protocol: openid-connect
   - Access Type: confidential
4. Settings:
   - Valid Redirect URIs: http://<service>.staging.internal/callback
   - Save
5. Credentials tab:
   - Copy Client Secret
```

---

## GitLab OIDC Configuration

### Kubernetes Secret Format

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <service>-oidc-keycloak
  namespace: <service-namespace>
  labels:
    app: <service>
    component: omniauth
type: Opaque
stringData:
  provider: |
    name: 'openid_connect'
    label: 'Keycloak SSO'
    icon: 'https://www.keycloak.org/resources/images/keycloak_icon_128px.svg'
    args:
      name: 'openid_connect'
      scope: ['openid', 'profile', 'email']
      response_type: 'code'
      issuer: 'http://keycloak.staging.internal/auth/realms/platform'
      client_auth_method: 'query'
      discovery: true
      uid_field: 'preferred_username'
      pkce: true
      client_options:
        identifier: '<client-id>'
        secret: '<client-secret>'
        redirect_uri: 'http://<service>.staging.internal/users/auth/openid_connect/callback'
```

### Helm Values (GitLab)

```yaml
global:
  appConfig:
    omniauth:
      enabled: true
      allowSingleSignOn: ['openid_connect']
      blockAutoCreatedUsers: false
      autoLinkUser: ['openid_connect']
      syncProfileFromProvider: ['openid_connect']
      syncProfileAttributes: ['email']
      providers:
        - secret: <service>-oidc-keycloak
          key: provider
```

---

## ArgoCD OIDC Configuration

### ConfigMap Format

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: http://argocd.staging.internal
  oidc.config: |
    name: Keycloak
    issuer: http://keycloak.staging.internal/auth/realms/platform
    clientID: argocd
    clientSecret: $oidc.keycloak.clientSecret
    requestedScopes: ["openid", "profile", "email", "groups"]
```

### Secret Format

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
stringData:
  oidc.keycloak.clientSecret: <client-secret>
```

---

## Grafana OIDC Configuration

### Helm Values

```yaml
grafana:
  grafana.ini:
    server:
      root_url: http://grafana.staging.internal
    auth.generic_oauth:
      enabled: true
      name: Keycloak
      allow_sign_up: true
      client_id: grafana
      client_secret: <client-secret>
      scopes: openid profile email
      auth_url: http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/auth
      token_url: http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/token
      api_url: http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/userinfo
      role_attribute_path: contains(groups[*], 'grafana-admin') && 'Admin' || 'Viewer'
```

---

## Validation Commands

### Test OIDC Discovery Endpoint

```bash
curl http://keycloak.staging.internal/auth/realms/platform/.well-known/openid-configuration | jq '.'

# Expected fields:
# - issuer
# - authorization_endpoint
# - token_endpoint
# - userinfo_endpoint
# - jwks_uri
```

### Test DNS Resolution

```bash
# From within cluster
kubectl run -it --rm debug --image=curlimages/curl:latest --restart=Never -- \
  curl -I http://keycloak.staging.internal/auth/realms/platform

# Expected: HTTP 200 OK
```

### Test Service Accessibility

```bash
# From browser host
curl -I http://keycloak.staging.internal/auth/realms/platform

# If connection refused, check:
# 1. DNS resolution: nslookup keycloak.staging.internal
# 2. Network connectivity: ping <ClusterIP>
# 3. Security Groups: allow traffic from browser host
```

### Debug OIDC Login Flow

```bash
# GitLab webservice logs
kubectl logs -n gitlab-staging -l app=webservice -c webservice --tail=100 | grep -i omniauth

# Keycloak logs
kubectl logs -n keycloak -l app=keycloak --tail=100 | grep -i oauth
```

---

## Common Issues

### Issue: redirect_uri_mismatch

**Cause**: OIDC client redirect URI doesn't match request.

**Fix**:
```sql
-- Check current redirect URI in database
SELECT value FROM redirect_uris WHERE client_id = '<uuid>';

-- Update if needed
UPDATE redirect_uris SET value = 'http://<service>.staging.internal/callback'
WHERE client_id = '<uuid>';
```

### Issue: Discovery Endpoint 404

**Cause**: Issuer URL missing `/auth` prefix.

**Fix**: Ensure issuer URL is:
```
http://keycloak.staging.internal/auth/realms/platform
```

NOT:
```
http://keycloak.staging.internal/realms/platform
```

### Issue: Client Secret Invalid

**Cause**: Secret mismatch between Keycloak and service config.

**Fix**:
```sql
-- Check client secret in Keycloak database
SELECT value FROM client_credentials WHERE client_id = '<uuid>' AND type = 'secret';

-- Update service K8s Secret to match
kubectl edit secret -n <namespace> <service>-oidc-keycloak
```

### Issue: User Not Auto-Created

**Cause**: `blockAutoCreatedUsers: true` in OmniAuth config.

**Fix**:
```yaml
omniauth:
  blockAutoCreatedUsers: false  # Allow auto-creation
  autoLinkUser: ['openid_connect']  # Link OIDC identity
```

---

## Rollback Procedures

### Disable OIDC for Service

**Option 1: Terraform**
```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
# Edit main.tf: enable_oidc = false
terraform apply -target=module.<service>_staging
kubectl rollout restart deployment -n <namespace> <service>
```

**Option 2: Helm**
```bash
helm get values <service> -n <namespace> > values.yaml
# Edit values.yaml: omniauth.enabled: false
helm upgrade <service> <chart> -n <namespace> -f values.yaml
```

**Option 3: Emergency (Scale Down)**
```bash
kubectl scale deployment -n <namespace> <service> --replicas=0
kubectl delete secret -n <namespace> <service>-oidc-keycloak
kubectl scale deployment -n <namespace> <service> --replicas=2
```

### Remove Service from Split-Horizon DNS

```bash
kubectl edit configmap -n kube-system coredns
# Remove rewrite line for service
kubectl rollout restart deployment -n kube-system coredns
```

---

## Production Checklist

Before enabling OIDC in production:

- [ ] HTTPS enabled (cert-manager + TLS certificates)
- [ ] External DNS configured (no split-horizon DNS)
- [ ] Group-based access control configured
- [ ] Client secrets stored in Vault (not K8s Secrets)
- [ ] Audit logging enabled (track OIDC logins)
- [ ] Security review completed
- [ ] Rollback plan documented
- [ ] Monitoring alerts configured (OIDC failure rate)
- [ ] Load testing completed (concurrent OIDC logins)
- [ ] Documentation updated (production URLs)

---

## Terraform Module Pattern

### Directory Structure

```
modules/<service>/
├── main.tf           # Helm release + K8s resources
├── variables.tf      # enable_oidc variable
├── values.yaml.tpl   # Helm values with omniauth section
└── outputs.tf        # Service endpoints
```

### Key Variables

```hcl
variable "enable_oidc" {
  description = "Enable OIDC authentication with Keycloak"
  type        = bool
  default     = false
}
```

### Template Usage

```hcl
values = [
  templatefile("${path.module}/values.yaml.tpl", {
    enable_oidc = var.enable_oidc
    # ... other variables
  })
]
```

---

## Useful URLs

### Staging Environment

- **Keycloak Admin**: http://keycloak.staging.internal/auth/admin
- **Keycloak Realm**: http://keycloak.staging.internal/auth/realms/platform
- **OIDC Discovery**: http://keycloak.staging.internal/auth/realms/platform/.well-known/openid-configuration
- **GitLab**: http://gitlab.staging.internal
- **ArgoCD**: http://argocd.staging.internal
- **Grafana**: http://grafana.staging.internal

### Database Access

```bash
# Keycloak database
kubectl exec -n keycloak keycloak-0 -- psql \
  -h postgresql-external.default.svc.cluster.local \
  -U keycloak_user \
  -d keycloak

# Tables of interest
\dt client*
SELECT client_id, realm_id, enabled FROM client;
```

---

## Related Documents

- [Logbook: GitLab OIDC Integration](../logbook/2026-02-11-gitlab-oidc-integration.md)
- [Operations: Split-Horizon DNS Setup](split-horizon-dns-setup.md)
- [ADR-046: Keycloak SSO Strategy](../adr/adr-046-keycloak-sso-strategy.md)

---

**Maintained by**: Platform Team
