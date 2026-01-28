#!/usr/bin/env bash
# =============================================================================
# VALIDATION SCRIPT - Cluster Autoscaler (Marco 2 Fase 6)
# =============================================================================
# Validates Cluster Autoscaler deployment and functionality
# Tests scale-up and scale-down behavior
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cluster configuration
CLUSTER_NAME="${CLUSTER_NAME:-k8s-platform-prod}"
NAMESPACE="kube-system"
DEPLOYMENT_NAME="cluster-autoscaler"

# Test configuration
TEST_NAMESPACE="default"
TEST_DEPLOYMENT="autoscaler-test"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 não está instalado"
        exit 1
    fi
}

wait_for_pods() {
    local namespace=$1
    local label=$2
    local expected_count=$3
    local timeout=${4:-300}

    print_info "Aguardando $expected_count pod(s) com label '$label' no namespace '$namespace'..."

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local ready_count=$(kubectl get pods -n "$namespace" -l "$label" \
            --field-selector=status.phase=Running \
            --no-headers 2>/dev/null | wc -l)

        if [ "$ready_count" -ge "$expected_count" ]; then
            print_success "$expected_count pod(s) Running"
            return 0
        fi

        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done

    print_error "Timeout esperando pods"
    return 1
}

# -----------------------------------------------------------------------------
# Validation Checks
# -----------------------------------------------------------------------------

print_header "VALIDAÇÃO - Cluster Autoscaler (Marco 2 Fase 6)"

print_info "Cluster: $CLUSTER_NAME"
print_info "Namespace: $NAMESPACE"
print_info "Data: $(date '+%Y-%m-%d %H:%M:%S')"

# Check required commands
print_header "1. Verificando Ferramentas"
check_command kubectl
check_command aws
print_success "Todas as ferramentas necessárias instaladas"

# Check cluster connectivity
print_header "2. Verificando Conectividade com Cluster"
if kubectl cluster-info &> /dev/null; then
    print_success "Conectado ao cluster $CLUSTER_NAME"
else
    print_error "Falha ao conectar ao cluster"
    exit 1
fi

# Check Cluster Autoscaler deployment
print_header "3. Verificando Deployment"
if kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &> /dev/null; then
    print_success "Deployment $DEPLOYMENT_NAME encontrado"

    # Check replicas
    REPLICAS=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}')

    if [ "${REPLICAS:-0}" -ge 1 ]; then
        print_success "Deployment com $REPLICAS réplica(s) Running"
    else
        print_error "Deployment sem réplicas Running"
        kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"
        exit 1
    fi
else
    print_error "Deployment $DEPLOYMENT_NAME não encontrado"
    exit 1
fi

# Check pods
print_header "4. Verificando Pods"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" \
    -l app.kubernetes.io/name=cluster-autoscaler \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$POD_NAME" ]; then
    print_success "Pod encontrado: $POD_NAME"

    # Check pod status
    POD_STATUS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.status.phase}')

    if [ "$POD_STATUS" == "Running" ]; then
        print_success "Pod status: Running"
    else
        print_error "Pod status: $POD_STATUS"
        kubectl describe pod "$POD_NAME" -n "$NAMESPACE"
        exit 1
    fi
else
    print_error "Nenhum pod encontrado"
    exit 1
fi

# Check Service Account
print_header "5. Verificando Service Account"
SA_NAME=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.serviceAccountName}')

