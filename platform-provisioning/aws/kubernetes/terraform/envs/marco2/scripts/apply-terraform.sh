#!/bin/bash
# -----------------------------------------------------------------------------
# Script: apply-terraform.sh
# Descrição: Aplica configurações do Marco 2 via Terraform
# Uso: ./apply-terraform.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "🚀 TERRAFORM APPLY - Marco 2"
echo "=============================================="
echo ""
echo "📍 Diretório: $TERRAFORM_DIR"
echo ""

# Navegar para o diretório Terraform
cd "$TERRAFORM_DIR"

# Verificar AWS Profile
if [ -z "$AWS_PROFILE" ]; then
    echo "⚠️  AWS_PROFILE não definido, usando profile: k8s-platform-prod"
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
echo "   Account: $(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
echo "   User: $(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Arn --output text | cut -d'/' -f2)"
echo ""

# Confirmar com usuário
echo "ℹ️  Este script irá instalar:"
echo "   - AWS Load Balancer Controller (Ingress Controller)"
echo "   - IAM Policy e Role com IRSA"
echo "   - Kubernetes Service Account"
echo ""
echo "⏱️  Tempo estimado: ~3-5 minutos"
echo ""

read -p "Deseja continuar? (sim/não): " CONFIRM

if [ "$CONFIRM" != "sim" ]; then
    echo "❌ Operação cancelada pelo usuário"
    exit 0
fi

echo ""
echo "🔄 Executando terraform apply..."
echo ""

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

terraform apply -auto-approve 2>&1 | tee "/tmp/terraform-marco2-apply-$TIMESTAMP.log"

EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=============================================="
    echo "✅ MARCO 2 INSTALADO COM SUCESSO!"
    echo "=============================================="
    echo ""

    echo "📊 Validando instalação..."
    echo ""

    # Verificar deployment do controller
    echo "🔍 AWS Load Balancer Controller:"
    kubectl get deployment -n kube-system aws-load-balancer-controller 2>/dev/null || echo "   ⚠️  Deployment ainda não disponível (pode levar alguns segundos)"

    echo ""
    echo "🔍 Pods do controller:"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller 2>/dev/null || echo "   ⚠️  Pods ainda não disponíveis (pode levar alguns segundos)"

    echo ""
    echo "📋 Log completo: /tmp/terraform-marco2-apply-$TIMESTAMP.log"
    echo ""
    echo "📊 Próximos passos:"
    echo "   1. Aguardar pods ficarem Ready (~1-2 minutos)"
    echo "   2. Testar criando um Ingress de exemplo"
    echo ""
else
    echo ""
    echo "=============================================="
    echo "❌ ERRO AO INSTALAR MARCO 2"
    echo "=============================================="
    echo ""
    echo "📋 Log completo: /tmp/terraform-marco2-apply-$TIMESTAMP.log"
    echo ""
    exit $EXIT_CODE
fi
