#!/usr/bin/env bash
# =============================================================================
# bootstrap-vault-setup.sh — Configuração do Vault para o Backstage IDP
# Cluster:    k8s-platform-prod (EKS us-east-1, conta 891377105802)
# Vault:      http://vault.staging-security-vault.svc.cluster.local:8200
#             Ingress: vault.staging.internal
# Criado:     2026-03-05
# ADR:        ADR-055
#
# PRÉ-REQUISITO: VAULT_TOKEN com permissões de admin (sys/auth, sys/policies, kv write)
#
# Uso:
#   export VAULT_TOKEN="<admin-token>"
#   export VAULT_ADDR="http://vault.staging-security-vault.svc.cluster.local:8200"
#   bash bootstrap-vault-setup.sh
#
# DRY_RUN=true bash bootstrap-vault-setup.sh   # só valida, não escreve
# =============================================================================

set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"
VAULT_ADDR="${VAULT_ADDR:-http://vault.staging-security-vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

# ─── Endpoints do cluster (descobertos automaticamente) ─────────────────────
EKS_CLUSTER_URL="https://EC913B145BF356481CBE823532F09150.gr7.us-east-1.eks.amazonaws.com"
ARGOCD_URL="https://argocd.staging.internal"
SONARQUBE_URL="https://sonarqube.staging.internal"
HARBOR_URL="https://harbor.staging.internal"
KEYCLOAK_URL="https://keycloak.staging.internal"
VAULT_INTERNAL_URL="http://vault.staging-security-vault.svc.cluster.local:8200"

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }
maybe_run() { if [ "$DRY_RUN" = "true" ]; then echo "[DRY-RUN] $*"; else "$@"; fi; }

# ─── Pré-checks ─────────────────────────────────────────────────────────────
preflight() {
  [ -z "$VAULT_TOKEN" ] && die "VAULT_TOKEN não definido. Export antes de executar."
  command -v vault >/dev/null || die "vault CLI não encontrado"
  command -v kubectl >/dev/null || die "kubectl não encontrado"

  export VAULT_ADDR VAULT_TOKEN

  log "Testando conectividade ao Vault..."
  vault token lookup >/dev/null 2>&1 || die "Token Vault inválido ou Vault inacessível"
  log "Vault: OK (token válido)"
}

# ─── PASSO 1: Criar policy backstage-policy ─────────────────────────────────
create_vault_policy() {
  log "PASSO 1: Criando policy backstage-policy..."
  maybe_run vault policy write backstage-policy - <<'HCL'
# Policy do Backstage IDP (ADR-055)
# Listar paths (plugin Vault UI)
path "secret/metadata/*" {
  capabilities = ["list"]
}
# Ler integrações da plataforma
path "secret/data/platform/integrations/*" {
  capabilities = ["read"]
}
# Ler e listar secrets do próprio Backstage
path "secret/data/staging/backstage/*" {
  capabilities = ["read"]
}
path "secret/metadata/staging/backstage/*" {
  capabilities = ["list"]
}
# Scaffolder: escrever skeleton de nova app
path "secret/data/staging/+/*" {
  capabilities = ["create", "update"]
}
path "secret/metadata/staging/+/*" {
  capabilities = ["list"]
}
# Scaffolder: criar policy por app
path "sys/policies/acl/app-*" {
  capabilities = ["create", "update", "read"]
}
# Scaffolder: criar AppRole por app
path "auth/approle/role/app-*" {
  capabilities = ["create", "update", "read"]
}
HCL
  log "Policy backstage-policy: OK"
}

# ─── PASSO 2: Criar role Kubernetes auth ────────────────────────────────────
create_k8s_auth_role() {
  log "PASSO 2: Criando role Kubernetes auth para backstage..."
  maybe_run vault write auth/kubernetes/role/backstage \
    bound_service_account_names=backstage \
    bound_service_account_namespaces=staging-platform-backstage \
    policies=backstage-policy \
    ttl=1h
  log "Role auth/kubernetes/role/backstage: OK"
}

