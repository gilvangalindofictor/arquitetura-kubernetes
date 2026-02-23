#!/usr/bin/env bash
# =============================================================================
# Keycloak Clients Import Script (TASK-002)
# Purpose: Discover existing Keycloak client UUIDs and generate terraform import commands
# Usage:   ./scripts/keycloak/import-clients.sh
# Prereqs: kubectl configured, aws-cli authenticated, terraform init done
#
# IMPORTANT — MEMORY.md patterns:
#   - keycloak.staging.internal does NOT resolve from WSL2 → use port-forward
#   - curl fails with Keycloak special-char passwords → use Python urllib
#   - /auth prefix required for Keycloak 26.5.1 (keycloakx chart legacy config)
#
# Steps:
#   1. Port-forward to Keycloak
#   2. Authenticate as admin
#   3. List clients in realm "platform"
#   4. Extract UUIDs for gitlab, argocd, grafana
#   5. List groups → extract grafana-admins UUID
#   6. Print terraform import commands
#   7. Execute imports in environments/staging/ (with -target to keycloak-clients module)
#
# After successful import, run:
#   terraform plan → verify 0 changes (zero drift)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_STAGING_DIR="$(cd "${SCRIPT_DIR}/../../environments/staging" && pwd)"
REALM="platform"
PORT=18080
PF_PID=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
log_info "Starting kubectl port-forward → localhost:${PORT}"
kubectl port-forward svc/keycloak-keycloakx-http "${PORT}:80" -n keycloak \
    --address 127.0.0.1 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

# Verify port-forward is alive
if ! kill -0 "${PF_PID}" 2>/dev/null; then
    log_error "Port-forward failed to start. Check: kubectl get svc -n keycloak"
    exit 1
fi
log_ok "Port-forward active (PID: ${PF_PID})"

BASE_URL="http://localhost:${PORT}/auth"

# -------------------------------------------------------------------------------
# 2. Get admin password from K8s secret (MEMORY.md pattern)
# -------------------------------------------------------------------------------
log_info "Reading Keycloak admin password from K8s secret..."
ADMIN_PASSWORD=$(kubectl get secret keycloak-admin-password -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d)
log_ok "Admin password retrieved"

# -------------------------------------------------------------------------------
# 3. Authenticate and get access token (Python urllib — curl fails with special chars)
# -------------------------------------------------------------------------------
log_info "Authenticating with Keycloak admin-cli..."
TOKEN=$(python3 - <<PYEOF
import json, urllib.request, urllib.parse

token_data = urllib.parse.urlencode({
    "client_id":   "admin-cli",
    "username":    "admin",
    "password":    "${ADMIN_PASSWORD}",
    "grant_type":  "password"
}).encode()

req = urllib.request.Request(
    "${BASE_URL}/realms/master/protocol/openid-connect/token",
    data=token_data, method="POST"
)
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read())
    print(data["access_token"])
PYEOF
)

if [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]]; then
    log_error "Authentication failed — check admin password"
    exit 1
fi
log_ok "Admin token obtained"

ADMIN_API="http://localhost:${PORT}/auth/admin/realms/${REALM}"

# -------------------------------------------------------------------------------
# 4. List clients in realm "platform" → extract UUIDs
# -------------------------------------------------------------------------------
log_info "Fetching clients from realm '${REALM}'..."

CLIENTS_JSON=$(python3 - <<PYEOF
import json, urllib.request

req = urllib.request.Request(
    "${ADMIN_API}/clients?max=100",
    headers={
        "Authorization": "Bearer ${TOKEN}",
        "Accept": "application/json"
    }
)
with urllib.request.urlopen(req) as resp:
    clients = json.loads(resp.read())
    print(json.dumps(clients))
PYEOF
)

