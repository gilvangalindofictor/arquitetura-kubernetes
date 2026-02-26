#!/bin/bash
# =============================================================================
# CICD-002: SonarQube Quality Gate Configuration — Production Thresholds
#
# Purpose: Create and configure the "Production" quality gate in SonarQube with
#          standardized thresholds for code coverage, bugs, vulnerabilities,
#          code smells, and security hotspot review rate. Sets this gate as
#          the default for all projects.
#
# Usage:
#   ./configure-quality-gate.sh [OPTIONS]
#
# Options:
#   --url URL                SonarQube URL (default: http://sonarqube.staging.internal)
#   --token TOKEN            SonarQube API token (required; or set SONAR_TOKEN env)
#   --gate-name NAME         Quality Gate name (default: "Production")
#   --coverage INT           Minimum new code coverage % (default: 80)
#   --max-bugs INT           Max new bugs allowed (default: 0)
#   --max-vulns INT          Max new vulnerabilities allowed (default: 0)
#   --max-smells INT         Max new code smells allowed (default: 10)
#   --hotspot-review INT     Min security hotspots reviewed % (default: 80)
#   --no-set-default         Do NOT set this gate as default (useful for testing)
#   --dry-run                Show what would be done without making changes
#   --validate               Validate current gate configuration and exit
#
# Environment Variables:
#   SONAR_HOST_URL           SonarQube base URL
#   SONAR_TOKEN              API token with admin permissions
#
# Prerequisites:
#   - curl, jq installed
#   - SonarQube admin token (generate: Administration > Security > Users > Tokens)
#   - SonarQube 10.x (API endpoints validated for 10.3.0)
#
# What it does:
#   1. Creates (or updates) a quality gate named "Production"
#   2. Adds conditions:
#      a. Coverage on New Code  >= 80%   (ERROR — blocks pipeline)
#      b. New Bugs              = 0      (ERROR — blocks pipeline)
#      c. New Vulnerabilities   = 0      (ERROR — blocks pipeline)
#      d. New Code Smells       <= 10    (ERROR — maintainability gate)
#      e. Security Hotspots Reviewed >= 80% (ERROR — blocks pipeline)
#   3. Optionally sets this gate as the default for all projects
#   4. Validates the configuration and prints a summary report
#
# Idempotent: safe to run multiple times. Existing conditions are replaced.
#
# Relationship to CICD-001:
#   CICD-001 (configure-blocking.sh) created "Platform Security Gate" focused
#   on security. CICD-002 (this script) creates "Production" gate with broader
#   quality thresholds (coverage + smells) intended as the default for all code.
#
# Author: Platform SRE Team
# Date: 2026-02-26
# Demand: CICD-002
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
SONAR_URL="${SONAR_HOST_URL:-http://sonarqube.staging.internal}"
SONAR_TOKEN="${SONAR_TOKEN:-}"
GATE_NAME="Production"
DRY_RUN=false
VALIDATE_ONLY=false
SET_DEFAULT=true

# Threshold defaults (all parametrizable via flags)
COVERAGE_THRESHOLD=80          # New code coverage >= N% (error if below)
MAX_BUGS=0                     # New bugs <= N (error if above)
MAX_VULNERABILITIES=0          # New vulnerabilities <= N (error if above)
MAX_CODE_SMELLS=10             # New code smells <= N (error if above)
HOTSPOT_REVIEW_THRESHOLD=80    # Security hotspots reviewed >= N% (error if below)

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
    --url)                SONAR_URL="$2";                shift 2 ;;
    --token)              SONAR_TOKEN="$2";              shift 2 ;;
    --gate-name)          GATE_NAME="$2";                shift 2 ;;
    --coverage)           COVERAGE_THRESHOLD="$2";       shift 2 ;;
    --max-bugs)           MAX_BUGS="$2";                 shift 2 ;;
    --max-vulns)          MAX_VULNERABILITIES="$2";      shift 2 ;;
    --max-smells)         MAX_CODE_SMELLS="$2";          shift 2 ;;
    --hotspot-review)     HOTSPOT_REVIEW_THRESHOLD="$2"; shift 2 ;;
    --no-set-default)     SET_DEFAULT=false;             shift ;;
    --dry-run)            DRY_RUN=true;                  shift ;;
    --validate)           VALIDATE_ONLY=true;            shift ;;
    -h|--help)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      log_error "Run with --help for usage."
      exit 1
      ;;
  esac