# ─── PASSO 3: Escrever paths Vault com credenciais ──────────────────────────
# ATENÇÃO: substitua os PLACEHOLDERs antes de executar
write_vault_paths() {
  log "PASSO 3: Escrevendo paths Vault para Backstage..."

  # -- 3.1 RDS PostgreSQL --
  # Obter endpoint RDS real:
  #   aws rds describe-db-instances --profile k8s-platform-prod --region us-east-1 \
  #     --query 'DBInstances[*].Endpoint.Address' --output text
  RDS_HOST="${RDS_HOST:-PLACEHOLDER_RDS_ENDPOINT}"
  RDS_USER="${RDS_USER:-backstage}"
  RDS_PASS="${RDS_PASS:-$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)}"

  maybe_run vault kv put secret/staging/backstage/database \
    postgres-host="$RDS_HOST" \
    postgres-user="$RDS_USER" \
    postgres-password="$RDS_PASS" \
    postgres-port="5432"
  log "  secret/staging/backstage/database: OK"

  # -- 3.2 Keycloak (preencher após criar o client) --
  # Executar: bash bootstrap-credentials.sh → seção Keycloak
  KC_CLIENT_SECRET="${KC_CLIENT_SECRET:-PLACEHOLDER_KEYCLOAK_CLIENT_SECRET}"
  maybe_run vault kv put secret/staging/backstage/keycloak \
    client-id="backstage" \
    client-secret="$KC_CLIENT_SECRET"
  log "  secret/staging/backstage/keycloak: OK"

  # -- 3.3 GitLab Group Access Token --
  # Criar manualmente: GitLab → Group → Settings → Access Tokens
  # Scopes: read_api, read_repository, read_registry
  GITLAB_TOKEN="${GITLAB_TOKEN:-PLACEHOLDER_GITLAB_GROUP_ACCESS_TOKEN}"
  maybe_run vault kv put secret/staging/backstage/gitlab \
    token="$GITLAB_TOKEN"
  log "  secret/staging/backstage/gitlab: OK"

  # -- 3.4 ArgoCD --
  # Gerar: argocd account generate-token --account backstage-readonly
  # Ou via API: POST /api/v1/session + GET /api/v1/account/backstage/token
  ARGOCD_TOKEN="${ARGOCD_TOKEN:-PLACEHOLDER_ARGOCD_API_TOKEN}"
  maybe_run vault kv put secret/staging/backstage/argocd \
    url="$ARGOCD_URL" \
    token="$ARGOCD_TOKEN"
  log "  secret/staging/backstage/argocd: OK"

  # -- 3.5 SonarQube --
  # Gerar: SonarQube → Admin → Security → Global Analysis Token
  SONAR_TOKEN="${SONAR_TOKEN:-PLACEHOLDER_SONARQUBE_TOKEN}"
  maybe_run vault kv put secret/staging/backstage/sonarqube \
    url="$SONARQUBE_URL" \
    token="$SONAR_TOKEN"
  log "  secret/staging/backstage/sonarqube: OK"

  # -- 3.6 Vault (endereço interno para plugin) --
  maybe_run vault kv put secret/staging/backstage/vault \
    addr="$VAULT_INTERNAL_URL"
  log "  secret/staging/backstage/vault: OK"

  # -- 3.7 EKS cluster URL (plugin Kubernetes) --
  maybe_run vault kv put secret/staging/backstage/eks \
    cluster-url="$EKS_CLUSTER_URL"
  log "  secret/staging/backstage/eks: OK"

  # -- 3.8 Session secret (gerado automaticamente) --
  SESSION_SECRET="${SESSION_SECRET:-$(openssl rand -base64 32)}"
  maybe_run vault kv put secret/staging/backstage/session \
    auth-session-secret="$SESSION_SECRET"
  log "  secret/staging/backstage/session: OK"

  # -- 3.9 Harbor robot account (M2 Scaffolder + Harbor plugin) --
  # Criar manualmente: Harbor → Admin → Robot Accounts → New Robot Account
  # Name: backstage-puller  | Scopes: Pull(push para M2 criar novas imagens base)
  # Após criar: copiar o token gerado
  HARBOR_ROBOT_TOKEN="${HARBOR_ROBOT_TOKEN:-PLACEHOLDER_HARBOR_ROBOT_TOKEN}"
  maybe_run vault kv put secret/staging/backstage/harbor \
    url="${HARBOR_URL}" \
    robot-token="${HARBOR_ROBOT_TOKEN}"
  log "  secret/staging/backstage/harbor: OK"
}

