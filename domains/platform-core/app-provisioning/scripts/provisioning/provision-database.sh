#!/bin/bash
# =============================================================================
# provision-database.sh — Provisiona PostgreSQL database no RDS shared cluster
# =============================================================================
# Descricao: Cria database, users (app/readonly/admin), secrets, ExternalSecret
#            e armazena credenciais no Vault. Idempotente.
# Uso:       ./provision-database.sh --env <env> --domain <domain> --app <name> --namespace <ns> [opts]
# Deps:      kubectl, vault (CLI), openssl
# Ref:       ADR-060 (PostgreSQL Governance)
# Idempotente: SIM — verifica existencia de secret e database antes de criar
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="POSTGRES"
source "${SCRIPT_DIR}/../lib/common.sh"

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Ajuda
# -----------------------------------------------------------------------------
usage() {
    cat <<USAGE
Uso: $0 --env <env> --domain <domain> --app <name> --namespace <ns> [opcoes]

Parametros obrigatorios:
  --env          Ambiente (staging, prod, etc.) — SEM default
  --domain       Dominio do app (ex: platform-core, checkout)
  --app          Nome da aplicacao
  --namespace    Namespace Kubernetes

Parametros opcionais:
  --db-type      shared|dedicated (default: shared)
  --db-name      Override do nome do database (default: APP_NAME em snake_case)
  --db-host      Override do hostname RDS (default: convencao baseada em --env)
  --db-port      Porta do database (default: 5432)
  --pg-image     Imagem postgres para o Job (default: postgres:16-alpine)
  --master-secret  Nome do secret com master credentials (default: rds-postgres-master-credentials-<env>)
  --extensions   Lista de extensoes separadas por virgula (default: uuid-ossp,pg_stat_statements)
  --dry-run      Apenas mostra o que seria feito
USAGE
    exit 1
}

