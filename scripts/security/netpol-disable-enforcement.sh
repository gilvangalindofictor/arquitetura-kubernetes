#!/bin/bash

# Script: netpol-disable-enforcement.sh
# Purpose: Rollback Network Policy enforcement by re-enabling audit mode (emergency only)
# Usage: ./netpol-disable-enforcement.sh [OPTIONS]
# Options:
#   --dry-run          Show what would change without making changes
#   --mode OPTION      Rollback mode: audit-mode (default) or delete
#   --namespace NS     Rollback only specific namespace
#   --confirm          Skip confirmation prompt (for automation)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
CONFIRM=false
FILTER_NAMESPACE=""
ROLLBACK_MODE="audit-mode"  # Options: audit-mode, delete
NAMESPACES=("argocd" "sonarqube" "keycloak" "staging-platform-gitlab" "staging-security-vault")

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# Functions
# ============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Options:
  --dry-run           Show what would be changed without making changes
  --mode MODE         Rollback mode: audit-mode (default) or delete
  --namespace NS      Rollback only specific namespace
  --confirm           Skip confirmation prompt (for automation)
  --help              Show this help message

Rollback Modes:
  audit-mode          Re-enable audit annotations (recommended - keeps policies in place)
  delete              Delete all GAP-007 policies completely (last resort)

Examples:
  # Return all policies to audit mode (recommended)
  $0 --confirm

  # Dry-run to see what would change
  $0 --dry-run

  # Delete all policies (emergency only)
  $0 --mode delete --confirm

  # Rollback only Keycloak policies
  $0 --namespace keycloak --confirm

EOF
  exit 0
}

# Confirmation prompt
confirm() {
  if $CONFIRM; then
    return 0
  fi

  local prompt="$1"
  local response

  read -p "$(echo -e ${YELLOW}$prompt${NC}) (yes/no) " response
  [[ "$response" == "yes" ]] || return 1
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --mode)
      ROLLBACK_MODE="$2"
      if [[ ! "$ROLLBACK_MODE" =~ ^(audit-mode|delete)$ ]]; then
        log_error "Invalid rollback mode: $ROLLBACK_MODE"
        usage
      fi
      shift 2
      ;;
    --namespace)
      FILTER_NAMESPACE="$2"
      shift 2
      ;;
    --confirm)
      CONFIRM=true
      shift
      ;;
    --help)
      usage
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

# ============================================================================
# Pre-Flight Checks
# ============================================================================

preflight_checks() {
  log_info "Performing pre-flight checks..."
  echo ""

  # Check kubectl access
  if ! kubectl auth can-i get networkpolicies --all-namespaces &>/dev/null; then
    log_error "Insufficient permissions: cannot read network policies"
    return 1
  fi

  if ! kubectl auth can-i patch networkpolicies --all-namespaces &>/dev/null; then
    log_error "Insufficient permissions: cannot patch network policies"
    return 1
  fi

  if ! kubectl auth can-i delete networkpolicies --all-namespaces &>/dev/null; then
    log_error "Insufficient permissions: cannot delete network policies"
    return 1
  fi

  log_success "kubectl permissions verified"

  # Check cluster connectivity
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    return 1
  fi

  log_success "Kubernetes cluster accessible"

  echo ""
  return 0
}

# ============================================================================
# Collect Policies
# ============================================================================

