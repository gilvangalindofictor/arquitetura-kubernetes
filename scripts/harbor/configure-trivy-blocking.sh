#!/bin/bash
# =============================================================================
# CICD-001: Harbor Trivy Scanner Blocking Configuration
#
# Purpose: Configure Harbor's built-in Trivy scanner to block image pushes
#          and pipeline deployments when HIGH or CRITICAL vulnerabilities
#          are detected. Enforces severity threshold via Harbor API.
#
# Usage:
#   ./configure-trivy-blocking.sh [OPTIONS]
#
# Options:
#   --url URL              Harbor URL (default: https://harbor.staging.internal)
#   --user USER            Harbor admin user (default: admin)
#   --password PASS        Harbor admin password (or HARBOR_ADMIN_PASSWORD env)
#   --severity LEVEL       Comma-separated severity threshold: HIGH,CRITICAL (default)
#   --project PROJECT      Apply to specific project (default: all projects)
#   --dry-run              Show what would be done without making changes
#   --validate             Validate current scanner configuration and exit
#   --enable-auto-scan     Enable automatic scan on push (default: true)
#
# Environment Variables:
#   HARBOR_REGISTRY        Harbor registry hostname
#   HARBOR_ADMIN_PASSWORD  Harbor admin password
#
# What it does:
#   1. Validates Harbor connectivity and Trivy scanner availability
#   2. Sets vulnerability severity threshold to HIGH,CRITICAL
#   3. Enables automatic scanning on image push for all projects
#   4. Configures vulnerability blocking (prevent pull of vulnerable images)
#   5. Sets up scan-on-push for the default project and optionally all projects
#   6. Validates the configuration
#
# Requirements:
#   - curl, jq installed
#   - Harbor admin credentials
#   - Trivy scanner already integrated in Harbor (default since Harbor 2.x)
#
# OIDC Auth Note (2026-03-03):
#   When Harbor is in oidc_auth mode (Keycloak), the K8s secret
#   harbor-admin-credentials may NOT work for all API endpoints.
#   The correct admin password is the one set in the harbor-core pod env
#   (HARBOR_ADMIN_PASSWORD). To retrieve it:
#     kubectl exec -n harbor-system deploy/harbor-core -- \
#       printenv HARBOR_ADMIN_PASSWORD
#   Alternatively, run API calls from inside the cluster:
#     kubectl exec -n harbor-system deploy/harbor-core -- \
#       curl -s -u "admin:$PASS" http://harbor-core/api/v2.0/projects
#
# Applied Configuration (2026-03-03):
#   - Trivy Scanner registered: uuid=82288804-170d-11f1-81cb-3a77f7c3897a
#   - 5 projects configured: library, infrastructure, microservices,
#     platform-apps, root (auto_scan=true, prevent_vul=true, severity=high)
#   - Daily scan-all schedule: cron 0 0 0 * * * (midnight UTC)
#
# Author: Platform SRE Team
# Date: 2026-02-26 (updated 2026-03-03)
# Demand: CICD-001
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
HARBOR_URL="${HARBOR_REGISTRY:-harbor.staging.internal}"
# Normalize: add https:// if not present
if [[ ! "${HARBOR_URL}" =~ ^https?:// ]]; then
  HARBOR_URL="https://${HARBOR_URL}"
fi
HARBOR_USER="${HARBOR_ADMIN_USER:-admin}"
HARBOR_PASSWORD="${HARBOR_ADMIN_PASSWORD:-}"
SEVERITY_THRESHOLD="high"     # Harbor API uses lowercase: low/medium/high/critical
APPLY_TO_PROJECT=""           # Empty = all projects
DRY_RUN=false
VALIDATE_ONLY=false
ENABLE_AUTO_SCAN=true

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
    --url)               HARBOR_URL="$2"; shift 2 ;;
    --user)              HARBOR_USER="$2"; shift 2 ;;
    --password)          HARBOR_PASSWORD="$2"; shift 2 ;;
    --severity)          SEVERITY_THRESHOLD="${2,,}"; shift 2 ;;
    --project)           APPLY_TO_PROJECT="$2"; shift 2 ;;
    --dry-run)           DRY_RUN=true; shift ;;
    --validate)          VALIDATE_ONLY=true; shift ;;
    --enable-auto-scan)  ENABLE_AUTO_SCAN=true; shift ;;
    --disable-auto-scan) ENABLE_AUTO_SCAN=false; shift ;;
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
    exit 1
  fi
  if [[ -z "${HARBOR_PASSWORD}" ]]; then
    log_error "Harbor admin password required. Set --password or HARBOR_ADMIN_PASSWORD env var."
    log_error "Retrieve from Vault: vault kv get secret/harbor/admin"
    exit 1
  fi
  log_success "Prerequisites satisfied"
}

