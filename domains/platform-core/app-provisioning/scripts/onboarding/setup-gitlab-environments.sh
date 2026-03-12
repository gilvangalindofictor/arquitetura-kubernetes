#!/bin/bash
# =============================================================================
# setup-gitlab-environments.sh — Configura environments e protection rules
#                                 no GitLab via API
# =============================================================================
# Descricao: Script generico e idempotente para configurar environments
#            (staging/production) e suas protection rules em qualquer projeto
#            GitLab. Aplica as politicas definidas em ADR-104 e resolve GAP-017.
#
# Uso:
#   ./setup-gitlab-environments.sh --project-path "grupo/projeto" --env all
#   ./setup-gitlab-environments.sh --project-id 42 --env production --approvers "10,20"
#
# Deps:     curl, jq, bash >= 4.0
# Env vars: GITLAB_TOKEN (obrigatorio), GITLAB_URL (default: gitlab.empresa.com.br)
# Ref:      ADR-104 (deploy em producao requer aprovacao manual)
#           GAP-017 (environment protection rules para producao nao configuradas)
# Idempotente: SIM — verifica existencia antes de criar/atualizar
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Source libs
# -----------------------------------------------------------------------------
LOG_PREFIX="ENV-SETUP"
source "${SCRIPT_DIR}/../lib/common.sh"

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
GITLAB_URL="${GITLAB_URL:-https://gitlab.empresa.com.br}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
PROJECT_ID=""
PROJECT_PATH=""
TARGET_ENV="all"
APPROVER_IDS=""
DRY_RUN="false"

# -----------------------------------------------------------------------------
# Ajuda
# -----------------------------------------------------------------------------
show_help() {
    cat <<EOF
setup-gitlab-environments.sh — Configura GitLab environment protection rules

Uso:
    ./setup-gitlab-environments.sh [opcoes]

Opcoes:
    --project-id <id>         ID numerico do projeto GitLab
    --project-path <path>     Path do projeto (ex: "grupo/subgrupo/projeto")
                              (um dos dois e obrigatorio: --project-id ou --project-path)
    --env <staging|production|all>
                              Qual environment configurar (default: all)
    --approvers <user_ids>    IDs de usuarios aprovadores para production
                              (virgula-separados, ex: "10,20,30")
    --dry-run                 Simula execucao sem criar/alterar recursos
    --help                    Mostra esta ajuda

Variaveis de ambiente:
    GITLAB_TOKEN   Token de acesso com permissao api (obrigatorio)
    GITLAB_URL     URL do GitLab (default: https://gitlab.empresa.com.br)

Exemplos:
    # Configurar staging + production para um projeto por path
    export GITLAB_TOKEN="glpat-xxx"
    ./setup-gitlab-environments.sh --project-path "data/hatch-etl" --env all

    # Configurar apenas production com aprovadores especificos
    ./setup-gitlab-environments.sh --project-id 42 --env production --approvers "10,20"

    # Dry-run para validar antes de aplicar
    ./setup-gitlab-environments.sh --project-path "data/hatch-etl" --env all --dry-run

Ref: ADR-104, GAP-017
EOF
}

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --project-path)
                PROJECT_PATH="$2"
                shift 2
                ;;
            --env)
                TARGET_ENV="$2"
                shift 2
                ;;
            --approvers)
                APPROVER_IDS="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Opcao desconhecida: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Validacoes
# -----------------------------------------------------------------------------
validate_inputs() {
    # Obter GITLAB_TOKEN do Vault se nao fornecido explicitamente
    if [[ -z "${GITLAB_TOKEN:-}" ]]; then
        source "${SCRIPT_DIR}/../lib/vault-auth.sh"
        vault_k8s_login
        # GAP-A6-01 (2026-03-12): quando TARGET_ENV=all, usar 'staging' para lookup do Vault
        # GITLAB_TOKEN é único por instância GitLab — não específico por ambiente
        VAULT_ENV="${TARGET_ENV}"
        if [[ "${TARGET_ENV}" == "all" ]]; then
            VAULT_ENV="staging"
        fi
        GITLAB_TOKEN=$(vault kv get -field=gitlab-api-token \
            "secret/${VAULT_ENV}/platform/integrations/gitlab" 2>/dev/null || true)
        if [[ -z "${GITLAB_TOKEN:-}" ]]; then
            log_error "GITLAB_TOKEN nao fornecido e nao encontrado no Vault"
            log_error "Configure: vault kv put secret/${VAULT_ENV}/platform/integrations/gitlab gitlab-api-token=<token>"
            exit 1
        fi
    fi

    if [[ -z "${PROJECT_ID}" && -z "${PROJECT_PATH}" ]]; then
        log_error "Informe --project-id ou --project-path."
        show_help
        exit 1
    fi

    if [[ "${TARGET_ENV}" != "staging" && "${TARGET_ENV}" != "production" && "${TARGET_ENV}" != "all" ]]; then
        log_error "Valor invalido para --env: '${TARGET_ENV}'. Use staging, production ou all."
        exit 1
    fi

    # Verificar dependencias
    for cmd in curl jq; do
        if ! command -v "${cmd}" &>/dev/null; then
            log_error "Dependencia nao encontrada: ${cmd}"
            exit 1
        fi
    done
}

