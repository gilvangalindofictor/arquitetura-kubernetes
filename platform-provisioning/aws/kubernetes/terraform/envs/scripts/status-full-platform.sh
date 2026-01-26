#!/bin/bash
# -----------------------------------------------------------------------------
# Script: status-full-platform.sh
# Descrição: Verifica status completo da plataforma (Marco 1 + Marco 2)
# Uso: ./status-full-platform.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "📊 STATUS FULL PLATFORM"
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

# -----------------------------------------------------------------------------
# Marco 1: Cluster EKS
# -----------------------------------------------------------------------------

echo "=============================================="
echo "📍 MARCO 1: Cluster EKS"
echo "=============================================="
echo ""

CLUSTER_STATUS=$(aws eks describe-cluster --name k8s-platform-prod --region us-east-1 --profile "$AWS_PROFILE" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" == "NOT_FOUND" ]; then
    echo "🛑 Status: DESLIGADO (cluster não existe)"
    echo "💰 Custo atual: ~\$0.09/hora (apenas NAT Gateways)"
    echo ""
    echo "🚀 Para ligar:"
    echo "   cd $SCRIPT_DIR"
    echo "   ./startup-full-platform.sh"
    echo ""
    exit 0
fi

echo "✅ Status: $CLUSTER_STATUS"

# Executar script de status do Marco 1
cd "$TERRAFORM_DIR/marco1/scripts"
./status-cluster.sh

# -----------------------------------------------------------------------------
# Marco 2: Platform Services
# -----------------------------------------------------------------------------

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo ""
    echo "=============================================="
    echo "📍 MARCO 2: Platform Services"
    echo "=============================================="
    echo ""

    # Verificar kubectl
    if ! command -v kubectl &> /dev/null; then
        echo "⚠️  kubectl não instalado"
        exit 0
    fi

    if ! kubectl cluster-info &> /dev/null; then
        echo "⚠️  kubectl não conectado ao cluster"
        echo "   Execute: aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod --profile $AWS_PROFILE"
        exit 0
    fi

    # AWS Load Balancer Controller
    echo "🔍 AWS Load Balancer Controller:"
    ALB_PODS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$ALB_PODS" -gt 0 ]; then
        echo "   ✅ Running ($ALB_PODS pods)"
        kubectl get deployment -n kube-system aws-load-balancer-controller 2>/dev/null | tail -1
    else
        echo "   ❌ Não instalado ou não Running"
        echo "   Execute: cd $TERRAFORM_DIR/marco2 && terraform apply"
    fi

    echo ""

    # Cert-Manager
    echo "🔍 Cert-Manager:"
    CM_PODS=$(kubectl get pods -n cert-manager --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$CM_PODS" -gt 0 ]; then
        echo "   ✅ Running ($CM_PODS pods)"
        kubectl get deployment -n cert-manager 2>/dev/null | tail -3
    else
        echo "   ❌ Não instalado ou não Running"
        echo "   Execute: cd $TERRAFORM_DIR/marco2 && terraform apply"
    fi

    echo ""

    # ClusterIssuers
    echo "🔍 ClusterIssuers:"
    ISSUERS=$(kubectl get clusterissuer 2>/dev/null | tail -n +2 || echo "")
    if [ -z "$ISSUERS" ]; then
        echo "   ❌ Nenhum ClusterIssuer encontrado"
        echo "   Execute: kubectl apply -f $TERRAFORM_DIR/marco2/cluster-issuers/"
    else
        kubectl get clusterissuer 2>/dev/null | grep -E "NAME|READY"
    fi

    echo ""
fi

echo "=============================================="
echo "📋 Resumo"
echo "=============================================="
echo ""

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo "✅ Marco 1: Cluster LIGADO"

    if [ "$ALB_PODS" -gt 0 ] && [ "$CM_PODS" -gt 0 ]; then
        echo "✅ Marco 2: Platform Services OPERACIONAL"
    else
        echo "⚠️  Marco 2: Platform Services PARCIALMENTE INSTALADO"
    fi

    echo ""
    echo "🛑 Para desligar ao fim do dia:"
    echo "   cd $SCRIPT_DIR"
    echo "   ./shutdown-full-platform.sh"
else
    echo "🛑 Marco 1: Cluster DESLIGADO"
    echo "💤 Marco 2: Platform Services INATIVOS"
    echo ""
    echo "🚀 Para ligar:"
    echo "   cd $SCRIPT_DIR"
    echo "   ./startup-full-platform.sh"
fi

echo ""
