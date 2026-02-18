#!/bin/bash
# =============================================================================
# Script: shutdown-marco2.sh
# Descrição: Stop nodes EKS + RDS + optional snapshot para Marco 2
# Uso: ./shutdown-marco2.sh [dev|staging|prod] [--snapshot]
# Autor: FinOps Team
# Data: 2026-01-29
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configurações
# -----------------------------------------------------------------------------

CLUSTER_NAME="k8s-platform-prod"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${1:-dev}"
SNAPSHOT_FLAG="${2:-}"  # --snapshot para criar snapshot antes de parar
LOG_FILE="/tmp/k8s-shutdown-$(date +%Y%m%d-%H%M%S).log"

# Node Groups
declare -A NODE_GROUPS=(
    ["system"]="0:0:4"      # min:desired:max
    ["workloads"]="0:0:6"
    ["critical"]="0:0:4"
)

# RDS instances (Marco 3 - PostgreSQL)
declare -A RDS_INSTANCES=(
    ["dev"]="k8s-platform-prod-postgresql"
    ["staging"]="k8s-platform-prod-postgresql"
    ["prod"]="k8s-platform-prod-postgresql"
)

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
        log_error "AWS CLI não encontrado"
        exit 1
    fi
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl não encontrado"
        exit 1
    fi
}

validate_environment() {
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Ambiente inválido: $ENVIRONMENT"
        exit 1
    fi
}

drain_critical_pods() {
    log "🔄 Drain de pods críticos (opcional, segurança)..."

    # Lista de recursos críticos para escalar gracefully antes do shutdown
    # Formato: "namespace:tipo:nome"
    local critical_deployments=(
        "monitoring:statefulset:prometheus-kube-prometheus-prometheus"
        "monitoring:deployment:kube-prometheus-stack-grafana"
        "monitoring:statefulset:loki-write"
    )

    for deploy in "${critical_deployments[@]}"; do
        IFS=':' read -r ns kind name <<< "$deploy"

        log "  → Scaling down $ns/$kind/$name"
        kubectl scale "$kind" "$name" -n "$ns" --replicas=0 2>&1 | tee -a "$LOG_FILE" || true
    done

    # Aguardar pods terminarem gracefully
    log "  → Aguardando pods terminarem (30s grace period)..."
    sleep 30
}

create_rds_snapshot() {
    local rds_name="${RDS_INSTANCES[$ENVIRONMENT]}"

    if [ -z "$rds_name" ]; then
        log_warning "Nenhuma instância RDS configurada para $ENVIRONMENT"
        return 0
    fi

    if [ "$SNAPSHOT_FLAG" != "--snapshot" ]; then
        log_warning "Pulando snapshot RDS (use --snapshot para criar)"
        return 0
    fi

    local snapshot_id="${rds_name}-shutdown-$(date +%Y%m%d-%H%M%S)"

    log "📸 Criando snapshot RDS: $snapshot_id"

    aws rds create-db-snapshot \
        --db-instance-identifier "$rds_name" \
        --db-snapshot-identifier "$snapshot_id" \
        --region "$AWS_REGION" \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=Type,Value=shutdown-snapshot \
        --output text >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        log_success "Snapshot $snapshot_id criado com sucesso"
        echo "$snapshot_id" > "/tmp/last-rds-snapshot-$ENVIRONMENT.txt"
    else
        log_error "Falha ao criar snapshot"
        return 1
    fi
}

