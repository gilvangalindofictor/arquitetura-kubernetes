#!/bin/bash
# =============================================================================
# provision-ingress.sh -- Provisionamento de Ingress (AWS ALB)
# =============================================================================
# Descricao: Le config.ingress.* do manifest.yaml e provisiona Ingress resource
#            com anotacoes corretas do AWS ALB Controller conforme IngressGroup.
#            Gera host interno (*.{env}.internal) e publico (*.hml|prod.alvocard.com.br).
# Uso:       ./provision-ingress.sh --manifest <path> [--dry-run] [--env <env>]
# Deps:      kubectl, yq, sed
# Idempotente: SIM -- usa kubectl apply
# Ref:       GAP-PLAT-ING-04 | 2026-03-18 | Updated 2026-03-27 (auto-Ingress)
# Seguranca: scheme sempre internal para hosts *.internal. data-public requer
#            costTier=dedicated ou aprovacao explicita via pipeline.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/../../templates"

LOG_PREFIX="ING"
_COMMON_SH="${SCRIPT_DIR}/../lib/common.sh"
if [[ -f "$_COMMON_SH" ]]; then
    # shellcheck source=../lib/common.sh
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
    log_info "Ingress desabilitado no manifesto -- nenhum recurso criado"
    exit 0
fi

ING_HOST=$(yq '.config.ingress.host // ""' "$MANIFEST_PATH")
ING_CLASS=$(yq '.config.ingress.class // "internal"' "$MANIFEST_PATH")
ING_GROUP=$(yq '.config.ingress.ingressGroup // ""' "$MANIFEST_PATH")
ING_COST_TIER=$(yq '.config.ingress.costTier // "shared"' "$MANIFEST_PATH")
ING_PORT=$(yq '.config.port // 8000' "$MANIFEST_PATH")
ING_PATH_PREFIX=$(yq '.config.ingress.pathPrefix // "/"' "$MANIFEST_PATH")
ING_HEALTH_PATH=$(yq '.config.ingress.healthCheckPath // .config.healthCheck.liveness // "/health"' "$MANIFEST_PATH")

# ---- Auto-detect IngressGroup based on domain if not set ----
if [[ -z "$ING_GROUP" ]] || [[ "$ING_GROUP" == "null" ]]; then
    case "$DOMAIN" in
        data)               ING_GROUP="data-internal" ;;
        platform)           ING_GROUP="platform-internal" ;;
        integration)        ING_GROUP="integration-internal" ;;
        shared-services)    ING_GROUP="platform-internal" ;;
        operations)         ING_GROUP="platform-internal" ;;
        *)                  ING_GROUP="data-internal" ;;
    esac
    log_info "IngressGroup auto-detectado pelo dominio '${DOMAIN}': ${ING_GROUP}"
fi

# ---- Default host se nao definido ----
if [[ -z "$ING_HOST" ]] || [[ "$ING_HOST" == "null" ]]; then
    ING_HOST="${APP_NAME}.${ENV}.internal"
fi

# ---- Default path prefix ----
if [[ -z "$ING_PATH_PREFIX" ]] || [[ "$ING_PATH_PREFIX" == "null" ]]; then
    ING_PATH_PREFIX="/"
fi

# ---- Default health check path ----
if [[ -z "$ING_HEALTH_PATH" ]] || [[ "$ING_HEALTH_PATH" == "null" ]]; then
    ING_HEALTH_PATH="/health"
fi

# ---- Resolve public host ----
# Public host pattern: {app}.hml.alvocard.com.br (staging) | {app}.prod.alvocard.com.br (prod)
# Only generate public Ingress when ingress class allows external access
# ING_CLASS="internal" still gets a public host (routed via internal ALB + External-DNS)
# ING_CLASS="external" would use internet-facing ALB (reserved for data-public group)
if [[ "$ENV" == "staging" ]]; then
    PUBLIC_HOST="${APP_NAME}.hml.alvocard.com.br"
elif [[ "$ENV" == "prod" ]]; then
    PUBLIC_HOST="${APP_NAME}.prod.alvocard.com.br"
else
    PUBLIC_HOST=""
fi
log_info "Ingress class: ${ING_CLASS}"

# ---- Resolve ACM certificate ARNs per environment ----
# ConfigMap lookup (preferred) with hardcoded fallback
# Staging: *.staging.internal + *.hml.alvocard.com.br
# Prod: *.prod.internal + *.prod.alvocard.com.br
CERT_ARN=""
if [[ "$DRY_RUN" == "false" ]]; then
    # Try to read from platform-acm-config ConfigMap in the platform namespace
    ACM_NS="${ENV}-platform-argocd"
    CERT_ARN=$(kubectl get configmap platform-acm-config -n "$ACM_NS" \
        -o jsonpath='{.data.certificate-arns}' 2>/dev/null || echo "")
fi