# Extract UUIDs for each client
GITLAB_UUID=$(echo "${CLIENTS_JSON}" | python3 -c "import json,sys; data=json.load(sys.stdin); c=[x for x in data if x.get('clientId')=='gitlab']; print(c[0]['id'] if c else 'NOT_FOUND')")
ARGOCD_UUID=$(echo "${CLIENTS_JSON}" | python3 -c "import json,sys; data=json.load(sys.stdin); c=[x for x in data if x.get('clientId')=='argocd']; print(c[0]['id'] if c else 'NOT_FOUND')")
GRAFANA_UUID=$(echo "${CLIENTS_JSON}" | python3 -c "import json,sys; data=json.load(sys.stdin); c=[x for x in data if x.get('clientId')=='grafana']; print(c[0]['id'] if c else 'NOT_FOUND')")

log_ok "gitlab  UUID: ${GITLAB_UUID}"
log_ok "argocd  UUID: ${ARGOCD_UUID}"
log_ok "grafana UUID: ${GRAFANA_UUID}"

# Validate all found
for CLIENT in gitlab argocd grafana; do
    VAR="${CLIENT^^}_UUID"
    UUID="${!VAR}"
    if [[ "${UUID}" == "NOT_FOUND" ]]; then
        log_error "Client '${CLIENT}' not found in realm '${REALM}'. Check Keycloak admin console."
        exit 1
    fi
done

# -------------------------------------------------------------------------------
# 5. List groups → extract grafana-admins UUID
# -------------------------------------------------------------------------------
log_info "Fetching groups from realm '${REALM}'..."

GROUPS_JSON=$(python3 - <<PYEOF
import json, urllib.request

req = urllib.request.Request(
    "${ADMIN_API}/groups",
    headers={
        "Authorization": "Bearer ${TOKEN}",
        "Accept": "application/json"
    }
)
with urllib.request.urlopen(req) as resp:
    groups = json.loads(resp.read())
    print(json.dumps(groups))
PYEOF
)

