#!/bin/bash
# =============================================================================
# GAP-011: Linkerd mTLS Validation Script
# =============================================================================
# Objetivo: Validar que o mTLS esta ativo e funcionando em todos os namespaces
#           apos a habilitacao de proxy injection (Fases 1, 2 e 3).
#
# Uso:
#   ./validate-mtls.sh                          # Validacao completa
#   ./validate-mtls.sh --namespace staging-platform    # Um namespace especifico
#   ./validate-mtls.sh --check-policies         # Verificar AuthorizationPolicies
#   ./validate-mtls.sh --check-profiles         # Verificar ServiceProfiles
#   ./validate-mtls.sh --report                 # Gerar relatorio HTML/texto
#
# Pre-requisitos:
#   - kubectl configurado para o cluster alvo
#   - Linkerd control plane Running (linkerd check OK)
#   - Proxy injection habilitado nos namespaces alvo
#
# Saida:
#   - PASS/FAIL por namespace
#   - Contagem de pods com/sem proxy
#   - Status de mTLS (se linkerd CLI disponivel)
#   - Relatorio de compliance BACEN BCB 85/2021
#
# Compliance: BACEN BCB 85/2021 Art. 6 SS IV/V, Art. 9, Art. 11, Art. 15
# =============================================================================

set -euo pipefail

# ----- Cores e simbolos -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${BLUE}[INFO]${NC}"

# ----- Configuracao -----------------------------------------------------------
NAMESPACES=(
  "staging-platform"
  "staging-data-services"
  "gitlab-staging"
  "staging-observability-monitoring"
)

# Contadores globais
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNED_CHECKS=0

# ----- Funcoes auxiliares -----------------------------------------------------

