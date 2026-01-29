#!/bin/bash
# =============================================================================
# Script: startup-marco2.sh
# Descrição: Start nodes EKS + RDS para Marco 2 (Development/Staging)
# Uso: ./startup-marco2.sh [dev|staging|prod]
# Autor: FinOps Team
# Data: 2026-01-29
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configurações
# -----------------------------------------------------------------------------

CLUSTER_NAME="k8s-platform-prod"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${1:-dev}"  # dev, staging, prod
LOG_FILE="/tmp/k8s-startup-$(date +%Y%m%d-%H%M%S).log"

# Node Groups configurações
declare -A NODE_GROUPS=(
    ["system"]="2:2:4"      # min:desired:max
    ["workloads"]="2:3:6"
    ["critical"]="2:2:4"
)

# RDS instances por ambiente
declare -A RDS_INSTANCES=(
    ["dev"]="gitlab-dev"
    ["staging"]="gitlab-staging"
    ["prod"]="gitlab-prod"
)

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Funções
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

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI não encontrado. Instale com: pip install awscli"
        exit 1
    fi
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl não encontrado. Instale com: curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        exit 1
    fi
}

validate_environment() {
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Ambiente inválido: $ENVIRONMENT. Use: dev, staging ou prod"
        exit 1
    fi
}

start_node_groups() {
    log "🚀 Iniciando node groups do cluster $CLUSTER_NAME..."

    for ng_name in "${!NODE_GROUPS[@]}"; do
        IFS=':' read -r min desired max <<< "${NODE_GROUPS[$ng_name]}"

        log "  → Scaling node group: $ng_name (min=$min, desired=$desired, max=$max)"

        aws eks update-nodegroup-config \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "$ng_name" \
            --scaling-config minSize="$min",desiredSize="$desired",maxSize="$max" \
            --region "$AWS_REGION" \
            --output text >> "$LOG_FILE" 2>&1

        if [ $? -eq 0 ]; then
            log_success "Node group $ng_name scaled successfully"
        else
            log_error "Falha ao escalar node group $ng_name"
            return 1
        fi
    done
}

wait_for_nodes() {
    log "⏳ Aguardando nodes ficarem Ready..."

    local max_retries=30
    local retry_count=0
    local expected_nodes=7  # 2+3+2

    while [ $retry_count -lt $max_retries ]; do
        ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c Ready || echo 0)

        if [ "$ready_nodes" -ge "$expected_nodes" ]; then
            log_success "Todos os $ready_nodes nodes estão Ready"
            kubectl get nodes
            return 0
        fi

        log "  → Nodes Ready: $ready_nodes/$expected_nodes (tentativa $((retry_count+1))/$max_retries)"
        sleep 10
        ((retry_count++))
    done

    log_error "Timeout aguardando nodes. Apenas $ready_nodes/$expected_nodes Ready"
    return 1
}

start_rds_instance() {
    local rds_name="${RDS_INSTANCES[$ENVIRONMENT]}"

    if [ -z "$rds_name" ]; then
        log_warning "Nenhuma instância RDS configurada para $ENVIRONMENT"
        return 0
    fi

    log "🗄️  Iniciando RDS instance: $rds_name..."

    # Verificar status atual
    local status=$(aws rds describe-db-instances \
        --db-instance-identifier "$rds_name" \
        --region "$AWS_REGION" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null || echo "not-found")

    case "$status" in
        "available")
            log_success "RDS já está available: $rds_name"
            return 0
            ;;
        "stopped")
            log "  → RDS está stopped, iniciando..."
            aws rds start-db-instance \
                --db-instance-identifier "$rds_name" \
                --region "$AWS_REGION" \
                --output text >> "$LOG_FILE" 2>&1

            if [ $? -eq 0 ]; then
                log_success "RDS $rds_name start initiated"
            else
                log_error "Falha ao iniciar RDS $rds_name"
                return 1
            fi
            ;;
        "starting")
            log_warning "RDS já está em processo de start"
            ;;
        "not-found")
            log_error "RDS instance $rds_name não encontrada"
            return 1
            ;;
        *)
            log_warning "RDS em estado inesperado: $status"
            ;;
    esac
}

wait_for_rds() {
    local rds_name="${RDS_INSTANCES[$ENVIRONMENT]}"

    if [ -z "$rds_name" ]; then
        return 0
    fi

    log "⏳ Aguardando RDS ficar available..."

    local max_retries=30
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        status=$(aws rds describe-db-instances \
            --db-instance-identifier "$rds_name" \
            --region "$AWS_REGION" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "error")

        if [ "$status" == "available" ]; then
            log_success "RDS $rds_name está available"
            return 0
        fi

        log "  → RDS status: $status (tentativa $((retry_count+1))/$max_retries)"
        sleep 10
        ((retry_count++))
    done

    log_error "Timeout aguardando RDS. Status atual: $status"
    return 1
}

verify_platform_pods() {
    log "🔍 Verificando pods da plataforma..."

    local critical_namespaces=("observability" "kube-system")

    for ns in "${critical_namespaces[@]}"; do
        log "  → Namespace: $ns"
        kubectl get pods -n "$ns" -o wide 2>&1 | tee -a "$LOG_FILE"
    done
}

print_summary() {
    log ""
    log "=================================================="
    log "           STARTUP SUMMARY - $ENVIRONMENT"
    log "=================================================="
    log ""
    log "Cluster: $CLUSTER_NAME"
    log "Region: $AWS_REGION"
    log "Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo 0)/7"

    if [ -n "${RDS_INSTANCES[$ENVIRONMENT]}" ]; then
        local rds_status=$(aws rds describe-db-instances \
            --db-instance-identifier "${RDS_INSTANCES[$ENVIRONMENT]}" \
            --region "$AWS_REGION" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "unknown")
        log "RDS: $rds_status"
    fi

    log "Log: $LOG_FILE"
    log ""
    log "=================================================="
}

send_notification() {
    local status="$1"
    local message="$2"

    # TODO: Integrar com SNS/Slack
    log "📢 Notification: $status - $message"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    log "=================================================="
    log "  EKS + RDS Startup Script - Marco 2"
    log "  Environment: $ENVIRONMENT"
    log "=================================================="
    log ""

    # Pre-flight checks
    check_aws_cli
    check_kubectl
    validate_environment

    # Update kubeconfig
    log "📝 Atualizando kubeconfig..."
    aws eks update-kubeconfig \
        --name "$CLUSTER_NAME" \
        --region "$AWS_REGION" >> "$LOG_FILE" 2>&1

    # Start resources
    start_node_groups || { log_error "Falha ao iniciar node groups"; exit 1; }
    wait_for_nodes || { log_error "Falha aguardando nodes"; exit 1; }

    start_rds_instance || { log_warning "RDS start teve problemas"; }
    wait_for_rds || { log_warning "RDS pode não estar ready"; }

    verify_platform_pods

    print_summary

    log_success "✅ Startup concluído com sucesso!"
    send_notification "SUCCESS" "Environment $ENVIRONMENT started successfully"
}

# Execute main
main "$@"
