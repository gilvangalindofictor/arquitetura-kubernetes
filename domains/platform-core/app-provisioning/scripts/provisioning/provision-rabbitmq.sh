#!/bin/bash
# =============================================================================
# provision-rabbitmq.sh — Provisiona RabbitMQ vhost, user, exchanges (idempotente)
# =============================================================================
# Descricao: Cria vhost, user, exchanges padrao (events/tasks/dlx), DLQ,
#            Secret, ExternalSecret e armazena no Vault.
# Uso:       ./provision-rabbitmq.sh --app <name> --namespace <ns> --domain <d> --env <e> [opcoes]
# Deps:      kubectl, vault (CLI), openssl
# Ref:       ADR-062 (RabbitMQ Governance), RabbitMQ Operator 2.19.0
# Idempotente: SIM — verifica secret existente antes de provisionar
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="RABBITMQ"
source "${SCRIPT_DIR}/../lib/common.sh"

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Ajuda
# -----------------------------------------------------------------------------
usage() {
    cat <<USAGE
Uso: $(basename "$0") --app <name> --namespace <ns> --domain <domain> --env <env> [opcoes]

Parametros obrigatorios:
  --app          Nome da aplicacao
  --namespace    Namespace Kubernetes
  --domain       Dominio de negocio (ex: checkout, payments)
  --env          Ambiente (staging, prod, dev)

Parametros opcionais:
  --host           Override do hostname RabbitMQ (default: convencao por env)
  --admin-secret   Nome do secret com admin credentials (default: rabbitmq-admin-credentials-<env>)
  --image          Imagem RabbitMQ para o Job (default: rabbitmq:3.13-management-alpine)
  --dlq-ttl        TTL da DLQ em ms (default: 2592000000 = 30 dias)
  --vhosts         Lista de vhosts adicionais separados por virgula
  --replicas       Numero de replicas (default: 1)
  --dry-run        Apenas exibir o que seria feito
USAGE
    exit 1
}

