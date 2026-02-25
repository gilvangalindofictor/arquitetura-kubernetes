#!/usr/bin/env bash
# =============================================================================
# Keycloak Terraform Service Account Bootstrap (TASK-002)
# Purpose: Create "terraform" client in Keycloak master realm for IaC management
#
# This is a ONE-TIME setup script. Run once per environment.
# After execution, the client_secret is stored in Vault KV and
# retrieved by Terraform via ExternalSecret or TF_VAR_keycloak_admin_password.
#
# What this script does:
#   1. Port-forward to Keycloak (WSL-safe)
#   2. Authenticate as admin (Python urllib — avoids curl special-char issues)
#   3. Check if "terraform" client already exists (idempotent)
#   4. Create client with serviceAccountsEnabled=true
#   5. Assign manage-realm + manage-clients roles to service account
#   6. Retrieve and print client_secret
#   7. Store secret in Vault KV: secret/keycloak/terraform
#
# Prerequisites:
#   - kubectl configured and connected to the cluster
#   - Vault CLI authenticated (vault login or VAULT_TOKEN set)
#   - AWS CLI authenticated (for EKS kubeconfig)
#
# Usage:
#   ./scripts/keycloak/bootstrap-terraform-client.sh
#
# MEMORY.md patterns used:
#   - WSL2: keycloak.staging.internal does NOT resolve → use port-forward
#   - Python urllib: curl fails with Keycloak special-char passwords
#   - Keycloak 26.5.1 keycloakx: /auth prefix required in all URLs
#   - Vault KV v2: path prefix secret/data/... for writes, secret/... for reads
#
# ADR: TASK-002
# =============================================================================

set -euo pipefail

# -------------------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------------------
PORT=18080
KEYCLOAK_NAMESPACE="keycloak"
KEYCLOAK_SVC="keycloak-keycloakx-http"
CLIENT_ID="terraform"
VAULT_PATH="secret/keycloak/terraform"
PF_PID=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

