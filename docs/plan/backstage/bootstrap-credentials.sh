#!/usr/bin/env bash
# =============================================================================
# bootstrap-credentials.sh
# Backstage IDP - Bootstrap de Credenciais e Secrets no Vault
#
# Cluster:   EKS us-east-1 (k8s-platform-prod)
# Namespace: staging-platform-backstage
#
# Pre-requisitos:
#   - kubectl configurado e apontando para o cluster correto
#   - vault CLI autenticado (vault login ...)
#   - argocd CLI instalado
#   - curl disponivel
#   - psql instalado (ou acesso via pod no cluster)
#
# Uso:
#   chmod +x bootstrap-credentials.sh
#   ./bootstrap-credentials.sh [--section all|rds|keycloak|harbor|argocd|sonarqube]
#
# Idempotente: cada secao verifica se o recurso ja existe antes de criar.
# =============================================================================

set -euo pipefail

# =============================================================================
# VARIAVEIS DE CONFIGURACAO - AJUSTE CONFORME NECESSARIO
# =============================================================================

# --- RDS / PostgreSQL ---
RDS_HOST="k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com"
RDS_PORT="5432"
RDS_MASTER_USER="postgres"            # usuario master do RDS
RDS_MASTER_DB="postgres"              # banco default para conexao inicial
BACKSTAGE_DB_NAME="backstage"
BACKSTAGE_DB_USER="backstage"
BACKSTAGE_DB_PASSWORD="${BACKSTAGE_DB_PASSWORD:-}"  # preencher ou exportar antes de rodar

# --- Keycloak ---
KEYCLOAK_URL="http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local"
KEYCLOAK_REALM="master"               # realm onde o client sera criado
KEYCLOAK_BACKSTAGE_REALM="platform"  # realm para autenticacao do Backstage (ajustar se necessario)
KEYCLOAK_ADMIN_USER="admin"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-}"  # preencher ou exportar
BACKSTAGE_KEYCLOAK_CLIENT_ID="backstage"
BACKSTAGE_KEYCLOAK_REDIRECT_URI="https://backstage.staging.internal/api/auth/oidc/handler/frame"

# --- Harbor ---
HARBOR_URL="http://harbor-core.staging-platform-harbor.svc.cluster.local"
HARBOR_ADMIN_USER="admin"
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:-}"  # preencher ou exportar
HARBOR_ROBOT_NAME="backstage"
HARBOR_ROBOT_DESCRIPTION="Robot account para Backstage IDP"
HARBOR_PROJECT_ID=1                  # 0 = system-level; ajustar se for project-scoped

# --- ArgoCD ---
ARGOCD_SERVER="argocd-server.staging-platform-argocd.svc.cluster.local:443"
ARGOCD_NAMESPACE="staging-platform-argocd"
ARGOCD_ADMIN_SECRET="argocd-initial-admin-secret"
ARGOCD_BACKSTAGE_ACCOUNT="backstage"
ARGOCD_TOKEN_ID="backstage-token"

# --- SonarQube ---
SONARQUBE_URL="http://sonarqube-sonarqube.staging-platform-sonarqube.svc.cluster.local:9000"
SONARQUBE_ADMIN_USER="admin"
SONARQUBE_ADMIN_PASSWORD="${SONARQUBE_ADMIN_PASSWORD:-}"  # preencher ou exportar
SONARQUBE_TOKEN_NAME="backstage-token"

# --- Vault ---
VAULT_ADDR="${VAULT_ADDR:-http://vault.staging-platform-vault.svc.cluster.local:8200}"
VAULT_PREFIX="secret/staging/backstage"

# --- GitLab (instrucoes manuais - nao automatizado) ---
GITLAB_URL="https://gitlab.staging.internal"
GITLAB_GROUP="platform"              # grupo para o Group Access Token
GITLAB_TOKEN_NAME="backstage"
GITLAB_TOKEN_SCOPES="read_api,read_repository,write_repository,api"

# =============================================================================
# FUNCOES AUXILIARES
# =============================================================================

