#!/bin/bash
# -----------------------------------------------------------------------------
# Script: shutdown-cluster.sh
# Descrição: Desliga completamente o cluster EKS para economia de custos (v2.0)
# Uso: ./shutdown-cluster.sh [--keep-cluster|--destroy-all]
# Opções:
#   --keep-cluster: Destrói apenas node groups (economia parcial ~70%)
#   --destroy-all: Destrói tudo incluindo cluster (economia 100%)
# Melhorias v2:
#   - Limpeza automática de locks DynamoDB
#   - Verificação de credenciais AWS
#   - Retry logic em caso de falha
#   - Opção de economia parcial (keep cluster, destroy nodes)
#   - Melhor logging e feedback
# -----------------------------------------------------------------------------

# Não usar set -e para melhor controle de erros
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/terraform-shutdown-$(date +%Y%m%d_%H%M%S).log"
DYNAMODB_TABLE="terraform-state-lock"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções de logging
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Função para limpar locks do DynamoDB
clean_terraform_locks() {
    log_step "🔓 Limpando locks do Terraform"

    local locks=$(aws dynamodb scan \
        --table-name "$DYNAMODB_TABLE" \
        --region us-east-1 \
        --profile "$AWS_PROFILE" \
        --output json 2>/dev/null | jq -r '.Items[] | .LockID.S' 2>/dev/null)

    if [ -z "$locks" ]; then
        log_success "Nenhum lock encontrado"
        return 0
    fi

    echo "$locks" | while read -r lock; do
        if [ -n "$lock" ]; then
            log_info "Removendo lock: $lock"
            aws dynamodb delete-item \
                --table-name "$DYNAMODB_TABLE" \
                --key "{\"LockID\":{\"S\":\"$lock\"}}" \
                --region us-east-1 \
                --profile "$AWS_PROFILE" 2>&1 >> "$LOG_FILE"

            if [ $? -eq 0 ]; then
                log_success "Lock removido: $lock"
            else
                log_warning "Falha ao remover lock: $lock"
            fi
        fi
    done

    sleep 2
}

# Função para remover IAM role do EBS CSI Driver
cleanup_ebs_csi_iam_role() {
    log_step "🧹 Limpando IAM Role do EBS CSI Driver"

    local role_name="AmazonEKS_EBS_CSI_DriverRole"
    local cluster_name="k8s-platform-prod"

    # Verificar se role existe
    local role_exists=$(aws iam get-role --role-name "$role_name" --query 'Role.RoleName' --output text 2>/dev/null)

    if [ -z "$role_exists" ]; then
        log_info "IAM Role não existe (já foi removido ou nunca foi criado)"
        return 0
    fi

    log_info "IAM Role '$role_name' encontrado, removendo..."

    # Remover service account via eksctl (remove role e policy attachments automaticamente)
    eksctl delete iamserviceaccount \
        --name ebs-csi-controller-sa \
        --namespace kube-system \
        --cluster "$cluster_name" \
        --region us-east-1 \
        --profile "$AWS_PROFILE" 2>&1 >> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log_success "IAM Role removido com sucesso"
    else
        log_warning "Falha ao remover IAM Role (pode não existir ou cluster já foi destruído)"
    fi
}

# Função para destruir apenas node groups (economia parcial)
destroy_node_groups_only() {
    log_step "🔄 Destruindo apenas Node Groups (economia parcial)"

    log_warning "Esta opção destrói apenas os node groups, mantendo:"
    echo "   - Cluster EKS (Control Plane) - ~$0.10/hora"
    echo "   - Add-ons EKS"
    echo "   - Security Groups e KMS Key"
    echo ""
    log_info "Economia: ~70% (de $0.76/hora para $0.10/hora)"
    echo ""

    read -p "Confirmar destruição parcial? (sim/não): " CONFIRM_PARTIAL
    if [ "$CONFIRM_PARTIAL" != "sim" ]; then
        log_error "Operação cancelada"
        exit 0
    fi

    # Usar terraform destroy com targets específicos
    log_info "Destruindo node groups..."

    terraform destroy \
        -target=aws_eks_node_group.system \
        -target=aws_eks_node_group.workloads \
        -target=aws_eks_node_group.critical \
        -auto-approve 2>&1 | tee -a "$LOG_FILE"

    local exit_code=${PIPESTATUS[0]}

    if [ $exit_code -eq 0 ]; then
        log_success "Node groups destruídos com sucesso"
        return 0
    else
        log_error "Falha ao destruir node groups"
        return 1
    fi
}

# Banner
echo ""
echo "=============================================="
echo "🛑 SHUTDOWN CLUSTER EKS - Marco 1 v2.0"
echo "=============================================="
echo ""
log_info "Diretório Terraform: $TERRAFORM_DIR"
log_info "Log file: $LOG_FILE"
echo ""

# Validações iniciais
if [ ! -f "$TERRAFORM_DIR/main.tf" ]; then
    log_error "main.tf não encontrado em $TERRAFORM_DIR"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Verificar AWS Profile
if [ -z "$AWS_PROFILE" ]; then
    log_warning "AWS_PROFILE não definido, usando: k8s-platform-prod"
    export AWS_PROFILE=k8s-platform-prod
fi

# Verificar credenciais AWS
log_step "🔐 Validando credenciais AWS"
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
    log_error "Credenciais AWS inválidas ou expiradas"
    echo "   Execute: aws sso login --profile $AWS_PROFILE"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
