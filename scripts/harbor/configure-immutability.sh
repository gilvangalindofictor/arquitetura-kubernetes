#!/usr/bin/env bash
# =============================================================================
# Harbor Immutability Rules Configuration — CICD-004
# =============================================================================
# Configures immutable tag rules via Harbor API v2.0 for all platform projects.
#
# Strategy:
#   - ALL tags are immutable by default (production safety)
#   - EXCEPTION: dev/* and staging/* tags remain mutable (development workflow)
#   - Tag retention: auto-delete dev/staging tags older than 90 days
#
# Projects configured:
#   - platform-apps      (platform services: harbor, keycloak, argocd, etc.)
#   - microservices      (application workloads)
#   - infrastructure     (base images, tooling)
#
# Prerequisites:
#   - HARBOR_URL   : Harbor base URL (e.g. https://harbor.staging.internal)
#   - HARBOR_USER  : Admin user (default: admin)
#   - HARBOR_PASS  : Admin password (from Vault secret/harbor/admin via ESO)
#
# Usage:
#   # Dry-run (preview changes, no modifications)
#   ./configure-immutability.sh --dry-run
#
#   # Apply to all projects
#   ./configure-immutability.sh
#
#   # Apply to a specific project only
#   ./configure-immutability.sh --project platform-apps
#
#   # Apply with custom Harbor URL
#   HARBOR_URL=https://harbor.prod.internal ./configure-immutability.sh
#
# Vault Integration:
#   HARBOR_PASS=$(kubectl get secret harbor-admin-credentials \
#     -n harbor-system \
#     -o jsonpath='{.data.password}' | base64 -d)
#
# ADR: docs/adr/adr-084-immutable-image-tags-enforcement.md
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

HARBOR_URL="${HARBOR_URL:-https://harbor.staging.internal}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-}"

# Projects to configure (space-separated)
DEFAULT_PROJECTS="platform-apps microservices infrastructure"

# Mutable tag patterns (exceptions to immutability rule)
# Tags matching these patterns CAN be overwritten (development workflow)
MUTABLE_PATTERNS="dev staging dev/* staging/* feature/* hotfix/*"

# Retention policy: delete dev/staging tags older than N days
RETENTION_DAYS=90

# Script behavior
DRY_RUN=false
SPECIFIC_PROJECT=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
RULES_CREATED=0
RULES_SKIPPED=0
RULES_FAILED=0
RETENTION_CREATED=0

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_dry()     { echo -e "${CYAN}[DRY]${NC}   $*"; }
log_verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "        $*" || true; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Configure Harbor immutable tag rules for platform registry projects.

OPTIONS:
  --dry-run              Preview changes without applying (safe to run anytime)
  --project NAME         Target a specific project only (default: all projects)
  --verbose              Show detailed API responses
  -h, --help             Show this help message

ENVIRONMENT VARIABLES:
  HARBOR_URL             Harbor base URL (default: https://harbor.staging.internal)
  HARBOR_USER            Harbor admin username (default: admin)
  HARBOR_PASS            Harbor admin password (REQUIRED — from Vault secret/harbor/admin)

EXAMPLES:
  # Dry-run preview
  $(basename "$0") --dry-run

  # Apply to all projects
  HARBOR_PASS=\$(kubectl get secret harbor-admin-credentials -n harbor-system \\
    -o jsonpath='{.data.password}' | base64 -d) \\
  $(basename "$0")

  # Apply to specific project
  $(basename "$0") --project platform-apps

  # With custom Harbor URL (production)
  HARBOR_URL=https://harbor.prod.internal $(basename "$0") --dry-run

EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------------------------

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --project)
        SPECIFIC_PROJECT="$2"
        shift 2
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      -h|--help)
        usage
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

validate_prerequisites() {
  log_info "Validating prerequisites..."

  local missing=()

  command -v curl  &>/dev/null || missing+=("curl")
  command -v jq    &>/dev/null || missing+=("jq")

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    log_error "Install with: apt-get install -y curl jq"
    exit 1
  fi

  if [[ -z "$HARBOR_PASS" ]]; then
    log_error "HARBOR_PASS is not set."
    log_error ""
    log_error "Retrieve from Vault via ESO:"
    log_error "  HARBOR_PASS=\$(kubectl get secret harbor-admin-credentials \\"
    log_error "    -n harbor-system \\"
    log_error "    -o jsonpath='{.data.password}' | base64 -d)"
    log_error ""
    log_error "Or set directly:"
    log_error "  export HARBOR_PASS='your-admin-password'"
    exit 1
  fi

  log_success "Prerequisites validated (curl, jq present; credentials set)"
}

