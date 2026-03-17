#!/usr/bin/env bash
# provision.sh — Provisionamento declarativo via .platform/manifest.yaml
# Gerado pelo Backstage Scaffolder — NÃO edite manualmente
# Referência: ADR-104 (onboarding declarativo)
set -euo pipefail
trap 'err "Falha na linha ${LINENO}. Último comando: ${BASH_COMMAND}"' ERR

# ─── Variáveis de ambiente obrigatórias ────────────────────────────────────
: "${VAULT_ADDR:?VAULT_ADDR não definido}"
: "${VAULT_TOKEN:?VAULT_TOKEN não definido}"
: "${KUBECONFIG:?KUBECONFIG não definido}"
: "${CI_PROJECT_DIR:?CI_PROJECT_DIR não definido}"

MANIFEST="${CI_PROJECT_DIR}/.platform/manifest.yaml"
DRY_RUN="${DRY_RUN:-false}"
FORCE_RECREATE_SECRETS="${FORCE_RECREATE_SECRETS:-false}"

# ─── Utilitários ───────────────────────────────────────────────────────────
log()  { echo "[provision] $*"; }
info() { echo "[provision] INFO: $*"; }
warn() { echo "[provision] WARN: $*"; }
err()  { echo "[provision] ERROR: $*" >&2; exit 1; }

vault_exec() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN: vault $*"
    return 0
  fi
  vault "$@"
}

kubectl_exec() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN: kubectl $*"
    return 0
  fi
  kubectl "$@"
}

# ─── Leitura do manifest ────────────────────────────────────────────────────
read_manifest() {
  local field="$1"
  yq e "$field" "$MANIFEST" 2>/dev/null || echo ""
}

APP_NAME=$(read_manifest '.metadata.name')
APP_DOMAIN=$(read_manifest '.metadata.domain')
APP_TYPE=$(read_manifest '.metadata.type')
NAMESPACE="staging-${APP_DOMAIN}-${APP_NAME}"

[[ -z "$APP_NAME" ]] && err "metadata.name não encontrado no manifest"

info "Provisionando: name=$APP_NAME namespace=$NAMESPACE type=$APP_TYPE"

# ─── Fase 1: Namespace ─────────────────────────────────────────────────────
provision_namespace() {
  info "Criando namespace $NAMESPACE..."
  if kubectl_exec get namespace "$NAMESPACE" &>/dev/null; then
    info "Namespace $NAMESPACE já existe — skip"
  else
    kubectl_exec create namespace "$NAMESPACE"
    info "Namespace $NAMESPACE criado"
  fi
}

# ─── Fase 2: Vault paths para recursos internos ────────────────────────────
provision_vault_database() {
  local db_enabled
  db_enabled=$(read_manifest '.dependencies.database.enabled')
  [[ "$db_enabled" != "true" ]] && return 0

  local vault_path="secret/staging/${APP_NAME}/database"
  info "Verificando Vault path: $vault_path"

  if vault_exec kv metadata get "$vault_path" &>/dev/null; then
    if [[ "$FORCE_RECREATE_SECRETS" == "true" ]]; then
      warn "FORCE_RECREATE_SECRETS=true — recriando path $vault_path"
    else
      info "Vault path $vault_path já existe — skip (use FORCE_RECREATE_SECRETS=true para recriar)"
      return 0
    fi
  fi

  local db_pass
  db_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
  local db_url="postgresql://${APP_NAME}_user:${db_pass}@${APP_NAME}-rds.staging.internal:5432/${APP_NAME//-/_}"

  vault_exec kv put "$vault_path" \
    url="$db_url" \
    password="$db_pass"
  info "Vault path $vault_path criado"
}

provision_vault_redis() {
  local redis_enabled
  redis_enabled=$(read_manifest '.dependencies.redis.enabled')
  [[ "$redis_enabled" != "true" ]] && return 0

  local vault_path="secret/staging/${APP_NAME}/redis"
  info "Verificando Vault path: $vault_path"

  if vault_exec kv metadata get "$vault_path" &>/dev/null; then
    if [[ "$FORCE_RECREATE_SECRETS" == "true" ]]; then
      warn "FORCE_RECREATE_SECRETS=true — recriando path $vault_path"
    else
      info "Vault path $vault_path já existe — skip (use FORCE_RECREATE_SECRETS=true para recriar)"
      return 0
    fi
  fi

  local redis_pass
  redis_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
  local redis_url="redis://:${redis_pass}@${APP_NAME}-redis.staging.internal:6379/0"

  vault_exec kv put "$vault_path" \
    url="$redis_url" \
    password="$redis_pass"
  info "Vault path $vault_path criado"
}

provision_vault_keycloak() {
  local keycloak_enabled
  keycloak_enabled=$(read_manifest '.dependencies.keycloak.enabled')
  [[ "$keycloak_enabled" != "true" ]] && return 0

  local vault_path="secret/staging/${APP_NAME}/keycloak"
  info "Verificando Vault path: $vault_path"

  if vault_exec kv metadata get "$vault_path" &>/dev/null; then
    info "Vault path $vault_path já existe — skip"
  else
    warn "Vault path $vault_path não existe — crie manualmente com as credenciais Keycloak OIDC"
    warn "Comando: vault kv put $vault_path client_secret=... admin_password=..."
    # Não falha — o operador deve preencher manualmente
  fi
}