stop_rds_instance() {
    local rds_name="${RDS_INSTANCES[$ENVIRONMENT]}"

    if [ -z "$rds_name" ]; then
        return 0
    fi

    log "🗄️  Parando RDS instance: $rds_name..."

    # Verificar status atual
    local status=$(aws rds describe-db-instances \
        --db-instance-identifier "$rds_name" \
        --region "$AWS_REGION" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null || echo "not-found")

    case "$status" in
        "stopped")
            log_success "RDS já está stopped: $rds_name"
            return 0
            ;;
        "backing-up")
            log "  → RDS está em backup, aguardando transição para available..."
            local wait_retries=30
            local wait_count=0
            while [ $wait_count -lt $wait_retries ]; do
                sleep 10
                ((wait_count++))
                status=$(aws rds describe-db-instances \
                    --db-instance-identifier "$rds_name" \
                    --region "$AWS_REGION" \
                    --query 'DBInstances[0].DBInstanceStatus' \
                    --output text 2>/dev/null || echo "unknown")
                log "  → RDS status: $status (aguardando... $wait_count/$wait_retries)"
                if [ "$status" == "available" ]; then
                    break
                fi
            done
            if [ "$status" != "available" ]; then
                log_warning "RDS não transitou para available em 5min. Stop manual necessário."
                return 0
            fi
            log "  → RDS está available, parando..."
            if aws rds stop-db-instance \
                --db-instance-identifier "$rds_name" \
                --region "$AWS_REGION" \
                --output text >> "$LOG_FILE" 2>&1; then
                log_success "RDS $rds_name stop initiated"
            else
                log_error "Falha ao parar RDS $rds_name"
                return 1
            fi
            ;;
        "available")
            log "  → RDS está available, parando..."
            aws rds stop-db-instance \
                --db-instance-identifier "$rds_name" \
                --region "$AWS_REGION" \
                --output text >> "$LOG_FILE" 2>&1

            if [ $? -eq 0 ]; then
                log_success "RDS $rds_name stop initiated"
            else
                log_error "Falha ao parar RDS $rds_name"
                return 1
            fi
            ;;
        "stopping")
            log_warning "RDS já está em processo de stop"
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

stop_node_groups() {
    log "🛑 Parando node groups do cluster $CLUSTER_NAME..."

    for ng_name in "${!NODE_GROUPS[@]}"; do
        IFS=':' read -r min desired max <<< "${NODE_GROUPS[$ng_name]}"

        log "  → Scaling node group: $ng_name (min=$min, desired=$desired)"

        aws eks update-nodegroup-config \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "$ng_name" \
            --scaling-config minSize="$min",desiredSize="$desired",maxSize="$max" \
            --region "$AWS_REGION" \
            --output text >> "$LOG_FILE" 2>&1

        if [ $? -eq 0 ]; then
            log_success "Node group $ng_name scaled to 0"
        else
            log_error "Falha ao escalar node group $ng_name"
            return 1
        fi
    done
}

wait_for_nodes_termination() {
    log "⏳ Aguardando nodes terminarem..."

    local max_retries=30
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' \n' || echo 0)

        if [ "$node_count" -eq 0 ]; then
            log_success "Todos os nodes foram terminados"
            return 0
        fi

        log "  → Nodes restantes: $node_count (tentativa $((retry_count+1))/$max_retries)"
        sleep 10
        ((retry_count++))
    done

    log_error "Timeout aguardando nodes terminarem. Ainda existem $node_count nodes"
    return 1
}

verify_shutdown() {
    log "🔍 Verificando shutdown completo..."

    # Check nodes
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' \n' || echo -1)

    if [ "$node_count" -eq 0 ]; then
        log_success "Nodes: 0 (shutdown completo)"
    elif [ "$node_count" -eq -1 ]; then
        log_warning "Nodes: Não foi possível verificar (cluster pode estar offline)"
    else
        log_error "Nodes: $node_count ainda running"
    fi

    # Check RDS
    if [ -n "${RDS_INSTANCES[$ENVIRONMENT]}" ]; then
        local rds_status=$(aws rds describe-db-instances \
            --db-instance-identifier "${RDS_INSTANCES[$ENVIRONMENT]}" \
            --region "$AWS_REGION" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "unknown")

        if [ "$rds_status" == "stopped" ]; then
            log_success "RDS: stopped"
        else
            log_warning "RDS: $rds_status (pode ainda estar stopping)"
        fi
    fi
}

calculate_savings() {
    log ""
    log "💰 Economia Estimada (24h shutdown):"
    log ""

    # Cálculo baseado no documento STARTUP-SHUTDOWN-STRATEGY.md
    local ec2_hourly_cost=0.2914  # 7 nodes × $30.37/730h
    local data_transfer_daily=0.75
    local alb_lcu_daily=0.33

    local daily_savings=$(echo "$ec2_hourly_cost * 24 + $data_transfer_daily + $alb_lcu_daily" | bc)

    log "  → EC2 Nodes: \$$(echo "$ec2_hourly_cost * 24" | bc)/dia"
    log "  → Data Transfer: \$$data_transfer_daily/dia"
    log "  → ALB LCU: \$$alb_lcu_daily/dia"
    log ""
    log "  → TOTAL: ~\$$(printf "%.2f" "$daily_savings")/dia"
    log "  → Mensal (22 dias úteis): ~\$$(echo "$daily_savings * 22" | bc)/mês"
    log ""
}

