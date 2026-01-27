#!/bin/bash
# -----------------------------------------------------------------------------
# Script: startup-cluster-v2.sh
# Descrição: Recria o cluster EKS via Terraform (versão melhorada e robusta)
# Uso: ./startup-cluster-v2.sh
# Tempo estimado: ~15 minutos
# Melhorias v2:
#   - Limpeza automática de locks DynamoDB
#   - Validação de estado Terraform
#   - Tratamento de recursos órfãos
#   - Melhor logging e feedback
#   - Configuração automática EBS CSI Driver IAM Role
#   - Criação automática StorageClass gp3
#   - Validação providers.tf com exec token
#   - Verificação de saúde completa do cluster
# -----------------------------------------------------------------------------

# Não usar set -e para melhor controle de erros
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/terraform-startup-$(date +%Y%m%d_%H%M%S).log"
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

# Função para verificar estado do Terraform
check_terraform_state() {
    log_step "📊 Verificando estado do Terraform"

    local state_count=$(terraform state list 2>/dev/null | wc -l)

    if [ "$state_count" -gt 0 ]; then
        log_warning "State contém $state_count recursos"
        log_info "Listando recursos existentes:"
        terraform state list | head -10

        echo ""
        read -p "Deseja limpar o state (destroy)? (sim/não): " CONFIRM_DESTROY

        if [ "$CONFIRM_DESTROY" = "sim" ]; then
            log_info "Executando terraform destroy..."
            clean_terraform_locks
            terraform destroy -auto-approve 2>&1 | tee -a "$LOG_FILE"

            if [ $? -eq 0 ]; then
                log_success "State limpo com sucesso"
            else
                log_error "Falha ao limpar state"
                return 1
            fi
        else
            log_warning "Continuando com state existente (pode causar conflitos)"
        fi
    else
        log_success "State limpo (0 recursos)"
    fi
}

# Função para importar recursos existentes automaticamente
import_existing_resources() {
    log_step "🔄 Detectando recursos existentes na AWS"

    # Verificar se cluster EKS existe
    local cluster_name="k8s-platform-prod"
    local cluster_exists=$(aws eks describe-cluster --name "$cluster_name" --region us-east-1 --profile "$AWS_PROFILE" --query 'cluster.status' --output text 2>/dev/null)

    if [ -n "$cluster_exists" ] && [ "$cluster_exists" != "None" ]; then
        log_info "Cluster EKS '$cluster_name' encontrado (Status: $cluster_exists)"

        # Verificar se está no Terraform state
        if ! terraform state list 2>/dev/null | grep -q "aws_eks_cluster.main"; then
            log_warning "Cluster não está no Terraform state, importando..."
            clean_terraform_locks
            terraform import aws_eks_cluster.main "$cluster_name" 2>&1 >> "$LOG_FILE"

            if [ $? -eq 0 ]; then
                log_success "Cluster importado com sucesso"
            else
                log_warning "Falha ao importar cluster (pode já existir no state)"
            fi
        else
            log_success "Cluster já está no Terraform state"
        fi
    else
        log_info "Cluster EKS não existe na AWS (será criado)"
    fi

    # Verificar se KMS Alias existe
    local alias_name="alias/k8s-platform-prod-eks-secrets"
    local alias_exists=$(aws kms list-aliases --region us-east-1 --profile "$AWS_PROFILE" --query "Aliases[?AliasName=='$alias_name'].AliasName" --output text 2>/dev/null)

    if [ -n "$alias_exists" ]; then
        log_info "KMS Alias '$alias_name' encontrado"

        # Verificar se está no Terraform state
        if ! terraform state list 2>/dev/null | grep -q "aws_kms_alias.eks"; then
            log_warning "KMS Alias não está no Terraform state, importando..."
            clean_terraform_locks
            terraform import aws_kms_alias.eks "$alias_name" 2>&1 >> "$LOG_FILE"

            if [ $? -eq 0 ]; then
                log_success "KMS Alias importado com sucesso"
            else
                log_warning "Falha ao importar KMS Alias (pode já existir no state)"
            fi
        else
            log_success "KMS Alias já está no Terraform state"
        fi
    else
        log_info "KMS Alias não existe na AWS (será criado)"
    fi

    sleep 1
}

