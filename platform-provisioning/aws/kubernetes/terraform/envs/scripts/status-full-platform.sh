#!/bin/bash
# -----------------------------------------------------------------------------
# Script: status-full-platform.sh
# Descrição: Verifica status completo da plataforma (Marco 1 + Marco 2)
# Uso: ./status-full-platform.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "📊 STATUS FULL PLATFORM"
echo "=============================================="
echo ""

# Verificar AWS Profile
if [ -z "$AWS_PROFILE" ]; then
    export AWS_PROFILE=k8s-platform-prod
fi

# Verificar credenciais AWS
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
    echo "❌ ERRO: Credenciais AWS inválidas ou expiradas"
    echo "   Execute: aws sso login --profile $AWS_PROFILE"
    exit 1
fi

echo "🔐 AWS Account: $(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
echo "👤 User: $(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Arn --output text | cut -d'/' -f2)"
echo ""

# -----------------------------------------------------------------------------
# Marco 1: Cluster EKS
# -----------------------------------------------------------------------------

echo "=============================================="
echo "📍 MARCO 1: Cluster EKS"
echo "=============================================="
echo ""

CLUSTER_STATUS=$(aws eks describe-cluster --name k8s-platform-prod --region us-east-1 --profile "$AWS_PROFILE" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" == "NOT_FOUND" ]; then
    echo "🛑 Status: DESLIGADO (cluster não existe)"
else
    echo "✅ Status: $CLUSTER_STATUS"
fi

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    # Executar script de status do Marco 1
    cd "$TERRAFORM_DIR/marco1/scripts"
    ./status-cluster.sh
fi

# -----------------------------------------------------------------------------
# Marco 2: Platform Services
# -----------------------------------------------------------------------------

# Inicializar variáveis
ALB_PODS=0
CM_PODS=0
MON_PODS=0
LOKI_PODS=0
FB_PODS=0

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo ""
    echo "=============================================="
    echo "📍 MARCO 2: Platform Services"
    echo "=============================================="
    echo ""

    # Verificar kubectl
    if ! command -v kubectl &> /dev/null; then
        echo "⚠️  kubectl não instalado"
        exit 0
    fi

    if ! kubectl cluster-info &> /dev/null; then
        echo "⚠️  kubectl não conectado ao cluster"
        echo "   Execute: aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod --profile $AWS_PROFILE"
        exit 0
    fi

    # AWS Load Balancer Controller
    echo "🔍 AWS Load Balancer Controller:"
    ALB_PODS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$ALB_PODS" -gt 0 ]; then
        echo "   ✅ Running ($ALB_PODS pods)"
        kubectl get deployment -n kube-system aws-load-balancer-controller 2>/dev/null | tail -1
    else
        echo "   ❌ Não instalado ou não Running"
        echo "   Execute: cd $TERRAFORM_DIR/marco2 && terraform apply"
    fi

    echo ""

    # Cert-Manager
    echo "🔍 Cert-Manager:"
    CM_PODS=$(kubectl get pods -n cert-manager --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$CM_PODS" -gt 0 ]; then
        echo "   ✅ Running ($CM_PODS pods)"
        kubectl get deployment -n cert-manager 2>/dev/null | tail -3
    else
        echo "   ❌ Não instalado ou não Running"
        echo "   Execute: cd $TERRAFORM_DIR/marco2 && terraform apply"
    fi

    echo ""

    # ClusterIssuers
    echo "🔍 ClusterIssuers:"
    ISSUERS=$(kubectl get clusterissuer 2>/dev/null | tail -n +2 || echo "")
    if [ -z "$ISSUERS" ]; then
        echo "   ❌ Nenhum ClusterIssuer encontrado"
        echo "   Execute: kubectl apply -f $TERRAFORM_DIR/marco2/cluster-issuers/"
    else
        kubectl get clusterissuer 2>/dev/null
    fi

    echo ""

    # Monitoring Stack (Prometheus + Grafana)
    echo "🔍 Monitoring Stack (Prometheus + Grafana + Alertmanager):"
    MON_PODS=$(kubectl get pods -n monitoring --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$MON_PODS" -gt 0 ]; then
        echo "   ✅ Running ($MON_PODS pods)"

        # Prometheus
        PROM_STATUS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
        if [ "$PROM_STATUS" -gt 0 ]; then
            echo "   ✅ Prometheus: Running"
        else
            echo "   ⚠️  Prometheus: Not Running"
        fi

        # Grafana
        GRAF_STATUS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
        if [ "$GRAF_STATUS" -gt 0 ]; then
            echo "   ✅ Grafana: Running"
        else
            echo "   ⚠️  Grafana: Not Running"
        fi

        # Alertmanager
        AM_STATUS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
        if [ "$AM_STATUS" -gt 0 ]; then
            echo "   ✅ Alertmanager: Running"
        else
            echo "   ⚠️  Alertmanager: Not Running"
        fi

    else
        echo "   ❌ Não instalado ou não Running"
        echo "   Execute: cd $TERRAFORM_DIR/marco2 && terraform apply"
    fi

    echo ""

    # Loki (Logging)
    echo "🔍 Loki (Logging Backend):"
    LOKI_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=loki --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$LOKI_PODS" -gt 0 ]; then
        echo "   ✅ Running ($LOKI_PODS pods)"

        # Loki components
        LOKI_READ=$(kubectl get pods -n monitoring -l app.kubernetes.io/component=read --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
        LOKI_WRITE=$(kubectl get pods -n monitoring -l app.kubernetes.io/component=write --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
        LOKI_BACKEND=$(kubectl get pods -n monitoring -l app.kubernetes.io/component=backend --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
        LOKI_GATEWAY=$(kubectl get pods -n monitoring -l app.kubernetes.io/component=gateway --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")

        echo "   ├─ Read: $LOKI_READ/2"
        echo "   ├─ Write: $LOKI_WRITE/2"
        echo "   ├─ Backend: $LOKI_BACKEND/2"
        echo "   └─ Gateway: $LOKI_GATEWAY/2"

        # S3 Bucket
        S3_BUCKET=$(aws s3 ls --profile "$AWS_PROFILE" 2>/dev/null | grep "loki" | awk '{print $3}' || echo "")
        if [ -n "$S3_BUCKET" ]; then
            echo "   ✅ S3 Bucket: $S3_BUCKET"
        else
            echo "   ⚠️  S3 Bucket: Not found"
        fi
    else
        echo "   ❌ Não instalado ou não Running"
        echo "   Execute: cd $TERRAFORM_DIR/marco2 && terraform apply"
    fi

    echo ""

    # Fluent Bit (Log Collector)
    echo "🔍 Fluent Bit (Log Collector):"
    FB_PODS=$(kubectl get pods -n monitoring -l app=fluent-bit --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$FB_PODS" -gt 0 ]; then
        echo "   ✅ Running ($FB_PODS/$TOTAL_NODES pods - DaemonSet)"
        if [ "$FB_PODS" -eq "$TOTAL_NODES" ]; then
            echo "   ✅ 100% cobertura dos nós"
        else
            echo "   ⚠️  Cobertura parcial (esperado: $TOTAL_NODES pods)"
        fi
    else
        echo "   ❌ Não instalado ou não Running"
        echo "   Execute: cd $TERRAFORM_DIR/marco2 && terraform apply"
    fi

    echo ""

    # PVCs consolidado
    echo "📊 Persistent Volumes (monitoring namespace):"
    kubectl get pvc -n monitoring 2>/dev/null | tail -n +2 | awk '{printf "   %s: %s (%s)\n", $1, $4, $2}'

    echo ""
fi

echo "=============================================="
echo "📋 Resumo"
echo "=============================================="
echo ""

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo "✅ Marco 1: Cluster LIGADO"

    if [ "$ALB_PODS" -gt 0 ] && [ "$CM_PODS" -gt 0 ] && [ "$MON_PODS" -gt 0 ] && [ "$LOKI_PODS" -gt 0 ] && [ "$FB_PODS" -gt 0 ]; then
        echo "✅ Marco 2: Platform Services COMPLETO (4/4 fases)"
        echo "   - Fase 1: AWS Load Balancer Controller ✅"
        echo "   - Fase 2: Cert-Manager ✅"
        echo "   - Fase 3: Prometheus + Grafana + Alertmanager ✅"
        echo "   - Fase 4: Loki + Fluent Bit (Logging) ✅"
    else
        echo "⚠️  Marco 2: Platform Services PARCIALMENTE INSTALADO"
        [ "$ALB_PODS" -eq 0 ] && echo "   - Fase 1: AWS Load Balancer Controller ❌"
        [ "$CM_PODS" -eq 0 ] && echo "   - Fase 2: Cert-Manager ❌"
        [ "$MON_PODS" -eq 0 ] && echo "   - Fase 3: Prometheus + Grafana + Alertmanager ❌"
        [ "$LOKI_PODS" -eq 0 ] && echo "   - Fase 4: Loki (Logging) ❌"
        [ "$FB_PODS" -eq 0 ] && echo "   - Fase 4: Fluent Bit ❌"
    fi

    echo ""
    echo "💰 Custo atual LIGADO: ~\$0.76/hora (~\$547/mês)"
    echo "   - Cluster EKS: \$0.10/hora (\$72/mês)"
    echo "   - 7 Nodes EC2: 7×\$0.0928/h (\$466/mês)"
    echo "   - 2 NAT Gateways: 2×\$0.045/h (\$66/mês)"
    echo "   - EBS Volumes: \$5.36/mês (67Gi)"
    echo "   - S3 (Loki): \$16.50/mês"

    echo ""
    echo "🛑 Para desligar ao fim do dia:"
    echo "   cd $SCRIPT_DIR"
    echo "   ./shutdown-full-platform.sh"
    echo "   💡 Economia: ~\$466/mês (cluster + nodes removidos)"
else
    echo "🛑 Marco 1: Cluster DESLIGADO"
    echo "💤 Marco 2: Platform Services INATIVOS"
    echo ""

    # Mostrar recursos preservados (volumes EBS)
    echo "💾 Recursos PRESERVADOS (dados não perdidos):"
    EBS_VOLUMES=$(aws ec2 describe-volumes \
        --region us-east-1 \
        --profile "$AWS_PROFILE" \
        --filters "Name=tag:kubernetes.io/cluster/k8s-platform-prod,Values=owned" \
        --query 'Volumes[*].[VolumeId,Size,State,Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null | wc -l || echo "0")

    if [ "$EBS_VOLUMES" -gt 0 ]; then
        echo "   ✅ EBS Volumes: $EBS_VOLUMES volumes (~\$5.36/mês)"
        aws ec2 describe-volumes \
            --region us-east-1 \
            --profile "$AWS_PROFILE" \
            --filters "Name=tag:kubernetes.io/cluster/k8s-platform-prod,Values=owned" \
            --query 'Volumes[*].[Tags[?Key==`Name`].Value|[0],Size,State]' \
            --output text 2>/dev/null | while read name size state; do
            echo "      - $name: ${size}Gi ($state)"
        done
    else
        echo "   ⚠️  EBS Volumes: Nenhum volume encontrado"
    fi

    # Verificar S3 bucket Loki
    S3_BUCKET=$(aws s3 ls --profile "$AWS_PROFILE" 2>/dev/null | grep "loki" | awk '{print $3}' || echo "")
    if [ -n "$S3_BUCKET" ]; then
        # Obter tamanho do bucket
        S3_SIZE=$(aws s3 ls s3://$S3_BUCKET --recursive --summarize --profile "$AWS_PROFILE" 2>/dev/null | grep "Total Size" | awk '{print $3}' || echo "0")
        S3_SIZE_GB=$((S3_SIZE / 1024 / 1024 / 1024))
        echo "   ✅ S3 Bucket: $S3_BUCKET (~\$16.50/mês)"
        echo "      - Tamanho: ${S3_SIZE_GB}GB"
        echo "      - Retenção: 30 dias"
        echo "      - Logs históricos preservados"
    else
        echo "   ⚠️  S3 Bucket: Não encontrado"
    fi

    echo ""
    echo "💰 Custo atual DESLIGADO: ~\$81/mês"
    echo "   - NAT Gateways: \$66/mês (2×\$0.045/h)"
    echo "   - EBS Volumes: \$5.36/mês (67Gi preservados)"
    echo "   - S3 (Loki): \$16.50/mês (logs históricos)"
    echo "   ℹ️  Volumes mantidos para preservar métricas e logs"

    echo ""
    echo "🚀 Para religar a plataforma:"
    echo "   cd $SCRIPT_DIR"
    echo "   ./startup-full-platform.sh"
    echo "   ℹ️  Todos os dados históricos serão restaurados"
fi

echo ""
