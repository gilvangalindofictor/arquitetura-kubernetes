# Runbook: Rotacao Manual de Emergencia de Secrets

**Versao**: 1.0
**Data**: 2026-02-26
**Contexto**: CICD-003 | ADR-083
**SLA**: Execucao completa em < 5 minutos por credencial
**Quando usar**: CronJob com falha, credencial comprometida, ou rotacao manual solicitada

---

## Pre-requisitos

- `vault` CLI configurado (`VAULT_ADDR`, `VAULT_TOKEN` com policy `vault-admin`)
- `kubectl` configurado com acesso ao cluster `k8s-platform-prod`
- `psql` disponivel (para rotacao de senhas PostgreSQL)
- Acesso ao Keycloak Admin UI ou kcadm.sh (para rotacao de OIDC clients)

```bash
# Verificar acesso
vault token lookup
kubectl get nodes
psql --version 2>/dev/null || echo "psql nao disponivel"
```

---

## SECAO 1: Rotacao Manual de PostgreSQL

### 1.1 Rotacao de senha de usuario de aplicacao (gitlab, keycloak, harbor, sonarqube)

**Tempo estimado**: 3-5 minutos

```bash
# Parametros
APP="keycloak"          # opcoes: keycloak | gitlab | harbor | sonarqube
PG_USER="${APP}_user"
PG_DB="keycloak"        # keycloak | gitlabhq_production | registry | sonarqube
NS_WORKLOAD="staging-platform-keycloak"  # namespace da aplicacao
PG_HOST="k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com"
VAULT_PATH="secret/${APP}/postgresql"

# Ler senha admin RDS do Vault
PGPASSWORD_ADMIN=$(vault kv get -field=password secret/postgresql-admin/password)
PGUSER_ADMIN=$(vault kv get -field=username secret/postgresql-admin/password)

# Gerar nova senha
NEW_PASS=$(cat /dev/urandom | tr -dc 'A-Za-z0-9!#%^&*()-_' | head -c 32)
echo "Nova senha gerada (${#NEW_PASS} chars)"

# STEP 1: Alterar no RDS
psql "postgresql://${PGUSER_ADMIN}:${PGPASSWORD_ADMIN}@${PG_HOST}:5432/${PG_DB}?sslmode=require" \
  -c "ALTER USER ${PG_USER} WITH PASSWORD '${NEW_PASS}';" \
  -v ON_ERROR_STOP=1 && \
  echo "RDS: ALTER USER OK" || { echo "FALHA no RDS — abortando"; exit 1; }

# STEP 2: Atualizar Vault
vault kv patch "${VAULT_PATH}" \
  "password=${NEW_PASS}" \
  "rotated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "rotation_id=manual-$(date -u +%Y%m%d%H%M%S)" && \
  echo "Vault: KV atualizado OK" || \
  echo "ATENCAO: Vault write falhou — RDS alterado mas Vault desatualizado! Repetir step 2"

# STEP 3: Forcara re-sync do ESO
kubectl annotate externalsecret "${APP}-postgresql-credentials" \
  -n "${NS_WORKLOAD}" \
  force-sync=$(date +%s) --overwrite

# STEP 4: Aguardar sync e reiniciar workload
sleep 5
kubectl rollout restart deployment -n "${NS_WORKLOAD}"
kubectl rollout status deployment -n "${NS_WORKLOAD}" --timeout=120s

echo "Rotacao de ${APP} postgresql CONCLUIDA"
```

### 1.2 Rotacao rapida de todos os databases (script batch)

