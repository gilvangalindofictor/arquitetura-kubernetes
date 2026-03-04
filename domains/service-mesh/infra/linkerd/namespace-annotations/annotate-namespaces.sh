#!/bin/bash
# =============================================================================
# GAP-011: Linkerd Proxy Injection — Namespace Annotation Automation
# =============================================================================
# Estrategia: opt-in gradual por fases (menor risco primeiro)
#
# Fase 1 — staging-platform    (Keycloak, Vault, ArgoCD)
# Fase 2 — staging-data-services + gitlab-staging
# Fase 3 — staging-observability-monitoring
#
# Pre-requisitos:
#   - kubectl configurado para o cluster correto
#   - Linkerd control plane Running (linkerd check)
#   - Aprovacao da lideranca para cada fase
#
# Uso:
#   ./annotate-namespaces.sh --phase 1          # Executa apenas Fase 1
#   ./annotate-namespaces.sh --phase 2          # Executa apenas Fase 2
#   ./annotate-namespaces.sh --phase 3          # Executa apenas Fase 3
#   ./annotate-namespaces.sh --rollback <ns>    # Remove annotation + restart pods
#   ./annotate-namespaces.sh --status           # Exibe status de todos os namespaces
#
# Compliance: BACEN BCB 85/2021 Art. 6 SS IV/V (criptografia + autenticacao mutual)
# =============================================================================

set -euo pipefail

# ----- Cores para output -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ----- Namespaces por fase -----------------------------------------------------
NAMESPACES_PHASE_1=(
  "staging-platform-keycloak"   # Keycloak IdP — menor risco de latencia
  "staging-platform-argocd"     # ArgoCD GitOps — deployments controlados
  "staging-security-vault"      # HashiCorp Vault — restart manual requerido (unseal)
)

NAMESPACES_PHASE_2=(
  "staging-platform-harbor"     # Harbor registry — verificar latencia antes
  "gitlab-staging"              # GitLab — validar performance pos-inject
)

NAMESPACES_PHASE_3=(
  "staging-observability-monitoring"  # Prometheus, Grafana, Loki, Tempo
  "data-services"                     # Redis, RabbitMQ — verificar latencia antes
)

# ----- Funcoes auxiliares -------------------------------------------------------

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

check_prerequisites() {
  log_info "Verificando pre-requisitos..."

  if ! command -v kubectl &>/dev/null; then
    log_error "kubectl nao encontrado. Instale: https://kubernetes.io/docs/tasks/tools/"
    exit 1
  fi

  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cluster nao acessivel. Configure KUBECONFIG corretamente."
    exit 1
  fi

  # Verificar se Linkerd control plane esta Running
  local linkerd_pods
  linkerd_pods=$(kubectl get pods -n linkerd --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
  if [[ "$linkerd_pods" -lt 3 ]]; then
    log_error "Linkerd control plane com menos de 3 pods Running (encontrado: $linkerd_pods)."
    log_error "Execute 'kubectl get pods -n linkerd' para diagnosticar."
    exit 1
  fi

  log_ok "Pre-requisitos OK (cluster acessivel, $linkerd_pods pods Linkerd Running)"
}

annotate_namespace() {
  local ns="$1"

  # Verificar se namespace existe
  if ! kubectl get namespace "$ns" &>/dev/null; then
    log_warn "Namespace '$ns' nao encontrado — pulando."
    return 0
  fi

  # Aplicar annotation
  kubectl annotate namespace "$ns" linkerd.io/inject=enabled --overwrite
  log_ok "$ns: linkerd.io/inject=enabled aplicado"

  # Restart deployments para injetar proxy nos pods existentes
  log_info "$ns: Reiniciando deployments para injecao de proxy..."
  local deploy_count
  deploy_count=$(kubectl get deployments -n "$ns" --no-headers 2>/dev/null | wc -l)
  if [[ "$deploy_count" -gt 0 ]]; then
    kubectl rollout restart deployment -n "$ns"
    log_ok "$ns: $deploy_count deployment(s) reiniciados"
  else
    log_warn "$ns: Nenhum deployment encontrado (StatefulSets/DaemonSets precisam reinicio manual)"
  fi

  # Restart StatefulSets se houver
  local sts_count
  sts_count=$(kubectl get statefulsets -n "$ns" --no-headers 2>/dev/null | wc -l)
  if [[ "$sts_count" -gt 0 ]]; then
    kubectl rollout restart statefulset -n "$ns"
    log_ok "$ns: $sts_count statefulset(s) reiniciados"
  fi
}

wait_for_rollout() {
  local ns="$1"
  log_info "$ns: Aguardando rollout completar (timeout 5 min)..."

  local deployments
  deployments=$(kubectl get deployments -n "$ns" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
  for deploy in $deployments; do
    if kubectl rollout status deployment/"$deploy" -n "$ns" --timeout=300s 2>/dev/null; then
      log_ok "$ns/$deploy: rollout completo"
    else
      log_warn "$ns/$deploy: rollout timeout — verifique manualmente"
    fi
  done
}

verify_mtls() {
  local ns="$1"
  log_info "$ns: Verificando proxy injection..."

  local injected_pods
  injected_pods=$(kubectl get pods -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}' 2>/dev/null | grep -c "linkerd-proxy" || echo "0")
  local total_pods
  total_pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)

  log_info "$ns: $injected_pods/$total_pods pods com linkerd-proxy injetado"

  if command -v linkerd &>/dev/null; then
    log_info "$ns: Status mTLS via linkerd viz:"
    linkerd viz stat deploy -n "$ns" 2>/dev/null || log_warn "linkerd viz nao disponivel"
  else
    log_warn "linkerd CLI nao disponivel — valide manualmente com 'linkerd viz stat deploy -n $ns'"
  fi
}

show_status() {
  log_info "=== Status de Proxy Injection por Namespace ==="
  echo ""

  local all_ns=("${NAMESPACES_PHASE_1[@]}" "${NAMESPACES_PHASE_2[@]}" "${NAMESPACES_PHASE_3[@]}")

  printf "%-45s %-20s %-15s\n" "NAMESPACE" "INJECT_ANNOTATION" "PODS_COM_PROXY"
  printf "%-45s %-20s %-15s\n" "---------" "-----------------" "--------------"

  for ns in "${all_ns[@]}"; do
    if ! kubectl get namespace "$ns" &>/dev/null; then
      printf "%-45s %-20s %-15s\n" "$ns" "NOT_FOUND" "-"
      continue
    fi

    local annotation
    annotation=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.annotations.linkerd\.io/inject}' 2>/dev/null || echo "not-set")
    local injected
    injected=$(kubectl get pods -n "$ns" -o jsonpath='{range .items[*]}{.spec.containers[*].name}{"\n"}{end}' 2>/dev/null | grep -c "linkerd-proxy" || echo "0")

    printf "%-45s %-20s %-15s\n" "$ns" "${annotation:-not-set}" "$injected"
  done
  echo ""
}

