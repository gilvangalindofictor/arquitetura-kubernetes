#!/usr/bin/env bash
# =============================================================================
# Keycloak Terraform Drift Detection (TASK-002)
# Purpose: Detect configuration drift between Terraform state and live Keycloak
#
# Usage:
#   ./scripts/keycloak/keycloak-drift-check.sh [--fix]
#
# Flags:
#   --fix    Run terraform apply to correct drift (requires confirmation)
#
# Exit codes:
#   0  No drift detected (infrastructure matches Terraform state)
#   1  Drift detected OR terraform plan/apply failed
#   2  Prerequisites not met (missing tools, no port-forward, etc.)
#
# Prerequisites:
#   - kubectl configured and connected to the cluster
#   - Terraform >= 1.5.0 installed
#   - AWS CLI authenticated (for Terraform backend access)
#   - Active kubectl port-forward to Keycloak OR KEYCLOAK_AUTO_PORTFORWARD=true
#
# Environment variables:
#   KEYCLOAK_AUTO_PORTFORWARD=true   Start port-forward automatically (default: true)
#   TF_VAR_keycloak_admin_password   Override admin password (auto-read from K8s if unset)
#   AWS_PROFILE                      Override AWS profile (default: k8s-platform-staging)
#   NOTIFY_TEAMS=true                Send Teams notification on drift (requires TEAMS_WEBHOOK_URL)
#   TEAMS_WEBHOOK_URL                Teams incoming webhook URL for drift notifications
#
# Recommended: Run daily via cron or GitHub Actions scheduled workflow
#   cron: 0 9 * * 1-5 /path/to/keycloak-drift-check.sh
#   gh actions: schedule: - cron: '0 12 * * 1-5'  (Mon-Fri 9h BRT = 12h UTC)
#
# ADR: TASK-002
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_STAGING_DIR="$(cd "${SCRIPT_DIR}/../../environments/staging" && pwd)"
PORT=18080
PF_PID=""
FIX_MODE="${FIX_MODE:-false}"
AUTO_PF="${KEYCLOAK_AUTO_PORTFORWARD:-true}"
PLAN_FILE="/tmp/keycloak-drift-$(date +%Y%m%d-%H%M%S).tfplan"
LOG_FILE="/tmp/keycloak-drift-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*" | tee -a "${LOG_FILE}"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "${LOG_FILE}"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "${LOG_FILE}"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"; }
log_drift() { echo -e "${RED}${BOLD}[DRIFT]${NC} $*" | tee -a "${LOG_FILE}"; }

# Parse args
for arg in "$@"; do
    case "${arg}" in
        --fix) FIX_MODE="true" ;;
        *) log_error "Unknown argument: ${arg}"; exit 2 ;;
    esac
done

cleanup() {
    if [[ -n "${PF_PID}" ]]; then
        log_info "Terminating port-forward (PID: ${PF_PID})"
        kill "${PF_PID}" 2>/dev/null || true
    fi
    rm -f "${PLAN_FILE}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

notify_teams() {
    local status="$1"
    local message="$2"

    if [[ "${NOTIFY_TEAMS:-false}" == "true" && -n "${TEAMS_WEBHOOK_URL:-}" ]]; then
        local color
        case "${status}" in
            ok)    color="00FF00" ;;
            drift) color="FF0000" ;;
            error) color="FFA500" ;;
            *)     color="cccccc" ;;
        esac

        python3 - <<PYEOF
import json, urllib.request

payload = json.dumps({
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "summary": "Keycloak Terraform Drift Check",
    "themeColor": "${color}",
    "title": "Keycloak Terraform Drift Check",
    "text": "${message}"
}).encode()

req = urllib.request.Request(
    "${TEAMS_WEBHOOK_URL}",
    data=payload,
    method="POST",
    headers={"Content-Type": "application/json"}
)
try:
    urllib.request.urlopen(req)
except Exception as e:
    pass  # Teams notification failure must not fail the drift check
PYEOF
    fi
}

# -------------------------------------------------------------------------------
# 1. Prerequisites check
# -------------------------------------------------------------------------------
log_info "=== Keycloak Terraform Drift Check — $(date -u '+%Y-%m-%d %H:%M UTC') ==="
log_info "Working dir: ${TF_STAGING_DIR}"
log_info "Log file:    ${LOG_FILE}"

if ! command -v terraform &>/dev/null; then
    log_error "terraform not found in PATH"
    exit 2
fi

TF_VERSION=$(terraform version -json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('terraform_version','unknown'))" 2>/dev/null || echo "unknown")
log_info "Terraform version: ${TF_VERSION}"

if ! command -v kubectl &>/dev/null; then
    log_error "kubectl not found in PATH"
    exit 2
fi

# -------------------------------------------------------------------------------
# 2. Start port-forward if needed (WSL-safe pattern from MEMORY.md)
# -------------------------------------------------------------------------------
if [[ "${AUTO_PF}" == "true" ]]; then
    # Check if port is already in use (user may have started PF manually)
    if python3 -c "
import socket
s = socket.socket()
s.settimeout(1)
try:
    s.connect(('localhost', ${PORT}))
    s.close()
    exit(0)
except:
    exit(1)
