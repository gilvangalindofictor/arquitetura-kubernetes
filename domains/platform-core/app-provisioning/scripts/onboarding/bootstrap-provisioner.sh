#!/bin/bash
# =============================================================================
# bootstrap-provisioner.sh — Bootstrap do ServiceAccount platform-provisioner
# =============================================================================
# Descricao: Cria o namespace platform-system, ServiceAccount e ClusterRole
#            para o platform-provisioner. Execucao unica (one-time setup).
# Uso:       ./bootstrap-provisioner.sh [--sa-namespace <ns>] [--dry-run]
# Deps:      kubectl
# Idempotente: SIM — usa kubectl apply
# Ref:       GAP-008 (P1, Sprint S2)
# =============================================================================

set -euo pipefail

# ---- Logging: usa common.sh quando disponivel, fallback local ----
LOG_PREFIX="BOOTSTRAP"
_COMMON_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

if [[ -f "$_COMMON_SH" ]]; then
    # shellcheck source=../lib/common.sh
    source "$_COMMON_SH"
else
    # Fallback: funcoes de logging locais (standalone mode)
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
    log_info()    { echo -e "${BLUE}[${LOG_PREFIX}]${NC} $1"; }
    log_success() { echo -e "${GREEN}[${LOG_PREFIX}]${NC} $1"; }
    log_warning() { echo -e "${YELLOW}[${LOG_PREFIX}]${NC} $1"; }
    log_error()   { echo -e "${RED}[${LOG_PREFIX}]${NC} $1" >&2; }
fi
unset _COMMON_SH

# ---- Defaults (parametrizaveis) ----
SA_NAME="platform-provisioner"
SA_NAMESPACE="cicd-argocd"
ENV=""
DOMAIN=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --sa-namespace) SA_NAMESPACE="$2"; shift 2 ;;
        --sa-name)      SA_NAME="$2"; shift 2 ;;
        --env)          ENV="$2"; shift 2 ;;
        --domain)       DOMAIN="$2"; shift 2 ;;
        --dry-run)      DRY_RUN=true; shift ;;
        *) log_error "Opcao desconhecida: $1"; exit 1 ;;
    esac
done

log_info "SA Name: ${SA_NAME}"
log_info "SA Namespace: ${SA_NAMESPACE}"
[[ -n "${ENV}" ]]    && log_info "Env: ${ENV}"
[[ -n "${DOMAIN}" ]] && log_info "Domain: ${DOMAIN}"

# ---- Pre-checks ----
if ! command -v kubectl &>/dev/null; then
    log_error "kubectl nao encontrado no PATH"
    exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
    log_error "Nao foi possivel conectar ao cluster Kubernetes"
    exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Criaria namespace ${SA_NAMESPACE}, SA ${SA_NAME} e ClusterRole"
    exit 0
fi

# ---- Step 1: Criar namespace platform-system (se nao existir) ----
if kubectl get namespace "${SA_NAMESPACE}" &>/dev/null; then
    log_warning "Namespace ${SA_NAMESPACE} ja existe"
else
    log_info "Criando namespace ${SA_NAMESPACE}..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${SA_NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: ${SA_NAME}
    app.kubernetes.io/part-of: platform-core
EOF
    log_success "Namespace ${SA_NAMESPACE} criado"
fi

# ---- Step 2: Criar ServiceAccount ----
log_info "Aplicando ServiceAccount ${SA_NAME}..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${SA_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${SA_NAME}
    app.kubernetes.io/part-of: platform-core
    app.kubernetes.io/managed-by: ${SA_NAME}
    app.kubernetes.io/component: ci-cd
EOF

log_success "ServiceAccount ${SA_NAME} criado/atualizado"

# ---- Step 3: Criar ClusterRole ----
log_info "Aplicando ClusterRole ${SA_NAME}..."

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${SA_NAME}
  labels:
    app.kubernetes.io/name: ${SA_NAME}
    app.kubernetes.io/part-of: platform-core
    app.kubernetes.io/managed-by: ${SA_NAME}
rules:
  # Verificar existencia de namespaces (read-only)
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]
  # Gerenciar secrets e configmaps
  - apiGroups: [""]
    resources: ["secrets", "configmaps"]
    verbs: ["create", "get", "update", "patch", "delete"]
  # Verificar service accounts
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["get", "list"]
  # Resource quotas e limit ranges
  - apiGroups: [""]
    resources: ["resourcequotas", "limitranges"]
    verbs: ["create", "get", "update", "patch"]
  # ExternalSecrets
  - apiGroups: ["external-secrets.io"]
    resources: ["externalsecrets", "clustersecretstores", "secretstores"]
    verbs: ["create", "get", "update", "patch", "delete"]
  # NetworkPolicies
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs: ["create", "get", "update", "patch"]
  # ArgoCD Applications
  - apiGroups: ["argoproj.io"]
    resources: ["applications", "appprojects"]
    verbs: ["create", "get", "update", "patch"]
EOF

log_success "ClusterRole ${SA_NAME} criado/atualizado"

# ---- Step 3.5: Criar ClusterRoleBinding (SA → ClusterRole) ----
# GAP-NEW-012 (2026-03-12): ClusterRoleBinding ausente — SA sem permissões efetivas
log_info "Step 3.5: Creating ClusterRoleBinding..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-provisioner
  labels:
    app.kubernetes.io/managed-by: bootstrap-provisioner
    environment: ${ENV}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: platform-provisioner
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${SA_NAMESPACE}
EOF

log_success "ClusterRoleBinding platform-provisioner criado/atualizado"

# ---- Step 4: Validacao ----
log_info "Validando recursos criados..."

if kubectl get serviceaccount "${SA_NAME}" -n "${SA_NAMESPACE}" &>/dev/null; then
    log_success "ServiceAccount ${SA_NAME} verificado em ${SA_NAMESPACE}"
else
    log_error "FALHA: ServiceAccount ${SA_NAME} nao encontrado em ${SA_NAMESPACE}"
    exit 1
fi

if kubectl get clusterrole "${SA_NAME}" &>/dev/null; then
    log_success "ClusterRole ${SA_NAME} verificado"
else
    log_error "FALHA: ClusterRole ${SA_NAME} nao encontrado"
    exit 1
fi

log_success "Bootstrap completo — platform-provisioner pronto para uso"
log_info "Proximo passo: criar RoleBindings por namespace via create-namespace.sh"
