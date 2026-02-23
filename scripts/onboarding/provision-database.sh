#!/bin/bash
# Provisiona PostgreSQL Database e Secrets
# Referência: ADR-060 (PostgreSQL Governance Standards)
# Uso: ./provision-database.sh <produto> <namespace>

set -euo pipefail

PRODUTO="$1"
NAMESPACE="$2"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[POSTGRES]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[POSTGRES]${NC} $1"
}

# Validações
log_info "Validando nome do produto..."

# ADR-060: Database naming convention
if ! [[ "$PRODUTO" =~ ^[a-z][a-z0-9_]{0,62}$ ]]; then
    echo "❌ Nome do produto inválido para PostgreSQL: '$PRODUTO'"
    echo "Formato esperado: ^[a-z][a-z0-9_]{0,62}$ (snake_case ou kebab-case)"
    exit 1
fi

# Converter kebab-case para snake_case se necessário
DB_NAME="${PRODUTO//-/_}"

log_info "Database: $DB_NAME"
log_info "Namespace: $NAMESPACE"

# ====================
# Gerar Passwords Seguros
# ====================
log_info "Gerando credenciais seguras..."

DB_USER="${DB_NAME}_user"
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
DB_READONLY_USER="${DB_NAME}_readonly"
DB_READONLY_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
DB_ADMIN_USER="${DB_NAME}_admin"
DB_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# RDS Shared Cluster endpoint (ADR-060)
DB_HOST="rds-shared-cluster.prod-platform-databases.svc.cluster.local"
DB_PORT="5432"

# ====================
# Criar Database e Users no RDS
# ====================
log_info "Criando database e users no RDS..."