log()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
warn() { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
err()  { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; exit 1; }

require_var() {
  local var_name="$1"
  local val="${!var_name:-}"
  if [[ -z "$val" ]]; then
    err "Variavel obrigatoria '$var_name' nao definida. Exporte-a antes de executar o script."
  fi
}

vault_write() {
  local path="$1"; shift
  log "Vault: escrevendo em $path"
  vault kv put "$path" "$@"
}

vault_path_exists() {
  local path="$1"
  vault kv get "$path" > /dev/null 2>&1
}

# =============================================================================
# SECAO 1: RDS - Criar schema e usuario backstage
# =============================================================================
section_rds() {
  log "====== SECAO RDS: Criacao de schema e usuario backstage ======"
  require_var "RDS_MASTER_USER"
  require_var "BACKSTAGE_DB_PASSWORD"

  # Exportar PGPASSWORD para evitar prompt interativo
  export PGPASSWORD="${PGPASSWORD_MASTER:-$BACKSTAGE_DB_PASSWORD}"
  warn "ATENCAO: PGPASSWORD_MASTER deve ser a senha do usuario master RDS, nao a senha do backstage."
  warn "Exporte PGPASSWORD_MASTER=<senha_master_rds> antes de rodar esta secao."

  PSQL_CMD="psql -h $RDS_HOST -p $RDS_PORT -U $RDS_MASTER_USER -d $RDS_MASTER_DB"

  # Verificar se usuario ja existe
  USER_EXISTS=$($PSQL_CMD -tAc "SELECT 1 FROM pg_roles WHERE rolname='$BACKSTAGE_DB_USER'" 2>/dev/null || echo "0")
  if [[ "$USER_EXISTS" == "1" ]]; then
    log "Usuario '$BACKSTAGE_DB_USER' ja existe no RDS. Pulando criacao."
  else
    log "Criando usuario '$BACKSTAGE_DB_USER' no RDS..."
    $PSQL_CMD -c "CREATE USER $BACKSTAGE_DB_USER WITH PASSWORD '$BACKSTAGE_DB_PASSWORD';"
    log "Usuario criado."
  fi

  # Verificar se database ja existe
  DB_EXISTS=$($PSQL_CMD -tAc "SELECT 1 FROM pg_database WHERE datname='$BACKSTAGE_DB_NAME'" 2>/dev/null || echo "0")
  if [[ "$DB_EXISTS" == "1" ]]; then
    log "Database '$BACKSTAGE_DB_NAME' ja existe. Pulando criacao."
  else
    log "Criando database '$BACKSTAGE_DB_NAME'..."
    $PSQL_CMD -c "CREATE DATABASE $BACKSTAGE_DB_NAME OWNER $BACKSTAGE_DB_USER;"
    log "Database criado."
  fi

  # Garantir privilegios
  $PSQL_CMD -c "GRANT ALL PRIVILEGES ON DATABASE $BACKSTAGE_DB_NAME TO $BACKSTAGE_DB_USER;"
  log "Privilegios garantidos."

  # Escrever no Vault
  vault_write "${VAULT_PREFIX}/database" \
    host="$RDS_HOST" \
    port="$RDS_PORT" \
    database="$BACKSTAGE_DB_NAME" \
    username="$BACKSTAGE_DB_USER" \
    password="$BACKSTAGE_DB_PASSWORD"

  log "RDS: credenciais salvas em ${VAULT_PREFIX}/database"
}

# =============================================================================
# SECAO 2: Keycloak - Criar client backstage via API
# =============================================================================
section_keycloak() {
  log "====== SECAO KEYCLOAK: Criacao de client para Backstage ======"
  require_var "KEYCLOAK_ADMIN_PASSWORD"

  # Obter token admin
  log "Obtendo token admin do Keycloak..."
  KC_TOKEN=$(curl -sf -X POST \
    "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${KEYCLOAK_ADMIN_USER}" \
    -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    | jq -r '.access_token')

  if [[ -z "$KC_TOKEN" || "$KC_TOKEN" == "null" ]]; then
    err "Falha ao obter token admin do Keycloak. Verifique KEYCLOAK_ADMIN_PASSWORD e conectividade."
  fi

  AUTH_HEADER="Authorization: Bearer $KC_TOKEN"

  # Verificar se client ja existe no realm de backstage
  log "Verificando se client '$BACKSTAGE_KEYCLOAK_CLIENT_ID' ja existe no realm '$KEYCLOAK_BACKSTAGE_REALM'..."
  EXISTING=$(curl -sf \
    "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_BACKSTAGE_REALM}/clients?clientId=${BACKSTAGE_KEYCLOAK_CLIENT_ID}" \
    -H "$AUTH_HEADER" | jq '. | length')

  if [[ "$EXISTING" -gt 0 ]]; then
    log "Client '$BACKSTAGE_KEYCLOAK_CLIENT_ID' ja existe no realm '$KEYCLOAK_BACKSTAGE_REALM'. Pulando criacao."
    CLIENT_ID_INTERNAL=$(curl -sf \
      "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_BACKSTAGE_REALM}/clients?clientId=${BACKSTAGE_KEYCLOAK_CLIENT_ID}" \
      -H "$AUTH_HEADER" | jq -r '.[0].id')
  else
    log "Criando client '$BACKSTAGE_KEYCLOAK_CLIENT_ID' no realm '$KEYCLOAK_BACKSTAGE_REALM'..."
    CREATE_RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
      "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_BACKSTAGE_REALM}/clients" \
      -H "$AUTH_HEADER" \
      -H "Content-Type: application/json" \
      -d "{
        \"clientId\": \"${BACKSTAGE_KEYCLOAK_CLIENT_ID}\",
        \"name\": \"Backstage IDP\",
        \"enabled\": true,
        \"protocol\": \"openid-connect\",
        \"publicClient\": false,
        \"standardFlowEnabled\": true,
        \"implicitFlowEnabled\": false,
        \"directAccessGrantsEnabled\": false,
        \"serviceAccountsEnabled\": false,
        \"redirectUris\": [\"${BACKSTAGE_KEYCLOAK_REDIRECT_URI}\"],
        \"webOrigins\": [\"+\"]
      }")
    if [[ "$CREATE_RESP" != "201" ]]; then
      err "Falha ao criar client no Keycloak. HTTP: $CREATE_RESP"
    fi
    CLIENT_ID_INTERNAL=$(curl -sf \
      "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_BACKSTAGE_REALM}/clients?clientId=${BACKSTAGE_KEYCLOAK_CLIENT_ID}" \
      -H "$AUTH_HEADER" | jq -r '.[0].id')
    log "Client criado. Internal ID: $CLIENT_ID_INTERNAL"
  fi

  # Obter client secret
  CLIENT_SECRET=$(curl -sf \
    "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_BACKSTAGE_REALM}/clients/${CLIENT_ID_INTERNAL}/client-secret" \
    -H "$AUTH_HEADER" | jq -r '.value')

  if [[ -z "$CLIENT_SECRET" || "$CLIENT_SECRET" == "null" ]]; then
    log "Regenerando client secret..."
    CLIENT_SECRET=$(curl -sf -X POST \
      "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_BACKSTAGE_REALM}/clients/${CLIENT_ID_INTERNAL}/client-secret" \
      -H "$AUTH_HEADER" | jq -r '.value')
  fi

  KC_ISSUER="${KEYCLOAK_URL}/realms/${KEYCLOAK_BACKSTAGE_REALM}"

  vault_write "${VAULT_PREFIX}/keycloak" \
    clientId="$BACKSTAGE_KEYCLOAK_CLIENT_ID" \
    clientSecret="$CLIENT_SECRET" \
    issuer="$KC_ISSUER" \
    realm="$KEYCLOAK_BACKSTAGE_REALM"

  log "Keycloak: credenciais salvas em ${VAULT_PREFIX}/keycloak"
}

