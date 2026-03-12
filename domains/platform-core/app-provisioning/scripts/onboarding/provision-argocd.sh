#!/bin/bash
# =============================================================================
# provision-argocd.sh — Provisiona AppProject ArgoCD a partir do template oficial
# =============================================================================
# Descricao: Aplica o appproject-template.yaml substituindo os 4 placeholders
#            via sed. Operacao idempotente: nao recria se AppProject ja existe.
# Uso:       ./provision-argocd.sh \
#              --app <nome> \
#              --domain <domain> \
#              --env <env> \
#              --argocd-namespace <ns> \
#              --gitlab-host <host>
# Deps:      kubectl, sed
# Idempotente: SIM — verifica existencia antes de aplicar
# Ref:       GAP-010 ITEM 5 | ADR-047 | ADR-048
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common.sh — com fallback se nao existir
LOG_PREFIX="ARGOCD-PROVISION"
if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/../lib/common.sh"
else
    # Fallback minimo de logging quando common.sh nao esta disponivel
    log_info()    { echo "[ARGOCD-PROVISION] $1"; }
    log_success() { echo "[ARGOCD-PROVISION] $1"; }
    log_warn()    { echo "[ARGOCD-PROVISION][WARN] $1"; }
    log_error()   { echo "[ARGOCD-PROVISION][ERROR] $1" >&2; }
    validate_required_args() {
        local missing=()
        for var in "$@"; do
            if [[ -z "${!var:-}" ]]; then
                local param_name
                param_name=$(echo "$var" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
                missing+=("--${param_name}")
            fi
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            log_error "Parametros obrigatorios ausentes: ${missing[*]}"
            return 1
        fi
        return 0
    }
    resource_exists() {
        local kind="$1" name="$2" namespace="${3:-}"
        local ns_flag=""
        [[ -n "$namespace" ]] && ns_flag="-n $namespace"
        kubectl get "$kind" "$name" $ns_flag &>/dev/null 2>&1
    }
fi

# -----------------------------------------------------------------------------
# Parse argumentos
# -----------------------------------------------------------------------------
parse_args() {
    APP_NAME="" DOMAIN="" ENV="" ARGOCD_NAMESPACE="" GITLAB_HOST=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --app)               APP_NAME="$2";        shift 2 ;;
            --domain)            DOMAIN="$2";           shift 2 ;;
            --env)               ENV="$2";              shift 2 ;;
            --argocd-namespace)  ARGOCD_NAMESPACE="$2"; shift 2 ;;
            --gitlab-host)       GITLAB_HOST="$2";      shift 2 ;;
            *) log_error "Opcao desconhecida: $1"; exit 1 ;;
        esac
    done

    validate_required_args APP_NAME DOMAIN ENV ARGOCD_NAMESPACE GITLAB_HOST || exit 1
}

# -----------------------------------------------------------------------------
# Localiza o template oficial do AppProject
# -----------------------------------------------------------------------------
find_template() {
    # Busca relativa ao script: sobe ate app-provisioning/ e entra em templates/
    local base_dir
    base_dir="$(cd "${SCRIPT_DIR}/../.." && pwd)"
    local template="${base_dir}/templates/appproject-template.yaml"

    if [[ ! -f "$template" ]]; then
        log_error "Template nao encontrado: ${template}"
        log_error "Verifique se o repositorio app-provisioning esta clonado corretamente."
        exit 1
    fi

    echo "$template"
}

# -----------------------------------------------------------------------------
# Aplica o AppProject via template (sed substitui os 4 placeholders)
# -----------------------------------------------------------------------------
apply_appproject() {
    local template_path="$1"

    log_info "Renderizando template: ${template_path}"
    log_info "  DOMAIN=${DOMAIN} | ENV=${ENV} | ARGOCD_NAMESPACE=${ARGOCD_NAMESPACE} | GITLAB_HOST=${GITLAB_HOST}"

    # sed substitui os 4 placeholders definidos no cabecalho do template
    # A ordem importa: ARGOCD_NAMESPACE antes de qualquer padrao mais curto
    local rendered
    rendered=$(sed \
        -e "s|\${DOMAIN}|${DOMAIN}|g" \
        -e "s|\${ARGOCD_NAMESPACE}|${ARGOCD_NAMESPACE}|g" \
        -e "s|\${GITLAB_HOST}|${GITLAB_HOST}|g" \
        -e "s|\${ENV}|${ENV}|g" \
        "$template_path")

    log_info "Aplicando AppProject '${DOMAIN}' no namespace '${ARGOCD_NAMESPACE}'..."
    echo "$rendered" | kubectl apply -f -
}

# -----------------------------------------------------------------------------
# Aguarda AppProject estar Ready (kubectl wait ou loop de fallback)
# -----------------------------------------------------------------------------
wait_appproject_ready() {
    local max_attempts=30
    local interval=2
    local attempt=0

    log_info "Aguardando AppProject '${DOMAIN}' estar disponivel..."

    # Tenta kubectl wait primeiro (ArgoCD >= 2.4 suporta)
    if kubectl wait appproject "${DOMAIN}" \
        -n "${ARGOCD_NAMESPACE}" \
        --for=jsonpath='{.metadata.name}'="${DOMAIN}" \
        --timeout=60s &>/dev/null 2>&1; then
        log_success "AppProject '${DOMAIN}' confirmado via kubectl wait"
        return 0
    fi

    # Fallback: loop de verificacao de existencia
    while [[ $attempt -lt $max_attempts ]]; do
        if kubectl get appproject "${DOMAIN}" -n "${ARGOCD_NAMESPACE}" &>/dev/null 2>&1; then
            log_success "AppProject '${DOMAIN}' esta disponivel (tentativa $((attempt + 1)))"
            return 0
        fi
        attempt=$((attempt + 1))
        log_info "Aguardando... (${attempt}/${max_attempts})"
        sleep "$interval"
    done

    log_error "AppProject '${DOMAIN}' nao ficou disponivel apos $((max_attempts * interval))s"
    return 1
}

# -----------------------------------------------------------------------------
# Cleanup (sem artefatos temporarios neste script)
# -----------------------------------------------------------------------------
_cleanup() { :; }
if declare -f register_cleanup &>/dev/null; then
    register_cleanup _cleanup
else
    trap _cleanup EXIT
fi

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    log_info "=== provision-argocd.sh ==="
    log_info "App: ${APP_NAME} | Domain: ${DOMAIN} | Env: ${ENV}"
    log_info "ArgoCD NS: ${ARGOCD_NAMESPACE} | GitLab: ${GITLAB_HOST}"

    # Verificar dependencias
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl nao encontrado no PATH"
        exit 1
    fi

    # Localizar template
    local template_path
    template_path="$(find_template)"

    # Idempotencia: verificar se AppProject ja existe
    if resource_exists appproject "${DOMAIN}" "${ARGOCD_NAMESPACE}"; then
        log_warn "AppProject '${DOMAIN}' ja existe em '${ARGOCD_NAMESPACE}' — nenhuma acao necessaria"
        log_warn "Para atualizar, delete o AppProject manualmente e rode este script novamente."
        log_success "provision-argocd.sh concluido (idempotente — recurso pre-existente)"
        return 0
    fi

    # Aplicar template
    apply_appproject "$template_path"

    # Aguardar disponibilidade
    wait_appproject_ready

    log_success "AppProject '${DOMAIN}' provisionado com sucesso em '${ARGOCD_NAMESPACE}'"
    return 0
}

main "$@"
