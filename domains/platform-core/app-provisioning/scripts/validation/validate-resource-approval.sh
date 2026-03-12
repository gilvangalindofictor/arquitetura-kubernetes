#!/bin/bash
# =============================================================================
# validate-resource-approval.sh — Valida camada de aprovacao de recursos
# =============================================================================
# Descricao: Compara resources do manifest.yaml contra presets por tipo (ADR-104)
#            e determina qual camada de aprovacao e necessaria (decisao P5).
#
#   Camada 1: AUTO       — recursos <= preset → aceito automaticamente
#   Camada 2: TECH LEAD  — recursos > preset mas <= hard cap → MR Approval
#   Camada 3: PLATFORM   — recursos > hard cap (4Gi mem / 2000m CPU) → BLOCK
#
# Uso:       ./validate-resource-approval.sh --manifest <path>
# Deps:      yq, common.sh, manifest-parser.sh
# Ref:       ADR-104 (presets por tipo), P5 (aprovacao 3 camadas), GAP-014
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="RESOURCE-APPROVAL"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/manifest-parser.sh"

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# =============================================================================
# Presets por tipo de aplicacao (ADR-104)
# Valores em millicores (CPU) e Mi (memoria)
# =============================================================================
declare -A PRESET_CPU_REQ PRESET_CPU_LIM PRESET_MEM_REQ PRESET_MEM_LIM

PRESET_CPU_REQ=([etl]=200 [api-rest]=100 [worker]=100 [frontend]=50 [cronjob]=100)
PRESET_CPU_LIM=([etl]=800 [api-rest]=400 [worker]=400 [frontend]=200 [cronjob]=500)
PRESET_MEM_REQ=([etl]=256 [api-rest]=128 [worker]=128 [frontend]=64 [cronjob]=128)
PRESET_MEM_LIM=([etl]=1024 [api-rest]=512 [worker]=512 [frontend]=256 [cronjob]=512)

# Hard caps (P5 — Kyverno Enforce)
HARD_CAP_CPU_MILLICORES=2000   # 2000m = 2 cores
HARD_CAP_MEM_MI=4096           # 4096Mi = 4Gi

# =============================================================================
# Funcoes de conversao de unidades Kubernetes
# =============================================================================

# Converte CPU para millicores (inteiro)
# Exemplos: 100m → 100, 1 → 1000, 500m → 500, 2 → 2000
convert_cpu_to_millicores() {
    local value="$1"

    if [[ -z "$value" ]]; then
        echo "0"
        return
    fi

    if [[ "$value" == *"m" ]]; then
        echo "${value%m}"
    else
        # Inteiro ou decimal sem sufixo = cores
        echo "$value" | awk '{printf "%d", $1 * 1000}'
    fi
}

# Converte memoria para Mi (inteiro)
# Exemplos: 256Mi → 256, 1Gi → 1024, 512Mi → 512, 2Gi → 2048
convert_mem_to_mi() {
    local value="$1"

    if [[ -z "$value" ]]; then
        echo "0"
        return
    fi

    if [[ "$value" == *"Gi" ]]; then
        echo "${value%Gi}" | awk '{printf "%d", $1 * 1024}'
    elif [[ "$value" == *"Mi" ]]; then
        echo "${value%Mi}"
    elif [[ "$value" == *"Ki" ]]; then
        echo "${value%Ki}" | awk '{printf "%d", $1 / 1024}'
    elif [[ "$value" == *"G" ]]; then
        echo "${value%G}" | awk '{printf "%d", $1 * 1000 * 1000 * 1000 / 1048576}'
    elif [[ "$value" == *"M" ]]; then
        echo "${value%M}" | awk '{printf "%d", $1 * 1000 * 1000 / 1048576}'
    else
        # Assume bytes
        echo "$value" | awk '{printf "%d", $1 / 1048576}'
    fi
}

