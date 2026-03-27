#!/bin/bash
# =============================================================================
# provision-rabbitmq.sh — Provisiona RabbitMQ vhost, user, exchanges (idempotente)
# =============================================================================
# Descricao: Suporta dois modos:
#   - shared:    Usa o RabbitMQ compartilhado do cluster. Cria vhost + user
#                dedicado por app (isolamento), armazena no Vault, cria ExternalSecret.
#   - dedicated: (futuro) Provisiona instancia RabbitMQ dedicada via Operator.
#
# Modo shared (default):
#   1. Le admin credentials do secret do RabbitMQ Operator
#   2. Cria vhost dedicado para a app via rabbitmqadmin Job
#   3. Cria user dedicado com permissoes no vhost
#   4. Gera connection string AMQP completa
#   5. Armazena tudo no Vault → ExternalSecret → K8s Secret
#
# Uso:       ./provision-rabbitmq.sh --app <name> --namespace <ns> --domain <d> --env <e> [opcoes]
# Deps:      kubectl, vault (CLI), openssl
# Ref:       ADR-062 (RabbitMQ Governance), RabbitMQ Operator 2.19.0
# Idempotente: SIM — verifica secret/ExternalSecret existente antes de provisionar
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
# Defaults — infraestrutura compartilhada
# O RabbitMQ roda em staging-data-infrastructure gerenciado pelo RabbitMQ Operator.
# O secret do admin user e criado automaticamente pelo Operator com o padrao:
#   <cluster-name>-default-user  (ns: staging-data-infrastructure)
# -----------------------------------------------------------------------------
SHARED_RABBITMQ_NAMESPACE="staging-data-infrastructure"
SHARED_RABBITMQ_ADMIN_SECRET="k8s-platform-prod-rabbitmq-default-user"
SHARED_RABBITMQ_HOST="k8s-platform-prod-rabbitmq.staging-data-infrastructure.svc.cluster.local"
SHARED_RABBITMQ_PORT="5672"
SHARED_RABBITMQ_MGMT_PORT="15672"

# Prod overrides
SHARED_RABBITMQ_NAMESPACE_PROD="prod-data-rabbitmq"
SHARED_RABBITMQ_HOST_PROD="k8s-platform-prod-rabbitmq.prod-data-rabbitmq.svc.cluster.local"

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
  --admin-secret   Override do secret admin (default: auto-detect do Operator)
  --admin-ns       Override do namespace do admin secret (default: staging-data-infrastructure)
  --image          Imagem RabbitMQ para o Job (default: rabbitmq:3.13-management-alpine)
  --dlq-ttl        TTL da DLQ em ms (default: 2592000000 = 30 dias)
  --vhosts         Lista de vhosts adicionais separados por virgula
  --replicas       Numero de replicas (default: 1, usado apenas em modo dedicated)
  --mode           shared|dedicated (default: shared)
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
    ADMIN_SECRET_OVERRIDE=""
    ADMIN_NS_OVERRIDE=""
    RABBITMQ_IMAGE="rabbitmq:3.13-management-alpine"
    DLQ_TTL="2592000000"
    EXTRA_VHOSTS=""
    MODE="shared"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --app)          APP_NAME="$2"; shift 2 ;;
            --namespace)    NAMESPACE="$2"; shift 2 ;;
            --domain)       DOMAIN="$2"; shift 2 ;;
            --env)          ENV="$2"; shift 2 ;;
            --host)         RABBITMQ_HOST_OVERRIDE="$2"; shift 2 ;;
            --admin-secret) ADMIN_SECRET_OVERRIDE="$2"; shift 2 ;;
            --admin-ns)     ADMIN_NS_OVERRIDE="$2"; shift 2 ;;
            --image)        RABBITMQ_IMAGE="$2"; shift 2 ;;
            --dlq-ttl)      DLQ_TTL="$2"; shift 2 ;;
            --vhosts)       EXTRA_VHOSTS="$2"; shift 2 ;;
            --replicas)     REPLICAS="$2"; shift 2 ;;
            --mode)         MODE="$2"; shift 2 ;;
            --dry-run)      DRY_RUN=true; shift ;;
            --help|-h)      usage ;;
            *) log_error "Opcao desconhecida: $1"; usage ;;
        esac
    done

    validate_required_args APP_NAME NAMESPACE DOMAIN ENV || { usage; }
}

