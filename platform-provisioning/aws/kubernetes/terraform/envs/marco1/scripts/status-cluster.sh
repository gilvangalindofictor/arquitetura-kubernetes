#!/bin/bash
# -----------------------------------------------------------------------------
# Script: status-cluster.sh
# Descrição: Verifica status do cluster EKS, custos e readiness para próximas ações (v2.0)
# Uso: ./status-cluster.sh [--detailed]
# Opções:
#   --detailed: Mostra análise detalhada incluindo Marco 2 e próximas ações
# Melhorias v2:
#   - Validação completa de infraestrutura (Marco 1 + Marco 2)
#   - Recomendações de próximas ações
#   - Validação de pré-requisitos (StorageClass, EBS CSI, etc)
#   - Status de Helm releases
#   - Melhor logging e feedback
# -----------------------------------------------------------------------------

# Não usar set -e para melhor controle de erros
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Banner
echo ""
echo "=============================================="
echo "📊 STATUS CLUSTER EKS - Marco 1 v2.0"
echo "=============================================="
echo ""

# Verificar mode
DETAILED_MODE=false
if [ "$1" = "--detailed" ]; then
    DETAILED_MODE=true
fi

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

# Verificar se cluster existe
log_step "🔍 Verificando Cluster EKS"
CLUSTER_STATUS=$(aws eks describe-cluster --name k8s-platform-prod --region us-east-1 --profile "$AWS_PROFILE" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" == "NOT_FOUND" ]; then
    echo ""
    log_step "🛑 CLUSTER DESLIGADO"
    echo ""
    log_info "Status: Cluster não existe (destruído)"
    log_success "Custo atual: \$0.00/hora"
    echo ""
    log_info "Para ligar o cluster:"
    echo "   cd $SCRIPT_DIR"
    echo "   ./startup-cluster-v2.sh"
    echo ""
    exit 0
fi

log_success "Cluster encontrado: k8s-platform-prod"
log_info "Status: $CLUSTER_STATUS"

# Pegar informações do cluster
CLUSTER_VERSION=$(aws eks describe-cluster --name k8s-platform-prod --region us-east-1 --profile "$AWS_PROFILE" --query 'cluster.version' --output text 2>/dev/null)
CLUSTER_ENDPOINT=$(aws eks describe-cluster --name k8s-platform-prod --region us-east-1 --profile "$AWS_PROFILE" --query 'cluster.endpoint' --output text 2>/dev/null)

echo "   Versão: $CLUSTER_VERSION"
echo "   Endpoint: $CLUSTER_ENDPOINT"

# Listar node groups
log_step "📊 Node Groups"
NODE_GROUPS=$(aws eks list-nodegroups --cluster-name k8s-platform-prod --region us-east-1 --profile "$AWS_PROFILE" --query 'nodegroups' --output text 2>/dev/null)

TOTAL_NODES=0
COST_PER_HOUR=0

for NG in $NODE_GROUPS; do
    NG_INFO=$(aws eks describe-nodegroup --cluster-name k8s-platform-prod --nodegroup-name "$NG" --region us-east-1 --profile "$AWS_PROFILE" 2>/dev/null)

    DESIRED=$(echo "$NG_INFO" | jq -r '.nodegroup.scalingConfig.desiredSize')
    MIN=$(echo "$NG_INFO" | jq -r '.nodegroup.scalingConfig.minSize')
    MAX=$(echo "$NG_INFO" | jq -r '.nodegroup.scalingConfig.maxSize')
    INSTANCE_TYPE=$(echo "$NG_INFO" | jq -r '.nodegroup.instanceTypes[0]')
    STATUS=$(echo "$NG_INFO" | jq -r '.nodegroup.status')

    echo "   $NG:"
    echo "      Instance: $INSTANCE_TYPE | Nodes: $DESIRED (min: $MIN, max: $MAX) | Status: $STATUS"

    TOTAL_NODES=$((TOTAL_NODES + DESIRED))

    # Calcular custo por hora (aproximado)
    case $INSTANCE_TYPE in
        t3.medium)
            NODE_COST=$(echo "$DESIRED * 0.0416" | bc)
            ;;
        t3.large)
            NODE_COST=$(echo "$DESIRED * 0.0832" | bc)
            ;;
        t3.xlarge)
            NODE_COST=$(echo "$DESIRED * 0.1664" | bc)
            ;;
        *)
            NODE_COST=0
            ;;
    esac

    COST_PER_HOUR=$(echo "$COST_PER_HOUR + $NODE_COST" | bc)