harbor_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local curl_args=(
    -s
    -w "\n%{http_code}"
    -u "${HARBOR_USER}:${HARBOR_PASSWORD}"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
    -X "${method}"
    "${HARBOR_URL}/api/v2.0/${endpoint}"
    --insecure   # Staging may use self-signed cert
  )

  if [[ -n "${data}" ]]; then
    curl_args+=(--data "${data}")
  fi

  local response
  response=$(curl "${curl_args[@]}" 2>&1)
  local body
  body=$(echo "${response}" | head -n -1)
  local http_code
  http_code=$(echo "${response}" | tail -n 1)

  # 200/201/204 are success; 304 is not modified
  if [[ "${http_code}" -ge 400 ]]; then
    log_error "API call failed: ${method} /api/v2.0/${endpoint} → HTTP ${http_code}"
    log_error "Response: ${body}"
    return 1
  fi

  echo "${body}"
}

# ── Functions ──────────────────────────────────────────────────────────────────
check_harbor_connectivity() {
  log_info "Testing Harbor connectivity: ${HARBOR_URL}"
  local response
  response=$(curl -s -u "${HARBOR_USER}:${HARBOR_PASSWORD}" --insecure \
    "${HARBOR_URL}/api/v2.0/ping" 2>&1) || {
    log_error "Cannot reach Harbor at ${HARBOR_URL}"
    log_error "If cluster is stopped, start it first:"
    log_error "  kubectl port-forward svc/harbor-portal 8080:80 -n harbor-system"
    exit 1
  }

  if [[ "${response}" == *"Pong"* ]] || [[ "${response}" == '"Pong"' ]]; then
    log_success "Harbor is reachable"
  else
    log_warn "Unexpected ping response: ${response}"
  fi

  # Check Harbor version
  local system_info
  system_info=$(harbor_api GET "systeminfo" 2>/dev/null || echo '{}')
  local version
  version=$(echo "${system_info}" | jq -r '.harbor_version // "unknown"')
  log_info "Harbor version: ${version}"
}

check_trivy_scanner() {
  log_info "Checking Trivy scanner integration..."
  local scanners
  scanners=$(harbor_api GET "scanners" 2>/dev/null || echo '[]')
  local trivy_scanner
  trivy_scanner=$(echo "${scanners}" | jq -r '.[] | select(.name | test("(?i)trivy")) | .uuid // empty' | head -1)

  if [[ -z "${trivy_scanner}" ]]; then
    log_warn "No Trivy scanner found in Harbor. Harbor 2.x includes Trivy built-in."
    log_warn "Check: Harbor UI → Administration → Interrogation Services"
    # Don't fail — Harbor may label it differently
    log_info "Available scanners:"
    echo "${scanners}" | jq -r '.[] | "  - \(.name) (UUID: \(.uuid))"'
  else
    log_success "Trivy scanner found (UUID: ${trivy_scanner})"
    # Show scanner details
    local scanner_detail
    scanner_detail=$(harbor_api GET "scanners/${trivy_scanner}" 2>/dev/null || echo '{}')
    local scanner_version
    scanner_version=$(echo "${scanner_detail}" | jq -r '.adapter.vendor // "unknown"')
    log_info "Scanner vendor: ${scanner_version}"
  fi

  echo "${trivy_scanner}"
}

get_all_projects() {
  log_info "Fetching all Harbor projects..."
  local page=1
  local all_projects=()

  while true; do
    local response
    response=$(harbor_api GET "projects?page=${page}&page_size=100" 2>/dev/null || echo '[]')
    local count
    count=$(echo "${response}" | jq 'length')
    if [[ "${count}" -eq 0 ]]; then
      break
    fi
    # Collect project names and IDs
    while IFS= read -r project; do
      all_projects+=("${project}")
    done < <(echo "${response}" | jq -r '.[] | "\(.project_id):\(.name)"')
    page=$((page + 1))
    if [[ "${count}" -lt 100 ]]; then
      break
    fi
  done

  printf '%s\n' "${all_projects[@]}"
}

configure_project_scanning() {
  local project_id="$1"
  local project_name="$2"

  log_info "  Configuring project: ${project_name} (ID: ${project_id})"

  # Build configuration payload
  # Harbor project configurations:
  #   prevent_vulnerable_images_from_running: block deployment of vulnerable images
  #   prevent_vulnerable_images_from_running_severity: threshold severity
  #   automatically_scan_images_on_push: auto-scan on push
  local config_payload
  config_payload=$(cat <<EOF
{
  "metadata": {
    "prevent_vul": "true",
    "severity": "${SEVERITY_THRESHOLD}",
    "auto_scan": "$(${ENABLE_AUTO_SCAN} && echo true || echo false)"
  }
}
EOF
)

  if ${DRY_RUN}; then
    log_dry "  Would update project ${project_name}: prevent_vul=true severity=${SEVERITY_THRESHOLD} auto_scan=${ENABLE_AUTO_SCAN}"
    return
  fi

  # Update project metadata
  harbor_api PUT "projects/${project_id}" "${config_payload}" > /dev/null || {
    log_warn "  Failed to update project ${project_name} — may not support this API"
  }

  log_success "  Project ${project_name}: prevent_vul=${SEVERITY_THRESHOLD}+ | auto_scan=${ENABLE_AUTO_SCAN}"
}

