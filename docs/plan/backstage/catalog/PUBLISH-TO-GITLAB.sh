#!/bin/bash
# =============================================================================
# PUBLISH-TO-GITLAB.sh — Publicação das Catalog Entities S6-A no GitLab
# Executar APÓS AWS-recovery quando GitLab (gitlab.staging.internal) estiver acessível
#
# Publica as 4 catalog entities:
#   1. catalog/catalog-info.yaml              — Location root (aponta para todos)
#   2. catalog/entities/domains/catalog-info.yaml   — 5 Domain entities
#   3. catalog/entities/systems/data/catalog-info.yaml — System: data-hatch-etl
#   4. catalog/ETL/Hatch/catalog-info.yaml    — 8 Component entities
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
# Sprint S6-A+B / ADR-055, ADR-102
# =============================================================================

set -euo pipefail

GITLAB_URL="http://gitlab.staging.internal"
REPO="platform/backstage-catalog"
BRANCH="feat/s6ab-catalog-entities"
SOURCE_DIR="/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/catalog"
CLONE_DIR="/tmp/backstage-catalog-entities-$$"

# ---------------------------------------------------------------------------
# Verificações de pré-requisito
# ---------------------------------------------------------------------------
if [[ -z "${GITLAB_TOKEN:-}" ]]; then
  echo "[ERRO] GITLAB_TOKEN não definido. Execute: export GITLAB_TOKEN='<token>'"
  exit 1
fi

echo "=== Publicação Catalog Entities S6-A+B Backstage ==="
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
echo "[4/6] Copiando catalog entities..."

# Estrutura alvo no repositório GitLab:
#   catalog-info.yaml                          (Location root)
#   entities/domains/catalog-info.yaml         (Domains)
#   entities/systems/data/catalog-info.yaml    (Systems)
#   ETL/Hatch/catalog-info.yaml                (Components)

mkdir -p entities/domains
mkdir -p entities/systems/data
mkdir -p ETL/Hatch

# Location root
cp "${SOURCE_DIR}/catalog-info.yaml"                              ./catalog-info.yaml

# Domain entities (5 domínios: platform, integration, data, operations, shared-services)
cp "${SOURCE_DIR}/entities/domains/catalog-info.yaml"             entities/domains/catalog-info.yaml

# System entity (data-hatch-etl)
cp "${SOURCE_DIR}/entities/systems/data/catalog-info.yaml"        entities/systems/data/catalog-info.yaml

# Component entities (8 serviços ETL/Hatch)
cp "${SOURCE_DIR}/ETL/Hatch/catalog-info.yaml"                    ETL/Hatch/catalog-info.yaml

echo "[OK] Artefatos copiados:"
find . -name "catalog-info.yaml" | sort | sed 's/^/        /'

# ---------------------------------------------------------------------------
# Commit
# ---------------------------------------------------------------------------
echo "[5/6] Commitando..."
git add catalog-info.yaml entities/ ETL/
git config user.email "backstage-bot@staging.internal"
git config user.name "Backstage Scaffolder Bot"
git commit -m "feat(s6-ab): adicionar catalog entities — domains, systems, components ETL/Hatch

Publica as 4 catalog entities do sistema ETL Hatch no repositório backstage-catalog:

- catalog-info.yaml: Location root — aponta para todos os catálogos
- entities/domains/catalog-info.yaml: 5 Domain entities da plataforma
  (platform, integration, data, operations, shared-services)
- entities/systems/data/catalog-info.yaml: System entity data-hatch-etl
- ETL/Hatch/catalog-info.yaml: 8 Component entities
  (hatch-api-gateway, hatch-worker, hatch-etl-core, hatch-data-processor,
   hatch-scheduler, hatch-dashboard, hatch-cronjob-etl-extraction,
   hatch-migration-runner)

Sprint S6-A+B / ADR-055 / ADR-102 / ADR-047"

# ---------------------------------------------------------------------------
# Push e abertura de MR
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
    \"title\": \"feat(s6-ab): catalog entities — domains, systems, components ETL/Hatch\",
    \"description\": \"## Objetivo\\n\\nPublica as 4 catalog entities do sistema ETL Hatch no repositório backstage-catalog.\\n\\n### Entities\\n\\n| Arquivo | Tipo | Conteúdo |\\n|---|---|---|\\n| \`catalog-info.yaml\` | Location | Root — aponta para todos os catálogos |\\n| \`entities/domains/catalog-info.yaml\` | Domain x5 | platform, integration, data, operations, shared-services |\\n| \`entities/systems/data/catalog-info.yaml\` | System | data-hatch-etl |\\n| \`ETL/Hatch/catalog-info.yaml\` | Component x8 | 8 serviços ETL/Hatch com observability links |\\n\\n### Como registrar no Backstage\\n\\nAdicionar ao \`app-config.yaml\`:\\n\\n\`\`\`yaml\\ncatalog:\\n  locations:\\n    - type: url\\n      target: https://gitlab.staging.internal/platform/backstage-catalog/-/raw/main/catalog-info.yaml\\n      rules:\\n        - allow: [Location, Domain, System, Component, API, Group, User, Template]\\n\`\`\`\\n\\n### Checklist\\n\\n- [ ] Backstage ingere catalog-info.yaml sem erros\\n- [ ] 5 domínios visíveis em /catalog\\n- [ ] Sistema data-hatch-etl visível\\n- [ ] 8 componentes ETL/Hatch visíveis\\n- [ ] Observability links funcionais (Grafana, ArgoCD, Vault)\\n\\n---\\n*Sprint S6-A+B — ADR-055, ADR-102*\",
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
echo "  2. Verificar que app-config.yaml aponta para catalog-info.yaml (ver comentário no arquivo)"
echo "  3. Acessar ${GITLAB_URL/-/}/backstage/catalog — entidades devem ser visíveis"
echo "  4. Verificar: 5 domínios + 1 sistema + 8 componentes ingeridos sem erros"