# =============================================================================
# SECAO 3: Harbor - Criar robot account para backstage via API
# =============================================================================
section_harbor() {
  log "====== SECAO HARBOR: Criacao de robot account para Backstage ======"
  require_var "HARBOR_ADMIN_PASSWORD"

  HARBOR_AUTH=$(echo -n "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" | base64)

  # Verificar se robot ja existe (system-level robots)
  log "Verificando robot accounts existentes..."
  EXISTING_ROBOT=$(curl -sf \
    "${HARBOR_URL}/api/v2.0/robots" \
    -H "Authorization: Basic $HARBOR_AUTH" \
    -H "X-Request-Id: bootstrap-check" \
    | jq --arg name "robot\$${HARBOR_ROBOT_NAME}" '.[] | select(.name == $name) | .id' 2>/dev/null || echo "")

  if [[ -n "$EXISTING_ROBOT" ]]; then
    log "Robot account 'robot\$${HARBOR_ROBOT_NAME}' ja existe (ID: $EXISTING_ROBOT). Pulando criacao."
    warn "Para renovar o token, delete o robot manualmente e re-execute esta secao."
    warn "Harbor robot secret NAO foi atualizado no Vault."
    return 0
  fi

  log "Criando robot account 'robot\$${HARBOR_ROBOT_NAME}'..."
  ROBOT_RESP=$(curl -sf -X POST \
    "${HARBOR_URL}/api/v2.0/robots" \
    -H "Authorization: Basic $HARBOR_AUTH" \
    -H "Content-Type: application/json" \
    -H "X-Request-Id: bootstrap-create" \
    -d "{
      \"name\": \"${HARBOR_ROBOT_NAME}\",
      \"description\": \"${HARBOR_ROBOT_DESCRIPTION}\",
      \"level\": \"system\",
      \"duration\": -1,
      \"permissions\": [
        {
          \"kind\": \"system\",
          \"namespace\": \"/\",
          \"access\": [
            {\"resource\": \"repository\", \"action\": \"pull\"},
            {\"resource\": \"repository\", \"action\": \"push\"},
            {\"resource\": \"catalog\",    \"action\": \"read\"}
          ]
        }
      ]
    }")

  ROBOT_NAME=$(echo "$ROBOT_RESP" | jq -r '.name')
  ROBOT_SECRET=$(echo "$ROBOT_RESP" | jq -r '.secret')

  if [[ -z "$ROBOT_SECRET" || "$ROBOT_SECRET" == "null" ]]; then
    err "Falha ao criar robot account no Harbor. Resposta: $ROBOT_RESP"
  fi

  vault_write "${VAULT_PREFIX}/harbor" \
    robotName="$ROBOT_NAME" \
    robotSecret="$ROBOT_SECRET" \
    url="${HARBOR_URL}"

  log "Harbor: credenciais salvas em ${VAULT_PREFIX}/harbor"
}

# =============================================================================
# SECAO 3.B: Harbor - Criar robot account backstage-puller (Scaffolder M2)
# GAP-002: robot account dedicado para Scaffolder criar/push imagens base
# =============================================================================
create_harbor_robot() {
  log "====== SECAO HARBOR SCAFFOLDER: Criacao de robot account backstage-puller ======"
  require_var "HARBOR_ADMIN_PASSWORD"

  local HARBOR_ADMIN_PASS="${HARBOR_ADMIN_PASSWORD}"

  # Robot account com pull (leitura) e push (escritura para Scaffolder criar imagens base)
  local robot_payload
  robot_payload=$(cat <<'JSON'
{
  "name": "backstage-puller",
  "description": "Backstage IDP — Harbor plugin read + Scaffolder push base images",
  "disable": false,
  "duration": -1,
  "permissions": [
    {
      "kind": "system",
      "namespace": "/",
      "access": [
        {"resource": "repository", "action": "pull"},
        {"resource": "repository", "action": "push"},
        {"resource": "repository", "action": "read"}
      ]
    }
  ]
}
JSON
)

  local response
  response=$(curl -sf -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASS}" \
    -X POST "${HARBOR_URL}/api/v2.0/robots" \
    -H "Content-Type: application/json" \
    -d "$robot_payload" 2>/dev/null || echo "{}")

  local robot_token
  robot_token=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('secret',''))" 2>/dev/null || echo "")

  if [[ -n "$robot_token" ]]; then
    log "  Harbor robot account 'backstage-puller' criado. Armazenando token no Vault..."
    vault_write "${VAULT_PREFIX}/harbor" \
      url="${HARBOR_URL}" \
      robot-token="${robot_token}"
    log "  Harbor: OK (token armazenado em ${VAULT_PREFIX}/harbor)"
  else
    local robot_name
    robot_name=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('name',''))" 2>/dev/null || echo "")
    if [[ "$robot_name" == *"backstage-puller"* ]]; then
      warn "Harbor robot account 'backstage-puller' ja existe (token nao disponivel para reutilizacao)."
      warn "Para renovar: delete o robot em Harbor → Admin → Robot Accounts e re-execute."
    else
      warn "Harbor robot account pode ja existir ou criacao falhou."
      warn "Resposta: $response"
      warn "ACAO NECESSARIA: Criar manualmente em Harbor → Admin → Robot Accounts"
      warn "  Name: backstage-puller | Scopes: Pull + Push"
    fi
  fi
}

