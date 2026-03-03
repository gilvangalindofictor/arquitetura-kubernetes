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
#   - SonarQube 10.x (API endpoints validated for 10.3.0.82913)
#
# What it does:
#   1. Creates (or updates) a custom Quality Gate named "Platform Security Gate"
#   2. Adds blocking conditions:
#      a. New Bugs:                   > 0  (ERROR)
#      b. New Vulnerabilities:        > 0  (ERROR)
#      c. New Security Hotspots:      < 100% reviewed (ERROR)
#      d. New Code Smells:            > 20 (non-critical indicator)
#      e. Coverage on New Code:       < 80% (ERROR)
#      f. Duplicated Lines:           > 5% (non-critical indicator)
#      g. Reliability Rating:         > A  (ERROR)
#      h. Security Rating:            > A  (ERROR)
#   3. Sets this gate as default for all projects
#   4. Optionally assigns to specific projects
#
# API Compatibility:
#   SonarQube 10.x changed several API parameters:
#   - qualitygates/create_condition: uses gateName (not gateId)
#   - qualitygates/set_as_default: uses name (not id)
#   - qualitygates/show: uses name (not id)
#   This script uses the v10.x API exclusively (gateName/name parameters).
#
# Idempotent: safe to run multiple times. Conditions are replaced, not duplicated.
#
# Author: Platform SRE Team
# Date: 2026-02-26
# Updated: 2026-03-03 — SonarQube 10.x API compatibility fix (gateId -> gateName)
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
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2; }
log_dry()     { echo -e "${YELLOW}[DRY-RUN]${NC} $*"; }
log_section() { echo -e "\n${CYAN}── $* ──${NC}"; }

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

# ── URL-encode a string (handles spaces and special chars) ────────────────────
url_encode() {
  local input="$1"
  if command -v python3 &>/dev/null; then
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "${input}"
  else
    # Basic encoding: spaces -> %20, common special chars
    echo "${input}" | sed 's/ /%20/g; s/&/%26/g; s/=/%3D/g; s/+/%2B/g'
  fi
}

# ── Validation ────────────────────────────────────────────────────────────────
check_prerequisites() {
  log_section "Prerequisites"
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
    log_error "Generate token: SonarQube UI -> Administration -> Security -> Users -> Tokens"
    exit 1
  fi
  log_success "Prerequisites satisfied (curl, jq available)"
}

# ── SonarQube API helper ──────────────────────────────────────────────────────
# Usage: sonar_api METHOD endpoint [data]
# Returns: response body (stdout). Returns 1 on non-2xx.
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
  if ! response=$(curl "${curl_args[@]}" 2>&1); then
    log_error "curl command failed for ${method} /api/${endpoint}"
    return 1
  fi

  local body
  body=$(echo "${response}" | head -n -1)
  local http_code
  http_code=$(echo "${response}" | tail -n 1)

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    log_error "API call failed: ${method} /api/${endpoint} -> HTTP ${http_code}"
    log_error "Response: ${body}"
    return 1
  fi

  echo "${body}"
}

# ── Functions ──────────────────────────────────────────────────────────────────
check_sonarqube_connectivity() {
  log_section "Connectivity"
  log_info "Testing SonarQube connectivity: ${SONAR_URL}"
  local response
  if ! response=$(curl -s -u "${SONAR_TOKEN}:" "${SONAR_URL}/api/system/status" 2>&1); then
    log_error "Cannot reach SonarQube at ${SONAR_URL}"
    log_error "Ensure the cluster is running and port-forward is active:"
    log_error "  kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube"
    exit 1
  fi

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

  # Validate SonarQube 10.x compatibility
  local major_version
  major_version=$(echo "${version}" | cut -d'.' -f1)
  if [[ "${major_version}" -lt 10 ]]; then
    log_warn "SonarQube version ${version} detected. This script is optimized for 10.x+"
    log_warn "API parameters (gateName, name) are for SonarQube 10.x."
    log_warn "For SonarQube 9.x, use gateId/id parameters instead."
    log_error "Aborting: SonarQube 9.x is not supported. Please upgrade to 10.x."
    exit 1
  else
    log_success "SonarQube 10.x API confirmed (version: ${version})"
  fi
}