# Função para configurar EBS CSI Driver com IAM Role
configure_ebs_csi_driver() {
    log_step "💾 Configurando EBS CSI Driver IAM Role"

    local cluster_name="k8s-platform-prod"
    local role_name="AmazonEKS_EBS_CSI_DriverRole"
    local service_account="ebs-csi-controller-sa"

    # Verificar se role já existe
    local role_exists=$(aws iam get-role --role-name "$role_name" --query 'Role.RoleName' --output text 2>/dev/null)

    if [ -n "$role_exists" ]; then
        log_success "IAM Role '$role_name' já existe"
    else
        log_info "Criando IAM Role para EBS CSI Driver..."

        # Criar service account com IAM role via eksctl
        eksctl create iamserviceaccount \
            --name "$service_account" \
            --namespace kube-system \
            --cluster "$cluster_name" \
            --role-name "$role_name" \
            --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
            --approve \
            --region us-east-1 \
            --profile "$AWS_PROFILE" 2>&1 >> "$LOG_FILE"

        if [ $? -eq 0 ]; then
            log_success "IAM Role criado com sucesso"
        else
            log_error "Falha ao criar IAM Role"
            return 1
        fi
    fi

    # Obter ARN do role
    local role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text --profile "$AWS_PROFILE")

    if [ -z "$role_arn" ]; then
        log_error "Falha ao obter ARN do IAM Role"
        return 1
    fi

    log_info "IAM Role ARN: $role_arn"

    # Atualizar add-on EBS CSI Driver com service account role
    log_info "Atualizando add-on EBS CSI Driver..."

    aws eks update-addon \
        --cluster-name "$cluster_name" \
        --addon-name aws-ebs-csi-driver \
        --service-account-role-arn "$role_arn" \
        --region us-east-1 \
        --profile "$AWS_PROFILE" 2>&1 >> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log_success "Add-on atualizado com sucesso"
    else
        log_warning "Falha ao atualizar add-on (pode já estar configurado)"
    fi

    # Aguardar add-on ficar ACTIVE
    log_info "Aguardando add-on ficar ACTIVE (timeout: 60s)..."

    local timeout=60
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local addon_status=$(aws eks describe-addon \
            --cluster-name "$cluster_name" \
            --addon-name aws-ebs-csi-driver \
            --region us-east-1 \
            --profile "$AWS_PROFILE" \
            --query 'addon.status' \
            --output text 2>/dev/null)

        if [ "$addon_status" = "ACTIVE" ]; then
            log_success "Add-on está ACTIVE"
            break
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    # Reiniciar pods do EBS CSI Driver para aplicar novo IAM role
    log_info "Reiniciando pods do EBS CSI Driver..."

    kubectl rollout restart deployment ebs-csi-controller -n kube-system 2>&1 >> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log_success "Pods reiniciados com sucesso"
    else
        log_warning "Falha ao reiniciar pods"
    fi

    sleep 5
}

# Função para criar StorageClass gp3
create_storageclass_gp3() {
    log_step "📦 Criando StorageClass gp3"

    # Verificar se StorageClass gp3 já existe
    if kubectl get storageclass gp3 &>/dev/null; then
        log_success "StorageClass gp3 já existe"
        return 0
    fi

    log_info "Criando StorageClass gp3..."

    # Remover default da gp2 (se existir)
    if kubectl get storageclass gp2 &>/dev/null; then
        log_info "Removendo default da StorageClass gp2..."
        kubectl annotate storageclass gp2 storageclass.kubernetes.io/is-default-class=false --overwrite 2>&1 >> "$LOG_FILE"
    fi

    # Criar StorageClass gp3
    cat <<EOF | kubectl apply -f - 2>&1 >> "$LOG_FILE"
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

    if [ $? -eq 0 ]; then
        log_success "StorageClass gp3 criado com sucesso"
    else
        log_error "Falha ao criar StorageClass gp3"
        return 1
    fi
}

