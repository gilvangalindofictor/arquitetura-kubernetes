#!/bin/bash
# =============================================================================
# GAP-VAULT-HATCH: Criar paths Vault para Hatch ETL
# =============================================================================
# Cria os paths KV v2 no Vault para o servico hatch-etl no ambiente staging.
# Executa via kubectl exec no pod vault-0 (acesso indireto — sem expor porta).
#
# ATENCAO: Executar apenas com acesso ao cluster AWS (pos-recovery).
# NUNCA incluir senhas reais neste arquivo — usar variaveis de ambiente.
#
# Pre-requisitos:
#   1. kubectl configurado com acesso ao cluster EKS staging
#      aws sso login --profile k8s-platform-prod
#      aws eks update-kubeconfig --name <cluster-name> --region us-east-1 --profile k8s-platform-prod
#   2. Vault pod vault-0 em estado Running no namespace staging-security-vault
#   3. Variaveis de ambiente definidas (ver secao abaixo)
#
# Uso:
#   export DB_PASSWORD="<senha_postgresql>"
#   export REDIS_PASSWORD="<senha_redis>"
#   export KEYCLOAK_SECRET="<client_secret_keycloak>"
#   export KEYCLOAK_ADMIN_PASSWORD="<senha_admin_keycloak>"
#   export HATCH_API_USERNAME="<usuario_hatch_api>"
#   export HATCH_API_PASSWORD="<senha_hatch_api>"
#   export VAULT_TOKEN="<vault_root_or_admin_token>"
#   chmod +x vault-setup-hatch-etl.sh
#   ./vault-setup-hatch-etl.sh
#
# Vault paths criados:
#   secret/staging/hatch-etl/database  (DATABASE_URL, DATABASE_PASSWORD)
#   secret/staging/hatch-etl/redis     (REDIS_URL, REDIS_PASSWORD)
#   secret/staging/hatch-etl/keycloak  (KEYCLOAK_CLIENT_SECRET, KEYCLOAK_ADMIN_PASSWORD)
#   secret/staging/hatch-etl/api       (HATCH_API_USERNAME, HATCH_API_PASSWORD)
#
# Ref: ETL/Hatch/.platform/manifest.yaml (dependencies + config.secretKeys)
# Ref: ADR-104, BACKSTAGE-IMPLEMENTATION-PLAN.md (secao 8 — Vault Integration)
#
# NOTA: O Vault CLI KV v2 abstrai o prefixo /data/ automaticamente.
# Portanto "kv put secret/staging/hatch-etl/database" cria internamente
# em "secret/data/staging/hatch-etl/database". O ExternalSecret Operator
# (ESO) le via API HTTP e requer o /data/ explicito — ambos apontam para
# o mesmo dado fisico no Vault KV v2.
# =============================================================================

set -euo pipefail
trap 'echo "ERRO: falha na linha ${LINENO}. Verifique os logs acima." >&2' ERR

# -----------------------------------------------------------------------------
# Configuracao
# -----------------------------------------------------------------------------
readonly VAULT_NAMESPACE="staging-security-vault"
readonly VAULT_POD="vault-0"
readonly HATCH_NS="staging-data-hatch-etl"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Valores nao-sensiveis extraidos do manifest.yaml (config.env)
readonly DB_HOST="hatch-etl-rds.staging.internal"
readonly DB_PORT="5432"
readonly DB_NAME="hatch_etl"
readonly DB_USER="hatch_user"
readonly REDIS_HOST="hatch-etl-redis.staging.internal"
readonly REDIS_PORT="6379"
readonly KEYCLOAK_URL="https://keycloak.staging.internal/auth"
readonly KEYCLOAK_REALM="hatch"
readonly KEYCLOAK_CLIENT_ID="hatch-etl"

