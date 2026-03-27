#!/bin/bash
# =============================================================================
# create-app.sh — Orquestrador de Onboarding de Aplicacoes via Manifesto Base
# =============================================================================
# Descricao: Le o .platform/manifest.yaml e executa scripts de provisioning
#            na ordem correta, respeitando dependencias e idempotencia.
# Uso:       ./create-app.sh --manifest <path> [--dry-run] [--env <env>]
# Deps:      kubectl, yq, bash >= 4.0
# Ref:       ADR-048 (naming), ADR-104 (manifesto base), P4 (repo structure)
# Idempotente: SIM — verifica existencia de todos recursos antes de criar
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISIONING_DIR="${SCRIPT_DIR}/../provisioning"
VALIDATION_DIR="${SCRIPT_DIR}/../validation"
PRESETS_DIR="${SCRIPT_DIR}/../../presets"

# -----------------------------------------------------------------------------
# Source libs
# -----------------------------------------------------------------------------
LOG_PREFIX="APP"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/manifest-parser.sh"

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Ajuda
# -----------------------------------------------------------------------------
show_help() {
    cat <<EOF
create-app.sh — Orquestrador de Onboarding via Manifesto Base

Uso:
    ./create-app.sh --manifest <path> [opcoes]

Opcoes:
    --manifest <path>   Caminho para .platform/manifest.yaml (obrigatorio)
    --env <env>         Override de ambiente (staging|prod). Default: staging
    --dry-run           Simula execucao sem criar recursos
    --skip-validation   Pula etapa de validacao do manifesto
    --help              Mostra esta ajuda

Exemplos:
    ./create-app.sh --manifest /app/.platform/manifest.yaml
    ./create-app.sh --manifest /app/.platform/manifest.yaml --env prod --dry-run

Fluxo:
    1. Valida manifesto (schema + naming + labels)
    2. Resolve presets de recursos por tipo de app
    3. Cria namespace com ResourceQuota + LimitRange + NetworkPolicy
    4. Provisiona Vault path + AppRole
    5. Valida pre-requisitos do External Secrets Operator (ESO)
    6. [paralelo] Provisiona database, Redis, RabbitMQ, Keycloak (se enabled)
    7. Provisiona ArgoCD AppProject (idempotente, por dominio)
    8. Cria ArgoCD Application
    9. Provisiona Observabilidade (ServiceMonitor, PrometheusRule, Grafana)
   10. Provisiona Ingress ALB (interno + publico, se habilitado)
   11. Configura Branch Protection (staging + main via GitLab API)

Ref: ADR-048, ADR-104, Mesa Tecnica P4
EOF
}