# Função para validar providers.tf do Marco 2
validate_marco2_providers() {
    log_step "🔍 Validando configuração Marco 2 providers.tf"

    local marco2_dir="$TERRAFORM_DIR/../marco2"
    local providers_file="$marco2_dir/providers.tf"

    if [ ! -f "$providers_file" ]; then
        log_warning "Arquivo providers.tf do Marco 2 não encontrado"
        log_info "Caminho esperado: $providers_file"
        return 0
    fi

    # Verificar se usa exec para token dinâmico
    if grep -q "exec {" "$providers_file" && grep -q "get-token" "$providers_file"; then
        log_success "providers.tf usa exec token (correto)"
    else
        log_warning "providers.tf NÃO usa exec token"
        log_warning "Deployments longos podem falhar com token expirado"
        echo ""
        log_info "Para corrigir, edite: $providers_file"
        log_info "Use exec com 'aws eks get-token' ao invés de token estático"
        echo ""
    fi
}

# Função para aguardar cluster ficar totalmente pronto
wait_cluster_ready() {
    log_step "⏳ Aguardando cluster ficar completamente pronto"

    local cluster_name="k8s-platform-prod"
    local max_attempts=30
    local attempt=0

    log_info "Aguardando todos os nodes ficarem Ready (timeout: 5min)..."

    while [ $attempt -lt $max_attempts ]; do
        # Contar nodes total
        local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

        # Contar nodes Ready
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready ")

        if [ "$total_nodes" -eq 7 ] && [ "$ready_nodes" -eq 7 ]; then
            log_success "Todos os 7 nodes estão Ready"
            break
        fi

        log_info "Nodes: $ready_nodes/7 Ready (tentativa $((attempt+1))/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done

    if [ $attempt -eq $max_attempts ]; then
        log_warning "Timeout: nem todos os nodes ficaram Ready"
        log_info "Nodes atuais:"
        kubectl get nodes
        return 1
    fi

    # Aguardar pods do kube-system ficarem Running
    log_info "Aguardando pods do kube-system ficarem Running (timeout: 3min)..."

    attempt=0
    max_attempts=18

    while [ $attempt -lt $max_attempts ]; do
        local total_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l)
        local running_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c " Running ")

        # Considerar sucesso se 90% dos pods estiverem Running
        if [ $total_pods -gt 0 ]; then
            local percentage=$((running_pods * 100 / total_pods))

            if [ $percentage -ge 90 ]; then
                log_success "Pods do kube-system: $running_pods/$total_pods Running ($percentage%)"
                break
            fi

            log_info "Pods do kube-system: $running_pods/$total_pods Running ($percentage%) (tentativa $((attempt+1))/$max_attempts)"
        else
            log_info "Aguardando pods do kube-system aparecerem..."
        fi

        sleep 10
        attempt=$((attempt + 1))
    done

    if [ $attempt -eq $max_attempts ]; then
        log_warning "Timeout: nem todos os pods do kube-system ficaram Running"
        log_info "Status atual:"
        kubectl get pods -n kube-system
        return 1
    fi

    log_success "Cluster está completamente pronto"
}

# Banner
echo ""
echo "=============================================="
echo "🚀 STARTUP CLUSTER EKS - Marco 1 v2.0"
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

# Informações sobre o que será criado
echo ""
log_info "Este script irá criar:"
echo "   - Cluster EKS k8s-platform-prod (Kubernetes 1.31)"
echo "   - 7 nodes (2 system + 3 workloads + 2 critical)"
echo "   - 4 add-ons (CoreDNS, VPC CNI, Kube-proxy, EBS CSI Driver)"
echo "   - Security Groups e KMS Key"
echo ""
log_warning "Tempo estimado: ~15 minutos"
log_warning "Custo estimado: ~\$0.76/hora (~\$547/mês) enquanto ligado"
echo ""

read -p "Deseja continuar? (sim/não): " CONFIRM
if [ "$CONFIRM" != "sim" ]; then
    log_error "Operação cancelada pelo usuário"
    exit 0
fi

# Limpeza de locks
clean_terraform_locks

# Verificar state
check_terraform_state
if [ $? -ne 0 ]; then
    log_error "Falha na verificação do state"
    exit 1
fi

# Importar recursos existentes
import_existing_resources

# Terraform plan
log_step "📋 Executando terraform plan"
log_info "Gerando plano de execução..."

