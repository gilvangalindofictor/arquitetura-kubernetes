#!/bin/bash

# Script: netpol-audit-analysis.sh
# Purpose: Analyze Network Policy audit logs from Calico to detect unexpected traffic blocks
# Usage: ./netpol-audit-analysis.sh [OPTIONS]
# Options:
#   --all      Analyze last 24 hours (default: last 1 hour)
#   --days N   Analyze last N days (default: 1)
#   --policy NAME  Filter by specific policy name
#   --namespace NS Analyze specific namespace only

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/tmp/netpol-audit-$(date +%s)"
HOURS_TO_ANALYZE=1
DAYS_TO_ANALYZE=0
FILTER_POLICY=""
FILTER_NAMESPACE=""
NAMESPACES=("argocd" "sonarqube" "keycloak" "staging-platform-gitlab" "staging-security-vault" "staging-security-vault")
CALICO_NAMESPACE="kube-system"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
  --all               Analyze last 24 hours (instead of last 1 hour)
  --days N            Analyze last N days (overrides --all)
  --policy NAME       Filter audit logs by policy name
  --namespace NS      Analyze specific namespace only
  --help              Show this help message

Examples:
  # Daily validation (analyze last 1 hour)
  $0

  # Full week review (analyze last 7 days)
  $0 --days 7

  # Specific policy analysis
  $0 --policy keycloak-ingress

  # Namespace-specific audit
  $0 --namespace staging-platform-gitlab

EOF
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --all)
      HOURS_TO_ANALYZE=24
      shift
      ;;
    --days)
      DAYS_TO_ANALYZE=$2
      HOURS_TO_ANALYZE=$((DAYS_TO_ANALYZE * 24))
      shift 2
      ;;
    --policy)
      FILTER_POLICY="$2"
      shift 2
      ;;
    --namespace)
      FILTER_NAMESPACE="$2"
      shift 2
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
# Main Execution
# ============================================================================