# SQL para criar database e users
SQL_SCRIPT=$(cat <<EOF
-- Criar database
CREATE DATABASE ${DB_NAME}
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;

-- Conectar ao database
\c ${DB_NAME}

-- Criar users (ADR-060)
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
CREATE USER ${DB_READONLY_USER} WITH PASSWORD '${DB_READONLY_PASSWORD}';
CREATE USER ${DB_ADMIN_USER} WITH PASSWORD '${DB_ADMIN_PASSWORD}';

-- Grants para user principal (read/write)
GRANT CONNECT ON DATABASE ${DB_NAME} TO ${DB_USER};
GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ${DB_USER};

-- Grants para readonly user
GRANT CONNECT ON DATABASE ${DB_NAME} TO ${DB_READONLY_USER};
GRANT USAGE ON SCHEMA public TO ${DB_READONLY_USER};
GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${DB_READONLY_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${DB_READONLY_USER};

-- Grants para admin user (DDL)
GRANT CONNECT ON DATABASE ${DB_NAME} TO ${DB_ADMIN_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_ADMIN_USER};
GRANT ALL PRIVILEGES ON SCHEMA public TO ${DB_ADMIN_USER};

-- Habilitar extensões padrão (ADR-060)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Configurações de performance (ADR-060)
ALTER DATABASE ${DB_NAME} SET statement_timeout = '30s';
ALTER DATABASE ${DB_NAME} SET idle_in_transaction_session_timeout = '60s';
EOF
)

# Executar via kubectl exec no pod do RDS proxy ou psql job
log_info "Executando SQL no RDS..."

# Criar Job temporário para executar SQL
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${PRODUTO}-db-setup
  namespace: ${NAMESPACE}
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: postgres-client
        image: postgres:15-alpine
        command:
        - sh
        - -c
        - |
          echo "\${SQL_SCRIPT}" | psql -h \${DB_HOST} -U postgres -d postgres
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: rds-postgres-master-credentials
              key: password
        - name: DB_HOST
          value: "${DB_HOST}"
        - name: SQL_SCRIPT
          value: |
$(echo "$SQL_SCRIPT" | sed 's/^/            /')
EOF

log_info "Aguardando Job concluir..."
kubectl wait --for=condition=complete --timeout=300s job/${PRODUTO}-db-setup -n ${NAMESPACE}

log_success "Database e users criados no RDS"

# ====================
# Criar Secret no Kubernetes
# ====================
log_info "Criando Secret no Kubernetes..."

# Secret naming (ADR-060)
SECRET_NAME="${PRODUTO}-postgres-credentials"

kubectl create secret generic "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    --from-literal=host="$DB_HOST" \
    --from-literal=port="$DB_PORT" \
    --from-literal=database="$DB_NAME" \
    --from-literal=username="$DB_USER" \
    --from-literal=password="$DB_PASSWORD" \
    --from-literal=readonly-username="$DB_READONLY_USER" \
    --from-literal=readonly-password="$DB_READONLY_PASSWORD" \
    --from-literal=admin-username="$DB_ADMIN_USER" \
    --from-literal=admin-password="$DB_ADMIN_PASSWORD" \
    --from-literal=connection-string="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require" \
    --dry-run=client -o yaml | kubectl apply -f -

# Adicionar labels obrigatórias (ADR-048)
kubectl label secret "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    app.kubernetes.io/name="$PRODUTO" \
    app.kubernetes.io/component="database" \
    app.kubernetes.io/managed-by="governance-onboarding" \
    database-type="postgresql" \
    --overwrite

log_success "Secret '$SECRET_NAME' criado em namespace '$NAMESPACE'"

# ====================
# Criar ExternalSecret para Vault (ADR-063)
# ====================
log_info "Criando ExternalSecret para sincronização com Vault..."

kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${PRODUTO}-postgres-external
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${PRODUTO}
    app.kubernetes.io/component: database
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: ${PRODUTO}-postgres-credentials
    creationPolicy: Owner
  data:
  - secretKey: host
    remoteRef:
      key: database/${PRODUTO}/postgres
      property: host
  - secretKey: port
    remoteRef:
      key: database/${PRODUTO}/postgres
      property: port
  - secretKey: database
    remoteRef:
      key: database/${PRODUTO}/postgres
      property: database
  - secretKey: username
    remoteRef:
      key: database/${PRODUTO}/postgres
      property: username
  - secretKey: password
    remoteRef:
      key: database/${PRODUTO}/postgres
      property: password
  - secretKey: connection-string
    remoteRef:
      key: database/${PRODUTO}/postgres
      property: connection-string
EOF

log_success "ExternalSecret criado para sincronização com Vault"

# ====================
# Armazenar credenciais no Vault
# ====================
log_info "Armazenando credenciais no Vault..."

# Usar Vault CLI para armazenar secrets
vault kv put secret/database/${PRODUTO}/postgres \
    host="${DB_HOST}" \
    port="${DB_PORT}" \
    database="${DB_NAME}" \
    username="${DB_USER}" \
    password="${DB_PASSWORD}" \
    readonly-username="${DB_READONLY_USER}" \
    readonly-password="${DB_READONLY_PASSWORD}" \
    admin-username="${DB_ADMIN_USER}" \
    admin-password="${DB_ADMIN_PASSWORD}" \
    connection-string="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require" \
    created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    rotation-schedule="90d"

log_success "Credenciais armazenadas no Vault (path: secret/database/${PRODUTO}/postgres)"

# ====================
# Criar ConfigMap com metadata
# ====================
log_info "Criando ConfigMap com metadata..."

kubectl create configmap "${PRODUTO}-postgres-config" \
    --namespace="$NAMESPACE" \
    --from-literal=database-name="$DB_NAME" \
    --from-literal=host="$DB_HOST" \
    --from-literal=port="$DB_PORT" \
    --from-literal=ssl-mode="require" \
    --from-literal=pool-size="10" \
    --from-literal=pool-mode="transaction" \
    --from-literal=max-connections="100" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap "${PRODUTO}-postgres-config" \
    --namespace="$NAMESPACE" \
    app.kubernetes.io/name="$PRODUTO" \
    app.kubernetes.io/component="database-config" \
    --overwrite

log_success "ConfigMap '${PRODUTO}-postgres-config' criado"

# ====================
# Sumário
# ====================
echo ""
log_success "========================================="
log_success "PostgreSQL Provisionado!"
log_success "========================================="
echo ""
log_info "Database: $DB_NAME"
log_info "Host: $DB_HOST:$DB_PORT"
log_info "Secret: $SECRET_NAME (namespace: $NAMESPACE)"
log_info "Vault Path: secret/database/${PRODUTO}/postgres"
echo ""
log_info "Users criados:"
log_info "  - ${DB_USER} (read/write)"
log_info "  - ${DB_READONLY_USER} (readonly)"
log_info "  - ${DB_ADMIN_USER} (admin/migrations)"
echo ""
log_info "Connection String:"
log_info "  postgresql://${DB_USER}:{password}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require"
echo ""
log_info "Uso no Deployment:"
echo "  env:"
echo "  - name: DATABASE_URL"
echo "    valueFrom:"
echo "      secretKeyRef:"
echo "        name: $SECRET_NAME"
echo "        key: connection-string"
echo ""
log_success "========================================="
