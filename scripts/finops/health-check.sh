#!/bin/bash
# =============================================================================
# Script: health-check.sh
# Descrição: Validação pós-startup da infraestrutura Marco 2
# Uso: ./health-check.sh
# Autor: FinOps Team
# Data: 2026-01-29
# ADR: ADR-022 (Startup/Shutdown Automation Strategy)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configurações
# -----------------------------------------------------------------------------

CLUSTER_NAME="k8s-platform-prod"
AWS_REGION="${AWS_REGION:-us-east-1}"
MONITORING_NAMESPACE="monitoring"
LOG_FILE="/tmp/health-check-$(date +%Y%m%d-%H%M%S).log"

# Componentes esperados por namespace
declare -A EXPECTED_PODS=(
    ["monitoring:prometheus"]="2"           # prometheus-kube-prometheus-stack-prometheus-0, prometheus-operator
    ["monitoring:grafana"]="1"              # kube-prometheus-stack-grafana
    ["monitoring:alertmanager"]="1"         # alertmanager-kube-prometheus-stack-alertmanager-0
    ["kube-system:aws-load-balancer"]="1"   # aws-load-balancer-controller
    ["kube-system:cert-manager"]="3"        # cert-manager, cert-manager-cainjector, cert-manager-webhook
    ["kube-system:cluster-autoscaler"]="1"  # cluster-autoscaler-aws-cluster-autoscaler
)

# Thresholds
MIN_NODES=2
MAX_POD_RESTART=5
GRAFANA_TIMEOUT=30

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Funções de Logging
# -----------------------------------------------------------------------------

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[i]${NC} $*" | tee -a "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# Health Check Functions
# -----------------------------------------------------------------------------

check_prerequisites() {
    log_info "Verificando pré-requisitos..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl não encontrado"
        return 1
    fi

    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI não encontrado"
        return 1
    fi

    # Update kubeconfig
    aws eks update-kubeconfig \
        --name "$CLUSTER_NAME" \
        --region "$AWS_REGION" >> "$LOG_FILE" 2>&1

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Não foi possível conectar ao cluster $CLUSTER_NAME"
        return 1
    fi

    log_success "Pré-requisitos OK"
    return 0
}

check_nodes() {
    log_info "Verificando nodes..."

    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | grep -c Ready || echo 0)

    if [ "$node_count" -lt "$MIN_NODES" ]; then
        log_error "Nodes insuficientes: $node_count/$MIN_NODES (mínimo esperado)"
        kubectl get nodes 2>&1 | tee -a "$LOG_FILE"
        return 1
    fi

    log_success "Nodes OK: $node_count nodes Ready"

    # Detalhar nodes
    kubectl get nodes -o wide 2>&1 | tee -a "$LOG_FILE"

    return 0
}