# =============================================================================
# SECAO 4: ArgoCD - Gerar token via argocd CLI
# =============================================================================
section_argocd() {
  log "====== SECAO ARGOCD: Geracao de token para Backstage ======"

  # Obter senha admin do secret
  ARGOCD_ADMIN_PASSWORD=$(kubectl get secret "$ARGOCD_ADMIN_SECRET" \
    -n "$ARGOCD_NAMESPACE" \
    -o jsonpath='{.data.password}' | base64 -d)

  if [[ -z "$ARGOCD_ADMIN_PASSWORD" ]]; then
    err "Nao foi possivel obter a senha admin do ArgoCD do secret '$ARGOCD_ADMIN_SECRET'."
  fi

  # Login no ArgoCD
  log "Fazendo login no ArgoCD..."
  argocd login "$ARGOCD_SERVER" \
    --username admin \
    --password "$ARGOCD_ADMIN_PASSWORD" \
    --insecure \
    --grpc-web

  # Verificar se conta backstage ja existe
  ACCOUNT_EXISTS=$(argocd account list --grpc-web 2>/dev/null | grep -w "$ARGOCD_BACKSTAGE_ACCOUNT" || echo "")

  if [[ -z "$ACCOUNT_EXISTS" ]]; then
    warn "Conta '$ARGOCD_BACKSTAGE_ACCOUNT' nao encontrada no ArgoCD."
    warn "Adicione ao ConfigMap argocd-cm:"
    warn "  accounts.$ARGOCD_BACKSTAGE_ACCOUNT: apiKey,login"
    warn "  accounts.$ARGOCD_BACKSTAGE_ACCOUNT.enabled: \"true\""
    warn "E ao argocd-rbac-cm:"
    warn "  p, role:backstage, applications, get, */*, allow"
    warn "  p, role:backstage, applications, list, */*, allow"
    warn "  g, $ARGOCD_BACKSTAGE_ACCOUNT, role:backstage"
    warn "Depois re-execute esta secao."
    return 0
  fi

  # Gerar token (tokens nao tem idempotencia nativa; sempre gera um novo)
  log "Gerando token para conta '$ARGOCD_BACKSTAGE_ACCOUNT'..."
  ARGOCD_TOKEN=$(argocd account generate-token \
    --account "$ARGOCD_BACKSTAGE_ACCOUNT" \
    --id "$ARGOCD_TOKEN_ID" \
    --grpc-web)

  if [[ -z "$ARGOCD_TOKEN" ]]; then
    err "Falha ao gerar token ArgoCD."
  fi

  vault_write "${VAULT_PREFIX}/argocd" \
    token="$ARGOCD_TOKEN" \
    server="https://${ARGOCD_SERVER}" \
    account="$ARGOCD_BACKSTAGE_ACCOUNT"

  log "ArgoCD: token salvo em ${VAULT_PREFIX}/argocd"

  # Gerar token para SA backstage-scaffolder (Scaffolder — create Applications)
  # Pre-requisito: argocd-scaffolder-sa.yaml aplicado no cluster
  log "ArgoCD: Gerando token para backstage-scaffolder..."
  ARGOCD_SCAFFOLDER_TOKEN=$(kubectl get secret backstage-scaffolder-token \
    -n "$ARGOCD_NAMESPACE" \
    -o jsonpath='{.data.token}' | base64 -d 2>/dev/null || echo "")

  if [[ -n "$ARGOCD_SCAFFOLDER_TOKEN" ]]; then
    vault_write "${VAULT_PREFIX}/argocd-scaffolder" \
      url="https://${ARGOCD_SERVER}" \
      token="$ARGOCD_SCAFFOLDER_TOKEN"
    log "ArgoCD: token scaffolder salvo em ${VAULT_PREFIX}/argocd-scaffolder"
  else
    warn "Secret 'backstage-scaffolder-token' nao encontrado em '$ARGOCD_NAMESPACE'."
    warn "Pre-requisito: kubectl apply -f argocd-scaffolder-sa.yaml"
    warn "ArgoCD scaffolder token NAO salvo no Vault."
  fi
}

