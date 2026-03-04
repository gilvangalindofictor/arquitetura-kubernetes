#!/bin/bash
# =============================================================================
# GAP-005: Criar projeto smoke-test no GitLab e disparar pipeline de validação
# =============================================================================
# Uso:
#   export GITLAB_TOKEN="<seu-personal-access-token>"
#   bash scripts/cicd/create-smoke-test-project.sh
#
# Pré-requisitos:
#   - GITLAB_TOKEN com escopo api (Personal Access Token ou Group/Project token)
#   - jq instalado (apt install jq / brew install jq)
#   - curl com acesso ao endpoint interno gitlab.staging.internal:8181
#
# O script:
#   1. Cria o projeto smoke-test-ci no namespace root (ou em GITLAB_NAMESPACE)
#   2. Faz upload do .gitlab-ci.yml e Dockerfile de smoke test
#   3. Dispara o primeiro pipeline e aguarda o resultado
#   4. Imprime o resumo final com status de cada job
#
# Demanda: GAP-005 — Pipeline End-to-End Validation
# =============================================================================

set -euo pipefail

# ── Configuração ──────────────────────────────────────────────────────────────
GITLAB_URL="${GITLAB_URL:-http://gitlab.staging.internal:8181}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"          # Obrigatório — Personal Access Token
GITLAB_NAMESPACE="${GITLAB_NAMESPACE:-}"  # Deixar vazio para namespace root
PROJECT_NAME="smoke-test-ci"
PROJECT_DESC="GAP-005: CI/CD end-to-end smoke test — K8s Platform"
BRANCH="${BRANCH:-main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SMOKE_TEST_DIR="${REPO_ROOT}/domains/cicd-platform/infra/gitlab-ci/smoke-test"

# ── Validações ────────────────────────────────────────────────────────────────
if [[ -z "${GITLAB_TOKEN}" ]]; then
  echo "[ERROR] Variável GITLAB_TOKEN não definida."
  echo "        Gere um Personal Access Token em:"
  echo "        ${GITLAB_URL}/-/user_settings/personal_access_tokens"
  echo "        Escopos necessários: api, read_user, read_repository, write_repository"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "[ERROR] jq não encontrado. Instale: apt install jq"
  exit 1
fi

if ! command -v curl &>/dev/null; then
  echo "[ERROR] curl não encontrado."
  exit 1
fi

# ── Funções auxiliares ────────────────────────────────────────────────────────
gitlab_api() {
  local method="$1"
  local path="$2"
  shift 2
  curl -s -f -X "${method}" \
    "${GITLAB_URL}/api/v4${path}" \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

gitlab_api_no_fail() {
  local method="$1"
  local path="$2"
  shift 2
  curl -s -X "${method}" \
    "${GITLAB_URL}/api/v4${path}" \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

encode_path() {
  # URL-encode a project path (replace / with %2F)
  echo "$1" | sed 's|/|%2F|g'
}

file_to_base64() {
  base64 -w 0 "$1"
}

# ── Step 1: Verificar conectividade com GitLab ────────────────────────────────
echo ""
echo "============================================================"
echo " GAP-005: CI/CD End-to-End Smoke Test Setup"
echo "============================================================"
echo " GitLab URL: ${GITLAB_URL}"
echo " Projeto:    ${PROJECT_NAME}"
echo " Branch:     ${BRANCH}"
echo "============================================================"
echo ""

echo "[1/6] Verificando conectividade com GitLab..."
VERSION=$(gitlab_api GET /version 2>/dev/null | jq -r '.version // "unknown"')
if [[ "${VERSION}" == "unknown" ]]; then
  echo "[WARN] Não foi possível verificar versão do GitLab. Continuando..."
else
  echo "       GitLab version: ${VERSION} — OK"
fi

# ── Step 2: Verificar se projeto já existe ────────────────────────────────────
echo ""
echo "[2/6] Verificando se projeto '${PROJECT_NAME}' já existe..."

NAMESPACE_QUERY=""
if [[ -n "${GITLAB_NAMESPACE}" ]]; then
  PROJECT_FULL_PATH="${GITLAB_NAMESPACE}/${PROJECT_NAME}"
  NAMESPACE_QUERY="\"namespace\": \"${GITLAB_NAMESPACE}\","
else
  PROJECT_FULL_PATH="${PROJECT_NAME}"
fi

ENCODED_PATH=$(encode_path "${PROJECT_FULL_PATH}")
EXISTING=$(gitlab_api_no_fail GET "/projects/${ENCODED_PATH}")
EXISTING_ID=$(echo "${EXISTING}" | jq -r '.id // empty' 2>/dev/null || true)

if [[ -n "${EXISTING_ID}" ]]; then
  echo "       Projeto já existe (id=${EXISTING_ID}). Reutilizando."
  PROJECT_ID="${EXISTING_ID}"
  HTTP_URL=$(echo "${EXISTING}" | jq -r '.http_url_to_repo')
  SSH_URL=$(echo "${EXISTING}" | jq -r '.ssh_url_to_repo')
  WEB_URL=$(echo "${EXISTING}" | jq -r '.web_url')
else
  # ── Step 3: Criar projeto ─────────────────────────────────────────────────
  echo "       Projeto não encontrado. Criando..."
  echo ""
  echo "[3/6] Criando projeto smoke-test-ci..."

  CREATE_PAYLOAD=$(cat <<JSON
{
  "name": "${PROJECT_NAME}",
  "description": "${PROJECT_DESC}",
  "visibility": "internal",
  "initialize_with_readme": true,
  "default_branch": "${BRANCH}",
  ${NAMESPACE_QUERY}
  "ci_config_path": ".gitlab-ci.yml",
  "shared_runners_enabled": true,
  "auto_devops_enabled": false,
  "build_timeout": 600
}
JSON
)

  CREATE_RESP=$(gitlab_api POST /projects -d "${CREATE_PAYLOAD}")
  PROJECT_ID=$(echo "${CREATE_RESP}" | jq -r '.id')
  HTTP_URL=$(echo "${CREATE_RESP}" | jq -r '.http_url_to_repo')
  SSH_URL=$(echo "${CREATE_RESP}" | jq -r '.ssh_url_to_repo')
  WEB_URL=$(echo "${CREATE_RESP}" | jq -r '.web_url')

  if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "null" ]]; then
    echo "[ERROR] Falha ao criar projeto. Resposta:"
    echo "${CREATE_RESP}" | jq .
    exit 1
  fi

  echo "       Projeto criado com sucesso!"
  echo "       ID:       ${PROJECT_ID}"
  echo "       HTTP URL: ${HTTP_URL}"
  echo "       SSH URL:  ${SSH_URL}"
  echo "       Web URL:  ${WEB_URL}"
