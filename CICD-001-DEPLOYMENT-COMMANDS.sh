#!/bin/bash
# =============================================================================
# CICD-001: SAST/DAST Security Scanning Enforcement — DEPLOYMENT SCRIPT
# =============================================================================
#
# This script deploys all CICD-001 components when the cluster is UP.
# Run each phase sequentially and verify before proceeding to the next.
#
# Author: Platform SRE Team
# Date: 2026-02-26
# Logbook: docs/logbook/2026-02-26-cicd-001-sast-dast-deployment.md
#
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2; }

KUBE_CONTEXT="${KUBE_CONTEXT:-k8s-platform-prod}"

# =============================================================================
# PHASE 1: Pre-requisites Check
# =============================================================================
phase1_check_prerequisites() {
  log_info "PHASE 1: Checking prerequisites..."

  local all_up=true

  # Check SonarQube
  if kubectl get pods -n sonarqube --context=${KUBE_CONTEXT} 2>/dev/null | grep -q "sonarqube.*Running"; then
    log_success "SonarQube is UP"
  else
    log_error "SonarQube is DOWN or not found"
    all_up=false
  fi

  # Check Harbor
  if kubectl get pods -n harbor-system --context=${KUBE_CONTEXT} 2>/dev/null | grep -q "harbor-core.*Running"; then
    log_success "Harbor is UP"
  else
    log_error "Harbor is DOWN or not found"
    all_up=false
  fi

  # Check GitLab
  if kubectl get pods -n staging-platform-gitlab --context=${KUBE_CONTEXT} 2>/dev/null | grep -q "webservice.*Running"; then
    log_success "GitLab is UP"
  else
    log_warn "GitLab is DOWN (optional for CICD-001 deployment)"
  fi

  # Check Prometheus
  if kubectl get pods -n monitoring --context=${KUBE_CONTEXT} 2>/dev/null | grep -q "prometheus.*Running"; then
    log_success "Prometheus is UP"
  else
    log_error "Prometheus is DOWN or not found"
    all_up=false
  fi

  if [ "$all_up" = false ]; then
    log_error "Some critical services are DOWN. Cannot proceed with deployment."
    exit 1
  fi

  log_success "All prerequisites met"
  echo ""
}

# =============================================================================
# PHASE 2: Deploy PrometheusRule Alerts
# =============================================================================
phase2_deploy_prometheusrule() {
  log_info "PHASE 2: Deploying PrometheusRule alerts..."

  kubectl apply -f domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml \
    --context=${KUBE_CONTEXT}

  log_info "Waiting 5s for PrometheusRule to be created..."
  sleep 5

  if kubectl get prometheusrules -n monitoring --context=${KUBE_CONTEXT} | grep -q "cicd001-security-scan-alerts"; then
    log_success "PrometheusRule 'cicd001-security-scan-alerts' created"
  else
    log_error "PrometheusRule was not created"
    exit 1
  fi

  log_info "Check Prometheus UI for alerts: http://prometheus.staging.platform/alerts"
  echo ""
}

# =============================================================================
# PHASE 3: Configure SonarQube Quality Gate
# =============================================================================
phase3_configure_sonarqube() {
  log_info "PHASE 3: Configuring SonarQube Quality Gate..."

  # Get SonarQube admin token from Vault
  log_info "Retrieving SonarQube admin token from Vault..."
  SONAR_TOKEN=$(kubectl exec -n staging-security-vault vault-0 --context=${KUBE_CONTEXT} -- \
    vault kv get -field=token secret/sonarqube/admin 2>/dev/null || echo "")

  if [ -z "$SONAR_TOKEN" ]; then
    log_error "Failed to retrieve SonarQube token from Vault"
    log_error "Manual action required: Get token from SonarQube UI → Administration → Security → Users → Tokens"
    return 1
  fi

  log_success "SonarQube token retrieved"

  # Port-forward SonarQube
  log_info "Starting port-forward to SonarQube..."
  kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube --context=${KUBE_CONTEXT} &
  PF_PID=$!
  sleep 5

  # Configure quality gate
  cd scripts/sonarqube
  SONAR_HOST_URL="http://localhost:9000" \
  SONAR_TOKEN="${SONAR_TOKEN}" \
    ./configure-blocking.sh

  # Validate
  log_info "Validating SonarQube configuration..."
  SONAR_HOST_URL="http://localhost:9000" \
  SONAR_TOKEN="${SONAR_TOKEN}" \
    ./configure-blocking.sh --validate

  # Kill port-forward
  kill $PF_PID 2>/dev/null || true
  cd ../..

  log_success "SonarQube Quality Gate configured"
  echo ""
}

