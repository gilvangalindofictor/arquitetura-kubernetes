#!/usr/bin/env bash
# ==============================================================================
# prod-startup-healthcheck.sh
# Mesa Técnica Resiliência — Startup K8s Prod (GAP-FINOPS-CNI-01)
# 2026-03-23
#
# Uso: ./prod-startup-healthcheck.sh
#   ou: CLUSTER_NAME=k8s-platform-prod AWS_REGION=us-east-1 ./prod-startup-healthcheck.sh
#
# Execução recomendada: após UP FinOps (07h30 BRT) ou via SSM Run Command
# ==============================================================================

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-k8s-platform-prod}"
REGION="${AWS_REGION:-us-east-1}"
CNI_NAMESPACE="linkerd-cni"
LINKERD_NAMESPACE="linkerd"
VAULT_NAMESPACE="prod-security-vault"
CA_NAMESPACE="kube-system"
CA_DEPLOYMENT="cluster-autoscaler"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC}  $*"; }
log_info() { echo "[INFO]  $*"; }

ERRORS=0
WARNINGS=0

# ------------------------------------------------------------------------------
# CHECK 1: linkerd-cni — token Unauthorized detectado → auto-fix
# GAP-FINOPS-CNI-01: Token JWT do host kubeconfig expira após 24h (weekends/feriados)
# ------------------------------------------------------------------------------
check_cni_tokens() {
    log_info "CHECK 1: linkerd-cni token status..."

    local pods_running
    pods_running=$(kubectl get pods -n "$CNI_NAMESPACE" --field-selector=status.phase=Running \
        --no-headers 2>/dev/null | wc -l || echo "0")
    local pods_total
    pods_total=$(kubectl get pods -n "$CNI_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")

    if [[ "${pods_total:-0}" -eq 0 ]]; then
        log_fail "CHECK 1 FAIL: Nenhum pod linkerd-cni encontrado"
        ((ERRORS++)); return
    fi

    # Detectar Unauthorized nos logs recentes de todos os pods CNI
    local unauthorized_count=0
    while read -r pod_name; do
        [[ -z "$pod_name" ]] && continue
        local unauth
        unauth=$(kubectl logs "$pod_name" -n "$CNI_NAMESPACE" --since=15m 2>/dev/null \
            | grep -c "Unauthorized\|401\|token.*expired" || true)
        [[ "$unauth" -gt 0 ]] && ((unauthorized_count++))
    done < <(kubectl get pods -n "$CNI_NAMESPACE" --no-headers -o custom-columns="NAME:.metadata.name" 2>/dev/null)

    if [[ "$unauthorized_count" -gt 0 ]]; then
        log_fail "CHECK 1 FAIL: $unauthorized_count pods CNI com Unauthorized (token expirado)"
        log_info "  GAP-FINOPS-CNI-01: executando rollout restart automático..."
        kubectl rollout restart daemonset/linkerd-cni -n "$CNI_NAMESPACE"
        log_info "  Aguardando rollout (180s)..."
        kubectl rollout status daemonset/linkerd-cni -n "$CNI_NAMESPACE" --timeout=180s \
            && log_ok "  rollout restart concluído — tokens renovados" \
            || log_fail "  rollout timeout — verificar manualmente"
        ((ERRORS++))
    elif [[ "$pods_running" -lt "$pods_total" ]]; then
        log_warn "CHECK 1 WARN: $pods_running/$pods_total pods Running (startup em progresso?)"
        ((WARNINGS++))
    else
        log_ok "CHECK 1: linkerd-cni $pods_running/$pods_total Running, sem Unauthorized"
    fi
}

# ------------------------------------------------------------------------------
# CHECK 2: Linkerd control plane
# ------------------------------------------------------------------------------
check_linkerd_control_plane() {
    log_info "CHECK 2: Linkerd control plane..."
    local fail=0
    for comp in linkerd-destination linkerd-identity linkerd-proxy-injector; do
        local running
        running=$(kubectl get pods -n "$LINKERD_NAMESPACE" --no-headers 2>/dev/null \
            | grep "^${comp}" | grep -c Running || true)
        if [[ "$running" -lt 1 ]]; then
            log_fail "  $comp: 0 pods Running"
            ((fail++))
        else
            log_ok "  $comp: $running Running"
        fi
    done
    if [[ "$fail" -gt 0 ]]; then
        log_fail "CHECK 2 FAIL: $fail componentes Linkerd não Ready"
        ((ERRORS++))
    else
        log_ok "CHECK 2: Linkerd control plane 3/3 Ready"
    fi
}