```bash
#!/bin/bash
# Executar apenas se voce quer rotacionar TODOS os databases de uma vez
PG_HOST="k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com"
PGPASSWORD_ADMIN=$(vault kv get -field=password secret/postgresql-admin/password)
PGUSER_ADMIN=$(vault kv get -field=username secret/postgresql-admin/password)
ROTATION_ID="manual-$(date -u +%Y%m%d%H%M%S)"

declare -A DB_MAP=(
  ["keycloak"]="keycloak_user:keycloak:staging-platform-keycloak"
  ["gitlab"]="gitlab_user:gitlabhq_production:staging-platform-gitlab"
  ["harbor"]="harbor_user:registry:harbor-system"
  ["sonarqube"]="sonarqube_user:sonarqube:staging-platform-sonarqube"
)

for app in "${!DB_MAP[@]}"; do
  IFS=: read -r pg_user pg_db ns_workload <<< "${DB_MAP[$app]}"
  new_pass=$(cat /dev/urandom | tr -dc 'A-Za-z0-9!#%^&*()-_' | head -c 32)

  echo "=== Rotacionando: $app ==="

  psql "postgresql://${PGUSER_ADMIN}:${PGPASSWORD_ADMIN}@${PG_HOST}:5432/${pg_db}?sslmode=require" \
    -c "ALTER USER ${pg_user} WITH PASSWORD '${new_pass}';" \
    -v ON_ERROR_STOP=1 || { echo "FALHA RDS para $app"; continue; }

  vault kv patch "secret/${app}/postgresql" \
    "password=${new_pass}" \
    "rotated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "rotation_id=${ROTATION_ID}" || \
    echo "ATENCAO: Vault write falhou para $app"

  kubectl annotate externalsecret "${app}-postgresql-credentials" \
    -n "${ns_workload}" force-sync=$(date +%s) --overwrite 2>/dev/null || true

  echo "  OK: $app rotacionado"
done

echo "Rotacao batch concluida. Reiniciar workloads apos ESO sync (aguardar ~60s)"
```

### 1.3 Rds manual alter user (sem psql disponivel — via pod temporario)

```bash
APP="keycloak"
PG_DB="keycloak"
PG_USER="keycloak_user"
PG_HOST="k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com"

# Ler nova senha do Vault (apos ter escrito via vault kv put)
NEW_PASS=$(vault kv get -field=password secret/${APP}/postgresql)

# Criar pod temporario postgres para executar ALTER USER
kubectl run pg-rotate-${APP} \
  --rm -it --restart=Never \
  -n staging-security-vault \
  --image=postgres:16-alpine \
  --env="PGPASSWORD=$(vault kv get -field=password secret/postgresql-admin/password)" \
  -- psql \
  "postgresql://$(vault kv get -field=username secret/postgresql-admin/password)@${PG_HOST}:5432/${PG_DB}?sslmode=require" \
  -c "ALTER USER ${PG_USER} WITH PASSWORD '${NEW_PASS}';"
```

---

## SECAO 2: Rotacao Manual da Senha de Admin Keycloak

**Tempo estimado**: 2 minutos

```bash
KEYCLOAK_URL="http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local"
KEYCLOAK_REALM="master"

# Ler credenciais atuais do Vault
KC_ADMIN_USER=$(vault kv get -field=username secret/keycloak/admin)
KC_ADMIN_PASS=$(vault kv get -field=password secret/keycloak/admin)

# Gerar nova senha
NEW_PASS=$(cat /dev/urandom | tr -dc 'A-Za-z0-9!#%^&*()-_' | head -c 32)

# Obter token admin
ADMIN_TOKEN=$(curl -s -X POST \
  "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli&username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASS}&grant_type=password" | \
  jq -r .access_token)

[ "$ADMIN_TOKEN" = "null" ] || [ -z "$ADMIN_TOKEN" ] && \
  { echo "FALHA ao obter token Keycloak"; exit 1; }

# Obter ID do usuario admin
ADMIN_USER_ID=$(curl -s \
  "${KEYCLOAK_URL}/admin/realms/master/users?username=${KC_ADMIN_USER}&exact=true" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" | \
  jq -r '.[0].id')

[ -z "$ADMIN_USER_ID" ] && { echo "FALHA ao encontrar user ID"; exit 1; }

# Alterar senha no Keycloak
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
  "${KEYCLOAK_URL}/admin/realms/master/users/${ADMIN_USER_ID}/reset-password" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"password\",\"value\":\"${NEW_PASS}\",\"temporary\":false}")

[ "$HTTP_CODE" = "204" ] && echo "Keycloak: senha alterada OK (HTTP 204)" || \
  { echo "FALHA Keycloak API: HTTP ${HTTP_CODE}"; exit 1; }

# Atualizar Vault
vault kv patch secret/keycloak/admin \
  "password=${NEW_PASS}" \
  "rotated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "rotation_id=manual-$(date -u +%Y%m%d%H%M%S)" && \
  echo "Vault: admin atualizado OK"

# Forcara re-sync ESO
kubectl annotate externalsecret keycloak-admin-credentials \
  -n staging-platform-keycloak \
  force-sync=$(date +%s) --overwrite

echo "Rotacao do Keycloak admin CONCLUIDA"
```