collect_policies() {
  local policies_array=()
  local mode="$1"  # "enforced" or "all"

  # Build namespace list
  local target_namespaces=()
  if [[ -n "$FILTER_NAMESPACE" ]]; then
    target_namespaces=("$FILTER_NAMESPACE")
  else
    target_namespaces=("${NAMESPACES[@]}")
  fi

  # Collect policies
  for ns in "${target_namespaces[@]}"; do
    # Check if namespace exists
    if ! kubectl get namespace "$ns" &>/dev/null; then
      continue
    fi

    # Get policies based on mode
    if [[ "$mode" == "enforced" ]]; then
      # Get enforced policies (audit-mode NOT true or missing)
      while IFS= read -r policy; do
        [[ -n "$policy" ]] && policies_array+=("$ns:$policy")
      done < <(kubectl get networkpolicies -n "$ns" -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.annotations["policy.cilium.io/audit-mode"] != "true") | .metadata.name')
    else
      # Get all GAP-007 policies
      while IFS= read -r policy; do
        [[ -n "$policy" ]] && policies_array+=("$ns:$policy")
      done < <(kubectl get networkpolicies -n "$ns" -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.annotations["gap"] == "GAP-007") | .metadata.name')
    fi
  done

  printf '%s\n' "${policies_array[@]}"
}

# ============================================================================
# Main Rollback Logic
# ============================================================================