rollback_namespace() {
  local ns="$1"

  if ! kubectl get namespace "$ns" &>/dev/null; then
    log_error "Namespace '$ns' nao encontrado."
    exit 1
  fi

  log_warn "ROLLBACK: Removendo linkerd.io/inject de '$ns'..."
  kubectl annotate namespace "$ns" linkerd.io/inject- --overwrite 2>/dev/null || true
  log_ok "$ns: annotation removida"

  log_info "$ns: Reiniciando workloads para remover sidecar..."
  kubectl rollout restart deployment -n "$ns" 2>/dev/null || true
  kubectl rollout restart statefulset -n "$ns" 2>/dev/null || true
  log_ok "$ns: Rollback completo. Proxies serao removidos apos restart."
  log_warn "NOTA: Pods existentes SEM restart manteem o sidecar ate proximo restart."
}

run_phase() {
  local phase="$1"
  local namespaces=()

  case "$phase" in
    1) namespaces=("${NAMESPACES_PHASE_1[@]}") ;;
    2) namespaces=("${NAMESPACES_PHASE_2[@]}") ;;
    3) namespaces=("${NAMESPACES_PHASE_3[@]}") ;;
    *) log_error "Fase invalida: $phase (use 1, 2 ou 3)"; exit 1 ;;
  esac

  log_info "=== GAP-011 Linkerd — Fase $phase ==="
  log_info "Namespaces: ${namespaces[*]}"
  echo ""

  check_prerequisites

  for ns in "${namespaces[@]}"; do
    echo "--- $ns ---"
    annotate_namespace "$ns"
    wait_for_rollout "$ns"
    verify_mtls "$ns"
    echo ""
  done

  log_ok "=== Fase $phase COMPLETA ==="
  log_info "Verificacao final:"
  show_status
  log_info "Proximos passos:"
  log_info "  1. Monitorar latencia por 24h: linkerd viz top deploy -n <namespace>"
  log_info "  2. Verificar mTLS: linkerd viz edges deploy -n <namespace>"
  log_info "  3. Aplicar AuthorizationPolicies: kubectl apply -f ../authorization-policies/"
}

# ----- Main --------------------------------------------------------------------
main() {
  if [[ $# -eq 0 ]]; then
    echo "Uso: $0 --phase <1|2|3> | --rollback <namespace> | --status"
    exit 1
  fi

  case "$1" in
    --phase)
      [[ -z "${2:-}" ]] && { log_error "Especifique a fase: --phase 1|2|3"; exit 1; }
      run_phase "$2"
      ;;
    --rollback)
      [[ -z "${2:-}" ]] && { log_error "Especifique o namespace: --rollback <namespace>"; exit 1; }
      rollback_namespace "$2"
      ;;
    --status)
      show_status
      ;;
    *)
      log_error "Argumento desconhecido: $1"
      echo "Uso: $0 --phase <1|2|3> | --rollback <namespace> | --status"
      exit 1
      ;;
  esac
}

main "$@"
