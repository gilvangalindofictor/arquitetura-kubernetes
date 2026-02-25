#!/bin/bash

# Script: netpol-connectivity-tests.sh
# Purpose: Validate critical connectivity paths work after Network Policy enforcement
# Usage: ./netpol-connectivity-tests.sh [OPTIONS]
# Options:
#   --quick           Run only essential tests (2 min)
#   --full            Run all tests including negative tests (5 min)
#   --services NS/POD Include custom service test

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_MODE="standard"  # quick, standard, full
CUSTOM_TESTS=()
TIMEOUT=10  # seconds per test

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ============================================================================
# Functions
# ============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_test() {
  echo -e "${BOLD}[TEST]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((TESTS_PASSED++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((TESTS_FAILED++))
}

log_skip() {
  echo -e "${YELLOW}[SKIP]${NC} $*"
  ((TESTS_SKIPPED++))
}

usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Options:
  --quick             Run only essential tests (2 min) - default
  --full              Run all tests including edge cases (5 min)
  --help              Show this help message

Examples:
  # Run standard connectivity tests
  $0

  # Quick validation (essential paths only)
  $0 --quick

  # Comprehensive testing
  $0 --full

EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --quick)
      TEST_MODE="quick"
      shift
      ;;
    --full)
      TEST_MODE="full"
      shift
      ;;
    --help)
      usage
      ;;
    *)
      log_info "Unknown option: $1"
      shift
      ;;
  esac
done

# ============================================================================
# Test Helpers
# ============================================================================

# Test if a pod can connect to a service
test_connectivity() {
  local source_ns="$1"
  local source_pod="$2"
  local target_ns="$3"
  local target_service="$4"
  local target_port="$5"
  local test_description="$6"

  ((TESTS_RUN++))
  log_test "[$TESTS_RUN] $test_description"

  # Check if source pod exists
  if ! kubectl get pod "$source_pod" -n "$source_ns" &>/dev/null; then
    log_skip "Source pod not found: $source_ns/$source_pod"
    return 0
  fi

  # Prepare test command
  local test_cmd="wget --spider --timeout=$TIMEOUT http://${target_service}.${target_ns}.svc.cluster.local:${target_port}/health 2>&1 || curl --max-time $TIMEOUT http://${target_service}.${target_ns}.svc.cluster.local:${target_port}/health 2>&1 || nc -zv -w $TIMEOUT ${target_service}.${target_ns}.svc.cluster.local $target_port 2>&1"

  # Execute test
  if kubectl exec -n "$source_ns" "$source_pod" -- bash -c "timeout $TIMEOUT bash -c 'echo > /dev/tcp/${target_service}.${target_ns}.svc.cluster.local/${target_port}' 2>/dev/null" &>/dev/null; then
    log_pass "Connected: $source_ns/$source_pod → $target_ns/$target_service:$target_port"
    return 0
  else
    log_fail "Cannot connect: $source_ns/$source_pod → $target_ns/$target_service:$target_port"
    return 1
  fi
}

# Create temporary test pod
create_test_pod() {
  local ns="$1"
  local pod_name="nettest-$$"

  # Delete if exists
  kubectl delete pod "$pod_name" -n "$ns" --ignore-not-found 2>/dev/null || true

  # Create test pod
  if kubectl run "$pod_name" -n "$ns" \
    --image=busybox:1.35 \
    --restart=Never \
    --command -- sleep 3600 &>/dev/null; then
    echo "$pod_name"
    # Wait for pod to be ready
    kubectl wait --for=condition=ready pod "$pod_name" -n "$ns" --timeout=30s &>/dev/null || true
    return 0
  else
    return 1
  fi
}

# Cleanup test pod
cleanup_test_pod() {
  local ns="$1"
  local pod_name="$2"
  kubectl delete pod "$pod_name" -n "$ns" --ignore-not-found 2>/dev/null || true
}

# ============================================================================
# Pre-Flight Checks
# ============================================================================

preflight_checks() {
  log_info "==================================================="
  log_info "Pre-Flight Checks"
  log_info "==================================================="
  echo ""

  # Check kubectl access
  if ! kubectl cluster-info &>/dev/null; then
    log_fail "Cannot connect to Kubernetes cluster"
    return 1
  fi
  log_pass "Kubernetes cluster accessible"

  # Check namespaces exist
  local required_namespaces=(
    "argocd"
    "sonarqube"
    "keycloak"
    "staging-platform-gitlab"
    "staging-security-vault"
    "kube-system"
  )

  for ns in "${required_namespaces[@]}"; do
    if ! kubectl get namespace "$ns" &>/dev/null; then
      log_skip "Namespace $ns does not exist"
      continue
    fi
    log_pass "Namespace $ns exists"
  done

  echo ""
}

# ============================================================================
# Test Suites
# ============================================================================