# -----------------------------------------------------------------------------
# Parse de parametros
# -----------------------------------------------------------------------------
parse_args() {
    APP_NAME="" NAMESPACE="" DB_TYPE="shared" DB_NAME_OVERRIDE="" DRY_RUN=false
    ENV="" DOMAIN="" DB_HOST_OVERRIDE="" DB_PORT="5432"
    PG_IMAGE="${PG_IMAGE:-postgres:16-alpine}"
    MASTER_SECRET_OVERRIDE=""
    EXTENSIONS="${EXTENSIONS:-uuid-ossp,pg_stat_statements}"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --env)            ENV="$2"; shift 2 ;;
            --domain)         DOMAIN="$2"; shift 2 ;;
            --app)            APP_NAME="$2"; shift 2 ;;
            --namespace)      NAMESPACE="$2"; shift 2 ;;
            --db-type)        DB_TYPE="$2"; shift 2 ;;
            --db-name)        DB_NAME_OVERRIDE="$2"; shift 2 ;;
            --db-host)        DB_HOST_OVERRIDE="$2"; shift 2 ;;
            --db-port)        DB_PORT="$2"; shift 2 ;;
            --pg-image)       PG_IMAGE="$2"; shift 2 ;;
            --master-secret)  MASTER_SECRET_OVERRIDE="$2"; shift 2 ;;
            --extensions)     EXTENSIONS="$2"; shift 2 ;;
            --dry-run)        DRY_RUN=true; shift ;;
            --help|-h)        usage ;;
            *) log_error "Opcao desconhecida: $1"; usage ;;
        esac
    done

    validate_required_args ENV DOMAIN APP_NAME NAMESPACE || { usage; }
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    # Derivar valores baseados em convencoes (ZERO hardcodes)
    DB_NAME="${DB_NAME_OVERRIDE:-${APP_NAME//-/_}}"
    DB_USER="${DB_NAME}_user"
    DB_READONLY_USER="${DB_NAME}_readonly"
    DB_ADMIN_USER="${DB_NAME}_admin"

    DB_HOST="${DB_HOST_OVERRIDE:-${DB_HOST:-rds-shared-cluster.${ENV}-platform-databases.svc.cluster.local}}"
    MASTER_SECRET="${MASTER_SECRET_OVERRIDE:-rds-postgres-master-credentials-${ENV}}"
    VAULT_PATH="secret/${ENV}/${DOMAIN}/${APP_NAME}/database"
    SECRET_NAME="${APP_NAME}-postgres-credentials"

    # Gerar SQL de extensoes
    EXTENSIONS_SQL=""
    IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
    for ext in "${EXT_ARRAY[@]}"; do
        ext=$(echo "$ext" | xargs)
        EXTENSIONS_SQL+="CREATE EXTENSION IF NOT EXISTS \"${ext}\";"$'\n'
    done

    # Resumo
    log_info "============================================="
    log_info "Env: $ENV | Domain: $DOMAIN"
    log_info "Database: $DB_NAME | Type: $DB_TYPE | Namespace: $NAMESPACE"
    log_info "Host: $DB_HOST | Port: $DB_PORT"
    log_info "Master secret: $MASTER_SECRET"
    log_info "Vault path: $VAULT_PATH"
    log_info "PG image: $PG_IMAGE"
    log_info "Extensions: $EXTENSIONS"
    log_info "============================================="

    # Check-before-create
    if resource_exists secret "$SECRET_NAME" "$NAMESPACE"; then
        log_warn "Secret '$SECRET_NAME' ja existe em '$NAMESPACE' — pulando provisioning"
        log_info "Para re-provisionar, delete o secret primeiro: kubectl delete secret $SECRET_NAME -n $NAMESPACE"
        exit 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Criaria database '$DB_NAME', users, secret e ExternalSecret"
        log_info "[DRY-RUN] Host: $DB_HOST"
        log_info "[DRY-RUN] Vault: $VAULT_PATH"
        log_info "[DRY-RUN] Master secret: $MASTER_SECRET"
        log_info "[DRY-RUN] Extensions: $EXTENSIONS"
        log_info "[DRY-RUN] PG image: $PG_IMAGE"
        exit 0
    fi

    # Gerar passwords seguros
    log_info "Gerando credenciais seguras..."
    DB_PASSWORD=$(generate_password 25)
    DB_READONLY_PASSWORD=$(generate_password 25)
    DB_ADMIN_PASSWORD=$(generate_password 25)

    # Criar database e users via Job
    log_info "Criando database e users no RDS..."
    kubectl delete job "${APP_NAME}-db-setup" -n "$NAMESPACE" --ignore-not-found &>/dev/null

    kubectl_apply_idempotent <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${APP_NAME}-db-setup
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: database-setup
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
      - name: postgres-client
        image: ${PG_IMAGE}
        command: ["sh", "-c"]
        args:
        - |
          set -e
          psql -h \${DB_HOST} -U postgres -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '\${DB_NAME}'" | grep -q 1 || \
            psql -h \${DB_HOST} -U postgres -d postgres -c "CREATE DATABASE \${DB_NAME} WITH OWNER = postgres ENCODING = 'UTF8';"

          psql -h \${DB_HOST} -U postgres -d postgres -c "DO \\\$\\\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '\${DB_USER}') THEN CREATE USER \${DB_USER} WITH PASSWORD '\${DB_PASSWORD}'; END IF; END \\\$\\\$;"
          psql -h \${DB_HOST} -U postgres -d postgres -c "DO \\\$\\\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '\${DB_READONLY_USER}') THEN CREATE USER \${DB_READONLY_USER} WITH PASSWORD '\${DB_READONLY_PASSWORD}'; END IF; END \\\$\\\$;"
          psql -h \${DB_HOST} -U postgres -d postgres -c "DO \\\$\\\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '\${DB_ADMIN_USER}') THEN CREATE USER \${DB_ADMIN_USER} WITH PASSWORD '\${DB_ADMIN_PASSWORD}'; END IF; END \\\$\\\$;"

          psql -h \${DB_HOST} -U postgres -d \${DB_NAME} -c "
            GRANT CONNECT ON DATABASE \${DB_NAME} TO \${DB_USER};
            GRANT USAGE ON SCHEMA public TO \${DB_USER};
            GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \${DB_USER};
            ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \${DB_USER};
            GRANT CONNECT ON DATABASE \${DB_NAME} TO \${DB_READONLY_USER};
            GRANT USAGE ON SCHEMA public TO \${DB_READONLY_USER};
            GRANT SELECT ON ALL TABLES IN SCHEMA public TO \${DB_READONLY_USER};
            ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO \${DB_READONLY_USER};
            GRANT ALL PRIVILEGES ON DATABASE \${DB_NAME} TO \${DB_ADMIN_USER};
            ${EXTENSIONS_SQL}
            ALTER DATABASE \${DB_NAME} SET statement_timeout = '30s';
            ALTER DATABASE \${DB_NAME} SET idle_in_transaction_session_timeout = '60s';
          "
          echo "Database setup completo."
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: ${MASTER_SECRET}
              key: password
        - name: DB_HOST
          value: "${DB_HOST}"
        - name: DB_NAME
          value: "${DB_NAME}"
        - name: DB_USER
          value: "${DB_USER}"
        - name: DB_PASSWORD
          value: "${DB_PASSWORD}"
        - name: DB_READONLY_USER
          value: "${DB_READONLY_USER}"
        - name: DB_READONLY_PASSWORD
          value: "${DB_READONLY_PASSWORD}"
        - name: DB_ADMIN_USER
          value: "${DB_ADMIN_USER}"
        - name: DB_ADMIN_PASSWORD
          value: "${DB_ADMIN_PASSWORD}"
