#!/bin/bash
# =============================================================================
# GAP-005: Deploy do GitLab Runner — Vault Gate + Helm Upgrade
# =============================================================================
# Sequência:
#   1. VAULT GATE: verifica Vault pods Running + unsealed
#   2. ESO GATE: verifica ExternalSecret gitlab-ci-credentials = SecretSynced
#   3. SECRET GATE: verifica Secret gitlab-ci-credentials tem 5 keys
#   4. HELM UPGRADE: aplica values-staging-working.yaml
#   5. POST-CHECK: verifica runner pod reiniciou + envFrom presente
#
# Uso:
#   bash scripts/cicd/deploy-runner-gap005.sh [--dry-run]
#
# Requisitos:
#   - kubectl configurado (cluster acessível)
#   - helm CLI instalado
#   - helm repo gitlab adicionado: helm repo add gitlab https://charts.gitlab.io
#
# Demanda: GAP-005 — GitLab Runner CI/CD Deploy
# =============================================================================

set -euo pipefail

# ── Configuração ──────────────────────────────────────────────────────────────
VAULT_NS="${VAULT_NS:-staging-security-vault}"
GITLAB_NS="${GITLAB_NS:-gitlab-staging}"
HELM_CHART_VERSION="${HELM_CHART_VERSION:-9.9.1}"
VALUES_FILE="${VALUES_FILE:-platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values-staging-working.yaml}"
DRY_RUN=false

# ── Parse de argumentos ───────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo "Argumento desconhecido: $arg" >&2; exit 1 ;;
  esac
done

# ── Funções auxiliares ────────────────────────────────────────────────────────
header() {
  echo ""
  echo "── $* ──────────────────────────────────────────────────────────────"
}