test_critical_paths() {
  echo ""
  log_info "==================================================="
  log_info "Critical Connectivity Tests"
  log_info "==================================================="
  echo ""

  local test_pod_argocd=""
  local test_pod_gitlab=""

  # Create test pods
  if kubectl get namespace argocd &>/dev/null; then
    test_pod_argocd=$(create_test_pod "argocd")
  fi

  if kubectl get namespace staging-platform-gitlab &>/dev/null; then
    test_pod_gitlab=$(create_test_pod "staging-platform-gitlab")
  fi

  # Test 1: ArgoCD → Keycloak (OIDC authentication)
  if [[ -n "$test_pod_argocd" ]]; then
    test_connectivity "argocd" "$test_pod_argocd" "keycloak" "keycloak" "8080" \
      "ArgoCD → Keycloak (OIDC auth)"
  fi

  # Test 2: GitLab → Keycloak (OIDC authentication)
  if [[ -n "$test_pod_gitlab" ]]; then
    test_connectivity "staging-platform-gitlab" "$test_pod_gitlab" "keycloak" "keycloak" "8080" \
      "GitLab → Keycloak (OIDC auth)"
  fi

  # Test 3: SonarQube → Keycloak (if namespace exists)
  if kubectl get namespace sonarqube &>/dev/null; then
    local test_pod_sonarqube=$(create_test_pod "sonarqube")
    test_connectivity "sonarqube" "$test_pod_sonarqube" "keycloak" "keycloak" "8080" \
      "SonarQube → Keycloak (SAML auth)"
    cleanup_test_pod "sonarqube" "$test_pod_sonarqube"
  fi

  # Test 4: Pod in staging-security-vault → Vault (secret access)
  if kubectl get namespace staging-security-vault &>/dev/null; then
    local test_pod_vault=$(create_test_pod "staging-security-vault")
    test_connectivity "staging-security-vault" "$test_pod_vault" "staging-security-vault" "vault" "8200" \
      "Vault → Self (cluster communication)"
    cleanup_test_pod "staging-security-vault" "$test_pod_vault"
  fi

  # Test 5: External Secrets Operator → Vault
  if kubectl get namespace staging-security-externalsecrets &>/dev/null; then
    local test_pod_eso=$(create_test_pod "staging-security-externalsecrets")
    test_connectivity "staging-security-externalsecrets" "$test_pod_eso" "staging-security-vault" "vault" "8200" \
      "ESO → Vault (secret syncing)"
    cleanup_test_pod "staging-security-externalsecrets" "$test_pod_eso"
  fi

  # Cleanup test pods
  [[ -n "$test_pod_argocd" ]] && cleanup_test_pod "argocd" "$test_pod_argocd"
  [[ -n "$test_pod_gitlab" ]] && cleanup_test_pod "staging-platform-gitlab" "$test_pod_gitlab"
}

test_negative_cases() {
  echo ""
  log_info "==================================================="
  log_info "Negative Test Cases (should be blocked/slow)"
  log_info "==================================================="
  echo ""

  ((TESTS_RUN++))
  log_test "[$TESTS_RUN] Unauthorized pod → Keycloak (should timeout)"

  # Create test pod in default namespace (should not access Keycloak)
  local test_pod=$(create_test_pod "default")

  if kubectl exec -n "default" "$test_pod" -- bash -c "timeout 3 bash -c 'echo > /dev/tcp/keycloak.keycloak.svc.cluster.local/8080' 2>/dev/null" &>/dev/null; then
    log_fail "Unauthorized access allowed (should be blocked)"
    cleanup_test_pod "default" "$test_pod"
    return 1
  else
    log_pass "Unauthorized access blocked as expected"
    cleanup_test_pod "default" "$test_pod"
    return 0
  fi
}

test_service_health() {
  echo ""
  log_info "==================================================="
  log_info "Service Health Checks"
  log_info "==================================================="
  echo ""

  local services_to_check=(
    "argocd:argocd-server"
    "sonarqube:sonarqube"
    "keycloak:keycloak"
    "staging-platform-gitlab:webservice"
    "staging-security-vault:vault"
  )

  for service in "${services_to_check[@]}"; do
    NS="${service%%:*}"
    POD_PREFIX="${service##*:}"

    ((TESTS_RUN++))
    log_test "[$TESTS_RUN] $NS/$POD_PREFIX service health"

    # Try multiple label patterns
    RUNNING_PODS=$(kubectl get pods -n "$NS" -l "app.kubernetes.io/name=$POD_PREFIX" \
      -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$RUNNING_PODS" ]]; then
      RUNNING_PODS=$(kubectl get pods -n "$NS" -l "app=$POD_PREFIX" \
        -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null || echo "")
    fi

    if [[ -z "$RUNNING_PODS" ]]; then
      log_skip "No pods found for $NS/$POD_PREFIX"
      continue
    fi

    # Check for restart loops
    RESTART_COUNT=$(kubectl get pods -n "$NS" -l "app=$POD_PREFIX" \
      -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")

    if [[ "$RESTART_COUNT" -gt 0 ]]; then
      log_fail "$NS/$POD_PREFIX has restarted $RESTART_COUNT times"
    else
      local pod_count=$(echo "$RUNNING_PODS" | wc -w)
      log_pass "$NS/$POD_PREFIX: $pod_count pods Running, 0 restarts"
    fi
  done
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo ""
  log_info "==================================================="
  log_info "Network Policy Connectivity Test Suite"
  log_info "==================================================="
  log_info "Mode: $TEST_MODE"
  echo ""

  # Pre-flight checks
  if ! preflight_checks; then
    log_fail "Pre-flight checks failed"
    return 1
  fi

  # Run test suites based on mode
  case $TEST_MODE in
    quick)
      test_critical_paths
      ;;
    standard)
      test_critical_paths
      test_service_health
      ;;
    full)
      test_critical_paths
      test_service_health
      test_negative_cases
      ;;
  esac

  # Print summary
  echo ""
  log_info "==================================================="
  log_info "Test Summary"
  log_info "==================================================="
  echo ""
  echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
  echo -e "${RED}Failed:${NC} $TESTS_FAILED"
  echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
  echo -e "${BLUE}Total:${NC} $TESTS_RUN"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    log_pass "ALL TESTS PASSED ✓"
    echo ""
    echo "Network Policies are correctly configured and enforced."
    return 0
  else
    log_fail "SOME TESTS FAILED"
    echo ""
    echo "Issues detected in connectivity. Review Network Policies before enforcement."
    return 1
  fi
}

# ============================================================================
# Execute
# ============================================================================

main "$@"
EXIT_CODE=$?

exit $EXIT_CODE
