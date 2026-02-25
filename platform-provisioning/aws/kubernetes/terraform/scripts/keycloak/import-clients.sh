#!/usr/bin/env bash
# =============================================================================
# Keycloak Clients Import Script (TASK-002)
# Purpose: Discover existing Keycloak client UUIDs and generate terraform import commands
# Usage:   ./scripts/keycloak/import-clients.sh [--execute]
#
# Clients covered (6 total):
#   OIDC: gitlab, argocd, grafana, harbor, vault
#   SAML: sonarqube
#   Groups: grafana-admins
#   Mappers: grafana groups mapper, sonarqube email/name mappers
#
# IMPORTANT — MEMORY.md patterns:
#   - keycloak.staging.internal does NOT resolve from WSL2 → use port-forward
#   - curl fails with Keycloak special-char passwords → use Python urllib
#   - /auth prefix required for Keycloak 26.5.1 (keycloakx chart legacy config)
#   - Keycloak SAML clients are in the same /clients API endpoint as OIDC clients
#
# Steps:
#   1. Port-forward to Keycloak
#   2. Authenticate as admin
#   3. List ALL clients in realm "platform" (OIDC + SAML)
#   4. Extract UUIDs for: gitlab, argocd, grafana, harbor, vault, sonarqube
#   5. List groups → extract grafana-admins UUID
#   6. List protocol mappers for grafana (groups) and sonarqube (email, name)
#   7. Print terraform import commands
#   8. Optionally execute imports (--execute flag or EXECUTE_IMPORTS=true)
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

# Parse args
EXECUTE_IMPORTS="${EXECUTE_IMPORTS:-false}"
if [[ "${1:-}" == "--execute" ]]; then
    EXECUTE_IMPORTS="true"
fi

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
log_info "Starting kubectl port-forward → localhost:${PORT}"
kubectl port-forward svc/keycloak-keycloakx-http "${PORT}:80" -n keycloak \
    --address 127.0.0.1 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

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

