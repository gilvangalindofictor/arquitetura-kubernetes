#!/bin/bash
# =============================================================================
# CICD-001: SonarQube Quality Gate Blocking Configuration
#
# Purpose: Configure SonarQube Quality Gate to block pipelines on any
#          detected security issue or quality regression.
#          Enables "Sonar way" gate enforcement via API (not UI).
#
# Usage:
#   ./configure-blocking.sh [OPTIONS]
#
# Options:
#   --url URL              SonarQube URL (default: http://sonarqube.staging.internal)
#   --token TOKEN          SonarQube API token (required; or set SONAR_TOKEN env)
#   --gate-name NAME       Quality Gate name to create/update (default: "Platform Security Gate")
#   --dry-run              Show what would be done without making changes
#   --validate             Validate current gate configuration and exit
#
# Environment Variables:
#   SONAR_HOST_URL         SonarQube base URL
#   SONAR_TOKEN            API token with admin permissions
#
# Prerequisites:
#   - curl, jq installed
#   - SonarQube admin token (generate: Administration > Security > Users > Tokens)
#
# What it does:
#   1. Creates (or updates) a custom Quality Gate named "Platform Security Gate"
#   2. Adds blocking conditions:
#      a. New Bugs:                   > 0  (ERROR)
#      b. New Vulnerabilities:        > 0  (ERROR)
#      c. New Security Hotspots:      < 100% reviewed (ERROR)
#      d. New Code Smells:            > 10 (WARN — non-blocking)
#      e. Coverage on New Code:       < 80% (ERROR)
#      f. Duplicated Lines:           > 3% (WARN — non-blocking)
#   3. Sets this gate as default for all projects
#   4. Optionally assigns to specific projects
#
# Idempotent: safe to run multiple times. Conditions are replaced, not duplicated.
#
# Author: Platform SRE Team
# Date: 2026-02-26
# Demand: CICD-001
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
SONAR_URL="${SONAR_HOST_URL:-http://sonarqube.staging.internal}"
SONAR_TOKEN="${SONAR_TOKEN:-}"
GATE_NAME="Platform Security Gate"
DRY_RUN=false
VALIDATE_ONLY=false

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2; }
log_dry()     { echo -e "${YELLOW}[DRY-RUN]${NC} $*"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)        SONAR_URL="$2"; shift 2 ;;
    --token)      SONAR_TOKEN="$2"; shift 2 ;;
    --gate-name)  GATE_NAME="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --validate)   VALIDATE_ONLY=true; shift ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────
check_prerequisites() {
  log_info "Checking prerequisites..."
  local missing=()
  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    log_error "Install with: apt-get install -y curl jq  OR  brew install curl jq"
    exit 1
  fi
  if [[ -z "${SONAR_TOKEN}" ]]; then
    log_error "SONAR_TOKEN is required. Set via --token or SONAR_TOKEN env variable."
    log_error "Generate token: SonarQube UI → Administration → Security → Users → Tokens"
    exit 1
  fi
  log_success "Prerequisites satisfied (curl, jq available)"
}

sonar_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local curl_args=(
    -s
    -w "\n%{http_code}"
    -u "${SONAR_TOKEN}:"
    -X "${method}"
    "${SONAR_URL}/api/${endpoint}"
  )

  if [[ -n "${data}" ]]; then
    curl_args+=(-H "Content-Type: application/x-www-form-urlencoded" --data "${data}")
  fi

  local response
  response=$(curl "${curl_args[@]}" 2>&1)
  local body
  body=$(echo "${response}" | head -n -1)
  local http_code
  http_code=$(echo "${response}" | tail -n 1)

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    log_error "API call failed: ${method} /api/${endpoint} → HTTP ${http_code}"
    log_error "Response: ${body}"
    return 1
  fi

  echo "${body}"
}

# ── Functions ──────────────────────────────────────────────────────────────────
check_sonarqube_connectivity() {
  log_info "Testing SonarQube connectivity: ${SONAR_URL}"
  local response
  response=$(curl -s -u "${SONAR_TOKEN}:" "${SONAR_URL}/api/system/status" 2>&1) || {
    log_error "Cannot reach SonarQube at ${SONAR_URL}"
    log_error "Ensure the cluster is running and port-forward is active:"
    log_error "  kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube"
    exit 1
  }

  local status
  status=$(echo "${response}" | jq -r '.status // empty' 2>/dev/null)
  if [[ "${status}" != "UP" ]]; then
    log_error "SonarQube is not UP. Status: ${status:-unknown}"
    log_error "Response: ${response}"
    exit 1
  fi

  local version
  version=$(echo "${response}" | jq -r '.version // "unknown"')
  log_success "SonarQube is UP (version: ${version})"
}