# =============================================================================
# SECAO 5: SonarQube - Gerar token via API
# =============================================================================
section_sonarqube() {
  log "====== SECAO SONARQUBE: Geracao de token para Backstage ======"
  require_var "SONARQUBE_ADMIN_PASSWORD"

  SONAR_AUTH=$(echo -n "${SONARQUBE_ADMIN_USER}:${SONARQUBE_ADMIN_PASSWORD}" | base64)

  # Verificar se token ja existe
  log "Verificando tokens existentes no SonarQube..."
  EXISTING_TOKEN=$(curl -sf \
    "${SONARQUBE_URL}/api/user_tokens/search" \
    -H "Authorization: Basic $SONAR_AUTH" \
    | jq --arg name "$SONARQUBE_TOKEN_NAME" '.userTokens[] | select(.name == $name) | .name' 2>/dev/null || echo "")

  if [[ -n "$EXISTING_TOKEN" ]]; then
    log "Token '$SONARQUBE_TOKEN_NAME' ja existe no SonarQube."
    warn "Para renovar, revogue o token manualmente e re-execute esta secao."
    warn "SonarQube token NAO foi atualizado no Vault."
    return 0
  fi

  log "Gerando token '$SONARQUBE_TOKEN_NAME' no SonarQube..."
  TOKEN_RESP=$(curl -sf -X POST \
    "${SONARQUBE_URL}/api/user_tokens/generate" \
    -H "Authorization: Basic $SONAR_AUTH" \
    -d "name=${SONARQUBE_TOKEN_NAME}&type=GLOBAL_ANALYSIS_TOKEN")

  SONAR_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.token')

  if [[ -z "$SONAR_TOKEN" || "$SONAR_TOKEN" == "null" ]]; then
    err "Falha ao gerar token SonarQube. Resposta: $TOKEN_RESP"
  fi

  vault_write "${VAULT_PREFIX}/sonarqube" \
    token="$SONAR_TOKEN" \
    url="${SONARQUBE_URL}" \
    tokenName="$SONARQUBE_TOKEN_NAME"

  log "SonarQube: token salvo em ${VAULT_PREFIX}/sonarqube"
}

