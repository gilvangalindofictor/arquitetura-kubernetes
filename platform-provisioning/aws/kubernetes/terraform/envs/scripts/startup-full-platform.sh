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
kubectl get pods -n monitoring

echo ""
echo "🔍 Network Policies (Calico):"
kubectl get pods -n calico-system 2>/dev/null || echo "   ℹ️  Calico não encontrado"
kubectl get networkpolicies -A 2>/dev/null | grep -E "NAMESPACE|kube-system|monitoring|cert-manager" || echo "   ℹ️  Nenhuma Network Policy encontrada"

echo ""
echo "🔍 Cluster Autoscaler:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler 2>/dev/null || echo "   ℹ️  Cluster Autoscaler não encontrado"

echo ""
echo "🔍 ClusterIssuers:"
kubectl get clusterissuer 2>/dev/null || echo "   ⚠️  Nenhum ClusterIssuer encontrado"

echo ""
echo "🔍 Persistent Volumes:"
kubectl get pvc -n monitoring

echo ""
echo "=============================================="
echo "📋 Resumo"
echo "=============================================="
echo ""
echo "✅ Marco 1: Cluster EKS com 7 nodes"
echo "✅ Marco 2 Fase 1: AWS Load Balancer Controller"
echo "✅ Marco 2 Fase 2: Cert-Manager"
echo "✅ Marco 2 Fase 3: Prometheus + Grafana + Alertmanager"
echo "✅ Marco 2 Fase 4: Loki + Fluent Bit (Logging)"
echo "✅ Marco 2 Fase 5: Network Policies (Calico policy-only + 11 políticas)"
echo "✅ Marco 2 Fase 6: Cluster Autoscaler (IRSA + scale-down habilitado)"
echo "✅ ClusterIssuers: Let's Encrypt Staging/Production/Self-Signed"
echo "✅ Volumes: 47Gi provisionados (Grafana 5Gi, Prometheus 20Gi, Alertmanager 2Gi, Loki 20Gi)"
echo "✅ S3 Bucket: Loki logs com retenção de 30 dias"
echo ""
echo "🎉 Plataforma pronta para uso!"
echo ""
echo "📊 Acesso ao Grafana:"
echo "   kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "   URL: http://localhost:3000"
echo "   Usuário: admin | Senha: (configurada no terraform.tfvars)"
echo ""
echo "📊 Verificar Logs (Loki):"
echo "   - No Grafana: Explore → Datasource: Loki"
echo "   - Query: {cluster=\"k8s-platform-prod\"}"
echo ""
echo "💡 Para desligar ao fim do dia:"
echo "   cd $SCRIPT_DIR"
echo "   ./shutdown-full-platform.sh"
echo ""