done

# ── Prerequisites check ───────────────────────────────────────────────────────
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
    log_error "Install: apt-get install -y curl jq  OR  brew install curl jq"
    exit 1
  fi
  if [[ -z "${SONAR_TOKEN}" ]]; then
    log_error "SONAR_TOKEN is required."
    log_error "Set via: --token <token>  OR  export SONAR_TOKEN=<token>"
    log_error "Generate: SonarQube UI → Administration → Security → Users → Tokens"
    exit 1
  fi
  # Validate numeric thresholds
  for var_name in COVERAGE_THRESHOLD MAX_BUGS MAX_VULNERABILITIES MAX_CODE_SMELLS HOTSPOT_REVIEW_THRESHOLD; do
    local val="${!var_name}"
    if ! [[ "${val}" =~ ^[0-9]+$ ]]; then
      log_error "Threshold '${var_name}' must be a non-negative integer, got: ${val}"
      exit 1
    fi
  done
  log_success "Prerequisites satisfied (curl, jq, token provided)"
}

# ── SonarQube API helper ──────────────────────────────────────────────────────
# Usage: sonar_api METHOD endpoint [data]
# Returns: response body (stdout). Exits with error on non-2xx.
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
    exit 1
  fi

  local body
  body=$(echo "${response}" | head -n -1)
  local http_code
  http_code=$(echo "${response}" | tail -n 1)

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    log_error "API call failed: ${method} /api/${endpoint} → HTTP ${http_code}"
    log_error "Response body: ${body}"
    return 1
  fi

  echo "${body}"
}

# ── URL-encode a string (simple, handles spaces and special chars) ─────────────
url_encode() {
  local input="$1"
  # Use python3 if available, else basic bash replacement
  if command -v python3 &>/dev/null; then
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "${input}"
  else
    # Basic encoding: spaces → %20, common special chars
    echo "${input}" | sed 's/ /%20/g; s/&/%26/g; s/=/%3D/g; s/+/%2B/g'
  fi
}

# ── SonarQube connectivity check ──────────────────────────────────────────────
check_sonarqube_connectivity() {
  log_section "Connectivity"
  log_info "Testing SonarQube: ${SONAR_URL}"

  local response
  if ! response=$(curl -s -u "${SONAR_TOKEN}:" "${SONAR_URL}/api/system/status" 2>&1); then
    log_error "Cannot reach SonarQube at ${SONAR_URL}"
    log_error "If cluster is offline (expected), prepare for deploy later:"
    log_error "  kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube"
    exit 1
  fi

  local status
  status=$(echo "${response}" | jq -r '.status // empty' 2>/dev/null)
  if [[ "${status}" != "UP" ]]; then
    log_error "SonarQube status: '${status:-unknown}' (expected: UP)"
    log_error "Response: ${response}"
    exit 1
  fi

  local version
  version=$(echo "${response}" | jq -r '.version // "unknown"')
  log_success "SonarQube is UP — version: ${version}"
}

# ── Get or create the quality gate ───────────────────────────────────────────
get_or_create_quality_gate() {
  log_section "Quality Gate Setup"
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

    local encoded_name
    encoded_name=$(url_encode "${GATE_NAME}")

    local create_response
    create_response=$(sonar_api POST "qualitygates/create" "name=${encoded_name}")
    gate_id=$(echo "${create_response}" | jq -r '.id')
    log_success "Created quality gate '${GATE_NAME}' with ID: ${gate_id}"
  else
    log_info "Found existing quality gate '${GATE_NAME}' with ID: ${gate_id}"

    # Remove all existing conditions for idempotency (clean slate approach)
    log_info "Removing existing conditions for idempotency..."
    local gate_detail
    gate_detail=$(sonar_api GET "qualitygates/show?id=${gate_id}")
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

  echo "${gate_id}"
}