# -----------------------------------------------------------------------------
# Parse de parametros
# -----------------------------------------------------------------------------
parse_args() {
    APP_NAME=""
    NAMESPACE=""
    DOMAIN=""
    ENV=""
    REPLICAS=1
    DRY_RUN=false
    RABBITMQ_HOST_OVERRIDE=""
    ADMIN_SECRET=""
    RABBITMQ_IMAGE="rabbitmq:3.13-management-alpine"
    DLQ_TTL="2592000000"
    EXTRA_VHOSTS=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --app)          APP_NAME="$2"; shift 2 ;;
            --namespace)    NAMESPACE="$2"; shift 2 ;;
            --domain)       DOMAIN="$2"; shift 2 ;;
            --env)          ENV="$2"; shift 2 ;;
            --host)         RABBITMQ_HOST_OVERRIDE="$2"; shift 2 ;;
            --admin-secret) ADMIN_SECRET="$2"; shift 2 ;;
            --image)        RABBITMQ_IMAGE="$2"; shift 2 ;;
            --dlq-ttl)      DLQ_TTL="$2"; shift 2 ;;
            --vhosts)       EXTRA_VHOSTS="$2"; shift 2 ;;
            --replicas)     REPLICAS="$2"; shift 2 ;;
            --dry-run)      DRY_RUN=true; shift ;;
            --help|-h)      usage ;;
            *) log_error "Opcao desconhecida: $1"; usage ;;
        esac
    done

    validate_required_args APP_NAME NAMESPACE DOMAIN ENV || { usage; }
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    # Derivar valores — ZERO hardcoded
    VHOST="${DOMAIN}.${APP_NAME}"
    RABBITMQ_USER="${APP_NAME}-user"
    RABBITMQ_HOST="${RABBITMQ_HOST_OVERRIDE:-rabbitmq-shared-cluster.${ENV}-platform-messaging.svc.cluster.local}"
    RABBITMQ_PORT="5672"
    RABBITMQ_MGMT_PORT="15672"
    SECRET_NAME="${APP_NAME}-rabbitmq-credentials"
    ADMIN_SECRET_NAME="${ADMIN_SECRET:-rabbitmq-admin-credentials-${ENV}}"
    VAULT_PATH="secret/${ENV}/${DOMAIN}/${APP_NAME}/rabbitmq"

    log_info "Env: $ENV | Host: $RABBITMQ_HOST"
    log_info "VHost: $VHOST | User: $RABBITMQ_USER | Replicas: $REPLICAS"
    log_info "Admin Secret: $ADMIN_SECRET_NAME | Vault: $VAULT_PATH"
    log_info "Image: $RABBITMQ_IMAGE | DLQ TTL: ${DLQ_TTL}ms"
    [[ -n "$EXTRA_VHOSTS" ]] && log_info "Vhosts adicionais: $EXTRA_VHOSTS"

    # Check-before-create
    if resource_exists secret "$SECRET_NAME" "$NAMESPACE"; then
        log_warn "Secret '$SECRET_NAME' ja existe — pulando provisioning"
        exit 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Criaria vhost, user, exchanges, Secret, ExternalSecret"
        log_info "[DRY-RUN] Host: $RABBITMQ_HOST"
        log_info "[DRY-RUN] Vault path: $VAULT_PATH"
        log_info "[DRY-RUN] Admin secret: $ADMIN_SECRET_NAME"
        [[ -n "$EXTRA_VHOSTS" ]] && log_info "[DRY-RUN] Vhosts adicionais: $EXTRA_VHOSTS"
        exit 0
    fi

    # Gerar password
    RABBITMQ_PASSWORD=$(generate_password 25)

    # Montar bloco de vhosts adicionais para o Job
    EXTRA_VHOSTS_SCRIPT=""
    if [[ -n "$EXTRA_VHOSTS" ]]; then
        IFS=',' read -ra VHOST_LIST <<< "$EXTRA_VHOSTS"
        for vh in "${VHOST_LIST[@]}"; do
            vh=$(echo "$vh" | xargs)
            EXTRA_VHOSTS_SCRIPT+="
          \${MGMT} declare vhost name=\"${vh}\"
          \${MGMT} declare permission vhost=\"${vh}\" user=\"\${RABBITMQ_USER}\" configure=\".*\" write=\".*\" read=\".*\""
        done
    fi

    # Setup via Job
    log_info "Criando VHost, User e Exchanges via Job..."

    kubectl_apply_idempotent <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${APP_NAME}-rabbitmq-setup
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: messaging
    managed-by: platform-provisioner
    environment: ${ENV}
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: rabbitmq-admin
        image: ${RABBITMQ_IMAGE}
        command: ["sh", "-c"]
        args:
        - |
          set -e
          MGMT="rabbitmqadmin -H \${RABBITMQ_HOST} -P \${RABBITMQ_MGMT_PORT} -u \${ADMIN_USER} -p \${ADMIN_PASSWORD}"

          until \${MGMT} list vhosts &>/dev/null; do echo "Aguardando RabbitMQ..."; sleep 5; done

          \${MGMT} declare vhost name="\${VHOST}"
          \${MGMT} declare user name="\${RABBITMQ_USER}" password="\${RABBITMQ_PASSWORD}" tags=""
          \${MGMT} declare permission vhost="\${VHOST}" user="\${RABBITMQ_USER}" configure=".*" write=".*" read=".*"

          \${MGMT} declare exchange --vhost="\${VHOST}" name="\${DOMAIN}.\${APP_NAME}.events" type=topic durable=true
          \${MGMT} declare exchange --vhost="\${VHOST}" name="\${DOMAIN}.\${APP_NAME}.tasks" type=direct durable=true
          \${MGMT} declare exchange --vhost="\${VHOST}" name="\${DOMAIN}.\${APP_NAME}.dlx" type=topic durable=true

          \${MGMT} declare queue --vhost="\${VHOST}" name="\${DOMAIN}.\${APP_NAME}.dlq" durable=true arguments="{\"x-message-ttl\":\${DLQ_TTL}}"
          \${MGMT} declare binding --vhost="\${VHOST}" source="\${DOMAIN}.\${APP_NAME}.dlx" destination="\${DOMAIN}.\${APP_NAME}.dlq" routing_key="#"