# -----------------------------------------------------------------------------
# Helpers — GitLab API
# -----------------------------------------------------------------------------
gitlab_api() {
    local method="$1"
    local endpoint="$2"
    shift 2
    local data="${1:-}"

    local url="${GITLAB_URL}/api/v4${endpoint}"

    local args=(
        --silent
        --show-error
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}"
        --header "Content-Type: application/json"
        --request "${method}"
    )

    if [[ -n "${data}" ]]; then
        args+=(--data "${data}")
    fi

    curl "${args[@]}" "${url}"
}

# Resolve project path para project ID se necessario
resolve_project_id() {
    if [[ -n "${PROJECT_ID}" ]]; then
        log_info "Usando project ID: ${PROJECT_ID}"
        return
    fi

    log_info "Resolvendo project path '${PROJECT_PATH}' para ID..."
    local encoded_path
    encoded_path=$(printf '%s' "${PROJECT_PATH}" | jq -sRr @uri)

    local response
    response=$(gitlab_api GET "/projects/${encoded_path}")

    PROJECT_ID=$(echo "${response}" | jq -r '.id // empty')

    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Projeto nao encontrado: ${PROJECT_PATH}"
        log_error "Resposta da API: ${response}"
        exit 1
    fi

    log_info "Project ID resolvido: ${PROJECT_ID}"
}

# -----------------------------------------------------------------------------
# Environment — criar ou verificar existencia
# -----------------------------------------------------------------------------
ensure_environment() {
    local env_name="$1"

    log_info "Verificando environment '${env_name}' no projeto ${PROJECT_ID}..."

    # Listar environments existentes e buscar pelo nome
    local response
    response=$(gitlab_api GET "/projects/${PROJECT_ID}/environments?search=${env_name}")

    local env_id
    env_id=$(echo "${response}" | jq -r ".[] | select(.name == \"${env_name}\") | .id // empty")

    if [[ -n "${env_id}" ]]; then
        log_info "Environment '${env_name}' ja existe (ID: ${env_id})"
        echo "${env_id}"
        return
    fi

    # Criar environment
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "[DRY-RUN] Criaria environment '${env_name}'"
        echo "dry-run"
        return
    fi

    log_info "Criando environment '${env_name}'..."
    local create_response
    create_response=$(gitlab_api POST "/projects/${PROJECT_ID}/environments" \
        "{\"name\": \"${env_name}\"}")

    env_id=$(echo "${create_response}" | jq -r '.id // empty')

    if [[ -z "${env_id}" ]]; then
        log_error "Falha ao criar environment '${env_name}'"
        log_error "Resposta: ${create_response}"
        exit 1
    fi

    log_info "Environment '${env_name}' criado (ID: ${env_id})"
    echo "${env_id}"
}

# -----------------------------------------------------------------------------
# Protected Environment — configurar protection rules
# -----------------------------------------------------------------------------
check_protected_environment() {
    local env_name="$1"

    local response
    response=$(gitlab_api GET "/projects/${PROJECT_ID}/protected_environments/${env_name}" 2>/dev/null || echo "{}")

    local name
    name=$(echo "${response}" | jq -r '.name // empty')

    if [[ "${name}" == "${env_name}" ]]; then
        return 0  # existe
    fi
    return 1  # nao existe
}

unprotect_environment() {
    local env_name="$1"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "[DRY-RUN] Removeria protecao de '${env_name}' para recriar"
        return
    fi

    log_info "Removendo protecao existente de '${env_name}' para recriar com novas regras..."
    gitlab_api DELETE "/projects/${PROJECT_ID}/protected_environments/${env_name}" >/dev/null 2>&1 || true
}

