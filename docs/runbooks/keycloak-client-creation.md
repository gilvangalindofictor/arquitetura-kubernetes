# Runbook: Keycloak Client Creation via Terraform

**Owner:** Platform Team
**Last updated:** 2026-02-25
**ADR:** TASK-002 (`docs/tasks/TASK-002-terraform-keycloak-provider.md`)
**Related:** `modules/keycloak-clients/`, `modules/keycloak-client-oidc/`

---

## Overview

All Keycloak clients (OIDC and SAML) are managed as Infrastructure as Code via the `mrparkers/keycloak` Terraform provider. **Never create clients manually via the Keycloak UI or SQL — this causes drift and has caused production SSO bugs** (see logbook 2026-02-12).

### Client Inventory (platform realm)

| Client       | Protocol | PKCE  | Namespace                 | Status |
|-------------|----------|-------|---------------------------|--------|
| gitlab      | OIDC     | S256  | staging-platform-gitlab   | TF managed |
| argocd      | OIDC     | none* | argocd                    | TF managed |
| grafana     | OIDC     | S256  | monitoring                | TF managed |
| harbor      | OIDC     | S256  | harbor-system             | TF managed |
| vault       | OIDC     | S256  | staging-security-vault    | TF managed |
| sonarqube   | SAML 2.0 | N/A   | sonarqube                 | TF managed |

*ArgoCD PKCE pending TASK-001 (ArgoCD upgrade to v2.12+)

---

## Prerequisites

Before any Terraform operation involving Keycloak:

```bash
# 1. Start port-forward (WSL-safe: keycloak.staging.internal does NOT resolve from WSL2)
kubectl port-forward svc/keycloak-keycloakx-http 18080:80 -n keycloak &

# 2. Set Keycloak admin password as TF variable
export TF_VAR_keycloak_admin_password=$(
  kubectl get secret keycloak-admin-credentials -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d
)

# 3. Authenticate AWS CLI (for Terraform S3 backend)
aws sso login --profile k8s-platform-staging
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
```

---

## Creating a New OIDC Client

### Step 1 — Use the reusable module

Add a new module block in `environments/staging/main.tf`:

```hcl
module "myapp_oidc" {
  source = "../../modules/keycloak-client-oidc"

  realm_id      = module.keycloak_clients_staging.realm_id
  client_id     = "myapp"
  client_name   = "My Application OIDC"
  description   = "My Application SSO via Keycloak platform realm"

  redirect_uris = ["http://myapp.staging.internal/oauth/callback"]
  web_origins   = ["http://myapp.staging.internal"]

  # Check app PKCE support before enabling:
  #   Grafana 10+, GitLab 8+, Harbor 2+, Vault 1.15+ → true
  #   ArgoCD < 2.12 → false
  enable_pkce = true
}
```

### Step 2 — Plan and apply

```bash
terraform plan -target=module.myapp_oidc
terraform apply -target=module.myapp_oidc
```

### Step 3 — Store client secret in Vault

```bash
# Get the client UUID from TF output
CLIENT_UUID=$(terraform output -raw myapp_oidc_client_uuid 2>/dev/null || \
  kubectl exec -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh \
    get clients -r platform --fields id,clientId | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print([x for x in d if x['clientId']=='myapp'][0]['id'])")

# Retrieve secret via kcadm.sh (port-forward must be active)
CLIENT_SECRET=$(kubectl exec -n keycloak keycloak-keycloakx-0 -- \
  /opt/keycloak/bin/kcadm.sh get "clients/${CLIENT_UUID}/client-secret" \
  -r platform --fields value --format csv --noquotes 2>/dev/null)

# Store in Vault KV (pattern: secret/{client_id}/oidc)
vault kv put secret/myapp/oidc \
  client_id="myapp" \
  client_secret="${CLIENT_SECRET}"
```

### Step 4 — Create ExternalSecret (if app uses ESO pattern)

```yaml
# Apply to app namespace
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-oidc-credentials
  namespace: myapp
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: myapp-oidc-secret
    creationPolicy: Owner
  data:
    - secretKey: client_id
      remoteRef:
        key: secret/data/myapp/oidc
        property: client_id
    - secretKey: client_secret
      remoteRef:
        key: secret/data/myapp/oidc
        property: client_secret
```

### Step 5 — Commit and PR

```bash
git add platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf
git commit -m "feat(keycloak): add OIDC client for myapp (TASK-002)"
# Open PR, wait for CI checks, merge
```

---

## Creating a New SAML Client

SAML clients are less common. Use `keycloak_saml_client` directly in the `keycloak-clients` module:

1. Add `clients/myapp-saml.tf` following the pattern in `clients/sonarqube.tf`
2. Add variables to `variables.tf` (`myapp_saml_enabled`, `myapp_namespace`)
3. Add outputs to `outputs.tf`
4. Import existing client if it already exists (see Import procedure below)

---

## Importing an Existing Client

When a client was created manually (legacy) and needs to be brought under Terraform management:

```bash
# 1. Get the client UUID
CLIENT_UUID=$(python3 - <<'PYEOF'
import json, urllib.request, urllib.parse

# Authenticate
token_data = urllib.parse.urlencode({
    "client_id": "admin-cli", "username": "admin",
    "password":  "ADMIN_PASSWORD", "grant_type": "password"
}).encode()
req = urllib.request.Request(
    "http://localhost:18080/auth/realms/master/protocol/openid-connect/token",
    data=token_data, method="POST"
)
token = json.loads(urllib.request.urlopen(req).read())["access_token"]

# Find client
req = urllib.request.Request(
    "http://localhost:18080/auth/admin/realms/platform/clients?max=100",
    headers={"Authorization": f"Bearer {token}", "Accept": "application/json"}
)
clients = json.loads(urllib.request.urlopen(req).read())
client = [c for c in clients if c["clientId"] == "myapp"]
print(client[0]["id"] if client else "NOT_FOUND")
PYEOF
)

# 2. Import to Terraform state
terraform import 'module.keycloak_clients_staging.keycloak_openid_client.myapp[0]' "platform/${CLIENT_UUID}"
# For SAML:
terraform import 'module.keycloak_clients_staging.keycloak_saml_client.myapp[0]' "platform/${CLIENT_UUID}"

# 3. Validate zero drift
terraform plan -target=module.keycloak_clients_staging
# Expected: "No changes. Your infrastructure matches the configuration."
```

For bulk import of all 6 platform clients, use the automated script:

```bash
# Dry run (print commands)
./platform-provisioning/aws/kubernetes/terraform/scripts/keycloak/import-clients.sh

# Execute imports automatically
./platform-provisioning/aws/kubernetes/terraform/scripts/keycloak/import-clients.sh --execute
```

---

## Drift Detection

### Manual drift check

```bash
./platform-provisioning/aws/kubernetes/terraform/scripts/keycloak/keycloak-drift-check.sh
# Exit 0 = no drift | Exit 1 = drift detected
```

### With auto-fix

```bash
./platform-provisioning/aws/kubernetes/terraform/scripts/keycloak/keycloak-drift-check.sh --fix
```

### Scheduled (recommended)

Add to GitHub Actions as a daily scheduled workflow:

```yaml
# .github/workflows/keycloak-drift-check.yml
name: Keycloak Drift Check
on:
  schedule:
    - cron: '0 12 * * 1-5'  # Mon-Fri 09:00 BRT (12:00 UTC)
  workflow_dispatch:
jobs:
  drift-check:
    runs-on: self-hosted  # requires kubectl access to cluster
    steps:
      - uses: actions/checkout@v4
      - name: Run drift check
        run: ./platform-provisioning/aws/kubernetes/terraform/scripts/keycloak/keycloak-drift-check.sh
        env:
          TF_VAR_keycloak_admin_password: ${{ secrets.KEYCLOAK_ADMIN_PASSWORD }}
          NOTIFY_SLACK: "true"
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## Troubleshooting

### Port-forward fails

```bash
# Check Keycloak pods are running
kubectl get pods -n keycloak
# Expected: keycloak-keycloakx-0  Running

# Check service
kubectl get svc -n keycloak
# Expected: keycloak-keycloakx-http  ClusterIP  ...  80/TCP
```

### Authentication fails (special characters in password)

The admin password may contain special characters that break `curl`. Always use Python urllib:

```python
import urllib.request, urllib.parse
# Never: curl -d "password=$(...)..." — fails with ! @ # $ % chars
```

### Terraform plan shows unexpected changes after import

```bash
# 1. Check what TF thinks the state is
terraform state show 'module.keycloak_clients_staging.keycloak_openid_client.gitlab[0]'

# 2. Compare with live Keycloak
kubectl exec -n keycloak keycloak-keycloakx-0 -- \
  /opt/keycloak/bin/kcadm.sh get clients/{UUID} -r platform

# 3. Update TF config to match reality, then re-import
# Common mismatches: pkce_code_challenge_method, backchannel_logout_*, web_origins
```

### Provider cannot connect to Keycloak

```bash
# Verify port-forward is active
curl -s http://localhost:18080/auth/realms/master/.well-known/openid-configuration | python3 -m json.tool | head -5
# Expected: { "issuer": "http://localhost:18080/auth/realms/master", ... }

# If "Connection refused": restart port-forward
pkill -f "port-forward.*keycloak" || true
kubectl port-forward svc/keycloak-keycloakx-http 18080:80 -n keycloak &
```

### SonarQube SAML: assertion signature validation error

If SonarQube rejects SAML assertions after TF changes:

```bash
# 1. Verify SP certificate in Vault matches what SonarQube has configured
vault kv get secret/sonarqube/saml

# 2. Export Keycloak IDP certificate
kubectl exec -n keycloak keycloak-keycloakx-0 -- \
  /opt/keycloak/bin/kcadm.sh get keys -r platform --fields certificate

# 3. Re-apply sonarqube-sp-saml ExternalSecret to refresh secret.properties
kubectl annotate externalsecret sonarqube-sp-saml -n sonarqube \
  force-sync="$(date +%s)" --overwrite
```

---

## Key Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Provider auth | `admin-cli` (password flow) | Simpler than service account for WSL2 port-forward |
| URL pattern | `http://localhost:18080` | `keycloak.staging.internal` does not resolve from WSL2 |
| `/auth` prefix | Required | keycloakx chart legacy config (Keycloak 26.5.1) |
| PKCE | S256 per client capability | Enforced where supported; tracked per client |
| Secret storage | Vault KV → ESO → K8s Secret | Consistent with platform-wide secret management |
| `prevent_destroy` | true on all clients | Safety net against accidental SSO breakage |
| `ignore_changes` | Minimal | State must track reality; avoid hiding drift |

---

**See also:** `docs/tasks/TASK-002-terraform-keycloak-provider.md`, `docs/logbook/2026-02-25-task002-keycloak-terraform-implementation.md`
