#!/bin/bash
# =============================================================================
# validate-labels.sh — Valida labels obrigatorias no manifesto
# =============================================================================
# Descricao: Verifica que o manifesto contem todos os campos necessarios
#            para gerar labels Kubernetes obrigatorias (ADR-048).
# Uso:       ./validate-labels.sh --manifest <path> [--env <env>] [--domain <domain>]
#            ./validate-labels.sh <manifest-path>   # compat posicional
# Deps:      yq
# Ref:       ADR-048 (Labels obrigatorias por governance)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="LABELS"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/manifest-parser.sh"

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
usage() {
    echo "Uso: $(basename "$0") --manifest <path> [--env <env>] [--domain <domain>]"
    echo "     $(basename "$0") <manifest-path>   # argumento posicional (compat)"
}

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
parse_args() {
    MANIFEST_PATH=""
    ENV=""
    DOMAIN=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --manifest|-m) MANIFEST_PATH="$2"; shift 2 ;;
            --env|-e)      ENV="$2"; shift 2 ;;
            --domain|-d)   DOMAIN="$2"; shift 2 ;;
            --help|-h)     usage; exit 0 ;;
            -*)            log_error "Flag desconhecida: $1"; usage; exit 1 ;;
            *)             MANIFEST_PATH="$1"; shift ;;  # posicional para compat
        esac
    done
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    if [[ -z "$MANIFEST_PATH" || ! -f "$MANIFEST_PATH" ]]; then
        log_error "Manifesto nao encontrado ou nao informado."
        usage
        exit 1
    fi

    # Fallback: obter env e domain do manifesto se nao passados via flag
    if [[ -z "$ENV" ]]; then
        ENV=$(manifest_get '.metadata.env' '' "$MANIFEST_PATH") || true
    fi
    if [[ -z "$DOMAIN" ]]; then
        DOMAIN=$(manifest_get '.metadata.domain' '' "$MANIFEST_PATH") || true
    fi

    local ERRORS=0

    log_info "Verificando campos para labels obrigatorias..."

    # Labels que serao geradas a partir do manifesto
    local LABEL_SOURCES=(
        "metadata.name:app.kubernetes.io/name"
        "metadata.product:app.kubernetes.io/part-of"
        "metadata.domain:domain"
        "metadata.owner:owner"
        "metadata.type:app-type"
    )

    for entry in "${LABEL_SOURCES[@]}"; do
        local field="${entry%%:*}"
        local label="${entry##*:}"
        local value
        value=$(manifest_get ".${field}" '' "$MANIFEST_PATH")

        if [[ -z "$value" ]]; then
            log_error "Campo '$field' vazio — necessario para label '$label'"
            ERRORS=$((ERRORS + 1))
        else
            # Validar formato de label value (max 63 chars, alphanumeric + - _ .)
            if ! [[ "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$ ]]; then
                log_error "Valor '$value' de '$field' nao e valido como label Kubernetes"
                ERRORS=$((ERRORS + 1))
            else
                log_success "$label = $value"
            fi
        fi
    done

    # Tags (opcional, mas se presentes devem ser validas)
    local TAG_COUNT
    TAG_COUNT=$(yq '.metadata.tags | length' "$MANIFEST_PATH" 2>/dev/null || echo "0")
    if [[ "$TAG_COUNT" -gt 0 ]]; then
        log_info "Tags encontradas: $TAG_COUNT"
    fi

    # Resultado
    if [[ $ERRORS -gt 0 ]]; then
        log_error "Labels validation FALHOU com $ERRORS erro(s)"
        exit 1
    else
        log_success "Labels validation OK — todos campos obrigatorios presentes"
        exit 0
    fi
}

main "$@"