# -----------------------------------------------------------------------------
# Setup Staging Environment
# -----------------------------------------------------------------------------
setup_staging() {
    log_info "=== Configurando environment STAGING ==="

    # Garantir que o environment existe
    ensure_environment "staging" >/dev/null

    # Verificar se ja esta protegido
    if check_protected_environment "staging"; then
        log_info "Environment 'staging' ja esta protegido. Recriando com regras atualizadas..."
        unprotect_environment "staging"
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "[DRY-RUN] Protegeria environment 'staging' com:"
        log_warn "  - required_approvals: 0 (auto-deploy)"
        log_warn "  - allowed_to_deploy: developer, maintainer"
        return
    fi

    # Proteger staging: sem aprovacao, developer+maintainer podem deployar
    # Ref: ADR-104 — staging e auto-deploy
    local payload
    payload=$(cat <<'ENDJSON'
{
    "name": "staging",
    "deploy_access_levels": [
        {"access_level": 30},
        {"access_level": 40}
    ],
    "required_approval_count": 0
}
ENDJSON
)

    local response
    response=$(gitlab_api POST "/projects/${PROJECT_ID}/protected_environments" "${payload}")

    local protected_name
    protected_name=$(echo "${response}" | jq -r '.name // empty')

    if [[ "${protected_name}" == "staging" ]]; then
        log_info "Environment 'staging' protegido com sucesso"
        log_info "  - required_approvals: 0 (auto-deploy)"
        log_info "  - deploy_access_levels: developer (30), maintainer (40)"
    else
        log_error "Falha ao proteger environment 'staging'"
        log_error "Resposta: ${response}"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Setup Production Environment (ADR-104, GAP-017)
# -----------------------------------------------------------------------------
setup_production() {
    log_info "=== Configurando environment PRODUCTION (ADR-104) ==="

    # Garantir que o environment existe
    ensure_environment "production" >/dev/null

    # Verificar se ja esta protegido
    if check_protected_environment "production"; then
        log_info "Environment 'production' ja esta protegido. Recriando com regras atualizadas..."
        unprotect_environment "production"
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "[DRY-RUN] Protegeria environment 'production' com:"
        log_warn "  - required_approvals: 1 (ADR-104)"
        log_warn "  - allowed_to_deploy: maintainer"
        log_warn "  - allowed_to_approve: maintainer"
        if [[ -n "${APPROVER_IDS}" ]]; then
            log_warn "  - approver_user_ids: ${APPROVER_IDS}"
        fi
        return
    fi

    # Construir payload para production
    # Ref: ADR-104 — producao requer 1 aprovacao de maintainer
    # Ref: GAP-017 — correcao da ausencia de protection rules
    local payload
    payload=$(jq -n \
        --arg name "production" \
        --argjson required_approval_count 1 \
        '{
            name: $name,
            deploy_access_levels: [
                {"access_level": 40}
            ],
            approval_rules: [
                {
                    "access_level": 40,
                    "required_approvals": 1
                }
            ],
            required_approval_count: $required_approval_count
        }')

    # Adicionar aprovadores especificos se fornecidos
    if [[ -n "${APPROVER_IDS}" ]]; then
        local user_ids_array
        user_ids_array=$(echo "${APPROVER_IDS}" | tr ',' '\n' | jq -R 'tonumber' | jq -s '.')

        payload=$(echo "${payload}" | jq \
            --argjson user_ids "${user_ids_array}" \
            '.approval_rules[0].user_id = $user_ids[0] |
             if ($user_ids | length) > 1 then
               .approval_rules += [{"user_id": $user_ids[1], "required_approvals": 1}]
             else . end')
    fi

    local response
    response=$(gitlab_api POST "/projects/${PROJECT_ID}/protected_environments" "${payload}")

    local protected_name
    protected_name=$(echo "${response}" | jq -r '.name // empty')

    if [[ "${protected_name}" == "production" ]]; then
        log_info "Environment 'production' protegido com sucesso (ADR-104)"
        log_info "  - required_approvals: 1"
        log_info "  - deploy_access_levels: maintainer (40)"
        log_info "  - approval_rules: maintainer (40)"
        if [[ -n "${APPROVER_IDS}" ]]; then
            log_info "  - approver_user_ids: ${APPROVER_IDS}"
        fi
    else
        log_error "Falha ao proteger environment 'production'"
        log_error "Resposta: ${response}"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"
    validate_inputs
    resolve_project_id

    log_info "Configurando environments para projeto ID=${PROJECT_ID}"
    log_info "Target env: ${TARGET_ENV} | Dry-run: ${DRY_RUN}"
    log_info "GitLab URL: ${GITLAB_URL}"

    case "${TARGET_ENV}" in
        staging)
            setup_staging
            ;;
        production)
            setup_production
            ;;
        all)
            setup_staging
            setup_production
            ;;
    esac

    echo ""
    log_info "=========================================="
    log_info " Environment setup CONCLUIDO (GAP-017)"
    log_info "=========================================="
    log_info ""
    log_info "Verifique em: ${GITLAB_URL}/${PROJECT_PATH:-projeto}/-/settings/ci_cd#js-environments"
    log_info ""

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "*** DRY-RUN — nenhuma alteracao foi aplicada ***"
    fi
}

main "$@"