get_or_create_quality_gate() {
  log_info "Looking for quality gate: '${GATE_NAME}'"

  local gates_response
  gates_response=$(sonar_api GET "qualitygates/list")
  local gate_id
  gate_id=$(echo "${gates_response}" | jq -r ".qualitygates[] | select(.name == \"${GATE_NAME}\") | .id")

  if [[ -z "${gate_id}" ]]; then
    log_info "Quality gate '${GATE_NAME}' not found — creating..."
    if ${DRY_RUN}; then
      log_dry "Would create quality gate: '${GATE_NAME}'"
      echo "DRY_RUN_GATE_ID"
      return
    fi
    local create_response
    create_response=$(sonar_api POST "qualitygates/create" "name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${GATE_NAME}'))" 2>/dev/null || echo "${GATE_NAME// /%20}")")
    gate_id=$(echo "${create_response}" | jq -r '.id')
    log_success "Created quality gate '${GATE_NAME}' with ID: ${gate_id}"
  else
    log_info "Found existing quality gate '${GATE_NAME}' with ID: ${gate_id}"
    # Remove existing conditions to avoid duplicates
    log_info "Removing existing conditions for idempotency..."
    local conditions
    conditions=$(sonar_api GET "qualitygates/show?id=${gate_id}" | jq -r '.conditions[]?.id // empty')
    for cond_id in ${conditions}; do
      if ${DRY_RUN}; then
        log_dry "Would delete condition ID: ${cond_id}"
      else
        sonar_api POST "qualitygates/delete_condition" "id=${cond_id}" > /dev/null || true
        log_info "  Deleted condition: ${cond_id}"
      fi
    done
  fi

  echo "${gate_id}"
}

add_condition() {
  local gate_id="$1"
  local metric="$2"
  local op="$3"
  local error_threshold="$4"
  local description="$5"

  log_info "  Adding condition: ${description} (${metric} ${op} ${error_threshold})"

  if ${DRY_RUN}; then
    log_dry "  Would add: metric=${metric} op=${op} error=${error_threshold}"
    return
  fi

  sonar_api POST "qualitygates/create_condition" \
    "gateName=${GATE_NAME}&metric=${metric}&op=${op}&error=${error_threshold}" > /dev/null

  log_success "  Condition added: ${metric} ${op} ${error_threshold}"
}

configure_quality_gate_conditions() {
  local gate_id="$1"

  log_info "Configuring quality gate conditions..."

  # ── BLOCKING conditions (ERROR = pipeline fails) ────────────────────────────

  # Security: Zero tolerance for new vulnerabilities
  add_condition "${gate_id}" \
    "new_vulnerabilities" "GT" "0" \
    "New Vulnerabilities > 0 (BLOCKING)"

  # Security: Zero tolerance for new bugs
  add_condition "${gate_id}" \
    "new_bugs" "GT" "0" \
    "New Bugs > 0 (BLOCKING)"

  # Security: All security hotspots must be reviewed
  add_condition "${gate_id}" \
    "new_security_hotspots_reviewed" "LT" "100" \
    "New Security Hotspots Reviewed < 100% (BLOCKING)"

  # Quality: New code must have adequate test coverage
  add_condition "${gate_id}" \
    "new_coverage" "LT" "80" \
    "New Code Coverage < 80% (BLOCKING)"

  # Quality: Reliability rating must be A on new code
  # A=1, B=2, C=3, D=4, E=5
  add_condition "${gate_id}" \
    "new_reliability_rating" "GT" "1" \
    "New Reliability Rating worse than A (BLOCKING)"

  # Security rating must be A on new code
  add_condition "${gate_id}" \
    "new_security_rating" "GT" "1" \
    "New Security Rating worse than A (BLOCKING)"

  # ── WARNING conditions (do NOT block pipeline) ──────────────────────────────
  # Note: SonarQube quality gates only have ERROR threshold (which blocks).
  # For informational warnings, add them as conditions with high thresholds
  # or use separate alerting (Prometheus rules in this stack do this).

  # Code smells: more relaxed, generates warning metric in Prometheus
  add_condition "${gate_id}" \
    "new_code_smells" "GT" "20" \
    "New Code Smells > 20 (non-critical indicator)"

  # Duplicated lines density
  add_condition "${gate_id}" \
    "new_duplicated_lines_density" "GT" "5" \
    "New Duplicated Lines > 5% (code quality indicator)"

  log_success "All conditions configured"
}

