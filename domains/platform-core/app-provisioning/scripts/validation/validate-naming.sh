#!/bin/bash
# =============================================================================
# validate-naming.sh — Valida naming conventions (ADR-048)
# =============================================================================
# Descricao: Verifica que app name, domain e product seguem kebab-case,
#            max 63 chars, e padroes definidos no ADR-048.
# Uso:       ./validate-naming.sh <app-name> <domain> <product>
# Deps:      bash
# Ref:       ADR-048 (Naming Conventions Deterministicas)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="NAMING"
source "${SCRIPT_DIR}/../lib/common.sh"

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local APP_NAME="${1:-}"
    local DOMAIN="${2:-}"
    local PRODUCT="${3:-}"

    if [[ -z "$APP_NAME" || -z "$DOMAIN" || -z "$PRODUCT" ]]; then
        log_error "Uso: ./validate-naming.sh <app-name> <domain> <product>"
        exit 1
    fi

    local ERRORS=0

    # Regex ADR-048: kebab-case, max 63 chars
    local KEBAB_REGEX='^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
    local MAX_LEN=63

    log_info "Validando naming conventions (ADR-048)..."

    # App name
    if ! [[ "$APP_NAME" =~ $KEBAB_REGEX ]]; then
        log_error "App name invalido: '$APP_NAME' (regex: $KEBAB_REGEX)"
        ERRORS=$((ERRORS + 1))
    elif [[ ${#APP_NAME} -gt $MAX_LEN ]]; then
        log_error "App name excede $MAX_LEN chars: '$APP_NAME' (${#APP_NAME} chars)"
        ERRORS=$((ERRORS + 1))
    else
        log_success "App name valido: $APP_NAME"
    fi

    # Product name
    if ! [[ "$PRODUCT" =~ $KEBAB_REGEX ]]; then
        log_error "Product name invalido: '$PRODUCT' (regex: $KEBAB_REGEX)"
        ERRORS=$((ERRORS + 1))
    elif [[ ${#PRODUCT} -gt $MAX_LEN ]]; then
        log_error "Product name excede $MAX_LEN chars: '$PRODUCT' (${#PRODUCT} chars)"
        ERRORS=$((ERRORS + 1))
    else
        log_success "Product name valido: $PRODUCT"
    fi

    # Domain (ADR-047)
    case "$DOMAIN" in
        platform|integration|data|operations|shared-services)
            log_success "Domain valido: $DOMAIN"
            ;;
        *)
            log_error "Domain invalido: '$DOMAIN'"
            ERRORS=$((ERRORS + 1))
            ;;
    esac

    # Namespace resultante nao excede 63 chars
    local NS_CANDIDATE="prod-${DOMAIN}-${APP_NAME}"
    if [[ ${#NS_CANDIDATE} -gt 63 ]]; then
        log_error "Namespace resultante excede 63 chars: '$NS_CANDIDATE' (${#NS_CANDIDATE} chars)"
        ERRORS=$((ERRORS + 1))
    else
        log_success "Namespace max length OK: '$NS_CANDIDATE' (${#NS_CANDIDATE} chars)"
    fi

    # Resultado
    if [[ $ERRORS -gt 0 ]]; then
        log_error "Naming validation FALHOU com $ERRORS erro(s)"
        exit 1
    else
        log_success "Naming conventions OK — ADR-048 compliant"
        exit 0
    fi
}

main "$@"
