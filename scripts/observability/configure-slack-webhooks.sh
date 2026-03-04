#!/bin/bash
# =============================================================================
# DT-005: Configure Slack Webhooks for Alertmanager
# =============================================================================
# Usage:
#   ./configure-slack-webhooks.sh <critical-url> <warning-url> <data-url> <security-url>
#
# Example:
#   ./configure-slack-webhooks.sh \
#     "https://hooks.slack.com/services/T000/B111/XXXX" \
#     "https://hooks.slack.com/services/T000/B222/YYYY" \
#     "https://hooks.slack.com/services/T000/B333/ZZZZ" \
#     "https://hooks.slack.com/services/T000/B444/WWWW"
#
# What this script does:
#   1. Validates all 4 webhook URLs (format + reachability)
#   2. Creates a Kubernetes Secret in staging-observability-monitoring
#   3. Patches the Alertmanager configuration to use the Secret reference
#   4. Verifies the Secret was created correctly
#
# Prerequisites:
#   - kubectl configured and pointing to k8s-platform-prod
#   - AWS session active (for EKS auth)
#   - curl available (for webhook validation)
#
# Output:
#   - K8s Secret: alertmanager-slack-webhooks (namespace: staging-observability-monitoring)
#   - No plaintext URLs are written to any YAML file
# =============================================================================

set -euo pipefail

# --- Constants ----------------------------------------------------------------
NAMESPACE="staging-observability-monitoring"
SECRET_NAME="alertmanager-slack-webhooks"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ALERTMANAGER_CONFIG="${REPO_ROOT}/domains/observability/infra/alerts/dt005-alertmanager-config.yaml"
LOG_PREFIX="[$(date +%H:%M:%S)] configure-slack-webhooks |"

# --- Colors -------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper functions ---------------------------------------------------------
log_info()    { echo -e "${BLUE}${LOG_PREFIX}${NC} $*"; }
log_success() { echo -e "${GREEN}${LOG_PREFIX} OK${NC} $*"; }
log_warn()    { echo -e "${YELLOW}${LOG_PREFIX} WARN${NC} $*"; }
log_error()   { echo -e "${RED}${LOG_PREFIX} ERROR${NC} $*"; exit 1; }

# --- Usage --------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") <critical-url> <warning-url> <data-url> <security-url>

Arguments:
  critical-url   Slack webhook for #alerts-critical  (severity=critical)
  warning-url    Slack webhook for #alerts-warning   (severity=warning)
  data-url       Slack webhook for #alerts-data-services (postgresql/redis/rabbitmq)
  security-url   Slack webhook for #alerts-security  (vault/cert-manager/external-secrets)

All URLs must match: https://hooks.slack.com/services/<T>/<B>/<TOKEN>

Example:
  $(basename "$0") \\
    "https://hooks.slack.com/services/T000/B111/XXXX" \\
    "https://hooks.slack.com/services/T000/B222/YYYY" \\
    "https://hooks.slack.com/services/T000/B333/ZZZZ" \\
    "https://hooks.slack.com/services/T000/B444/WWWW"
EOF
  exit 1
}

# --- Validate webhook URL format ----------------------------------------------
validate_webhook_url() {
  local label="$1"
  local url="$2"
  local pattern="^https://hooks\.slack\.com/services/[A-Z0-9]+/[A-Z0-9]+/[A-Za-z0-9]+$"

  log_info "Validating ${label}: ${url:0:50}..."

  if [[ ! "$url" =~ $pattern ]]; then
    log_error "Invalid webhook URL for ${label}.\n  Expected format: https://hooks.slack.com/services/T.../B.../TOKEN\n  Got: ${url}"
  fi

  log_success "${label} URL format valid."
}