main() {
  echo ""
  log_info "==================================================="
  log_info "Network Policy Rollback"
  log_info "==================================================="
  echo ""

  if $DRY_RUN; then
    log_info "Running in DRY-RUN mode (no changes will be made)"
    echo ""
  fi

  # Display warning based on mode
  case $ROLLBACK_MODE in
    audit-mode)
      log_warn "This will RE-ENABLE AUDIT MODE on all Network Policies"
      log_info "Policies will log violations but NOT block traffic"
      echo ""
      ;;
    delete)
      log_error "⚠️  THIS WILL DELETE ALL GAP-007 NETWORK POLICIES"
      log_error "All traffic restrictions will be removed immediately"
      log_error "Use only if audit-mode rollback fails"
      echo ""
      ;;
  esac

  # Pre-flight checks
  if ! preflight_checks; then
    log_error "Pre-flight checks failed"
    return 1
  fi

  # Step 1: Collect policies to rollback
  log_info "Collecting Network Policies for rollback..."
  echo ""

  case $ROLLBACK_MODE in
    audit-mode)
      mapfile -t POLICIES_TO_ROLLBACK < <(collect_policies "enforced")
      ;;
    delete)
      mapfile -t POLICIES_TO_ROLLBACK < <(collect_policies "all")
      ;;
  esac

  if [[ ${#POLICIES_TO_ROLLBACK[@]} -eq 0 ]]; then
    if [[ "$ROLLBACK_MODE" == "audit-mode" ]]; then
      log_info "No enforced policies found (all may be in audit mode already)"
    else
      log_info "No GAP-007 policies found"
    fi
    return 0
  fi

  # Display policies
  log_info "Found ${#POLICIES_TO_ROLLBACK[@]} policies for rollback:"
  echo ""
  for policy_pair in "${POLICIES_TO_ROLLBACK[@]}"; do
    NS="${policy_pair%%:*}"
    POLICY="${policy_pair##*:}"
    echo "  • $NS/$POLICY"
  done

  echo ""

  # Step 2: Confirmation
  local prompt
  case $ROLLBACK_MODE in
    audit-mode)
      prompt="Re-enable audit mode on ${#POLICIES_TO_ROLLBACK[@]} policies?"
      ;;
    delete)
      prompt="⚠️  DELETE ${#POLICIES_TO_ROLLBACK[@]} Network Policies? (LAST RESORT)"
      ;;
  esac

  if ! $DRY_RUN; then
    if ! confirm "$prompt"; then
      log_warn "Rollback cancelled by user"
      return 0
    fi
    echo ""
  fi

  # Step 3: Execute rollback
  log_info "Executing rollback..."
  echo ""

  local success_count=0
  local error_count=0
  local start_time=$(date +%s)

  for policy_pair in "${POLICIES_TO_ROLLBACK[@]}"; do
    NS="${policy_pair%%:*}"
    POLICY="${policy_pair##*:}"

    if $DRY_RUN; then
      case $ROLLBACK_MODE in
        audit-mode)
          echo -e "${YELLOW}[DRY-RUN]${NC} Would enable audit mode: $NS/$POLICY"
          ;;
        delete)
          echo -e "${YELLOW}[DRY-RUN]${NC} Would delete: $NS/$POLICY"
          ;;
      esac
      ((success_count++))
      continue
    fi

    case $ROLLBACK_MODE in
      audit-mode)
        # Re-enable audit mode
        if kubectl annotate networkpolicy "$POLICY" -n "$NS" \
          "policy.cilium.io/audit-mode=true" \
          --overwrite &>/dev/null; then
          log_success "$NS/$POLICY (audit mode enabled)"
          ((success_count++))
        else
          log_error "Failed to enable audit mode on $NS/$POLICY"
          ((error_count++))
        fi
        ;;
      delete)
        # Delete policy
        if kubectl delete networkpolicy "$POLICY" -n "$NS" &>/dev/null; then
          log_success "$NS/$POLICY (deleted)"
          ((success_count++))
        else
          log_error "Failed to delete $NS/$POLICY"
          ((error_count++))
        fi
        ;;
    esac
  done

  echo ""

  # Step 4: Validation
  log_info "Validating rollback..."
  echo ""

  case $ROLLBACK_MODE in
    audit-mode)
      # Verify audit mode re-enabled
      local still_enforced=0
      for policy_pair in "${POLICIES_TO_ROLLBACK[@]}"; do
        NS="${policy_pair%%:*}"
        POLICY="${policy_pair##*:}"

        AUDIT_MODE=$(kubectl get networkpolicy "$POLICY" -n "$NS" \
          -o jsonpath='{.metadata.annotations.policy\.cilium\.io/audit-mode}' 2>/dev/null || echo "")

        if [[ "$AUDIT_MODE" != "true" ]]; then
          log_error "$NS/$POLICY still enforcing!"
          ((still_enforced++))
        fi
      done

      if [[ $still_enforced -gt 0 ]]; then
        log_error "Rollback validation failed: $still_enforced policies still enforcing"
        error_count=$((error_count + still_enforced))
      fi
      ;;
    delete)
      # Verify policies deleted
      local still_exist=0
      for policy_pair in "${POLICIES_TO_ROLLBACK[@]}"; do
        NS="${policy_pair%%:*}"
        POLICY="${policy_pair##*:}"

        if kubectl get networkpolicy "$POLICY" -n "$NS" &>/dev/null; then
          log_error "$NS/$POLICY still exists!"
          ((still_exist++))
        fi
      done

      if [[ $still_exist -gt 0 ]]; then
        log_error "Rollback validation failed: $still_exist policies still exist"
        error_count=$((error_count + still_exist))
      fi
      ;;
  esac

  echo ""
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Step 5: Summary
  log_info "==================================================="
  log_info "Rollback Summary"
  log_info "==================================================="
  echo ""
  echo -e "${BLUE}Policies Rolled Back:${NC} $success_count/${#POLICIES_TO_ROLLBACK[@]}"
  echo -e "${BLUE}Errors:${NC} $error_count"
  echo -e "${BLUE}Time Taken:${NC} ${duration}s"
  echo ""

  if [[ $error_count -eq 0 ]]; then
    log_success "Rollback successful!"
    echo ""
    case $ROLLBACK_MODE in
      audit-mode)
        echo "All policies are now in AUDIT MODE."
        echo "Traffic is not being blocked, only logged."
        echo "Review issues and re-validate before enforcement."
        ;;
      delete)
        echo "All GAP-007 policies have been deleted."
        echo "Network traffic restrictions have been removed."
        echo "CRITICAL: Document why policies were deleted and plan recovery."
        ;;
    esac
    echo ""
    return 0
  else
    log_error "Rollback completed with errors"
    return 1
  fi
}

# ============================================================================
# Execute
# ============================================================================

main "$@"
EXIT_CODE=$?

exit $EXIT_CODE
