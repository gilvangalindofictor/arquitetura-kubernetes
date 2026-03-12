#!/usr/bin/env bash
# =============================================================================
# provision-externalsecrets.sh — Valida pre-requisitos do External Secrets Operator
# =============================================================================
# Descricao: Verifica que o ESO (External Secrets Operator) esta instalado e
#            configurado antes que scripts individuais criem ExternalSecrets.
#            Executado como Step 3 do fluxo arquitetural (apos provision-vault.sh,
#            antes dos scripts de data services paralelos).
# Uso:       ./provision-externalsecrets.sh \
#              --app <nome> \
#              --namespace <ns> \
#              --env <env> \
#              --domain <domain>
# Deps:      kubectl
# Ref:       ADR-104, GAP-D2-01
# Idempotente: SIM — apenas leitura/verificacao, sem criacao de recursos
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Source libs — com fallback minimo se common.sh nao disponivel
# -----------------------------------------------------------------------------
LOG_PREFIX="ESO"
if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/../lib/common.sh"
else
    # Fallback minimo de logging
    log_info()    { echo "[ESO][INFO] $*"; }
    log_success() { echo "[ESO][OK] $*"; }
    log_warn()    { echo "[ESO][WARN] $*"; }
    log_error()   { echo "[ESO][ERROR] $*" >&2; }
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
fi

# Constantes
readonly ESO_CRD="externalsecrets.external-secrets.io"
readonly CLUSTER_SECRET_STORE="vault-secret-store"
readonly PROVISIONER_SA="platform-provisioner"

# -----------------------------------------------------------------------------
# Ajuda
# -----------------------------------------------------------------------------
show_help() {
    cat <<EOF
provision-externalsecrets.sh — Valida pre-requisitos do External Secrets Operator

Uso:
    ./provision-externalsecrets.sh --app <nome> --namespace <ns> --env <env> --domain <domain>

Parametros obrigatorios:
    --app       <nome>    Nome da aplicacao
    --namespace <ns>      Namespace Kubernetes alvo
    --env       <env>     Ambiente (staging, prod, etc.)
    --domain    <domain>  Dominio da aplicacao

Opcoes:
    --help, -h            Mostra esta ajuda

Exemplos:
    ./provision-externalsecrets.sh --app minha-api --namespace staging-checkout-minha-api \\
        --env staging --domain checkout

Ref: ADR-104, GAP-D2-01
EOF
}

# -----------------------------------------------------------------------------
# Parse argumentos
# -----------------------------------------------------------------------------
parse_args() {
    APP_NAME="" NAMESPACE="" ENV="" DOMAIN=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --app)       APP_NAME="$2";  shift 2 ;;
            --namespace) NAMESPACE="$2"; shift 2 ;;
            --env)       ENV="$2";       shift 2 ;;
            --domain)    DOMAIN="$2";    shift 2 ;;
            --help|-h)   show_help; exit 0 ;;
            *) log_error "Opcao desconhecida: $1"; show_help; exit 1 ;;
        esac
    done

    validate_required_args APP_NAME NAMESPACE ENV DOMAIN || exit 1
}

# -----------------------------------------------------------------------------
# Verifica dependencias de CLI
# -----------------------------------------------------------------------------
check_cli_deps() {
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl nao encontrado no PATH — instale kubectl e tente novamente"
        exit 1
    fi
    log_info "kubectl disponivel: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
}

