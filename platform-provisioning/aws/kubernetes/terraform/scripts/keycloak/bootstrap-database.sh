#!/usr/bin/env bash
# =============================================================================
# Keycloak Database Bootstrap Script
# Creates database and user for Keycloak SSO Platform
# Idempotent: Safe to run multiple times
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

DB_NAME="keycloak"
DB_USER="keycloak_user"
DB_PASSWORD="${KEYCLOAK_DB_PASSWORD:-$(openssl rand -base64 24)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Bootstrap Keycloak database in PostgreSQL RDS.

OPTIONS:
  -h, --help              Show this help message
  -H, --host HOST         PostgreSQL host (default: from terraform output)
  -p, --port PORT         PostgreSQL port (default: 5432)
  -U, --admin-user USER   Admin user (default: postgres)
  -d, --dry-run           Dry run (show SQL only)

ENVIRONMENT VARIABLES:
  KEYCLOAK_DB_PASSWORD    Database password (default: auto-generated)
  PGPASSWORD              PostgreSQL admin password (required)

EXAMPLES:
  # Auto-detect RDS endpoint from Terraform
  PGPASSWORD=<admin-pass> $SCRIPT_NAME

  # Specify host manually
  PGPASSWORD=<admin-pass> $SCRIPT_NAME --host my-rds.amazonaws.com

  # Dry run
  $SCRIPT_NAME --dry-run
EOF
}

check_prerequisites() {
  log "Checking prerequisites..."

  # Check psql
  if ! command -v psql &>/dev/null; then
    error "psql not found. Install postgresql-client."
    exit 1
  fi

  # Check openssl
  if ! command -v openssl &>/dev/null; then
    error "openssl not found."
    exit 1
  fi

  # Check kubectl
  if ! command -v kubectl &>/dev/null; then
    warn "kubectl not found. Will not be able to store secret in Vault."
  fi

  log "Prerequisites OK"
}

get_rds_endpoint() {
  log "Getting PostgreSQL endpoint from Terraform..."

  cd "${SCRIPT_DIR}/../../environments/staging" || {
    error "Staging environment directory not found"
    exit 1
  }

  # Try to get from terraform output
  if RDS_ENDPOINT=$(terraform output -raw postgresql_endpoint 2>/dev/null); then
    log "RDS endpoint: $RDS_ENDPOINT"
    echo "$RDS_ENDPOINT"
  else
    # Fallback: get from Kubernetes service
    warn "Could not get from Terraform, checking Kubernetes..."

    if command -v kubectl &>/dev/null; then
      K8S_SERVICE=$(kubectl get svc -n default postgresql-external -o jsonpath='{.spec.externalName}' 2>/dev/null || echo "")

      if [[ -n "$K8S_SERVICE" ]]; then
        log "PostgreSQL endpoint (from K8s): $K8S_SERVICE"
        echo "$K8S_SERVICE"
      else
        error "Could not determine PostgreSQL endpoint. Use --host flag."
        exit 1
      fi
    else
      error "Could not determine PostgreSQL endpoint. Use --host flag."
      exit 1
    fi
  fi
}

bootstrap_database() {
  local host=$1
  local port=$2
  local admin_user=$3
  local dry_run=$4

  log "Bootstrapping Keycloak database..."
  log "  Host: $host"
  log "  Port: $port"
  log "  Admin User: $admin_user"
  log "  Database: $DB_NAME"
  log "  DB User: $DB_USER"

  # Check if PGPASSWORD is set
  if [[ -z "${PGPASSWORD:-}" ]]; then
    error "PGPASSWORD environment variable not set"
    exit 1
  fi

  # SQL commands
  local SQL_CREATE_USER="
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '${DB_USER}') THEN
        CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
      END IF;
    END
    \$\$;
  "

  local SQL_CREATE_DB="
    SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\\gexec
  "

  local SQL_GRANT_PRIVILEGES="
    GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
  "

  if [[ "$dry_run" == "true" ]]; then
    log "DRY RUN - SQL commands that would be executed:"
    echo ""
    echo "-- Create user (idempotent)"
    echo "$SQL_CREATE_USER"
    echo ""
    echo "-- Create database (idempotent)"
    echo "$SQL_CREATE_DB"
    echo ""
    echo "-- Grant privileges"
    echo "$SQL_GRANT_PRIVILEGES"
    echo ""
    log "Dry run complete. No changes made."
    return 0
  fi

  # Execute SQL commands
  log "Creating user ${DB_USER}..."
  psql -h "$host" -p "$port" -U "$admin_user" -d postgres -c "$SQL_CREATE_USER" || {
    error "Failed to create user"
    return 1
  }

  log "Creating database ${DB_NAME}..."
  psql -h "$host" -p "$port" -U "$admin_user" -d postgres -c "$SQL_CREATE_DB" || {
    error "Failed to create database"
    return 1
  }

  log "Granting privileges..."
  psql -h "$host" -p "$port" -U "$admin_user" -d postgres -c "$SQL_GRANT_PRIVILEGES" || {
    error "Failed to grant privileges"
    return 1
  }

  log "✅ Database bootstrap complete"

  # Test connection
  log "Testing connection as ${DB_USER}..."
  PGPASSWORD="$DB_PASSWORD" psql -h "$host" -p "$port" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" >/dev/null || {
    error "Connection test failed"
    return 1
  }

  log "✅ Connection test successful"
}

save_credentials() {
  log "Saving credentials output..."

  cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Keycloak Database Credentials
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Database:  $DB_NAME
Username:  $DB_USER
Password:  $DB_PASSWORD

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔐 Store in Vault:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

kubectl exec -n vault-system vault-0 -- vault kv put secret/keycloak/postgresql \\
  username=$DB_USER \\
  password=$DB_PASSWORD \\
  host=$PG_HOST \\
  port=$PG_PORT \\
  database=$DB_NAME

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  IMPORTANT: Store these credentials securely!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

  # Save to temporary file
  local CREDS_FILE="/tmp/keycloak-db-credentials-$(date +%s).txt"
  cat > "$CREDS_FILE" <<EOF
Database: $DB_NAME
Username: $DB_USER
Password: $DB_PASSWORD
Host: $PG_HOST
Port: $PG_PORT
EOF

  log "Credentials saved to: $CREDS_FILE"
  log "⚠️  Remember to delete this file after storing in Vault!"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  # Default values
  local PG_HOST=""
  local PG_PORT="5432"
  local PG_ADMIN_USER="postgres"
  local DRY_RUN="false"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        usage
        exit 0
        ;;
      -H|--host)
        PG_HOST="$2"
        shift 2
        ;;
      -p|--port)
        PG_PORT="$2"
        shift 2
        ;;
      -U|--admin-user)
        PG_ADMIN_USER="$2"
        shift 2
        ;;
      -d|--dry-run)
        DRY_RUN="true"
        shift
        ;;
      *)
        error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  log "Starting Keycloak database bootstrap..."

  check_prerequisites

  # Get RDS endpoint if not provided
  if [[ -z "$PG_HOST" ]]; then
    PG_HOST=$(get_rds_endpoint)
  fi

  # Export for use in save_credentials
  export PG_HOST PG_PORT

  bootstrap_database "$PG_HOST" "$PG_PORT" "$PG_ADMIN_USER" "$DRY_RUN"

  if [[ "$DRY_RUN" == "false" ]]; then
    save_credentials
  fi

  log "✅ Keycloak database bootstrap complete"
}

main "$@"
