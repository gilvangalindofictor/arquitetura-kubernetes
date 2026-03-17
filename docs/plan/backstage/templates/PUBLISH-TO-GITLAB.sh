#!/bin/bash
# =============================================================================
# PUBLISH-TO-GITLAB.sh — Publicação dos Templates S6-C no GitLab
# Executar APÓS AWS-recovery quando GitLab (gitlab.staging.internal) estiver acessível
#
# Pré-requisitos:
#   - GITLAB_TOKEN exportado com escopo api + write_repository
#   - git configurado com credenciais válidas
#   - Acesso de rede ao gitlab.staging.internal
#
# Uso:
#   export GITLAB_TOKEN="<seu-token>"
#   bash PUBLISH-TO-GITLAB.sh
#
# GAP resolvido: GAP-S6C-03 (Templates ETL ausentes no Backstage)
# Sprint S6-C / ADR-055
# =============================================================================

set -euo pipefail

GITLAB_URL="http://gitlab.staging.internal"
REPO="platform/backstage-catalog"
BRANCH="feat/s6c-templates"
SOURCE_DIR="/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/templates"
CLONE_DIR="/tmp/backstage-catalog-templates-$$"

# ---------------------------------------------------------------------------
# Verificações de pré-requisito
# ---------------------------------------------------------------------------
if [[ -z "${GITLAB_TOKEN:-}" ]]; then
  echo "[ERRO] GITLAB_TOKEN não definido. Execute: export GITLAB_TOKEN='<token>'"
  exit 1
fi

echo "=== Publicação Templates S6-C Backstage ==="
echo "Repositório alvo : ${GITLAB_URL}/${REPO}"
echo "Branch           : ${BRANCH}"
echo "Fonte local      : ${SOURCE_DIR}"
echo ""

# ---------------------------------------------------------------------------
# Verificar conectividade com GitLab
# ---------------------------------------------------------------------------
echo "[1/6] Verificando conectividade com GitLab..."
if ! curl -sf --max-time 10 \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_URL}/api/v4/user" > /dev/null; then
  echo "[ERRO] Não foi possível conectar ao GitLab em ${GITLAB_URL}"
  echo "       Verifique: AWS-recovery concluído? VPN ativa? Token válido?"
  exit 1
fi
echo "[OK] GitLab acessível"

# ---------------------------------------------------------------------------
# Clone do repositório
# ---------------------------------------------------------------------------
echo "[2/6] Clonando repositório ${REPO}..."
git clone \
  --config http.extraHeader="PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_URL}/${REPO}.git" \
  "${CLONE_DIR}"

cd "${CLONE_DIR}"
git checkout main
git pull origin main
echo "[OK] Repositório clonado em ${CLONE_DIR}"

# ---------------------------------------------------------------------------
# Criar branch de feature
# ---------------------------------------------------------------------------
echo "[3/6] Criando branch ${BRANCH}..."
git checkout -b "${BRANCH}"

# ---------------------------------------------------------------------------
# Criar estrutura de diretórios e copiar artefatos
# ---------------------------------------------------------------------------
echo "[4/6] Copiando templates e skeletons..."

mkdir -p templates/new-service/skeleton/.platform
mkdir -p templates/etl-service/skeleton/.platform
mkdir -p templates/api-service/skeleton/.platform
mkdir -p templates/frontend/skeleton/.platform

# Templates principais
cp "${SOURCE_DIR}/new-service/template.yaml"   templates/new-service/
cp "${SOURCE_DIR}/etl-service/template.yaml"   templates/etl-service/
cp "${SOURCE_DIR}/api-service/template.yaml"   templates/api-service/
cp "${SOURCE_DIR}/frontend/template.yaml"      templates/frontend/

# Location entity (catalog-info.yaml dos templates)
cp "${SOURCE_DIR}/catalog-info.yaml"           templates/

# Skeletons .platform/manifest.yaml
cp "${SOURCE_DIR}/new-service/skeleton/.platform/manifest.yaml"   templates/new-service/skeleton/.platform/
cp "${SOURCE_DIR}/etl-service/skeleton/.platform/manifest.yaml"   templates/etl-service/skeleton/.platform/
cp "${SOURCE_DIR}/api-service/skeleton/.platform/manifest.yaml"   templates/api-service/skeleton/.platform/
# Frontend não possui manifest.yaml (sem AppRole Vault — ADR-102, nota em frontend/template.yaml)
cp "${SOURCE_DIR}/frontend/skeleton/.platform/manifest.yaml"      templates/frontend/skeleton/.platform/  2>/dev/null || true

