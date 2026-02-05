#!/bin/bash
# Bootstrap SonarQube database in PostgreSQL RDS
# Usage: ./bootstrap-database.sh <RDS_ENDPOINT> <MASTER_PASSWORD>

set -e

RDS_ENDPOINT=${1:-""}
MASTER_PASSWORD=${2:-""}
DATABASE="sonarqube"
DB_USER="sonarqube_user"
DB_PASSWORD=$(openssl rand -base64 32)

if [ -z "$RDS_ENDPOINT" ] || [ -z "$MASTER_PASSWORD" ]; then
  echo "Usage: $0 <RDS_ENDPOINT> <MASTER_PASSWORD>"
  exit 1
fi

echo "🔧 Bootstrapping SonarQube database..."

# Create database and user
kubectl run psql-sonarqube --rm -i --restart=Never \
  --image=postgres:15 --env="PGPASSWORD=$MASTER_PASSWORD" -- \
  psql -h "$RDS_ENDPOINT" -U postgres_admin -d postgres <<SQL
-- Create database
CREATE DATABASE $DATABASE;

-- Create user
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DATABASE TO $DB_USER;

-- Connect to database and grant schema privileges
\c $DATABASE
GRANT ALL ON SCHEMA public TO $DB_USER;
SQL

echo "✅ Database bootstrapped"
echo "📝 Store credentials in Vault:"
echo "  vault kv put secret/sonarqube/database \\"
echo "    username=$DB_USER \\"
echo "    password=$DB_PASSWORD \\"
echo "    host=$RDS_ENDPOINT \\"
echo "    port=5432 \\"
echo "    database=$DATABASE"