# =============================================================================
# Argument parsing
# =============================================================================
usage() {
    echo "Uso: $(basename "$0") --manifest <path>"
    echo ""
    echo "Valida camada de aprovacao de recursos (P5/ADR-104/GAP-014)"
    echo ""
    echo "  --manifest <path>   Caminho para .platform/manifest.yaml (obrigatorio)"
    echo "  --help              Exibe esta ajuda"
    echo ""
    echo "Camadas de aprovacao:"
    echo "  CAMADA 1 (AUTO)      — recursos dentro do preset do tipo"
    echo "  CAMADA 2 (TECH LEAD) — recursos acima do preset, dentro do hard cap"
    echo "  CAMADA 3 (BLOCK)     — recursos acima do hard cap (4Gi mem / 2000m CPU)"
}

parse_args() {
    MANIFEST_PATH=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --manifest)
                MANIFEST_PATH="${2:-}"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Argumento desconhecido: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$MANIFEST_PATH" ]]; then
        log_error "Parametro --manifest e obrigatorio"
        usage
        exit 1
    fi

    if [[ ! -f "$MANIFEST_PATH" ]]; then
        log_error "Manifesto nao encontrado: $MANIFEST_PATH"
        exit 1
    fi
}

# =============================================================================
# Comparacao de recursos contra preset
# =============================================================================
# Retorna: 0 = dentro do preset, 1 = acima do preset
check_exceeds_preset() {
    local actual="$1" preset="$2"

    if [[ "$actual" -gt "$preset" ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# Comparacao de recursos contra hard cap
# =============================================================================
# Retorna: 0 = dentro do hard cap, 1 = acima do hard cap
check_exceeds_hardcap() {
    local cpu_lim_mc="$1" mem_lim_mi="$2"

    if [[ "$cpu_lim_mc" -gt "$HARD_CAP_CPU_MILLICORES" ]]; then
        return 1
    fi
    if [[ "$mem_lim_mi" -gt "$HARD_CAP_MEM_MI" ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"

    check_dependency yq

    # Carregar manifesto
    parse_manifest "$MANIFEST_PATH"

    # Validar tipo suportado
    if [[ -z "${PRESET_CPU_LIM[$APP_TYPE]+_}" ]]; then
        log_error "Tipo '$APP_TYPE' nao possui preset definido (ADR-104)"
        log_error "Tipos suportados: etl, api-rest, worker, frontend, cronjob"
        exit 1
    fi

    # Ler resources do manifesto
    eval "$(manifest_get_resources "$MANIFEST_PATH")"

    # Converter para unidades normalizadas
    local CPU_REQ_MC CPU_LIM_MC MEM_REQ_MI MEM_LIM_MI
    CPU_REQ_MC=$(convert_cpu_to_millicores "${RES_CPU_REQ:-0}")
    CPU_LIM_MC=$(convert_cpu_to_millicores "${RES_CPU_LIM:-0}")
    MEM_REQ_MI=$(convert_mem_to_mi "${RES_MEM_REQ:-0}")
    MEM_LIM_MI=$(convert_mem_to_mi "${RES_MEM_LIM:-0}")

    log_info "Tipo da aplicacao: $APP_TYPE"
    log_info "Recursos solicitados:"
    log_info "  CPU  request=${CPU_REQ_MC}m  limit=${CPU_LIM_MC}m"
    log_info "  MEM  request=${MEM_REQ_MI}Mi limit=${MEM_LIM_MI}Mi"
    log_info "Preset para tipo '$APP_TYPE' (ADR-104):"
    log_info "  CPU  request=${PRESET_CPU_REQ[$APP_TYPE]}m  limit=${PRESET_CPU_LIM[$APP_TYPE]}m"
    log_info "  MEM  request=${PRESET_MEM_REQ[$APP_TYPE]}Mi limit=${PRESET_MEM_LIM[$APP_TYPE]}Mi"
    log_info "Hard cap (P5): CPU=${HARD_CAP_CPU_MILLICORES}m  MEM=${HARD_CAP_MEM_MI}Mi (4Gi)"

    echo ""

    # ── CAMADA 3: Verificar hard cap primeiro ─────────────────────────────────
    local HARDCAP_EXCEEDED=false
    local HARDCAP_REASONS=()

    if [[ "$CPU_LIM_MC" -gt "$HARD_CAP_CPU_MILLICORES" ]]; then
        HARDCAP_EXCEEDED=true
        HARDCAP_REASONS+=("CPU limit ${CPU_LIM_MC}m excede hard cap de ${HARD_CAP_CPU_MILLICORES}m")
    fi

    if [[ "$MEM_LIM_MI" -gt "$HARD_CAP_MEM_MI" ]]; then
        HARDCAP_EXCEEDED=true
        HARDCAP_REASONS+=("Memory limit ${MEM_LIM_MI}Mi excede hard cap de ${HARD_CAP_MEM_MI}Mi (4Gi)")
    fi

    if [[ "$HARDCAP_EXCEEDED" == "true" ]]; then
        log_error "=========================================================="
        log_error " CAMADA 3: BLOQUEADO — Recursos excedem hard cap (P5)"
        log_error "=========================================================="
        for reason in "${HARDCAP_REASONS[@]}"; do
            log_error "  -> $reason"
        done
        log_error ""
        log_error "Acao necessaria:"
        log_error "  1. Reduza recursos para dentro do hard cap (4Gi mem / 2000m CPU)"
        log_error "  2. OU abra processo de exception com Platform Team"
        log_error "     (MR com label 'resource-exception' + justificativa tecnica)"
        log_error ""
        log_error "Ref: ADR-104, decisao P5, GAP-014"
        log_error "Nota: Kyverno ClusterPolicy 'enforce-resource-hard-cap' bloqueia"
        log_error "      deploy de workloads acima do hard cap no cluster."
        exit 1
    fi

    # ── CAMADA 2: Verificar se excede preset ──────────────────────────────────
    local PRESET_EXCEEDED=false
    local PRESET_REASONS=()

    if [[ "$CPU_REQ_MC" -gt "${PRESET_CPU_REQ[$APP_TYPE]}" ]]; then
        PRESET_EXCEEDED=true
        PRESET_REASONS+=("CPU request ${CPU_REQ_MC}m > preset ${PRESET_CPU_REQ[$APP_TYPE]}m")
    fi
    if [[ "$CPU_LIM_MC" -gt "${PRESET_CPU_LIM[$APP_TYPE]}" ]]; then
        PRESET_EXCEEDED=true
        PRESET_REASONS+=("CPU limit ${CPU_LIM_MC}m > preset ${PRESET_CPU_LIM[$APP_TYPE]}m")
    fi
    if [[ "$MEM_REQ_MI" -gt "${PRESET_MEM_REQ[$APP_TYPE]}" ]]; then
        PRESET_EXCEEDED=true
        PRESET_REASONS+=("Memory request ${MEM_REQ_MI}Mi > preset ${PRESET_MEM_REQ[$APP_TYPE]}Mi")
    fi
    if [[ "$MEM_LIM_MI" -gt "${PRESET_MEM_LIM[$APP_TYPE]}" ]]; then
        PRESET_EXCEEDED=true
        PRESET_REASONS+=("Memory limit ${MEM_LIM_MI}Mi > preset ${PRESET_MEM_LIM[$APP_TYPE]}Mi")
    fi

    if [[ "$PRESET_EXCEEDED" == "true" ]]; then
        log_warn "=========================================================="
        log_warn " CAMADA 2: TECH LEAD APPROVAL — Recursos acima do preset"
        log_warn "=========================================================="
        for reason in "${PRESET_REASONS[@]}"; do
            log_warn "  -> $reason"
        done
        log_warn ""
        log_warn "Acao necessaria:"
        log_warn "  1. MR requer aprovacao de 1 Maintainer do dominio '$DOMAIN'"
        log_warn "  2. MR DEVE conter label 'resource-override' com justificativa"
        log_warn ""
        log_warn "Ref: ADR-104, decisao P5, GAP-014"
        # Camada 2 nao bloqueia pipeline — apenas exige aprovacao no MR
        exit 0
    fi

    # ── CAMADA 1: Dentro do preset ────────────────────────────────────────────
    log_success "=========================================================="
    log_success " CAMADA 1: AUTO — Recursos dentro do preset para '$APP_TYPE'"
    log_success "=========================================================="
    log_success "Nenhuma aprovacao adicional necessaria."
    log_success "Ref: ADR-104, decisao P5"
    exit 0
}

main "$@"