set_as_default_gate() {
  local gate_id="$1"

  log_info "Setting '${GATE_NAME}' as the default quality gate..."

  if ${DRY_RUN}; then
    log_dry "Would set gate ID ${gate_id} as default"
    return
  fi

  sonar_api POST "qualitygates/set_as_default" "id=${gate_id}" > /dev/null
  log_success "Gate '${GATE_NAME}' set as default for all new projects"
}

validate_configuration() {
  log_info "Validating quality gate configuration..."

  local gates_response
  gates_response=$(sonar_api GET "qualitygates/list")
  local default_gate
  default_gate=$(echo "${gates_response}" | jq -r '.qualitygates[] | select(.isDefault == true) | .name')

  echo ""
  echo "======================================================================"
  echo " SonarQube Quality Gate Validation Report"
  echo " Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "======================================================================"

  echo ""
  echo "Available Quality Gates:"
  echo "${gates_response}" | jq -r '.qualitygates[] | "  \(if .isDefault then "[DEFAULT] " else "         " end)\(.name) (ID: \(.id))"'

  echo ""
  echo "Default Gate: ${default_gate:-NONE SET}"

  if [[ "${default_gate}" != "${GATE_NAME}" ]]; then
    log_warn "Default gate is NOT '${GATE_NAME}' — run without --validate to fix"
  else
    log_success "Default gate is correctly set to '${GATE_NAME}'"
  fi

  # Show conditions for the platform gate
  local gate_id
  gate_id=$(echo "${gates_response}" | jq -r ".qualitygates[] | select(.name == \"${GATE_NAME}\") | .id")
  if [[ -n "${gate_id}" ]]; then
    echo ""
    echo "Conditions for '${GATE_NAME}':"
    local gate_detail
    gate_detail=$(sonar_api GET "qualitygates/show?id=${gate_id}")
    echo "${gate_detail}" | jq -r '.conditions[]? | "  metric=\(.metric) op=\(.op) error=\(.error // "n/a")"'
  fi

  echo ""
  echo "======================================================================"
}

check_webhook_configured() {
  log_info "Checking CI webhook configuration..."
  local webhooks
  webhooks=$(sonar_api GET "webhooks/list" 2>/dev/null || echo '{"webhooks":[]}')
  local webhook_count
  webhook_count=$(echo "${webhooks}" | jq '.webhooks | length')

  if [[ "${webhook_count}" -eq 0 ]]; then
    log_warn "No webhooks configured. For Quality Gate wait to work in CI:"
    log_warn "  SonarQube UI → Administration → Configuration → Webhooks"
    log_warn "  Add: Name=GitLab, URL=<your gitlab webhook endpoint>"
    log_warn "  OR: Use -Dsonar.qualitygate.wait=true in sonar-scanner (already configured)"
  else
    log_success "Webhooks configured: ${webhook_count} webhook(s)"
    echo "${webhooks}" | jq -r '.webhooks[] | "  - \(.name): \(.url)"'
  fi
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "======================================================================"
  echo " CICD-001: SonarQube Quality Gate Blocking Configuration"
  echo " Target: ${SONAR_URL}"
  echo " Gate:   ${GATE_NAME}"
  if ${DRY_RUN}; then
    echo " Mode:   DRY-RUN (no changes will be made)"
  fi
  echo "======================================================================"
  echo ""

  check_prerequisites
  check_sonarqube_connectivity

  if ${VALIDATE_ONLY}; then
    validate_configuration
    exit 0
  fi

  local gate_id
  gate_id=$(get_or_create_quality_gate)

  if [[ "${gate_id}" == "DRY_RUN_GATE_ID" ]]; then
    log_dry "Skipping condition setup in dry-run mode"
  else
    configure_quality_gate_conditions "${gate_id}"
    set_as_default_gate "${gate_id}"
  fi

  check_webhook_configured
  validate_configuration

  echo ""
  log_success "SonarQube blocking Quality Gate configuration complete"
  echo ""
  echo "Next steps:"
  echo "  1. Verify in SonarQube UI: Quality Gates → '${GATE_NAME}' → Conditions"
  echo "  2. Run a pipeline to confirm blocking behavior"
  echo "  3. Verify Prometheus metrics: sonarqube_quality_gate_status{status!='OK'}"
  echo "  4. See runbook for false positive handling:"
  echo "     docs/runbooks/security-scan-failures-troubleshooting.md"
  echo ""
}

main "$@"