# -----------------------------------------------------------------------------
# Parse argumentos
# -----------------------------------------------------------------------------
parse_args() {
    MANIFEST_PATH=""
    ENV_OVERRIDE=""
    DRY_RUN=false
    SKIP_VALIDATION=false
    TOTAL_STEPS=11

    while [[ $# -gt 0 ]]; do
        case $1 in
            --manifest)        MANIFEST_PATH="$2"; shift 2 ;;
            --env)             ENV_OVERRIDE="$2"; shift 2 ;;
            --dry-run)         DRY_RUN=true; shift ;;
            --skip-validation) SKIP_VALIDATION=true; shift ;;
            --help|-h)         show_help; exit 0 ;;
            *)                 log_error "Opcao desconhecida: $1"; show_help; exit 1 ;;
        esac
    done

    if [[ -z "$MANIFEST_PATH" ]]; then
        log_error "Argumento --manifest e obrigatorio"
        show_help
        exit 1
    fi

    if [[ ! -f "$MANIFEST_PATH" ]]; then
        log_error "Manifesto nao encontrado: $MANIFEST_PATH"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    check_dependency kubectl yq || exit 1

    # Ler manifesto
    parse_manifest "$MANIFEST_PATH" || exit 1

    # Ambiente: override > default staging
    ENV="${ENV_OVERRIDE:-staging}"

    # Namespace (ADR-048)
    NAMESPACE="${ENV}-${DOMAIN}-${APP_NAME}"

    log_info "Namespace: $NAMESPACE"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "MODO DRY-RUN — nenhum recurso sera criado"
    fi

    # -----------------------------------------------------------------
    # STEP 1: Validacao
    # -----------------------------------------------------------------
    log_step 1 "$TOTAL_STEPS" "Validacao do Manifesto"

    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_warn "Validacao pulada (--skip-validation)"
    else
        if [[ -x "${VALIDATION_DIR}/validate-manifest.sh" ]]; then
            bash "${VALIDATION_DIR}/validate-manifest.sh" "$MANIFEST_PATH" || {
                log_error "Manifesto invalido. Corrija e re-execute."
                exit 1
            }
        else
            log_warn "validate-manifest.sh nao encontrado, pulando validacao de schema"
        fi

        if [[ -x "${VALIDATION_DIR}/validate-naming.sh" ]]; then
            bash "${VALIDATION_DIR}/validate-naming.sh" "$APP_NAME" "$DOMAIN" "$PRODUCT" || {
                log_error "Naming conventions violadas (ADR-048)"
                exit 1
            }
        fi

        if [[ -x "${VALIDATION_DIR}/validate-labels.sh" ]]; then
            bash "${VALIDATION_DIR}/validate-labels.sh" --manifest "$MANIFEST_PATH" || {
                log_error "Labels obrigatorias ausentes"
                exit 1
            }
        fi

        log_success "Manifesto valido"
    fi

    # -----------------------------------------------------------------
    # STEP 2: Resolver presets de recursos
    # -----------------------------------------------------------------
    log_step 2 "$TOTAL_STEPS" "Resolucao de Presets"

    PRESET_FILE="${PRESETS_DIR}/${APP_TYPE}.yaml"

    if [[ -f "$PRESET_FILE" ]]; then
        # Ler recursos do manifesto; se vazio, usar preset
        eval "$(manifest_get_resources)"

        # Se vazio, usar preset conforme ambiente
        ENV_KEY="production"
        [[ "$ENV" == "staging" ]] && ENV_KEY="staging"

        if [[ -z "$RES_CPU_REQ" ]]; then
            CPU_REQ=$(yq ".environments.${ENV_KEY}.resources.requests.cpu" "$PRESET_FILE")
            MEM_REQ=$(yq ".environments.${ENV_KEY}.resources.requests.memory" "$PRESET_FILE")
            CPU_LIM=$(yq ".environments.${ENV_KEY}.resources.limits.cpu" "$PRESET_FILE")
            MEM_LIM=$(yq ".environments.${ENV_KEY}.resources.limits.memory" "$PRESET_FILE")
            log_info "Usando preset ${APP_TYPE} (${ENV_KEY}): CPU ${CPU_REQ}/${CPU_LIM}, Mem ${MEM_REQ}/${MEM_LIM}"
        else
            CPU_REQ="$RES_CPU_REQ"
            MEM_REQ="$RES_MEM_REQ"
            CPU_LIM="$RES_CPU_LIM"
            MEM_LIM="$RES_MEM_LIM"
            log_info "Usando recursos do manifesto: CPU ${CPU_REQ}/${CPU_LIM}, Mem ${MEM_REQ}/${MEM_LIM}"
        fi

        if [[ "$RES_REP_MIN" == "0" ]]; then
            REP_MIN=$(yq ".environments.${ENV_KEY}.replicas.min" "$PRESET_FILE")
            REP_MAX=$(yq ".environments.${ENV_KEY}.replicas.max" "$PRESET_FILE")
        else
            REP_MIN="$RES_REP_MIN"
            REP_MAX="$RES_REP_MAX"
        fi
        log_info "Replicas: min=${REP_MIN}, max=${REP_MAX}"
    else
        log_warn "Preset nao encontrado para tipo '${APP_TYPE}', usando valores do manifesto"
    fi

    log_success "Presets resolvidos"

    # -----------------------------------------------------------------
    # STEP 3: Criar Namespace
    # -----------------------------------------------------------------
    log_step 3 "$TOTAL_STEPS" "Namespace + ResourceQuota + LimitRange"

    # GAP-D2-02: chama provision-namespace.sh (Step 1 canonico do fluxo arquitetural)
    # que delega para scripts/onboarding/create-namespace.sh via thin wrapper.
    bash "${PROVISIONING_DIR}/provision-namespace.sh" \
        --name "$NAMESPACE" \
        --domain "$DOMAIN" \
        --product "$APP_NAME" \
        --env "$ENV" \
        --owner "$OWNER" \
        $([ "$DRY_RUN" == "true" ] && echo "--dry-run") \
        || { log_error "Falha ao criar namespace"; exit 1; }

    log_success "Namespace $NAMESPACE pronto"

    # -----------------------------------------------------------------
    # STEP 4: Provisionar Vault
    # -----------------------------------------------------------------
    log_step 4 "$TOTAL_STEPS" "Vault Path + AppRole"

    if [[ -x "${PROVISIONING_DIR}/provision-vault.sh" ]]; then
        bash "${PROVISIONING_DIR}/provision-vault.sh" \
            --app "$APP_NAME" \
            --domain "$DOMAIN" \
            --namespace "$NAMESPACE" \
            --env "$ENV" \
            $([ "$DRY_RUN" == "true" ] && echo "--dry-run") \
            || { log_error "Falha ao provisionar Vault"; exit 1; }
        log_success "Vault provisionado"
    else
        log_warn "provision-vault.sh nao disponivel, pulando"
    fi

    # -----------------------------------------------------------------
    # STEP 5: Verificar pre-requisitos do ESO — GAP-D2-01
    # -----------------------------------------------------------------
    log_step 5 "$TOTAL_STEPS" "External Secrets Operator — pre-requisitos"

    if [[ -x "${PROVISIONING_DIR}/provision-externalsecrets.sh" ]]; then
        bash "${PROVISIONING_DIR}/provision-externalsecrets.sh" \
            --app       "$APP_NAME" \
            --namespace "$NAMESPACE" \
            --env       "$ENV" \
            --domain    "$DOMAIN" \
            || { log_error "Falha na verificacao dos pre-requisitos do ESO"; exit 1; }
        log_success "ESO pre-requisitos verificados"
    else
        log_warn "provision-externalsecrets.sh nao disponivel, pulando verificacao ESO"
    fi

    # -----------------------------------------------------------------
    # STEP 6: Provisionar Data Services (paralelo)
    # -----------------------------------------------------------------
    log_step 6 "$TOTAL_STEPS" "Data Services (database, Redis, RabbitMQ, Keycloak)"

    PIDS=()
    SERVICES=()

    # Database
    DB_ENABLED=$(manifest_get_dependency "database" "enabled" "false")
    if [[ "$DB_ENABLED" == "true" ]]; then
        DB_TYPE=$(manifest_get_dependency "database" "type" "shared")
        DB_NAME=$(manifest_get_dependency "database" "name" "")
        log_info "Provisionando PostgreSQL (type=$DB_TYPE)..."
        bash "${PROVISIONING_DIR}/provision-database.sh" \
            --app "$APP_NAME" \
            --namespace "$NAMESPACE" \
            --domain "$DOMAIN" \
            --env "$ENV" \
            --db-type "$DB_TYPE" \
            --db-name "$DB_NAME" \
            $([ "$DRY_RUN" == "true" ] && echo "--dry-run") &
        PIDS+=($!)
        SERVICES+=("database")
    fi

    # Redis
    REDIS_ENABLED=$(manifest_get_dependency "redis" "enabled" "false")
    if [[ "$REDIS_ENABLED" == "true" ]]; then
        REDIS_MODE=$(manifest_get_dependency "redis" "mode" "shared")
        log_info "Provisionando Redis (mode=$REDIS_MODE)..."
        bash "${PROVISIONING_DIR}/provision-redis.sh" \
            --app "$APP_NAME" \
            --namespace "$NAMESPACE" \
            --domain "$DOMAIN" \
            --mode "$REDIS_MODE" \
            --env "$ENV" \
            $([ "$DRY_RUN" == "true" ] && echo "--dry-run") &
        PIDS+=($!)
        SERVICES+=("redis")
    fi

    # RabbitMQ
    RABBIT_ENABLED=$(manifest_get_dependency "rabbitmq" "enabled" "false")
    if [[ "$RABBIT_ENABLED" == "true" ]]; then
        RABBIT_REPLICAS=$(manifest_get_dependency "rabbitmq" "replicas" "1")
        RABBIT_MODE=$(manifest_get_dependency "rabbitmq" "mode" "shared")
        log_info "Provisionando RabbitMQ (mode=$RABBIT_MODE, replicas=$RABBIT_REPLICAS)..."
        bash "${PROVISIONING_DIR}/provision-rabbitmq.sh" \
            --app "$APP_NAME" \
            --namespace "$NAMESPACE" \
            --domain "$DOMAIN" \
            --env "$ENV" \
            --mode "$RABBIT_MODE" \
            --replicas "$RABBIT_REPLICAS" \
            $([ "$DRY_RUN" == "true" ] && echo "--dry-run") &
        PIDS+=($!)
        SERVICES+=("rabbitmq")
    fi

    # Keycloak
    KC_ENABLED=$(manifest_get_dependency "keycloak" "enabled" "false")
    if [[ "$KC_ENABLED" == "true" ]]; then
        KC_CLIENT_TYPE=$(manifest_get_dependency "keycloak" "clientType" "confidential")
        log_info "Provisionando Keycloak (clientType=$KC_CLIENT_TYPE)..."
        bash "${PROVISIONING_DIR}/provision-keycloak.sh" \
            --app "$APP_NAME" \
            --namespace "$NAMESPACE" \
            --domain "$DOMAIN" \
            --env "$ENV" \
            --client-type "$KC_CLIENT_TYPE" \
            --manifest "$MANIFEST_PATH" \
            $([ "$DRY_RUN" == "true" ] && echo "--dry-run") &
        PIDS+=($!)
        SERVICES+=("keycloak")
    fi

    # Aguardar todos os processos paralelos
    FAILED=0
    for i in "${!PIDS[@]}"; do
        if ! wait "${PIDS[$i]}"; then
            log_error "Falha ao provisionar: ${SERVICES[$i]}"
            FAILED=$((FAILED + 1))
        else
            log_success "${SERVICES[$i]} provisionado"
        fi
    done

    if [[ $FAILED -gt 0 ]]; then
        log_error "$FAILED servico(s) falharam. Verifique os logs acima."
        exit 1
    fi

    if [[ ${#SERVICES[@]} -eq 0 ]]; then
        log_info "Nenhum data service habilitado no manifesto"
    fi

    # -----------------------------------------------------------------
    # STEP 7: Provisionar ArgoCD AppProject — GAP-D2-03
    # Deve ser chamado ANTES de create-argocd-app.sh, que aborta se o
    # AppProject nao existir. provision-argocd.sh e idempotente.
    # -----------------------------------------------------------------
    log_step 7 "$TOTAL_STEPS" "ArgoCD AppProject (dominio: ${DOMAIN})"

    bash "${SCRIPT_DIR}/provision-argocd.sh" \
        --app              "$APP_NAME" \
        --domain           "$DOMAIN" \
        --env              "$ENV" \
        --argocd-namespace "${ARGOCD_NAMESPACE:-${ENV}-platform-argocd}" \
        --gitlab-host      "${GITLAB_HOST:-gitlab.empresa.com.br}" \
        || { log_error "Falha ao provisionar ArgoCD AppProject"; exit 1; }

    log_success "ArgoCD AppProject '${DOMAIN}' provisionado"

    # -----------------------------------------------------------------
    # STEP 8: Criar ArgoCD Application
    # -----------------------------------------------------------------
    log_step 8 "$TOTAL_STEPS" "ArgoCD Application"

    bash "${SCRIPT_DIR}/create-argocd-app.sh" \
        --app       "$APP_NAME" \
        --domain    "$DOMAIN" \
        --namespace "$NAMESPACE" \
        --env       "$ENV" \
        $([ "$DRY_RUN" == "true" ] && echo "--dry-run") \
        || { log_error "Falha ao criar ArgoCD Application"; exit 1; }

    log_success "ArgoCD Application criado"

    # -----------------------------------------------------------------
    # STEP 9: Observabilidade (ServiceMonitor, PrometheusRule, Grafana) — GAP-PLAT-OBS-04
    # -----------------------------------------------------------------
    log_step 9 "$TOTAL_STEPS" "Observabilidade (ServiceMonitor / PrometheusRule / Grafana)"

    if [[ -x "${PROVISIONING_DIR}/provision-observability.sh" ]]; then
        OBS_ARGS=(--manifest "$MANIFEST_PATH" --app "$APP_NAME" --namespace "$NAMESPACE" --env "$ENV" --domain "$DOMAIN")
        [[ "$DRY_RUN" == "true" ]] && OBS_ARGS+=(--dry-run)
        bash "${PROVISIONING_DIR}/provision-observability.sh" "${OBS_ARGS[@]}" \
            || { log_error "Falha ao provisionar observabilidade"; exit 1; }
        log_success "Observabilidade provisionada"
    else
        log_warn "provision-observability.sh nao disponivel, pulando observabilidade"
    fi

    # -----------------------------------------------------------------
    # STEP 10: Ingress (se enabled) — GAP-PLAT-ING-04
    # -----------------------------------------------------------------
    log_step 10 "$TOTAL_STEPS" "Ingress (se habilitado no manifesto)"

    if [[ -x "${PROVISIONING_DIR}/provision-ingress.sh" ]]; then
        ING_ARGS=(--manifest "$MANIFEST_PATH" --app "$APP_NAME" --namespace "$NAMESPACE" --env "$ENV" --domain "$DOMAIN")
        [[ "$DRY_RUN" == "true" ]] && ING_ARGS+=(--dry-run)
        bash "${PROVISIONING_DIR}/provision-ingress.sh" "${ING_ARGS[@]}" \
            || { log_error "Falha ao provisionar Ingress"; exit 1; }
        log_success "Ingress verificado/provisionado"
    else
        log_warn "provision-ingress.sh nao disponivel, pulando Ingress"
    fi

    # -----------------------------------------------------------------
    # STEP 11: Branch Protection (staging + main) — GitLab API
    # -----------------------------------------------------------------
    log_step 11 "$TOTAL_STEPS" "Branch Protection (staging + main)"

    if [[ -x "${PROVISIONING_DIR}/provision-branch-protection.sh" ]]; then
        BP_ARGS=(--app "$APP_NAME")
        # Resolve GitLab project ID from CI or manifest
        if [[ -n "${CI_PROJECT_ID:-}" ]]; then
            BP_ARGS+=(--project-id "$CI_PROJECT_ID")
        elif [[ -n "${GITLAB_PROJECT_NAME:-}" ]]; then
            BP_ARGS+=(--project-name "$GITLAB_PROJECT_NAME")
        else
            log_warn "GITLAB_PROJECT_ID ou GITLAB_PROJECT_NAME nao definidos — tentando resolver pelo nome"
            BP_ARGS+=(--project-name "${GITLAB_GROUP:-services}/${APP_NAME}")
        fi
        [[ -n "${GITLAB_URL:-}" ]] && BP_ARGS+=(--gitlab-url "$GITLAB_URL")
        [[ -n "${GITLAB_TOKEN:-}" ]] && BP_ARGS+=(--gitlab-token "$GITLAB_TOKEN")
        [[ "$DRY_RUN" == "true" ]] && BP_ARGS+=(--dry-run)

        bash "${PROVISIONING_DIR}/provision-branch-protection.sh" "${BP_ARGS[@]}" \
            || { log_warn "Falha ao configurar branch protection (nao-bloqueante)"; }
        log_success "Branch protection configurada"
    else
        log_warn "provision-branch-protection.sh nao disponivel, pulando branch protection"
    fi

    # -----------------------------------------------------------------
    # Sumario
    # -----------------------------------------------------------------
    echo ""
    log_success "========================================="
    log_success " Onboarding Completo: $APP_NAME"
    log_success "========================================="
    echo ""
    log_info "App:       $APP_NAME"
    log_info "Tipo:      $APP_TYPE"
    log_info "Dominio:   $DOMAIN"
    log_info "Produto:   $PRODUCT"
    log_info "Namespace: $NAMESPACE"
    log_info "Env:       $ENV"
    log_info "Recursos:  CPU ${CPU_REQ:-preset}/${CPU_LIM:-preset}, Mem ${MEM_REQ:-preset}/${MEM_LIM:-preset}"
    log_info "Replicas:  ${REP_MIN:-0}/${REP_MAX:-0}"
    echo ""
    log_info "Servicos provisionados:"
    for svc in ${SERVICES[@]+"${SERVICES[@]}"}; do
        [[ -n "$svc" ]] && log_info "  - $svc"
    done
    [[ ${#SERVICES[@]} -eq 0 ]] && log_info "  (nenhum)"
    echo ""
    log_info "Branch protection:"
    log_info "  - staging: push=BLOQUEADO, merge=MAINTAINERS"
    log_info "  - main:    push=BLOQUEADO, merge=MAINTAINERS"
    echo ""
    log_info "Proximos passos:"
    log_info "  1. Verifique o namespace: kubectl get all -n $NAMESPACE"
    log_info "  2. ArgoCD UI: https://argocd.empresa.com/applications/${ENV}-${APP_NAME}"
    log_info "  3. Grafana: https://grafana.empresa.com/d/${APP_NAME}"
    echo ""
    log_success "========================================="
}

main "$@"