GRAFANA_ADMINS_GROUP_UUID=$(echo "${GROUPS_JSON}" | python3 -c "
import json,sys
data=json.load(sys.stdin)
g=[x for x in data if x.get('name')=='grafana-admins']
print(g[0]['id'] if g else 'NOT_FOUND')
")

if [[ "${GRAFANA_ADMINS_GROUP_UUID}" == "NOT_FOUND" ]]; then
    log_warn "Group 'grafana-admins' not found. It will be created by TF on first apply."
    GRAFANA_ADMINS_GROUP_UUID=""
else
    log_ok "grafana-admins group UUID: ${GRAFANA_ADMINS_GROUP_UUID}"
fi

# -------------------------------------------------------------------------------
# 6. Get grafana client protocol mapper UUID for 'groups' mapper
# -------------------------------------------------------------------------------
log_info "Fetching protocol mappers for grafana client..."

MAPPERS_JSON=$(python3 - <<PYEOF
import json, urllib.request

req = urllib.request.Request(
    "${ADMIN_API}/clients/${GRAFANA_UUID}/protocol-mappers/models",
    headers={
        "Authorization": "Bearer ${TOKEN}",
        "Accept": "application/json"
    }
)
with urllib.request.urlopen(req) as resp:
    mappers = json.loads(resp.read())
    print(json.dumps(mappers))
PYEOF
)

GROUPS_MAPPER_UUID=$(echo "${MAPPERS_JSON}" | python3 -c "
import json,sys
data=json.load(sys.stdin)
m=[x for x in data if x.get('name')=='groups']
print(m[0]['id'] if m else 'NOT_FOUND')
")

if [[ "${GROUPS_MAPPER_UUID}" == "NOT_FOUND" ]]; then
    log_warn "Protocol mapper 'groups' not found on grafana client. Will be created by TF."
    GROUPS_MAPPER_UUID=""
else
    log_ok "grafana groups mapper UUID: ${GROUPS_MAPPER_UUID}"
fi

# -------------------------------------------------------------------------------
# 7. Print import commands (for review before execution)
# -------------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " TERRAFORM IMPORT COMMANDS"
echo " Working dir: ${TF_STAGING_DIR}"
echo "=================================================================="
echo ""
echo "# Step 1: Init terraform with new keycloak provider"
echo "# Run from: ${TF_STAGING_DIR}"
echo "terraform init -upgrade"
echo ""
echo "# Step 2: Import realm"
echo "terraform import 'module.keycloak_clients_staging.keycloak_realm.platform' '${REALM}'"
echo ""
echo "# Step 3: Import OIDC clients"
echo "terraform import 'module.keycloak_clients_staging.keycloak_openid_client.gitlab[0]' '${REALM}/${GITLAB_UUID}'"
echo "terraform import 'module.keycloak_clients_staging.keycloak_openid_client.argocd[0]' '${REALM}/${ARGOCD_UUID}'"
echo "terraform import 'module.keycloak_clients_staging.keycloak_openid_client.grafana[0]' '${REALM}/${GRAFANA_UUID}'"
echo ""

if [[ -n "${GRAFANA_ADMINS_GROUP_UUID}" ]]; then
    echo "# Step 4: Import grafana-admins group (already exists)"
    echo "terraform import 'module.keycloak_clients_staging.keycloak_group.grafana_admins[0]' '${REALM}/${GRAFANA_ADMINS_GROUP_UUID}'"
    echo ""
fi

if [[ -n "${GROUPS_MAPPER_UUID}" ]]; then
    echo "# Step 5: Import groups protocol mapper (already exists on grafana client)"
    echo "terraform import 'module.keycloak_clients_staging.keycloak_generic_protocol_mapper.grafana_groups[0]' '${REALM}/clients/${GRAFANA_UUID}/${GROUPS_MAPPER_UUID}'"
    echo ""
fi

echo "# Step 6: Validate zero drift"
echo "terraform plan"
echo ""
echo "=================================================================="

# -------------------------------------------------------------------------------
# 8. Optional: Execute imports automatically (set EXECUTE_IMPORTS=true)
# -------------------------------------------------------------------------------
if [[ "${EXECUTE_IMPORTS:-false}" == "true" ]]; then
    log_info "EXECUTE_IMPORTS=true — running imports automatically..."
    cd "${TF_STAGING_DIR}"

    # Export AWS credentials
    eval "$(aws configure export-credentials --profile k8s-platform-staging --format env 2>/dev/null)" || true
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    unset AWS_PROFILE

    # Export Keycloak admin password for TF variable
    export TF_VAR_keycloak_admin_password="${ADMIN_PASSWORD}"

    terraform init -upgrade -reconfigure

    terraform import \
        "module.keycloak_clients_staging.keycloak_realm.platform" \
        "${REALM}"

    terraform import \
        "module.keycloak_clients_staging.keycloak_openid_client.gitlab[0]" \
        "${REALM}/${GITLAB_UUID}"

    terraform import \
        "module.keycloak_clients_staging.keycloak_openid_client.argocd[0]" \
        "${REALM}/${ARGOCD_UUID}"

    terraform import \
        "module.keycloak_clients_staging.keycloak_openid_client.grafana[0]" \
        "${REALM}/${GRAFANA_UUID}"

    if [[ -n "${GRAFANA_ADMINS_GROUP_UUID}" ]]; then
        terraform import \
            "module.keycloak_clients_staging.keycloak_group.grafana_admins[0]" \
            "${REALM}/${GRAFANA_ADMINS_GROUP_UUID}"
    fi

    if [[ -n "${GROUPS_MAPPER_UUID}" ]]; then
        terraform import \
            "module.keycloak_clients_staging.keycloak_generic_protocol_mapper.grafana_groups[0]" \
            "${REALM}/clients/${GRAFANA_UUID}/${GROUPS_MAPPER_UUID}"
    fi

    log_ok "All imports complete. Running plan to validate zero drift..."
    terraform plan -refresh=false
fi

log_ok "Script complete."
