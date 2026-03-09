#!/bin/bash
# =============================================================================
# DT-005: Deploy Alertas PrometheusRule + AlertmanagerConfig
# =============================================================================
# Cluster:   k8s-platform-prod (EKS 1.34, us-east-1)
# Namespace: staging-observability-monitoring
# Maintainer: Platform SRE Team
# Last Updated: 2026-03-04
#
# Prerequisites:
#   - kubectl configured and pointing to k8s-platform-prod
#   - AWS session active (EKS auth)
#   - Teams webhooks configured via configure-teams-webhooks.sh
#   - kube-prometheus-stack already deployed
#
# What this script does:
#   1. Validates cluster connectivity and prerequisites
#   2. Applies dt005-prometheus-rules.yaml (37 alerts, 4 groups)
#   3. Applies dt005-alertmanager-config-crd.yaml (AlertmanagerConfig CRD)
#   4. Verifies PrometheusRules are loaded (via port-forward to Prometheus)
#   5. Verifies Alertmanager is picking up the new configuration
#   6. Prints a validation summary
#
# Usage:
#   ./deploy-dt005-alerts.sh [--dry-run] [--skip-verify]
#
# Flags:
#   --dry-run      Show what would be applied, but don't apply
#   --skip-verify  Skip the Prometheus port-forward verification step
# =============================================================================

set -euo pipefail

# --- Constants ----------------------------------------------------------------
NAMESPACE="staging-observability-monitoring"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ALERTS_DIR="${REPO_ROOT}/domains/observability/infra/alerts"
HELM_DIR="${REPO_ROOT}/domains/observability/infra/helm/kube-prometheus-stack"

DRY_RUN=false
SKIP_VERIFY=false

# --- Colors -------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Parse arguments ----------------------------------------------------------
for arg in "$@"; do
  case $arg in
    --dry-run)     DRY_RUN=true ;;
    --skip-verify) SKIP_VERIFY=true ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--dry-run] [--skip-verify]"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown argument: ${arg}${NC}"
      exit 1
      ;;
  esac
done

# --- Helper functions ---------------------------------------------------------
ts()          { date +%H:%M:%S; }
log_info()    { echo -e "[$(ts)] ${BLUE}INFO${NC}  $*"; }
log_success() { echo -e "[$(ts)] ${GREEN}OK${NC}    $*"; }
log_warn()    { echo -e "[$(ts)] ${YELLOW}WARN${NC}  $*"; }
log_error()   { echo -e "[$(ts)] ${RED}ERROR${NC} $*"; exit 1; }
log_step()    { echo -e "\n[$(ts)] ${CYAN}====== $* ======${NC}"; }

kubectl_apply() {
  local file="$1"
  local resource_name
  resource_name="$(basename "$file")"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY RUN] Would apply: ${resource_name}"
    kubectl apply -f "$file" -n "${NAMESPACE}" --dry-run=client
  else
    kubectl apply -f "$file" -n "${NAMESPACE}"
  fi
}

# =============================================================================
# STEP 0: Banner
# =============================================================================
echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN} DT-005: Alertas Deploy — k8s-platform-prod                    ${NC}"
echo -e "${CYAN} Namespace: ${NAMESPACE}${NC}"
if [[ "${DRY_RUN}" == "true" ]]; then
  echo -e "${YELLOW} MODE: DRY RUN (nothing will be applied)${NC}"
fi
echo -e "${CYAN}================================================================${NC}"
echo ""

# =============================================================================
# STEP 1: Validate prerequisites
# =============================================================================
log_step "STEP 1: Validating prerequisites"

# kubectl
if ! command -v kubectl &>/dev/null; then
  log_error "kubectl not found. Install kubectl and configure for k8s-platform-prod."
fi
log_success "kubectl found: $(kubectl version --client --short 2>/dev/null | head -1)"

# Cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
  log_error "kubectl cannot reach cluster. Check kubeconfig and AWS session (aws sso login)."
fi
CLUSTER=$(kubectl config current-context)
log_success "Cluster connected: ${CLUSTER}"