# ------------------------------------------------------------------------------
# CHECK 3: Cluster Autoscaler
# ------------------------------------------------------------------------------
check_cluster_autoscaler() {
    log_info "CHECK 3: Cluster Autoscaler..."
    local ready
    ready=$(kubectl get deployment "$CA_DEPLOYMENT" -n "$CA_NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "${ready:-0}" -lt 1 ]]; then
        log_fail "CHECK 3 FAIL: Cluster Autoscaler 0 replicas Ready"
        kubectl get pods -n "$CA_NAMESPACE" | grep -i autoscaler || true
        ((ERRORS++))
    else
        log_ok "CHECK 3: Cluster Autoscaler $ready replica(s) Ready"
    fi
}

# ------------------------------------------------------------------------------
# CHECK 4: Vault prod
# ------------------------------------------------------------------------------
check_vault() {
    log_info "CHECK 4: Vault prod..."
    if ! kubectl get namespace "$VAULT_NAMESPACE" &>/dev/null; then
        log_warn "CHECK 4 WARN: Namespace $VAULT_NAMESPACE não encontrado"
        ((WARNINGS++)); return
    fi
    local vault_pod
    vault_pod=$(kubectl get pods -n "$VAULT_NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -z "$vault_pod" ]]; then
        log_fail "CHECK 4 FAIL: Nenhum pod vault em $VAULT_NAMESPACE"
        ((ERRORS++)); return
    fi
    local sealed
    sealed=$(kubectl exec -n "$VAULT_NAMESPACE" "$vault_pod" -- \
        vault status 2>/dev/null | grep "^Sealed" | awk '{print $2}' || echo "unknown")
    if [[ "$sealed" == "true" ]]; then
        log_fail "CHECK 4 FAIL: Vault SEALED — KMS auto-unseal falhou"
        ((ERRORS++))
    elif [[ "$sealed" == "unknown" ]]; then
        log_warn "CHECK 4 WARN: Não foi possível verificar Vault status"
        ((WARNINGS++))
    else
        log_ok "CHECK 4: Vault unsealed ($vault_pod)"
    fi
}

# ------------------------------------------------------------------------------
# CHECK 5: Pods Pending (threshold: 10)
# ------------------------------------------------------------------------------
check_pending_pods() {
    log_info "CHECK 5: Pods Pending..."
    local count
    count=$(kubectl get pods -A --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$count" -gt 10 ]]; then
        log_fail "CHECK 5 FAIL: $count pods Pending (threshold 10)"
        kubectl get pods -A --field-selector=status.phase=Pending --no-headers \
            | awk '{print $1}' | sort | uniq -c | sort -rn | head -5
        ((ERRORS++))
    elif [[ "$count" -gt 0 ]]; then
        log_warn "CHECK 5 WARN: $count pods Pending (startup normal?)"
        ((WARNINGS++))
    else
        log_ok "CHECK 5: 0 pods Pending"
    fi
}

# ------------------------------------------------------------------------------
# RESUMO
# ------------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "========================================================"
    echo " STARTUP HEALTH CHECK — $(date '+%Y-%m-%d %H:%M:%S BRT')"
    echo " Cluster: $CLUSTER_NAME"
    echo "========================================================"
    if [[ "$ERRORS" -eq 0 && "$WARNINGS" -eq 0 ]]; then
        log_ok "RESULTADO: HEALTHY — ambiente pronto"
    elif [[ "$ERRORS" -eq 0 ]]; then
        log_warn "RESULTADO: DEGRADED ($WARNINGS warnings) — monitorar"
    else
        log_fail "RESULTADO: UNHEALTHY ($ERRORS erros, $WARNINGS warnings)"
        log_fail "AÇÃO: resolver itens FAIL antes de declarar saudável"
    fi
    echo "========================================================"
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
main() {
    echo "========================================================"
    echo " K8s Prod — Startup Health Check (GAP-FINOPS-CNI-01)"
    echo " $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================================"
    echo ""

    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" 2>/dev/null \
        || log_warn "kubeconfig não atualizado — usando contexto existente"

    check_cni_tokens
    check_linkerd_control_plane
    check_cluster_autoscaler
    check_vault
    check_pending_pods
    print_summary

    [[ "$ERRORS" -eq 0 ]]
}

main "$@"