# -----------------------------------------------------------------------------
# Verificar variaveis obrigatorias
# Falha imediatamente com mensagem clara se alguma nao estiver definida
# -----------------------------------------------------------------------------
check_required_vars() {
  echo "=== Verificando variaveis obrigatorias ==="
  : "${DB_PASSWORD:?ERRO: Variavel DB_PASSWORD nao definida. Execute: export DB_PASSWORD=<senha>}"
  : "${REDIS_PASSWORD:?ERRO: Variavel REDIS_PASSWORD nao definida. Execute: export REDIS_PASSWORD=<senha>}"
  : "${KEYCLOAK_SECRET:?ERRO: Variavel KEYCLOAK_SECRET nao definida. Execute: export KEYCLOAK_SECRET=<secret>}"
  : "${KEYCLOAK_ADMIN_PASSWORD:?ERRO: Variavel KEYCLOAK_ADMIN_PASSWORD nao definida. Execute: export KEYCLOAK_ADMIN_PASSWORD=<senha>}"
  : "${HATCH_API_USERNAME:?ERRO: Variavel HATCH_API_USERNAME nao definida. Execute: export HATCH_API_USERNAME=<username>}"
  : "${HATCH_API_PASSWORD:?ERRO: Variavel HATCH_API_PASSWORD nao definida. Execute: export HATCH_API_PASSWORD=<senha>}"
  : "${VAULT_TOKEN:?ERRO: Variavel VAULT_TOKEN nao definida. Execute: export VAULT_TOKEN=<token>}"
  echo "OK: Todas as variaveis obrigatorias estao definidas."
}

# -----------------------------------------------------------------------------
# Verificar pre-requisitos de infraestrutura
# -----------------------------------------------------------------------------
check_prerequisites() {
  echo ""
  echo "=== Verificando pre-requisitos ==="

  # kubectl disponivel
  if ! command -v kubectl &>/dev/null; then
    echo "ERRO: kubectl nao encontrado. Instale o kubectl e configure o acesso ao cluster."
    exit 1
  fi

  # Vault pod acessivel
  if ! kubectl get pod "${VAULT_POD}" -n "${VAULT_NAMESPACE}" --no-headers 2>/dev/null | grep -q "Running"; then
    echo "ERRO: Pod ${VAULT_POD} nao esta em estado Running no namespace ${VAULT_NAMESPACE}."
    echo "  Verifique: kubectl get pods -n ${VAULT_NAMESPACE}"
    exit 1
  fi

  # Namespace hatch-etl existe
  if ! kubectl get namespace "${HATCH_NS}" --no-headers 2>/dev/null | grep -q "Active"; then
    echo "AVISO: Namespace ${HATCH_NS} nao encontrado ou nao esta Active."
    echo "  Sera criado automaticamente pelo pipeline de onboarding."
    echo "  Para criar manualmente: kubectl create namespace ${HATCH_NS}"
  fi

  echo "OK: Pre-requisitos verificados."
}

# -----------------------------------------------------------------------------
# Executar comando no pod Vault via kubectl exec
# Injeta VAULT_TOKEN via variavel de ambiente do exec (nao exposta nos logs)
# -----------------------------------------------------------------------------
vault_exec() {
  kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" \
    -- env VAULT_TOKEN="${VAULT_TOKEN}" VAULT_ADDR="http://127.0.0.1:8200" \
    vault "$@"
}

# -----------------------------------------------------------------------------
# Criar secret database no Vault
# Path: secret/staging/hatch-etl/database
# Extraido de: manifest.yaml dependencies.database + config.env
# -----------------------------------------------------------------------------
create_database_secret() {
  echo ""
  echo "=== [1/4] Criando secret/staging/hatch-etl/database ==="

  # Verificar se secret ja existe (idempotencia segura)
  if vault_exec kv metadata get secret/staging/hatch-etl/database &>/dev/null; then
    if [[ "${FORCE_RECREATE_SECRETS:-false}" != "true" ]]; then
      echo "AVISO: Secret database ja existe em Vault. Use FORCE_RECREATE_SECRETS=true para sobrescrever."
      return 0
    fi
    echo "AVISO: FORCE_RECREATE_SECRETS=true: sobrescrevendo secret database..."
  fi

  local db_url="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

  vault_exec kv put secret/staging/hatch-etl/database \
    url="${db_url}" \
    host="${DB_HOST}" \
    port="${DB_PORT}" \
    database="${DB_NAME}" \
    user="${DB_USER}" \
    password="${DB_PASSWORD}"

  echo "OK: secret/staging/hatch-etl/database criado."
}

