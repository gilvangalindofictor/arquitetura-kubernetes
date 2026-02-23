#!/bin/bash
# Provisiona RabbitMQ Resources (Virtual Host, Users, Exchanges, Queues)
# Referência: ADR-062 (RabbitMQ Governance Standards)
# Uso: ./provision-rabbitmq.sh <produto> <namespace> <domain> <env>

set -euo pipefail

PRODUTO="$1"
NAMESPACE="$2"
DOMAIN="$3"
ENV="$4"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[RABBITMQ]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[RABBITMQ]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[RABBITMQ]${NC} $1"
}

# Validações
log_info "Validando parâmetros..."

# ADR-062: Naming conventions
if ! [[ "$PRODUTO" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
    echo "❌ Nome do produto inválido: '$PRODUTO'"
    echo "Formato esperado: ^[a-z][a-z0-9-]{0,62}$ (kebab-case)"
    exit 1
fi

# Virtual Host naming: {domain}.{produto} (ADR-062)
VHOST="${DOMAIN}.${PRODUTO}"

log_info "Virtual Host: $VHOST"
log_info "Namespace: $NAMESPACE"
log_info "Domínio: $DOMAIN"
log_info "Ambiente: $ENV"

# RabbitMQ Shared Cluster endpoint (ADR-062)
RABBITMQ_HOST="rabbitmq-shared-cluster.prod-platform-messaging.svc.cluster.local"
RABBITMQ_PORT="5672"
RABBITMQ_MGMT_PORT="15672"

# ====================
# Gerar Passwords Seguros
# ====================
log_info "Gerando credenciais seguras..."

RABBITMQ_USER="${PRODUTO}-user"
RABBITMQ_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# ====================
# Criar Virtual Host e User no RabbitMQ
# ====================
log_info "Criando Virtual Host e User no RabbitMQ..."

# Obter credenciais admin do RabbitMQ do Secret
ADMIN_USER=$(kubectl get secret rabbitmq-admin-credentials -n prod-platform-messaging -o jsonpath='{.data.username}' | base64 -d)
ADMIN_PASSWORD=$(kubectl get secret rabbitmq-admin-credentials -n prod-platform-messaging -o jsonpath='{.data.password}' | base64 -d)

# Criar Job temporário para configuração via rabbitmqadmin
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${PRODUTO}-rabbitmq-setup
  namespace: ${NAMESPACE}
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: rabbitmq-admin
        image: rabbitmq:3.12-management-alpine
        command:
        - sh
        - -c
        - |
          set -e

          # Aguardar RabbitMQ estar ready
          until rabbitmqadmin -H \${RABBITMQ_HOST} -P \${RABBITMQ_MGMT_PORT} -u \${ADMIN_USER} -p \${ADMIN_PASSWORD} list vhosts; do
            echo "Aguardando RabbitMQ..."
            sleep 5
          done

          # Criar Virtual Host
          rabbitmqadmin -H \${RABBITMQ_HOST} -P \${RABBITMQ_MGMT_PORT} -u \${ADMIN_USER} -p \${ADMIN_PASSWORD} \
            declare vhost name="\${VHOST}"

          # Criar User
          rabbitmqadmin -H \${RABBITMQ_HOST} -P \${RABBITMQ_MGMT_PORT} -u \${ADMIN_USER} -p \${ADMIN_PASSWORD} \
            declare user name="\${RABBITMQ_USER}" password="\${RABBITMQ_PASSWORD}" tags=""

          # Dar permissões ao user no vhost (configure, write, read)
          rabbitmqadmin -H \${RABBITMQ_HOST} -P \${RABBITMQ_MGMT_PORT} -u \${ADMIN_USER} -p \${ADMIN_PASSWORD} \
            declare permission vhost="\${VHOST}" user="\${RABBITMQ_USER}" configure=".*" write=".*" read=".*"

          # Criar Exchanges padrão (ADR-062)
          # 1. Events exchange (topic)
          rabbitmqadmin -H \${RABBITMQ_HOST} -P \${RABBITMQ_MGMT_PORT} -u \${ADMIN_USER} -p \${ADMIN_PASSWORD} \
            declare exchange --vhost="\${VHOST}" name="\${DOMAIN}.\${PRODUTO}.events" type=topic durable=true

          # 2. Tasks exchange (direct)
          rabbitmqadmin -H \${RABBITMQ_HOST} -P \${RABBITMQ_MGMT_PORT} -u \${ADMIN_USER} -p \${ADMIN_PASSWORD} \
            declare exchange --vhost="\${VHOST}" name="\${DOMAIN}.\${PRODUTO}.tasks" type=direct durable=true

          # 3. DLX - Dead Letter Exchange
          rabbitmqadmin -H \${RABBITMQ_HOST} -P \${RABBITMQ_MGMT_PORT} -u \${ADMIN_USER} -p \${ADMIN_PASSWORD} \
            declare exchange --vhost="\${VHOST}" name="\${DOMAIN}.\${PRODUTO}.dlx" type=topic durable=true

          # Criar DLQ - Dead Letter Queue (ADR-062)
          rabbitmqadmin -H \${RABBITMQ_HOST} -P \${RABBITMQ_MGMT_PORT} -u \${ADMIN_USER} -p \${ADMIN_PASSWORD} \
            declare queue --vhost="\${VHOST}" name="\${DOMAIN}.\${PRODUTO}.dlq" durable=true \
            arguments='{"x-message-ttl":2592000000}'

          # Bind DLQ ao DLX
          rabbitmqadmin -H \${RABBITMQ_HOST} -P \${RABBITMQ_MGMT_PORT} -u \${ADMIN_USER} -p \${ADMIN_PASSWORD} \
            declare binding --vhost="\${VHOST}" source="\${DOMAIN}.\${PRODUTO}.dlx" destination="\${DOMAIN}.\${PRODUTO}.dlq" routing_key="#"

          echo "RabbitMQ setup concluído!"
        env:
        - name: RABBITMQ_HOST
          value: "${RABBITMQ_HOST}"
        - name: RABBITMQ_MGMT_PORT
          value: "${RABBITMQ_MGMT_PORT}"
        - name: ADMIN_USER
          value: "${ADMIN_USER}"
        - name: ADMIN_PASSWORD
          value: "${ADMIN_PASSWORD}"
        - name: VHOST
          value: "${VHOST}"
        - name: DOMAIN
          value: "${DOMAIN}"
        - name: PRODUTO
          value: "${PRODUTO}"
        - name: RABBITMQ_USER
          value: "${RABBITMQ_USER}"
        - name: RABBITMQ_PASSWORD
          value: "${RABBITMQ_PASSWORD}"
EOF

log_info "Aguardando Job concluir..."
kubectl wait --for=condition=complete --timeout=300s job/${PRODUTO}-rabbitmq-setup -n ${NAMESPACE}

log_success "Virtual Host, User e Exchanges criados"

# ====================
# Criar Secret no Kubernetes
# ====================
log_info "Criando Secret no Kubernetes..."

SECRET_NAME="${PRODUTO}-rabbitmq-credentials"

kubectl create secret generic "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    --from-literal=host="$RABBITMQ_HOST" \
    --from-literal=port="$RABBITMQ_PORT" \
    --from-literal=management-port="$RABBITMQ_MGMT_PORT" \
    --from-literal=vhost="$VHOST" \
    --from-literal=username="$RABBITMQ_USER" \
    --from-literal=password="$RABBITMQ_PASSWORD" \
    --from-literal=connection-string="amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@${RABBITMQ_HOST}:${RABBITMQ_PORT}/${VHOST}" \
    --from-literal=exchange-events="${DOMAIN}.${PRODUTO}.events" \
    --from-literal=exchange-tasks="${DOMAIN}.${PRODUTO}.tasks" \
    --from-literal=exchange-dlx="${DOMAIN}.${PRODUTO}.dlx" \
    --dry-run=client -o yaml | kubectl apply -f -

# Labels obrigatórias (ADR-048)
kubectl label secret "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    app.kubernetes.io/name="$PRODUTO" \
    app.kubernetes.io/component="messaging" \
    app.kubernetes.io/managed-by="governance-onboarding" \
    messaging-type="rabbitmq" \
    --overwrite

log_success "Secret '$SECRET_NAME' criado"

# ====================
# Criar ConfigMap com Metadata
# ====================
log_info "Criando ConfigMap com metadata..."

kubectl create configmap "${PRODUTO}-rabbitmq-config" \
    --namespace="$NAMESPACE" \
    --from-literal=host="$RABBITMQ_HOST" \
    --from-literal=port="$RABBITMQ_PORT" \
    --from-literal=vhost="$VHOST" \
    --from-literal=exchange-events="${DOMAIN}.${PRODUTO}.events" \
    --from-literal=exchange-tasks="${DOMAIN}.${PRODUTO}.tasks" \
    --from-literal=exchange-dlx="${DOMAIN}.${PRODUTO}.dlx" \
    --from-literal=queue-dlq="${DOMAIN}.${PRODUTO}.dlq" \
    --from-literal=routing-key-pattern="{resource}.{action}" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap "${PRODUTO}-rabbitmq-config" \
    --namespace="$NAMESPACE" \
    app.kubernetes.io/name="$PRODUTO" \
    app.kubernetes.io/component="messaging-config" \
    --overwrite

log_success "ConfigMap '${PRODUTO}-rabbitmq-config' criado"

# ====================
# Armazenar credenciais no Vault
# ====================
log_info "Armazenando credenciais no Vault..."

vault kv put secret/messaging/${PRODUTO}/rabbitmq \
    host="${RABBITMQ_HOST}" \
    port="${RABBITMQ_PORT}" \
    vhost="${VHOST}" \
    username="${RABBITMQ_USER}" \
    password="${RABBITMQ_PASSWORD}" \
    connection-string="amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@${RABBITMQ_HOST}:${RABBITMQ_PORT}/${VHOST}" \
    exchange-events="${DOMAIN}.${PRODUTO}.events" \
    exchange-tasks="${DOMAIN}.${PRODUTO}.tasks" \
    exchange-dlx="${DOMAIN}.${PRODUTO}.dlx" \
    created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    rotation-schedule="180d"

log_success "Credenciais armazenadas no Vault (path: secret/messaging/${PRODUTO}/rabbitmq)"

# ====================
# Criar ExternalSecret para Vault
# ====================
log_info "Criando ExternalSecret para sincronização com Vault..."

kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${PRODUTO}-rabbitmq-external
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${PRODUTO}
    app.kubernetes.io/component: messaging
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: ${PRODUTO}-rabbitmq-credentials
    creationPolicy: Owner
  data:
  - secretKey: host
    remoteRef:
      key: messaging/${PRODUTO}/rabbitmq
      property: host
  - secretKey: port
    remoteRef:
      key: messaging/${PRODUTO}/rabbitmq
      property: port
  - secretKey: vhost
    remoteRef:
      key: messaging/${PRODUTO}/rabbitmq
      property: vhost
  - secretKey: username
    remoteRef:
      key: messaging/${PRODUTO}/rabbitmq
      property: username
  - secretKey: password
    remoteRef:
      key: messaging/${PRODUTO}/rabbitmq
      property: password
  - secretKey: connection-string
    remoteRef:
      key: messaging/${PRODUTO}/rabbitmq
      property: connection-string
EOF

log_success "ExternalSecret criado"

# ====================
# Sumário
# ====================
echo ""
log_success "========================================="
log_success "RabbitMQ Provisionado!"
log_success "========================================="
echo ""
log_info "Virtual Host: $VHOST"
log_info "Host: $RABBITMQ_HOST:$RABBITMQ_PORT"
log_info "User: $RABBITMQ_USER"
log_info "Secret: $SECRET_NAME (namespace: $NAMESPACE)"
log_info "Vault Path: secret/messaging/${PRODUTO}/rabbitmq"
echo ""
log_info "Exchanges criadas (ADR-062):"
log_info "  - ${DOMAIN}.${PRODUTO}.events (topic) - Pub/Sub events"
log_info "  - ${DOMAIN}.${PRODUTO}.tasks (direct) - Work queues"
log_info "  - ${DOMAIN}.${PRODUTO}.dlx (topic) - Dead Letter Exchange"
echo ""
log_info "Queues criadas:"
log_info "  - ${DOMAIN}.${PRODUTO}.dlq (Dead Letter Queue, TTL: 30 dias)"
echo ""
log_info "Naming Conventions (ADR-062):"
log_info "  Exchange: {domain}.{produto}.{type}"
log_info "  Queue:    {domain}.{produto}.{queue-name}"
log_info "  Routing:  {resource}.{action}[.{detail}]"
echo ""
log_info "Uso no Deployment:"
echo "  env:"
echo "  - name: RABBITMQ_URL"
echo "    valueFrom:"
echo "      secretKeyRef:"
echo "        name: $SECRET_NAME"
echo "        key: connection-string"
echo "  - name: RABBITMQ_EXCHANGE_EVENTS"
echo "    valueFrom:"
echo "      configMapKeyRef:"
echo "        name: ${PRODUTO}-rabbitmq-config"
echo "        key: exchange-events"
echo ""
log_info "Exemplo de uso (Python/pika):"
echo "  # Publicar evento"
echo "  channel.basic_publish("
echo "      exchange='${DOMAIN}.${PRODUTO}.events',"
echo "      routing_key='user.created',"
echo "      body=json.dumps(payload)"
echo "  )"
echo ""
log_info "RabbitMQ Management:"
log_info "  URL: http://${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}"
log_info "  VHost: $VHOST"
echo ""
log_success "========================================="