# Namespace
if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  log_error "Namespace '${NAMESPACE}' not found. Deploy kube-prometheus-stack first."
fi
log_success "Namespace '${NAMESPACE}' exists."

# kube-prometheus-stack
if ! kubectl get deployment kube-prometheus-stack-operator -n "${NAMESPACE}" &>/dev/null; then
  log_warn "kube-prometheus-stack-operator not found in ${NAMESPACE}. Prometheus Operator may not be installed."
else
  log_success "kube-prometheus-stack-operator running."
fi

# Check Teams webhooks Secret
if kubectl get secret alertmanager-teams-webhooks -n "${NAMESPACE}" &>/dev/null; then
  log_success "Secret 'alertmanager-teams-webhooks' found. Webhooks configured."
else
  log_warn "Secret 'alertmanager-teams-webhooks' NOT found."
  log_warn "Run: scripts/observability/configure-teams-webhooks.sh <critical> <warning> <data> <security>"
  log_warn "Continuing deploy — alerting will work but Teams notifications will not fire."
fi

# Check alert files exist
for f in \
  "${ALERTS_DIR}/dt005-prometheus-rules.yaml" \
  "${ALERTS_DIR}/dt005-alertmanager-config-crd.yaml"; do
  if [[ ! -f "$f" ]]; then
    log_error "Required file not found: ${f}"
  fi
done
log_success "All required alert files present."

# =============================================================================
# STEP 2: Apply PrometheusRules
# =============================================================================
log_step "STEP 2: Applying PrometheusRules (37 alerts, 4 groups)"

kubectl_apply "${ALERTS_DIR}/dt005-prometheus-rules.yaml"

if [[ "${DRY_RUN}" == "false" ]]; then
  log_success "PrometheusRules applied."

  # Verify rule was created
  if kubectl get prometheusrule dt005-platform-alerts -n "${NAMESPACE}" &>/dev/null; then
    log_success "PrometheusRule 'dt005-platform-alerts' confirmed in cluster."
  else
    log_warn "PrometheusRule not found yet (may take a few seconds to register)."
  fi
fi

# =============================================================================
# STEP 3: Apply AlertmanagerConfig CRD
# =============================================================================
log_step "STEP 3: Applying AlertmanagerConfig CRD (dt005-teams-routing)"

kubectl_apply "${ALERTS_DIR}/dt005-alertmanager-config-crd.yaml"

if [[ "${DRY_RUN}" == "false" ]]; then
  log_success "AlertmanagerConfig applied."

  if kubectl get alertmanagerconfig dt005-teams-routing -n "${NAMESPACE}" &>/dev/null; then
    log_success "AlertmanagerConfig 'dt005-teams-routing' confirmed in cluster."
  else
    log_warn "AlertmanagerConfig not found yet. Alertmanager Operator may take a few seconds."
  fi
fi

# =============================================================================
# STEP 4: Show current PrometheusRules
# =============================================================================
log_step "STEP 4: PrometheusRules in namespace"

echo ""
kubectl get prometheusrule -n "${NAMESPACE}" 2>/dev/null || \
  log_warn "Could not list PrometheusRules."

# =============================================================================
# STEP 5: Verify alerts loaded in Prometheus (via port-forward)
# =============================================================================
if [[ "${SKIP_VERIFY}" == "true" ]]; then
  log_warn "STEP 5: Skipped (--skip-verify flag set)."