done

log_info "Total de Nodes: $TOTAL_NODES"

# Calcular custos
EKS_COST=0.10  # $0.10/hora para cluster EKS
TOTAL_COST=$(echo "$EKS_COST + $COST_PER_HOUR" | bc)
DAILY_COST=$(echo "$TOTAL_COST * 24" | bc)
MONTHLY_COST=$(echo "$TOTAL_COST * 730" | bc)  # 730 horas/mês em média

log_step "💰 Custos Estimados"
echo "Cluster EKS:        \$$EKS_COST/hora"
echo "Nodes EC2:          \$$COST_PER_HOUR/hora"
echo "NAT Gateways (2):   \$0.09/hora"
echo ""
log_info "Total por hora:  \$$(echo "$TOTAL_COST + 0.09" | bc)"
log_info "Total por dia:   \$$(echo "$DAILY_COST + 2.16" | bc)"
log_info "Total por mês:   \$$(echo "$MONTHLY_COST + 65.70" | bc)"
echo ""
log_warning "NAT Gateways permanecem mesmo com cluster desligado"

# Validações kubectl
log_step "🔧 Validação Kubernetes"

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl não instalado"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    log_warning "kubectl não conectado ao cluster"
    echo ""
    log_info "Para configurar kubectl:"
    echo "   aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod --profile $AWS_PROFILE"
    exit 1
fi

log_success "kubectl conectado ao cluster"

# Validar nodes
NODES_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
NODES_TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")

if [ "$NODES_READY" -eq "$NODES_TOTAL" ] && [ "$NODES_READY" -gt 0 ]; then
    log_success "Nodes: $NODES_READY/$NODES_TOTAL Ready"
else
    log_warning "Nodes: $NODES_READY/$NODES_TOTAL Ready"
fi

# Validar pods kube-system
PODS_RUNNING=$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
PODS_TOTAL=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l || echo "0")

if [ "$PODS_RUNNING" -gt 0 ]; then
    log_success "Pods kube-system: $PODS_RUNNING/$PODS_TOTAL Running"
else
    log_warning "Pods kube-system: $PODS_RUNNING/$PODS_TOTAL Running"
fi

# Validações de pré-requisitos Marco 1
log_step "✅ Validação Pré-requisitos Marco 1"

# StorageClass gp3
if kubectl get storageclass gp3 &> /dev/null; then
    log_success "StorageClass gp3 existe"
else
    log_error "StorageClass gp3 NÃO existe"
    log_info "Execute: startup-cluster-v2.sh (cria automaticamente)"
fi

