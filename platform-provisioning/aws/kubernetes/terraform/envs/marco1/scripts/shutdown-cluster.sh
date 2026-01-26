#!/bin/bash
# -----------------------------------------------------------------------------
# Script: shutdown-cluster.sh
# Descrição: Desliga completamente o cluster EKS para economia de custos
# Uso: ./shutdown-cluster.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "🛑 SHUTDOWN CLUSTER EKS - Marco 1"
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
echo "⚠️  ATENÇÃO: Este script irá destruir:"
echo "   - Cluster EKS k8s-platform-prod"
echo "   - 7 nodes (2 system + 3 workloads + 2 critical)"
echo "   - 4 add-ons (CoreDNS, VPC CNI, Kube-proxy, EBS CSI Driver)"
echo "   - Security Groups e KMS Key"
echo ""
echo "   Recursos que NÃO serão destruídos:"
echo "   - VPC fictor-vpc e suas subnets"
echo "   - NAT Gateways e Internet Gateway"
echo "   - IAM Roles"
echo ""
echo "💰 Economia estimada: ~$0.76/hora (~$547/mês)"
echo ""

read -p "Deseja continuar? (sim/não): " CONFIRM

if [ "$CONFIRM" != "sim" ]; then
    echo "❌ Operação cancelada pelo usuário"
    exit 0
fi

echo ""
echo "🔄 Iniciando destruição da infraestrutura..."
echo ""

# Navegar para o diretório Terraform
cd "$TERRAFORM_DIR"

# Verificar AWS Profile
if [ -z "$AWS_PROFILE" ]; then
    echo "⚠️  AWS_PROFILE não definido, usando profile: k8s-platform-prod"
    export AWS_PROFILE=k8s-platform-prod
fi

# Criar backup do state antes da destruição
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$HOME/.terraform-backups/marco1"
mkdir -p "$BACKUP_DIR"

echo "💾 Criando backup do state..."
terraform state pull > "$BACKUP_DIR/terraform.tfstate.backup.$TIMESTAMP" 2>/dev/null || true

# Executar terraform destroy
echo ""
echo "🗑️  Executando terraform destroy..."
echo ""

terraform destroy -auto-approve 2>&1 | tee "/tmp/terraform-shutdown-$TIMESTAMP.log"

EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=============================================="
    echo "✅ CLUSTER DESLIGADO COM SUCESSO!"
    echo "=============================================="
    echo ""
    echo "📊 Recursos destruídos:"
    echo "   - Cluster EKS k8s-platform-prod"
    echo "   - 7 nodes EC2"
    echo "   - 4 add-ons EKS"
    echo "   - Security Groups e KMS Key"
    echo ""
    echo "💾 Backup do state: $BACKUP_DIR/terraform.tfstate.backup.$TIMESTAMP"
    echo "📋 Log da operação: /tmp/terraform-shutdown-$TIMESTAMP.log"
    echo ""
    echo "🚀 Para religar o cluster, execute:"
    echo "   ./startup-cluster.sh"
    echo ""
else
    echo ""
    echo "=============================================="
    echo "❌ ERRO AO DESLIGAR CLUSTER"
    echo "=============================================="
    echo ""
    echo "📋 Log completo: /tmp/terraform-shutdown-$TIMESTAMP.log"
    echo "💾 Backup do state: $BACKUP_DIR/terraform.tfstate.backup.$TIMESTAMP"
    echo ""
    echo "Para troubleshooting:"
    echo "1. Verificar locks no DynamoDB: terraform force-unlock <LOCK_ID>"
    echo "2. Verificar state: terraform state list"
    echo "3. Tentar novamente: ./shutdown-cluster.sh"
    echo ""
    exit $EXIT_CODE
fi