# ── Add a single condition to the quality gate ───────────────────────────────
# Usage: add_condition gate_id metric operator threshold description
# Operator: GT (greater than), LT (less than)
add_condition() {
  local gate_id="$1"
  local metric="$2"
  local op="$3"
  local threshold="$4"
  local description="$5"

  local op_display
  op_display=$([ "${op}" = "GT" ] && echo ">" || echo "<")

  log_info "  Adding condition: ${description}"
  log_info "    metric=${metric} ${op_display} ${threshold} → ERROR (blocks pipeline)"

  if ${DRY_RUN}; then
    log_dry "  Would add: metric=${metric} op=${op} error=${threshold}"
    return
  fi

  sonar_api POST "qualitygates/create_condition" \
    "gateId=${gate_id}&metric=${metric}&op=${op}&error=${threshold}" > /dev/null

  log_success "  Condition set: ${metric} ${op_display} ${threshold}"
}

# ── Configure all quality gate conditions ────────────────────────────────────
configure_quality_gate_conditions() {
  local gate_id="$1"
  log_section "Quality Gate Conditions"
  log_info "Configuring conditions for gate ID: ${gate_id}"
  log_info "Thresholds: coverage>=${COVERAGE_THRESHOLD}%, bugs<=${MAX_BUGS}, vulns<=${MAX_VULNERABILITIES}, smells<=${MAX_CODE_SMELLS}, hotspot-review>=${HOTSPOT_REVIEW_THRESHOLD}%"
  echo ""

  # ── CONDITION 1: Code Coverage ─────────────────────────────────────────────
  # Metric: new_coverage
  # Operator: LT (error if coverage is LESS THAN threshold)
  # Industry standard: 80% ensures meaningful test coverage on all new code
  add_condition "${gate_id}" \
    "new_coverage" \
    "LT" \
    "${COVERAGE_THRESHOLD}" \
    "New Code Coverage < ${COVERAGE_THRESHOLD}% (BLOCKING — must cover new code with tests)"

  # ── CONDITION 2: New Bugs ──────────────────────────────────────────────────
  # Metric: new_bugs
  # Operator: GT (error if bugs is GREATER THAN 0)
  # Zero tolerance: bugs in new code indicate logic errors that must be fixed
  add_condition "${gate_id}" \
    "new_bugs" \
    "GT" \
    "${MAX_BUGS}" \
    "New Bugs > ${MAX_BUGS} (BLOCKING — zero tolerance for new bugs)"

  # ── CONDITION 3: New Vulnerabilities ──────────────────────────────────────
  # Metric: new_vulnerabilities
  # Operator: GT (error if vulnerabilities is GREATER THAN 0)
  # Zero tolerance: security-first policy, no new CVEs may be introduced
  add_condition "${gate_id}" \
    "new_vulnerabilities" \
    "GT" \
    "${MAX_VULNERABILITIES}" \
    "New Vulnerabilities > ${MAX_VULNERABILITIES} (BLOCKING — security-first, zero new CVEs)"

  # ── CONDITION 4: Code Smells ───────────────────────────────────────────────
  # Metric: new_code_smells
  # Operator: GT (error if smells exceed threshold)
  # Maintainability gate: prevents technical debt accumulation
  add_condition "${gate_id}" \
    "new_code_smells" \
    "GT" \
    "${MAX_CODE_SMELLS}" \
    "New Code Smells > ${MAX_CODE_SMELLS} (BLOCKING — maintainability threshold)"

  # ── CONDITION 5: Security Hotspots Reviewed ────────────────────────────────
  # Metric: new_security_hotspots_reviewed
  # Operator: LT (error if review rate is LESS THAN threshold)
  # Security posture: ensures security-sensitive code is reviewed
  add_condition "${gate_id}" \
    "new_security_hotspots_reviewed" \
    "LT" \
    "${HOTSPOT_REVIEW_THRESHOLD}" \
    "Security Hotspots Reviewed < ${HOTSPOT_REVIEW_THRESHOLD}% (BLOCKING — all security hotspots must be reviewed)"

  echo ""
  log_success "All 5 quality gate conditions configured"
}