# ─── PASSO 4: Criar schema backstage no RDS ─────────────────────────────────
create_rds_schema() {
  log "PASSO 4: Criando schema backstage no RDS..."
  log "  AÇÃO MANUAL NECESSÁRIA:"
  log "  1. Obter endpoint RDS:"
  log "     aws rds describe-db-instances --profile k8s-platform-prod --region us-east-1 \\"
  log "       --query 'DBInstances[*].{Id:DBInstanceIdentifier,Endpoint:Endpoint.Address}' --output table"
  log "  2. Criar user e database:"
  log "     psql 'postgresql://admin:<pass>@<rds-endpoint>:5432/postgres?sslmode=require' \\"
  log "       -c \"CREATE USER backstage WITH PASSWORD '<RDS_PASS_DO_PASSO_3.1>';\""
  log "     psql 'postgresql://admin:<pass>@<rds-endpoint>:5432/postgres?sslmode=require' \\"
  log "       -c \"CREATE DATABASE backstage OWNER backstage;\""
  log "     psql 'postgresql://admin:<pass>@<rds-endpoint>:5432/postgres?sslmode=require' \\"
  log "       -c \"GRANT ALL PRIVILEGES ON DATABASE backstage TO backstage;\""
}

# ─── PASSO 5: Verificação final ─────────────────────────────────────────────
verify() {
  log "PASSO 5: Verificando paths criados..."
  PATHS=(
    "secret/staging/backstage/database"
    "secret/staging/backstage/keycloak"
    "secret/staging/backstage/gitlab"
    "secret/staging/backstage/argocd"
    "secret/staging/backstage/sonarqube"
    "secret/staging/backstage/vault"
    "secret/staging/backstage/eks"
    "secret/staging/backstage/session"
    "secret/staging/backstage/harbor"
  )
  for path in "${PATHS[@]}"; do
    if [ "$DRY_RUN" = "true" ]; then
      echo "  [DRY-RUN] vault kv get $path"
    else
      vault kv get -format=json "$path" >/dev/null 2>&1 \
        && log "  ✅ $path" \
        || log "  ❌ $path — NÃO ENCONTRADO"
    fi
  done
  log ""
  log "Após preencher todos os PLACEHOLDERs, aplique o ExternalSecret:"
  log "  kubectl apply -f externalsecret-backstage.yaml"
  log "  kubectl get externalsecret backstage-secrets -n staging-platform-backstage -w"
}

# ─── PASSO 6: Configurar AppRole auth method para Scaffolder ──────────────
# GAP-012: TTL obrigatório nos AppRoles criados pelo Scaffolder
configure_approle_auth() {
  log "PASSO 6: Verificando/configurando AppRole auth method..."

  if ! vault auth list 2>/dev/null | grep -q "approle/"; then
    log "  Habilitando AppRole auth method..."
    maybe_run vault auth enable approle
    log "  AppRole auth method: habilitado"
  else
    log "  AppRole auth method: já habilitado"
  fi

  # Template AppRole para novos serviços criados pelo Scaffolder
  # GAP-012: TTL obrigatório (sem TTL = credencial persistente = risco)
  log "  Criando AppRole template app-template (padrão para novos serviços)..."
  maybe_run vault write auth/approle/role/app-template \
    secret_id_ttl="24h" \
    token_ttl="1h" \
    token_max_ttl="4h" \
    token_policies="default" \
    bind_secret_id=true
  log "  AppRole app-template: OK (TTL: secret_id=24h, token=1h, max=4h)"
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  log "=== bootstrap-vault-setup.sh — Backstage IDP Vault Config ==="
  [ "$DRY_RUN" = "true" ] && log ">>> MODO DRY-RUN — nenhuma escrita será feita <<<"
  preflight
  create_vault_policy
  create_k8s_auth_role
  write_vault_paths
  create_rds_schema
  verify
  configure_approle_auth
  log "=== CONCLUÍDO ==="
  log ""
  log "PRÓXIMOS PASSOS:"
  log "  1. Preencher PLACEHOLDERs nas variáveis de ambiente e re-executar"
  log "     (RDS_HOST, KC_CLIENT_SECRET, GITLAB_TOKEN, ARGOCD_TOKEN, SONAR_TOKEN)"
  log "  2. Criar schema backstage no RDS (PASSO 4 acima)"
  log "  3. kubectl apply -f externalsecret-backstage.yaml"
  log "  4. Aguardar ExternalSecret STATUS=SecretSynced (até 1h ou forçar com annotation)"
  log "  5. helm upgrade --install backstage backstage/backstage \\"
  log "       --version 2.6.3 \\"
  log "       --namespace staging-platform-backstage \\"
  log "       --values helm-values-staging.yaml"
}

main "$@"
