#!/bin/bash
# =============================================================================
# provision-vault.sh — Provisiona Vault KV path + policy + AppRole (idempotente)
# =============================================================================
# Descricao: Cria path KV v2, policy least-privilege e AppRole para a app.
#            Configura Kubernetes Auth method para o namespace.
# Uso:       ./provision-vault.sh --app <name> --domain <d> --namespace <ns> --env <e>
# Deps:      vault (CLI)
# Ref:       P8 (ServiceAccount), ADR-104
# Idempotente: SIM — vault policy write e auth tune sao idempotentes
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="VAULT"
source "${SCRIPT_DIR}/../lib/common.sh"

# Source vault-auth.sh — Kubernetes Auth para token dinamico
if [[ -f "${SCRIPT_DIR}/../lib/vault-auth.sh" ]]; then
    # shellcheck source=../lib/vault-auth.sh
    source "${SCRIPT_DIR}/../lib/vault-auth.sh"
else
    log_error "vault-auth.sh nao encontrado em ${SCRIPT_DIR}/../lib"
    log_error "Biblioteca de autenticacao Vault e obrigatoria"
    exit 1
fi

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Parse argumentos
# -----------------------------------------------------------------------------
parse_args() {
    APP_NAME="" DOMAIN="" NAMESPACE="" ENV="" DRY_RUN=false
    SA_NAME="platform-provisioner"
    SA_NAMESPACE="platform-system"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --app)       APP_NAME="$2"; shift 2 ;;
            --domain)    DOMAIN="$2"; shift 2 ;;
            --namespace) NAMESPACE="$2"; shift 2 ;;
            --env)       ENV="$2"; shift 2 ;;
            --dry-run)   DRY_RUN=true; shift ;;
            *) log_error "Opcao desconhecida: $1"; exit 1 ;;
        esac
    done

    validate_required_args APP_NAME DOMAIN NAMESPACE ENV || exit 1
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    if ! command -v vault &>/dev/null; then
        log_warn "Vault CLI nao disponivel — pulando provisioning de Vault"
        exit 0
    fi

    # Autenticacao Vault via Kubernetes Auth (token dinamico, TTL curto)
    # Ref: GAP-009 — eliminar VAULT_TOKEN estatico
    log_info "Autenticando no Vault via Kubernetes Auth..."

    export ENV DOMAIN APP_NAME

    vault_k8s_login --role "platform-provisioner-${ENV}" || {
        log_error "Falha na autenticacao Vault — abortando provisioning"
        exit 1
    }

    # Garantir revogacao do token ao sair
    register_cleanup vault_token_revoke

    VAULT_BASE_PATH="secret/${ENV}/${DOMAIN}/${APP_NAME}"
    POLICY_NAME="${ENV}-${APP_NAME}-policy"
    ROLE_NAME="${ENV}-${APP_NAME}-role"

    log_info "Vault path: $VAULT_BASE_PATH | Policy: $POLICY_NAME | Role: $ROLE_NAME"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Criaria KV path, policy e Kubernetes auth role"
        exit 0
    fi

    # Criar KV paths (idempotente)
    log_info "Inicializando KV paths..."

    vault kv metadata put -custom-metadata="domain=${DOMAIN}" \
        -custom-metadata="app=${APP_NAME}" \
        -custom-metadata="env=${ENV}" \
        -custom-metadata="created-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "secret/${ENV}/${DOMAIN}/${APP_NAME}/config" 2>/dev/null || true

    vault kv metadata put -custom-metadata="domain=${DOMAIN}" \
        -custom-metadata="env=${ENV}" \
        "secret/${ENV}/${DOMAIN}/${APP_NAME}/redis" 2>/dev/null || true

    vault kv metadata put -custom-metadata="domain=${DOMAIN}" \
        -custom-metadata="env=${ENV}" \
        "secret/${ENV}/${DOMAIN}/${APP_NAME}/postgres" 2>/dev/null || true

    vault kv metadata put -custom-metadata="domain=${DOMAIN}" \
        -custom-metadata="env=${ENV}" \
        "secret/${ENV}/${DOMAIN}/${APP_NAME}/rabbitmq" 2>/dev/null || true

    log_success "KV paths inicializados"

    # Policy (idempotente)
    log_info "Criando policy: $POLICY_NAME"

    vault policy write "$POLICY_NAME" - <<EOF
# Policy para ${APP_NAME} (${DOMAIN}) — env: ${ENV}
# Gerado por platform-provisioner — NAO editar manualmente

# App config
path "secret/data/${ENV}/${DOMAIN}/${APP_NAME}/*" {
  capabilities = ["read", "list"]
}

