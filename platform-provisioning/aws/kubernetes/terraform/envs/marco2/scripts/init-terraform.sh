#!/bin/bash
# -----------------------------------------------------------------------------
# Script: init-terraform.sh
# Descrição: Inicializa Terraform para Marco 2
# Uso: ./init-terraform.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "🔧 TERRAFORM INIT - Marco 2"
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

# Inicializar Terraform
echo "🔄 Executando terraform init..."
echo ""

terraform init

echo ""
echo "✅ Terraform inicializado com sucesso!"
echo ""
echo "📋 Próximos passos:"
echo "   1. ./plan-terraform.sh  # Visualizar mudanças"
echo "   2. ./apply-terraform.sh # Aplicar mudanças"
echo ""
