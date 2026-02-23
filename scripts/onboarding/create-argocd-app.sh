#!/bin/bash
# Cria ArgoCD Application para deploy automatizado
# Referência: ADR-048, ADR-049 (GitOps)
# Uso: ./create-argocd-app.sh <produto> <domain> <env>

set -euo pipefail

PRODUTO="$1"
DOMAIN="$2"
ENV="$3"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[ARGOCD]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[ARGOCD]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[ARGOCD]${NC} $1"
}

# Validações
log_info "Validando parâmetros..."

if ! [[ "$PRODUTO" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
    echo "❌ Nome do produto inválido: '$PRODUTO'"
    exit 1
fi

# Namespace (ADR-048)
NAMESPACE="${ENV}-${DOMAIN}-${PRODUTO}"

# GitLab repo GitOps
GITLAB_HOST="${GITLAB_HOST:-gitlab.empresa.com}"
GITOPS_REPO_URL="https://${GITLAB_HOST}/corporate-domains/${DOMAIN}/${PRODUTO}/${PRODUTO}-gitops.git"

# ArgoCD Application name
ARGOCD_APP_NAME="${ENV}-${PRODUTO}"

log_info "ArgoCD Application: $ARGOCD_APP_NAME"
log_info "Namespace: $NAMESPACE"
log_info "GitOps Repo: $GITOPS_REPO_URL"
log_info "Path: overlays/$ENV"

# Verificar dependências
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl não encontrado"
    exit 1
fi

if ! command -v argocd &> /dev/null; then
    log_warning "argocd CLI não encontrado, usando kubectl diretamente"
fi

# Verificar se namespace existe
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_warning "Namespace $NAMESPACE não existe. Criando..."
    kubectl create namespace "$NAMESPACE"

    # Adicionar labels obrigatórias (ADR-048)
    kubectl label namespace "$NAMESPACE" \
        domain="$DOMAIN" \
        environment="$ENV" \
        product="$PRODUTO" \
        managed-by="argocd" \
        --overwrite
fi

# ====================
# Criar ArgoCD Application
# ====================
log_info "Criando ArgoCD Application..."

# Determinar sync policy baseado no ambiente (ADR-049)
case "$ENV" in
    dev)
        AUTO_SYNC="true"
        AUTO_PRUNE="true"
        SELF_HEAL="true"
        ;;
    staging)
        AUTO_SYNC="true"
        AUTO_PRUNE="false"
        SELF_HEAL="true"
        ;;
    prod)
        AUTO_SYNC="false"  # Produção requer aprovação manual
        AUTO_PRUNE="false"
        SELF_HEAL="false"
        ;;
    *)
        echo "❌ Ambiente inválido: $ENV"
        exit 1
        ;;
esac

log_info "Sync Policy: AutoSync=$AUTO_SYNC, Prune=$AUTO_PRUNE, SelfHeal=$SELF_HEAL"

# Criar ArgoCD Application via kubectl
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${ARGOCD_APP_NAME}
  namespace: argocd
  labels:
    app.kubernetes.io/name: ${PRODUTO}
    app.kubernetes.io/part-of: ${PRODUTO}
    domain: ${DOMAIN}
    environment: ${ENV}
    managed-by: governance-onboarding
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: ${DOMAIN}

  source:
    repoURL: ${GITOPS_REPO_URL}
    targetRevision: main
    path: overlays/${ENV}

  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}

  syncPolicy:
    automated:
      prune: ${AUTO_PRUNE}
      selfHeal: ${SELF_HEAL}
$(if [ "$AUTO_SYNC" = "true" ]; then
echo "      allowEmpty: false"
fi)
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

  revisionHistoryLimit: 10

  # Health assessment
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas

  # Notification on sync
  info:
  - name: Environment
    value: ${ENV}
  - name: Domain
    value: ${DOMAIN}
  - name: GitOps Repo
    value: ${GITOPS_REPO_URL}
EOF

log_success "ArgoCD Application criado: $ARGOCD_APP_NAME"

# ====================
# Criar ArgoCD Project (se não existir)
# ====================
log_info "Verificando ArgoCD Project: $DOMAIN"

if ! kubectl get appproject "$DOMAIN" -n argocd &> /dev/null; then
    log_info "Criando ArgoCD Project: $DOMAIN"

    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: ${DOMAIN}
  namespace: argocd
  labels:
    domain: ${DOMAIN}
