#!/bin/bash
# -----------------------------------------------------------------------------
# Script: shutdown-full-platform.sh
# Descrição: Desliga cluster EKS (Marco 1) - Platform Services (Marco 2) ficam no state
# Uso: ./shutdown-full-platform.sh
# Tempo estimado: ~6 minutos
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "🛑 SHUTDOWN FULL PLATFORM"
echo "=============================================="
echo ""
echo "Este script irá:"
echo "  1. Desligar cluster EKS (Marco 1) - ~6 min"
echo ""
echo "⚠️  NOTA IMPORTANTE:"
echo "  - Recursos do Marco 2 (IAM, OIDC) permanecerão (não geram custo)"
echo "  - Pods (ALB Controller, Cert-Manager) serão removidos"
echo "  - No próximo startup, Marco 2 será reaplicado automaticamente"
echo ""
echo "💰 Economia estimada: ~\$0.76/hora (~\$18.24/dia)"
echo ""

# Verificar AWS Profile
if [ -z "$AWS_PROFILE" ]; then
    export AWS_PROFILE=k8s-platform-prod
fi

# Verificar credenciais AWS
echo "🔐 Validando credenciais AWS..."
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
    echo "❌ ERRO: Credenciais AWS inválidas ou expiradas"
    echo "   Execute: aws sso login --profile $AWS_PROFILE"
    exit 1
fi

echo "✅ Credenciais válidas"
echo ""

read -p "Deseja continuar? (sim/não): " CONFIRM

if [ "$CONFIRM" != "sim" ]; then
    echo "❌ Operação cancelada pelo usuário"
    exit 0
fi

# -----------------------------------------------------------------------------
# Desligar cluster EKS (Marco 1)
# -----------------------------------------------------------------------------

echo ""
echo "=============================================="
echo "📍 Desligando Cluster EKS (Marco 1)"
echo "=============================================="
echo ""

cd "$TERRAFORM_DIR/marco1/scripts"
./shutdown-cluster.sh

if [ $? -ne 0 ]; then
    echo "❌ Erro ao desligar cluster EKS"
    exit 1
fi

# -----------------------------------------------------------------------------
# RESUMO FINAL
# -----------------------------------------------------------------------------

echo ""
echo "=============================================="
echo "✅ PLATAFORMA DESLIGADA!"
echo "=============================================="
echo ""

echo "📊 Recursos REMOVIDOS:"
echo "  - Cluster EKS k8s-platform-prod"
echo "  - 7 nodes EC2"
echo "  - Pods (ALB Controller, Cert-Manager)"
echo "  - 4 add-ons EKS"
echo ""

echo "📊 Recursos que PERMANECEM (sem custo):"
echo "  - OIDC Provider (IAM - gratuito)"
echo "  - IAM Policies e Roles (gratuito)"
echo "  - State Terraform Marco 2 (S3 - ~\$0.00002/mês)"
echo "  - VPC e subnets (gratuito)"
echo "  - NAT Gateways (2) - \$0.09/hora (~\$66/mês)"
echo ""

echo "💰 Custo atual: ~\$0.09/hora (apenas NAT Gateways)"
echo ""

echo "🚀 Para religar a plataforma:"
echo "   cd $SCRIPT_DIR"
echo "   ./startup-full-platform.sh"
echo ""