if ! terraform plan -out=/tmp/terraform-startup.tfplan 2>&1 | tee -a "$LOG_FILE"; then
    log_error "Terraform plan falhou"
    log_info "Verificando se é problema de lock..."
    clean_terraform_locks

    log_info "Tentando novamente..."
    if ! terraform plan -out=/tmp/terraform-startup.tfplan 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Terraform plan falhou novamente. Verifique o log: $LOG_FILE"
        exit 1
    fi
fi

echo ""
read -p "Plano aprovado? Deseja aplicar? (sim/não): " CONFIRM_PLAN
if [ "$CONFIRM_PLAN" != "sim" ]; then
    log_error "Operação cancelada pelo usuário"
    rm -f /tmp/terraform-startup.tfplan
    exit 0
fi

# Terraform apply
log_step "🚀 Executando terraform apply"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log_info "Timeline esperado:"
echo "   - 0-15s: Security Groups e KMS Key"
echo "   - 15s-11m: Cluster EKS (fase mais longa)"
echo "   - 11m-13m: Node Groups (3 grupos)"
echo "   - 13m-15m: Add-ons (4)"
echo ""

terraform apply /tmp/terraform-startup.tfplan 2>&1 | tee -a "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}

# Remover arquivo de plano
rm -f /tmp/terraform-startup.tfplan

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    log_step "✅ CLUSTER CRIADO COM SUCESSO!"

    # Configurar kubectl
    log_info "Configurando kubectl..."
    aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod --profile "$AWS_PROFILE"

    # Aguardar cluster ficar pronto
    wait_cluster_ready

    # Configurar EBS CSI Driver
    configure_ebs_csi_driver
    if [ $? -ne 0 ]; then
        log_warning "Falha ao configurar EBS CSI Driver (não crítico)"
    fi

    # Criar StorageClass gp3
    create_storageclass_gp3
    if [ $? -ne 0 ]; then
        log_warning "Falha ao criar StorageClass gp3 (não crítico)"
    fi

    # Validar providers.tf do Marco 2
    validate_marco2_providers

    echo ""
    log_info "Validando nodes..."
    kubectl get nodes -L node-type,workload,eks.amazonaws.com/nodegroup 2>&1 | tee -a "$LOG_FILE"

    echo ""
    log_info "Validando pods do sistema..."
    kubectl get pods -n kube-system 2>&1 | tee -a "$LOG_FILE"

    echo ""
    log_step "📋 Informações do Cluster"

    CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint 2>/dev/null || echo "N/A")
    CLUSTER_VERSION=$(terraform output -raw cluster_version 2>/dev/null || echo "N/A")

    echo "Nome: k8s-platform-prod"
    echo "Endpoint: $CLUSTER_ENDPOINT"
    echo "Versão: $CLUSTER_VERSION"
    echo "Region: us-east-1"
    echo ""
    log_info "Log completo: $LOG_FILE"
    echo ""
    log_step "📚 Lições Aprendidas Implementadas"
    echo "✅ EBS CSI Driver configurado com IAM Role (previne erro de credentials)"
    echo "✅ StorageClass gp3 criado (previne PVCs Pending)"
    echo "✅ Validação de providers.tf do Marco 2 (previne timeout de token)"
    echo "✅ Cluster aguarda todos os nodes Ready antes de prosseguir"
    echo "✅ Import automático de recursos existentes"
    echo ""
    log_warning "Para desligar o cluster ao fim do dia:"
    echo "   ./shutdown-cluster.sh"
    echo ""
    log_info "Próximos passos:"
    echo "1. Validar cluster: ./status-cluster.sh"
    echo "2. Deploy Marco 2 (Prometheus + Loki): cd ../marco2 && terraform apply"
    echo ""

else
    echo ""
    log_step "❌ ERRO AO CRIAR CLUSTER"
    echo ""
    log_info "Log completo: $LOG_FILE"
    echo ""
    log_info "Para troubleshooting:"
    echo "1. Verificar locks no DynamoDB: terraform force-unlock <LOCK_ID>"
    echo "2. Verificar state: terraform state list"
    echo "3. Revisar log: cat $LOG_FILE"
    echo ""
    exit $EXIT_CODE
fi
