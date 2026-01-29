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
echo "  - Pods (ALB Controller, Cert-Manager, Prometheus, Grafana, Loki, Fluent Bit, Calico, Cluster Autoscaler, Test Apps)"
echo "  - 4 add-ons EKS"
echo "  - 2 ALBs (test applications - custo $32.40/mês removido)"
echo "  - Network Policies (11 políticas - serão recriadas no próximo startup)"
echo ""

echo "📊 Recursos que PERMANECEM (sem custo):"
echo "  - OIDC Provider (IAM - gratuito)"
echo "  - IAM Policies e Roles (gratuito)"
echo "  - State Terraform Marco 2 (S3 - ~\$0.00002/mês)"
echo "  - VPC e subnets (gratuito)"
echo "  - NAT Gateways (2) - \$0.09/hora (~\$66/mês)"
echo ""

echo "📊 Recursos que PERMANECEM (com custo):"
echo "  - EBS Volumes (PVCs) - \$3.76/mês (~47GB total)"
echo "    * Grafana: 5Gi = \$0.40/mês"
echo "    * Prometheus: 20Gi = \$1.60/mês"
echo "    * Alertmanager: 2Gi = \$0.16/mês"
echo "    * Loki (write): 10Gi = \$0.80/mês"
echo "    * Loki (backend): 10Gi = \$0.80/mês"
echo "  - S3 Bucket (Loki) - ~\$11.50/mês (500GB estimado)"
echo "  ℹ️  Volumes e S3 são mantidos para preservar dados históricos"
echo ""

echo "💰 Custo atual enquanto desligado: ~\$0.09/hora + \$15.26/mês"
echo "   (NAT Gateways \$66/mês + Volumes \$3.76/mês + S3 \$11.50/mês = ~\$81/mês)"
echo ""

echo "🚀 Para religar a plataforma:"
echo "   cd $SCRIPT_DIR"
echo "   ./startup-full-platform.sh"
echo ""
