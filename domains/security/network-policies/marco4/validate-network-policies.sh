#!/bin/bash
#
# Network Policy Validation Script - Marco 4
# Tests connectivity between Marco 4 services to validate Network Policies
#
# Usage:
#   ./validate-network-policies.sh [--enforce]
#
# Options:
#   --enforce    Run tests expecting denies (for after enforcement)
#               Default: Run tests in audit mode (all should succeed)
#
# Exit codes:
#   0 = All tests passed
#   1 = One or more tests failed
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
ENFORCE_MODE=false
FAILED_TESTS=0
PASSED_TESTS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --enforce)
      ENFORCE_MODE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--enforce]"
      exit 1
      ;;
  esac
done

# Helper functions
print_header() {
  echo ""
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}============================================================${NC}"
}

print_test() {
  echo -e "${YELLOW}[TEST]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[✓ PASS]${NC} $1"
  ((PASSED_TESTS++))
}

print_fail() {
  echo -e "${RED}[✗ FAIL]${NC} $1"
  ((FAILED_TESTS++))
}

# Test connectivity from source pod to destination
# Args: namespace, deployment, target_url, expected_result (should_succeed|should_fail)
test_connectivity() {
  local namespace=$1
  local deployment=$2
  local target_url=$3
  local expected=$4
  local test_name="${namespace}/${deployment} → ${target_url}"

  print_test "$test_name"

  # Get first pod from deployment
  local pod=$(kubectl get pod -n "$namespace" -l "app.kubernetes.io/name=${deployment}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -z "$pod" ]]; then
    # Try alternate label
    pod=$(kubectl get pod -n "$namespace" -l "app=${deployment}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  fi

  if [[ -z "$pod" ]]; then
    print_fail "$test_name (pod not found)"
    return 1
  fi

  # Test connection with timeout
  if kubectl exec -n "$namespace" "$pod" -- timeout 5 sh -c "curl -s -o /dev/null -w '%{http_code}' $target_url" &>/dev/null; then
    if [[ "$expected" == "should_succeed" ]]; then
      print_success "$test_name"
      return 0
    else
      print_fail "$test_name (should have been blocked)"
      return 1
    fi
  else
    if [[ "$expected" == "should_fail" ]]; then
      print_success "$test_name (correctly blocked)"
      return 0
    else
      print_fail "$test_name (connection failed)"
      return 1
    fi
  fi
}

# Main test suite
main() {
  print_header "Network Policy Validation - Marco 4"
  echo "Mode: $(if $ENFORCE_MODE; then echo 'Enforcement'; else echo 'Audit'; fi)"
  echo "Date: $(date)"

  # ArgoCD Tests
  print_header "ArgoCD Connectivity Tests"

  print_test "Testing ArgoCD → Keycloak (OIDC)"
  test_connectivity "argocd" "argocd-server" "http://keycloak.keycloak.svc.cluster.local:8080/auth/realms/master" "should_succeed"

  print_test "Testing ArgoCD → PostgreSQL RDS"
  # Note: This tests egress to VPC CIDR, not actual RDS endpoint (need psql)
  echo -e "${YELLOW}[SKIP]${NC} RDS connectivity requires database client (manual test)"

  print_test "Testing ArgoCD Repo Server → Git (external)"
  test_connectivity "argocd" "argocd-repo-server" "https://github.com" "should_succeed"

  # SonarQube Tests
  print_header "SonarQube Connectivity Tests"

  print_test "Testing SonarQube → Keycloak (SAML)"
  test_connectivity "sonarqube" "sonarqube" "http://keycloak.keycloak.svc.cluster.local:8080/auth/realms/master" "should_succeed"

  print_test "Testing GitLab → SonarQube (code quality)"
  # Test from GitLab runner (if available)
  local gitlab_runner_pod=$(kubectl get pod -n gitlab-staging -l "app=gitlab-runner" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$gitlab_runner_pod" ]]; then
    kubectl exec -n gitlab-staging "$gitlab_runner_pod" -- timeout 5 curl -s -o /dev/null -w '%{http_code}' http://sonarqube.sonarqube.svc.cluster.local:9000 &>/dev/null && \
      print_success "GitLab Runner → SonarQube" || \
      print_fail "GitLab Runner → SonarQube"
  else
    echo -e "${YELLOW}[SKIP]${NC} GitLab runner not found"
  fi

  # Keycloak Tests
  print_header "Keycloak Connectivity Tests"

  print_test "Testing Grafana → Keycloak (OIDC)"
  local grafana_pod=$(kubectl get pod -n monitoring -l "app.kubernetes.io/name=grafana" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$grafana_pod" ]]; then
    kubectl exec -n monitoring "$grafana_pod" -- timeout 5 curl -s -o /dev/null -w '%{http_code}' http://keycloak.keycloak.svc.cluster.local:8080/auth/realms/master &>/dev/null && \
      print_success "Grafana → Keycloak" || \
      print_fail "Grafana → Keycloak"
  else
    echo -e "${YELLOW}[SKIP]${NC} Grafana not found"
  fi

  print_test "Testing Harbor → Keycloak (OIDC)"
  local harbor_pod=$(kubectl get pod -n harbor-system -l "app=harbor,component=core" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$harbor_pod" ]]; then
    kubectl exec -n harbor-system "$harbor_pod" -- timeout 5 curl -s -o /dev/null -w '%{http_code}' http://keycloak.keycloak.svc.cluster.local:8080/auth/realms/master &>/dev/null && \
      print_success "Harbor → Keycloak" || \
      print_fail "Harbor → Keycloak"
  else
    echo -e "${YELLOW}[SKIP]${NC} Harbor not found"
  fi

  # GitLab Tests
  print_header "GitLab Connectivity Tests"

  print_test "Testing GitLab Webservice → Redis"
  local gitlab_webservice_pod=$(kubectl get pod -n gitlab-staging -l "app=webservice" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$gitlab_webservice_pod" ]]; then
    # Test Redis connection (port 6379)
    kubectl exec -n gitlab-staging "$gitlab_webservice_pod" -- timeout 5 sh -c "echo PING | nc redis.data-services.svc.cluster.local 6379" &>/dev/null && \
      print_success "GitLab Webservice → Redis" || \
      print_fail "GitLab Webservice → Redis"
  else
    echo -e "${YELLOW}[SKIP]${NC} GitLab webservice not found"
  fi

  print_test "Testing GitLab Webservice → Gitaly"
  if [[ -n "$gitlab_webservice_pod" ]]; then
    kubectl exec -n gitlab-staging "$gitlab_webservice_pod" -- timeout 5 curl -s -o /dev/null -w '%{http_code}' http://gitlab-gitaly.gitlab-staging.svc.cluster.local:8075 &>/dev/null && \
      print_success "GitLab Webservice → Gitaly" || \
      print_fail "GitLab Webservice → Gitaly"
  else
    echo -e "${YELLOW}[SKIP]${NC} GitLab webservice not found"
  fi

  print_test "Testing GitLab Sidekiq → Gitaly"
  local gitlab_sidekiq_pod=$(kubectl get pod -n gitlab-staging -l "app=sidekiq" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$gitlab_sidekiq_pod" ]]; then
    kubectl exec -n gitlab-staging "$gitlab_sidekiq_pod" -- timeout 5 curl -s -o /dev/null -w '%{http_code}' http://gitlab-gitaly.gitlab-staging.svc.cluster.local:8075 &>/dev/null && \
      print_success "GitLab Sidekiq → Gitaly" || \
      print_fail "GitLab Sidekiq → Gitaly"
  else
    echo -e "${YELLOW}[SKIP]${NC} GitLab sidekiq not found"
  fi

  # Negative tests (should fail if policies are enforced)
  if $ENFORCE_MODE; then
    print_header "Negative Tests (Should be Blocked)"

    print_test "Testing default namespace → ArgoCD (should fail)"
    kubectl run test-curl-pod --rm -i --restart=Never --image=curlimages/curl -n default -- timeout 5 curl -s http://argocd-server.argocd.svc.cluster.local:8080 &>/dev/null && \
      print_fail "default → ArgoCD (should have been blocked)" || \
      print_success "default → ArgoCD (correctly blocked)"

    print_test "Testing default namespace → Keycloak (should fail)"
    kubectl run test-curl-pod --rm -i --restart=Never --image=curlimages/curl -n default -- timeout 5 curl -s http://keycloak.keycloak.svc.cluster.local:8080 &>/dev/null && \
      print_fail "default → Keycloak (should have been blocked)" || \
      print_success "default → Keycloak (correctly blocked)"

    print_test "Testing default namespace → SonarQube (should fail)"
    kubectl run test-curl-pod --rm -i --restart=Never --image=curlimages/curl -n default -- timeout 5 curl -s http://sonarqube.sonarqube.svc.cluster.local:9000 &>/dev/null && \
      print_fail "default → SonarQube (should have been blocked)" || \
      print_success "default → SonarQube (correctly blocked)"

    print_test "Testing default namespace → GitLab (should fail)"
    kubectl run test-curl-pod --rm -i --restart=Never --image=curlimages/curl -n default -- timeout 5 curl -s http://gitlab-webservice.gitlab-staging.svc.cluster.local:8181 &>/dev/null && \
      print_fail "default → GitLab (should have been blocked)" || \
      print_success "default → GitLab (correctly blocked)"
  fi

  # Summary
  print_header "Test Summary"
  echo -e "Passed: ${GREEN}${PASSED_TESTS}${NC}"
  echo -e "Failed: ${RED}${FAILED_TESTS}${NC}"
  echo -e "Total:  $((PASSED_TESTS + FAILED_TESTS))"

  if [[ $FAILED_TESTS -gt 0 ]]; then
    echo ""
    echo -e "${RED}Some tests failed. Review policies and pod connectivity.${NC}"
    exit 1
  else
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  fi
}

# Check prerequisites
if ! command -v kubectl &>/dev/null; then
  echo -e "${RED}Error: kubectl not found${NC}"
  exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
  exit 1
fi

# Run main test suite
main
