#!/bin/bash
# -----------------------------------------------------------------------------
# Script: plan-terraform.sh
# Descrição: Executa terraform plan para Marco 2
# Uso: ./plan-terraform.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "📋 TERRAFORM PLAN - Marco 2"
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
echo ""

# Executar terraform plan
echo "🔄 Executando terraform plan..."
echo ""

terraform plan "$@"

echo ""
echo "✅ Plan executado com sucesso!"
echo ""