print_summary() {
    log ""
    log "=================================================="
    log "          SHUTDOWN SUMMARY - $ENVIRONMENT"
    log "=================================================="
    log ""
    log "Cluster: $CLUSTER_NAME"
    log "Region: $AWS_REGION"
    log "Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' \n' || echo "N/A")"

    if [ -n "${RDS_INSTANCES[$ENVIRONMENT]}" ]; then
        local rds_status=$(aws rds describe-db-instances \
            --db-instance-identifier "${RDS_INSTANCES[$ENVIRONMENT]}" \
            --region "$AWS_REGION" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "unknown")
        log "RDS: $rds_status"
    fi

    if [ "$SNAPSHOT_FLAG" == "--snapshot" ] && [ -f "/tmp/last-rds-snapshot-$ENVIRONMENT.txt" ]; then
        log "Snapshot: $(cat /tmp/last-rds-snapshot-$ENVIRONMENT.txt)"
    fi

    log "Log: $LOG_FILE"
    log ""
    log "=================================================="
}

send_notification() {
    local status="$1"
    local message="$2"
    local topic_arn="arn:aws:sns:us-east-1:891377105802:k8s-platform-prod-finops-alerts-staging"

    log "📢 Notification: $status - $message"

    aws sns publish \
        --topic-arn "$topic_arn" \
        --subject "[$status] EKS Shutdown - $ENVIRONMENT" \
        --message "$(printf 'Environment: %s\nCluster: %s\nStatus: %s\nMessage: %s\nTimestamp: %s' \
            "$ENVIRONMENT" "$CLUSTER_NAME" "$status" "$message" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")" \
        --region "$AWS_REGION" \
        --output text >> "$LOG_FILE" 2>&1 \
        || log_warning "SNS publish falhou (non-fatal)"
}

show_restart_instructions() {
    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "📋 INSTRUÇÕES PARA RESTART:"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""
    log "Para reiniciar o ambiente, execute:"
    log ""
    log "  ./startup-marco2.sh $ENVIRONMENT"
    log ""

    if [ "$SNAPSHOT_FLAG" == "--snapshot" ]; then
        log "RDS será restaurado do snapshot:"
        log "  $(cat /tmp/last-rds-snapshot-$ENVIRONMENT.txt 2>/dev/null || echo 'último snapshot')"
        log ""
    fi

    log "Tempo estimado de restart: 5-7 minutos"
    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    log "=================================================="
    log "  EKS + RDS Shutdown Script - Marco 2"
    log "  Environment: $ENVIRONMENT"
    log "  Snapshot: ${SNAPSHOT_FLAG:-no}"
    log "=================================================="
    log ""

    # Pre-flight checks
    check_aws_cli
    check_kubectl
    validate_environment

    # Confirmação de segurança para produção
    if [ "$ENVIRONMENT" == "prod" ]; then
        log_warning "⚠️  ATENÇÃO: Você está prestes a desligar PRODUÇÃO!"
        log_warning "Pressione Ctrl+C nos próximos 10 segundos para cancelar..."
        sleep 10
    fi

    # Update kubeconfig
    log "📝 Atualizando kubeconfig..."
    aws eks update-kubeconfig \
        --name "$CLUSTER_NAME" \
        --region "$AWS_REGION" >> "$LOG_FILE" 2>&1

    # Shutdown sequence
    drain_critical_pods || log_warning "Drain falhou, continuando..."

    create_rds_snapshot || log_warning "Snapshot falhou, continuando com stop..."
    stop_rds_instance || log_warning "RDS stop teve problemas"

    stop_node_groups || { log_error "Falha ao parar node groups"; exit 1; }
    wait_for_nodes_termination || log_warning "Alguns nodes podem ainda estar terminando"

    verify_shutdown
    calculate_savings
    print_summary

    show_restart_instructions

    log_success "✅ Shutdown concluído com sucesso!"
    send_notification "SUCCESS" "Environment $ENVIRONMENT stopped successfully"
}

# Execute main
main "$@"