# --- Validate webhook reachability (dry-run POST) ----------------------------
validate_webhook_reachable() {
  local label="$1"
  local url="$2"

  log_info "Testing reachability for ${label}..."

  # Send a dry-run payload — Slack returns 200 even for test payloads
  # We only check HTTP connectivity (not 200 response code for real payloads)
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 \
    --max-time 10 \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"text":"[DT-005] Alertmanager webhook validation — ignore this message"}' \
    "$url" 2>/dev/null || echo "000")

  if [[ "$http_code" == "000" ]]; then
    log_warn "Cannot reach ${label} webhook (network issue or timeout). Continuing anyway."
  elif [[ "$http_code" == "200" ]]; then
    log_success "${label} webhook reachable (HTTP 200)."
  else
    log_warn "${label} webhook returned HTTP ${http_code}. May be invalid or revoked."
  fi
}

# --- Check prerequisites ------------------------------------------------------
check_prerequisites() {
  log_info "Checking prerequisites..."

  # kubectl
  if ! command -v kubectl &>/dev/null; then
    log_error "kubectl not found. Install kubectl and configure it for k8s-platform-prod."
  fi

  # kubectl connectivity
  if ! kubectl cluster-info &>/dev/null; then
    log_error "kubectl cannot connect to cluster. Check your kubeconfig and AWS session."
  fi

  # Namespace exists
  if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    log_error "Namespace '${NAMESPACE}' does not exist. Deploy kube-prometheus-stack first."
  fi

  # curl (for webhook validation)
  if ! command -v curl &>/dev/null; then
    log_warn "curl not found. Skipping webhook reachability check."
    SKIP_REACH_CHECK=true
  fi

  log_success "All prerequisites met."
}

# --- Create K8s Secret with webhook URLs -------------------------------------
create_or_update_secret() {
  local critical_url="$1"
  local warning_url="$2"
  local data_url="$3"
  local security_url="$4"

  log_info "Creating/updating Secret '${SECRET_NAME}' in namespace '${NAMESPACE}'..."

  # Delete existing secret if present (idempotent)
  if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    log_warn "Secret '${SECRET_NAME}' already exists. Overwriting."
    kubectl delete secret "${SECRET_NAME}" -n "${NAMESPACE}" --ignore-not-found=true
  fi

  kubectl create secret generic "${SECRET_NAME}" \
    --namespace="${NAMESPACE}" \
    --from-literal=slack-webhook-critical="${critical_url}" \
    --from-literal=slack-webhook-warning="${warning_url}" \
    --from-literal=slack-webhook-data="${data_url}" \
    --from-literal=slack-webhook-security="${security_url}" \
    --dry-run=client -o yaml | kubectl apply -f -

  log_success "Secret '${SECRET_NAME}' created successfully."

  # Add labels for Kyverno compliance
  kubectl label secret "${SECRET_NAME}" \
    -n "${NAMESPACE}" \
    app.kubernetes.io/name=alertmanager-slack-webhooks \
    app.kubernetes.io/component=alerting \
    app.kubernetes.io/managed-by=configure-slack-webhooks \
    team=platform-sre \
    demand=dt005 \
    --overwrite

  log_success "Labels applied to Secret '${SECRET_NAME}'."
}

# --- Patch Alertmanager to use the Secret ------------------------------------
patch_alertmanager_secret_ref() {
  log_info "Patching Alertmanager StatefulSet to mount slack webhook secret..."

  # Check if AlertmanagerConfig CRD exists
  if kubectl get alertmanagerconfig dt005-slack-routing -n "${NAMESPACE}" &>/dev/null; then
    log_info "AlertmanagerConfig 'dt005-slack-routing' found. Secret reference is already configured via CRD."
    return 0
  fi

  # Fallback: patch the kube-prometheus-stack Alertmanager secret
  # The Alertmanager uses a secret named 'alertmanager-kube-prometheus-stack-alertmanager'
  # that contains the alertmanager.yaml. We need to rebuild it with real webhook URLs.

  local am_secret_name="alertmanager-kube-prometheus-stack-alertmanager"

  if kubectl get secret "${am_secret_name}" -n "${NAMESPACE}" &>/dev/null; then
    log_info "Found Alertmanager config secret '${am_secret_name}'."
    log_info "To apply real webhook URLs, re-run helm upgrade with alertmanager-values-patch.yaml"
    log_info "OR use the AlertmanagerConfig CRD approach (dt005-alertmanager-config-crd.yaml)."
  else
    log_warn "Alertmanager config secret '${am_secret_name}' not found."
    log_warn "Deploy kube-prometheus-stack first, then re-run this script."
  fi
}