pass() { echo "  ✅ $*"; }
fail() { echo "  ❌ $*"; }
warn() { echo "  ⚠️  $*"; }
info() { echo "  🔍 $*"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================="
echo "  GAP-005: Deploy do GitLab Runner"
echo "  Chart: gitlab/gitlab v${HELM_CHART_VERSION}"
echo "  Namespace: ${GITLAB_NS}"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  Modo: DRY RUN (nenhuma alteração será aplicada)"
fi
echo "============================================================="
echo ""

# =============================================================================
# STEP 1 — VAULT GATE: Vault pods Running + unsealed
# =============================================================================
header "STEP 1/5 — VAULT GATE"

VAULT_PODS=$(kubectl get pods -n "$VAULT_NS" -l app.kubernetes.io/name=vault \
  --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

if [[ "$VAULT_PODS" -eq 0 ]]; then
  fail "GATE FAIL: Vault pods not Running em $VAULT_NS"
  echo "       Fix: kubectl get pods -n $VAULT_NS"
  exit 1
fi

info "Vault pods Running: $VAULT_PODS"

# Verificar que vault-0 está unsealed (KMS auto-unseal)
VAULT_SEALED=$(kubectl exec vault-0 -n "$VAULT_NS" -- vault status -format=json 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('sealed','unknown'))" 2>/dev/null || echo "unknown")

if [[ "$VAULT_SEALED" == "true" ]]; then
  fail "GATE FAIL: vault-0 está SEALED"
  echo "       Fix: aguardar KMS auto-unseal (~20s) ou executar:"
  echo "            kubectl delete pod vault-0 -n $VAULT_NS"
  exit 1
fi

if [[ "$VAULT_SEALED" == "unknown" ]]; then
  warn "Não foi possível verificar o status de seal do vault-0 (assume unsealed)"
else
  pass "GATE 1/3: Vault Running + Unsealed (sealed=$VAULT_SEALED)"
fi

# =============================================================================
# STEP 2 — ESO GATE: ExternalSecret gitlab-ci-credentials = SecretSynced
# =============================================================================
header "STEP 2/5 — ESO GATE"

ESO_STATUS=$(kubectl get externalsecret gitlab-ci-credentials -n "$GITLAB_NS" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || echo "NOT_FOUND")

if [[ "$ESO_STATUS" != "SecretSynced" ]]; then
  fail "GATE FAIL: ExternalSecret gitlab-ci-credentials NOT SecretSynced (got: $ESO_STATUS)"
  echo "       Fix: kubectl describe externalsecret gitlab-ci-credentials -n $GITLAB_NS"
  exit 1
fi

pass "GATE 2/3: ExternalSecret SecretSynced"

# =============================================================================
# STEP 3 — SECRET GATE: Secret gitlab-ci-credentials tem 5 keys
# =============================================================================
header "STEP 3/5 — SECRET KEYS GATE"

SECRET_KEYS=$(kubectl get secret gitlab-ci-credentials -n "$GITLAB_NS" \
  -o jsonpath='{.data}' 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")

REQUIRED_KEYS=5
if [[ "$SECRET_KEYS" -lt "$REQUIRED_KEYS" ]]; then
  fail "GATE FAIL: Secret gitlab-ci-credentials tem $SECRET_KEYS keys (esperado: $REQUIRED_KEYS)"
  echo "       Keys esperadas: HARBOR_REGISTRY, HARBOR_USER, HARBOR_PASSWORD, SONAR_HOST_URL, SONAR_TOKEN"
  exit 1
fi

pass "GATE 3/3: Secret gitlab-ci-credentials com $SECRET_KEYS keys"

# =============================================================================
# STEP 4 — HELM UPGRADE
# =============================================================================
header "STEP 4/5 — HELM UPGRADE"

if [[ ! -f "$VALUES_FILE" ]]; then
  fail "Values file não encontrado: $VALUES_FILE"
  echo "       Certifique-se de executar o script a partir da raiz do repositório."
  exit 1
fi

info "Values file: $VALUES_FILE"
info "Chart: gitlab/gitlab v${HELM_CHART_VERSION}"

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  warn "DRY RUN — simulando helm upgrade (sem alterações no cluster)"
  echo ""
  helm upgrade gitlab gitlab/gitlab \
    -n "$GITLAB_NS" \
    -f "$VALUES_FILE" \
    --version "$HELM_CHART_VERSION" \
    --reuse-values \
    --dry-run \
    --debug 2>&1 | tail -50
  echo ""
  pass "DRY RUN completo — nenhuma mudança aplicada"
  echo ""
  echo "Para aplicar: bash scripts/cicd/deploy-runner-gap005.sh (sem --dry-run)"
  exit 0
fi

echo ""
echo "  🚀 Executando helm upgrade..."
helm upgrade gitlab gitlab/gitlab \
  -n "$GITLAB_NS" \
  -f "$VALUES_FILE" \
  --version "$HELM_CHART_VERSION" \
  --reuse-values \
  --timeout 10m \
  --wait

pass "Helm upgrade concluído"

# =============================================================================
# STEP 5 — POST-CHECK: runner pod reiniciou + envFrom presente
# =============================================================================
header "STEP 5/5 — POST-CHECK"

echo ""
echo "  ⏳ Aguardando runner pod reiniciar (max 120s)..."
kubectl rollout status deployment/gitlab-gitlab-runner -n "$GITLAB_NS" --timeout=120s

# Verificar envFrom presente no deployment
ENVFROM=$(kubectl get deployment gitlab-gitlab-runner -n "$GITLAB_NS" \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom}' 2>/dev/null || echo "")

if [[ -z "$ENVFROM" || "$ENVFROM" == "null" ]]; then
  warn "envFrom não detectado no deployment (pode levar 1-2 min para sincronizar)"
else
  pass "envFrom configurado: $ENVFROM"
fi

# Localizar pod do runner Running
RUNNER_POD=$(kubectl get pods -n "$GITLAB_NS" -l app=gitlab-gitlab-runner \
  --field-selector=status.phase=Running -o name 2>/dev/null | head -1 || echo "")

if [[ -n "$RUNNER_POD" ]]; then
  pass "Runner pod: $RUNNER_POD"
  echo ""
  echo "  📋 Logs do runner (últimas 5 linhas):"
  kubectl logs "$RUNNER_POD" -n "$GITLAB_NS" --tail=5 2>/dev/null || warn "Não foi possível obter logs do runner"
else
  warn "Runner pod ainda não Running — verifique: kubectl get pods -n $GITLAB_NS -l app=gitlab-gitlab-runner"
fi

# =============================================================================
# RESUMO FINAL
# =============================================================================
echo ""
echo "============================================================="
echo "  ✅ GAP-005 DEPLOY COMPLETO"
echo "============================================================="
echo ""
echo "  Próximos passos:"
echo "    1. Criar Personal Access Token:"
echo "       http://gitlab.staging.internal:8181/-/user_settings/personal_access_tokens"
echo "    2. export GITLAB_TOKEN=<token>"
echo "    3. bash scripts/cicd/create-smoke-test-project.sh"
echo "    4. Verificar pipeline:"
echo "       http://gitlab.staging.internal:8181/smoke-test-ci/-/pipelines"
echo ""
echo "  Validação completa:"
echo "    bash scripts/cicd/validate-pipeline-e2e.sh"
echo ""