---

## SECAO 3: Rotacao Manual de OIDC Client Secrets

**Tempo estimado**: 2 minutos por client

```bash
# Parametros
CLIENT_NAME="grafana"   # grafana | argocd | harbor | gitlab | vault
VAULT_PATH="secret/${CLIENT_NAME}/oidc"
KEYCLOAK_REALM="platform"
KEYCLOAK_URL="http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local"

# Ler admin Keycloak do Vault
KC_ADMIN_USER=$(vault kv get -field=username secret/keycloak/admin)
KC_ADMIN_PASS=$(vault kv get -field=password secret/keycloak/admin)

# Obter token
ADMIN_TOKEN=$(curl -s -X POST \
  "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli&username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASS}&grant_type=password" | \
  jq -r .access_token)

# Obter UUID do client no realm platform
CLIENT_UUID=$(curl -s \
  "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${CLIENT_NAME}" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" | \
  jq -r '.[0].id')

[ -z "$CLIENT_UUID" ] && { echo "Client nao encontrado: $CLIENT_NAME"; exit 1; }
echo "Client UUID: $CLIENT_UUID"

# Regenerar secret no Keycloak
NEW_SECRET=$(curl -s -X POST \
  "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" | \
  jq -r .value)

[ -z "$NEW_SECRET" ] || [ "$NEW_SECRET" = "null" ] && \
  { echo "FALHA ao regenerar secret para $CLIENT_NAME"; exit 1; }

echo "Novo secret gerado para $CLIENT_NAME"

# Atualizar Vault
vault kv patch "${VAULT_PATH}" \
  "client_secret=${NEW_SECRET}" \
  "rotated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "rotation_id=manual-$(date -u +%Y%m%d%H%M%S)" && \
  echo "Vault: ${CLIENT_NAME}/oidc atualizado OK"

# Forcara re-sync ESO (localizar o ExternalSecret correto por namespace)
declare -A CLIENT_NS=(
  ["grafana"]="monitoring"
  ["argocd"]="argocd"
  ["harbor"]="harbor-system"
  ["gitlab"]="staging-platform-gitlab"
  ["vault"]="staging-security-vault"
)
NS="${CLIENT_NS[$CLIENT_NAME]}"
ES_NAME="${CLIENT_NAME}-oidc-credentials"

kubectl annotate externalsecret "${ES_NAME}" -n "${NS}" \
  force-sync=$(date +%s) --overwrite 2>/dev/null || \
  echo "ExternalSecret ${ES_NAME} nao encontrado em ${NS} — verificar nome correto"

# Reiniciar aplicacao apos ESO sync
sleep 10
kubectl rollout restart deployment -n "${NS}" -l "app.kubernetes.io/name=${CLIENT_NAME}" 2>/dev/null || \
  echo "Reiniciar manualmente os pods em $NS"

echo "Rotacao OIDC client '$CLIENT_NAME' CONCLUIDA"
```

---

## SECAO 4: Resposta a Credencial Comprometida (Breach Response)

**Objetivo**: Revogar credencial comprometida em < 5 minutos

### 4.1 Credencial de banco de dados comprometida

