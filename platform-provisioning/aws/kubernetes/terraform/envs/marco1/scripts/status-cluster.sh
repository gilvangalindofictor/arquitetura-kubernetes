#!/bin/bash
# -----------------------------------------------------------------------------
# Script: status-cluster.sh
# Descrição: Verifica o status do cluster EKS e calcula custos
# Uso: ./status-cluster.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "📊 STATUS CLUSTER EKS - Marco 1"
echo "=============================================="
echo ""

# Verificar AWS Profile
if [ -z "$AWS_PROFILE" ]; then
    export AWS_PROFILE=k8s-platform-prod
fi

# Verificar credenciais AWS
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
    echo "❌ ERRO: Credenciais AWS inválidas ou expiradas"
    echo "   Execute: aws sso login --profile $AWS_PROFILE"
    exit 1
fi

echo "🔐 AWS Account: $(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
echo "👤 User: $(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Arn --output text | cut -d'/' -f2)"
echo ""

# Verificar se cluster existe
echo "🔍 Verificando cluster EKS..."
CLUSTER_STATUS=$(aws eks describe-cluster --name k8s-platform-prod --region us-east-1 --profile "$AWS_PROFILE" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" == "NOT_FOUND" ]; then
    echo ""
    echo "=============================================="
    echo "🛑 CLUSTER DESLIGADO"
    echo "=============================================="
    echo ""
    echo "Status: Cluster não existe (destruído)"
    echo "💰 Custo atual: $0.00/hora"
    echo ""
    echo "🚀 Para ligar o cluster:"
    echo "   cd $SCRIPT_DIR"
    echo "   ./startup-cluster.sh"
    echo ""
    exit 0
fi

echo "✅ Cluster encontrado: k8s-platform-prod"
echo "Status: $CLUSTER_STATUS"
echo ""

# Pegar informações do cluster
CLUSTER_VERSION=$(aws eks describe-cluster --name k8s-platform-prod --region us-east-1 --profile "$AWS_PROFILE" --query 'cluster.version' --output text 2>/dev/null)
CLUSTER_ENDPOINT=$(aws eks describe-cluster --name k8s-platform-prod --region us-east-1 --profile "$AWS_PROFILE" --query 'cluster.endpoint' --output text 2>/dev/null)
CLUSTER_ARN=$(aws eks describe-cluster --name k8s-platform-prod --region us-east-1 --profile "$AWS_PROFILE" --query 'cluster.arn' --output text 2>/dev/null)

echo "📋 Informações do Cluster:"
echo "   Versão: $CLUSTER_VERSION"
echo "   Endpoint: $CLUSTER_ENDPOINT"
echo ""

# Listar node groups
echo "📊 Node Groups:"
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

    echo "   - $NG:"
    echo "     Instance: $INSTANCE_TYPE"
    echo "     Nodes: $DESIRED (min: $MIN, max: $MAX)"
    echo "     Status: $STATUS"

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

echo ""
echo "📊 Total de Nodes: $TOTAL_NODES"
echo ""

# Calcular custos
EKS_COST=0.10  # $0.10/hora para cluster EKS
TOTAL_COST=$(echo "$EKS_COST + $COST_PER_HOUR" | bc)
DAILY_COST=$(echo "$TOTAL_COST * 24" | bc)
MONTHLY_COST=$(echo "$TOTAL_COST * 730" | bc)  # 730 horas/mês em média

echo "=============================================="
echo "💰 CUSTOS ESTIMADOS"
echo "=============================================="
echo ""
echo "Cluster EKS:        \$$EKS_COST/hora"
echo "Nodes EC2:          \$$COST_PER_HOUR/hora"
echo "NAT Gateways (2):   \$0.09/hora"
echo ""
echo "Total por hora:     \$$(echo "$TOTAL_COST + 0.09" | bc)/hora"
echo "Total por dia:      \$$(echo "$DAILY_COST + 2.16" | bc)/dia"
echo "Total por mês:      \$$(echo "$MONTHLY_COST + 65.70" | bc)/mês"
echo ""
echo "⚠️  Nota: NAT Gateways permanecem mesmo com cluster desligado"
echo "   Para economia total, seria necessário destruir VPC também"
echo ""

# Verificar kubectl
if command -v kubectl &> /dev/null; then
    echo "=============================================="
    echo "🔧 VALIDAÇÃO KUBECTL"
    echo "=============================================="
    echo ""

    if kubectl cluster-info &> /dev/null; then
        echo "✅ kubectl configurado e conectado"
        echo ""
        echo "📊 Nodes:"
        kubectl get nodes -L node-type,workload 2>/dev/null || echo "   Erro ao listar nodes"
        echo ""
        echo "📊 Pods do sistema:"
        kubectl get pods -n kube-system --field-selector=status.phase=Running 2>/dev/null | wc -l | xargs echo "   Pods Running:"
    else
        echo "⚠️  kubectl não conectado ao cluster"
        echo ""
        echo "Para configurar kubectl:"
        echo "   aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod --profile $AWS_PROFILE"
    fi
else
    echo "⚠️  kubectl não instalado"
fi

echo ""
echo "=============================================="
echo "🛑 GERENCIAMENTO DE CUSTOS"
echo "=============================================="
echo ""
echo "Para desligar o cluster e economizar custos:"
echo "   cd $SCRIPT_DIR"
echo "   ./shutdown-cluster.sh"
echo ""
echo "Economia com shutdown: ~\$$(echo "$TOTAL_COST * 24" | bc)/dia"
echo ""