check() {
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

pass() {
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  echo -e "${PASS} $*"
}

fail() {
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
  echo -e "${FAIL} $*"
}

warn() {
  WARNED_CHECKS=$((WARNED_CHECKS + 1))
  echo -e "${WARN} $*"
}

info() {
  echo -e "${INFO} $*"
}

section() {
  echo ""
  echo -e "${BOLD}${CYAN}=== $* ===${NC}"
  echo ""
}

# ----- Verificacao 1: Control Plane ------------------------------------------

check_control_plane() {
  section "1. Linkerd Control Plane"

  check
  local pod_count
  pod_count=$(kubectl get pods -n linkerd \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l)

  if [[ "$pod_count" -ge 3 ]]; then
    pass "Control plane: $pod_count pods Running (esperado >= 3)"
  else
    fail "Control plane: apenas $pod_count pods Running (esperado >= 3)"
    info "Execute: kubectl get pods -n linkerd"
    return 1
  fi

  # Verificar CRDs
  check
  local crd_count
  crd_count=$(kubectl get crd 2>/dev/null | grep -c "linkerd.io" || echo "0")
  if [[ "$crd_count" -ge 6 ]]; then
    pass "CRDs Linkerd: $crd_count instalados (esperado >= 6)"
  else
    fail "CRDs Linkerd: apenas $crd_count instalados"
    info "Execute: kubectl get crd | grep linkerd.io"
  fi

  # Verificar MutatingWebhookConfiguration
  check
  if kubectl get mutatingwebhookconfiguration linkerd-proxy-injector &>/dev/null; then
    local ca_bundle_size
    ca_bundle_size=$(kubectl get mutatingwebhookconfiguration linkerd-proxy-injector \
      -o jsonpath='{.webhooks[0].clientConfig.caBundle}' 2>/dev/null | wc -c)
    if [[ "$ca_bundle_size" -gt 10 ]]; then
      pass "MutatingWebhookConfiguration: caBundle presente ($ca_bundle_size bytes)"
    else
      fail "MutatingWebhookConfiguration: caBundle VAZIO — proxy injection nao vai funcionar"
    fi
  else
    fail "MutatingWebhookConfiguration linkerd-proxy-injector nao encontrado"
  fi

  # Linkerd CLI check (opcional)
  if command -v linkerd &>/dev/null; then
    info "Linkerd CLI disponivel — executando linkerd check:"
    linkerd check 2>&1 | tail -5 || true
  else
    warn "Linkerd CLI nao disponivel — instale para validacao completa"
    info "Instalar: curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh"
  fi
}

# ----- Verificacao 2: Namespace Annotations -----------------------------------

check_namespace_annotations() {
  section "2. Namespace Annotations (proxy injection)"

  for ns in "${NAMESPACES[@]}"; do
    check
    if ! kubectl get namespace "$ns" &>/dev/null; then
      warn "Namespace '$ns' nao encontrado — pulando"
      continue
    fi

    local annotation
    annotation=$(kubectl get namespace "$ns" \
      -o jsonpath='{.metadata.annotations.linkerd\.io/inject}' 2>/dev/null || echo "")

    if [[ "$annotation" == "enabled" ]]; then
      pass "Namespace $ns: linkerd.io/inject=enabled"
    else
      fail "Namespace $ns: linkerd.io/inject=${annotation:-'NAO DEFINIDO'}"
      info "Corrigir: kubectl annotate namespace $ns linkerd.io/inject=enabled --overwrite"
    fi
  done
}

# ----- Verificacao 3: Pods com Proxy ------------------------------------------

check_proxy_injection() {
  section "3. Pods com Proxy Linkerd Injetado"

  for ns in "${NAMESPACES[@]}"; do
    if ! kubectl get namespace "$ns" &>/dev/null; then
      continue
    fi

    local total_pods injected_pods not_injected_pods
    total_pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)

    if [[ "$total_pods" -eq 0 ]]; then
      warn "Namespace $ns: nenhum pod encontrado"
      continue
    fi

    # Contar pods com linkerd-proxy nos containers
    injected_pods=$(kubectl get pods -n "$ns" \
      -o jsonpath='{range .items[*]}{.spec.containers[*].name}{"\n"}{end}' \
      2>/dev/null | grep -c "linkerd-proxy" || echo "0")

    not_injected_pods=$((total_pods - injected_pods))

    check
    if [[ "$injected_pods" -eq "$total_pods" ]]; then
      pass "Namespace $ns: $injected_pods/$total_pods pods com proxy Linkerd"
    elif [[ "$injected_pods" -gt 0 ]]; then
      warn "Namespace $ns: $injected_pods/$total_pods pods com proxy ($not_injected_pods SEM proxy)"
      info "Pods sem proxy (podem precisar de restart): kubectl rollout restart deploy -n $ns"
    else
      fail "Namespace $ns: NENHUM pod com proxy ($total_pods pods sem inject)"
      info "Verificar annotation: kubectl get ns $ns -o jsonpath='{.metadata.annotations}'"
    fi

    # Listar pods sem proxy (se houver)
    if [[ "$not_injected_pods" -gt 0 ]]; then
      info "Pods SEM linkerd-proxy em $ns:"
      kubectl get pods -n "$ns" -o json 2>/dev/null | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for pod in data.get('items', []):
    containers = [c['name'] for c in pod['spec'].get('containers', [])]
    if 'linkerd-proxy' not in containers:
        print(f'  - {pod[\"metadata\"][\"name\"]}')
" 2>/dev/null || true
    fi
  done
}

# ----- Verificacao 4: mTLS via Linkerd CLI ------------------------------------

check_mtls_status() {
  section "4. Status mTLS (requer Linkerd CLI)"

  if ! command -v linkerd &>/dev/null; then
    warn "Linkerd CLI nao disponivel — pulando verificacao mTLS detalhada"
    info "Instalar linkerd CLI para validacao completa de mTLS"
    return 0
  fi

  info "Status mTLS por namespace (linkerd viz stat ns):"
  linkerd viz stat ns 2>/dev/null || warn "linkerd viz nao disponivel"

  for ns in "${NAMESPACES[@]}"; do
    if ! kubectl get namespace "$ns" &>/dev/null; then
      continue
    fi

    echo ""
    info "=== Edges mTLS em $ns (linkerd viz edges) ==="
    linkerd viz edges deploy -n "$ns" 2>/dev/null || \
      warn "$ns: nao ha edges — proxy injection pode nao estar ativa ainda"
  done
}