fi

echo ""

# ── Step 4: Upload dos arquivos de smoke test ─────────────────────────────────
echo "[4/6] Fazendo upload dos arquivos de smoke test..."

# Função para criar ou atualizar arquivo via API
upsert_file() {
  local project_id="$1"
  local file_path="$2"
  local local_path="$3"
  local commit_msg="$4"

  local content
  content=$(base64 -w 0 "${local_path}" 2>/dev/null || base64 "${local_path}")

  local encoded_file_path
  encoded_file_path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${file_path}', safe=''))" 2>/dev/null \
    || echo "${file_path}" | sed 's|/|%2F|g' | sed 's|\.|%2E|g')

  # Tentar criar; se já existir, atualizar
  local create_payload
  create_payload=$(cat <<JSON
{
  "branch": "${BRANCH}",
  "content": "${content}",
  "encoding": "base64",
  "commit_message": "${commit_msg}"
}
JSON
)

  local response
  response=$(curl -s -X POST \
    "${GITLAB_URL}/api/v4/projects/${project_id}/repository/files/${encoded_file_path}" \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${create_payload}")

  local file_path_result
  file_path_result=$(echo "${response}" | jq -r '.file_path // empty' 2>/dev/null || true)

  if [[ -n "${file_path_result}" ]]; then
    echo "       [CREATE] ${file_path} — OK"
  else
    # Tentar update se já existir
    response=$(curl -s -X PUT \
      "${GITLAB_URL}/api/v4/projects/${project_id}/repository/files/${encoded_file_path}" \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${create_payload}")
    file_path_result=$(echo "${response}" | jq -r '.file_path // empty' 2>/dev/null || true)
    if [[ -n "${file_path_result}" ]]; then
      echo "       [UPDATE] ${file_path} — OK"
    else
      echo "       [WARN]   ${file_path} — resposta inesperada:"
      echo "${response}" | jq -r '.message // .' 2>/dev/null || echo "${response}"
    fi
  fi
}

# Upload .gitlab-ci.yml
if [[ -f "${SMOKE_TEST_DIR}/.gitlab-ci.yml" ]]; then
  upsert_file "${PROJECT_ID}" ".gitlab-ci.yml" \
    "${SMOKE_TEST_DIR}/.gitlab-ci.yml" \
    "GAP-005: Add smoke test CI pipeline"
else
  echo "[WARN] ${SMOKE_TEST_DIR}/.gitlab-ci.yml não encontrado — skipping upload"
fi

# Upload Dockerfile
if [[ -f "${SMOKE_TEST_DIR}/Dockerfile" ]]; then
  upsert_file "${PROJECT_ID}" "Dockerfile" \
    "${SMOKE_TEST_DIR}/Dockerfile" \
    "GAP-005: Add smoke test Dockerfile"
else
  echo "[WARN] ${SMOKE_TEST_DIR}/Dockerfile não encontrado — skipping upload"
fi

echo ""

# ── Step 5: Disparar pipeline ─────────────────────────────────────────────────
echo "[5/6] Disparando pipeline de smoke test..."

PIPELINE_PAYLOAD=$(cat <<JSON
{
  "ref": "${BRANCH}",
  "variables": [
    {"key": "GAP005_SMOKE_TEST", "value": "true"},
    {"key": "CI_ENVIRONMENT_NAME", "value": "staging"}
  ]
}
JSON
)

PIPELINE_RESP=$(gitlab_api POST "/projects/${PROJECT_ID}/pipeline" -d "${PIPELINE_PAYLOAD}")
PIPELINE_ID=$(echo "${PIPELINE_RESP}" | jq -r '.id // empty')
PIPELINE_URL=$(echo "${PIPELINE_RESP}" | jq -r '.web_url // empty')

if [[ -z "${PIPELINE_ID}" || "${PIPELINE_ID}" == "null" ]]; then
  echo "[WARN] Não foi possível disparar pipeline via API trigger."
  echo "       Acesse o projeto e dispare manualmente:"
  echo "       ${WEB_URL}/-/pipelines/new"
else
  echo "       Pipeline criado: ${PIPELINE_URL}"
  echo "       Pipeline ID: ${PIPELINE_ID}"
  echo ""

  # ── Step 6: Aguardar resultado ──────────────────────────────────────────────
  echo "[6/6] Aguardando resultado do pipeline (timeout: 10 min)..."
  echo ""

  TIMEOUT=600
  ELAPSED=0
  POLL_INTERVAL=15
  FINAL_STATUS=""

  while [[ ${ELAPSED} -lt ${TIMEOUT} ]]; do
    PIPELINE_STATUS=$(gitlab_api GET "/projects/${PROJECT_ID}/pipelines/${PIPELINE_ID}" \
      | jq -r '.status // "unknown"')

    case "${PIPELINE_STATUS}" in
      running|pending|created|waiting_for_resource|preparing|scheduled)
        echo "       [${ELAPSED}s] Status: ${PIPELINE_STATUS}..."
        sleep ${POLL_INTERVAL}
        ELAPSED=$((ELAPSED + POLL_INTERVAL))
        ;;
      success)
        FINAL_STATUS="success"
        break
        ;;
      failed|canceled|skipped)
        FINAL_STATUS="${PIPELINE_STATUS}"
        break
        ;;
      *)
        echo "       [${ELAPSED}s] Status desconhecido: ${PIPELINE_STATUS}"
        sleep ${POLL_INTERVAL}
        ELAPSED=$((ELAPSED + POLL_INTERVAL))
        ;;
    esac
  done

  # Imprimir jobs
  echo ""
  echo "============================================================"
  echo " Resultado do Pipeline #${PIPELINE_ID}"
  echo "============================================================"

  JOBS=$(gitlab_api GET "/projects/${PROJECT_ID}/pipelines/${PIPELINE_ID}/jobs" \
    | jq -r '.[] | "\(.name)|\(.status)|\(.duration // 0 | floor)s|\(.web_url)"')

  while IFS='|' read -r name status duration url; do
    STATUS_ICON="  "
    case "${status}" in
      success)  STATUS_ICON="OK" ;;
      failed)   STATUS_ICON="FAIL" ;;
      skipped)  STATUS_ICON="SKIP" ;;
      running)  STATUS_ICON="RUNNING" ;;
      *)        STATUS_ICON="${status}" ;;
    esac
    printf "  %-30s %-8s %8s  %s\n" "${name}" "${STATUS_ICON}" "${duration}" "${url}"
  done <<< "${JOBS}"

  echo ""
  if [[ "${FINAL_STATUS}" == "success" ]]; then
    echo " RESULTADO: PASSED — Pipeline end-to-end concluido com sucesso"
    echo " GAP-005: VALIDADO"
  else
    echo " RESULTADO: ${FINAL_STATUS^^} — Verifique os logs em: ${PIPELINE_URL}"
  fi
  echo "============================================================"
fi

echo ""
echo " Projeto: ${WEB_URL}"
echo ""