```bash
# URGENTE: alterar imediatamente (nao gerar nova, qualquer senha funciona para urgencia)
APP="gitlab"  # application afetada
EMERGENCY_PASS="$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 24)-EMERGENCY"
PG_HOST="k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com"

PGPASSWORD_ADMIN=$(vault kv get -field=password secret/postgresql-admin/password)
PGUSER_ADMIN=$(vault kv get -field=username secret/postgresql-admin/password)

# Revogar imediatamente no RDS
psql "postgresql://${PGUSER_ADMIN}:${PGPASSWORD_ADMIN}@${PG_HOST}:5432/postgres?sslmode=require" \
  -c "ALTER USER ${APP}_user WITH PASSWORD '${EMERGENCY_PASS}';" \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename='${APP}_user';"

echo "Credencial revogada e sessoes encerradas"

# Atualizar Vault (importante: antes de reiniciar workloads)
vault kv patch "secret/${APP}/postgresql" \
  "password=${EMERGENCY_PASS}" \
  "rotated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "rotation_id=breach-response-$(date -u +%Y%m%d%H%M%S)" \
  "note=BREACH_RESPONSE"

# Forcara re-sync e reiniciar
kubectl annotate externalsecret "${APP}-postgresql-credentials" \
  -n "staging-platform-${APP}" \
  force-sync=$(date +%s) --overwrite
sleep 15  # Aguardar ESO sync
kubectl rollout restart deployment -n "staging-platform-${APP}"

# Analisar CloudTrail para acesso suspeito
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=${APP}_user \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events[*].{Time:EventTime,Name:EventName,IP:CloudTrailEvent}' \
  --output table 2>/dev/null || \
  echo "CloudTrail lookup requer credenciais AWS"

# Registrar incidente no Vault
vault kv put "secret/secret-rotator/last-rotation" \
  "rotation_id=breach-response-$(date -u +%Y%m%d%H%M%S)" \
  "rotation_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "status=breach_response" \
  "affected=${APP}" \
  "note=CREDENCIAL_COMPROMETIDA_ROTACIONADA_MANUALMENTE"

echo "BREACH RESPONSE: credencial ${APP} revogada. Documentar incidente no logbook."
```

### 4.2 Vault token comprometido

```bash
# Revogar token imediatamente
vault token revoke <TOKEN_COMPROMETIDO>

# Criar novo token
NEW_TOKEN=$(vault token create \
  -policy=secret-rotator \
  -ttl=8760h \
  -renewable=true \
  -display-name=secret-rotator-cronjob-new \
  -format=json | jq -r .auth.client_token)

# Atualizar no Vault
vault kv put secret/secret-rotator/token token="${NEW_TOKEN}"

# Forcara re-sync ESO
kubectl annotate externalsecret secret-rotator-vault-token \
  -n staging-security-vault \
  force-sync=$(date +%s) --overwrite
```

---

## SECAO 5: Verificacao Pos-Rotacao

Executar apos qualquer rotacao manual:

```bash
echo "=== Verificacao pos-rotacao ==="

# 1. Pods em Running
echo "--- Status de pods criticos ---"
for ns in staging-platform-keycloak staging-platform-gitlab harbor-system monitoring staging-security-vault; do
  echo "Namespace: $ns"
  kubectl get pods -n $ns --no-headers | awk '{print $1, $3}' | column -t
  echo ""
done

# 2. ExternalSecrets sincronizados
echo "--- ExternalSecrets ---"
kubectl get externalsecret -A 2>/dev/null | grep -v "SecretSynced" | \
  grep -v "^NAMESPACE" || echo "Todos sincronizados"

# 3. Ultima rotacao no Vault
echo "--- Ultima rotacao registrada ---"
vault kv get secret/secret-rotator/last-rotation

# 4. Smoke test SSO (se servicos acessiveis)
echo "--- SSO health (interno) ---"
curl -s "http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local/health" | \
  python3 -m json.tool 2>/dev/null || echo "Keycloak health check nao acessivel externamente"

echo "=== Verificacao concluida ==="
```

---

## Referencias

- ADR-083: `docs/adr/adr-083-automated-secret-rotation-strategy.md`
- Troubleshooting do CronJob: `docs/runbooks/secret-rotation-troubleshooting.md`
- Politica de rotacao: `docs/runbooks/secret-rotation-policy.md`
- Script de rotacao automatica: `scripts/vault/rotate-secrets.sh`
