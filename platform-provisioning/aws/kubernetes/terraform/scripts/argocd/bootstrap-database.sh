#!/bin/bash
# ArgoCD Database Bootstrap Script
# Creates database and user in PostgreSQL RDS for ArgoCD

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
PG_HOST="postgresql-external.default.svc.cluster.local"
PG_ADMIN_USER="postgres_admin"
ARGOCD_DB_NAME="argocd"
ARGOCD_USER="argocd_user"

# Generate random password
ARGOCD_PASSWORD=$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-32)

echo -e "${GREEN}==> ArgoCD Database Bootstrap${NC}"
echo ""

# Get PostgreSQL admin password from AWS Secrets Manager
echo -e "${YELLOW}Retrieving PostgreSQL admin password from AWS Secrets Manager...${NC}"
PG_ADMIN_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id k8s-platform-prod/postgresql-master-20260122121716228600000001 \
  --query 'SecretString' \
  --output text 2>/dev/null | jq -r '.password')

if [ -z "$PG_ADMIN_PASSWORD" ]; then
  echo -e "${RED}Failed to retrieve admin password from Secrets Manager${NC}"
  exit 1
fi

export PGPASSWORD="$PG_ADMIN_PASSWORD"

echo -e "${GREEN}==> Checking if database '$ARGOCD_DB_NAME' exists...${NC}"
DB_EXISTS=$(kubectl exec -n default postgresql-external-client -- \
  psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d platform -tAc \
  "SELECT 1 FROM pg_database WHERE datname='$ARGOCD_DB_NAME'")

if [ "$DB_EXISTS" = "1" ]; then
  echo -e "${GREEN}✅ Database '$ARGOCD_DB_NAME' already exists${NC}"
else
  echo -e "${YELLOW}Creating database '$ARGOCD_DB_NAME'...${NC}"
  kubectl exec -n default postgresql-external-client -- \
    psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d platform -c \
    "CREATE DATABASE $ARGOCD_DB_NAME ENCODING 'UTF8'"
  echo -e "${GREEN}✅ Database created${NC}"
fi

echo ""
echo -e "${GREEN}==> Checking if user '$ARGOCD_USER' exists...${NC}"
USER_EXISTS=$(kubectl exec -n default postgresql-external-client -- \
  psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d platform -tAc \
  "SELECT 1 FROM pg_user WHERE usename='$ARGOCD_USER'")

if [ "$USER_EXISTS" = "1" ]; then
  echo -e "${GREEN}✅ User '$ARGOCD_USER' already exists${NC}"
  echo -e "${YELLOW}Updating password...${NC}"
  kubectl exec -n default postgresql-external-client -- \
    psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d platform -c \
    "ALTER USER $ARGOCD_USER WITH PASSWORD '$ARGOCD_PASSWORD'"
else
  echo -e "${YELLOW}Creating user '$ARGOCD_USER'...${NC}"
  kubectl exec -n default postgresql-external-client -- \
    psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d platform -c \
    "CREATE USER $ARGOCD_USER WITH PASSWORD '$ARGOCD_PASSWORD'"
  echo -e "${GREEN}✅ User created${NC}"
fi

echo ""
echo -e "${GREEN}==> Granting privileges...${NC}"
kubectl exec -n default postgresql-external-client -- \
  psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d platform -c \
  "GRANT ALL PRIVILEGES ON DATABASE $ARGOCD_DB_NAME TO $ARGOCD_USER"

kubectl exec -n default postgresql-external-client -- \
  psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d platform -c \
  "ALTER DATABASE $ARGOCD_DB_NAME OWNER TO $ARGOCD_USER"

# Grant schema permissions
kubectl exec -n default postgresql-external-client -- \
  psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d "$ARGOCD_DB_NAME" -c \
  "GRANT ALL ON SCHEMA public TO $ARGOCD_USER"

echo ""
echo -e "${GREEN}==> Verification:${NC}"
kubectl exec -n default postgresql-external-client -- \
  psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d platform -c \
  "\\l $ARGOCD_DB_NAME"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📋 ArgoCD Database Credentials${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Database:  $ARGOCD_DB_NAME"
echo "Username:  $ARGOCD_USER"
echo "Password:  $ARGOCD_PASSWORD"
echo "Host:      $PG_HOST"
echo "Port:      5432"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔐 Store in Vault:${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "kubectl exec -n vault-system vault-0 -- vault kv put secret/argocd/postgresql \\"
echo "  username=$ARGOCD_USER \\"
echo "  password=$ARGOCD_PASSWORD \\"
echo "  host=$PG_HOST \\"
echo "  port=5432 \\"
echo "  database=$ARGOCD_DB_NAME"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}⚠️  IMPORTANT: Store these credentials securely!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Save credentials to file
CREDS_FILE="/tmp/argocd-db-credentials-$(date +%Y%m%d-%H%M%S).txt"
cat > "$CREDS_FILE" <<EOF
ArgoCD PostgreSQL Credentials
=============================
Database: $ARGOCD_DB_NAME
Username: $ARGOCD_USER
Password: $ARGOCD_PASSWORD
Host:     $PG_HOST
Port:     5432

Vault Command:
kubectl exec -n vault-system vault-0 -- vault kv put secret/argocd/postgresql username=$ARGOCD_USER password=$ARGOCD_PASSWORD host=$PG_HOST port=5432 database=$ARGOCD_DB_NAME
EOF

echo "Credentials saved to: $CREDS_FILE"
echo -e "${YELLOW}⚠️  Remember to delete this file after storing in Vault!${NC}"
echo ""
echo -e "${GREEN}✅ ArgoCD database bootstrap complete${NC}"