ADMIN_PASSWORD=""
for SECRET_NAME in "keycloak-admin-credentials" "keycloak-admin-password"; do
    ADMIN_PASSWORD=$(kubectl get secret "${SECRET_NAME}" -n keycloak \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [[ -n "${ADMIN_PASSWORD}" ]]; then
        log_ok "Admin password from secret '${SECRET_NAME}'"
        break
    fi
done

if [[ -z "${ADMIN_PASSWORD}" ]]; then
    log_error "Could not retrieve admin password from keycloak-admin-credentials or keycloak-admin-password"
    exit 1
fi

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
# 4. List ALL clients in realm "platform" (OIDC + SAML share same endpoint)
# -------------------------------------------------------------------------------
log_info "Fetching all clients from realm '${REALM}'..."

CLIENTS_JSON=$(python3 - <<PYEOF
import json, urllib.request

req = urllib.request.Request(
    "${ADMIN_API}/clients?max=200",
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

# Helper function to extract UUID by clientId
extract_uuid() {
    local client_id="$1"
    echo "${CLIENTS_JSON}" | python3 -c "
import json,sys
data=json.load(sys.stdin)
c=[x for x in data if x.get('clientId')=='${client_id}']
print(c[0]['id'] if c else 'NOT_FOUND')
"
}

# Extract UUIDs for all 6 clients
GITLAB_UUID=$(extract_uuid "gitlab")
ARGOCD_UUID=$(extract_uuid "argocd")
GRAFANA_UUID=$(extract_uuid "grafana")
HARBOR_UUID=$(extract_uuid "harbor")
VAULT_UUID=$(extract_uuid "vault")
SONARQUBE_UUID=$(extract_uuid "sonarqube")

log_ok "gitlab     UUID: ${GITLAB_UUID}"
log_ok "argocd     UUID: ${ARGOCD_UUID}"
log_ok "grafana    UUID: ${GRAFANA_UUID}"
log_ok "harbor     UUID: ${HARBOR_UUID}"
log_ok "vault      UUID: ${VAULT_UUID}"
log_ok "sonarqube  UUID: ${SONARQUBE_UUID}"

# Validate all required clients found
MISSING=()
for CLIENT in gitlab argocd grafana harbor vault sonarqube; do
    VAR="${CLIENT^^}_UUID"
    UUID="${!VAR}"
    if [[ "${UUID}" == "NOT_FOUND" ]]; then
        MISSING+=("${CLIENT}")
        log_warn "Client '${CLIENT}' not found in realm '${REALM}' — will be created by TF on first apply"
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
    log_warn "Group 'grafana-admins' not found. Will be created by TF on first apply."
    GRAFANA_ADMINS_GROUP_UUID=""
else
    log_ok "grafana-admins group UUID: ${GRAFANA_ADMINS_GROUP_UUID}"
fi

# -------------------------------------------------------------------------------
# 6. Get protocol mapper UUIDs
# -------------------------------------------------------------------------------

get_mapper_uuid() {
    local client_uuid="$1"
    local mapper_name="$2"
    python3 - <<PYEOF
import json, urllib.request, sys

req = urllib.request.Request(
    "${ADMIN_API}/clients/${client_uuid}/protocol-mappers/models",
    headers={
        "Authorization": "Bearer ${TOKEN}",
        "Accept": "application/json"
    }
)
with urllib.request.urlopen(req) as resp:
    mappers = json.loads(resp.read())
    m=[x for x in mappers if x.get('name')=='${mapper_name}']
    print(m[0]['id'] if m else 'NOT_FOUND')
PYEOF
}

# Grafana: groups mapper
GROUPS_MAPPER_UUID="NOT_FOUND"
if [[ "${GRAFANA_UUID}" != "NOT_FOUND" ]]; then
    log_info "Fetching protocol mappers for grafana client..."
    GROUPS_MAPPER_UUID=$(get_mapper_uuid "${GRAFANA_UUID}" "groups")
    if [[ "${GROUPS_MAPPER_UUID}" == "NOT_FOUND" ]]; then
        log_warn "Protocol mapper 'groups' not found on grafana client. Will be created by TF."
        GROUPS_MAPPER_UUID=""
    else
        log_ok "grafana groups mapper UUID: ${GROUPS_MAPPER_UUID}"
    fi
fi

# SonarQube: email and name mappers (SAML attribute mappers)
SONARQUBE_EMAIL_MAPPER_UUID="NOT_FOUND"
SONARQUBE_NAME_MAPPER_UUID="NOT_FOUND"
if [[ "${SONARQUBE_UUID}" != "NOT_FOUND" ]]; then
    log_info "Fetching protocol mappers for sonarqube client (SAML)..."
    SONARQUBE_EMAIL_MAPPER_UUID=$(get_mapper_uuid "${SONARQUBE_UUID}" "email")
    SONARQUBE_NAME_MAPPER_UUID=$(get_mapper_uuid "${SONARQUBE_UUID}" "name")

    if [[ "${SONARQUBE_EMAIL_MAPPER_UUID}" == "NOT_FOUND" ]]; then
        log_warn "SAML mapper 'email' not found on sonarqube client. Will be created by TF."
        SONARQUBE_EMAIL_MAPPER_UUID=""
    else
        log_ok "sonarqube email mapper UUID: ${SONARQUBE_EMAIL_MAPPER_UUID}"
    fi

    if [[ "${SONARQUBE_NAME_MAPPER_UUID}" == "NOT_FOUND" ]]; then
        log_warn "SAML mapper 'name' not found on sonarqube client. Will be created by TF."
        SONARQUBE_NAME_MAPPER_UUID=""
    else
        log_ok "sonarqube name mapper UUID: ${SONARQUBE_NAME_MAPPER_UUID}"
    fi
fi

# -------------------------------------------------------------------------------
# 7. Print import commands (for review before execution)
# -------------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " TERRAFORM IMPORT COMMANDS"
echo " Working dir: ${TF_STAGING_DIR}"
echo " Module path: module.keycloak_clients_staging"
echo "=================================================================="
echo ""
echo "# Step 1: Init terraform (downloads mrparkers/keycloak provider)"
echo "# Run from: ${TF_STAGING_DIR}"
echo "terraform init -upgrade"
echo ""
echo "# Step 2: Import realm"
echo "terraform import 'module.keycloak_clients_staging.keycloak_realm.platform' '${REALM}'"
echo ""
echo "# Step 3: Import OIDC clients"
[[ "${GITLAB_UUID}" != "NOT_FOUND" ]]   && echo "terraform import 'module.keycloak_clients_staging.keycloak_openid_client.gitlab[0]' '${REALM}/${GITLAB_UUID}'"
[[ "${ARGOCD_UUID}" != "NOT_FOUND" ]]   && echo "terraform import 'module.keycloak_clients_staging.keycloak_openid_client.argocd[0]' '${REALM}/${ARGOCD_UUID}'"
[[ "${GRAFANA_UUID}" != "NOT_FOUND" ]]  && echo "terraform import 'module.keycloak_clients_staging.keycloak_openid_client.grafana[0]' '${REALM}/${GRAFANA_UUID}'"
[[ "${HARBOR_UUID}" != "NOT_FOUND" ]]   && echo "terraform import 'module.keycloak_clients_staging.keycloak_openid_client.harbor[0]' '${REALM}/${HARBOR_UUID}'"
[[ "${VAULT_UUID}" != "NOT_FOUND" ]]    && echo "terraform import 'module.keycloak_clients_staging.keycloak_openid_client.vault[0]' '${REALM}/${VAULT_UUID}'"
echo ""
echo "# Step 4: Import SAML client (SonarQube)"
[[ "${SONARQUBE_UUID}" != "NOT_FOUND" ]] && echo "terraform import 'module.keycloak_clients_staging.keycloak_saml_client.sonarqube[0]' '${REALM}/${SONARQUBE_UUID}'"
echo ""

if [[ -n "${GRAFANA_ADMINS_GROUP_UUID}" ]]; then
    echo "# Step 5: Import grafana-admins group"
    echo "terraform import 'module.keycloak_clients_staging.keycloak_group.grafana_admins[0]' '${REALM}/${GRAFANA_ADMINS_GROUP_UUID}'"
    echo ""
fi

if [[ -n "${GROUPS_MAPPER_UUID:-}" ]]; then
    echo "# Step 6: Import grafana groups protocol mapper"
    echo "terraform import 'module.keycloak_clients_staging.keycloak_generic_protocol_mapper.grafana_groups[0]' '${REALM}/clients/${GRAFANA_UUID}/${GROUPS_MAPPER_UUID}'"
    echo ""
fi

if [[ -n "${SONARQUBE_EMAIL_MAPPER_UUID:-}" ]]; then
    echo "# Step 7: Import sonarqube SAML email mapper"
    echo "terraform import 'module.keycloak_clients_staging.keycloak_saml_user_attribute_protocol_mapper.sonarqube_email[0]' '${REALM}/clients/${SONARQUBE_UUID}/${SONARQUBE_EMAIL_MAPPER_UUID}'"
fi

if [[ -n "${SONARQUBE_NAME_MAPPER_UUID:-}" ]]; then
    echo "terraform import 'module.keycloak_clients_staging.keycloak_saml_user_property_protocol_mapper.sonarqube_name[0]' '${REALM}/clients/${SONARQUBE_UUID}/${SONARQUBE_NAME_MAPPER_UUID}'"
    echo ""
fi

echo "# Step 8: Validate zero drift"
echo "terraform plan -target=module.keycloak_clients_staging"
echo ""
echo "=================================================================="

# -------------------------------------------------------------------------------
# 8. Optional: Execute imports automatically (--execute flag or EXECUTE_IMPORTS=true)
# -------------------------------------------------------------------------------
if [[ "${EXECUTE_IMPORTS}" == "true" ]]; then
    log_info "EXECUTE_IMPORTS=true — running imports automatically..."
    cd "${TF_STAGING_DIR}"

    # Export AWS credentials
    eval "$(aws configure export-credentials --profile k8s-platform-staging --format env 2>/dev/null)" || true
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    unset AWS_PROFILE

    # Export Keycloak admin password for TF variable
    export TF_VAR_keycloak_admin_password="${ADMIN_PASSWORD}"

    terraform init -upgrade -reconfigure

    # Import realm
    terraform import "module.keycloak_clients_staging.keycloak_realm.platform" "${REALM}"

    # Import OIDC clients (skip NOT_FOUND)
    [[ "${GITLAB_UUID}" != "NOT_FOUND" ]]   && terraform import "module.keycloak_clients_staging.keycloak_openid_client.gitlab[0]" "${REALM}/${GITLAB_UUID}"
    [[ "${ARGOCD_UUID}" != "NOT_FOUND" ]]   && terraform import "module.keycloak_clients_staging.keycloak_openid_client.argocd[0]" "${REALM}/${ARGOCD_UUID}"
    [[ "${GRAFANA_UUID}" != "NOT_FOUND" ]]  && terraform import "module.keycloak_clients_staging.keycloak_openid_client.grafana[0]" "${REALM}/${GRAFANA_UUID}"
    [[ "${HARBOR_UUID}" != "NOT_FOUND" ]]   && terraform import "module.keycloak_clients_staging.keycloak_openid_client.harbor[0]" "${REALM}/${HARBOR_UUID}"
    [[ "${VAULT_UUID}" != "NOT_FOUND" ]]    && terraform import "module.keycloak_clients_staging.keycloak_openid_client.vault[0]" "${REALM}/${VAULT_UUID}"

    # Import SAML client
    [[ "${SONARQUBE_UUID}" != "NOT_FOUND" ]] && terraform import "module.keycloak_clients_staging.keycloak_saml_client.sonarqube[0]" "${REALM}/${SONARQUBE_UUID}"

    # Import group
    if [[ -n "${GRAFANA_ADMINS_GROUP_UUID}" ]]; then
        terraform import "module.keycloak_clients_staging.keycloak_group.grafana_admins[0]" "${REALM}/${GRAFANA_ADMINS_GROUP_UUID}"
    fi

    # Import mappers
    if [[ -n "${GROUPS_MAPPER_UUID:-}" ]]; then
        terraform import "module.keycloak_clients_staging.keycloak_generic_protocol_mapper.grafana_groups[0]" "${REALM}/clients/${GRAFANA_UUID}/${GROUPS_MAPPER_UUID}"
    fi
    if [[ -n "${SONARQUBE_EMAIL_MAPPER_UUID:-}" ]]; then
        terraform import "module.keycloak_clients_staging.keycloak_saml_user_attribute_protocol_mapper.sonarqube_email[0]" "${REALM}/clients/${SONARQUBE_UUID}/${SONARQUBE_EMAIL_MAPPER_UUID}"
    fi
    if [[ -n "${SONARQUBE_NAME_MAPPER_UUID:-}" ]]; then
        terraform import "module.keycloak_clients_staging.keycloak_saml_user_property_protocol_mapper.sonarqube_name[0]" "${REALM}/clients/${SONARQUBE_UUID}/${SONARQUBE_NAME_MAPPER_UUID}"
    fi

    log_ok "All imports complete. Running plan to validate zero drift..."
    terraform plan -target=module.keycloak_clients_staging -refresh=false
fi

log_ok "Script complete."
