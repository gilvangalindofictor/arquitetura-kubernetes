#!/bin/bash
# =============================================================================
# provision-redis.sh — Provisiona Redis para aplicacao (idempotente)
# =============================================================================
# Descricao: Suporta dois modos:
#   - shared:     Usa o Redis compartilhado do cluster (staging-data-infrastructure).
#                 Le a password do secret existente, cria Vault path + ExternalSecret.
#   - standalone: Cria Redis CR dedicado via Redis Operator (OT).
#                 Gera password, cria Secret, CR, ExternalSecret e Vault path.
#   - sentinel:   (futuro) Redis HA com Sentinel.
#
# Uso:       ./provision-redis.sh --app <name> --namespace <ns> --env <e> --domain <d> --mode <shared|standalone|sentinel> [--storage-class <sc>]
# Deps:      kubectl, vault (CLI), openssl
# Ref:       ADR-061 (Redis Governance), OT Redis Operator v0.23.0
# Idempotente: SIM — verifica existencia de secret/CR antes de criar
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
# Defaults — infraestrutura compartilhada
# Ajustar se o cluster Redis mudar de namespace ou nome.
# -----------------------------------------------------------------------------
SHARED_REDIS_NAMESPACE="staging-data-infrastructure"
SHARED_REDIS_SECRET_NAME="redis-password"
SHARED_REDIS_SECRET_KEY="password"
SHARED_REDIS_HOST="redis.staging-data-infrastructure.svc.cluster.local"
SHARED_REDIS_PORT="6379"

# Prod overrides
SHARED_REDIS_NAMESPACE_PROD="prod-data-infrastructure"
SHARED_REDIS_HOST_PROD="redis.prod-data-infrastructure.svc.cluster.local"

# -----------------------------------------------------------------------------
# Parse argumentos
# -----------------------------------------------------------------------------
parse_args() {
    APP_NAME="" NAMESPACE="" MODE="shared" ENV="" DOMAIN="" STORAGE_CLASS="default" DRY_RUN=false
    REDIS_DB="${REDIS_DB:-0}"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --app)            APP_NAME="$2"; shift 2 ;;
            --namespace)      NAMESPACE="$2"; shift 2 ;;
            --mode)           MODE="$2"; shift 2 ;;
            --env)            ENV="$2"; shift 2 ;;
            --domain)         DOMAIN="$2"; shift 2 ;;
            --storage-class)  STORAGE_CLASS="$2"; shift 2 ;;
            --redis-db)       REDIS_DB="$2"; shift 2 ;;
            --dry-run)        DRY_RUN=true; shift ;;
            *) log_error "Opcao desconhecida: $1"; exit 1 ;;
        esac
    done

    validate_required_args APP_NAME NAMESPACE ENV DOMAIN || exit 1
}