# =============================================================================
# SECAO 6: GitLab - Instrucoes manuais (Group Access Token nao disponivel via API publica)
# =============================================================================
section_gitlab() {
  log "====== SECAO GITLAB: Instrucoes para criacao manual do Group Access Token ======"
  cat <<'INSTRUCTIONS'

  ACAO MANUAL NECESSARIA - GitLab Group Access Token:
  =====================================================
  O GitLab Group Access Token deve ser criado manualmente via UI:

  1. Acesse: https://gitlab.staging.internal
  2. Navegue para: Groups > platform > Settings > Access Tokens
     (ou o grupo de sua organizacao)
  3. Clique em "Add new token"
  4. Preencha:
     - Token name:   backstage
     - Expiration:   (defina conforme politica, sugerido 1 ano)
     - Role:         Reporter (minimo) ou Developer
     - Scopes:       [x] api  [x] read_api  [x] read_repository  [x] write_repository
                     (api: necessario para Scaffolder M2 criar repositorios via API)
  5. Clique em "Create group access token"
  6. COPIE o token gerado (visivel apenas uma vez)

  Apos obter o token, execute:
  -------------------------------------------------------
  vault kv put secret/staging/backstage/gitlab \
    token="<COLE_O_TOKEN_AQUI>" \
    url="https://gitlab.staging.internal" \
    tokenName="backstage"
  -------------------------------------------------------

INSTRUCTIONS
}

# =============================================================================
# SECAO 7: Verificar todos os paths Vault ao final
# =============================================================================
section_verify_vault() {
  log "====== VERIFICACAO FINAL: Paths no Vault ======"
  local paths=(
    "${VAULT_PREFIX}/database"
    "${VAULT_PREFIX}/keycloak"
    "${VAULT_PREFIX}/harbor"
    "${VAULT_PREFIX}/argocd"
    "${VAULT_PREFIX}/sonarqube"
    "${VAULT_PREFIX}/gitlab"
    "${VAULT_PREFIX}/argocd-scaffolder"
  )
  for p in "${paths[@]}"; do
    if vault_path_exists "$p"; then
      log "OK  $p"
    else
      warn "FALTANDO  $p"
    fi
  done
}

# =============================================================================
# ENTRY POINT
# =============================================================================
SECTION="${1:-all}"

case "$SECTION" in
  all)
    section_rds
    section_keycloak
    section_harbor
    create_harbor_robot
    section_argocd
    section_sonarqube
    section_gitlab
    section_verify_vault
    ;;
  rds)       section_rds ;;
  keycloak)  section_keycloak ;;
  harbor)             section_harbor ;;
  harbor-scaffolder)  create_harbor_robot ;;
  argocd)             section_argocd ;;
  sonarqube) section_sonarqube ;;
  gitlab)    section_gitlab ;;
  verify)    section_verify_vault ;;
  *)
    echo "Uso: $0 [all|rds|keycloak|harbor|harbor-scaffolder|argocd|sonarqube|gitlab|verify]"
    exit 1
    ;;
esac

log "Bootstrap concluido para secao: $SECTION"
