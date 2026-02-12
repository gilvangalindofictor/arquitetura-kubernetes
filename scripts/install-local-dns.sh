#!/bin/bash
# install-local-dns.sh
# Configura /etc/hosts para DNS local da plataforma K8s

set -e

echo "🔍 Descobrindo IP do ALB..."

ALB_HOSTNAME=$(kubectl get ingress -n gitlab-staging gitlab-webservice-default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -z "$ALB_HOSTNAME" ]; then
  echo "❌ Falha ao obter hostname do ALB. Verifique acesso ao cluster."
  exit 1
fi

echo "📡 ALB Hostname: $ALB_HOSTNAME"

# Tentar resolver IP (dig pode não estar instalado em WSL)
if command -v dig &> /dev/null; then
  ALB_IP=$(dig +short "$ALB_HOSTNAME" | head -1)
else
  # Fallback: usar IP fixo atual
  ALB_IP="50.17.236.17"
  echo "⚠️  dig não disponível. Usando IP fixo: $ALB_IP"
  echo "   (Recomendado instalar: sudo apt-get install dnsutils)"
fi

if [ -z "$ALB_IP" ]; then
  echo "❌ Falha ao resolver IP do ALB."
  exit 1
fi

echo "✅ ALB IP: $ALB_IP"
echo ""

# Backup
BACKUP_FILE="/etc/hosts.backup.$(date +%Y%m%d-%H%M%S)"
echo "📦 Criando backup: $BACKUP_FILE"
sudo cp /etc/hosts "$BACKUP_FILE"

# Remover entradas antigas (se existirem)
echo "🧹 Removendo entradas antigas (.staging.internal)..."
sudo sed -i '/.staging.internal/d' /etc/hosts

# Adicionar entradas
echo "➕ Adicionando entradas ao /etc/hosts..."
sudo tee -a /etc/hosts > /dev/null <<EOF

# ========================================
# Kubernetes Platform - Staging Environment
# Domain: .staging.internal (corporate convention)
# Generated: $(date)
# ALB: $ALB_HOSTNAME
# ========================================
$ALB_IP  gitlab.staging.internal
$ALB_IP  argocd.staging.internal
$ALB_IP  keycloak.staging.internal
$ALB_IP  sonarqube.staging.internal
$ALB_IP  harbor.staging.internal
EOF

echo ""
echo "✅ /etc/hosts atualizado com sucesso!"
echo ""
echo "🧪 Testando conectividade..."
echo ""

if curl -I -s -o /dev/null -w "%{http_code}" http://gitlab.staging.internal | grep -q "302\|200"; then
  echo "✅ GitLab: http://gitlab.staging.internal (OK)"
else
  echo "⚠️  GitLab: http://gitlab.staging.internal (não responde ainda)"
fi

echo ""
echo "📋 Próximos passos:"
echo "   1. Testar no browser: http://gitlab.staging.internal"
echo "   2. Criar ingresses para ArgoCD/Keycloak (pendente Marco 4)"
echo "   3. Compartilhar docs/operations/local-dns-setup.md com o time"
echo ""
echo "📖 Documentação completa: docs/operations/local-dns-setup.md"
echo "🔄 Para reverter: sudo cp $BACKUP_FILE /etc/hosts"