# -----------------------------------------------------------------------------
# resolve_shared_endpoints — resolve host, admin secret e namespace por env
# -----------------------------------------------------------------------------
resolve_shared_endpoints() {
    if [[ "$ENV" == "prod" ]]; then
        RABBITMQ_HOST="${RABBITMQ_HOST_OVERRIDE:-$SHARED_RABBITMQ_HOST_PROD}"
        ADMIN_NS="${ADMIN_NS_OVERRIDE:-$SHARED_RABBITMQ_NAMESPACE_PROD}"
    else
        RABBITMQ_HOST="${RABBITMQ_HOST_OVERRIDE:-$SHARED_RABBITMQ_HOST}"
        ADMIN_NS="${ADMIN_NS_OVERRIDE:-$SHARED_RABBITMQ_NAMESPACE}"
    fi
    ADMIN_SECRET_NAME="${ADMIN_SECRET_OVERRIDE:-$SHARED_RABBITMQ_ADMIN_SECRET}"
    RABBITMQ_PORT="$SHARED_RABBITMQ_PORT"
    RABBITMQ_MGMT_PORT="$SHARED_RABBITMQ_MGMT_PORT"
}

# -----------------------------------------------------------------------------
# provision_shared — RabbitMQ compartilhado com vhost + user dedicado por app
# Fluxo: admin creds → Job (vhost+user+exchanges) → Vault → ExternalSecret
# -----------------------------------------------------------------------------
provision_shared() {
    resolve_shared_endpoints

    VHOST="${DOMAIN}.${APP_NAME}"
    RABBITMQ_USER="${APP_NAME}-user"
    SECRET_NAME="${APP_NAME}-rabbitmq-credentials"
    VAULT_PATH="secret/${ENV}/${DOMAIN}/${APP_NAME}/rabbitmq"

    log_info "============================================="
    log_info "Modo: SHARED (RabbitMQ compartilhado)"
    log_info "Env: $ENV | Host: $RABBITMQ_HOST"
    log_info "VHost: $VHOST | User: $RABBITMQ_USER"
    log_info "Admin Secret: $ADMIN_SECRET_NAME (ns: $ADMIN_NS)"
    log_info "Vault: $VAULT_PATH"
    log_info "Image: $RABBITMQ_IMAGE | DLQ TTL: ${DLQ_TTL}ms"
    [[ -n "$EXTRA_VHOSTS" ]] && log_info "Vhosts adicionais: $EXTRA_VHOSTS"
    log_info "============================================="

    # Check-before-create: se ExternalSecret ja existe e Synced, pular
    if resource_exists externalsecret "${APP_NAME}-rabbitmq-external" "$NAMESPACE"; then
        local es_status
        es_status=$(kubectl get externalsecret "${APP_NAME}-rabbitmq-external" -n "$NAMESPACE" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || echo "Unknown")
        if [[ "$es_status" == "SecretSynced" ]]; then
            log_warn "ExternalSecret '${APP_NAME}-rabbitmq-external' ja existe e Synced — pulando"
            exit 0
        fi
        log_info "ExternalSecret existe mas status=$es_status — re-provisionando"
    fi

    # Fallback: check secret diretamente
    if resource_exists secret "$SECRET_NAME" "$NAMESPACE"; then
        log_warn "Secret '$SECRET_NAME' ja existe — pulando provisioning"
        log_info "Para re-provisionar, delete: kubectl delete secret $SECRET_NAME -n $NAMESPACE"
        exit 0
    fi

    # Validar que o admin secret existe
    if ! resource_exists secret "$ADMIN_SECRET_NAME" "$ADMIN_NS"; then
        log_error "Admin secret '$ADMIN_SECRET_NAME' NAO encontrado em '$ADMIN_NS'"
        log_error "O RabbitMQ Operator cria este secret automaticamente."
        log_error "Verifique: kubectl get secret -n $ADMIN_NS | grep rabbitmq"
        exit 1
    fi
    log_success "Admin secret '$ADMIN_SECRET_NAME' encontrado em '$ADMIN_NS'"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Criaria vhost, user, exchanges, Secret, ExternalSecret"
        log_info "[DRY-RUN] Host: $RABBITMQ_HOST | VHost: $VHOST"
        log_info "[DRY-RUN] Vault path: $VAULT_PATH"
        log_info "[DRY-RUN] Admin secret: ${ADMIN_NS}/${ADMIN_SECRET_NAME}"
        [[ -n "$EXTRA_VHOSTS" ]] && log_info "[DRY-RUN] Vhosts adicionais: $EXTRA_VHOSTS"
        exit 0
    fi

    # Gerar password dedicado para a app
    RABBITMQ_PASSWORD=$(generate_password 25)

    # Copiar admin secret para o namespace da app (Job precisa acessar)
    # Idempotente: dry-run + apply
    log_info "Copiando admin credentials para namespace $NAMESPACE..."
    local admin_user admin_pass
    admin_user=$(kubectl get secret "$ADMIN_SECRET_NAME" -n "$ADMIN_NS" \
        -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
    admin_pass=$(kubectl get secret "$ADMIN_SECRET_NAME" -n "$ADMIN_NS" \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

    if [[ -z "$admin_user" || -z "$admin_pass" ]]; then
        log_error "Falha ao ler admin credentials de ${ADMIN_NS}/${ADMIN_SECRET_NAME}"
        exit 1
    fi

    local local_admin_secret="rabbitmq-admin-temp-${APP_NAME}"
    create_secret_idempotent "$local_admin_secret" "$NAMESPACE" \
        --from-literal=username="$admin_user" \
        --from-literal=password="$admin_pass"

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

    # Cleanup de Job anterior (pode ter falhado em run anterior)
    kubectl delete job "${APP_NAME}-rabbitmq-setup" -n "$NAMESPACE" --ignore-not-found &>/dev/null

    # Setup via Job — cria vhost + user + exchanges + DLQ
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
    app.kubernetes.io/part-of: ${DOMAIN}
    platform.io/env: ${ENV}
    managed-by: platform-provisioner
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

          echo "Aguardando RabbitMQ em \${RABBITMQ_HOST}:\${RABBITMQ_MGMT_PORT}..."
          until \${MGMT} list vhosts &>/dev/null; do echo "Aguardando RabbitMQ..."; sleep 5; done
          echo "RabbitMQ acessivel."

          echo "Criando vhost: \${VHOST}"
          \${MGMT} declare vhost name="\${VHOST}"

          echo "Criando user: \${RABBITMQ_USER}"
          \${MGMT} declare user name="\${RABBITMQ_USER}" password="\${RABBITMQ_PASSWORD}" tags=""

          echo "Setando permissoes em \${VHOST} para \${RABBITMQ_USER}"
          \${MGMT} declare permission vhost="\${VHOST}" user="\${RABBITMQ_USER}" configure=".*" write=".*" read=".*"

          echo "Criando exchanges padrao..."
          \${MGMT} declare exchange --vhost="\${VHOST}" name="\${DOMAIN}.\${APP_NAME}.events" type=topic durable=true
          \${MGMT} declare exchange --vhost="\${VHOST}" name="\${DOMAIN}.\${APP_NAME}.tasks" type=direct durable=true
          \${MGMT} declare exchange --vhost="\${VHOST}" name="\${DOMAIN}.\${APP_NAME}.dlx" type=topic durable=true

          echo "Criando DLQ com TTL ${DLQ_TTL}ms..."
          \${MGMT} declare queue --vhost="\${VHOST}" name="\${DOMAIN}.\${APP_NAME}.dlq" durable=true arguments="{\"x-message-ttl\":\${DLQ_TTL}}"
          \${MGMT} declare binding --vhost="\${VHOST}" source="\${DOMAIN}.\${APP_NAME}.dlx" destination="\${DOMAIN}.\${APP_NAME}.dlq" routing_key="#"

${EXTRA_VHOSTS_SCRIPT}

          echo "RabbitMQ setup completo para \${APP_NAME}."
        env:
        - { name: RABBITMQ_HOST, value: "${RABBITMQ_HOST}" }
        - { name: RABBITMQ_MGMT_PORT, value: "${RABBITMQ_MGMT_PORT}" }
        - { name: ADMIN_USER, valueFrom: { secretKeyRef: { name: "${local_admin_secret}", key: username } } }
        - { name: ADMIN_PASSWORD, valueFrom: { secretKeyRef: { name: "${local_admin_secret}", key: password } } }
        - { name: VHOST, value: "${VHOST}" }
        - { name: DOMAIN, value: "${DOMAIN}" }
        - { name: APP_NAME, value: "${APP_NAME}" }
        - { name: RABBITMQ_USER, value: "${RABBITMQ_USER}" }
        - { name: RABBITMQ_PASSWORD, value: "${RABBITMQ_PASSWORD}" }
        - { name: DLQ_TTL, value: "${DLQ_TTL}" }
EOF

    log_info "Aguardando Job concluir (timeout: 300s)..."
    kubectl wait --for=condition=complete --timeout=300s "job/${APP_NAME}-rabbitmq-setup" -n "$NAMESPACE"
    log_success "VHost, User e Exchanges criados"

    # Limpar admin temp secret
    kubectl delete secret "$local_admin_secret" -n "$NAMESPACE" --ignore-not-found &>/dev/null
    log_info "Admin temp secret removido"

    # Secret da app
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

    # Armazenar no Vault
    log_info "Armazenando credenciais no Vault..."

    vault_kv_put_safe "$VAULT_PATH" \
        host="$RABBITMQ_HOST" port="$RABBITMQ_PORT" vhost="$VHOST" \
        username="$RABBITMQ_USER" password="$RABBITMQ_PASSWORD" \
        connection-string="amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@${RABBITMQ_HOST}:${RABBITMQ_PORT}/${VHOST}" \
        exchange-events="${DOMAIN}.${APP_NAME}.events" \
        exchange-tasks="${DOMAIN}.${APP_NAME}.tasks" \
        exchange-dlx="${DOMAIN}.${APP_NAME}.dlx" \
        mode="shared" \
        environment="$ENV" domain="$DOMAIN" \
        created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # ExternalSecret — Vault → K8s Secret (futura source of truth)
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
    app.kubernetes.io/part-of: ${DOMAIN}
    platform.io/env: ${ENV}
    managed-by: platform-provisioner
    rabbitmq-mode: shared
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

    log_success "ExternalSecret criado: ${APP_NAME}-rabbitmq-external"
    log_success "RabbitMQ SHARED provisionado para $APP_NAME (env=$ENV, domain=$DOMAIN)"
    log_info "VHost: $VHOST | User: $RABBITMQ_USER | Host: $RABBITMQ_HOST"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    log_info "Provisionando RabbitMQ para $APP_NAME | Mode: $MODE | Env: $ENV | Domain: $DOMAIN"

    case "$MODE" in
        shared)
            provision_shared
            ;;
        dedicated)
            log_error "Modo 'dedicated' ainda nao implementado — use 'shared'"
            exit 1
            ;;
        *)
            log_error "Modo invalido: '$MODE' (esperado: shared|dedicated)"
            exit 1
            ;;
    esac
}

main "$@"
