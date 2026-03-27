#!/bin/bash
# =============================================================================
# provision-branch-protection.sh -- Branch Protection via GitLab API
# =============================================================================
# Descricao: Configura branch protection para staging e main automaticamente.
#            - Push direto BLOQUEADO em staging e main
#            - Merge permitido apenas por Maintainers (role TL)
#            - Force push BLOQUEADO
#            - Delete BLOQUEADO
#            - Merge settings do projeto: pipeline obrigatoria, discussions
#              resolvidas, squash default, remove source branch
#
# Uso:       ./provision-branch-protection.sh --project-id <id> --app <name>
#            ./provision-branch-protection.sh --project-name <group/repo> --app <name>
#
# Deps:      curl, jq (opcional)
# Idempotente: SIM -- remove protection existente antes de recriar
# Ref:       ADR-048 (naming), ADR-104 (manifesto base)
#
# Limitacoes GitLab CE:
#   - Approval rules (approvals_required) requer GitLab Premium/Ultimate
#   - approvals_before_merge nao existe na API CE
#   - Workaround: MR deve ser aprovado manualmente pelo TL via code review
#     A protecao de merge_access_level=40 garante que apenas Maintainers
#     podem fazer merge, o que equivale a "TL approval obrigatoria"
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common.sh if available
LOG_PREFIX="BRANCH"
_COMMON_SH="${SCRIPT_DIR}/../lib/common.sh"
if [[ -f "$_COMMON_SH" ]]; then
    # shellcheck source=../lib/common.sh
    source "$_COMMON_SH"
else
    _RED='\033[0;31m'; _GREEN='\033[0;32m'; _YELLOW='\033[1;33m'; _BLUE='\033[0;34m'; _NC='\033[0m'
    log_info()    { echo -e "${_BLUE}[${LOG_PREFIX}]${_NC} $1"; }
    log_success() { echo -e "${_GREEN}[${LOG_PREFIX}]${_NC} $1"; }
    log_warn()    { echo -e "${_YELLOW}[${LOG_PREFIX}]${_NC} $1"; }
    log_error()   { echo -e "${_RED}[${LOG_PREFIX}]${_NC} $1" >&2; }
fi

# =============================================================================
# Defaults
# =============================================================================
APP_NAME=""
GITLAB_PROJECT_ID=""
GITLAB_PROJECT_NAME=""
GITLAB_URL="${GITLAB_URL:-http://localhost:8443}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
DRY_RUN=false

# =============================================================================
# Access levels (GitLab API)
# =============================================================================
ACCESS_NO_ONE=0
ACCESS_DEVELOPER=30
ACCESS_MAINTAINER=40

# =============================================================================
# Parse arguments
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)    GITLAB_PROJECT_ID="$2"; shift 2 ;;
            --project-name)  GITLAB_PROJECT_NAME="$2"; shift 2 ;;
            --app)           APP_NAME="$2"; shift 2 ;;
            --gitlab-url)    GITLAB_URL="$2"; shift 2 ;;
            --gitlab-token)  GITLAB_TOKEN="$2"; shift 2 ;;
            --dry-run)       DRY_RUN=true; shift ;;
            --help|-h)
                echo "Usage: $0 --project-id <id> --app <name> [--gitlab-url <url>] [--gitlab-token <token>] [--dry-run]"
                echo "   or: $0 --project-name <group/repo> --app <name> [--gitlab-url <url>] [--gitlab-token <token>] [--dry-run]"
                exit 0
                ;;
            *) log_warn "Opcao desconhecida: $1"; shift ;;
        esac
    done

    # Resolve project ID from project name if needed
    if [[ -z "$GITLAB_PROJECT_ID" && -n "$GITLAB_PROJECT_NAME" ]]; then
        resolve_project_id
    fi

    if [[ -z "$GITLAB_TOKEN" ]]; then
        log_error "GITLAB_TOKEN nao definido. Use --gitlab-token ou export GITLAB_TOKEN"
        exit 1
    fi

    if [[ -z "$GITLAB_PROJECT_ID" ]]; then
        log_error "Informe --project-id ou --project-name"
        exit 1
    fi
}

# =============================================================================
# Resolve project ID from name (group/repo)
# =============================================================================
resolve_project_id() {
    local encoded_name
    encoded_name=$(echo "$GITLAB_PROJECT_NAME" | sed 's|/|%2F|g')

    local response
    response=$(curl -s --max-time 10 \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "${GITLAB_URL}/api/v4/projects/${encoded_name}" 2>/dev/null)

    GITLAB_PROJECT_ID=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)

    if [[ -z "$GITLAB_PROJECT_ID" ]]; then
        log_error "Projeto nao encontrado: $GITLAB_PROJECT_NAME"
        exit 1
    fi
    log_info "Projeto resolvido: $GITLAB_PROJECT_NAME -> ID $GITLAB_PROJECT_ID"
}