# EBS CSI Driver IAM Role
EBS_CSI_ROLE=$(kubectl get sa ebs-csi-controller-sa -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")

if [ -n "$EBS_CSI_ROLE" ]; then
    log_success "EBS CSI Driver tem IAM Role configurado"
    echo "   Role: $EBS_CSI_ROLE"
else
    log_error "EBS CSI Driver NÃO tem IAM Role"
    log_info "Execute: startup-cluster-v2.sh (configura automaticamente)"
fi

# Validar providers.tf do Marco 2
MARCO2_DIR="$TERRAFORM_DIR/../marco2"
PROVIDERS_FILE="$MARCO2_DIR/providers.tf"

if [ -f "$PROVIDERS_FILE" ]; then
    if grep -q "exec {" "$PROVIDERS_FILE" && grep -q "get-token" "$PROVIDERS_FILE"; then
        log_success "Marco 2 providers.tf usa exec token (correto)"
    else
        log_warning "Marco 2 providers.tf NÃO usa exec token"
        log_info "Deployments longos podem falhar com token expirado"
    fi
else
    log_info "Marco 2 providers.tf não encontrado (Marco 2 não iniciado)"
fi

# Análise detalhada Marco 2
if [ "$DETAILED_MODE" = true ]; then
    log_step "📊 Status Marco 2 (Observability Stack)"

    # Verificar namespace monitoring
    if kubectl get namespace monitoring &> /dev/null; then
        log_success "Namespace monitoring existe"

        # Contar pods
        MONITORING_PODS_RUNNING=$(kubectl get pods -n monitoring --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
        MONITORING_PODS_TOTAL=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l || echo "0")

        if [ "$MONITORING_PODS_RUNNING" -eq "$MONITORING_PODS_TOTAL" ] && [ "$MONITORING_PODS_RUNNING" -gt 0 ]; then
            log_success "Pods monitoring: $MONITORING_PODS_RUNNING/$MONITORING_PODS_TOTAL Running"
        elif [ "$MONITORING_PODS_TOTAL" -gt 0 ]; then
            log_warning "Pods monitoring: $MONITORING_PODS_RUNNING/$MONITORING_PODS_TOTAL Running"
        else
            log_info "Nenhum pod no namespace monitoring"
        fi

        # Verificar Helm releases
        echo ""
        log_info "Helm Releases:"

        # Prometheus Stack
        if helm list -n monitoring 2>/dev/null | grep -q "kube-prometheus-stack"; then
            PROM_STATUS=$(helm list -n monitoring 2>/dev/null | grep "kube-prometheus-stack" | awk '{print $8}')
            log_success "   kube-prometheus-stack: $PROM_STATUS"
        else
            log_warning "   kube-prometheus-stack: NÃO deployado"
        fi

        # Loki
        if helm list -n monitoring 2>/dev/null | grep -q "loki"; then
            LOKI_STATUS=$(helm list -n monitoring 2>/dev/null | grep "loki" | awk '{print $8}')
            log_success "   loki: $LOKI_STATUS"
        else
            log_warning "   loki: NÃO deployado"
        fi

        # Fluent Bit
        if helm list -n monitoring 2>/dev/null | grep -q "fluent-bit"; then
            FB_STATUS=$(helm list -n monitoring 2>/dev/null | grep "fluent-bit" | awk '{print $8}')
            log_success "   fluent-bit: $FB_STATUS"
        else
            log_warning "   fluent-bit: NÃO deployado"
        fi

        # Validar serviços críticos
        echo ""
        log_info "Serviços Críticos:"

        # Prometheus
        if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --field-selector=status.phase=Running &> /dev/null; then
            log_success "   Prometheus: Running"
        else
            log_warning "   Prometheus: NOT Running"
        fi

        # Grafana
        if kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running &> /dev/null; then
            GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            if [ -n "$GRAFANA_POD" ]; then
                log_success "   Grafana: Running (Pod: $GRAFANA_POD)"
            else
                log_warning "   Grafana: Pod not found"
            fi
        else
            log_warning "   Grafana: NOT Running"
        fi

        # Loki
        if kubectl get pods -n monitoring -l app.kubernetes.io/name=loki --field-selector=status.phase=Running &> /dev/null; then
            LOKI_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=loki --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
            log_success "   Loki: Running ($LOKI_PODS pods)"
        else
            log_warning "   Loki: NOT Running"
        fi

        # Fluent Bit
        if kubectl get ds fluent-bit -n monitoring &> /dev/null; then
            FB_DESIRED=$(kubectl get ds fluent-bit -n monitoring -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
            FB_READY=$(kubectl get ds fluent-bit -n monitoring -o jsonpath='{.status.numberReady}' 2>/dev/null)
            if [ "$FB_DESIRED" -eq "$FB_READY" ]; then
                log_success "   Fluent Bit: Running ($FB_READY/$FB_DESIRED DaemonSet)"
            else
                log_warning "   Fluent Bit: $FB_READY/$FB_DESIRED DaemonSet"
            fi
        else
            log_warning "   Fluent Bit: NOT deployed"
        fi

    else
        log_info "Namespace monitoring não existe (Marco 2 não deployado)"
    fi
fi

# Recomendações de próximas ações
log_step "🎯 Próximas Ações Recomendadas"

MARCO1_OK=true
MARCO2_OK=false

# Validar se Marco 1 está completo
if [ "$NODES_READY" -ne "$NODES_TOTAL" ] || [ "$NODES_READY" -eq 0 ]; then
    MARCO1_OK=false
fi

if ! kubectl get storageclass gp3 &> /dev/null; then
    MARCO1_OK=false
fi

if [ -z "$EBS_CSI_ROLE" ]; then
    MARCO1_OK=false
fi

# Validar se Marco 2 está completo
if kubectl get namespace monitoring &> /dev/null; then
    if helm list -n monitoring 2>/dev/null | grep -q "kube-prometheus-stack" && \
       helm list -n monitoring 2>/dev/null | grep -q "loki" && \
       helm list -n monitoring 2>/dev/null | grep -q "fluent-bit"; then
        MARCO2_OK=true
    fi
fi

if [ "$MARCO1_OK" = false ]; then
    log_warning "Marco 1 INCOMPLETO - Execute os passos de correção acima"
    echo ""
    echo "1. Se cluster foi criado manualmente (não via startup-cluster-v2.sh):"
    echo "   cd $SCRIPT_DIR"
    echo "   ./startup-cluster-v2.sh  # Configura StorageClass + EBS CSI"
    echo ""
elif [ "$MARCO2_OK" = false ]; then
    log_success "Marco 1 COMPLETO - Pronto para Marco 2!"
    echo ""
    echo "Próximo passo: Deploy Observability Stack (Prometheus + Loki + Fluent Bit)"
    echo ""
    echo "1. Acessar Marco 2:"
    echo "   cd $MARCO2_DIR"
    echo ""
    echo "2. Deploy completo:"
    echo "   terraform init"
    echo "   terraform plan"
    echo "   terraform apply"
    echo ""
    echo "3. Validar deployment:"
    echo "   kubectl get pods -n monitoring"
    echo "   ./scripts/status-cluster.sh --detailed"
    echo ""
else
    log_success "Marco 1 e Marco 2 COMPLETOS!"
    echo ""
    log_info "Cluster totalmente operacional com observability stack"
    echo ""
    echo "Próximos passos sugeridos:"
    echo ""
    echo "1. Acessar Grafana:"
    echo "   kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    echo "   URL: http://localhost:3000"
    echo "   User: admin"
    echo "   Password: \$(kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
    echo ""
    echo "2. Consultar logs no Loki via Grafana:"
    echo "   - Acessar Grafana > Explore > DataSource: Loki"
    echo "   - Query exemplo: {namespace=\"kube-system\"}"
    echo ""
    echo "3. Iniciar Marco 3 (Data Services):"
    echo "   - PostgreSQL Operator"
    echo "   - Redis Operator"
    echo "   - RabbitMQ Operator"
    echo ""
fi

# Gerenciamento de custos
log_step "🛑 Gerenciamento de Custos"
echo "Para desligar o cluster:"
echo "   cd $SCRIPT_DIR"
echo "   ./shutdown-cluster.sh                # Destruição completa (economia: \$$(echo "$TOTAL_COST * 24" | bc)/dia)"
echo "   ./shutdown-cluster.sh --keep-cluster # Apenas nodes (economia: ~70%)"
echo ""

if [ "$DETAILED_MODE" = false ]; then
    log_info "Para análise detalhada incluindo Marco 2:"
    echo "   ./status-cluster.sh --detailed"
    echo ""
fi