# =============================================================================
# PHASE 4: Configure Harbor Trivy Blocking
# =============================================================================
phase4_configure_harbor() {
  log_info "PHASE 4: Configuring Harbor Trivy blocking..."

  # Get Harbor admin password from Vault
  log_info "Retrieving Harbor admin password from Vault..."
  HARBOR_ADMIN_PASSWORD=$(kubectl exec -n staging-security-vault vault-0 --context=${KUBE_CONTEXT} -- \
    vault kv get -field=password secret/harbor/admin 2>/dev/null || echo "")

  if [ -z "$HARBOR_ADMIN_PASSWORD" ]; then
    log_error "Failed to retrieve Harbor password from Vault"
    log_error "Manual action required: Get password from Vault or Harbor UI"
    return 1
  fi

  log_success "Harbor password retrieved"

  # Port-forward Harbor
  log_info "Starting port-forward to Harbor..."
  kubectl port-forward svc/harbor-portal 8080:80 -n harbor-system --context=${KUBE_CONTEXT} &
  PF_PID=$!
  sleep 5

  # Configure Trivy blocking
  cd scripts/harbor
  HARBOR_REGISTRY="http://localhost:8080" \
  HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD}" \
    ./configure-trivy-blocking.sh

  # Validate
  log_info "Validating Harbor configuration..."
  HARBOR_REGISTRY="http://localhost:8080" \
  HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD}" \
    ./configure-trivy-blocking.sh --validate

  # Kill port-forward
  kill $PF_PID 2>/dev/null || true
  cd ../..

  log_success "Harbor Trivy blocking configured"
  echo ""
}

# =============================================================================
# PHASE 5: Import Grafana Dashboard
# =============================================================================
phase5_import_grafana_dashboard() {
  log_info "PHASE 5: Importing Grafana dashboard..."

  log_info "Dashboard import requires manual action via Grafana UI:"
  log_info "  1. Access: http://grafana.staging.platform"
  log_info "  2. Navigate: Dashboards → Import → Upload JSON file"
  log_info "  3. Select: $(pwd)/monitoring/grafana/dashboards/cicd-security-scan-performance.json"
  log_info "  4. Click 'Import'"
  log_info ""
  log_info "Expected UID: cicd001-security-scans"

  read -p "Press ENTER when dashboard is imported (or Ctrl+C to skip)..."

  log_success "Grafana dashboard import acknowledged"
  echo ""
}

# =============================================================================
# PHASE 6: Post-Deployment Validation
# =============================================================================
phase6_validate_deployment() {
  log_info "PHASE 6: Post-deployment validation..."

  # Check PrometheusRule
  if kubectl get prometheusrules -n monitoring --context=${KUBE_CONTEXT} | grep -q "cicd001-security-scan-alerts"; then
    log_success "PrometheusRule exists"
  else
    log_error "PrometheusRule not found"
  fi

  # Check PushGateway accessibility
  log_info "Testing PushGateway accessibility..."
  kubectl port-forward svc/prometheus-pushgateway 9091:9091 -n monitoring --context=${KUBE_CONTEXT} &
  PF_PID=$!
  sleep 3

  if curl -s http://localhost:9091/metrics >/dev/null 2>&1; then
    log_success "PushGateway is accessible"
  else
    log_warn "PushGateway not accessible (may need NetworkPolicy adjustment)"
  fi

  kill $PF_PID 2>/dev/null || true

  log_success "Validation complete"
  echo ""
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
  echo ""
  echo "======================================================================"
  echo " CICD-001: SAST/DAST Security Scanning Enforcement — DEPLOYMENT"
  echo " Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo " Context: ${KUBE_CONTEXT}"
  echo "======================================================================"
  echo ""

  phase1_check_prerequisites

  read -p "Continue with Phase 2 (PrometheusRule)? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    phase2_deploy_prometheusrule
  fi

  read -p "Continue with Phase 3 (SonarQube)? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    phase3_configure_sonarqube
  fi

  read -p "Continue with Phase 4 (Harbor)? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    phase4_configure_harbor
  fi

  read -p "Continue with Phase 5 (Grafana Dashboard)? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    phase5_import_grafana_dashboard
  fi

  read -p "Continue with Phase 6 (Validation)? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    phase6_validate_deployment
  fi

  echo ""
  echo "======================================================================"
  log_success "CICD-001 deployment complete!"
  echo "======================================================================"
  echo ""
  echo "Next steps:"
  echo "  1. Review Prometheus alerts: http://prometheus.staging.platform/alerts"
  echo "  2. Review Grafana dashboard: http://grafana.staging.platform/d/cicd001-security-scans"
  echo "  3. Onboard pilot project: Add security template to .gitlab-ci.yml"
  echo "  4. See developer guide: docs/CICD-001-DEVELOPER-GUIDE.md"
  echo "  5. See runbook: docs/runbooks/security-scan-failures-troubleshooting.md"
  echo ""
}

# Check if script is sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