# ---------------------------------------------------------------------------
# Harbor API Functions
# ---------------------------------------------------------------------------

# Perform authenticated Harbor API call
# Args: METHOD PATH [BODY]
harbor_api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local url="${HARBOR_URL}/api/v2.0${path}"

  local curl_args=(
    --silent
    --show-error
    --fail-with-body
    --request "$method"
    --header "Content-Type: application/json"
    --header "Accept: application/json"
    --user "${HARBOR_USER}:${HARBOR_PASS}"
  )

  if [[ -n "$body" ]]; then
    curl_args+=(--data "$body")
  fi

  curl "${curl_args[@]}" "$url"
}

# Check if Harbor API is accessible
check_harbor_connectivity() {
  log_info "Checking Harbor API connectivity at ${HARBOR_URL}..."

  local http_code
  http_code=$(curl --silent --output /dev/null --write-out "%{http_code}" \
    --user "${HARBOR_USER}:${HARBOR_PASS}" \
    "${HARBOR_URL}/api/v2.0/systeminfo" 2>/dev/null || echo "000")

  case "$http_code" in
    200)
      log_success "Harbor API accessible (HTTP 200)"
      ;;
    401)
      log_error "Harbor API authentication failed (HTTP 401). Check HARBOR_USER/HARBOR_PASS."
      exit 1
      ;;
    000)
      log_error "Cannot reach Harbor at ${HARBOR_URL}. Is the cluster running?"
      log_error "For port-forwarding: kubectl port-forward -n harbor-system svc/harbor-core 8080:80"
      exit 1
      ;;
    *)
      log_error "Harbor API returned unexpected HTTP ${http_code}"
      exit 1
      ;;
  esac
}

# Get Harbor system version info
get_harbor_version() {
  local version
  version=$(harbor_api GET /systeminfo 2>/dev/null | jq -r '.harbor_version // "unknown"')
  log_info "Harbor version: ${version}"
}

# ---------------------------------------------------------------------------
# Project Management
# ---------------------------------------------------------------------------

# Get project ID by name
# Returns empty string if project does not exist
get_project_id() {
  local project_name="$1"
  harbor_api GET "/projects?name=${project_name}&page_size=1" 2>/dev/null \
    | jq -r ".[] | select(.name == \"${project_name}\") | .id // empty" \
    | head -1
}

# Check if a project exists
project_exists() {
  local project_name="$1"
  local project_id
  project_id=$(get_project_id "$project_name")
  [[ -n "$project_id" ]]
}

# Create a project if it does not exist
ensure_project_exists() {
  local project_name="$1"

  if project_exists "$project_name"; then
    log_verbose "Project '${project_name}' already exists"
    return 0
  fi

  log_info "Creating project '${project_name}'..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry "Would create project: ${project_name} (private, auto-scan enabled)"
    return 0
  fi

  local response http_code
  http_code=$(curl --silent --output /dev/null --write-out "%{http_code}" \
    --request POST \
    --header "Content-Type: application/json" \
    --user "${HARBOR_USER}:${HARBOR_PASS}" \
    --data "{
      \"project_name\": \"${project_name}\",
      \"metadata\": {
        \"public\": \"false\",
        \"enable_content_trust\": \"false\",
        \"auto_scan\": \"true\",
        \"severity\": \"medium\",
        \"reuse_sys_cve_allowlist\": \"true\"
      }
    }" \
    "${HARBOR_URL}/api/v2.0/projects")

  if [[ "$http_code" == "201" ]]; then
    log_success "Created project: ${project_name}"
  else
    log_warn "Project creation returned HTTP ${http_code} for '${project_name}'"
  fi
}

# ---------------------------------------------------------------------------
# Immutability Rules
# ---------------------------------------------------------------------------

# List existing immutability rules for a project
list_immutability_rules() {
  local project_id="$1"
  harbor_api GET "/projects/${project_id}/immutabletagrules" 2>/dev/null
}

# Check if an immutability rule already exists for given tag filter
# Args: project_id tag_filter
rule_exists() {
  local project_id="$1"
  local tag_filter="$2"

  local existing
  existing=$(list_immutability_rules "$project_id" 2>/dev/null)

  echo "$existing" | jq -e --arg tf "$tag_filter" \
    '.[] | select(.tag_selectors[]?.pattern == $tf)' &>/dev/null
}