# =============================================================================
# GitLab API helper
# =============================================================================
gitlab_api() {
    local method="$1"
    local endpoint="$2"
    shift 2
    local extra_args=("$@")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $method ${GITLAB_URL}/api/v4${endpoint}"
        return 0
    fi

    curl -s --max-time 15 \
        --request "$method" \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "${GITLAB_URL}/api/v4${endpoint}" \
        "${extra_args[@]}" 2>/dev/null
}

# =============================================================================
# Protect a single branch
# =============================================================================
protect_branch() {
    local branch="$1"
    local push_access="$2"   # 0=no one, 30=developers, 40=maintainers
    local merge_access="$3"  # 40=maintainers

    log_info "Configurando protecao para branch '$branch' (project $GITLAB_PROJECT_ID)"

    # Step 1: Remove existing protection (idempotent — ignora 404)
    log_info "  Removendo protecao existente (se houver)..."
    gitlab_api DELETE "/projects/$GITLAB_PROJECT_ID/protected_branches/$branch" || true

    # Step 2: Create protection
    log_info "  Criando protecao: push_access=$push_access, merge_access=$merge_access, force_push=false"
    local response
    response=$(gitlab_api POST "/projects/$GITLAB_PROJECT_ID/protected_branches" \
        -d "name=$branch" \
        -d "push_access_level=$push_access" \
        -d "merge_access_level=$merge_access" \
        -d "allow_force_push=false" \
        -d "code_owner_approval_required=false")

    # Validate response
    if echo "$response" | grep -q '"name"'; then
        log_success "  Branch '$branch' protegida com sucesso"
    elif echo "$response" | grep -q '"message"'; then
        local msg
        msg=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null || echo "$response")
        log_warn "  Resposta API: $msg"
        # If branch already protected, try to update
        if echo "$msg" | grep -qi "already"; then
            log_info "  Branch ja protegida — tentando atualizar via PATCH..."
            gitlab_api PATCH "/projects/$GITLAB_PROJECT_ID/protected_branches/$branch" \
                -d "allow_force_push=false" || true
        fi
    else
        log_warn "  Resposta inesperada (branch pode nao existir ainda): $(echo "$response" | head -c 200)"
    fi
}

# =============================================================================
# Configure project-level merge settings
# =============================================================================
configure_project_merge_settings() {
    log_info "Configurando merge settings do projeto $GITLAB_PROJECT_ID"

    local response
    response=$(gitlab_api PUT "/projects/$GITLAB_PROJECT_ID" \
        -d "merge_requests_access_level=enabled" \
        -d "only_allow_merge_if_pipeline_succeeds=true" \
        -d "only_allow_merge_if_all_discussions_are_resolved=true" \
        -d "remove_source_branch_after_merge=true" \
        -d "squash_option=default_on" \
        -d "merge_method=merge")

    if echo "$response" | grep -q '"id"'; then
        log_success "Merge settings configurados:"
        log_info "  - only_allow_merge_if_pipeline_succeeds = true"
        log_info "  - only_allow_merge_if_all_discussions_are_resolved = true"
        log_info "  - remove_source_branch_after_merge = true"
        log_info "  - squash_option = default_on"
        log_info "  - merge_method = merge"
    else
        log_warn "Falha ao configurar merge settings: $(echo "$response" | head -c 200)"
    fi
}

# =============================================================================
# Try to configure approval rules (Premium-only — graceful fallback for CE)
# =============================================================================
try_configure_approval_rules() {
    local branch="$1"
    local approvals_required="${2:-1}"

    log_info "Tentando configurar approval rules para '$branch' (requer GitLab Premium)..."

    local response
    response=$(gitlab_api POST "/projects/$GITLAB_PROJECT_ID/approval_rules" \
        --header "Content-Type: application/json" \
        -d "{
            \"name\": \"TL Approval for $branch\",
            \"approvals_required\": $approvals_required,
            \"rule_type\": \"regular\"
        }")

    if echo "$response" | grep -q '"id"'; then
        log_success "  Approval rule criada: $approvals_required aprovacao(oes) para '$branch'"
    elif echo "$response" | grep -q '404'; then
        log_warn "  Approval rules nao disponivel (GitLab CE) — usar code review manual por Maintainer"
    else
        log_warn "  Approval rules nao configurada: $(echo "$response" | head -c 200)"
        log_warn "  LIMITACAO GitLab CE: approval_rules requer GitLab Premium/Ultimate"
        log_warn "  WORKAROUND: merge_access_level=40 garante que apenas Maintainers (TLs) podem fazer merge"
    fi
}