# Skeletons catalog-info.yaml (para registro automático pelo Scaffolder)
cp "${SOURCE_DIR}/new-service/skeleton/catalog-info.yaml"   templates/new-service/skeleton/  2>/dev/null || true
cp "${SOURCE_DIR}/etl-service/skeleton/catalog-info.yaml"   templates/etl-service/skeleton/  2>/dev/null || true
cp "${SOURCE_DIR}/api-service/skeleton/catalog-info.yaml"   templates/api-service/skeleton/  2>/dev/null || true
cp "${SOURCE_DIR}/frontend/skeleton/catalog-info.yaml"      templates/frontend/skeleton/      2>/dev/null || true

echo "[OK] Artefatos copiados:"
find templates/ -type f | sort | sed 's/^/        /'

# ---------------------------------------------------------------------------
# Commit
# ---------------------------------------------------------------------------
echo "[5/6] Commitando..."
git add templates/
git config user.email "backstage-bot@staging.internal"
git config user.name "Backstage Scaffolder Bot"
git commit -m "feat(s6-c): adicionar templates Golden Path — new-service, etl-service, api-service, frontend

Resolve GAP-S6C-03: templates ETL ausentes no Backstage /create.

Templates incluídos:
- new-service: template genérico (api/worker/etl) com parâmetros básicos
- etl-service: template especializado ETL/Worker/CronJob com dependências de dados
- api-service: template API REST com Ingress, Keycloak OIDC e HPA
- frontend: template Frontend React + nginx (sem AppRole Vault — ADR-102)

Todos os templates implementam:
- backstage.io/techdocs-ref annotation adicionada nos 4 templates (catalog-info.yaml de cada template)
- platform:manifest:validate (S6-C feature — valida .platform/manifest.yaml)
- publish:gitlab com MR automático (branchName != defaultBranch)
- catalog:register automático pós-scaffold
- mergeRequestUrl no output

Sprint S6-C / ADR-055 / ADR-102"

# ---------------------------------------------------------------------------
# Push
# ---------------------------------------------------------------------------
echo "[6/6] Push e abertura de MR..."
git push origin "${BRANCH}"

# Abrir MR via API GitLab
MR_RESPONSE=$(curl -sf --request POST \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --header "Content-Type: application/json" \
  --data "{
    \"source_branch\": \"${BRANCH}\",
    \"target_branch\": \"main\",
    \"title\": \"feat(s6-c): templates Golden Path — new-service, etl-service, api-service, frontend\",
    \"description\": \"## Objetivo\\n\\nAdiciona os 4 templates Scaffolder do Golden Path para uso no Backstage /create.\\n\\n### Templates\\n\\n- **new-service**: template genérico (api/worker/etl)\\n- **etl-service**: template especializado ETL/Worker/CronJob com dependências de dados\\n- **api-service**: template API REST com Ingress, Keycloak OIDC e HPA\\n- **frontend**: template Frontend React + nginx (sem AppRole Vault — ADR-102)\\n\\n### Features (S6-C)\\n\\n- \`backstage.io/techdocs-ref\` annotation em todos os templates\\n- Step \`platform:manifest:validate\` em todos os templates\\n- Step \`publish:gitlab\` com MR automático (branchName != defaultBranch)\\n- Step \`catalog:register\` automático pós-scaffold\\n- Output \`mergeRequestUrl\` mapeado\\n\\n### Checklist\\n\\n- [ ] Backstage consegue ler \`templates/catalog-info.yaml\`\\n- [ ] Os 4 templates aparecem em /create\\n- [ ] Scaffold end-to-end funcional (test com etl-service)\\n- [ ] Step platform:manifest:validate passa\\n\\n---\\n*GAP-S6C-03 resolvido — Sprint S6-C*\",
    \"remove_source_branch\": true,
    \"squash\": false
  }" \
  "${GITLAB_URL}/api/v4/projects/$(python3 -c "import urllib.parse; print(urllib.parse.quote('${REPO}', safe=''))")/merge_requests")

MR_URL=$(echo "${MR_RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('web_url','(não obtido)'))" 2>/dev/null || echo "(não obtido)")

# ---------------------------------------------------------------------------
# Limpeza
# ---------------------------------------------------------------------------
cd /
rm -rf "${CLONE_DIR}"

echo ""
echo "=== Concluído ==="
echo "Branch  : ${BRANCH}"
echo "MR URL  : ${MR_URL}"
echo ""
echo "Próximos passos:"
echo "  1. Revisar o MR e fazer merge para main"
echo "  2. Confirmar que Backstage lê templates/catalog-info.yaml no app-config.yaml"
echo "  3. Acessar ${GITLAB_URL/-/}/backstage/create — os 4 templates devem aparecer"
echo "  4. Testar scaffold end-to-end com etl-service-template"