# -----------------------------------------------------------------------------
# Criar secret redis no Vault
# Path: secret/staging/hatch-etl/redis
# Extraido de: manifest.yaml dependencies.redis (mode: sentinel)
# Redis Sentinel: master name "mymaster" (config.env.REDIS_SENTINEL_MASTER_NAME)
# -----------------------------------------------------------------------------
create_redis_secret() {
  echo ""
  echo "=== [2/4] Criando secret/staging/hatch-etl/redis ==="

  # Verificar se secret ja existe (idempotencia segura)
  if vault_exec kv metadata get secret/staging/hatch-etl/redis &>/dev/null; then
    if [[ "${FORCE_RECREATE_SECRETS:-false}" != "true" ]]; then
      echo "AVISO: Secret redis ja existe em Vault. Use FORCE_RECREATE_SECRETS=true para sobrescrever."
      return 0
    fi
    echo "AVISO: FORCE_RECREATE_SECRETS=true: sobrescrevendo secret redis..."
  fi

  local redis_url="redis://:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}"

  vault_exec kv put secret/staging/hatch-etl/redis \
    url="${redis_url}" \
    host="${REDIS_HOST}" \
    port="${REDIS_PORT}" \
    password="${REDIS_PASSWORD}" \
    sentinel_master_name="mymaster"

  echo "OK: secret/staging/hatch-etl/redis criado."
}

# -----------------------------------------------------------------------------
# Criar secret keycloak no Vault
# Path: secret/staging/hatch-etl/keycloak
# Extraido de: manifest.yaml dependencies.keycloak (clientType: confidential)
# Client ID e realm nao-sensiveis (tambem no ConfigMap), mas incluidos aqui
# para conveniencia do ExternalSecret
# -----------------------------------------------------------------------------
create_keycloak_secret() {
  echo ""
  echo "=== [3/4] Criando secret/staging/hatch-etl/keycloak ==="

  # Verificar se secret ja existe (idempotencia segura)
  if vault_exec kv metadata get secret/staging/hatch-etl/keycloak &>/dev/null; then
    if [[ "${FORCE_RECREATE_SECRETS:-false}" != "true" ]]; then
      echo "AVISO: Secret keycloak ja existe em Vault. Use FORCE_RECREATE_SECRETS=true para sobrescrever."
      return 0
    fi
    echo "AVISO: FORCE_RECREATE_SECRETS=true: sobrescrevendo secret keycloak..."
  fi

  vault_exec kv put secret/staging/hatch-etl/keycloak \
    url="${KEYCLOAK_URL}" \
    realm="${KEYCLOAK_REALM}" \
    client_id="${KEYCLOAK_CLIENT_ID}" \
    client_secret="${KEYCLOAK_SECRET}" \
    admin_password="${KEYCLOAK_ADMIN_PASSWORD}"

  echo "OK: secret/staging/hatch-etl/keycloak criado."
}

# -----------------------------------------------------------------------------
# Criar secret api no Vault
# Path: secret/staging/hatch-etl/api
# Credenciais de autenticacao na Hatch API (P0 — obrigatorias para extracao)
# NOTA: O sistema possui 3 login-masters distintos (aspbras_jwt, eicard_jwt,
# vemcard_jwt), cada um com credenciais proprias. Este path contem as
# credenciais do login-master primario. A estrategia multi-master completa
# e configurada via config/originadoras.yaml (Secret hatch-auth-config).
# Ref: ETL/Hatch/config/originadoras.yaml, CLAUDE.md (auth multi-master)
# -----------------------------------------------------------------------------
create_api_secret() {
  echo ""
  echo "=== [4/4] Criando secret/staging/hatch-etl/api ==="

  # Verificar se secret ja existe (idempotencia segura)
  if vault_exec kv metadata get secret/staging/hatch-etl/api &>/dev/null; then
    if [[ "${FORCE_RECREATE_SECRETS:-false}" != "true" ]]; then
      echo "AVISO: Secret api ja existe em Vault. Use FORCE_RECREATE_SECRETS=true para sobrescrever."
      return 0
    fi
    echo "AVISO: FORCE_RECREATE_SECRETS=true: sobrescrevendo secret api..."
  fi

  vault_exec kv put secret/staging/hatch-etl/api \
    username="${HATCH_API_USERNAME}" \
    password="${HATCH_API_PASSWORD}"

  echo "OK: secret/staging/hatch-etl/api criado."
}

