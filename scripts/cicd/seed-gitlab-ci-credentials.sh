#!/usr/bin/env bash
# =============================================================================
# GAP-005: Seed GitLab CI Credentials into Vault
# =============================================================================
# Popula os paths Vault usados pelo ExternalSecret gitlab-ci-credentials.
#
# Uso:
#   ./seed-gitlab-ci-credentials.sh \
#     --harbor-registry harbor.staging.internal \
#     --harbor-user "robot\$gitlab-ci" \
#     --harbor-password "<token>" \
#     --sonar-host http://sonarqube.staging.internal \
#     --sonar-token "<token>"
#
# Pré-requisitos:
#   - vault CLI instalado e autenticado (vault login)
#   - Vault acessível via kubectl port-forward svc/vault 8200:8200 -n staging-security-vault
# =============================================================================
set -euo pipefail

HARBOR_REGISTRY="harbor.staging.internal"
HARBOR_USER="robot\$gitlab-ci"
HARBOR_PASSWORD=""
SONAR_HOST_URL="http://sonarqube.staging.internal"
SONAR_TOKEN=""

usage() {
  echo "Uso: $0 --harbor-password <token> --sonar-token <token> [opções]"
  echo "  --harbor-registry  (default: harbor.staging.internal)"
  echo "  --harbor-user      (default: robot\$gitlab-ci)"
  echo "  --harbor-password  OBRIGATÓRIO"
  echo "  --sonar-host       (default: http://sonarqube.staging.internal)"
  echo "  --sonar-token      OBRIGATÓRIO"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --harbor-registry) HARBOR_REGISTRY="$2"; shift 2 ;;
    --harbor-user)     HARBOR_USER="$2"; shift 2 ;;
    --harbor-password) HARBOR_PASSWORD="$2"; shift 2 ;;
    --sonar-host)      SONAR_HOST_URL="$2"; shift 2 ;;
    --sonar-token)     SONAR_TOKEN="$2"; shift 2 ;;
    *) echo "Opção desconhecida: $1"; usage ;;
  esac
done

[[ -z "${HARBOR_PASSWORD}" ]] && { echo "[ERROR] --harbor-password é obrigatório"; usage; }
[[ -z "${SONAR_TOKEN}" ]] && { echo "[ERROR] --sonar-token é obrigatório"; usage; }

echo "=== Seeding GitLab CI credentials into Vault ==="

echo "[1/2] Harbor credentials → secret/gitlab-ci/harbor"
vault kv put secret/gitlab-ci/harbor \
  registry="${HARBOR_REGISTRY}" \
  username="${HARBOR_USER}" \
  password="${HARBOR_PASSWORD}"
echo "  ✅ Harbor secrets written"

echo "[2/2] SonarQube credentials → secret/gitlab-ci/sonar"
vault kv put secret/gitlab-ci/sonar \
  host_url="${SONAR_HOST_URL}" \
  token="${SONAR_TOKEN}"
echo "  ✅ SonarQube secrets written"

echo ""
echo "=== Verificando paths Vault ==="
vault kv get -format=json secret/gitlab-ci/harbor | jq -r '.data.data | keys[]'
vault kv get -format=json secret/gitlab-ci/sonar  | jq -r '.data.data | keys[]'

echo ""
echo "=== Próximos passos ==="
echo "1. Deploy ExternalSecret:"
echo "   kubectl apply -f domains/cicd-platform/infra/gitlab-ci/runner-credentials/external-secret-gitlab-ci-credentials.yaml"
echo "2. Verificar secret criado:"
echo "   kubectl get secret gitlab-ci-credentials -n gitlab-staging"
echo "3. Reiniciar runner para aplicar envFrom:"
echo "   kubectl rollout restart deployment gitlab-runner -n gitlab-staging"
echo "4. Validar variáveis no job:"
echo "   Execute o smoke-test pipeline (domains/cicd-platform/infra/gitlab-ci/smoke-test/.gitlab-ci.yml)"