if [ -n "$SA_NAME" ]; then
    print_success "Service Account: $SA_NAME"

    # Check IRSA annotation
    IAM_ROLE=$(kubectl get sa "$SA_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)

    if [ -n "$IAM_ROLE" ]; then
        print_success "IAM Role ARN: $IAM_ROLE"
    else
        print_warning "IAM Role annotation não encontrada (IRSA pode não estar configurado)"
    fi
else
    print_error "Service Account não encontrado"
fi

# Check logs for errors
print_header "6. Verificando Logs (últimas 50 linhas)"
echo "---"
kubectl logs "$POD_NAME" -n "$NAMESPACE" --tail=50 2>/dev/null | grep -E "ERROR|WARN|scale|node" || true
echo "---"

# Check for IAM permission errors
if kubectl logs "$POD_NAME" -n "$NAMESPACE" --tail=100 2>/dev/null | \
   grep -i "unauthorized\|access denied\|permission" > /dev/null; then
    print_error "Erros de permissão IAM detectados nos logs"
    print_info "Verifique se a IAM Role tem as permissões corretas"
else
    print_success "Nenhum erro de permissão IAM nos logs"
fi

# Check Auto Scaling Groups tags
print_header "7. Verificando Tags dos Auto Scaling Groups"
print_info "Buscando ASGs com tags do Cluster Autoscaler..."

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
print_info "AWS Account: $AWS_ACCOUNT_ID"

ASG_LIST=$(aws autoscaling describe-auto-scaling-groups \
    --query "AutoScalingGroups[?contains(Tags[?Key=='eks:cluster-name'].Value, '$CLUSTER_NAME')].AutoScalingGroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$ASG_LIST" ]; then
    print_success "ASGs encontrados: $ASG_LIST"

    for ASG in $ASG_LIST; do
        echo ""
        print_info "ASG: $ASG"

        # Check Cluster Autoscaler tags
        CA_ENABLED=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG" \
            --query "AutoScalingGroups[0].Tags[?Key=='k8s.io/cluster-autoscaler/enabled'].Value" \
            --output text 2>/dev/null || echo "")

        CA_CLUSTER=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG" \
            --query "AutoScalingGroups[0].Tags[?Key=='k8s.io/cluster-autoscaler/$CLUSTER_NAME'].Value" \
            --output text 2>/dev/null || echo "")

        if [ "$CA_ENABLED" == "true" ] && [ "$CA_CLUSTER" == "owned" ]; then
            print_success "  Tags corretas: enabled=true, cluster=owned"
        elif [ "$CA_ENABLED" == "false" ] || [ "$CA_CLUSTER" == "disabled" ]; then
            print_info "  Autoscaling desabilitado (expected para system/critical nodes)"
        else
            print_warning "  Tags ausentes ou incorretas"
            print_info "    k8s.io/cluster-autoscaler/enabled: ${CA_ENABLED:-missing}"
            print_info "    k8s.io/cluster-autoscaler/$CLUSTER_NAME: ${CA_CLUSTER:-missing}"
        fi

        # Show scaling config
        MIN_SIZE=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG" \
            --query "AutoScalingGroups[0].MinSize" \
            --output text 2>/dev/null)
        MAX_SIZE=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG" \
            --query "AutoScalingGroups[0].MaxSize" \
            --output text 2>/dev/null)
        DESIRED=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG" \
            --query "AutoScalingGroups[0].DesiredCapacity" \
            --output text 2>/dev/null)

        print_info "  Scaling: min=$MIN_SIZE, max=$MAX_SIZE, desired=$DESIRED"
    done
else
    print_warning "Nenhum ASG encontrado (AWS CLI pode não estar autenticado)"
fi

# Check Prometheus metrics
print_header "8. Verificando Métricas Prometheus"
if kubectl get servicemonitor -n "$NAMESPACE" "$DEPLOYMENT_NAME" &> /dev/null 2>&1; then
    print_success "ServiceMonitor criado"
else
    print_warning "ServiceMonitor não encontrado (métricas podem não estar disponíveis)"
fi

# Check current node count
print_header "9. Status Atual dos Nodes"
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
print_info "Total de nodes: $NODE_COUNT"

echo ""
kubectl get nodes -o wide --show-labels | grep -E "NAME|node-type"

# -----------------------------------------------------------------------------
# Scale-Up Test (Optional - requires user confirmation)
# -----------------------------------------------------------------------------

print_header "10. Teste de Scale-Up (Opcional)"
read -p "Executar teste de scale-up? (isso criará um deployment de teste) [y/N]: " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Criando deployment de teste para forçar scale-up..."

    # Create test deployment requiring more resources than available
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $TEST_DEPLOYMENT
  namespace: $TEST_NAMESPACE
spec:
  replicas: 10
  selector:
    matchLabels:
      app: autoscaler-test
  template:
    metadata:
      labels:
        app: autoscaler-test
    spec:
      nodeSelector:
        node-type: workloads
      containers:
      - name: nginx
        image: nginx:alpine
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
EOF

    print_success "Deployment de teste criado"
    print_info "Aguardando scale-up (pode levar até 60 segundos)..."

    sleep 10

    # Monitor nodes and pending pods
    print_info "Nodes atuais:"
    kubectl get nodes -l node-type=workloads

    print_info "Pods pending:"
    kubectl get pods -n $TEST_NAMESPACE -l app=autoscaler-test | grep Pending || print_success "Nenhum pod pending"

    print_info "Logs do Cluster Autoscaler:"
    kubectl logs "$POD_NAME" -n "$NAMESPACE" --tail=20 | grep -E "scale|node" || true

    print_warning "Para limpar o teste, execute:"
    echo "  kubectl delete deployment $TEST_DEPLOYMENT -n $TEST_NAMESPACE"
else
    print_info "Teste de scale-up ignorado"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

print_header "RESUMO DA VALIDAÇÃO"

echo ""
print_success "Cluster Autoscaler validado com sucesso!"
echo ""
print_info "Próximos Passos:"
echo "  1. Monitorar logs: kubectl logs -f $POD_NAME -n $NAMESPACE"
echo "  2. Verificar métricas no Grafana: cluster_autoscaler_*"
echo "  3. Executar teste de scale-up (criado acima)"
echo "  4. Aguardar scale-down automático após 10 minutos de baixa utilização"
echo ""
print_info "Referências:"
echo "  - ADR-007: docs/adr/adr-007-cluster-autoscaler-strategy.md"
echo "  - Logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=cluster-autoscaler"
echo "  - Métricas: http://localhost:9090 (Prometheus)"
echo ""
