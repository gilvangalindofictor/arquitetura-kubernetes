#!/bin/bash
# =============================================================================
# provision-observability.sh — Provisionamento de Recursos de Observabilidade
# =============================================================================
# Descricao: Le observability.* do manifest.yaml e provisiona ServiceMonitor,
#            PrometheusRule e Grafana Dashboard ConfigMap conforme tier e flags.
# Uso:       ./provision-observability.sh --manifest <path> [--dry-run] [--env <env>]
# Deps:      kubectl, yq, sed
# Idempotente: SIM — usa kubectl apply
# Ref:       GAP-PLAT-OBS-04 | 2026-03-18
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/../../templates"

LOG_PREFIX="OBS"
_COMMON_SH="${SCRIPT_DIR}/../lib/common.sh"
if [[ -f "$_COMMON_SH" ]]; then
    source "$_COMMON_SH"
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
    log_info()    { echo -e "${BLUE}[${LOG_PREFIX}]${NC} $1"; }
    log_success() { echo -e "${GREEN}[${LOG_PREFIX}]${NC} $1"; }
    log_warn()    { echo -e "${YELLOW}[${LOG_PREFIX}]${NC} $1"; }
    log_error()   { echo -e "${RED}[${LOG_PREFIX}]${NC} $1" >&2; }
fi
unset _COMMON_SH

# ---- Defaults ----
MANIFEST_PATH=""
ENV="staging"
DOMAIN=""
NAMESPACE=""
APP_NAME=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --manifest)   MANIFEST_PATH="$2"; shift 2 ;;
        --env)        ENV="$2"; shift 2 ;;
        --domain)     DOMAIN="$2"; shift 2 ;;
        --namespace)  NAMESPACE="$2"; shift 2 ;;
        --app)        APP_NAME="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=true; shift ;;
        *) log_error "Opcao desconhecida: $1"; exit 1 ;;
    esac
done

if [[ -z "$MANIFEST_PATH" ]] || [[ ! -f "$MANIFEST_PATH" ]]; then
    log_error "Manifesto nao encontrado: ${MANIFEST_PATH:-<vazio>}"
    exit 1
fi

# Ler campos do manifesto via yq
APP_NAME="${APP_NAME:-$(yq '.metadata.name' "$MANIFEST_PATH")}"
DOMAIN="${DOMAIN:-$(yq '.metadata.domain' "$MANIFEST_PATH")}"
NAMESPACE="${NAMESPACE:-${ENV}-${DOMAIN}-${APP_NAME}}"

OBS_METRICS_ENABLED=$(yq '.observability.metrics.enabled // false' "$MANIFEST_PATH")
OBS_METRICS_PORT=$(yq '.observability.metrics.port // 9090' "$MANIFEST_PATH")
OBS_METRICS_PATH=$(yq '.observability.metrics.path // "/metrics"' "$MANIFEST_PATH")
OBS_SCRAPE_INTERVAL=$(yq '.observability.metrics.scrapeInterval // "30s"' "$MANIFEST_PATH")
OBS_TIER=$(yq '.observability.tier // "standard"' "$MANIFEST_PATH")
OBS_ALERTING_ENABLED=$(yq '.observability.alerting.enabled // true' "$MANIFEST_PATH")
OBS_DASHBOARD_ENABLED=$(yq '.observability.dashboard.enabled // true' "$MANIFEST_PATH")
OWNER=$(yq '.metadata.owner // "data-team"' "$MANIFEST_PATH")

log_info "App: ${APP_NAME} | Namespace: ${NAMESPACE} | Tier: ${OBS_TIER}"

# ---- apply_template: substitui placeholders e aplica ou exibe (dry-run) ----
apply_template() {
    local template_file="$1"
    local description="$2"
    shift 2
    local sed_args=("$@")

    if [[ ! -f "$template_file" ]]; then
        log_warn "Template nao encontrado: $template_file — pulando ${description}"
        return 0
    fi

    local rendered
    rendered=$(sed "${sed_args[@]}" "$template_file")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Aplicaria ${description}:"
        echo "$rendered"
    else
        echo "$rendered" | kubectl apply -f - && log_success "${description} aplicado"
    fi
}

# ---- ServiceMonitor ----
if [[ "$OBS_METRICS_ENABLED" == "true" ]]; then
    log_info "Provisionando ServiceMonitor para ${APP_NAME}..."
    apply_template "${TEMPLATES_DIR}/servicemonitor-template.yaml" "ServiceMonitor ${APP_NAME}" \
        -e "s/\${APP_NAME}/${APP_NAME}/g" \
        -e "s/\${NAMESPACE}/${NAMESPACE}/g" \
        -e "s/\${METRICS_PORT}/${OBS_METRICS_PORT}/g" \
        -e "s|\${METRICS_PATH}|${OBS_METRICS_PATH}|g" \
        -e "s/\${SCRAPE_INTERVAL}/${OBS_SCRAPE_INTERVAL}/g"
else
    log_info "Metrics desabilitado — ServiceMonitor nao criado"
fi

# ---- PrometheusRule ----
if [[ "$OBS_ALERTING_ENABLED" == "true" ]] && [[ "$OBS_METRICS_ENABLED" == "true" ]]; then
    log_info "Provisionando PrometheusRule para ${APP_NAME} (tier=${OBS_TIER})..."
    apply_template "${TEMPLATES_DIR}/prometheusrule-template.yaml" "PrometheusRule ${APP_NAME}" \
        -e "s/\${APP_NAME}/${APP_NAME}/g" \
        -e "s/\${NAMESPACE}/${NAMESPACE}/g" \
        -e "s/\${TIER}/${OBS_TIER}/g" \
        -e "s/\${TEAM}/${OWNER}/g" \
        -e "s/\${OWNER}/${OWNER}/g"
else
    log_info "Alerting desabilitado ou metrics desabilitado — PrometheusRule nao criado"
fi

# ---- Grafana Dashboard ----
if [[ "$OBS_DASHBOARD_ENABLED" == "true" ]]; then
    log_info "Provisionando Grafana Dashboard ConfigMap para ${APP_NAME}..."
    apply_template "${TEMPLATES_DIR}/grafana-dashboard-template.yaml" "GrafanaDashboard ${APP_NAME}" \
        -e "s/\${APP_NAME}/${APP_NAME}/g" \
        -e "s/\${NAMESPACE}/${NAMESPACE}/g"
else
    log_info "Dashboard desabilitado — Grafana ConfigMap nao criado"
fi

log_success "Observabilidade provisionada para ${APP_NAME} (tier=${OBS_TIER})"
