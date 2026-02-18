#!/bin/bash
# =============================================================================
# Script: validate-shutdown.sh
# Descrição: Validação pós-shutdown — verifica estado dos recursos e estima economia
# Uso: ./validate-shutdown.sh [dev|staging|prod]
# Autor: FinOps Team
# Data: 2026-02-18
# =============================================================================

set -euo pipefail

CLUSTER_NAME="k8s-platform-prod"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${1:-staging}"
LOG_FILE="/tmp/k8s-validate-shutdown-$(date +%Y%m%d-%H%M%S).log"

declare -A RDS_INSTANCES=(
    ["dev"]="k8s-platform-prod-postgresql"
    ["staging"]="k8s-platform-prod-postgresql"
    ["prod"]="k8s-platform-prod-postgresql"
)

# Node Groups esperados em shutdown (desiredSize=0)
EXPECTED_NODE_GROUPS=("system" "workloads" "critical")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

log() { echo -e "[$(date +'%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
pass() { echo -e "${GREEN}[PASS]${NC} $*" | tee -a "$LOG_FILE"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $*" | tee -a "$LOG_FILE"; ((FAIL++)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; ((WARN++)); }
info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }

# -----------------------------------------------------------------------------
# Checks
# -----------------------------------------------------------------------------

check_aws_session() {
    log "🔐 Verificando sessão AWS..."
    if aws sts get-caller-identity --region "$AWS_REGION" > /tmp/aws-id.json 2>&1; then
        local account
        account=$(python3 -c "import json; print(json.load(open('/tmp/aws-id.json'))['Account'])" 2>/dev/null || echo "unknown")
        pass "Sessão AWS ativa | account: $account"
    else
        fail "Sessão AWS expirada — execute: aws sso login --profile k8s-platform-prod"
        exit 1
    fi
}

check_eks_node_groups() {
    log "🖥️  Verificando EKS Node Groups..."

    aws eks list-nodegroups \
        --cluster-name "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --output json > /tmp/ng-list.json 2>&1

    for ng in "${EXPECTED_NODE_GROUPS[@]}"; do
        aws eks describe-nodegroup \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "$ng" \
            --region "$AWS_REGION" \
            --output json > /tmp/ng-"$ng".json 2>&1

        local desired
        desired=$(python3 -c "import json; d=json.load(open('/tmp/ng-$ng.json')); print(d['nodegroup']['scalingConfig']['desiredSize'])" 2>/dev/null || echo "-1")
        local status
        status=$(python3 -c "import json; d=json.load(open('/tmp/ng-$ng.json')); print(d['nodegroup']['status'])" 2>/dev/null || echo "UNKNOWN")

        if [ "$desired" -eq 0 ]; then
            pass "Node group $ng | desiredSize=0 | status=$status"
        else
            fail "Node group $ng | desiredSize=$desired (esperado=0) | status=$status"
        fi
    done
}

check_ec2_instances() {
    log "💻 Verificando EC2 instances do cluster..."

    aws ec2 describe-instances \
        --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
                  "Name=instance-state-name,Values=running,pending,stopping" \
        --region "$AWS_REGION" \
        --output json > /tmp/ec2-instances.json 2>&1

    local running_count
    running_count=$(python3 -c "
import json
data = json.load(open('/tmp/ec2-instances.json'))
instances = [i for r in data['Reservations'] for i in r['Instances']]
print(len(instances))
" 2>/dev/null || echo "-1")

    if [ "$running_count" -eq 0 ]; then
        pass "EC2 instances do cluster: 0 running (shutdown completo)"
    elif [ "$running_count" -gt 0 ]; then
        warn "EC2 instances ainda running: $running_count (aguardar terminação graceful)"
    else
        warn "EC2: não foi possível verificar"
    fi
}

check_rds_status() {
    log "🗄️  Verificando RDS PostgreSQL..."
    local rds_name="${RDS_INSTANCES[$ENVIRONMENT]}"

    aws rds describe-db-instances \
        --db-instance-identifier "$rds_name" \
        --region "$AWS_REGION" \
        --output json > /tmp/rds-status.json 2>&1

    local rds_status
    rds_status=$(python3 -c "import json; print(json.load(open('/tmp/rds-status.json'))['DBInstances'][0]['DBInstanceStatus'])" 2>/dev/null || echo "unknown")

    case "$rds_status" in
        "stopped")
            pass "RDS $rds_name | status=stopped ✅"
            ;;
        "stopping")
            warn "RDS $rds_name | status=stopping (aguardar ~2min)"
            ;;
        "available")
            fail "RDS $rds_name | status=available — RDS NÃO foi parado!"
            ;;
        *)
            warn "RDS $rds_name | status=$rds_status (inesperado)"
            ;;
    esac
}