" 2>/dev/null; then
        log_ok "Port ${PORT} already open — skipping port-forward setup"
    else
        log_info "Starting kubectl port-forward → localhost:${PORT}"
        kubectl port-forward svc/keycloak-keycloakx-http "${PORT}:80" -n keycloak \
            --address 127.0.0.1 >/dev/null 2>&1 &
        PF_PID=$!
        sleep 3

        if ! kill -0 "${PF_PID}" 2>/dev/null; then
            log_error "Port-forward failed. Check: kubectl get svc -n keycloak"
            notify_teams "error" "Port-forward to Keycloak failed. Drift check aborted."
            exit 2
        fi
        log_ok "Port-forward active (PID: ${PF_PID})"
    fi
fi

# -------------------------------------------------------------------------------
# 3. Get admin password from K8s secret
# -------------------------------------------------------------------------------
if [[ -z "${TF_VAR_keycloak_admin_password:-}" ]]; then
    log_info "Reading Keycloak admin password from K8s secret..."
    for SECRET_NAME in "keycloak-admin-credentials" "keycloak-admin-password"; do
        ADMIN_PASSWORD=$(kubectl get secret "${SECRET_NAME}" -n keycloak \
            -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
        if [[ -n "${ADMIN_PASSWORD}" ]]; then
            log_ok "Admin password from secret '${SECRET_NAME}'"
            export TF_VAR_keycloak_admin_password="${ADMIN_PASSWORD}"
            break
        fi
    done

    if [[ -z "${TF_VAR_keycloak_admin_password:-}" ]]; then
        log_error "Could not retrieve admin password. Set TF_VAR_keycloak_admin_password manually."
        notify_teams "error" "Could not retrieve Keycloak admin password. Drift check aborted."
        exit 2
    fi
fi

# -------------------------------------------------------------------------------
# 4. Configure AWS credentials for Terraform backend
# -------------------------------------------------------------------------------
log_info "Configuring AWS credentials..."
AWS_PROFILE_NAME="${AWS_PROFILE:-k8s-platform-staging}"
eval "$(aws configure export-credentials --profile "${AWS_PROFILE_NAME}" --format env 2>/dev/null)" || true
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
unset AWS_PROFILE

# -------------------------------------------------------------------------------
# 5. Terraform init (ensure providers and backend are up-to-date)
# -------------------------------------------------------------------------------
log_info "Running terraform init..."
cd "${TF_STAGING_DIR}"
terraform init -upgrade -reconfigure -input=false >> "${LOG_FILE}" 2>&1
log_ok "Terraform init complete"

# -------------------------------------------------------------------------------
# 6. Terraform plan (drift detection)
# -------------------------------------------------------------------------------
log_info "Running terraform plan (target: module.keycloak_clients_staging)..."
log_info "Plan file: ${PLAN_FILE}"

set +e
terraform plan \
    -target=module.keycloak_clients_staging \
    -detailed-exitcode \
    -no-color \
    -out="${PLAN_FILE}" \
    >> "${LOG_FILE}" 2>&1
PLAN_EXIT_CODE=$?
set -e

# -------------------------------------------------------------------------------
# 7. Evaluate result
# -------------------------------------------------------------------------------
case "${PLAN_EXIT_CODE}" in
    0)
        log_ok "=== NO DRIFT DETECTED ==="
        log_ok "Keycloak configuration matches Terraform state."
        notify_teams "ok" "No drift detected. Keycloak clients match Terraform state."
        exit 0
        ;;

    2)
        log_drift "=== DRIFT DETECTED ==="
        log_drift "Keycloak configuration differs from Terraform state."
        log_drift "See log: ${LOG_FILE}"

        # Extract and print the diff summary
        terraform show -no-color "${PLAN_FILE}" 2>/dev/null | \
            grep -A2 -E "^  [~+\-]" | \
            head -60 | \
            tee -a "${LOG_FILE}" || true

        # Count changes by type
        ADDS=$(grep -c "^  + " "${LOG_FILE}" 2>/dev/null || echo 0)
        CHANGES=$(grep -c "^  ~ " "${LOG_FILE}" 2>/dev/null || echo 0)
        DESTROYS=$(grep -c "^  - " "${LOG_FILE}" 2>/dev/null || echo 0)

        DRIFT_MSG="DRIFT: +${ADDS} add, ~${CHANGES} change, -${DESTROYS} destroy in Keycloak clients."
        notify_teams "drift" "${DRIFT_MSG}\nLog: ${LOG_FILE}"

        if [[ "${FIX_MODE}" == "true" ]]; then
            log_warn "FIX MODE enabled — running terraform apply..."
            read -r -p "Apply changes to Keycloak? (yes/no): " CONFIRM
            if [[ "${CONFIRM}" == "yes" ]]; then
                terraform apply \
                    -target=module.keycloak_clients_staging \
                    -no-color \
                    -auto-approve \
                    "${PLAN_FILE}" \
                    | tee -a "${LOG_FILE}"
                log_ok "Drift corrected via terraform apply."
                notify_teams "ok" "Drift corrected via terraform apply. ${DRIFT_MSG}"
            else
                log_warn "Apply cancelled by user."
            fi
        fi

        exit 1
        ;;

    *)
        log_error "=== TERRAFORM PLAN FAILED (exit code: ${PLAN_EXIT_CODE}) ==="
        log_error "See log: ${LOG_FILE}"
        notify_teams "error" "Terraform plan failed (exit ${PLAN_EXIT_CODE}). Check: ${LOG_FILE}"
        exit 1
        ;;
esac