get_or_create_quality_gate() {
  log_section "Quality Gate Setup"
  log_info "Looking for quality gate: '${GATE_NAME}'"

  local gates_response
  gates_response=$(sonar_api GET "qualitygates/list")

  local gate_exists
  gate_exists=$(echo "${gates_response}" | jq -r ".qualitygates[] | select(.name == \"${GATE_NAME}\") | .name")

  if [[ -z "${gate_exists}" ]]; then
    log_info "Quality gate '${GATE_NAME}' not found -- creating..."
    if ${DRY_RUN}; then
      log_dry "Would create quality gate: '${GATE_NAME}'"
      return
    fi

    local encoded_name
    encoded_name=$(url_encode "${GATE_NAME}")

    local create_response
    create_response=$(sonar_api POST "qualitygates/create" "name=${encoded_name}")
    log_success "Created quality gate '${GATE_NAME}'"
  else
    log_info "Found existing quality gate '${GATE_NAME}'"

    # Remove all existing conditions for idempotency (clean slate approach)
    # SonarQube 10.x: use name= parameter for qualitygates/show
    log_info "Removing existing conditions for idempotency..."
    local gate_detail
    gate_detail=$(sonar_api GET "qualitygates/show?name=$(url_encode "${GATE_NAME}")")
    local conditions
    conditions=$(echo "${gate_detail}" | jq -r '.conditions[]?.id // empty')

    for cond_id in ${conditions}; do
      if ${DRY_RUN}; then
        log_dry "  Would delete condition ID: ${cond_id}"
      else
        sonar_api POST "qualitygates/delete_condition" "id=${cond_id}" > /dev/null || true
        log_info "  Deleted condition: ${cond_id}"
      fi
    done
  fi
}

# ── Add a single condition to the quality gate ────────────────────────────────
# SonarQube 10.x API: qualitygates/create_condition uses gateName (not gateId)
# Parameters: gate_name metric operator threshold description
add_condition() {
  local gate_name="$1"
  local metric="$2"
  local op="$3"
  local error_threshold="$4"
  local description="$5"

  local op_display
  op_display=$([ "${op}" = "GT" ] && echo ">" || echo "<")

  log_info "  Adding condition: ${description}"
  log_info "    metric=${metric} ${op_display} ${error_threshold}"

  if ${DRY_RUN}; then
    log_dry "  Would add: gateName=${gate_name} metric=${metric} op=${op} error=${error_threshold}"
    return
  fi

  # SonarQube 10.x: use gateName parameter (not gateId)
  local encoded_gate_name
  encoded_gate_name=$(url_encode "${gate_name}")

  sonar_api POST "qualitygates/create_condition" \
    "gateName=${encoded_gate_name}&metric=${metric}&op=${op}&error=${error_threshold}" > /dev/null

  log_success "  Condition set: ${metric} ${op_display} ${error_threshold}"
}

configure_quality_gate_conditions() {
  local gate_name="$1"

  log_section "Quality Gate Conditions"
  log_info "Configuring conditions for gate: '${gate_name}'"
  echo ""

  # ── BLOCKING conditions (ERROR = pipeline fails) ────────────────────────────

  # Security: Zero tolerance for new vulnerabilities
  add_condition "${gate_name}" \
    "new_vulnerabilities" "GT" "0" \
    "New Vulnerabilities > 0 (BLOCKING)"

  # Security: Zero tolerance for new bugs
  add_condition "${gate_name}" \
    "new_bugs" "GT" "0" \
    "New Bugs > 0 (BLOCKING)"

  # Security: All security hotspots must be reviewed
  add_condition "${gate_name}" \
    "new_security_hotspots_reviewed" "LT" "100" \
    "New Security Hotspots Reviewed < 100% (BLOCKING)"

  # Quality: New code must have adequate test coverage
  add_condition "${gate_name}" \
    "new_coverage" "LT" "80" \
    "New Code Coverage < 80% (BLOCKING)"

  # Quality: Reliability rating must be A on new code
  # A=1, B=2, C=3, D=4, E=5
  add_condition "${gate_name}" \
    "new_reliability_rating" "GT" "1" \
    "New Reliability Rating worse than A (BLOCKING)"

  # Security rating must be A on new code
  add_condition "${gate_name}" \
    "new_security_rating" "GT" "1" \
    "New Security Rating worse than A (BLOCKING)"

  # ── WARNING conditions (higher thresholds, non-critical indicators) ─────────
  # Note: SonarQube quality gates only have ERROR threshold (which blocks).
  # For informational warnings, add them as conditions with higher thresholds.
  # Prometheus alerting rules provide additional granularity.

  # Code smells: more relaxed, generates warning metric in Prometheus
  add_condition "${gate_name}" \
    "new_code_smells" "GT" "20" \
    "New Code Smells > 20 (non-critical indicator)"

  # Duplicated lines density
  add_condition "${gate_name}" \
    "new_duplicated_lines_density" "GT" "5" \
    "New Duplicated Lines > 5% (code quality indicator)"

  echo ""
  log_success "All 8 quality gate conditions configured"
}

# ── Set this gate as the default ──────────────────────────────────────────────
# SonarQube 10.x: use name= parameter (not id=)
set_as_default_gate() {
  local gate_name="$1"

  log_section "Set Default Gate"
  log_info "Setting '${gate_name}' as the default quality gate..."

  if ${DRY_RUN}; then
    log_dry "Would set gate '${gate_name}' as default"
    return
  fi

  # SonarQube 10.x: qualitygates/set_as_default uses name= (not id=)
  local encoded_gate_name
  encoded_gate_name=$(url_encode "${gate_name}")

  sonar_api POST "qualitygates/set_as_default" "name=${encoded_gate_name}" > /dev/null
  log_success "Gate '${gate_name}' set as default for all new projects"
}

