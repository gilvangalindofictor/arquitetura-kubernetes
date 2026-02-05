#!/bin/bash
# Bootstrap PostgreSQL Additional Databases
# Idempotent: CREATE DATABASE IF NOT EXISTS / CREATE USER IF NOT EXISTS

set -euo pipefail

# Arguments: HOST PORT MASTER_USER MASTER_PASS DB_NAME DB_USER DB_PASS
RDS_HOST="$1"
RDS_PORT="$2"
MASTER_USER="$3"
MASTER_PASS="$4"
DB_NAME="$5"
DB_USER="$6"
DB_PASS="$7"

export PGPASSWORD="$MASTER_PASS"

echo "[$(date '+%H:%M:%S')] Bootstrap | PostgreSQL | Database: $DB_NAME | User: $DB_USER"

# Check if database exists
DB_EXISTS=$(psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$MASTER_USER" -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")

if [ "$DB_EXISTS" != "1" ]; then
  echo "  → Creating database $DB_NAME"
  psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$MASTER_USER" -d postgres -c \
    "CREATE DATABASE $DB_NAME OWNER $MASTER_USER ENCODING 'UTF8';"
else
  echo "  → Database $DB_NAME already exists (skip)"
fi

# Check if user exists
USER_EXISTS=$(psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$MASTER_USER" -d postgres -tAc \
  "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'")

if [ "$USER_EXISTS" != "1" ]; then
  echo "  → Creating user $DB_USER"
  psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$MASTER_USER" -d postgres -c \
    "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
else
  echo "  → User $DB_USER already exists, updating password"
  psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$MASTER_USER" -d postgres -c \
    "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';"
fi

# Grant privileges
echo "  → Granting privileges"
psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$MASTER_USER" -d "$DB_NAME" <<SQL
  GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
  GRANT ALL ON SCHEMA public TO $DB_USER;
  ALTER DATABASE $DB_NAME OWNER TO $DB_USER;
SQL

echo "  ✅ Bootstrap complete for $DB_NAME"