# Fallback to known ARNs if ConfigMap not available
if [[ -z "$CERT_ARN" ]]; then
    if [[ "$ENV" == "staging" ]]; then
        CERT_ARN="arn:aws:acm:us-east-1:891377105802:certificate/6aa5140b-e1ba-4005-a703-d9f5850bc16a,arn:aws:acm:us-east-1:891377105802:certificate/3bfc603d-3a90-4663-b363-28f5122b7dbb"
    elif [[ "$ENV" == "prod" ]]; then
        # Prod certs: *.prod.internal + *.prod.alvocard.com.br
        CERT_ARN="arn:aws:acm:us-east-1:891377105802:certificate/da133107-2ce8-4fb8-82fc-d12a346ea039"
    fi
    log_info "Usando certificate-arn fallback para env=${ENV}"
fi

log_info "App: ${APP_NAME} | Host: ${ING_HOST} | Group: ${ING_GROUP} | CostTier: ${ING_COST_TIER}"
log_info "HealthCheck: ${ING_HEALTH_PATH} | Port: ${ING_PORT} | PathPrefix: ${ING_PATH_PREFIX}"
log_info "Public Host: ${PUBLIC_HOST:-<nenhum>}"

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

# ---- Aplicar template (host interno) ----
TEMPLATE_FILE="${TEMPLATES_DIR}/ingress-template.yaml"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_error "Template nao encontrado: $TEMPLATE_FILE"
    exit 1
fi

# Escape forward slashes in paths for sed
ESCAPED_HEALTH_PATH=$(echo "$ING_HEALTH_PATH" | sed 's|/|\\/|g')
ESCAPED_PATH_PREFIX=$(echo "$ING_PATH_PREFIX" | sed 's|/|\\/|g')
ESCAPED_CERT_ARN=$(echo "$CERT_ARN" | sed 's|/|\\/|g')

RENDERED=$(sed \
    -e "s/\${APP_NAME}/${APP_NAME}/g" \
    -e "s/\${NAMESPACE}/${NAMESPACE}/g" \
    -e "s/\${HOST}/${ING_HOST}/g" \
    -e "s/\${INGRESS_GROUP}/${ING_GROUP}/g" \
    -e "s|\${PORT}|${ING_PORT}|g" \
    -e "s/\${HEALTH_CHECK_PATH}/${ESCAPED_HEALTH_PATH}/g" \
    -e "s/\${CERTIFICATE_ARN}/${ESCAPED_CERT_ARN}/g" \
    -e "s/\${ENV}/${ENV}/g" \
    -e "s/\${DOMAIN}/${DOMAIN}/g" \
    -e "s/\${PATH_PREFIX}/${ESCAPED_PATH_PREFIX}/g" \
    "$TEMPLATE_FILE")

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Aplicaria Ingress interno ${APP_NAME}:"
    echo "$RENDERED"
    echo "---"
else
    echo "$RENDERED" | kubectl apply -f - && log_success "Ingress interno ${APP_NAME} aplicado (${ING_HOST})"
fi

# ---- Aplicar Ingress publico (se public host definido) ----
# Public Ingress uses a different name (app-public) but routes to the SAME service backend.
if [[ -n "$PUBLIC_HOST" ]]; then
    log_info "Gerando Ingress publico: ${PUBLIC_HOST}"

    # First render with original APP_NAME (so service backend is correct)
    RENDERED_PUBLIC=$(sed \
        -e "s/\${APP_NAME}/${APP_NAME}/g" \
        -e "s/\${NAMESPACE}/${NAMESPACE}/g" \
        -e "s/\${HOST}/${PUBLIC_HOST}/g" \
        -e "s/\${INGRESS_GROUP}/${ING_GROUP}/g" \
        -e "s|\${PORT}|${ING_PORT}|g" \
        -e "s/\${HEALTH_CHECK_PATH}/${ESCAPED_HEALTH_PATH}/g" \
        -e "s/\${CERTIFICATE_ARN}/${ESCAPED_CERT_ARN}/g" \
        -e "s/\${ENV}/${ENV}/g" \
        -e "s/\${DOMAIN}/${DOMAIN}/g" \
        -e "s/\${PATH_PREFIX}/${ESCAPED_PATH_PREFIX}/g" \
        "$TEMPLATE_FILE")

    # Then patch only the metadata.name to be unique (app-public) while keeping service backend as app
    RENDERED_PUBLIC=$(echo "$RENDERED_PUBLIC" | sed "0,/^  name: ${APP_NAME}$/s/^  name: ${APP_NAME}$/  name: ${APP_NAME}-public/")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Aplicaria Ingress publico ${APP_NAME}-public:"
        echo "$RENDERED_PUBLIC"
    else
        echo "$RENDERED_PUBLIC" | kubectl apply -f - && log_success "Ingress publico ${APP_NAME}-public aplicado (${PUBLIC_HOST})"
    fi
fi

log_success "Ingress provisionado: ${ING_HOST} + ${PUBLIC_HOST:-<sem public>} -> ${APP_NAME}:${ING_PORT} via ${ING_GROUP}"
