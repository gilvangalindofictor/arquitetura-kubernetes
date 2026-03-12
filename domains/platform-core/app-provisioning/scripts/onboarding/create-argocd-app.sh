#!/bin/bash
# =============================================================================
# create-argocd-app.sh — Cria ArgoCD Application (idempotente)
# =============================================================================
# Descricao: Provisiona ArgoCD Application para a aplicacao,
#            com sync policy baseada no ambiente (ADR-049).
#            NOTA: Este script NAO cria AppProject. O AppProject deve ser
#            provisionado antes via provision-argocd.sh (GAP-010 ITEM 5).
# Uso:       ./create-argocd-app.sh --app <name> --domain <d> --namespace <ns> --env <e> [--branch <b>] [--path <p>]
# Deps:      kubectl
# Idempotente: SIM — usa kubectl apply
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="ARGOCD"
source "${SCRIPT_DIR}/../lib/common.sh"

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Parse argumentos
# -----------------------------------------------------------------------------
parse_args() {
    APP_NAME="" DOMAIN="" NAMESPACE="" ENV="" BRANCH="main" APP_PATH="" DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --app)       APP_NAME="$2"; shift 2 ;;
            --domain)    DOMAIN="$2"; shift 2 ;;
            --namespace) NAMESPACE="$2"; shift 2 ;;
            --env)       ENV="$2"; shift 2 ;;
            --branch)    BRANCH="$2"; shift 2 ;;
            --path)      APP_PATH="$2"; shift 2 ;;
            --dry-run)   DRY_RUN=true; shift ;;
            *) log_error "Opcao desconhecida: $1"; exit 1 ;;
        esac
    done

    validate_required_args APP_NAME DOMAIN NAMESPACE ENV || exit 1

    # Default path se nao especificado
    if [[ -z "$APP_PATH" ]]; then
        APP_PATH="overlays/${ENV}"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    # Configuracoes
    GITLAB_HOST="${GITLAB_HOST:-gitlab.empresa.com.br}"
    GITOPS_REPO_URL="https://${GITLAB_HOST}/corporate-domains/${DOMAIN}/${APP_NAME}/${APP_NAME}-gitops.git"
    ARGOCD_APP_NAME="${ENV}-${APP_NAME}"
    ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-staging-platform-argocd}"

    # Sync policy por ambiente (ADR-049)
    case "$ENV" in
        staging)
            AUTO_SYNC="true"; AUTO_PRUNE="${AUTO_PRUNE:-true}"; SELF_HEAL="true"
            ;;
        prod)
            AUTO_SYNC="false"; AUTO_PRUNE="false"; SELF_HEAL="false"
            ;;
        *)
            AUTO_SYNC="true"; AUTO_PRUNE="true"; SELF_HEAL="true"
            ;;
    esac

    log_info "ArgoCD App: $ARGOCD_APP_NAME"
    log_info "GitOps Repo: $GITOPS_REPO_URL"
    log_info "Branch: $BRANCH | Path: $APP_PATH"
    log_info "Sync Policy: auto=$AUTO_SYNC, prune=$AUTO_PRUNE, selfHeal=$SELF_HEAL"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] kubectl apply Application"
        log_info "[DRY-RUN] AppProject '${DOMAIN}' deve existir previamente (provision-argocd.sh)"
        exit 0
    fi

    # -----------------------------------------------------------------
    # Guarda: AppProject DEVE existir antes de criar a Application
    # A criacao do AppProject e responsabilidade de provision-argocd.sh
    # -----------------------------------------------------------------
    if ! resource_exists appproject "$DOMAIN" "$ARGOCD_NAMESPACE"; then
        log_warn "AppProject '${DOMAIN}' nao encontrado em '${ARGOCD_NAMESPACE}'"
        log_warn "Execute provision-argocd.sh antes de criar a Application:"
        log_warn "  ./provision-argocd.sh \\"
        log_warn "    --app ${APP_NAME} \\"
        log_warn "    --domain ${DOMAIN} \\"
        log_warn "    --env ${ENV} \\"
        log_warn "    --argocd-namespace ${ARGOCD_NAMESPACE} \\"
        log_warn "    --gitlab-host \${GITLAB_HOST}"
        log_error "Abortando: AppProject ausente. Provisione-o e tente novamente."
        exit 1
    fi

    log_info "AppProject '${DOMAIN}' confirmado em '${ARGOCD_NAMESPACE}'"

    # -----------------------------------------------------------------
    # Check-before-create: Application
    # -----------------------------------------------------------------
    if resource_exists application "$ARGOCD_APP_NAME" "$ARGOCD_NAMESPACE"; then
        log_warn "Application '$ARGOCD_APP_NAME' ja existe — atualizando"
    fi

    log_info "Aplicando ArgoCD Application: $ARGOCD_APP_NAME"

    kubectl_apply_idempotent <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${ARGOCD_APP_NAME}
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/part-of: ${APP_NAME}
    domain: ${DOMAIN}
    environment: ${ENV}
    managed-by: platform-provisioner
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: ${DOMAIN}
  source:
    repoURL: ${GITOPS_REPO_URL}
    targetRevision: ${BRANCH}
    path: ${APP_PATH}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: ${AUTO_PRUNE}
      selfHeal: ${SELF_HEAL}
    syncOptions:
    - CreateNamespace=false
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  revisionHistoryLimit: 10
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
  info:
  - name: Environment
    value: ${ENV}
  - name: Domain
    value: ${DOMAIN}
  - name: GitOps Repo
    value: ${GITOPS_REPO_URL}
EOF

    log_success "ArgoCD Application aplicado: $ARGOCD_APP_NAME"
}

main "$@"
