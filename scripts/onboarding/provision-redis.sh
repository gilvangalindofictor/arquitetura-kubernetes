#!/bin/bash
# Provisiona Redis Instance usando Redis Operator
# Referência: ADR-061 (Redis Governance Standards)
# Uso: ./provision-redis.sh <produto> <namespace> <env>

set -euo pipefail

PRODUTO="$1"
NAMESPACE="$2"
ENV="$3"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[REDIS]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[REDIS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[REDIS]${NC} $1"
}

# Validações
log_info "Validando nome do produto..."

# ADR-061: Redis CR naming convention
if ! [[ "$PRODUTO" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
    echo "❌ Nome do produto inválido para Redis: '$PRODUTO'"
    echo "Formato esperado: ^[a-z][a-z0-9-]{0,62}$ (kebab-case)"
    exit 1
fi

REDIS_CR_NAME="${PRODUTO}-redis"

log_info "Redis CR: $REDIS_CR_NAME"
log_info "Namespace: $NAMESPACE"
log_info "Ambiente: $ENV"

# Determinar configuração baseada no ambiente (ADR-061)
case "$ENV" in
    dev)
        REPLICAS=1
        MEMORY="256Mi"
        CPU_REQUEST="100m"
        CPU_LIMIT="500m"
        EVICTION_POLICY="allkeys-lru"
        PERSISTENCE="no"
        ;;
    staging)
        REPLICAS=2
        MEMORY="512Mi"
        CPU_REQUEST="200m"
        CPU_LIMIT="1000m"
        EVICTION_POLICY="allkeys-lru"
        PERSISTENCE="yes"
        ;;
    prod)
        REPLICAS=3
        MEMORY="2Gi"
        CPU_REQUEST="500m"
        CPU_LIMIT="2000m"
        EVICTION_POLICY="allkeys-lru"
        PERSISTENCE="yes"
        ;;
    *)
        echo "❌ Ambiente inválido: $ENV"
        exit 1
        ;;
esac

log_info "Configuração para ambiente $ENV:"
log_info "  - Replicas: $REPLICAS"
log_info "  - Memory: $MEMORY"
log_info "  - CPU: ${CPU_REQUEST}/${CPU_LIMIT}"
log_info "  - Eviction Policy: $EVICTION_POLICY"
log_info "  - Persistence: $PERSISTENCE"

# ====================
# Gerar Password Seguro
# ====================
log_info "Gerando password seguro..."

REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# ====================
# Criar Secret com Credentials
# ====================
log_info "Criando Secret com credenciais..."

SECRET_NAME="${PRODUTO}-redis-credentials"

kubectl create secret generic "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    --from-literal=password="$REDIS_PASSWORD" \
    --from-literal=host="${REDIS_CR_NAME}.${NAMESPACE}.svc.cluster.local" \
    --from-literal=port="6379" \
    --from-literal=connection-string="redis://:${REDIS_PASSWORD}@${REDIS_CR_NAME}.${NAMESPACE}.svc.cluster.local:6379/0" \
    --dry-run=client -o yaml | kubectl apply -f -

# Labels obrigatórias (ADR-048)
kubectl label secret "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    app.kubernetes.io/name="$PRODUTO" \
    app.kubernetes.io/component="cache" \
    app.kubernetes.io/managed-by="governance-onboarding" \
    database-type="redis" \
    --overwrite

log_success "Secret '$SECRET_NAME' criado"

# ====================
# Criar Redis CR (Custom Resource)
# ====================
log_info "Criando Redis Custom Resource..."

# Configuração de persistence
if [ "$PERSISTENCE" = "yes" ]; then
    PERSISTENCE_CONFIG=$(cat <<EOF
  storage:
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
        storageClassName: gp3
  redisExporter:
    enabled: true
    image: oliver006/redis_exporter:v1.55.0
EOF
)
else
    PERSISTENCE_CONFIG=""
fi

