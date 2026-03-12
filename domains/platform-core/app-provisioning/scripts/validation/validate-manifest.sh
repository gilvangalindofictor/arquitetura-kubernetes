#!/bin/bash
# =============================================================================
# validate-manifest.sh — Valida .platform/manifest.yaml contra schema e regras
# =============================================================================
# Descricao: Verifica que o manifesto e YAML valido, tem apiVersion correta,
#            campos obrigatorios preenchidos e valores dentro dos limites.
# Uso:       ./validate-manifest.sh <manifest-path>
# Deps:      yq, python3+jsonschema (opcional — graceful degradation)
# Ref:       P6 (versionamento schema), GAP-003 (JSON Schema futuro), GAP-023
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="VALIDATE"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/manifest-parser.sh"

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local MANIFEST_PATH="${1:-}"
    if [[ -z "$MANIFEST_PATH" || ! -f "$MANIFEST_PATH" ]]; then
        log_error "Uso: ./validate-manifest.sh <manifest-path>"
        exit 1
    fi

    local ERRORS=0

    # 0. JSON Schema validation (graceful — GAP-023)
    local SCHEMA_PATH="${SCRIPT_DIR}/../../schemas/v1/manifest-schema.json"

    if [[ -f "$SCHEMA_PATH" ]]; then
        if command -v python3 &>/dev/null && python3 -c "import jsonschema" &>/dev/null; then
            log_info "Executando validacao JSON Schema (standalone)..."
            local MANIFEST_JSON
            MANIFEST_JSON=$(yq -o=json '.' "$MANIFEST_PATH")
            if export SCHEMA_PATH="$SCHEMA_PATH" && echo "$MANIFEST_JSON" | python3 -c "
import sys, json, os
from jsonschema import validate, ValidationError
schema_path = os.environ.get('SCHEMA_PATH', '')
with open(schema_path) as f:
    schema = json.load(f)
instance = json.load(sys.stdin)
try:
    validate(instance=instance, schema=schema)
    print('OK')
except ValidationError as e:
    print(f'SCHEMA_ERROR: {e.message}')
    sys.exit(1)
"; then
                log_success "JSON Schema validation passed"
            else
                log_error "JSON Schema validation failed"
                ERRORS=$((ERRORS + 1))
            fi
        else
            log_warn "python3 ou jsonschema nao disponivel — pulando validacao JSON Schema (instale com: pip install jsonschema)"
        fi
    else
        log_warn "Schema nao encontrado em ${SCHEMA_PATH} — pulando validacao JSON Schema"
    fi

    # 1. YAML valido
    log_info "Verificando YAML valido..."
    if ! yq '.' "$MANIFEST_PATH" &>/dev/null; then
        log_error "YAML invalido: $MANIFEST_PATH"
        exit 1
    fi
    log_success "YAML valido"

    # 2. apiVersion
    log_info "Verificando apiVersion..."
    local API_VERSION
    API_VERSION=$(manifest_get '.apiVersion' '' "$MANIFEST_PATH")
    if [[ "$API_VERSION" != "platform.k8s/v1" ]]; then
        log_error "apiVersion invalida: '$API_VERSION' (esperado: platform.k8s/v1)"
        ERRORS=$((ERRORS + 1))
    else
        log_success "apiVersion: $API_VERSION"
    fi

    # 3. kind
    local KIND
    KIND=$(manifest_get '.kind' '' "$MANIFEST_PATH")
    if [[ "$KIND" != "ApplicationManifest" ]]; then
        log_error "kind invalido: '$KIND' (esperado: ApplicationManifest)"
        ERRORS=$((ERRORS + 1))
    fi

    # 4. Campos obrigatorios de metadata
    log_info "Verificando campos obrigatorios..."

    local REQUIRED_FIELDS=("metadata.name" "metadata.domain" "metadata.product" "metadata.type" "metadata.owner")
    for field in "${REQUIRED_FIELDS[@]}"; do
        local value
        value=$(manifest_get ".${field}" '' "$MANIFEST_PATH")
        if [[ -z "$value" ]]; then
            log_error "Campo obrigatorio vazio: $field"
            ERRORS=$((ERRORS + 1))
        fi
    done

    # 5. Tipo valido
    local APP_TYPE
    APP_TYPE=$(manifest_get '.metadata.type' '' "$MANIFEST_PATH")
    case "$APP_TYPE" in
        etl|api-rest|worker|frontend|cronjob)
            log_success "Tipo valido: $APP_TYPE"
            ;;
        *)
            log_error "Tipo invalido: '$APP_TYPE' (permitidos: etl, api-rest, worker, frontend, cronjob)"
            ERRORS=$((ERRORS + 1))
            ;;
    esac

    # 6. Dominio valido (ADR-047)
    local DOMAIN
    DOMAIN=$(manifest_get '.metadata.domain' '' "$MANIFEST_PATH")
    case "$DOMAIN" in
        platform|integration|data|operations|shared-services)
            log_success "Dominio valido: $DOMAIN"
            ;;
        *)
            log_error "Dominio invalido: '$DOMAIN' (ADR-047)"
            ERRORS=$((ERRORS + 1))
            ;;
    esac

    # 7. Hard cap de recursos (P5: 4Gi mem / 2000m CPU)
    log_info "Verificando hard caps de recursos (P5)..."

    local CPU_LIM MEM_LIM
    CPU_LIM=$(manifest_get '.resources.limits.cpu' '' "$MANIFEST_PATH")
    MEM_LIM=$(manifest_get '.resources.limits.memory' '' "$MANIFEST_PATH")

    if [[ -n "$CPU_LIM" ]]; then
        local CPU_VAL="${CPU_LIM%m}"
        if [[ "$CPU_LIM" != *"m" ]]; then
            CPU_VAL=$((CPU_VAL * 1000))
        fi
        if [[ "$CPU_VAL" -gt 2000 ]]; then
            log_error "CPU limit ${CPU_LIM} excede hard cap de 2000m (P5)"
            ERRORS=$((ERRORS + 1))
        fi
    fi

    if [[ -n "$MEM_LIM" ]]; then
        local MEM_VAL
        if [[ "$MEM_LIM" == *"Gi" ]]; then
            MEM_VAL=$(echo "${MEM_LIM%Gi}" | awk '{printf "%d", $1 * 1024}')
        elif [[ "$MEM_LIM" == *"Mi" ]]; then
            MEM_VAL="${MEM_LIM%Mi}"
        else
            MEM_VAL=0
        fi
        if [[ "$MEM_VAL" -gt 4096 ]]; then
            log_error "Memory limit ${MEM_LIM} excede hard cap de 4Gi (P5)"
            ERRORS=$((ERRORS + 1))
        fi
    fi

    # 8. Config basica
    local PORT
    PORT=$(manifest_get '.config.port' '0' "$MANIFEST_PATH")
    if [[ "$APP_TYPE" != "cronjob" && ("$PORT" == "0" || "$PORT" == "null") ]]; then
        log_warn "config.port nao definida (recomendado para tipos nao-cronjob)"
    fi

    # Resultado
    echo ""
    if [[ $ERRORS -gt 0 ]]; then
        log_error "Validacao FALHOU com $ERRORS erro(s)"
        exit 1
    else
        log_success "Manifesto valido — 0 erros"
        exit 0
    fi
}

main "$@"