# Metadata (read-only)
path "secret/metadata/${ENV}/${DOMAIN}/${APP_NAME}/*" {
  capabilities = ["read", "list"]
}
EOF

    log_success "Policy criada"

    # Kubernetes Auth Role (idempotente)
    log_info "Criando Kubernetes auth role: $ROLE_NAME"

    vault write "auth/kubernetes/role/${ROLE_NAME}" \
        bound_service_account_names="${APP_NAME}" \
        bound_service_account_namespaces="${NAMESPACE}" \
        policies="${POLICY_NAME}" \
        ttl="1h" \
        max_ttl="4h"

    log_success "Kubernetes auth role criado"

    # Validar ServiceAccount platform-provisioner (GAP-008)
    log_info "Validando ServiceAccount ${SA_NAME} em ${SA_NAMESPACE}..."

    if command -v kubectl &>/dev/null; then
        if ! resource_exists serviceaccount "${SA_NAME}" "${SA_NAMESPACE}"; then
            log_error "============================================================"
            log_error "ERRO CRITICO: ServiceAccount '${SA_NAME}' NAO encontrado"
            log_error "  Namespace esperado: ${SA_NAMESPACE}"
            log_error "  O Vault Kubernetes Auth role para o provisioner requer"
            log_error "  que o SA exista no cluster."
            log_error ""
            log_error "SOLUCAO: Execute o bootstrap antes do provisioning:"
            log_error "  ./bootstrap-provisioner.sh --sa-namespace ${SA_NAMESPACE}"
            log_error "============================================================"
            exit 1
        fi
        log_success "ServiceAccount ${SA_NAME} validado em ${SA_NAMESPACE}"
    else
        log_warn "kubectl nao disponivel — pulando validacao do SA (assume existente)"
    fi

    # Platform provisioner per-app policy (para pipeline CI — P8)
    PROVISIONER_APP_POLICY="platform-provisioner-${ENV}-${APP_NAME}"

    vault policy write "$PROVISIONER_APP_POLICY" - <<EOF
# Policy para platform-provisioner criar/atualizar secrets de ${APP_NAME} — env: ${ENV}

path "secret/data/${ENV}/${DOMAIN}/${APP_NAME}/*" {
  capabilities = ["create", "read", "update", "list"]
}
EOF

    log_success "Provisioner app policy criada: $PROVISIONER_APP_POLICY"

    # Platform Provisioner Role + Policy (Kubernetes Auth — pipeline CI)
    # Ref: GAP-009 — role do provisioner para auth via K8s JWT (token dinamico)
    PLATFORM_PROVISIONER_ROLE="platform-provisioner-${ENV}"
    PLATFORM_PROVISIONER_POLICY="platform-provisioner-${ENV}-policy"

    log_info "Criando/atualizando platform provisioner policy: $PLATFORM_PROVISIONER_POLICY"

    vault policy write "$PLATFORM_PROVISIONER_POLICY" - <<EOF
# Policy para platform-provisioner — env: ${ENV}
# Acesso amplo para criar/atualizar secrets e policies de todas as apps do env
# Gerado por provision-vault.sh — NAO editar manualmente

# Criar/atualizar secrets em qualquer app do env
path "secret/data/${ENV}/*" {
  capabilities = ["create", "read", "update", "list"]
}

# Gerenciar metadata de secrets
path "secret/metadata/${ENV}/*" {
  capabilities = ["create", "read", "update", "list", "delete"]
}

# Gerenciar policies (necessario para criar policies de apps)
path "sys/policies/acl/${ENV}-*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Gerenciar auth roles (necessario para criar roles K8s de apps)
path "auth/kubernetes/role/${ENV}-*" {
  capabilities = ["create", "read", "update", "delete"]
}
EOF

    log_success "Platform provisioner policy criada: $PLATFORM_PROVISIONER_POLICY"

    log_info "Criando/atualizando Kubernetes auth role: ${PLATFORM_PROVISIONER_ROLE}"

    vault write "auth/kubernetes/role/${PLATFORM_PROVISIONER_ROLE}" \
        bound_service_account_names="${SA_NAME}" \
        bound_service_account_namespaces="${SA_NAMESPACE}" \
        policies="${PLATFORM_PROVISIONER_POLICY},${PROVISIONER_APP_POLICY}" \
        ttl="15m" \
        max_ttl="30m"

    log_success "Platform provisioner K8s auth role criado: ${PLATFORM_PROVISIONER_ROLE}"
    log_success "Vault totalmente provisionado para $APP_NAME (env=$ENV, domain=$DOMAIN)"
}

main "$@"