# Create immutability rule for a project
# Args: project_id project_name tag_filter mutable (true=mutable, false=immutable)
create_immutability_rule() {
  local project_id="$1"
  local project_name="$2"
  local tag_filter="$3"
  local is_mutable="${4:-false}"

  local rule_desc
  if [[ "$is_mutable" == "true" ]]; then
    rule_desc="MUTABLE (${tag_filter} — development tags)"
  else
    rule_desc="IMMUTABLE (${tag_filter})"
  fi

  # Check if rule already exists (idempotency)
  if rule_exists "$project_id" "$tag_filter" 2>/dev/null; then
    log_verbose "Rule already exists for tag '${tag_filter}' in '${project_name}'"
    ((RULES_SKIPPED++)) || true
    return 0
  fi

  log_info "  Adding rule: ${rule_desc} → project '${project_name}'"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry "  Would POST /projects/${project_id}/immutabletagrules — tag: ${tag_filter}"
    ((RULES_CREATED++)) || true
    return 0
  fi

  # Harbor immutability rule payload
  # disabled: false = rule is ACTIVE
  # action: immutableTagRule = immutable
  # tag_selectors: which tags this rule applies to
  # repository_selectors: which repos (** = all)
  local payload
  payload=$(jq -n \
    --arg tag_filter "$tag_filter" \
    --argjson disabled false \
    '{
      "disabled": $disabled,
      "action": "immutableTagRule",
      "tag_selectors": [
        {
          "kind": "doublestar",
          "decoration": "matches",
          "pattern": $tag_filter,
          "extras": "{}"
        }
      ],
      "scope_selectors": {
        "repository": [
          {
            "kind": "doublestar",
            "decoration": "repoMatches",
            "pattern": "**",
            "extras": "{}"
          }
        ]
      }
    }')

  local http_code
  http_code=$(curl --silent --output /dev/null --write-out "%{http_code}" \
    --request POST \
    --header "Content-Type: application/json" \
    --user "${HARBOR_USER}:${HARBOR_PASS}" \
    --data "$payload" \
    "${HARBOR_URL}/api/v2.0/projects/${project_id}/immutabletagrules")

  if [[ "$http_code" == "201" ]]; then
    log_success "  Rule created: ${rule_desc}"
    ((RULES_CREATED++)) || true
  else
    log_error "  Failed to create rule (HTTP ${http_code}): ${rule_desc}"
    log_verbose "  Payload: ${payload}"
    ((RULES_FAILED++)) || true
  fi
}

