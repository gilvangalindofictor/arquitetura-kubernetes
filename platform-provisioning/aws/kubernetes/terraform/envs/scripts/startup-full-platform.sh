#!/bin/bash
# -----------------------------------------------------------------------------
# Script: startup-full-platform.sh
# Descrição: Liga cluster EKS + Platform Services (Marco 1 + Marco 2)
# Uso: ./startup-full-platform.sh
# Tempo estimado: ~20 minutos
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "🚀 STARTUP FULL PLATFORM"
echo "=============================================="
echo ""
echo "Este script irá:"
echo "  1. Ligar cluster EKS (Marco 1) - ~15 min"
echo "  2. Instalar Platform Services (Marco 2) - ~3 min"
echo "  3. Recriar ClusterIssuers do Cert-Manager"
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
# PASSO 1: Ligar cluster EKS (Marco 1)
# -----------------------------------------------------------------------------

echo ""
echo "=============================================="
echo "📍 PASSO 1/3: Ligando Cluster EKS (Marco 1)"
echo "=============================================="
echo ""

cd "$TERRAFORM_DIR/marco1/scripts"
./startup-cluster.sh

if [ $? -ne 0 ]; then
    echo "❌ Erro ao ligar cluster EKS"
    exit 1
fi

# -----------------------------------------------------------------------------
# PASSO 2: Aplicar Platform Services (Marco 2)
# -----------------------------------------------------------------------------

echo ""
echo "=============================================="
echo "📍 PASSO 2/3: Instalando Platform Services (Marco 2)"
echo "=============================================="
echo ""

cd "$TERRAFORM_DIR/marco2"

# Terraform init (caso providers tenham mudado)
echo "🔄 Inicializando Terraform Marco 2..."
terraform init -input=false

# Terraform apply
echo ""
echo "🚀 Aplicando Marco 2..."
terraform apply -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Erro ao aplicar Marco 2"
    exit 1
fi

# -----------------------------------------------------------------------------
# PASSO 3: Recriar ClusterIssuers
# -----------------------------------------------------------------------------

echo ""
echo "=============================================="
echo "📍 PASSO 3/3: Recriando ClusterIssuers"
echo "=============================================="
echo ""

# Aguardar CRDs do Cert-Manager ficarem disponíveis
echo "⏳ Aguardando CRDs do Cert-Manager..."
sleep 30

# Aplicar ClusterIssuers
echo "📝 Aplicando ClusterIssuers..."
kubectl apply -f "$TERRAFORM_DIR/marco2/cluster-issuers/"

if [ $? -ne 0 ]; then
    echo "⚠️  Aviso: Erro ao aplicar ClusterIssuers"
    echo "   Você pode aplicar manualmente depois:"
    echo "   kubectl apply -f $TERRAFORM_DIR/marco2/cluster-issuers/"
fi

# -----------------------------------------------------------------------------
# VALIDAÇÃO FINAL
# -----------------------------------------------------------------------------

echo ""
echo "=============================================="
echo "✅ PLATAFORMA COMPLETA LIGADA!"
echo "=============================================="
echo ""

echo "📊 Validando componentes..."
echo ""

echo "🔍 Cluster EKS:"
kubectl get nodes -L node-type,workload | head -8

echo ""
echo "🔍 Platform Services:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get pods -n cert-manager

echo ""
echo "🔍 ClusterIssuers:"
kubectl get clusterissuer

echo ""
echo "=============================================="
echo "📋 Resumo"
echo "=============================================="
echo ""
echo "✅ Marco 1: Cluster EKS com 7 nodes"
echo "✅ Marco 2: AWS Load Balancer Controller"
echo "✅ Marco 2: Cert-Manager"
echo "✅ ClusterIssuers: Let's Encrypt Staging/Production/Self-Signed"
echo ""
echo "🎉 Plataforma pronta para uso!"
echo ""
echo "💡 Para desligar ao fim do dia:"
echo "   cd $SCRIPT_DIR"
echo "   ./shutdown-full-platform.sh"
echo ""