EOF

    log_info "Aguardando Job concluir..."
    kubectl wait --for=condition=complete --timeout=300s "job/${APP_NAME}-db-setup" -n "$NAMESPACE"
    log_success "Database e users criados"

    # Criar Secret
    log_info "Criando Secret..."

    create_secret_idempotent "$SECRET_NAME" "$NAMESPACE" \
        --from-literal=host="$DB_HOST" \
        --from-literal=port="$DB_PORT" \
        --from-literal=database="$DB_NAME" \
        --from-literal=username="$DB_USER" \
        --from-literal=password="$DB_PASSWORD" \
        --from-literal=readonly-username="$DB_READONLY_USER" \
        --from-literal=readonly-password="$DB_READONLY_PASSWORD" \
        --from-literal=admin-username="$DB_ADMIN_USER" \
        --from-literal=admin-password="$DB_ADMIN_PASSWORD" \
        --from-literal=connection-string="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require"

    label_secret "$SECRET_NAME" "$NAMESPACE" "$APP_NAME" "database" "$ENV" "$DOMAIN"

    log_success "Secret '$SECRET_NAME' criado"

    # ExternalSecret
    log_info "Criando ExternalSecret..."

    kubectl_apply_idempotent <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${APP_NAME}-postgres-external
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: database
    app.kubernetes.io/part-of: ${DOMAIN}
    platform.io/env: ${ENV}
    managed-by: platform-provisioner
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
  - secretKey: database
    remoteRef: { key: "${VAULT_PATH}", property: "database" }
  - secretKey: username
    remoteRef: { key: "${VAULT_PATH}", property: "username" }
  - secretKey: password
    remoteRef: { key: "${VAULT_PATH}", property: "password" }
  - secretKey: connection-string
    remoteRef: { key: "${VAULT_PATH}", property: "connection-string" }
EOF

    log_success "ExternalSecret criado"

    # Vault
    vault_kv_put_safe "${VAULT_PATH}" \
        host="$DB_HOST" port="$DB_PORT" database="$DB_NAME" \
        username="$DB_USER" password="$DB_PASSWORD" \
        readonly-username="$DB_READONLY_USER" readonly-password="$DB_READONLY_PASSWORD" \
        admin-username="$DB_ADMIN_USER" admin-password="$DB_ADMIN_PASSWORD" \
        connection-string="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require" \
        env="$ENV" domain="$DOMAIN" \
        created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    log_success "PostgreSQL totalmente provisionado para $APP_NAME (env=$ENV, domain=$DOMAIN)"
}

main "$@"