cleanup() {
    if [[ -n "${PF_PID}" ]]; then
        log_info "Terminating port-forward (PID: ${PF_PID})"
        kill "${PF_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# -------------------------------------------------------------------------------
# 1. Start port-forward (WSL-safe pattern from MEMORY.md)
# -------------------------------------------------------------------------------
log_info "Starting kubectl port-forward svc/${KEYCLOAK_SVC} ${PORT}:80 -n ${KEYCLOAK_NAMESPACE}"
kubectl port-forward "svc/${KEYCLOAK_SVC}" "${PORT}:80" -n "${KEYCLOAK_NAMESPACE}" \
    --address 127.0.0.1 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

if ! kill -0 "${PF_PID}" 2>/dev/null; then
    log_error "Port-forward failed. Check: kubectl get svc -n ${KEYCLOAK_NAMESPACE}"
    exit 1
fi
log_ok "Port-forward active (PID: ${PF_PID})"

BASE_URL="http://localhost:${PORT}/auth"

# -------------------------------------------------------------------------------
# 2. Get admin password from K8s secret
# -------------------------------------------------------------------------------
log_info "Reading Keycloak admin password from K8s secret..."

# Try the ESO-managed secret first (V-006), fall back to legacy name
ADMIN_PASSWORD=""
for SECRET_NAME in "keycloak-admin-credentials" "keycloak-admin-password"; do
    ADMIN_PASSWORD=$(kubectl get secret "${SECRET_NAME}" -n "${KEYCLOAK_NAMESPACE}" \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [[ -n "${ADMIN_PASSWORD}" ]]; then
        log_ok "Admin password retrieved from secret '${SECRET_NAME}'"
        break
    fi
done

if [[ -z "${ADMIN_PASSWORD}" ]]; then
    log_error "Could not retrieve admin password. Checked: keycloak-admin-credentials, keycloak-admin-password"
    exit 1
fi

# -------------------------------------------------------------------------------
# 3. Authenticate and get access token (Python urllib — MEMORY.md pattern)
# -------------------------------------------------------------------------------
log_info "Authenticating with Keycloak admin-cli (master realm)..."

TOKEN=$(python3 - <<PYEOF
import json, urllib.request, urllib.parse, sys

token_data = urllib.parse.urlencode({
    "client_id":   "admin-cli",
    "username":    "admin",
    "password":    "${ADMIN_PASSWORD}",
    "grant_type":  "password"
}).encode()

try:
    req = urllib.request.Request(
        "${BASE_URL}/realms/master/protocol/openid-connect/token",
        data=token_data, method="POST"
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())
        print(data["access_token"])
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)

if [[ -z "${TOKEN}" ]]; then
    log_error "Authentication failed — empty token"
    exit 1
fi
log_ok "Admin token obtained"

MASTER_API="http://localhost:${PORT}/auth/admin/realms/master"

# -------------------------------------------------------------------------------
# 4. Check if "terraform" client already exists (idempotent)
# -------------------------------------------------------------------------------
log_info "Checking if client '${CLIENT_ID}' already exists in master realm..."

EXISTING_UUID=$(python3 - <<PYEOF
import json, urllib.request, sys

req = urllib.request.Request(
    "${MASTER_API}/clients?clientId=${CLIENT_ID}&max=1",
    headers={
        "Authorization": "Bearer ${TOKEN}",
        "Accept": "application/json"
    }
)
with urllib.request.urlopen(req) as resp:
    clients = json.loads(resp.read())
    if clients:
        print(clients[0]["id"])
    else:
        print("")
PYEOF
)

if [[ -n "${EXISTING_UUID}" ]]; then
    log_warn "Client '${CLIENT_ID}' already exists (UUID: ${EXISTING_UUID}). Skipping creation."
    CLIENT_UUID="${EXISTING_UUID}"
else
    # -------------------------------------------------------------------------------
    # 5. Create "terraform" client in master realm
    # -------------------------------------------------------------------------------
    log_info "Creating client '${CLIENT_ID}' in master realm..."

    CLIENT_UUID=$(python3 - <<PYEOF
import json, urllib.request, sys

payload = json.dumps({
    "clientId":               "${CLIENT_ID}",
    "name":                   "Terraform IaC Service Account",
    "description":            "Service account for Terraform mrparkers/keycloak provider. Manages realm, clients and groups via IaC. Created by bootstrap-terraform-client.sh (TASK-002).",
    "enabled":                True,
    "serviceAccountsEnabled": True,
    "standardFlowEnabled":    False,
    "directAccessGrantsEnabled": False,
    "publicClient":           False,
    "redirectUris":           ["http://localhost"],
    "attributes": {
        "access.token.lifespan": "3600"
    }
}).encode()

req = urllib.request.Request(
    "${MASTER_API}/clients",
    data=payload,
    method="POST",
    headers={
        "Authorization":  "Bearer ${TOKEN}",
        "Content-Type":   "application/json"
    }
)
try:
    with urllib.request.urlopen(req) as resp:
        location = resp.headers.get("Location", "")
        client_uuid = location.split("/")[-1]
        print(client_uuid)
except urllib.error.HTTPError as e:
    body = e.read().decode()
    print(f"ERROR {e.code}: {body}", file=sys.stderr)
    sys.exit(1)
PYEOF
)

    if [[ -z "${CLIENT_UUID}" ]]; then
        log_error "Failed to create client '${CLIENT_ID}'"
        exit 1
    fi
    log_ok "Client '${CLIENT_ID}' created (UUID: ${CLIENT_UUID})"
fi

# -------------------------------------------------------------------------------
# 6. Get service account user for the terraform client
# -------------------------------------------------------------------------------
log_info "Fetching service account user for client '${CLIENT_ID}'..."

SA_USER_ID=$(python3 - <<PYEOF
import json, urllib.request, sys

req = urllib.request.Request(
    "${MASTER_API}/clients/${CLIENT_UUID}/service-account-user",
    headers={
        "Authorization": "Bearer ${TOKEN}",
        "Accept": "application/json"
    }
)
with urllib.request.urlopen(req) as resp:
    user = json.loads(resp.read())
    print(user["id"])
PYEOF
)

log_ok "Service account user ID: ${SA_USER_ID}"

# -------------------------------------------------------------------------------
# 7. Assign manage-realm + manage-clients roles (master realm client roles)
# -------------------------------------------------------------------------------
log_info "Assigning manage-realm and manage-clients roles to service account..."

# Get master-realm client UUID (the built-in "master-realm" client in master realm)
MASTER_REALM_CLIENT_UUID=$(python3 - <<PYEOF
import json, urllib.request, sys

req = urllib.request.Request(
    "${MASTER_API}/clients?clientId=master-realm&max=1",
    headers={
        "Authorization": "Bearer ${TOKEN}",
        "Accept": "application/json"
    }
)
with urllib.request.urlopen(req) as resp:
    clients = json.loads(resp.read())
    if clients:
        print(clients[0]["id"])
    else:
        print("", file=sys.stderr)
        sys.exit(1)
PYEOF
)

log_ok "master-realm client UUID: ${MASTER_REALM_CLIENT_UUID}"

# Get role IDs for manage-realm and manage-clients
ROLES_JSON=$(python3 - <<PYEOF
import json, urllib.request, sys

req = urllib.request.Request(
    "${MASTER_API}/clients/${MASTER_REALM_CLIENT_UUID}/roles",
    headers={
        "Authorization": "Bearer ${TOKEN}",
        "Accept": "application/json"
    }
)
with urllib.request.urlopen(req) as resp:
    roles = json.loads(resp.read())
    target = [r for r in roles if r["name"] in ("manage-realm", "manage-clients")]
    print(json.dumps(target))
PYEOF
)

log_ok "Roles to assign: $(echo "${ROLES_JSON}" | python3 -c "import json,sys; print([r['name'] for r in json.load(sys.stdin)])")"

# Assign roles to service account
python3 - <<PYEOF
import json, urllib.request, sys

roles = ${ROLES_JSON}

payload = json.dumps(roles).encode()
req = urllib.request.Request(
    "${MASTER_API}/users/${SA_USER_ID}/role-mappings/clients/${MASTER_REALM_CLIENT_UUID}",
    data=payload,
    method="POST",
    headers={
        "Authorization": "Bearer ${TOKEN}",
        "Content-Type":  "application/json"
    }
)
try:
    with urllib.request.urlopen(req) as resp:
        print("Roles assigned successfully")
except urllib.error.HTTPError as e:
    body = e.read().decode()
    # 409 = already assigned (idempotent)
    if e.code == 409:
        print("Roles already assigned (idempotent)")
    else:
        print(f"ERROR {e.code}: {body}", file=sys.stderr)
        sys.exit(1)
PYEOF

log_ok "Roles assigned: manage-realm, manage-clients"

# -------------------------------------------------------------------------------
# 8. Retrieve client secret
# -------------------------------------------------------------------------------
log_info "Retrieving client secret for '${CLIENT_ID}'..."

CLIENT_SECRET=$(python3 - <<PYEOF
import json, urllib.request, sys

req = urllib.request.Request(
    "${MASTER_API}/clients/${CLIENT_UUID}/client-secret",
    headers={
        "Authorization": "Bearer ${TOKEN}",
        "Accept": "application/json"
    }
)
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read())
    print(data["value"])
PYEOF
)

if [[ -z "${CLIENT_SECRET}" ]]; then
    log_error "Failed to retrieve client secret"
    exit 1
fi
log_ok "Client secret retrieved (masked: ${CLIENT_SECRET:0:4}****)"

# -------------------------------------------------------------------------------
# 9. Store secret in Vault KV (secret/keycloak/terraform)
# -------------------------------------------------------------------------------
log_info "Storing client_secret in Vault KV: ${VAULT_PATH}"

if command -v vault &>/dev/null && [[ -n "${VAULT_TOKEN:-}" || -f "${HOME}/.vault-token" ]]; then
    # Determine Vault address
    VAULT_ADDR="${VAULT_ADDR:-http://vault.staging.internal}"

    vault kv put "${VAULT_PATH}" \
        client_id="${CLIENT_ID}" \
        client_secret="${CLIENT_SECRET}" \
        realm="master" \
        url="http://localhost:18080"

    log_ok "Secret stored in Vault KV: ${VAULT_PATH}"
    log_info "ESO ExternalSecret will sync to K8s secret 'keycloak-terraform-credentials' in keycloak namespace."
else
    log_warn "Vault CLI not available or not authenticated. Store the secret manually:"
    echo ""
    echo "  vault kv put ${VAULT_PATH} \\"
    echo "    client_id='${CLIENT_ID}' \\"
    echo "    client_secret='<see below>' \\"
    echo "    realm='master' \\"
    echo "    url='http://localhost:18080'"
    echo ""
    log_warn "CLIENT SECRET (store in Vault, do NOT commit to git):"
    echo "  ${CLIENT_SECRET}"
fi

# -------------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " BOOTSTRAP COMPLETE"
echo "=================================================================="
echo ""
echo " Client ID:     ${CLIENT_ID}"
echo " Client UUID:   ${CLIENT_UUID}"
echo " Realm:         master"
echo " Roles:         manage-realm, manage-clients"
echo " Vault KV:      ${VAULT_PATH}"
echo ""
echo " Next steps:"
echo "   1. Verify Vault KV: vault kv get ${VAULT_PATH}"
echo "   2. Run import script: ./scripts/keycloak/import-clients.sh"
echo "   3. Validate zero drift: terraform plan (from environments/staging/)"
echo "=================================================================="
