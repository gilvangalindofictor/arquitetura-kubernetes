#!/bin/bash
# -----------------------------------------------------------------------------
# Script: startup-cluster.sh
# Descrição: Recria o cluster EKS via Terraform (100% conformidade IaC)
# Uso: ./startup-cluster.sh
# Tempo estimado: ~15 minutos
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "🚀 STARTUP CLUSTER EKS - Marco 1"
echo "=============================================="
echo ""
echo "📍 Diretório Terraform: $TERRAFORM_DIR"
echo ""

# Verificar se estamos no diretório correto
if [ ! -f "$TERRAFORM_DIR/main.tf" ]; then
    echo "❌ ERRO: main.tf não encontrado em $TERRAFORM_DIR"
    exit 1
fi

# Confirmar com usuário
echo "ℹ️  Este script irá criar:"
echo "   - Cluster EKS k8s-platform-prod (Kubernetes 1.31)"
echo "   - 7 nodes (2 system + 3 workloads + 2 critical)"
echo "   - 4 add-ons (CoreDNS, VPC CNI, Kube-proxy, EBS CSI Driver)"
echo "   - Security Groups e KMS Key"
echo ""
echo "⏱️  Tempo estimado: ~15 minutos"
echo "💰 Custo estimado: ~$0.76/hora (~$547/mês) enquanto ligado"
echo ""

read -p "Deseja continuar? (sim/não): " CONFIRM

if [ "$CONFIRM" != "sim" ]; then
    echo "❌ Operação cancelada pelo usuário"
    exit 0
fi

echo ""
echo "🔄 Iniciando criação da infraestrutura..."
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

# Executar terraform plan primeiro
echo "📋 Executando terraform plan..."
echo ""

terraform plan -out=/tmp/terraform-startup.tfplan

echo ""
read -p "Plano aprovado? Deseja aplicar? (sim/não): " CONFIRM_PLAN

if [ "$CONFIRM_PLAN" != "sim" ]; then
    echo "❌ Operação cancelada pelo usuário"
    rm -f /tmp/terraform-startup.tfplan
    exit 0
fi

# Executar terraform apply
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo ""
echo "🚀 Executando terraform apply..."
echo ""
echo "📊 Timeline esperado:"
echo "   - 0-15s: Security Groups e KMS Key"
echo "   - 15s-11m: Cluster EKS"
echo "   - 11m-13m: Node Groups (3)"
echo "   - 13m-15m: Add-ons (4)"
echo ""

terraform apply /tmp/terraform-startup.tfplan 2>&1 | tee "/tmp/terraform-startup-$TIMESTAMP.log"

EXIT_CODE=${PIPESTATUS[0]}

# Remover arquivo de plano
rm -f /tmp/terraform-startup.tfplan

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=============================================="
    echo "✅ CLUSTER CRIADO COM SUCESSO!"
    echo "=============================================="
    echo ""

    # Configurar kubectl automaticamente
    echo "🔧 Configurando kubectl..."
    aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod --profile "$AWS_PROFILE"

    echo ""
    echo "📊 Validando nodes..."
    kubectl get nodes -L node-type,workload,eks.amazonaws.com/nodegroup

    echo ""
    echo "📊 Validando pods do sistema..."
    kubectl get pods -n kube-system

    echo ""
    echo "=============================================="
    echo "📋 Informações do Cluster"
    echo "=============================================="
    echo ""

    # Extrair outputs do Terraform
    CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint 2>/dev/null || echo "N/A")
    CLUSTER_VERSION=$(terraform output -raw cluster_version 2>/dev/null || echo "N/A")

    echo "Nome: k8s-platform-prod"
    echo "Endpoint: $CLUSTER_ENDPOINT"
    echo "Versão: $CLUSTER_VERSION"
    echo "Region: us-east-1"
    echo ""
    echo "📋 Log completo: /tmp/terraform-startup-$TIMESTAMP.log"
    echo ""
    echo "🛑 Para desligar o cluster ao fim do dia:"
    echo "   ./shutdown-cluster.sh"
    echo ""
else
    echo ""
    echo "=============================================="
    echo "❌ ERRO AO CRIAR CLUSTER"
    echo "=============================================="
    echo ""
    echo "📋 Log completo: /tmp/terraform-startup-$TIMESTAMP.log"
    echo ""
    echo "Para troubleshooting:"
    echo "1. Verificar locks no DynamoDB: terraform force-unlock <LOCK_ID>"
    echo "2. Verificar state: terraform state list"
    echo "3. Revisar log: cat /tmp/terraform-startup-$TIMESTAMP.log"
    echo ""
    exit $EXIT_CODE
fi