validate_configuration() {
  log_section "Validation Report"

  local gates_response
  gates_response=$(sonar_api GET "qualitygates/list")
  local default_gate
  default_gate=$(echo "${gates_response}" | jq -r '.qualitygates[] | select(.isDefault == true) | .name')

  echo ""
  echo "======================================================================"
  echo " SonarQube Quality Gate Validation Report"
  echo " Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo " Target: ${SONAR_URL}"
  echo "======================================================================"

  echo ""
  echo "Available Quality Gates:"
  echo "${gates_response}" | jq -r '.qualitygates[] | "  \(if .isDefault then "[DEFAULT] " else "         " end)\(.name)"'

  echo ""
  echo "Default Gate: ${default_gate:-NONE SET}"

  if [[ "${default_gate}" != "${GATE_NAME}" ]]; then
    log_warn "Default gate is NOT '${GATE_NAME}' -- run without --validate to fix"
  else
    log_success "Default gate is correctly set to '${GATE_NAME}'"
  fi

  # Show conditions for the platform gate -- use name= parameter (SonarQube 10.x)
  local gate_exists
  gate_exists=$(echo "${gates_response}" | jq -r ".qualitygates[] | select(.name == \"${GATE_NAME}\") | .name")
  if [[ -n "${gate_exists}" ]]; then
    echo ""
    echo "Conditions for '${GATE_NAME}':"
    local gate_detail
    gate_detail=$(sonar_api GET "qualitygates/show?name=$(url_encode "${GATE_NAME}")")
    echo "${gate_detail}" | jq -r '
      .conditions[]? |
      "  [" + .op + "] metric=" + .metric +
      " threshold=" + (.error // "n/a") +
      " (error: " + (.error // "n/a") + ")"
    '

    local condition_count
    condition_count=$(echo "${gate_detail}" | jq '.conditions | length')
    echo ""
    echo "Total conditions: ${condition_count}"
  fi

  echo ""
  echo "======================================================================"
}

check_webhook_configured() {
  log_section "Webhook Check"
  local webhooks
  webhooks=$(sonar_api GET "webhooks/list" 2>/dev/null || echo '{"webhooks":[]}')
  local webhook_count
  webhook_count=$(echo "${webhooks}" | jq '.webhooks | length')

  if [[ "${webhook_count}" -eq 0 ]]; then
    log_warn "No webhooks configured. For Quality Gate wait to work in CI:"
    log_warn "  Option A (recommended): Use -Dsonar.qualitygate.wait=true (polling mode)"
    log_warn "    Already configured in the GitLab CI template (CICD-001)."
    log_warn "  Option B (optional): Configure webhook for push notification:"
    log_warn "    SonarQube UI -> Administration -> Configuration -> Webhooks"
    log_warn "    Add: Name=GitLab, URL=<your gitlab webhook endpoint>"
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
  echo " API:    SonarQube 10.x (gateName/name parameters)"
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

  get_or_create_quality_gate

  if ${DRY_RUN}; then
    log_dry "Skipping condition setup in dry-run mode"
    log_dry "Would configure 8 conditions for gate '${GATE_NAME}'"
  else
    configure_quality_gate_conditions "${GATE_NAME}"
    set_as_default_gate "${GATE_NAME}"
  fi

  check_webhook_configured
  validate_configuration

  echo ""
  log_success "CICD-001: SonarQube blocking Quality Gate configuration complete"
  echo ""
  echo "Next steps:"
  echo "  1. Verify in SonarQube UI: Quality Gates -> '${GATE_NAME}' -> Conditions"
  echo "     Check: All 8 conditions appear with correct thresholds"
  echo "  2. Verify it is the default gate (check [DEFAULT] marker)"
  echo "  3. Run a pipeline to confirm blocking behavior"
  echo "  4. Verify Prometheus metrics: sonarqube_quality_gate_status{status!='OK'}"
  echo "  5. See runbook for false positive handling:"
  echo "     docs/runbooks/security-scan-failures-troubleshooting.md"
  echo ""
  echo "API Compatibility:"
  echo "  This script uses SonarQube 10.x API (gateName/name parameters)."
  echo "  SonarQube 9.x (gateId/id) is NOT supported."
  echo ""
  echo "Maintenance:"
  echo "  Re-run to update:  SONAR_TOKEN=<tok> $0"
  echo "  Validate only:     SONAR_TOKEN=<tok> $0 --validate"
  echo "  Dry-run preview:   SONAR_TOKEN=<tok> $0 --dry-run"
  echo ""
  echo "Demand: CICD-001"
  echo "ADR: docs/adr/adr-081-sast-dast-pipeline-enforcement.md"
  echo ""
}

main "$@"