# ----- Verificacao 5: Certificados mTLS ---------------------------------------

check_certificates() {
  section "5. Certificados mTLS (PKI)"

  # Verificar Secret do trust anchor
  check
  if kubectl get secret linkerd-trust-anchor -n linkerd &>/dev/null; then
    local expiry
    expiry=$(kubectl get secret linkerd-trust-anchor -n linkerd \
      -o jsonpath='{.data.tls\.crt}' 2>/dev/null | \
      base64 -d 2>/dev/null | \
      openssl x509 -noout -enddate 2>/dev/null | \
      sed 's/notAfter=//' || echo "nao determinado")
    pass "Secret linkerd-trust-anchor: presente (expiry: $expiry)"
  else
    warn "Secret linkerd-trust-anchor nao encontrado diretamente"
    info "PKI pode estar gerenciado pelo Terraform (normal)"
  fi

  # Via Linkerd CLI — expiry do trust anchor
  if command -v linkerd &>/dev/null; then
    check
    local anchor_expiry
    anchor_expiry=$(linkerd identity 2>/dev/null | grep "Valid Until" | head -1 || echo "indisponivel")
    if [[ "$anchor_expiry" != "indisponivel" ]]; then
      pass "Trust anchor expiry: $anchor_expiry"
    else
      warn "Trust anchor expiry: nao foi possivel determinar via CLI"
    fi
  fi

  # Verificar metrica de expiracao no Prometheus (se disponivel)
  info "Para verificar expiracao do trust anchor via PromQL:"
  info "  linkerd_identity_trust_anchors_expiration_timestamp_seconds - time() > 0"
  info "  (Deve ser > 2592000 = 30 dias para nao acionar alerta)"
}

# ----- Verificacao 6: AuthorizationPolicies -----------------------------------

check_authorization_policies() {
  section "6. AuthorizationPolicies"

  check
  local total_policies
  total_policies=$(kubectl get authorizationpolicies -A --no-headers 2>/dev/null | wc -l)
  local total_auth
  total_auth=$(kubectl get meshtlsauthentications -A --no-headers 2>/dev/null | wc -l)

  if [[ "$total_policies" -gt 0 ]]; then
    pass "AuthorizationPolicies: $total_policies criadas"
    kubectl get authorizationpolicies -A 2>/dev/null | head -20
  else
    warn "Nenhuma AuthorizationPolicy encontrada"
    info "Aplicar: kubectl apply -f domains/service-mesh/infra/linkerd/authorization-policies/"
  fi

  if [[ "$total_auth" -gt 0 ]]; then
    pass "MeshTLSAuthentications: $total_auth criadas"
  else
    warn "Nenhuma MeshTLSAuthentication encontrada"
  fi

  # Verificar Servers
  local total_servers
  total_servers=$(kubectl get servers -A --no-headers 2>/dev/null | wc -l)
  if [[ "$total_servers" -gt 0 ]]; then
    pass "Servers (policy targets): $total_servers criados"
  else
    warn "Nenhum Server encontrado — policies podem usar target Namespace"
  fi
}

# ----- Verificacao 7: ServiceProfiles -----------------------------------------

check_service_profiles() {
  section "7. ServiceProfiles (observabilidade por rota)"

  check
  local total_profiles
  total_profiles=$(kubectl get serviceprofiles -A --no-headers 2>/dev/null | wc -l)

  if [[ "$total_profiles" -gt 0 ]]; then
    pass "ServiceProfiles: $total_profiles criados"
    kubectl get serviceprofiles -A 2>/dev/null
  else
    warn "Nenhum ServiceProfile encontrado"
    info "Aplicar: kubectl apply -f domains/service-mesh/infra/linkerd/service-profiles/"
  fi
}