# -----------------------------------------------------------------------------
# provision_shared — Redis compartilhado (sem criar instancia nova)
# Fluxo: ler password do shared secret → Vault → ExternalSecret → K8s Secret
# -----------------------------------------------------------------------------
provision_shared() {
    local secret_name="${APP_NAME}-redis-credentials"
    local vault_path="secret/${ENV}/${DOMAIN}/${APP_NAME}/redis"

    # Resolver endpoint por ambiente
    local redis_host="$SHARED_REDIS_HOST"
    local redis_ns="$SHARED_REDIS_NAMESPACE"
    if [[ "$ENV" == "prod" ]]; then
        redis_host="$SHARED_REDIS_HOST_PROD"
        redis_ns="$SHARED_REDIS_NAMESPACE_PROD"
    fi

    log_info "============================================="
    log_info "Modo: SHARED (Redis compartilhado)"
    log_info "Host: $redis_host | Port: $SHARED_REDIS_PORT | DB: $REDIS_DB"
    log_info "Shared secret: $SHARED_REDIS_SECRET_NAME (ns: $redis_ns)"
    log_info "Vault path: $vault_path"
    log_info "K8s Secret: $secret_name (ns: $NAMESPACE)"
    log_info "============================================="

    # Check-before-create: se ExternalSecret ja existe E esta Synced, pular
    if resource_exists externalsecret "${APP_NAME}-redis-external" "$NAMESPACE"; then
        local es_status
        es_status=$(kubectl get externalsecret "${APP_NAME}-redis-external" -n "$NAMESPACE" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || echo "Unknown")
        if [[ "$es_status" == "SecretSynced" ]]; then
            log_warn "ExternalSecret '${APP_NAME}-redis-external' ja existe e Synced — pulando"
            exit 0
        fi
        log_info "ExternalSecret existe mas status=$es_status — re-provisionando"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Criaria Vault secret, ExternalSecret e K8s Secret (shared Redis)"
        log_info "[DRY-RUN] Host: $redis_host | Secret source: ${redis_ns}/${SHARED_REDIS_SECRET_NAME}"
        exit 0
    fi

    # Ler password do Redis compartilhado
    log_info "Lendo password do Redis compartilhado..."
    local redis_password
    redis_password=$(kubectl get secret "$SHARED_REDIS_SECRET_NAME" -n "$redis_ns" \
        -o jsonpath="{.data.${SHARED_REDIS_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null)

    if [[ -z "$redis_password" ]]; then
        log_error "Falha ao ler password do Redis compartilhado"
        log_error "Secret: ${redis_ns}/${SHARED_REDIS_SECRET_NAME} (key: ${SHARED_REDIS_SECRET_KEY})"
        log_error "Verifique se o secret existe: kubectl get secret $SHARED_REDIS_SECRET_NAME -n $redis_ns"
        exit 1
    fi
    log_success "Password do Redis compartilhado obtida"

    # URL-encode password para connection strings (caracteres especiais)
    local redis_password_encoded
    redis_password_encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$redis_password', safe=''))" 2>/dev/null \
        || echo "$redis_password")

    # Construir connection strings por linguagem
    local conn_go="redis://:${redis_password_encoded}@${redis_host}:${SHARED_REDIS_PORT}/${REDIS_DB}"
    local conn_python="redis://:${redis_password}@${redis_host}:${SHARED_REDIS_PORT}/${REDIS_DB}"
    local conn_dotnet="${redis_host}:${SHARED_REDIS_PORT},password=${redis_password},abortConnect=false,connectTimeout=5000"

    # Gravar no Vault
    log_info "Armazenando credenciais no Vault..."
    vault_kv_put_safe "$vault_path" \
        host="$redis_host" \
        port="$SHARED_REDIS_PORT" \
        password="$redis_password" \
        db="$REDIS_DB" \
        mode="shared" \
        connection-string="$conn_go" \
        connection-string-python="$conn_python" \
        connection-string-dotnet="$conn_dotnet" \
        source-namespace="$redis_ns" \
        env="$ENV" domain="$DOMAIN" \
        created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # ExternalSecret — puxa do Vault para K8s Secret
    log_info "Criando ExternalSecret (Vault → K8s Secret)..."

    kubectl_apply_idempotent <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${APP_NAME}-redis-external
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: cache
    app.kubernetes.io/part-of: ${DOMAIN}
    platform.io/env: ${ENV}
    managed-by: platform-provisioner
    redis-mode: shared
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: ${secret_name}
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef: { key: "${vault_path}", property: "password" }
  - secretKey: host
    remoteRef: { key: "${vault_path}", property: "host" }
  - secretKey: port
    remoteRef: { key: "${vault_path}", property: "port" }
  - secretKey: connection-string
    remoteRef: { key: "${vault_path}", property: "connection-string" }
  - secretKey: connection-string-python
    remoteRef: { key: "${vault_path}", property: "connection-string-python" }
  - secretKey: connection-string-dotnet
    remoteRef: { key: "${vault_path}", property: "connection-string-dotnet" }
EOF

    log_success "ExternalSecret criado: ${APP_NAME}-redis-external"
    log_success "Redis SHARED provisionado para $APP_NAME (env=$ENV, domain=$DOMAIN)"
    log_info "K8s Secret '${secret_name}' sera criado pelo ESO apos sync"
    log_info "Env vars disponiveis: REDIS_HOST, REDIS_PORT, REDIS_PASSWORD, REDIS_URL (connection-string)"
}

# -----------------------------------------------------------------------------
# provision_dedicated — Redis dedicado via Redis Operator CR
# Fluxo: gerar password → K8s Secret → Redis CR → Vault → ExternalSecret
# -----------------------------------------------------------------------------
provision_dedicated() {
    local redis_cr_name="${APP_NAME}-redis"
    local secret_name="${APP_NAME}-redis-credentials"
    local vault_path="secret/${ENV}/${DOMAIN}/${APP_NAME}/redis"

    # Recursos por ambiente (ADR-061)
    local memory cpu_req cpu_lim persistence
    case "$ENV" in
        staging)  memory="512Mi"; cpu_req="200m"; cpu_lim="1000m"; persistence="yes" ;;
        prod)     memory="2Gi";   cpu_req="500m"; cpu_lim="2000m"; persistence="yes" ;;
        *)        memory="256Mi"; cpu_req="100m"; cpu_lim="500m";  persistence="no"  ;;
    esac

    log_info "============================================="
    log_info "Modo: DEDICATED (Redis Operator CR)"
    log_info "Redis CR: $redis_cr_name | Namespace: $NAMESPACE"
    log_info "Vault path: $vault_path | StorageClass: $STORAGE_CLASS"
    log_info "============================================="

    # Check-before-create
    if resource_exists redis "$redis_cr_name" "$NAMESPACE"; then
        log_warn "Redis CR '$redis_cr_name' ja existe — pulando"
        exit 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Criaria Redis CR, Secret e ExternalSecret"
        exit 0
    fi

    # Gerar password
    local redis_password
    redis_password=$(generate_password 25)
    local redis_host="${redis_cr_name}.${NAMESPACE}.svc.cluster.local"

    # Secret
    log_info "Criando Secret..."
    create_secret_idempotent "$secret_name" "$NAMESPACE" \
        --from-literal=password="$redis_password" \
        --from-literal=host="$redis_host" \
        --from-literal=port="6379" \
        --from-literal=connection-string="redis://:${redis_password}@${redis_host}:6379/${REDIS_DB}"

    label_secret "$secret_name" "$NAMESPACE" "$APP_NAME" "cache" "$ENV" "$DOMAIN"
    log_success "Secret criado"

    # Redis CR
    log_info "Criando Redis Custom Resource..."

    local storage_spec=""
    if [[ "$persistence" == "yes" ]]; then
        storage_spec="
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
  name: ${redis_cr_name}
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
      name: ${secret_name}
      key: password
  redisConfig:
    additionalRedisConfig: |
      maxmemory-policy allkeys-lru
      timeout 300
      tcp-keepalive 60
  resources:
    requests:
      cpu: ${cpu_req}
      memory: ${memory}
    limits:
      cpu: ${cpu_lim}
      memory: ${memory}