${EXTRA_VHOSTS_SCRIPT}

          echo "RabbitMQ setup completo."
        env:
        - { name: RABBITMQ_HOST, value: "${RABBITMQ_HOST}" }
        - { name: RABBITMQ_MGMT_PORT, value: "${RABBITMQ_MGMT_PORT}" }
        - { name: ADMIN_USER, valueFrom: { secretKeyRef: { name: "${ADMIN_SECRET_NAME}", key: username } } }
        - { name: ADMIN_PASSWORD, valueFrom: { secretKeyRef: { name: "${ADMIN_SECRET_NAME}", key: password } } }
        - { name: VHOST, value: "${VHOST}" }
        - { name: DOMAIN, value: "${DOMAIN}" }
        - { name: APP_NAME, value: "${APP_NAME}" }
        - { name: RABBITMQ_USER, value: "${RABBITMQ_USER}" }
        - { name: RABBITMQ_PASSWORD, value: "${RABBITMQ_PASSWORD}" }
        - { name: DLQ_TTL, value: "${DLQ_TTL}" }
EOF

    log_info "Aguardando Job..."
    kubectl wait --for=condition=complete --timeout=300s "job/${APP_NAME}-rabbitmq-setup" -n "$NAMESPACE"
    log_success "VHost, User e Exchanges criados"

    # Secret
    log_info "Criando Secret..."

    create_secret_idempotent "$SECRET_NAME" "$NAMESPACE" \
        --from-literal=host="$RABBITMQ_HOST" \
        --from-literal=port="$RABBITMQ_PORT" \
        --from-literal=vhost="$VHOST" \
        --from-literal=username="$RABBITMQ_USER" \
        --from-literal=password="$RABBITMQ_PASSWORD" \
        --from-literal=connection-string="amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@${RABBITMQ_HOST}:${RABBITMQ_PORT}/${VHOST}" \
        --from-literal=exchange-events="${DOMAIN}.${APP_NAME}.events" \
        --from-literal=exchange-tasks="${DOMAIN}.${APP_NAME}.tasks" \
        --from-literal=exchange-dlx="${DOMAIN}.${APP_NAME}.dlx"

    label_secret "$SECRET_NAME" "$NAMESPACE" "$APP_NAME" "messaging" "$ENV" "$DOMAIN"

    log_success "Secret criado"

    # ExternalSecret
    log_info "Criando ExternalSecret (Vault path: $VAULT_PATH)..."

    kubectl_apply_idempotent <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${APP_NAME}-rabbitmq-external
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: messaging
    managed-by: platform-provisioner
    environment: ${ENV}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: ${SECRET_NAME}
    creationPolicy: Owner
  data:
  - secretKey: host
    remoteRef: { key: "${VAULT_PATH}", property: "host" }
  - secretKey: port
    remoteRef: { key: "${VAULT_PATH}", property: "port" }
  - secretKey: vhost
    remoteRef: { key: "${VAULT_PATH}", property: "vhost" }
  - secretKey: username
    remoteRef: { key: "${VAULT_PATH}", property: "username" }
  - secretKey: password
    remoteRef: { key: "${VAULT_PATH}", property: "password" }
  - secretKey: connection-string
    remoteRef: { key: "${VAULT_PATH}", property: "connection-string" }
EOF

    log_success "ExternalSecret criado"

    # Vault
    vault_kv_put_safe "$VAULT_PATH" \
        host="$RABBITMQ_HOST" port="$RABBITMQ_PORT" vhost="$VHOST" \
        username="$RABBITMQ_USER" password="$RABBITMQ_PASSWORD" \
        connection-string="amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@${RABBITMQ_HOST}:${RABBITMQ_PORT}/${VHOST}" \
        environment="$ENV" domain="$DOMAIN" \
        created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    log_success "RabbitMQ totalmente provisionado para $APP_NAME (env=$ENV, domain=$DOMAIN)"
}

main "$@"