check_rds_7day_warning() {
    log "⏰ Verificando RDS 7-day auto-restart risk..."
    local rds_name="${RDS_INSTANCES[$ENVIRONMENT]}"

    local stop_time
    stop_time=$(python3 -c "
import json, datetime
data = json.load(open('/tmp/rds-status.json'))
inst = data['DBInstances'][0]
# InstanceCreateTime como proxy se não houver campo de stop
create = inst.get('InstanceCreateTime', '')
print(create[:10] if create else 'unknown')
" 2>/dev/null || echo "unknown")

    warn "RDS auto-restart: AWS reinicia instâncias paradas após 7 dias"
    info "  → Próximo restart automático: verificar no Console AWS (RDS → Events)"
    info "  → Mitigação: shutdown-marco2.sh --snapshot garante snapshot antes de parar"
    info "  → Se férias >7d: use 'aws rds stop-db-instance' novamente no dia 6"
}

check_alb_status() {
    log "⚖️  Verificando ALBs ativos..."

    aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --output json > /tmp/albs.json 2>&1

    local alb_count
    alb_count=$(python3 -c "
import json
data = json.load(open('/tmp/albs.json'))
lbs = [lb for lb in data['LoadBalancers'] if lb['State']['Code'] == 'active']
print(len(lbs))
" 2>/dev/null || echo "?")

    info "ALBs ativos: $alb_count (ALBs não são parados no shutdown — custo fixo ~\$0.33/dia)"
}

check_ebs_volumes() {
    log "💾 Verificando volumes EBS orphaned..."

    aws ec2 describe-volumes \
        --filters "Name=status,Values=available" \
        --region "$AWS_REGION" \
        --output json > /tmp/ebs-available.json 2>&1

    local orphan_count
    orphan_count=$(python3 -c "
import json
data = json.load(open('/tmp/ebs-available.json'))
print(len(data['Volumes']))
" 2>/dev/null || echo "?")

    if [ "$orphan_count" -eq 0 ] 2>/dev/null; then
        pass "EBS volumes orphaned: 0 ✅"
    else
        warn "EBS volumes disponíveis (potencialmente orphaned): $orphan_count"
        info "  → Verificar: são PVCs legítimos ou volumes orphaned?"
    fi
}

print_cost_summary() {
    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "💰 ECONOMIA ESTIMADA (shutdown ativo)"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""
    log "  EC2 Nodes (7x):   \$0.2914/h × 24h = \$6.99/dia"
    log "  Data Transfer:    \$0.75/dia"
    log "  ALB LCU:          \$0.33/dia (fixo, não economizado)"
    log ""
    log "  TOTAL/DIA:        ~\$7.74 | R\$ 46,44"
    log "  MENSAL (22d):     ~\$170 | R\$ 1.020"
    log ""
    log "  Instância RDS:    \$0 (stopped = sem cobrança de compute)"
    log "  Storage RDS:      Cobrado mesmo stopped (~\$1.15/mês para 20GB)"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_summary() {
    log ""
    log "=================================================="
    log "  VALIDATE SHUTDOWN SUMMARY - $ENVIRONMENT"
    log "=================================================="
    log ""
    log "  PASS: $PASS"
    log "  WARN: $WARN"
    log "  FAIL: $FAIL"
    log ""

    if [ "$FAIL" -gt 0 ]; then
        echo -e "${RED}❌ Shutdown INCOMPLETO — $FAIL checks falharam${NC}" | tee -a "$LOG_FILE"
        log "   Ação: Verifique os itens FAIL acima e execute shutdown manualmente"
    elif [ "$WARN" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Shutdown OK com $WARN avisos (pode estar em progresso)${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${GREEN}✅ Shutdown COMPLETO — todos os recursos parados${NC}" | tee -a "$LOG_FILE"
    fi

    log ""
    log "Log: $LOG_FILE"
    log "=================================================="
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    log "=================================================="
    log "  Validate Shutdown - Marco 2"
    log "  Environment: $ENVIRONMENT"
    log "  $(date)"
    log "=================================================="
    log ""

    check_aws_session
    echo ""
    check_eks_node_groups
    echo ""
    check_ec2_instances
    echo ""
    check_rds_status
    check_rds_7day_warning
    echo ""
    check_alb_status
    echo ""
    check_ebs_volumes

    print_cost_summary
    print_summary

    # Exit code baseado nos FAILs
    [ "$FAIL" -eq 0 ]
}

main "$@"