# =============================================================================
# Verify protection was applied correctly
# =============================================================================
verify_protection() {
    local branch="$1"

    log_info "Verificando protecao da branch '$branch'..."

    local response
    response=$(gitlab_api GET "/projects/$GITLAB_PROJECT_ID/protected_branches/$branch")

    if echo "$response" | grep -q '"name"'; then
        local push_level merge_level force_push
        push_level=$(echo "$response" | python3 -c "
import json,sys
d=json.load(sys.stdin)
levels=[l.get('access_level',0) for l in d.get('push_access_levels',[])]
print(levels[0] if levels else 'N/A')
" 2>/dev/null || echo "N/A")
        merge_level=$(echo "$response" | python3 -c "
import json,sys
d=json.load(sys.stdin)
levels=[l.get('access_level',0) for l in d.get('merge_access_levels',[])]
print(levels[0] if levels else 'N/A')
" 2>/dev/null || echo "N/A")
        force_push=$(echo "$response" | python3 -c "
import json,sys; print(json.load(sys.stdin).get('allow_force_push','N/A'))
" 2>/dev/null || echo "N/A")

        log_info "  push_access_level:  $push_level (esperado: 0 = No one)"
        log_info "  merge_access_level: $merge_level (esperado: 40 = Maintainers)"
        log_info "  allow_force_push:   $force_push (esperado: False)"

        if [[ "$push_level" == "0" && "$merge_level" == "40" && "$force_push" == "False" ]]; then
            log_success "  Branch '$branch' — protecao CORRETA"
            return 0
        else
            log_warn "  Branch '$branch' — protecao PARCIAL (valores nao correspondem ao esperado)"
            return 1
        fi
    else
        log_warn "  Branch '$branch' nao encontrada ou nao protegida"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"

    log_info "============================================="
    log_info "Branch Protection — ${APP_NAME:-project $GITLAB_PROJECT_ID}"
    log_info "============================================="
    log_info "GitLab URL:    $GITLAB_URL"
    log_info "Project ID:    $GITLAB_PROJECT_ID"
    log_info "App:           ${APP_NAME:-N/A}"
    log_info "Dry-run:       $DRY_RUN"
    echo ""

    # Step 1: Configure project-level merge settings
    configure_project_merge_settings

    echo ""

    # Step 2: Protect 'staging' branch
    # push_access=0 (no one), merge_access=40 (maintainers only)
    protect_branch "staging" "$ACCESS_NO_ONE" "$ACCESS_MAINTAINER"

    # Step 3: Protect 'main' branch
    # push_access=0 (no one), merge_access=40 (maintainers only)
    protect_branch "main" "$ACCESS_NO_ONE" "$ACCESS_MAINTAINER"

    echo ""

    # Step 4: Try approval rules (Premium-only, graceful fallback)
    try_configure_approval_rules "staging" 1
    try_configure_approval_rules "main" 1

    echo ""

    # Step 5: Verify
    if [[ "$DRY_RUN" != "true" ]]; then
        local ok=0 fail=0
        verify_protection "staging" && ok=$((ok+1)) || fail=$((fail+1))
        verify_protection "main"    && ok=$((ok+1)) || fail=$((fail+1))

        echo ""
        log_info "============================================="
        if [[ $fail -eq 0 ]]; then
            log_success "Branch protection COMPLETA: $ok/$((ok+fail)) branches protegidas"
        else
            log_warn "Branch protection PARCIAL: $ok/$((ok+fail)) branches protegidas"
        fi
        log_info "============================================="

        echo ""
        log_info "Resumo de protecao aplicada:"
        log_info "  staging: push=BLOQUEADO, merge=MAINTAINERS, force-push=BLOQUEADO, delete=BLOQUEADO"
        log_info "  main:    push=BLOQUEADO, merge=MAINTAINERS, force-push=BLOQUEADO, delete=BLOQUEADO"
        log_info "  feature/bugfix/hotfix: push=PERMITIDO (sem protecao), MR obrigatorio para staging/main"
        echo ""
        log_info "NOTA GitLab CE: Approval rules (N aprovacoes obrigatorias) requerem GitLab Premium."
        log_info "  Workaround: merge_access_level=40 garante que APENAS Maintainers (TLs) podem"
        log_info "  executar merge, o que equivale a aprovacao TL obrigatoria."
    else
        log_info "[DRY-RUN] Verificacao pulada"
    fi
}

main "$@"
