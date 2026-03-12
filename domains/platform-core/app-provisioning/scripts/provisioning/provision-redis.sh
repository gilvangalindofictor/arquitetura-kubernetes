#!/bin/bash
# =============================================================================
# provision-redis.sh — Provisiona Redis via Redis Operator (idempotente)
# =============================================================================
# Descricao: Cria Redis CR, Secret, ExternalSecret e armazena no Vault.
# Uso:       ./provision-redis.sh --app <name> --namespace <ns> --env <e> --domain <d> --mode <standalone|sentinel> [--storage-class <sc>]
# Deps:      kubectl, vault (CLI), openssl
# Ref:       ADR-061 (Redis Governance), OT Redis Operator v0.23.0
# Idempotente: SIM — verifica existencia de Redis CR antes de criar
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="REDIS"
source "${SCRIPT_DIR}/../lib/common.sh"

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Parse argumentos
# -----------------------------------------------------------------------------
parse_args() {
    APP_NAME="" NAMESPACE="" MODE="standalone" ENV="" DOMAIN="" STORAGE_CLASS="default" DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --app)            APP_NAME="$2"; shift 2 ;;
            --namespace)      NAMESPACE="$2"; shift 2 ;;
            --mode)           MODE="$2"; shift 2 ;;
            --env)            ENV="$2"; shift 2 ;;
            --domain)         DOMAIN="$2"; shift 2 ;;
            --storage-class)  STORAGE_CLASS="$2"; shift 2 ;;
            --dry-run)        DRY_RUN=true; shift ;;
            *) log_error "Opcao desconhecida: $1"; exit 1 ;;
        esac
    done

    validate_required_args APP_NAME NAMESPACE ENV DOMAIN || exit 1
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    REDIS_CR_NAME="${APP_NAME}-redis"
    SECRET_NAME="${APP_NAME}-redis-credentials"
    VAULT_PATH="secret/${ENV}/${DOMAIN}/${APP_NAME}/redis"

    # Recursos por ambiente (ADR-061)
    case "$ENV" in
        staging)  MEMORY="512Mi"; CPU_REQ="200m"; CPU_LIM="1000m"; PERSISTENCE="yes" ;;
        prod)     MEMORY="2Gi";   CPU_REQ="500m"; CPU_LIM="2000m"; PERSISTENCE="yes" ;;
        *)        MEMORY="256Mi"; CPU_REQ="100m"; CPU_LIM="500m";  PERSISTENCE="no"  ;;
    esac

    log_info "Redis CR: $REDIS_CR_NAME | Mode: $MODE | Env: $ENV | Domain: $DOMAIN"
    log_info "Vault path: $VAULT_PATH | StorageClass: $STORAGE_CLASS"

    # Check-before-create
    if resource_exists redis "$REDIS_CR_NAME" "$NAMESPACE"; then
        log_warn "Redis CR '$REDIS_CR_NAME' ja existe — pulando"
        exit 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Criaria Redis CR, Secret e ExternalSecret"
        exit 0
    fi

    # Gerar password
    REDIS_PASSWORD=$(generate_password 25)

    # Secret
    log_info "Criando Secret..."

    create_secret_idempotent "$SECRET_NAME" "$NAMESPACE" \
        --from-literal=password="$REDIS_PASSWORD" \
        --from-literal=host="${REDIS_CR_NAME}.${NAMESPACE}.svc.cluster.local" \
        --from-literal=port="6379" \
        --from-literal=connection-string="redis://:${REDIS_PASSWORD}@${REDIS_CR_NAME}.${NAMESPACE}.svc.cluster.local:6379/0"

    label_secret "$SECRET_NAME" "$NAMESPACE" "$APP_NAME" "cache" "$ENV" "$DOMAIN"

    log_success "Secret criado"

    # Redis CR
    log_info "Criando Redis Custom Resource..."

    STORAGE_SPEC=""
    if [[ "$PERSISTENCE" == "yes" ]]; then
        STORAGE_SPEC="
  storage:
    volumeClaimTemplate:
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 5Gi
        storageClassName: ${STORAGE_CLASS}"
    fi

    kubectl_apply_idempotent <<EOF
apiVersion: redis.redis.opstreelabs.in/v1beta2
kind: Redis
metadata:
  name: ${REDIS_CR_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: cache
    app.kubernetes.io/managed-by: redis-operator
    managed-by: platform-provisioner
    environment: ${ENV}
    domain: ${DOMAIN}
spec:
  kubernetesConfig:
    image: redis:7.2-alpine
    imagePullPolicy: IfNotPresent
    redisSecret:
      name: ${SECRET_NAME}
      key: password
  redisConfig:
    additionalRedisConfig: |
      maxmemory-policy allkeys-lru
      timeout 300
      tcp-keepalive 60
  resources:
    requests:
      cpu: ${CPU_REQ}
      memory: ${MEMORY}
    limits:
      cpu: ${CPU_LIM}
      memory: ${MEMORY}
${STORAGE_SPEC}
  securityContext:
    runAsUser: 1000
    fsGroup: 1000
EOF

    log_success "Redis CR criado"

    # ExternalSecret
    log_info "Criando ExternalSecret..."

    kubectl_apply_idempotent <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${APP_NAME}-redis-external
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: cache
    managed-by: platform-provisioner
    environment: ${ENV}
    domain: ${DOMAIN}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: ${SECRET_NAME}
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef: { key: "${VAULT_PATH}", property: "password" }
  - secretKey: host
    remoteRef: { key: "${VAULT_PATH}", property: "host" }
  - secretKey: port
    remoteRef: { key: "${VAULT_PATH}", property: "port" }
  - secretKey: connection-string
    remoteRef: { key: "${VAULT_PATH}", property: "connection-string" }
EOF

    log_success "ExternalSecret criado"

    # Vault
    vault_kv_put_safe "${VAULT_PATH}" \
        host="${REDIS_CR_NAME}.${NAMESPACE}.svc.cluster.local" port="6379" \
        password="$REDIS_PASSWORD" \
        connection-string="redis://:${REDIS_PASSWORD}@${REDIS_CR_NAME}.${NAMESPACE}.svc.cluster.local:6379/0" \
        created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    log_success "Redis totalmente provisionado para $APP_NAME (env=$ENV, domain=$DOMAIN)"
}

main "$@"