# Criar Redis CR
kubectl apply -f - <<EOF
apiVersion: redis.redis.opstreelabs.in/v1beta2
kind: Redis
metadata:
  name: ${REDIS_CR_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${PRODUTO}
    app.kubernetes.io/component: cache
    app.kubernetes.io/part-of: ${PRODUTO}
    app.kubernetes.io/managed-by: redis-operator
    domain: $(kubectl get namespace ${NAMESPACE} -o jsonpath='{.metadata.labels.domain}')
    environment: ${ENV}
spec:
  kubernetesConfig:
    image: redis:7.2-alpine
    imagePullPolicy: IfNotPresent
  redisConfig:
    additionalRedisConfig: |
      # ADR-061: Redis Governance Standards
      maxmemory-policy ${EVICTION_POLICY}
      timeout 300
      tcp-keepalive 60
      slowlog-log-slower-than 10000
      slowlog-max-len 128

      # Security
      requirepass ${REDIS_PASSWORD}

      # Persistence (se habilitado)
$(if [ "$PERSISTENCE" = "yes" ]; then
echo "      save 900 1"
echo "      save 300 10"
echo "      save 60 10000"
echo "      appendonly yes"
echo "      appendfsync everysec"
fi)
  resources:
    requests:
      cpu: ${CPU_REQUEST}
      memory: ${MEMORY}
    limits:
      cpu: ${CPU_LIMIT}
      memory: ${MEMORY}
${PERSISTENCE_CONFIG}
  securityContext:
    runAsUser: 1000
    fsGroup: 1000
EOF

log_success "Redis CR '${REDIS_CR_NAME}' criado"

# ====================
# Aguardar Redis ficar ready
# ====================
log_info "Aguardando Redis ficar ready..."

# Aguardar até 5 minutos
for i in {1..30}; do
    if kubectl get redis "${REDIS_CR_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.state}' 2>/dev/null | grep -q "ready"; then
        log_success "Redis está ready!"
        break
    fi

    if [ $i -eq 30 ]; then
        log_warning "Timeout aguardando Redis. Verifique: kubectl get redis ${REDIS_CR_NAME} -n ${NAMESPACE}"
        break
    fi

    echo -n "."
    sleep 10
done
echo ""

# ====================
# Criar ConfigMap com Metadata
# ====================
log_info "Criando ConfigMap com metadata..."

kubectl create configmap "${PRODUTO}-redis-config" \
    --namespace="$NAMESPACE" \
    --from-literal=host="${REDIS_CR_NAME}.${NAMESPACE}.svc.cluster.local" \
    --from-literal=port="6379" \
    --from-literal=database="0" \
    --from-literal=eviction-policy="$EVICTION_POLICY" \
    --from-literal=max-connections="1000" \
    --from-literal=key-prefix="${PRODUTO}:" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap "${PRODUTO}-redis-config" \
    --namespace="$NAMESPACE" \
    app.kubernetes.io/name="$PRODUTO" \
    app.kubernetes.io/component="cache-config" \
    --overwrite

log_success "ConfigMap '${PRODUTO}-redis-config' criado"

# ====================
# Criar ServiceMonitor para Prometheus
# ====================
if [ "$ENV" != "dev" ]; then
    log_info "Criando ServiceMonitor para Prometheus..."

    kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ${REDIS_CR_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${PRODUTO}
    app.kubernetes.io/component: cache
spec:
  selector:
    matchLabels:
      app: ${REDIS_CR_NAME}
  endpoints:
  - port: redis-exporter
    interval: 30s
    path: /metrics
EOF

    log_success "ServiceMonitor criado"
fi

# ====================
# Armazenar credenciais no Vault
# ====================
log_info "Armazenando credenciais no Vault..."

vault kv put secret/database/${PRODUTO}/redis \
    host="${REDIS_CR_NAME}.${NAMESPACE}.svc.cluster.local" \
    port="6379" \
    password="${REDIS_PASSWORD}" \
    connection-string="redis://:${REDIS_PASSWORD}@${REDIS_CR_NAME}.${NAMESPACE}.svc.cluster.local:6379/0" \
    created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    rotation-schedule="180d" \
    eviction-policy="${EVICTION_POLICY}"

log_success "Credenciais armazenadas no Vault (path: secret/database/${PRODUTO}/redis)"

# ====================
# Criar ExternalSecret para Vault
# ====================
log_info "Criando ExternalSecret para sincronização com Vault..."

kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${PRODUTO}-redis-external
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${PRODUTO}
    app.kubernetes.io/component: cache
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: ${PRODUTO}-redis-credentials
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: database/${PRODUTO}/redis
      property: password
  - secretKey: host
    remoteRef:
      key: database/${PRODUTO}/redis
      property: host
  - secretKey: port
    remoteRef:
      key: database/${PRODUTO}/redis
      property: port
  - secretKey: connection-string
    remoteRef:
      key: database/${PRODUTO}/redis
      property: connection-string
EOF

log_success "ExternalSecret criado"

# ====================
# Sumário
# ====================
echo ""
log_success "========================================="
log_success "Redis Provisionado!"
log_success "========================================="
echo ""
log_info "Redis CR: $REDIS_CR_NAME"
log_info "Host: ${REDIS_CR_NAME}.${NAMESPACE}.svc.cluster.local:6379"
log_info "Secret: $SECRET_NAME (namespace: $NAMESPACE)"
log_info "Vault Path: secret/database/${PRODUTO}/redis"
log_info "Replicas: $REPLICAS"
log_info "Memory: $MEMORY"
log_info "Eviction Policy: $EVICTION_POLICY"
log_info "Persistence: $PERSISTENCE"
echo ""
log_info "Key Naming Convention (ADR-061):"
log_info "  {domain}:{produto}:{resource}:{id}"
log_info "  Exemplo: data:${PRODUTO}:session:user-123"
echo ""
log_info "Uso no Deployment:"
echo "  env:"
echo "  - name: REDIS_URL"
echo "    valueFrom:"
echo "      secretKeyRef:"
echo "        name: $SECRET_NAME"
echo "        key: connection-string"
echo "  - name: REDIS_PASSWORD"
echo "    valueFrom:"
echo "      secretKeyRef:"
echo "        name: $SECRET_NAME"
echo "        key: password"
echo ""
log_info "Monitoramento:"
log_info "  kubectl logs -n ${NAMESPACE} -l app=${REDIS_CR_NAME}"
log_info "  kubectl get redis ${REDIS_CR_NAME} -n ${NAMESPACE}"
echo ""
log_success "========================================="