# -----------------------------------------------------------------------------
# Criar Vault policy para o servico hatch-etl
# Concede permissao de leitura nos 4 paths KV v2 do servico
# -----------------------------------------------------------------------------
create_vault_policy() {
  echo ""
  echo "=== Criando Vault policy hatch-etl-policy ==="

  vault_exec policy write hatch-etl-policy - <<'POLICY'
# Policy: hatch-etl-policy
# Gerada por: vault-setup-hatch-etl.sh (GAP-VAULT-HATCH)
# Permite leitura dos secrets KV v2 do servico hatch-etl em staging

path "secret/data/staging/hatch-etl/database" {
  capabilities = ["read"]
}

path "secret/data/staging/hatch-etl/redis" {
  capabilities = ["read"]
}

path "secret/data/staging/hatch-etl/keycloak" {
  capabilities = ["read"]
}

path "secret/data/staging/hatch-etl/api" {
  capabilities = ["read"]
}

# Permite leitura de metadata (sem expor valores)
path "secret/metadata/staging/hatch-etl/*" {
  capabilities = ["read", "list"]
}
POLICY

  echo "OK: Policy hatch-etl-policy criada/atualizada."
}

# -----------------------------------------------------------------------------
# Configurar Kubernetes auth role para o servico hatch-etl
# Vincula ServiceAccount do namespace staging-data-hatch-etl a policy hatch-etl-policy
# Ref: ADR-104 (Vault Kubernetes auth), ESO ClusterSecretStore vault-backend
# -----------------------------------------------------------------------------
configure_kubernetes_auth_role() {
  echo ""
  echo "=== Configurando Kubernetes auth role hatch-etl ==="

  # Namespace onde o ESO (External Secrets Operator) roda.
  # O ESO tipicamente opera em namespace dedicado (nao no namespace da aplicacao).
  # Detectar automaticamente ou usar o default staging-platform-operator.
  # Para sobrescrever: export ESO_NAMESPACE=<namespace-do-eso>
  ESO_NAMESPACE="${ESO_NAMESPACE:-staging-platform-operator}"

  # Verificar se auth kubernetes esta habilitado
  if ! vault_exec auth list 2>/dev/null | grep -q "kubernetes"; then
    echo "AVISO: Vault auth method 'kubernetes' nao encontrado."
    echo "  Habilite com: vault auth enable kubernetes"
    echo "  Em seguida, configure: vault write auth/kubernetes/config ..."
    echo "  Pulando configuracao de role — execute manualmente apos habilitar o auth method."
    return 0
  fi

  # Criar/atualizar role vinculando ServiceAccount dos namespaces ao policy.
  # bound_service_account_namespaces inclui tanto o namespace da aplicacao (HATCH_NS)
  # quanto o namespace do ESO (ESO_NAMESPACE), pois o ESO precisa autenticar no Vault
  # a partir do seu proprio namespace para sincronizar os ExternalSecrets.
  vault_exec write auth/kubernetes/role/hatch-etl \
    bound_service_account_names="hatch-etl,external-secrets" \
    bound_service_account_namespaces="${HATCH_NS},${ESO_NAMESPACE}" \
    policies="hatch-etl-policy" \
    ttl="1h" \
    max_ttl="24h"

  echo "OK: Kubernetes auth role 'hatch-etl' configurada."
  echo "  ServiceAccounts: hatch-etl, external-secrets"
  echo "  Namespaces: ${HATCH_NS}, ${ESO_NAMESPACE}"
  echo "  Policy: hatch-etl-policy"
  echo "  TTL: 1h / max_ttl: 24h"
}

# -----------------------------------------------------------------------------
# Verificar secrets criados (lista metadata — nao expoe valores)
# -----------------------------------------------------------------------------
verify_vault_secrets() {
  echo ""
  echo "=== Verificando paths criados no Vault ==="

  for path in database redis keycloak api; do
    echo -n "  secret/staging/hatch-etl/${path}: "
    if vault_exec kv metadata get "secret/staging/hatch-etl/${path}" &>/dev/null; then
      local version
      version=$(vault_exec kv metadata get -format=json "secret/staging/hatch-etl/${path}" 2>/dev/null | grep '"current_version"' | awk '{print $2}' | tr -d ',' || echo "?")
      echo "OK (version ${version})"
    else
      echo "ERRO: Path nao encontrado!"
    fi
  done
}