${storage_spec}
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
    name: ${secret_name}
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef: { key: "${vault_path}", property: "password" }
  - secretKey: host
    remoteRef: { key: "${vault_path}", property: "host" }
  - secretKey: port
    remoteRef: { key: "${vault_path}", property: "port" }
  - secretKey: connection-string
    remoteRef: { key: "${vault_path}", property: "connection-string" }
EOF

    log_success "ExternalSecret criado"

    # Vault
    vault_kv_put_safe "$vault_path" \
        host="$redis_host" port="6379" \
        password="$redis_password" \
        db="$REDIS_DB" \
        mode="dedicated" \
        connection-string="redis://:${redis_password}@${redis_host}:6379/${REDIS_DB}" \
        created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    log_success "Redis DEDICATED provisionado para $APP_NAME (env=$ENV, domain=$DOMAIN)"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    log_info "Provisionando Redis para $APP_NAME | Mode: $MODE | Env: $ENV | Domain: $DOMAIN"

    case "$MODE" in
        shared)
            provision_shared
            ;;
        standalone|dedicated)
            provision_dedicated
            ;;
        sentinel)
            log_error "Modo 'sentinel' ainda nao implementado — use 'shared' ou 'standalone'"
            exit 1
            ;;
        *)
            log_error "Modo invalido: '$MODE' (esperado: shared|standalone|sentinel)"
            exit 1
            ;;
    esac
}

main "$@"