# ----- Relatorio Final --------------------------------------------------------

print_summary() {
  section "RESUMO DE VALIDACAO — GAP-011 mTLS"

  local compliance_status
  if [[ "$FAILED_CHECKS" -eq 0 ]]; then
    compliance_status="${GREEN}CONFORME${NC}"
  elif [[ "$FAILED_CHECKS" -le 2 ]]; then
    compliance_status="${YELLOW}PARCIALMENTE CONFORME${NC}"
  else
    compliance_status="${RED}NAO CONFORME${NC}"
  fi

  echo -e "Status Compliance BACEN BCB 85/2021: ${compliance_status}"
  echo ""
  echo -e "Total de verificacoes: ${TOTAL_CHECKS}"
  echo -e "${GREEN}PASS: ${PASSED_CHECKS}${NC}"
  echo -e "${YELLOW}WARN: ${WARNED_CHECKS}${NC}"
  echo -e "${RED}FAIL: ${FAILED_CHECKS}${NC}"
  echo ""

  if [[ "$FAILED_CHECKS" -gt 0 ]]; then
    echo -e "${RED}Acao necessaria:${NC}"
    echo "  1. Verificar namespace annotations (Fase 1/2/3 do rollout)"
    echo "  2. Reiniciar pods sem proxy: kubectl rollout restart deploy -n <namespace>"
    echo "  3. Aplicar AuthorizationPolicies: kubectl apply -f .../authorization-policies/"
  fi

  echo ""
  echo "Proximos passos apos compliance total:"
  echo "  - Configurar alertas Prometheus para expiracao de certificados"
  echo "  - Habilitar Grafana dashboards Linkerd (4 dashboards disponiveis)"
  echo "  - Monitorar latencia por 24h via: linkerd viz top deploy -n <ns>"
  echo ""

  # Data/hora do relatorio
  echo "Relatorio gerado: $(date '+%Y-%m-%d %H:%M:%S UTC%z')"
  echo "Cluster: $(kubectl config current-context 2>/dev/null || echo 'desconhecido')"
}

# ----- Main -------------------------------------------------------------------

main() {
  echo -e "${BOLD}${CYAN}"
  echo "================================================================"
  echo "  GAP-011: Linkerd mTLS Validation"
  echo "  BACEN BCB 85/2021 Compliance Check"
  echo "================================================================"
  echo -e "${NC}"

  local target_namespace=""
  local check_policies_only=false
  local check_profiles_only=false

  # Parse argumentos
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace|-n)
        target_namespace="${2:-}"
        shift 2
        ;;
      --check-policies)
        check_policies_only=true
        shift
        ;;
      --check-profiles)
        check_profiles_only=true
        shift
        ;;
      --report)
        # Modo relatorio — mesma saida, mas sem interatividade
        shift
        ;;
      *)
        echo "Argumento desconhecido: $1"
        echo "Uso: $0 [--namespace <ns>] [--check-policies] [--check-profiles] [--report]"
        exit 1
        ;;
    esac
  done

  # Se namespace especifico, sobrescrever array
  if [[ -n "$target_namespace" ]]; then
    NAMESPACES=("$target_namespace")
    info "Modo: namespace especifico ($target_namespace)"
  fi

  if "$check_policies_only"; then
    check_authorization_policies
    print_summary
    return
  fi

  if "$check_profiles_only"; then
    check_service_profiles
    print_summary
    return
  fi

  # Validacao completa
  check_control_plane
  check_namespace_annotations
  check_proxy_injection
  check_mtls_status
  check_certificates
  check_authorization_policies
  check_service_profiles
  print_summary

  # Exit code baseado em falhas
  if [[ "$FAILED_CHECKS" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