USER=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Arn --output text | cut -d'/' -f2)
log_success "Autenticado como: $USER (Account: $ACCOUNT_ID)"

# Verificar mode de operação
DESTROY_MODE="all"

if [ "$1" = "--keep-cluster" ]; then
    DESTROY_MODE="nodes-only"
elif [ "$1" = "--destroy-all" ]; then
    DESTROY_MODE="all"
fi

# Informações sobre o que será destruído
echo ""

if [ "$DESTROY_MODE" = "all" ]; then
    log_warning "Modo: DESTRUIÇÃO COMPLETA"
    echo ""
    log_info "Este script irá destruir:"
    echo "   - Cluster EKS k8s-platform-prod (Control Plane)"
    echo "   - 7 nodes EC2 (2 system + 3 workloads + 2 critical)"
    echo "   - 4 add-ons (CoreDNS, VPC CNI, Kube-proxy, EBS CSI Driver)"
    echo "   - Security Groups e KMS Key"
    echo ""
    log_info "Recursos que NÃO serão destruídos:"
    echo "   - VPC e suas subnets"
    echo "   - NAT Gateways e Internet Gateway"
    echo "   - IAM Roles"
    echo ""
    log_success "Economia: ~$0.76/hora (~$547/mês)"
else
    log_warning "Modo: DESTRUIÇÃO PARCIAL (apenas node groups)"
    echo ""
    log_info "Este script irá destruir:"
    echo "   - 7 nodes EC2 (2 system + 3 workloads + 2 critical)"
    echo ""
    log_info "Recursos que serão MANTIDOS:"
    echo "   - Cluster EKS (Control Plane) - ~$0.10/hora"
    echo "   - Add-ons EKS"
    echo "   - Security Groups e KMS Key"
    echo ""
    log_success "Economia: ~$0.53/hora (~$381/mês) - 70% de economia"
    echo ""
    log_info "Para destruição completa, use: ./shutdown-cluster.sh --destroy-all"
fi

echo ""

read -p "Deseja continuar? (sim/não): " CONFIRM
if [ "$CONFIRM" != "sim" ]; then
    log_error "Operação cancelada pelo usuário"
    exit 0
fi

# Criar backup do state antes da destruição
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$HOME/.terraform-backups/marco1"
mkdir -p "$BACKUP_DIR"

log_step "💾 Criando backup do state"
terraform state pull > "$BACKUP_DIR/terraform.tfstate.backup.$TIMESTAMP" 2>/dev/null || true

if [ -f "$BACKUP_DIR/terraform.tfstate.backup.$TIMESTAMP" ]; then
    log_success "Backup criado: $BACKUP_DIR/terraform.tfstate.backup.$TIMESTAMP"
else
    log_warning "Falha ao criar backup do state (não crítico)"
fi

# Limpar IAM role do EBS CSI Driver
cleanup_ebs_csi_iam_role

# Limpar locks
clean_terraform_locks

# Executar destruição
if [ "$DESTROY_MODE" = "nodes-only" ]; then
    destroy_node_groups_only
    EXIT_CODE=$?
else
    log_step "🗑️  Executando terraform destroy (completo)"

    terraform destroy -auto-approve 2>&1 | tee -a "$LOG_FILE"
    EXIT_CODE=${PIPESTATUS[0]}

    # Retry em caso de lock
    if [ $EXIT_CODE -ne 0 ]; then
        log_warning "Destroy falhou, tentando limpar locks e tentar novamente..."
        clean_terraform_locks
        sleep 3

        log_info "Tentativa 2/2..."
        terraform destroy -auto-approve 2>&1 | tee -a "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[0]}
    fi
fi

# Resultado final
if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    log_step "✅ CLUSTER DESLIGADO COM SUCESSO!"

    if [ "$DESTROY_MODE" = "all" ]; then
        echo "📊 Recursos destruídos:"
        echo "   - Cluster EKS k8s-platform-prod"
        echo "   - 7 nodes EC2"
        echo "   - 4 add-ons EKS"
        echo "   - Security Groups e KMS Key"
        echo ""
        log_success "Economia: ~$0.76/hora (~$547/mês)"
    else
        echo "📊 Recursos destruídos:"
        echo "   - 7 nodes EC2"
        echo ""
        log_success "Economia: ~$0.53/hora (~$381/mês) - 70%"
        log_info "Cluster EKS mantido (custo: ~$0.10/hora)"
    fi

    echo ""
    echo "💾 Backup do state: $BACKUP_DIR/terraform.tfstate.backup.$TIMESTAMP"
    echo "📋 Log da operação: $LOG_FILE"
    echo ""
    log_info "Para religar o cluster, execute:"
    echo "   ./startup-cluster-v2.sh"
    echo ""

else
    echo ""
    log_step "❌ ERRO AO DESLIGAR CLUSTER"
    echo ""
    echo "📋 Log completo: $LOG_FILE"
    echo "💾 Backup do state: $BACKUP_DIR/terraform.tfstate.backup.$TIMESTAMP"
    echo ""
    log_info "Para troubleshooting:"
    echo "1. Limpar locks manualmente: ./startup-cluster-v2.sh (função clean_terraform_locks)"
    echo "2. Verificar state: terraform state list"
    echo "3. Tentar novamente: ./shutdown-cluster.sh"
    echo ""
    exit $EXIT_CODE
fi