# -----------------------------------------------------------------------------
# Aplicar ExternalSecret no namespace hatch-etl
# Aguarda sincronizacao e verifica status
# -----------------------------------------------------------------------------
apply_external_secret() {
  echo ""
  echo "=== Aplicando ExternalSecret no namespace ${HATCH_NS} ==="

  local es_manifest="${SCRIPT_DIR}/hatch-etl-external-secret.yaml"

  if [[ ! -f "${es_manifest}" ]]; then
    echo "ERRO: Arquivo ${es_manifest} nao encontrado."
    echo "  Certifique-se de que hatch-etl-external-secret.yaml esta no mesmo diretorio."
    exit 1
  fi

  kubectl apply -f "${es_manifest}"
  echo "OK: ExternalSecret aplicado."

  echo ""
  echo "Aguardando sincronizacao do ExternalSecret (max 60s)..."
  local attempts=0
  local max_attempts=12

  while [[ ${attempts} -lt ${max_attempts} ]]; do
    local status
    status=$(kubectl get externalsecret hatch-etl-secrets -n "${HATCH_NS}" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

    if [[ "${status}" == "True" ]]; then
      echo "OK: ExternalSecret sincronizado com sucesso!"
      break
    fi

    attempts=$((attempts + 1))
    echo "  Tentativa ${attempts}/${max_attempts} — aguardando... (status: ${status:-Pending})"
    sleep 5
  done

  if [[ ${attempts} -ge ${max_attempts} ]]; then
    echo "AVISO: ExternalSecret ainda nao sincronizado apos ${max_attempts} tentativas."
    echo "  Verifique: kubectl describe externalsecret hatch-etl-secrets -n ${HATCH_NS}"
  fi
}

# -----------------------------------------------------------------------------
# Validacao final: verificar Secret K8s criado pelo ExternalSecret
# -----------------------------------------------------------------------------
validate_k8s_secret() {
  echo ""
  echo "=== Validando Secret Kubernetes criado ==="

  if kubectl get secret hatch-etl-secrets -n "${HATCH_NS}" &>/dev/null; then
    echo "OK: Secret hatch-etl-secrets criado no namespace ${HATCH_NS}."

    # Listar chaves (sem expor valores)
    echo "  Chaves presentes:"
    kubectl get secret hatch-etl-secrets -n "${HATCH_NS}" \
      -o jsonpath='{.data}' | python3 -c "
import sys, json
data = json.load(sys.stdin)
for key in sorted(data.keys()):
    print(f'    - {key}')
" 2>/dev/null || \
    kubectl get secret hatch-etl-secrets -n "${HATCH_NS}" \
      -o go-template='{{range $k,$v := .data}}  - {{$k}}{{"\n"}}{{end}}'
  else
    echo "AVISO: Secret hatch-etl-secrets ainda nao criado."
    echo "  O ExternalSecret pode estar ainda sincronizando."
    echo "  Verifique: kubectl describe externalsecret hatch-etl-secrets -n ${HATCH_NS}"
  fi
}

# -----------------------------------------------------------------------------
# Funcao principal
# -----------------------------------------------------------------------------
main() {
  echo "============================================================"
  echo "GAP-VAULT-HATCH: Setup Vault para Hatch ETL"
  echo "  Vault pod:  ${VAULT_POD} (${VAULT_NAMESPACE})"
  echo "  Namespace:  ${HATCH_NS}"
  echo "  Timestamp:  $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "============================================================"

  check_required_vars
  check_prerequisites
  create_database_secret
  create_redis_secret
  create_keycloak_secret
  create_api_secret
  verify_vault_secrets
  create_vault_policy
  configure_kubernetes_auth_role
  apply_external_secret
  validate_k8s_secret

  echo ""
  echo "============================================================"
  echo "GAP-VAULT-HATCH: CONCLUIDO"
  echo ""
  echo "Proximos passos:"
  echo "  1. Executar configmap-setup.sh (GAP-S6C-01)"
  echo "  2. Verificar ESO: kubectl get externalsecret -n ${HATCH_NS}"
  echo "  3. Continuar Fase 3 do playbook (Helm Backstage Upgrade)"
  echo "============================================================"
}

main "$@"