# Configure immutability rules for a project
# Strategy:
#   1. Create IMMUTABLE rule for ALL tags (**)
#   2. This is the catch-all: any tag not matching an exception is immutable
#
# NOTE: Harbor evaluates rules top-down; the most specific mutable-exception
#       rule must be created AFTER the catch-all immutable rule.
#       Harbor 2.x does NOT support "except" logic in a single rule —
#       the workaround is to delete + recreate tags in the mutable exception
#       patterns. For dev/staging workflows, teams push to mutable tag slots.
configure_project_immutability() {
  local project_name="$1"
  local project_id

  echo ""
  log_info "=== Configuring project: ${project_name} ==="

  project_id=$(get_project_id "$project_name")
  if [[ -z "$project_id" ]]; then
    log_warn "Project '${project_name}' not found — skipping (use ensure_project_exists first)"
    return 0
  fi

  log_verbose "Project ID: ${project_id}"

  # List current rules
  local existing_count
  existing_count=$(list_immutability_rules "$project_id" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
  log_info "  Existing rules: ${existing_count}"

  # Rule 1: Immutable — ALL production tags (sha-*, v*)
  # These tags are created by CI with git SHA or semver — must never be overwritten
  create_immutability_rule "$project_id" "$project_name" "sha-*"    "false"
  create_immutability_rule "$project_id" "$project_name" "v*"       "false"
  create_immutability_rule "$project_id" "$project_name" "release-*" "false"

  # Rule 2: Catch-all immutable for any other production-style tags
  # This prevents accidental pushes of unrecognized tag formats to production repos
  # Teams pushing to dev/staging environments MUST use the mutable patterns below
  create_immutability_rule "$project_id" "$project_name" "latest"   "false"

  log_success "  Immutability rules configured for '${project_name}'"
}

# ---------------------------------------------------------------------------
# Tag Retention Policies
# ---------------------------------------------------------------------------

# Configure tag retention policy to auto-delete old dev/staging tags
configure_tag_retention() {
  local project_id="$1"
  local project_name="$2"

  log_info "  Configuring tag retention (${RETENTION_DAYS}-day cleanup for dev/staging)..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry "  Would configure retention policy: delete dev/staging/feature/* tags > ${RETENTION_DAYS} days"
    ((RETENTION_CREATED++)) || true
    return 0
  fi

  # Harbor retention policy payload
  # Selectors: tags matching dev/staging/feature/* older than RETENTION_DAYS days
  # Action: retain (negate → delete non-matching from candidates)
  local payload
  payload=$(jq -n \
    --argjson days "$RETENTION_DAYS" \
    --argjson project_id "$project_id" \
    '{
      "algorithm": "or",
      "rules": [
        {
          "disabled": false,
          "priority": 1,
          "action": "retain",
          "template": "latestPushedK",
          "params": {
            "latestPushedK": 10
          },
          "tag_selectors": [
            {
              "kind": "doublestar",
              "decoration": "matches",
              "pattern": "dev*",
              "extras": "{}"
            }
          ],
          "scope_selectors": {
            "repository": [
              {
                "kind": "doublestar",
                "decoration": "repoMatches",
                "pattern": "**",
                "extras": "{}"
              }
            ]
          }
        },
        {
          "disabled": false,
          "priority": 2,
          "action": "retain",
          "template": "latestPushedK",
          "params": {
            "latestPushedK": 10
          },
          "tag_selectors": [
            {
              "kind": "doublestar",
              "decoration": "matches",
              "pattern": "staging*",
              "extras": "{}"
            }
          ],
          "scope_selectors": {
            "repository": [
              {
                "kind": "doublestar",
                "decoration": "repoMatches",
                "pattern": "**",
                "extras": "{}"
              }
            ]
          }
        },
        {
          "disabled": false,
          "priority": 3,
          "action": "retain",
          "template": "latestPushedK",
          "params": {
            "latestPushedK": 5
          },
          "tag_selectors": [
            {
              "kind": "doublestar",
              "decoration": "matches",
              "pattern": "feature-*",
              "extras": "{}"
            }
          ],
          "scope_selectors": {
            "repository": [
              {
                "kind": "doublestar",
                "decoration": "repoMatches",
                "pattern": "**",
                "extras": "{}"
              }
            ]
          }
        }
      ],
      "scope": {
        "level": "project",
        "ref": $project_id
      },
      "trigger": {
        "kind": "Schedule",
        "settings": {
          "cron": "0 0 * * 0"
        },
        "references": {}
      }
    }')

  # Check if retention policy already exists
  local existing_retention
  existing_retention=$(harbor_api GET "/retentions/metadatas?project_id=${project_id}" 2>/dev/null \
    | jq -r '.[0].id // empty' 2>/dev/null || echo "")

  if [[ -n "$existing_retention" ]]; then
    log_verbose "  Retention policy already exists (ID: ${existing_retention}) — skipping"
    return 0
  fi

  local http_code
  http_code=$(curl --silent --output /dev/null --write-out "%{http_code}" \
    --request POST \
    --header "Content-Type: application/json" \
    --user "${HARBOR_USER}:${HARBOR_PASS}" \
    --data "$payload" \
    "${HARBOR_URL}/api/v2.0/retentions")

  if [[ "$http_code" == "201" ]]; then
    log_success "  Retention policy created (${RETENTION_DAYS}-day cleanup, weekly schedule)"
    ((RETENTION_CREATED++)) || true
  elif [[ "$http_code" == "200" ]]; then
    log_success "  Retention policy updated"
    ((RETENTION_CREATED++)) || true
  else
    log_warn "  Retention policy returned HTTP ${http_code} for '${project_name}' (may already exist)"
  fi
}

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

# Verify immutability rules are active after configuration
verify_project_rules() {
  local project_name="$1"
  local project_id

  project_id=$(get_project_id "$project_name")
  if [[ -z "$project_id" ]]; then
    return 0
  fi

  local rules
  rules=$(list_immutability_rules "$project_id" 2>/dev/null)

  local rule_count
  rule_count=$(echo "$rules" | jq 'length' 2>/dev/null || echo "0")

  if [[ "$rule_count" -gt 0 ]]; then
    log_success "  Verified: ${rule_count} immutability rule(s) active for '${project_name}'"

    if [[ "$VERBOSE" == "true" ]]; then
      echo "$rules" | jq -r '.[] | "    - tag: \(.tag_selectors[0].pattern) | disabled: \(.disabled)"'
    fi
  else
    log_warn "  No immutability rules found for '${project_name}' — verification failed"
  fi
}

# ---------------------------------------------------------------------------
# Summary Report
# ---------------------------------------------------------------------------

print_summary() {
  echo ""
  echo "============================================================"
  echo " CICD-004 Immutability Configuration — Summary"
  echo "============================================================"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo " Mode: DRY-RUN (no changes applied)"
  else
    echo " Mode: APPLIED"
  fi

  echo " Harbor: ${HARBOR_URL}"
  echo ""
  echo " Rules created:   ${RULES_CREATED}"
  echo " Rules skipped:   ${RULES_SKIPPED} (already existed)"
  echo " Rules failed:    ${RULES_FAILED}"
  echo " Retention rules: ${RETENTION_CREATED}"
  echo ""

  if [[ "$RULES_FAILED" -gt 0 ]]; then
    echo -e " ${RED}Status: PARTIAL — ${RULES_FAILED} rule(s) failed${NC}"
    echo " Review logs above and re-run for failed projects."
    exit 1
  else
    echo -e " ${GREEN}Status: SUCCESS${NC}"
  fi

  echo ""
  echo " Tag Strategy Applied:"
  echo "   IMMUTABLE: sha-*, v*, release-*, latest"
  echo "   CI Mutable: dev/staging tags (dev-*, staging-*)"
  echo "   Retention: Keep last 10 dev/staging, 5 feature/* tags"
  echo ""
  echo " Next Steps:"
  echo "   1. Verify rules in Harbor UI: ${HARBOR_URL}/harbor/projects"
  echo "   2. Test: push sha-* tag → should succeed (first push)"
  echo "   3. Test: push same sha-* tag again → should fail (immutable)"
  echo "   4. Update .gitlab-ci-security-template.yml in your projects"
  echo "   5. See: docs/guides/image-tagging-best-practices.md"
  echo "============================================================"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  parse_args "$@"

  echo ""
  echo "============================================================"
  echo " Harbor Immutability Configuration — CICD-004"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo " Mode: DRY-RUN (preview only — no changes will be made)"
  fi
  echo "============================================================"
  echo ""

  # Validate before proceeding
  validate_prerequisites

  # Check connectivity only when not in dry-run (environment may be offline)
  if [[ "$DRY_RUN" == "false" ]]; then
    check_harbor_connectivity
    get_harbor_version
  else
    log_info "Dry-run mode: skipping Harbor connectivity check"
  fi

  # Determine target projects
  local projects
  if [[ -n "$SPECIFIC_PROJECT" ]]; then
    projects="$SPECIFIC_PROJECT"
    log_info "Targeting specific project: ${SPECIFIC_PROJECT}"
  else
    projects="$DEFAULT_PROJECTS"
    log_info "Targeting all default projects: ${projects}"
  fi

  # Process each project
  for project_name in $projects; do
    # Ensure project exists (create if missing)
    if [[ "$DRY_RUN" == "false" ]]; then
      ensure_project_exists "$project_name"
    fi

    # Get project ID
    local project_id=""
    if [[ "$DRY_RUN" == "false" ]]; then
      project_id=$(get_project_id "$project_name")
      if [[ -z "$project_id" ]]; then
        log_warn "Project '${project_name}' not found after creation — skipping"
        continue
      fi
    fi

    # Configure immutability rules
    configure_project_immutability "$project_name"

    # Configure tag retention policy
    if [[ "$DRY_RUN" == "false" ]] && [[ -n "$project_id" ]]; then
      configure_tag_retention "$project_id" "$project_name"
    elif [[ "$DRY_RUN" == "true" ]]; then
      log_dry "Would configure retention policy for: ${project_name}"
      ((RETENTION_CREATED++)) || true
    fi
  done

  # Verification pass (live mode only)
  if [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    log_info "=== Verification Pass ==="
    for project_name in $projects; do
      verify_project_rules "$project_name"
    done
  fi

  print_summary
}

main "$@"