# -----------------------------------------------------------------------------
# Verifica que o CRD externalsecrets.external-secrets.io existe no cluster
# -----------------------------------------------------------------------------
check_eso_crd() {
    log_info "Verificando CRD: ${ESO_CRD}..."

    if kubectl get crd "${ESO_CRD}" &>/dev/null 2>&1; then
        log_success "CRD '${ESO_CRD}' encontrado no cluster"
        return 0
    else
        log_error "============================================================"
        log_error "ERRO CRITICO: CRD '${ESO_CRD}' NAO encontrado"
        log_error "  O External Secrets Operator nao esta instalado no cluster."
        log_error ""
        log_error "SOLUCAO: Instale o ESO antes de continuar:"
        log_error "  helm repo add external-secrets https://charts.external-secrets.io"
        log_error "  helm install external-secrets external-secrets/external-secrets \\"
        log_error "    -n external-secrets-system --create-namespace"
        log_error "============================================================"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Verifica ClusterSecretStore vault-secret-store
# Nao e fatal (pode nao existir em dev), mas loga WARNING claramente
# -----------------------------------------------------------------------------
check_cluster_secret_store() {
    log_info "Verificando ClusterSecretStore: ${CLUSTER_SECRET_STORE}..."

    if kubectl get clustersecretstore "${CLUSTER_SECRET_STORE}" &>/dev/null 2>&1; then
        local ready_status
        ready_status=$(kubectl get clustersecretstore "${CLUSTER_SECRET_STORE}" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

        if [[ "$ready_status" == "True" ]]; then
            log_success "ClusterSecretStore '${CLUSTER_SECRET_STORE}' encontrado e Ready"
        else
            log_warn "ClusterSecretStore '${CLUSTER_SECRET_STORE}' encontrado mas status Ready=${ready_status}"
            log_warn "Verifique a conectividade com o Vault: kubectl describe clustersecretstore ${CLUSTER_SECRET_STORE}"
        fi
    else
        log_warn "======================================================"
        log_warn "WARNING: ClusterSecretStore '${CLUSTER_SECRET_STORE}' nao encontrado"
        log_warn "  Ambiente: ${ENV} | Namespace: ${NAMESPACE}"
        log_warn "  Em dev/local este aviso pode ser ignorado."
        log_warn "  Em staging/prod, crie o ClusterSecretStore antes"
        log_warn "  de aplicar ExternalSecrets."
        log_warn "======================================================"
        # NAO e fatal — retorna 0 para nao interromper o fluxo
        return 0
    fi
}

# -----------------------------------------------------------------------------
# Verifica que o ServiceAccount platform-provisioner pode criar ExternalSecrets
# no namespace alvo (kubectl auth can-i)
# -----------------------------------------------------------------------------
check_provisioner_sa_permissions() {
    log_info "Verificando permissoes do ServiceAccount '${PROVISIONER_SA}' no namespace '${NAMESPACE}'..."

    # Checar se o SA existe em platform-system (namespace padrao do provisioner)
    local sa_namespace="${PROVISIONER_SA_NAMESPACE:-platform-system}"

    if ! kubectl get serviceaccount "${PROVISIONER_SA}" -n "${sa_namespace}" &>/dev/null 2>&1; then
        log_warn "ServiceAccount '${PROVISIONER_SA}' nao encontrado em '${sa_namespace}'"
        log_warn "Execute bootstrap-provisioner.sh para criar o SA antes de continuar"
        # Nao fatal aqui — provision-vault.sh ja valida e falha se ausente
        return 0
    fi

    # Verificar permissao de criacao de ExternalSecrets no namespace alvo
    local can_create
    can_create=$(kubectl auth can-i create externalsecrets.external-secrets.io \
        --as="system:serviceaccount:${sa_namespace}:${PROVISIONER_SA}" \
        -n "${NAMESPACE}" 2>/dev/null || echo "no")

    if [[ "$can_create" == "yes" ]]; then
        log_success "ServiceAccount '${PROVISIONER_SA}' tem permissao para criar ExternalSecrets em '${NAMESPACE}'"
    else
        log_warn "======================================================"
        log_warn "WARNING: ServiceAccount '${PROVISIONER_SA}' NAO tem permissao"
        log_warn "  para criar ExternalSecrets no namespace '${NAMESPACE}'"
        log_warn "  Role/RoleBinding pode estar ausente."
        log_warn ""
        log_warn "SOLUCAO: Verifique o RBAC do provisioner no namespace:"
        log_warn "  kubectl get rolebindings -n ${NAMESPACE} | grep ${PROVISIONER_SA}"
        log_warn "======================================================"
        # Nao e fatal — o namespace pode ainda nao ter o RoleBinding aplicado
        # (create-namespace.sh aplica apos este step no fluxo normal)
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    log_info "=== provision-externalsecrets.sh ==="
    log_info "App: ${APP_NAME} | Namespace: ${NAMESPACE} | Env: ${ENV} | Domain: ${DOMAIN}"

    # 1. Verificar dependencias CLI
    check_cli_deps

    # 2. CRD ESO — FATAL se ausente
    check_eso_crd || exit 1

    # 3. ClusterSecretStore — WARNING (nao fatal)
    check_cluster_secret_store

    # 4. Permissoes do ServiceAccount — WARNING (nao fatal)
    check_provisioner_sa_permissions

    log_success "ESO prerequisites verified for ${APP_NAME} in ${NAMESPACE}"
}

main "$@"
