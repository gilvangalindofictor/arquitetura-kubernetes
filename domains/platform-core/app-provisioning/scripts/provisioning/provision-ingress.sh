#!/bin/bash
# =============================================================================
# provision-ingress.sh — Provisionamento de Ingress (AWS ALB)
# =============================================================================
# Descricao: Le config.ingress.* do manifest.yaml e provisiona Ingress resource
#            com anotacoes corretas do AWS ALB Controller conforme IngressGroup.
# Uso:       ./provision-ingress.sh --manifest <path> [--dry-run] [--env <env>]
# Deps:      kubectl, yq, sed
# Idempotente: SIM — usa kubectl apply
# Ref:       GAP-PLAT-ING-04 | 2026-03-18
# Seguranca: scheme sempre internal para hosts *.internal. data-public requer
#            costTier=dedicated ou aprovacao explícita via pipeline.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/../../templates"

LOG_PREFIX="ING"
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

# Ler campos do manifesto
APP_NAME="${APP_NAME:-$(yq '.metadata.name' "$MANIFEST_PATH")}"
DOMAIN="${DOMAIN:-$(yq '.metadata.domain' "$MANIFEST_PATH")}"
NAMESPACE="${NAMESPACE:-${ENV}-${DOMAIN}-${APP_NAME}}"

ING_ENABLED=$(yq '.config.ingress.enabled // false' "$MANIFEST_PATH")

if [[ "$ING_ENABLED" != "true" ]]; then
    log_info "Ingress desabilitado no manifesto — nenhum recurso criado"
    exit 0
fi

ING_HOST=$(yq '.config.ingress.host // ""' "$MANIFEST_PATH")
ING_CLASS=$(yq '.config.ingress.class // "internal"' "$MANIFEST_PATH")
ING_GROUP=$(yq '.config.ingress.ingressGroup // "data-internal"' "$MANIFEST_PATH")
ING_COST_TIER=$(yq '.config.ingress.costTier // "shared"' "$MANIFEST_PATH")
ING_PORT=$(yq '.config.port // 8000' "$MANIFEST_PATH")
ING_PATH_PREFIX=$(yq '.config.ingress.pathPrefix // "/"' "$MANIFEST_PATH")
ING_HEALTH_PATH=$(yq '.config.ingress.healthCheckPath // .config.healthCheck.liveness // "/health"' "$MANIFEST_PATH")

# Default host se nao definido
if [[ -z "$ING_HOST" ]] || [[ "$ING_HOST" == "null" ]]; then
    ING_HOST="${APP_NAME}.${ENV}.internal"
fi

# Default path prefix
if [[ -z "$ING_PATH_PREFIX" ]] || [[ "$ING_PATH_PREFIX" == "null" ]]; then
    ING_PATH_PREFIX="/"
fi

log_info "App: ${APP_NAME} | Host: ${ING_HOST} | Group: ${ING_GROUP} | CostTier: ${ING_COST_TIER}"

# ---- Validacao de seguranca ----
# Hosts *.internal NUNCA devem usar data-public (internet-facing)
if [[ "$ING_HOST" == *".internal" ]] && [[ "$ING_GROUP" == "data-public" ]]; then
    log_error "SEGURANCA: Host '${ING_HOST}' e interno (*.internal) mas ingressGroup='data-public' (internet-facing)."
    log_error "Use ingressGroup='data-internal' para hosts internos."
    exit 1
fi

# data-public requer costTier=dedicated ou aviso explicito
if [[ "$ING_GROUP" == "data-public" ]] && [[ "$ING_COST_TIER" != "dedicated" ]]; then
    log_warn "AVISO: ingressGroup='data-public' com costTier='${ING_COST_TIER}'. Requer aprovacao no pipeline."
fi

# ---- Aplicar template ----
TEMPLATE_FILE="${TEMPLATES_DIR}/ingress-template.yaml"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_error "Template nao encontrado: $TEMPLATE_FILE"
    exit 1
fi

RENDERED=$(sed \
    -e "s/\${APP_NAME}/${APP_NAME}/g" \
    -e "s/\${NAMESPACE}/${NAMESPACE}/g" \
    -e "s/\${HOST}/${ING_HOST}/g" \
    -e "s/\${INGRESS_GROUP}/${ING_GROUP}/g" \
    -e "s|\${PORT}|${ING_PORT}|g" \
    "$TEMPLATE_FILE")

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Aplicaria Ingress ${APP_NAME}:"
    echo "$RENDERED"
else
    echo "$RENDERED" | kubectl apply -f - && log_success "Ingress ${APP_NAME} aplicado"
fi

log_success "Ingress provisionado: ${ING_HOST} → ${APP_NAME}:${ING_PORT} via ${ING_GROUP}"
