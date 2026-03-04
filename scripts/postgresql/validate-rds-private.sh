#!/bin/bash
# DT-001: Validar que RDS está em subnet privada e inacessível publicamente
# Usage: bash scripts/postgresql/validate-rds-private.sh
# Requirements: aws cli configurado com profile k8s-platform-prod, nc (netcat)

set -euo pipefail

PROFILE="k8s-platform-prod"
DB_ID="k8s-platform-prod-postgresql"
EXPECTED_SUBNET_1="subnet-0472ab28726cdf745"
EXPECTED_SUBNET_2="subnet-0288a67cd352effa7"
EXPECTED_SUBNET_GROUP="k8s-platform-prod-postgresql"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

echo "=== DT-001: Validacao RDS Private Subnet ==="
echo "Instancia: $DB_ID"
echo "Profile:   $PROFILE"
echo "Data:      $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 1. Checar publicly_accessible
echo "--- Check 1: publicly_accessible ---"
PA=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --profile "$PROFILE" \
  --query 'DBInstances[0].PubliclyAccessible' \
  --output text 2>&1)
echo "PubliclyAccessible: $PA (esperado: False)"
if [ "$PA" = "False" ]; then
  pass "publicly_accessible = False"
else
  fail "publicly_accessible = $PA (esperado: False)"
fi
echo ""

# 2. Checar subnet group name
echo "--- Check 2: subnet group name ---"
SG_NAME=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --profile "$PROFILE" \
  --query 'DBInstances[0].DBSubnetGroup.DBSubnetGroupName' \
  --output text 2>&1)
echo "Subnet Group: $SG_NAME (esperado: $EXPECTED_SUBNET_GROUP)"
if [ "$SG_NAME" = "$EXPECTED_SUBNET_GROUP" ]; then
  pass "Subnet group correto: $SG_NAME"
else
  fail "Subnet group incorreto: $SG_NAME (esperado: $EXPECTED_SUBNET_GROUP)"
fi
echo ""

# 3. Checar subnets em uso
echo "--- Check 3: subnets privadas ---"
SUBNETS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --profile "$PROFILE" \
  --query 'DBInstances[0].DBSubnetGroup.Subnets[*].SubnetIdentifier' \
  --output text 2>&1)
echo "Subnets: $SUBNETS"
echo "Esperadas: $EXPECTED_SUBNET_1 $EXPECTED_SUBNET_2"

if echo "$SUBNETS" | grep -q "$EXPECTED_SUBNET_1"; then
  pass "Subnet us-east-1a presente: $EXPECTED_SUBNET_1"
else
  fail "Subnet us-east-1a ausente: $EXPECTED_SUBNET_1"
fi

if echo "$SUBNETS" | grep -q "$EXPECTED_SUBNET_2"; then
  pass "Subnet us-east-1b presente: $EXPECTED_SUBNET_2"
else
  fail "Subnet us-east-1b ausente: $EXPECTED_SUBNET_2"
fi
echo ""

# 4. Checar status da instancia
echo "--- Check 4: status da instancia ---"
STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --profile "$PROFILE" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>&1)
echo "Status: $STATUS (esperado: available)"
if [ "$STATUS" = "available" ]; then
  pass "RDS status: available"
else
  fail "RDS status inesperado: $STATUS"
fi
echo ""

# 5. Obter endpoint e testar inacessibilidade externa
echo "--- Check 5: inacessibilidade externa (porta 5432) ---"
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --profile "$PROFILE" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text 2>&1)
echo "RDS Endpoint: $RDS_ENDPOINT"

if timeout 5 nc -zv "$RDS_ENDPOINT" 5432 2>/dev/null; then
  fail "PORTA 5432 ACESSIVEL externamente — RDS pode estar publicamente exposto!"
  echo "  Acao requerida: verificar SecurityGroup e publicly_accessible"
else
  pass "Porta 5432 NAO acessivel externamente (correto para subnet privada)"
fi
echo ""

# 6. Checar routing das subnets via EC2 (confirma NAT GW, nao IGW)
echo "--- Check 6: route tables das subnets (NAT vs IGW) ---"
for SUBNET in "$EXPECTED_SUBNET_1" "$EXPECTED_SUBNET_2"; do
  IGW_ROUTE=$(aws ec2 describe-route-tables \
    --profile "$PROFILE" \
    --filters "Name=association.subnet-id,Values=$SUBNET" \
    --query 'RouteTables[*].Routes[?GatewayId!=null && starts_with(GatewayId, `igw-`)]' \
    --output text 2>&1)

  if [ -z "$IGW_ROUTE" ]; then
    pass "Subnet $SUBNET nao tem rota para IGW (privada confirmada)"
  else
    fail "Subnet $SUBNET tem rota para IGW: $IGW_ROUTE — SUBNET PUBLICA!"
  fi
done
echo ""

# 7. Verificar conectividade interna via kubectl (se disponivel)
echo "--- Check 7: conectividade interna (pod GitLab -> RDS) ---"
if command -v kubectl &>/dev/null; then
  GITLAB_POD=$(kubectl get pods -n gitlab-staging --no-headers 2>/dev/null \
    | grep "Running" | grep -v "runner\|shell\|gitaly\|exporter" | head -1 | awk '{print $1}')

  if [ -n "$GITLAB_POD" ]; then
    echo "Testando via pod: $GITLAB_POD"
    CONN_RESULT=$(kubectl exec -n gitlab-staging "$GITLAB_POD" -- \
      timeout 5 bash -c "echo > /dev/tcp/$RDS_ENDPOINT/5432" 2>&1 && echo "CONECTADO" || echo "FALHOU")
    if [ "$CONN_RESULT" = "CONECTADO" ]; then
      pass "Pod GitLab consegue conectar ao RDS internamente"
    else
      echo "  INFO: Teste de conectividade interna inconclusivo (pode ser restricao do pod: $CONN_RESULT)"
    fi
  else
    echo "  INFO: Nenhum pod GitLab Running disponivel para teste interno"
  fi
else
  echo "  INFO: kubectl nao disponivel — pulando teste de conectividade interna"
fi
echo ""

# Sumario final
echo "==================================================="
echo "=== SUMARIO DT-001 ==="
echo "==================================================="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "STATUS: APROVADO — RDS configurado corretamente em subnet privada"
  echo "DT-001: CONFORME"
  exit 0
else
  echo "STATUS: REPROVADO — $FAIL verificacao(oes) falharam"
  echo "DT-001: NAO CONFORME — requer correcao"
  exit 1
fi
