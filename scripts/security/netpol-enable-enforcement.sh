#!/bin/bash

# Script: netpol-enable-enforcement.sh
# Purpose: Enable enforcement of Network Policies by removing audit-mode annotations
# Usage: ./netpol-enable-enforcement.sh [OPTIONS]
# Options:
#   --dry-run          Show what would be changed without making changes
#   --namespace NS     Enforce policies only in specific namespace
#   --policy NAME      Enforce only specific policy
#   --confirm          Skip confirmation prompt (for automation)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
CONFIRM=false
FILTER_NAMESPACE=""
FILTER_POLICY=""
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
  --namespace NS      Enforce policies only in specific namespace
  --policy NAME       Enforce only specific policy (with --namespace)
  --confirm           Skip confirmation prompt (for automation/scripts)
  --help              Show this help message

Examples:
  # Full enforcement (all 22 GAP-007 policies)
  $0 --confirm

  # Dry-run to see what would change
  $0 --dry-run

  # Enforce only Keycloak policies
  $0 --namespace keycloak --confirm

  # Enforce specific policy
  $0 --namespace argocd --policy argocd-server-ingress --confirm

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
    --namespace)
      FILTER_NAMESPACE="$2"
      shift 2
      ;;
    --policy)
      FILTER_POLICY="$2"
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

  log_success "kubectl permissions verified"

  # Check cluster connectivity
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    return 1
  fi

  log_success "Kubernetes cluster accessible"

  # Verify Calico is installed
  CALICO_PODS=$(kubectl get pods -n kube-system -l k8s-app=calico-node -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  if [[ -z "$CALICO_PODS" ]]; then
    log_warn "No Calico node pods found - policies may not enforce properly"
  else
    log_success "Calico CNI verified ($(echo "$CALICO_PODS" | wc -w) nodes)"
  fi

  echo ""
  return 0
}

# ============================================================================
# Collect Policies
# ============================================================================

collect_policies() {
  local policies_array=()

  # Build namespace list
  local target_namespaces=()
  if [[ -n "$FILTER_NAMESPACE" ]]; then
    target_namespaces=("$FILTER_NAMESPACE")
  else
    target_namespaces=("${NAMESPACES[@]}")
  fi

  # Collect all audit-mode policies
  for ns in "${target_namespaces[@]}"; do
    # Check if namespace exists
    if ! kubectl get namespace "$ns" &>/dev/null; then
      log_warn "Namespace $ns does not exist, skipping"
      continue
    fi

    # Get all policies in namespace that are in audit mode
    while IFS= read -r policy; do
      if [[ -n "$FILTER_POLICY" ]]; then
        # If specific policy filter, only include that one
        [[ "$policy" != "$FILTER_POLICY" ]] && continue
      fi

      policies_array+=("$ns:$policy")
    done < <(kubectl get networkpolicies -n "$ns" -o json 2>/dev/null | \
      jq -r '.items[] | select(.metadata.annotations["policy.cilium.io/audit-mode"] == "true") | .metadata.name')
  done

  printf '%s\n' "${policies_array[@]}"
}

# ============================================================================
# Main Enforcement Logic
# ============================================================================

main() {
  echo ""
  log_info "==================================================="
  log_info "Network Policy Enforcement"
  log_info "==================================================="
  echo ""

  if $DRY_RUN; then
    log_info "Running in DRY-RUN mode (no changes will be made)"
    echo ""
  fi

  # Step 1: Pre-flight checks
  if ! preflight_checks; then
    log_error "Pre-flight checks failed"
    return 1
  fi

  # Step 2: Collect policies to enforce
  log_info "Collecting Network Policies to enforce..."
  echo ""

  mapfile -t POLICIES_TO_ENFORCE < <(collect_policies)

  if [[ ${#POLICIES_TO_ENFORCE[@]} -eq 0 ]]; then
    log_warn "No Network Policies found in audit mode"
    log_info "All policies may already be enforced, or no GAP-007 policies found"
    return 0
  fi

  # Display policies to be enforced
  log_info "Found ${#POLICIES_TO_ENFORCE[@]} policies in audit mode:"
  echo ""
  for policy_pair in "${POLICIES_TO_ENFORCE[@]}"; do
    NS="${policy_pair%%:*}"
    POLICY="${policy_pair##*:}"
    echo "  • $NS/$POLICY"
  done

  echo ""

  # Step 3: Confirmation
  if ! $DRY_RUN; then
    if ! confirm "⚠️  Remove audit-mode annotation from ${#POLICIES_TO_ENFORCE[@]} policies? This will ENABLE traffic blocking."; then
      log_warn "Enforcement cancelled by user"
      return 0
    fi
    echo ""
  fi

  # Step 4: Enforce policies
  log_info "Enforcing policies..."
  echo ""

  local success_count=0
  local error_count=0
  local start_time=$(date +%s)

  for policy_pair in "${POLICIES_TO_ENFORCE[@]}"; do
    NS="${policy_pair%%:*}"
    POLICY="${policy_pair##*:}"

    if $DRY_RUN; then
      echo -e "${YELLOW}[DRY-RUN]${NC} Would enforce: $NS/$POLICY"
      ((success_count++))
      continue
    fi

    # Remove audit-mode annotation (this enables enforcement)
    if kubectl annotate networkpolicy "$POLICY" -n "$NS" \
      "policy.cilium.io/audit-mode-" \
      --overwrite &>/dev/null; then
      log_success "$NS/$POLICY (enforced)"
      ((success_count++))
    else
      log_error "Failed to enforce $NS/$POLICY"
      ((error_count++))
    fi
  done

  echo ""

  # Step 5: Validation
  log_info "Validating enforcement..."
  echo ""

  # Verify audit-mode annotations removed
  local still_in_audit=0
  for policy_pair in "${POLICIES_TO_ENFORCE[@]}"; do
    NS="${policy_pair%%:*}"
    POLICY="${policy_pair##*:}"

    AUDIT_MODE=$(kubectl get networkpolicy "$POLICY" -n "$NS" \
      -o jsonpath='{.metadata.annotations.policy\.cilium\.io/audit-mode}' 2>/dev/null || echo "")

    if [[ "$AUDIT_MODE" == "true" ]]; then
      log_error "$NS/$POLICY still in audit mode!"
      ((still_in_audit++))
    fi
  done

  echo ""
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Step 6: Summary
  log_info "==================================================="
  log_info "Enforcement Summary"
  log_info "==================================================="
  echo ""
  echo -e "${BLUE}Policies Enforced:${NC} $success_count/${#POLICIES_TO_ENFORCE[@]}"
  echo -e "${BLUE}Errors:${NC} $error_count"
  echo -e "${BLUE}Time Taken:${NC} ${duration}s"
  echo ""

  if [[ $error_count -eq 0 ]] && [[ $still_in_audit -eq 0 ]]; then
    log_success "All policies successfully enforced!"
    echo ""
    echo "Next steps:"
    echo "1. Run connectivity tests: bash netpol-connectivity-tests.sh"
    echo "2. Monitor for 30 minutes for unexpected errors"
    echo "3. Update ADR-070 with enforcement date"
    echo ""
    return 0
  else
    log_error "Enforcement completed with errors"
    echo ""
    echo "Issues found:"
    if [[ $error_count -gt 0 ]]; then
      echo "  • $error_count policies failed to enforce"
    fi
    if [[ $still_in_audit -gt 0 ]]; then
      echo "  • $still_in_audit policies still in audit mode"
    fi
    echo ""
    return 1
  fi
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
EXIT_CODE=$?

exit $EXIT_CODE