spec:
  description: "Corporate Domain: ${DOMAIN} (ADR-047)"

  # Source repos permitidos
  sourceRepos:
  - 'https://${GITLAB_HOST}/corporate-domains/${DOMAIN}/*'

  # Destinations permitidos
  destinations:
  - namespace: 'dev-${DOMAIN}-*'
    server: https://kubernetes.default.svc
  - namespace: 'staging-${DOMAIN}-*'
    server: https://kubernetes.default.svc
  - namespace: 'prod-${DOMAIN}-*'
    server: https://kubernetes.default.svc

  # Cluster resources permitidos
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRole
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRoleBinding

  # Namespace resources (permitir todos)
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'

  # RBAC Roles (ADR-049)
  roles:
  - name: ${DOMAIN}-developer
    description: Developers do domínio ${DOMAIN}
    policies:
    - p, proj:${DOMAIN}:${DOMAIN}-developer, applications, get, ${DOMAIN}/*, allow
    - p, proj:${DOMAIN}:${DOMAIN}-developer, applications, sync, ${DOMAIN}/*-dev-*, allow
    - p, proj:${DOMAIN}:${DOMAIN}-developer, applications, sync, ${DOMAIN}/*-staging-*, allow
    groups:
    - ${DOMAIN}-team

  - name: ${DOMAIN}-admin
    description: Admins do domínio ${DOMAIN}
    policies:
    - p, proj:${DOMAIN}:${DOMAIN}-admin, applications, *, ${DOMAIN}/*, allow
    groups:
    - ${DOMAIN}-leads
    - platform-team
EOF

    log_success "ArgoCD Project criado: $DOMAIN"
else
    log_warning "ArgoCD Project já existe: $DOMAIN"
fi

# ====================
# Sync inicial (se auto-sync desabilitado)
# ====================
if [ "$AUTO_SYNC" = "false" ]; then
    log_info "Auto-sync desabilitado para $ENV. Sync manual necessário."
    log_info "Para fazer sync: argocd app sync $ARGOCD_APP_NAME"
else
    log_info "Aguardando ArgoCD detectar aplicação e fazer sync automático..."
    sleep 5

    # Verificar status
    if command -v argocd &> /dev/null; then
        argocd app wait "$ARGOCD_APP_NAME" --timeout 300 --health || log_warning "Timeout aguardando sync. Verifique: argocd app get $ARGOCD_APP_NAME"
    else
        log_info "Use: kubectl get applications -n argocd $ARGOCD_APP_NAME"
    fi
fi

# ====================
# Criar Notification ConfigMap (opcional)
# ====================
log_info "Configurando notificações ArgoCD..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm-${PRODUTO}
  namespace: argocd
  labels:
    app.kubernetes.io/name: ${PRODUTO}
    domain: ${DOMAIN}
data:
  # Slack notification (exemplo)
  service.slack: |
    token: \$slack-token
  template.app-deployed: |
    message: |
      ✅ Application {{.app.metadata.name}} deployed to {{.context.environment}}
      🔗 https://argocd.empresa.com/applications/{{.app.metadata.name}}
  trigger.on-deployed: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [app-deployed]
EOF

log_success "Notification ConfigMap criado"

# ====================
# Sumário
# ====================
echo ""
log_success "========================================="
log_success "ArgoCD Application Criado!"
log_success "========================================="
echo ""
log_info "Application: $ARGOCD_APP_NAME"
log_info "Project: $DOMAIN"
log_info "Namespace: $NAMESPACE"
log_info "Environment: $ENV"
echo ""
log_info "GitOps:"
log_info "  Repo: $GITOPS_REPO_URL"
log_info "  Branch: main"
log_info "  Path: overlays/$ENV"
echo ""
log_info "Sync Policy:"
log_info "  Auto-Sync: $AUTO_SYNC"
log_info "  Auto-Prune: $AUTO_PRUNE"
log_info "  Self-Heal: $SELF_HEAL"
echo ""
log_info "URLs:"
log_info "  ArgoCD UI: https://argocd.empresa.com/applications/$ARGOCD_APP_NAME"
log_info "  Kubernetes: kubectl get all -n $NAMESPACE"
echo ""

if [ "$AUTO_SYNC" = "true" ]; then
    log_info "🚀 Deploy Automático:"
    log_info "   1. Commit no repo app → CI build imagem"
    log_info "   2. CI atualiza image tag no GitOps repo"
    log_info "   3. ArgoCD detecta mudança e faz sync automático"
else
    log_info "⚠️  Deploy Manual (Produção):"
    log_info "   1. Commit no repo app → CI build imagem"
    log_info "   2. CI atualiza image tag no GitOps repo"
    log_info "   3. Aprovador faz: argocd app sync $ARGOCD_APP_NAME"
    log_info "   4. Validar: argocd app wait $ARGOCD_APP_NAME --health"
fi

echo ""
log_info "Comandos úteis:"
log_info "  # Ver status"
log_info "  argocd app get $ARGOCD_APP_NAME"
log_info ""
log_info "  # Ver logs do sync"
log_info "  argocd app logs $ARGOCD_APP_NAME --follow"
log_info ""
log_info "  # Fazer sync manual"
log_info "  argocd app sync $ARGOCD_APP_NAME"
log_info ""
log_info "  # Rollback"
log_info "  argocd app rollback $ARGOCD_APP_NAME <revision>"
echo ""
log_success "========================================="