check_monitoring_stack() {
    log_info "Verificando stack de monitoramento..."

    local failed=0

    # Verificar namespace monitoring existe
    if ! kubectl get namespace "$MONITORING_NAMESPACE" &> /dev/null; then
        log_error "Namespace $MONITORING_NAMESPACE não encontrado"
        return 1
    fi

    # Verificar pods críticos
    log "  → Pods no namespace $MONITORING_NAMESPACE:"
    kubectl get pods -n "$MONITORING_NAMESPACE" -o wide 2>&1 | tee -a "$LOG_FILE"

    # Contar pods Running vs esperados
    local total_pods=$(kubectl get pods -n "$MONITORING_NAMESPACE" --no-headers 2>/dev/null | wc -l)
    local running_pods=$(kubectl get pods -n "$MONITORING_NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)

    log_info "Pods Running: $running_pods/$total_pods"

    if [ "$running_pods" -eq 0 ]; then
        log_error "Nenhum pod Running no namespace $MONITORING_NAMESPACE"
        return 1
    fi

    # Verificar pods específicos críticos
    local critical_pods=(
        "prometheus-kube-prometheus-stack-prometheus-0"
        "kube-prometheus-stack-grafana"
        "alertmanager-kube-prometheus-stack-alertmanager-0"
    )

    for pod in "${critical_pods[@]}"; do
        local status=$(kubectl get pod "$pod" -n "$MONITORING_NAMESPACE" \
            --no-headers 2>/dev/null | awk '{print $3}' || echo "NotFound")

        if [ "$status" == "Running" ]; then
            log_success "Pod $pod: Running"
        else
            log_error "Pod $pod: $status"
            ((failed++))
        fi
    done

    # Verificar restarts excessivos
    local high_restart_pods=$(kubectl get pods -n "$MONITORING_NAMESPACE" --no-headers 2>/dev/null | \
        awk -v max="$MAX_POD_RESTART" '$4 > max {print $1 " (" $4 " restarts)"}')

    if [ -n "$high_restart_pods" ]; then
        log_warning "Pods com restarts excessivos (>$MAX_POD_RESTART):"
        echo "$high_restart_pods" | while read -r line; do
            log_warning "  → $line"
        done
    fi

    if [ "$failed" -gt 0 ]; then
        log_error "Falhas detectadas em $failed pods críticos"
        return 1
    fi

    log_success "Stack de monitoramento OK"
    return 0
}

check_platform_services() {
    log_info "Verificando serviços da plataforma..."

    local failed=0

    # AWS Load Balancer Controller
    if kubectl get deployment -n kube-system aws-load-balancer-controller &> /dev/null; then
        local ready=$(kubectl get deployment -n kube-system aws-load-balancer-controller \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
        if [ "$ready" -ge 1 ]; then
            log_success "AWS Load Balancer Controller: Ready ($ready replicas)"
        else
            log_error "AWS Load Balancer Controller: Not Ready"
            ((failed++))
        fi
    else
        log_warning "AWS Load Balancer Controller: Not deployed"
    fi

    # Cert-Manager
    if kubectl get deployment -n kube-system cert-manager &> /dev/null; then
        local ready=$(kubectl get deployment -n kube-system cert-manager \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
        if [ "$ready" -ge 1 ]; then
            log_success "Cert-Manager: Ready ($ready replicas)"
        else
            log_error "Cert-Manager: Not Ready"
            ((failed++))
        fi
    else
        log_warning "Cert-Manager: Not deployed"
    fi

    # Cluster Autoscaler
    if kubectl get deployment -n kube-system cluster-autoscaler-aws-cluster-autoscaler &> /dev/null; then
        local ready=$(kubectl get deployment -n kube-system cluster-autoscaler-aws-cluster-autoscaler \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
        if [ "$ready" -ge 1 ]; then
            log_success "Cluster Autoscaler: Ready ($ready replicas)"
        else
            log_error "Cluster Autoscaler: Not Ready"
            ((failed++))
        fi
    else
        log_warning "Cluster Autoscaler: Not deployed"
    fi

    if [ "$failed" -gt 0 ]; then
        log_error "Falhas detectadas em $failed serviços da plataforma"
        return 1
    fi

    log_success "Serviços da plataforma OK"
    return 0
}

check_grafana_ui() {
    log_info "Verificando Grafana UI..."

    # Port-forward temporário para teste
    kubectl port-forward -n "$MONITORING_NAMESPACE" svc/kube-prometheus-stack-grafana 13000:80 >> "$LOG_FILE" 2>&1 &
    local pf_pid=$!

    sleep 3  # Aguardar port-forward estabilizar

    # Testar endpoint
    local grafana_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:13000/api/health 2>/dev/null || echo "000")

    # Matar port-forward
    kill $pf_pid 2>/dev/null || true

    if [ "$grafana_response" == "200" ]; then
        log_success "Grafana UI: Acessível (HTTP $grafana_response)"
        return 0
    else
        log_error "Grafana UI: Não acessível (HTTP $grafana_response)"
        return 1
    fi
}

check_pvcs() {
    log_info "Verificando PVCs (Persistent Volume Claims)..."

    local failed=0

    # PVCs no namespace monitoring
    local pvc_list=$(kubectl get pvc -n "$MONITORING_NAMESPACE" --no-headers 2>/dev/null | \
        awk '{print $1 " " $2}')

    if [ -z "$pvc_list" ]; then
        log_warning "Nenhum PVC encontrado em $MONITORING_NAMESPACE"
        return 0
    fi

    echo "$pvc_list" | while read -r pvc_name pvc_status; do
        if [ "$pvc_status" == "Bound" ]; then
            log_success "PVC $pvc_name: Bound"
        else
            log_error "PVC $pvc_name: $pvc_status"
            ((failed++))
        fi
    done

    if [ "$failed" -gt 0 ]; then
        log_error "Falhas detectadas em $failed PVCs"
        return 1
    fi

    log_success "PVCs OK"
    return 0
}

check_s3_backend() {
    log_info "Verificando S3 backends..."

    local buckets=(
        "terraform-state-marco0-891377105802"
        "k8s-platform-loki-891377105802"
    )

    local failed=0

    for bucket in "${buckets[@]}"; do
        if aws s3 ls "s3://$bucket" &> /dev/null; then
            log_success "S3 bucket $bucket: Acessível"
        else
            log_error "S3 bucket $bucket: Não acessível"
            ((failed++))
        fi
    done

    if [ "$failed" -gt 0 ]; then
        log_error "Falhas detectadas em $failed buckets S3"
        return 1
    fi

    log_success "S3 backends OK"
    return 0
}

# -----------------------------------------------------------------------------
# Summary & Reporting
# -----------------------------------------------------------------------------

print_summary() {
    local total_checks=$1
    local passed_checks=$2
    local failed_checks=$3

    log ""
    log "=================================================="
    log "          HEALTH CHECK SUMMARY"
    log "=================================================="
    log ""
    log "Cluster: $CLUSTER_NAME"
    log "Region: $AWS_REGION"
    log "Timestamp: $(date +'%Y-%m-%d %H:%M:%S')"
    log ""
    log "Checks executados: $total_checks"
    log "Sucesso: $passed_checks"
    log "Falhas: $failed_checks"
    log ""

    if [ "$failed_checks" -eq 0 ]; then
        log_success "✅ INFRAESTRUTURA SAUDÁVEL"
        log ""
        log "Próximos passos:"
        log "  → Grafana UI: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
        log "  → Prometheus UI: kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
        log "  → Acesso Grafana: http://localhost:3000 (admin/prom-operator)"
    else
        log_error "⚠️  INFRAESTRUTURA COM PROBLEMAS"
        log ""
        log "Troubleshooting:"
        log "  → Verificar pods com erro: kubectl get pods -A | grep -v Running"
        log "  → Logs de um pod: kubectl logs <pod-name> -n <namespace>"
        log "  → Descrever pod: kubectl describe pod <pod-name> -n <namespace>"
    fi

    log ""
    log "Log completo: $LOG_FILE"
    log "=================================================="
    log ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    local total_checks=0
    local passed_checks=0
    local failed_checks=0

    log "=================================================="
    log "  Marco 2 - Infrastructure Health Check"
    log "  ADR-022: Startup/Shutdown Automation"
    log "=================================================="
    log ""

    # Array de checks (função:descrição)
    local checks=(
        "check_prerequisites:Pré-requisitos"
        "check_nodes:Nodes"
        "check_monitoring_stack:Stack Monitoramento"
        "check_platform_services:Serviços Plataforma"
        "check_grafana_ui:Grafana UI"
        "check_pvcs:PVCs"
        "check_s3_backend:S3 Backends"
    )

    for check in "${checks[@]}"; do
        IFS=':' read -r func desc <<< "$check"

        log ""
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "Check: $desc"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        ((total_checks++))

        if $func; then
            ((passed_checks++))
        else
            ((failed_checks++))
        fi
    done

    print_summary "$total_checks" "$passed_checks" "$failed_checks"

    # Exit code baseado em falhas
    if [ "$failed_checks" -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Execute main
main "$@"