# ── Set this gate as the default ─────────────────────────────────────────────
set_as_default_gate() {
  local gate_id="$1"
  log_section "Set Default Gate"

  if ! ${SET_DEFAULT}; then
    log_warn "--no-set-default flag used. Gate will NOT be set as default."
    return
  fi

  log_info "Setting '${GATE_NAME}' as the default quality gate for all projects..."

  if ${DRY_RUN}; then
    log_dry "Would set gate ID ${gate_id} as default"
    return
  fi

  sonar_api POST "qualitygates/set_as_default" "id=${gate_id}" > /dev/null
  log_success "Gate '${GATE_NAME}' is now the default for all new projects"
}

# ── Validate and print configuration report ──────────────────────────────────
validate_configuration() {
  log_section "Validation Report"

  local gates_response
  gates_response=$(sonar_api GET "qualitygates/list")

  local default_gate_name
  default_gate_name=$(echo "${gates_response}" | jq -r '.qualitygates[] | select(.isDefault == true) | .name')

  local default_gate_id
  default_gate_id=$(echo "${gates_response}" | jq -r '.qualitygates[] | select(.isDefault == true) | .id')

  echo ""
  echo "======================================================================"
  echo " CICD-002: SonarQube Quality Gate Validation Report"
  echo " Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo " Target: ${SONAR_URL}"
  echo "======================================================================"
  echo ""
  echo "Available Quality Gates:"
  echo "${gates_response}" | jq -r '.qualitygates[] | "  \(if .isDefault then "[DEFAULT] " else "         " end)\(.name) (ID: \(.id))"'
  echo ""
  echo "Default Gate: ${default_gate_name:-NONE SET} (ID: ${default_gate_id:-n/a})"
  echo ""

  # Verify our target gate exists
  local our_gate_id
  our_gate_id=$(echo "${gates_response}" | jq -r ".qualitygates[] | select(.name == \"${GATE_NAME}\") | .id")

  if [[ -z "${our_gate_id}" ]]; then
    log_warn "Quality gate '${GATE_NAME}' NOT FOUND. Run without --validate to create it."
  else
    echo "Conditions for '${GATE_NAME}' (ID: ${our_gate_id}):"
    local gate_detail
    gate_detail=$(sonar_api GET "qualitygates/show?id=${our_gate_id}")
    echo "${gate_detail}" | jq -r '
      .conditions[]? |
      "  [" + .op + "] metric=" + .metric +
      " threshold=" + (.error // .warning // "n/a") +
      " (error: " + (.error // "n/a") + ")"
    '

    local condition_count
    condition_count=$(echo "${gate_detail}" | jq '.conditions | length')
    echo ""
    echo "Total conditions: ${condition_count}"

    if [[ "${default_gate_name}" == "${GATE_NAME}" ]]; then
      log_success "Gate '${GATE_NAME}' is correctly set as DEFAULT"
    else
      if ${SET_DEFAULT}; then
        log_warn "Gate '${GATE_NAME}' is NOT the default. Current default: '${default_gate_name:-none}'"
        log_warn "Run without --validate to fix this."
      else
        log_info "Gate is not default (--no-set-default was used — this is intentional)"
      fi
    fi
  fi

  echo ""
  echo "======================================================================"
}

# ── Check webhook configuration ──────────────────────────────────────────────
check_webhook_configured() {
  log_section "Webhook Check"
  local webhooks
  webhooks=$(sonar_api GET "webhooks/list" 2>/dev/null || echo '{"webhooks":[]}')
  local webhook_count
  webhook_count=$(echo "${webhooks}" | jq '.webhooks | length')

  if [[ "${webhook_count}" -eq 0 ]]; then
    log_warn "No webhooks configured in SonarQube."
    log_warn "For qualitygate.wait=true to work, SonarQube needs to notify CI:"
    log_warn "  Option A (recommended): Use -Dsonar.qualitygate.wait=true (polling mode)"
    log_warn "    This polls SonarQube every 5s until the gate is evaluated."
    log_warn "    Already configured in the GitLab CI template (CICD-002)."
    log_warn "  Option B (optional): Configure webhook for push notification:"
    log_warn "    SonarQube UI → Administration → Configuration → Webhooks"
    log_warn "    Add: Name=GitLab-CI  URL=<gitlab-webhook-url>"
  else
    log_success "Webhooks configured: ${webhook_count} webhook(s)"
    echo "${webhooks}" | jq -r '.webhooks[] | "  - \(.name): \(.url)"'
  fi
}

# ── Print thresholds summary ──────────────────────────────────────────────────
print_thresholds_summary() {
  echo ""
  echo "Quality Gate Thresholds:"
  echo "  Coverage on New Code:         >= ${COVERAGE_THRESHOLD}%  (blocks if below)"
  echo "  New Bugs:                     =  ${MAX_BUGS}   (blocks if above)"
  echo "  New Vulnerabilities:          =  ${MAX_VULNERABILITIES}   (blocks if above)"
  echo "  New Code Smells:              <= ${MAX_CODE_SMELLS}  (blocks if above)"
  echo "  Security Hotspots Reviewed:   >= ${HOTSPOT_REVIEW_THRESHOLD}%  (blocks if below)"
  echo ""
  if ${DRY_RUN}; then
    echo "  Mode: DRY-RUN (no changes will be made)"
    echo ""
  fi
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "======================================================================"
  echo " CICD-002: SonarQube Quality Gate Configuration"
  echo " Target: ${SONAR_URL}"
  echo " Gate:   ${GATE_NAME}"
  echo "======================================================================"

  print_thresholds_summary
  check_prerequisites
  check_sonarqube_connectivity

  if ${VALIDATE_ONLY}; then
    validate_configuration
    exit 0
  fi

  local gate_id
  gate_id=$(get_or_create_quality_gate)

  if [[ "${gate_id}" == "DRY_RUN_GATE_ID" ]]; then
    log_dry "Skipping condition setup (dry-run mode)"
    log_dry "Would configure 5 conditions for gate '${GATE_NAME}'"
  else
    configure_quality_gate_conditions "${gate_id}"
    set_as_default_gate "${gate_id}"
  fi

  check_webhook_configured
  validate_configuration

  echo ""
  log_success "CICD-002: Quality gate '${GATE_NAME}' configuration complete"
  echo ""
  echo "Next steps:"
  echo "  1. Verify: SonarQube UI → Quality Gates → '${GATE_NAME}'"
  echo "     Check: All 5 conditions appear with correct thresholds"
  echo "  2. Verify it is the default gate (check [DEFAULT] marker)"
  echo "  3. Run a pipeline to confirm blocking behavior:"
  echo "     Push a MR with code that has <${COVERAGE_THRESHOLD}% coverage"
  echo "     Pipeline should fail at sonarqube-quality-gate job"
  echo "  4. Check Prometheus metrics (after ServiceMonitor scrapes):"
  echo "     sonarqube_project_quality_gate_status{status!=\"OK\"}"
  echo "  5. Verify Grafana dashboard: CICD-002 Code Quality Trends"
  echo "     (uid: cicd002-quality-gate)"
  echo ""
  echo "Maintenance:"
  echo "  Re-run to update thresholds: SONAR_TOKEN=<tok> $0 --coverage 90"
  echo "  Validate only:               SONAR_TOKEN=<tok> $0 --validate"
  echo "  Dry-run preview:             SONAR_TOKEN=<tok> $0 --dry-run"
  echo ""
  echo "Demand: CICD-002"
  echo "ADR: docs/adr/adr-082-sonarqube-quality-gate-policy.md"
  echo ""
}

main "$@"