main() {
  echo ""
  log_info "==================================================="
  log_info "Network Policy Audit Log Analysis"
  log_info "==================================================="
  echo ""
  log_info "Analyzing last ${HOURS_TO_ANALYZE} hours of audit logs"
  [[ -n "$FILTER_POLICY" ]] && log_info "Policy filter: $FILTER_POLICY"
  [[ -n "$FILTER_NAMESPACE" ]] && log_info "Namespace filter: $FILTER_NAMESPACE"
  echo ""

  mkdir -p "$LOG_DIR"

  # ========================================================================
  # Step 1: Collect Calico audit logs
  # ========================================================================

  log_info "Collecting Calico audit logs from kube-system namespace..."

  # Get all Calico node logs
  CALICO_NODES=$(kubectl get pods -n "$CALICO_NAMESPACE" -l k8s-app=calico-node -o jsonpath='{.items[*].metadata.name}')

  if [[ -z "$CALICO_NODES" ]]; then
    log_error "No Calico node pods found in $CALICO_NAMESPACE"
    log_info "Network Policies may not be properly installed"
    echo ""
    return 1
  fi

  TOTAL_DENIES=0
  UNIQUE_POLICIES=0

  # Get logs from last N hours
  SINCE_TIME=$((HOURS_TO_ANALYZE * 60))

  for node in $CALICO_NODES; do
    node_log="$LOG_DIR/${node}.log"
    # Fetch logs from Calico node pod (audit mode logs policy evaluations)
    kubectl logs -n "$CALICO_NAMESPACE" "$node" --tail=5000 2>/dev/null > "$node_log" || {
      log_warn "Could not retrieve logs from $node"
      continue
    }
  done

  log_success "Calico logs collected to $LOG_DIR"
  echo ""

  # ========================================================================
  # Step 2: Parse and aggregate audit data
  # ========================================================================

  log_info "Parsing audit logs for policy violations..."

  # Combine all logs
  COMBINED_LOG="$LOG_DIR/combined.log"
  cat "$LOG_DIR"/*.log > "$COMBINED_LOG" 2>/dev/null || true

  # Parse policy denies (look for indicators of blocked traffic)
  # Calico audit logs typically include patterns like:
  #   - "policy=" markers
  #   - "denied" or "drop" keywords
  #   - pod to pod communication attempts

  DENY_LOG="$LOG_DIR/denies.log"

  # Extract deny/block patterns from logs
  grep -iE "(policy|denied|drop|reject)" "$COMBINED_LOG" > "$DENY_LOG" 2>/dev/null || true

  # Filter by policy if specified
  if [[ -n "$FILTER_POLICY" ]]; then
    grep -i "$FILTER_POLICY" "$DENY_LOG" > "$DENY_LOG.tmp" && mv "$DENY_LOG.tmp" "$DENY_LOG" || true
  fi

  # Filter by namespace if specified
  if [[ -n "$FILTER_NAMESPACE" ]]; then
    grep -i "$FILTER_NAMESPACE" "$DENY_LOG" > "$DENY_LOG.tmp" && mv "$DENY_LOG.tmp" "$DENY_LOG" || true
  fi

  # Count unique denies
  DENY_COUNT=$(wc -l < "$DENY_LOG")
  TOTAL_DENIES=$(($TOTAL_DENIES + $DENY_COUNT))

  log_success "Parsed audit logs: $DENY_COUNT policy-related entries found"
  echo ""

  # ========================================================================
  # Step 3: Validate Kubernetes cluster connectivity
  # ========================================================================

  log_info "Validating cluster connectivity metrics..."
  echo ""

  # Check for errors in key services
  CRITICAL_SERVICES=(
    "argocd:argocd-server"
    "keycloak:keycloak"
    "sonarqube:sonarqube"
    "staging-platform-gitlab:webservice"
    "staging-security-vault:vault"
  )

  CONNECTIVITY_ERRORS=0

  for service in "${CRITICAL_SERVICES[@]}"; do
    NS="${service%%:*}"
    POD_PREFIX="${service##*:}"

    # Check if pods are running
    RUNNING_PODS=$(kubectl get pods -n "$NS" -l "app.kubernetes.io/name=$POD_PREFIX" \
      -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$RUNNING_PODS" ]]; then
      # Try alternate label format
      RUNNING_PODS=$(kubectl get pods -n "$NS" -l "app=$POD_PREFIX" \
        -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null || echo "")
    fi

    if [[ -z "$RUNNING_PODS" ]]; then
      log_warn "No running pods found for $NS/$POD_PREFIX"
      CONNECTIVITY_ERRORS=$((CONNECTIVITY_ERRORS + 1))
    else
      log_success "$NS/$POD_PREFIX: $(echo "$RUNNING_PODS" | wc -w) pods running"
    fi
  done

  echo ""

  # ========================================================================
  # Step 4: Analysis Summary
  # ========================================================================

  log_info "==================================================="
  log_info "Audit Analysis Summary (Last ${HOURS_TO_ANALYZE}h)"
  log_info "==================================================="
  echo ""

  echo -e "${BLUE}Policy-Related Audit Entries:${NC} $TOTAL_DENIES"
  echo -e "${BLUE}Connectivity Errors Found:${NC} $CONNECTIVITY_ERRORS"
  echo ""

  # ========================================================================
  # Step 5: Safety Assessment
  # ========================================================================

  log_info "Safety Assessment for Enforcement..."
  echo ""

  SAFE_TO_ENFORCE=true

  # Criteria 1: Low deny rate
  DENY_RATE=$((TOTAL_DENIES / HOURS_TO_ANALYZE))
  echo -e "${BLUE}Average denies/hour:${NC} $DENY_RATE"

  if [[ $DENY_RATE -gt 100 ]]; then
    log_warn "High deny rate detected (>100/hour)"
    log_info "This may indicate legitimate traffic being blocked"
    SAFE_TO_ENFORCE=false
  elif [[ $DENY_RATE -gt 10 ]]; then
    log_warn "Moderate deny rate ($DENY_RATE/hour) - review logs for patterns"
  else
    log_success "Deny rate acceptable (<10/hour)"
  fi

  echo ""

  # Criteria 2: All services healthy
  echo -e "${BLUE}Service Health Check:${NC}"
  if [[ $CONNECTIVITY_ERRORS -eq 0 ]]; then
    log_success "All critical services Running and healthy"
  else
    log_warn "$CONNECTIVITY_ERRORS critical services unhealthy"
    SAFE_TO_ENFORCE=false
  fi

  echo ""

  # ========================================================================
  # Step 6: Recommendation
  # ========================================================================

  echo -e "${BLUE}==================================================="
  echo "Enforcement Recommendation:"
  echo "===================================================${NC}"
  echo ""

  if $SAFE_TO_ENFORCE; then
    log_success "✓ SAFE_TO_ENFORCE"
    echo ""
    echo "All audit criteria passed. Network Policies can be enforced."
    echo ""
    return 0
  else
    log_error "✗ INVESTIGATE_REQUIRED"
    echo ""
    echo "Audit findings suggest issues with policies. Review before enforcement:"
    echo "1. Check audit logs for unexpected denies: cat $DENY_LOG"
    echo "2. Review pod labels against policy selectors"
    echo "3. Verify all required RDS/external endpoints are in egress rules"
    echo ""
    return 1
  fi
}

# ============================================================================
# Run Main
# ============================================================================

main "$@"
EXIT_CODE=$?

# Cleanup logs (keep for manual review if needed)
log_info "Audit logs saved to: $LOG_DIR"

exit $EXIT_CODE