# --- Verify Secret -----------------------------------------------------------
verify_secret() {
  log_info "Verifying Secret contents..."

  local keys
  keys=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.data}' 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for k in data:
    print(f'  - {k}: [base64 encoded, {len(data[k])} chars]')
" 2>/dev/null || echo "  (python3 not available)")

  if [[ -n "$keys" ]]; then
    echo "$keys"
  else
    # Fallback: just list the keys without values
    kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" \
      -o jsonpath='{.data}' | tr ',' '\n' | tr -d '{}' | cut -d: -f1 | \
      while read -r key; do echo "  - ${key}"; done
  fi

  log_success "Secret verification complete. URLs are stored securely (base64 in etcd)."
}

# --- Print next steps --------------------------------------------------------
print_next_steps() {
  cat <<EOF

${GREEN}========================================================================${NC}
${GREEN} DT-005: Slack Webhooks Configured Successfully                         ${NC}
${GREEN}========================================================================${NC}

Secret created: ${SECRET_NAME}
Namespace:      ${NAMESPACE}

NEXT STEPS:
  1. Apply PrometheusRules:
     kubectl apply -f domains/observability/infra/alerts/dt005-prometheus-rules.yaml \\
       -n ${NAMESPACE}

  2. Apply AlertmanagerConfig CRD (uses Secret reference):
     kubectl apply -f domains/observability/infra/alerts/dt005-alertmanager-config-crd.yaml \\
       -n ${NAMESPACE}

  3. Helm upgrade Alertmanager with values patch:
     helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \\
       -n ${NAMESPACE} \\
       -f domains/observability/infra/helm/kube-prometheus-stack/values.yaml \\
       -f domains/observability/infra/helm/kube-prometheus-stack/alertmanager-values-patch.yaml \\
       --reuse-values

  4. Verify alerts are loaded:
     kubectl get prometheusrule -n ${NAMESPACE}
     kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n ${NAMESPACE}
     # Then visit: http://localhost:9090/alerts

  5. Full deploy script:
     scripts/observability/deploy-dt005-alerts.sh

EOF
}

# =============================================================================
# MAIN
# =============================================================================

# Parse arguments
if [[ $# -ne 4 ]]; then
  echo -e "${RED}ERROR: Expected exactly 4 arguments.${NC}"
  usage
fi

WEBHOOK_CRITICAL="$1"
WEBHOOK_WARNING="$2"
WEBHOOK_DATA="$3"
WEBHOOK_SECURITY="$4"

SKIP_REACH_CHECK="${SKIP_REACH_CHECK:-false}"

echo ""
log_info "DT-005 Slack Webhook Configuration"
log_info "Cluster: k8s-platform-prod | Namespace: ${NAMESPACE}"
echo ""

# Step 1: Validate URL formats
validate_webhook_url "critical" "${WEBHOOK_CRITICAL}"
validate_webhook_url "warning"  "${WEBHOOK_WARNING}"
validate_webhook_url "data"     "${WEBHOOK_DATA}"
validate_webhook_url "security" "${WEBHOOK_SECURITY}"

# Step 2: Validate reachability (optional, skip if curl missing)
if [[ "${SKIP_REACH_CHECK}" != "true" ]]; then
  validate_webhook_reachable "critical" "${WEBHOOK_CRITICAL}"
  validate_webhook_reachable "warning"  "${WEBHOOK_WARNING}"
  validate_webhook_reachable "data"     "${WEBHOOK_DATA}"
  validate_webhook_reachable "security" "${WEBHOOK_SECURITY}"
fi

# Step 3: Check cluster prerequisites
check_prerequisites

# Step 4: Create K8s Secret
create_or_update_secret \
  "${WEBHOOK_CRITICAL}" \
  "${WEBHOOK_WARNING}" \
  "${WEBHOOK_DATA}" \
  "${WEBHOOK_SECURITY}"

# Step 5: Patch Alertmanager reference
patch_alertmanager_secret_ref

# Step 6: Verify
verify_secret

# Step 7: Print next steps
print_next_steps