# ─── Fase 3: ExternalSecret ─────────────────────────────────────────────────
generate_external_secret() {
  cat <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${APP_NAME}-secrets
  namespace: ${NAMESPACE}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: ${APP_NAME}-secrets
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
EOF

  # Recursos internos
  local db_enabled redis_enabled keycloak_enabled
  db_enabled=$(read_manifest '.dependencies.database.enabled')
  redis_enabled=$(read_manifest '.dependencies.redis.enabled')
  keycloak_enabled=$(read_manifest '.dependencies.keycloak.enabled')

  [[ "$db_enabled" == "true" ]] && cat <<EOF
  - secretKey: DATABASE_URL
    remoteRef:
      key: secret/data/staging/${APP_NAME}/database
      property: url
  - secretKey: DATABASE_PASSWORD
    remoteRef:
      key: secret/data/staging/${APP_NAME}/database
      property: password
EOF

  [[ "$redis_enabled" == "true" ]] && cat <<EOF
  - secretKey: REDIS_URL
    remoteRef:
      key: secret/data/staging/${APP_NAME}/redis
      property: url
  - secretKey: REDIS_PASSWORD
    remoteRef:
      key: secret/data/staging/${APP_NAME}/redis
      property: password
EOF

  [[ "$keycloak_enabled" == "true" ]] && cat <<EOF
  - secretKey: KEYCLOAK_CLIENT_SECRET
    remoteRef:
      key: secret/data/staging/${APP_NAME}/keycloak
      property: client_secret
  - secretKey: KEYCLOAK_ADMIN_PASSWORD
    remoteRef:
      key: secret/data/staging/${APP_NAME}/keycloak
      property: admin_password
EOF

  # Originadoras
  local orig_count
  orig_count=$(read_manifest '.originadoras | length')
  if [[ "$orig_count" =~ ^[0-9]+$ ]] && [[ "$orig_count" -gt 0 ]]; then
    for i in $(seq 0 $((orig_count - 1))); do
      local codigo secret_key_ref
      codigo=$(read_manifest ".originadoras[$i].codigo")
      secret_key_ref=$(read_manifest ".originadoras[$i].secretKeyRef")
      [[ -z "$secret_key_ref" ]] && secret_key_ref="$codigo"

      local upper_codigo
      upper_codigo=$(echo "$codigo" | tr '[:lower:]' '[:upper:]')

      cat <<EOF
  - secretKey: ${upper_codigo}_API_USERNAME
    remoteRef:
      key: secret/data/staging/${APP_NAME}/${secret_key_ref}
      property: username
  - secretKey: ${upper_codigo}_API_PASSWORD
    remoteRef:
      key: secret/data/staging/${APP_NAME}/${secret_key_ref}
      property: password
EOF
    done
  fi

  # Nota: config.secretKeys é documentado no manifest mas não gera entradas adicionais aqui.
  # Secrets externas com vaultPath customizado devem ser adicionadas via externalSecrets no manifest.
}

provision_external_secret() {
  local es_yaml
  es_yaml=$(generate_external_secret)

  info "Aplicando ExternalSecret ${APP_NAME}-secrets..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN: kubectl apply ExternalSecret"
    echo "$es_yaml"
    return 0
  fi

  echo "$es_yaml" | kubectl_exec apply -f -
  info "ExternalSecret aplicado"

  # Aguarda sync (max 60s)
  local retries=0
  while [[ $retries -lt 12 ]]; do
    local status
    status=$(kubectl_exec get externalsecret "${APP_NAME}-secrets" -n "$NAMESPACE" \
      -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "")
    if [[ "$status" == "True" ]]; then
      info "ExternalSecret ${APP_NAME}-secrets: READY"
      return 0
    fi
    sleep 5
    retries=$((retries + 1))
  done
  warn "ExternalSecret não ficou READY em 60s — verifique os paths no Vault"
}

# ─── Fase 4: Vault policy + Kubernetes auth role ────────────────────────────
ESO_NAMESPACE="${ESO_NAMESPACE:-staging-platform-operator}"

provision_vault_policy() {
  local policy_name="${APP_NAME}-policy"

  info "Criando Vault policy $policy_name..."

  local policy_hcl
  policy_hcl=$(cat <<POLICY
path "secret/data/staging/${APP_NAME}/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/staging/${APP_NAME}/*" {
  capabilities = ["list"]
}
POLICY
)

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN: vault policy write $policy_name"
    return 0
  fi

  # vault policy write é uma operação de upsert nativa do Vault:
  # sobrescreve a policy se já existir — idempotente por definição.
  # Erros reais (token inválido, permissão negada) propagam via set -euo pipefail.
  echo "$policy_hcl" | vault_exec policy write "$policy_name" -
  info "Policy $policy_name criada/atualizada"

  # vault write auth/kubernetes/role/... também é upsert nativo do Vault:
  # sobrescreve o role se já existir — idempotente por definição.
  # O || warn anterior mascarava falhas reais; removido para que erros
  # genuínos (token inválido, path errado, falha de rede) propaguem corretamente.
  vault_exec write "auth/kubernetes/role/${APP_NAME}" \
    bound_service_account_names="${APP_NAME},external-secrets" \
    bound_service_account_namespaces="$NAMESPACE,${ESO_NAMESPACE}" \
    policies="${policy_name}" \
    ttl="1h" \
    max_ttl="24h"
  info "Kubernetes auth role ${APP_NAME} criado/atualizado"
}

# ─── Main ───────────────────────────────────────────────────────────────────
main() {
  log "=== Iniciando provisionamento: $APP_NAME ==="
  log "Manifest: $MANIFEST"
  log "Namespace: $NAMESPACE"
  log "DRY_RUN: $DRY_RUN"

  provision_namespace
  provision_vault_database
  provision_vault_redis
  provision_vault_keycloak
  provision_vault_policy
  provision_external_secret

  log "=== Provisionamento concluído: $APP_NAME ==="
}

main "$@"