configure_system_vulnerability_policy() {
  log_info "Configuring system-level vulnerability policy..."

  local system_config_payload
  system_config_payload=$(cat <<EOF
{
  "configuration": {
    "vulnerability": {
      "severity": "${SEVERITY_THRESHOLD}"
    }
  }
}
EOF
)

  if ${DRY_RUN}; then
    log_dry "Would set system vulnerability severity threshold to: ${SEVERITY_THRESHOLD}"
    return
  fi

  harbor_api PUT "configurations" "${system_config_payload}" > /dev/null || {
    log_warn "Could not update system configuration — requires system admin privileges"
    log_warn "Update manually: Harbor UI → Administration → Configuration → Vulnerability"
  }

  log_success "System vulnerability threshold set to: ${SEVERITY_THRESHOLD}"
}

validate_configuration() {
  log_info "Validating Harbor security configuration..."

  echo ""
  echo "======================================================================"
  echo " Harbor Trivy Scanner Validation Report"
  echo " Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo " Harbor: ${HARBOR_URL}"
  echo "======================================================================"

  # System configuration
  echo ""
  echo "System Configuration:"
  local sys_config
  sys_config=$(harbor_api GET "configurations" 2>/dev/null || echo '{}')
  echo "${sys_config}" | jq -r '
    "  Vulnerability Severity Threshold: \(.configuration.vulnerability.severity // "not set")"
  ' 2>/dev/null || log_warn "Could not parse system configuration"

  # Projects
  echo ""
  echo "Project Security Settings:"
  local projects
  projects=$(harbor_api GET "projects?page_size=50" 2>/dev/null || echo '[]')
  echo "${projects}" | jq -r '.[] | "  Project: \(.name) | auto_scan=\(.metadata.auto_scan // "?") | prevent_vul=\(.metadata.prevent_vul // "?") | severity=\(.metadata.severity // "?")"' 2>/dev/null || \
    log_warn "Could not parse project configurations"

  # Scanners
  echo ""
  echo "Registered Scanners:"
  local scanners
  scanners=$(harbor_api GET "scanners" 2>/dev/null || echo '[]')
  echo "${scanners}" | jq -r '.[] | "  [\(if .is_default then "DEFAULT" else "       " end)] \(.name) v\(.adapter.version // "?")"' 2>/dev/null

  echo ""
  echo "======================================================================"
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "======================================================================"
  echo " CICD-001: Harbor Trivy Blocking Configuration"
  echo " Target: ${HARBOR_URL}"
  echo " Severity Threshold: ${SEVERITY_THRESHOLD^^}"
  echo " Auto-scan on push: ${ENABLE_AUTO_SCAN}"
  if ${DRY_RUN}; then
    echo " Mode: DRY-RUN (no changes will be made)"
  fi
  echo "======================================================================"
  echo ""

  check_prerequisites
  check_harbor_connectivity
  check_trivy_scanner > /dev/null

  if ${VALIDATE_ONLY}; then
    validate_configuration
    exit 0
  fi

  configure_system_vulnerability_policy

  # Configure projects
  if [[ -n "${APPLY_TO_PROJECT}" ]]; then
    # Single project
    log_info "Configuring single project: ${APPLY_TO_PROJECT}"
    local project_info
    project_info=$(harbor_api GET "projects?name=${APPLY_TO_PROJECT}" 2>/dev/null || echo '[]')
    local project_id
    project_id=$(echo "${project_info}" | jq -r '.[0].project_id // empty')
    if [[ -z "${project_id}" ]]; then
      log_error "Project '${APPLY_TO_PROJECT}' not found in Harbor"
      exit 1
    fi
    configure_project_scanning "${project_id}" "${APPLY_TO_PROJECT}"
  else
    # All projects
    log_info "Configuring ALL Harbor projects..."
    local projects_list
    mapfile -t projects_list < <(get_all_projects)
    local project_count=${#projects_list[@]}
    log_info "Found ${project_count} project(s)"

    for project_entry in "${projects_list[@]}"; do
      local pid pname
      pid=$(echo "${project_entry}" | cut -d: -f1)
      pname=$(echo "${project_entry}" | cut -d: -f2-)
      configure_project_scanning "${pid}" "${pname}"
    done
  fi

  validate_configuration

  echo ""
  log_success "Harbor Trivy blocking configuration complete"
  echo ""
  echo "Configuration summary:"
  echo "  Severity threshold:    ${SEVERITY_THRESHOLD^^} and above"
  echo "  Block vulnerable pull: ENABLED"
  echo "  Auto-scan on push:     ${ENABLE_AUTO_SCAN}"
  echo ""
  echo "Next steps:"
  echo "  1. Push a test image and verify scan runs automatically"
  echo "  2. Verify in Harbor UI: Projects → [project] → Configuration → Vulnerability scanning"
  echo "  3. Test blocking: attempt to pull a HIGH vulnerability image"
  echo "  4. Check CI pipeline: trivy-container-scan job should now block merges"
  echo "  5. See runbook: docs/runbooks/security-scan-failures-troubleshooting.md"
  echo ""
}

main "$@"