else
  log_step "STEP 5: Verifying alerts loaded in Prometheus"

  PROM_SVC="kube-prometheus-stack-prometheus"
  PROM_PORT=9090

  log_info "Starting port-forward to Prometheus (${PROM_SVC}:${PROM_PORT})..."
  kubectl port-forward "svc/${PROM_SVC}" "${PROM_PORT}:${PROM_PORT}" \
    -n "${NAMESPACE}" &>/dev/null &
  PF_PID=$!

  # Wait for port-forward to be ready
  sleep 4

  if kill -0 "${PF_PID}" 2>/dev/null; then
    log_info "Port-forward active (PID ${PF_PID}). Querying /api/v1/rules..."

    # Query rules API and filter for dt005 groups
    DT005_RULES=$(curl -s --connect-timeout 5 \
      "http://localhost:${PROM_PORT}/api/v1/rules" 2>/dev/null | \
      python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    groups = data.get('data', {}).get('groups', [])
    dt005_groups = [g for g in groups if 'dt005' in g.get('name','')]
    print(f'DT-005 groups loaded: {len(dt005_groups)}')
    total_rules = sum(len(g.get('rules',[])) for g in dt005_groups)
    print(f'Total rules: {total_rules}')
    for g in dt005_groups:
        print(f'  - {g[\"name\"]}: {len(g[\"rules\"])} rules')
except Exception as e:
    print(f'Parse error: {e}')
" 2>/dev/null || echo "  (python3 parse failed — check manually at http://localhost:${PROM_PORT}/alerts)")

    echo "${DT005_RULES}"

    # Terminate port-forward
    kill "${PF_PID}" 2>/dev/null || true
    log_success "Port-forward terminated."
  else
    log_warn "Port-forward failed. Verify manually:"
    log_warn "  kubectl port-forward svc/${PROM_SVC} ${PROM_PORT}:${PROM_PORT} -n ${NAMESPACE}"
    log_warn "  Then visit: http://localhost:${PROM_PORT}/alerts"
  fi
fi

# =============================================================================
# STEP 6: Verify Alertmanager config status
# =============================================================================
log_step "STEP 6: Alertmanager config status"

echo ""
kubectl get alertmanagerconfig -n "${NAMESPACE}" 2>/dev/null || \
  log_warn "AlertmanagerConfig CRD not installed. Using values.yaml config instead."

# Check Alertmanager pods
echo ""
log_info "Alertmanager pods:"
kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=alertmanager" 2>/dev/null || \
  kubectl get pods -n "${NAMESPACE}" | grep alertmanager || \
  log_warn "No alertmanager pods found."

# =============================================================================
# STEP 7: Summary
# =============================================================================
log_step "STEP 7: Deploy Summary"

if [[ "${DRY_RUN}" == "true" ]]; then
  echo ""
  echo -e "${YELLOW}  DRY RUN COMPLETE — no changes applied.${NC}"
  echo -e "${YELLOW}  Re-run without --dry-run to apply.${NC}"
else
  echo ""
  echo -e "${GREEN}================================================================${NC}"
  echo -e "${GREEN} DT-005 Deploy | COMPLETE                                      ${NC}"
  echo -e "${GREEN}================================================================${NC}"
  echo ""
  echo "  PrometheusRules:    dt005-platform-alerts (37 alerts, 4 groups)"
  echo "  AlertmanagerConfig: dt005-teams-routing   (4 Teams receivers)"
  echo "  Namespace:          ${NAMESPACE}"
  echo ""
  echo -e "${CYAN}VALIDATION COMMANDS:${NC}"
  echo "  # List all PrometheusRules"
  echo "  kubectl get prometheusrule -n ${NAMESPACE}"
  echo ""
  echo "  # Check Prometheus alerts UI"
  echo "  kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n ${NAMESPACE}"
  echo "  # http://localhost:9090/alerts"
  echo ""
  echo "  # Check Alertmanager UI"
  echo "  kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n ${NAMESPACE}"
  echo "  # http://localhost:9093"
  echo ""
  echo "  # Check Alertmanager config is loaded"
  echo "  kubectl get alertmanagerconfig -n ${NAMESPACE}"
  echo ""
  echo -e "${CYAN}IF TEAMS WEBHOOKS NOT YET CONFIGURED:${NC}"
  echo "  scripts/observability/configure-teams-webhooks.sh \\"
  echo "    <critical-url> <warning-url> <data-url> <security-url>"
  echo ""
  echo -e "${CYAN}HELM UPGRADE (if needed):${NC}"
  echo "  helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \\"
  echo "    -n ${NAMESPACE} \\"
  echo "    -f ${HELM_DIR}/values.yaml \\"
  echo "    -f ${HELM_DIR}/alertmanager-values-patch.yaml \\"
  echo "    --reuse-values"
  echo ""
fi

log_info "DT-005 Deploy | Fim"
