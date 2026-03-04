#!/bin/bash
# =============================================================================
# GAP-005: Runner Deploy — helm upgrade do GitLab com envFrom habilitado
# =============================================================================
# Script de deploy one-shot para aplicar valores do runner (envFrom + concurrency
# + pod_labels) ao cluster via helm upgrade.
#
# Pré-requisito: gap005-vault-unseal-gate.sh deve PASSAR (exit 0 ou 2)
#
# O que muda no cluster após este deploy:
#   1. Runner pod reiniciado com envFrom → gitlab-ci-credentials injetado
#   2. Job pods criados pelo runner herdam HARBOR_*, SONAR_* como env vars
#   3. ADR-048 compliance: job pods têm labels domain=integration
#   4. request_concurrency=2 resolve long-polling bottleneck
#
# Uso:
#   bash scripts/cicd/gap005-runner-deploy.sh
#   bash scripts/cicd/gap005-runner-deploy.sh --dry-run   # apenas simula
#   bash scripts/cicd/gap005-runner-deploy.sh --skip-gate # pula vault gate
#
# Demanda: GAP-005 — CI/CD End-to-End Pipeline Validation
# =============================================================================

set -euo pipefail

# ── Configuração ──────────────────────────────────────────────────────────────
GITLAB_NS="gitlab-staging"
HELM_RELEASE="gitlab"
HELM_CHART="gitlab/gitlab"
HELM_VERSION="9.9.1"
VALUES_FILE="platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values-staging-working.yaml"
GATE_SCRIPT="scripts/cicd/gap005-vault-unseal-gate.sh"
ROLLOUT_TIMEOUT="300"  # 5 minutos
DRY_RUN="${1:-}"
SKIP_GATE="${1:-}"

# =============================================================================
# FASE 1: Vault Gate
# =============================================================================
echo "═══════════════════════════════════════════"
echo " FASE 1: Vault Unseal Gate"
echo "═══════════════════════════════════════════"

if [[ "$SKIP_GATE" != "--skip-gate" ]]; then
  if [[ ! -f "$GATE_SCRIPT" ]]; then
    echo "❌ Gate script não encontrado: $GATE_SCRIPT"
    exit 1
  fi
  bash "$GATE_SCRIPT"
  GATE_EXIT=$?
  if [[ $GATE_EXIT -eq 1 ]]; then
    echo "❌ Gate BLOQUEADO — abortando deploy"
    exit 1
  fi
  echo "✅ Gate aprovado (exit=$GATE_EXIT)"
else
  echo "⚠️  --skip-gate ativo — gate ignorado"
fi

# =============================================================================
# FASE 2: Pre-deploy snapshot
# =============================================================================
echo "═══════════════════════════════════════════"
echo " FASE 2: Snapshot estado atual"
echo "═══════════════════════════════════════════"

echo "→ Helm history (últimas revisões):"
helm history "$HELM_RELEASE" -n "$GITLAB_NS" --max 3 2>/dev/null || \
  echo "  (sem histórico disponível)"

echo ""
echo "→ Runner pod antes do deploy:"
kubectl get pod -n "$GITLAB_NS" -l app=gitlab-runner 2>/dev/null || \
  kubectl get pod -n "$GITLAB_NS" -l app=gitlab-gitlab-runner 2>/dev/null || \
  echo "  (nenhum pod runner encontrado)"

echo ""
echo "→ envFrom atual no deployment gitlab-gitlab-runner:"
kubectl get deployment gitlab-gitlab-runner -n "$GITLAB_NS" \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom}' 2>/dev/null || \
  echo "  (deployment não encontrado ou envFrom ausente)"
echo ""

# =============================================================================
# FASE 3: Helm Upgrade
# =============================================================================
echo "═══════════════════════════════════════════"
echo " FASE 3: Helm Upgrade"
echo "═══════════════════════════════════════════"

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "❌ Values file não encontrado: $VALUES_FILE"
  echo "   Certifique-se de executar o script a partir da raiz do repositório."
  exit 1
fi

echo "→ Values file: $VALUES_FILE"
echo "→ Chart       : $HELM_CHART v$HELM_VERSION"
echo "→ Namespace   : $GITLAB_NS"
echo ""

HELM_CMD="helm upgrade $HELM_RELEASE $HELM_CHART \
  --namespace $GITLAB_NS \
  --version $HELM_VERSION \
  --values $VALUES_FILE \
  --atomic \
  --timeout ${ROLLOUT_TIMEOUT}s \
  --cleanup-on-fail"

echo "Executando: $HELM_CMD"
echo ""

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  $HELM_CMD --dry-run
  echo ""
  echo "✅ Dry-run concluído — sem alterações no cluster"
  echo "   Para aplicar: bash scripts/cicd/gap005-runner-deploy.sh"
  exit 0
else
  $HELM_CMD
fi

# =============================================================================
# FASE 4: Verificação pós-deploy
# =============================================================================
echo "═══════════════════════════════════════════"
echo " FASE 4: Verificação pós-deploy"
echo "═══════════════════════════════════════════"

# V1: Helm revision
echo "→ Helm revision atual:"
helm history "$HELM_RELEASE" -n "$GITLAB_NS" --max 3

echo ""

# V2: Runner pod status
echo "→ Runner pod status:"
kubectl get pod -n "$GITLAB_NS" -l app=gitlab-runner 2>/dev/null || \
  kubectl get pod -n "$GITLAB_NS" -l app=gitlab-gitlab-runner 2>/dev/null || \
  echo "  (nenhum pod runner encontrado)"

echo ""

# V3: envFrom presente no deployment
echo "→ Verificando envFrom no deployment..."
ENV_FROM=$(kubectl get deployment gitlab-gitlab-runner -n "$GITLAB_NS" \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom}' 2>/dev/null || echo "")

if echo "$ENV_FROM" | grep -q "gitlab-ci-credentials"; then
  echo "✅ envFrom configurado corretamente"
else
  echo "⚠️  envFrom NÃO detectado — verificar manualmente"
  echo "   kubectl get deployment gitlab-gitlab-runner -n $GITLAB_NS -o jsonpath='{.spec.template.spec.containers[0].envFrom}'"
fi

echo ""

# V4: Secret acessível no runner pod
echo "→ Verificando acesso ao secret no pod runner..."
RUNNER_POD=$(kubectl get pod -n "$GITLAB_NS" -l app=gitlab-runner \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
  kubectl get pod -n "$GITLAB_NS" -l app=gitlab-gitlab-runner \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$RUNNER_POD" ]]; then
  echo "  Runner pod: $RUNNER_POD"
  # Verificar que a variável existe (não expor valor)
  kubectl exec "$RUNNER_POD" -n "$GITLAB_NS" -- \
    sh -c 'test -n "$HARBOR_REGISTRY" && echo "HARBOR_REGISTRY: SET" || echo "HARBOR_REGISTRY: UNSET"' 2>/dev/null || \
    echo "⚠️  Não foi possível verificar variáveis no pod"
else
  echo "⚠️  Runner pod não localizado — verificar manualmente"
fi

# =============================================================================
# FASE 5: Sumário
# =============================================================================
echo ""
echo "═══════════════════════════════════════════"
echo " GAP-005 Runner Deploy — CONCLUÍDO"
echo "═══════════════════════════════════════════"
echo " Helm release : $HELM_RELEASE v$HELM_VERSION"
echo " Namespace    : $GITLAB_NS"
echo " Values file  : $VALUES_FILE"
echo ""
echo " Próximos passos:"
echo "   1. Verificar logs do runner: kubectl logs -n $GITLAB_NS -l app=gitlab-runner -f"
echo "   2. Disparar smoke test   : bash scripts/cicd/create-smoke-test-project.sh"
echo "   3. Validar pipeline e2e  : bash scripts/cicd/validate-pipeline-e2e.sh"
echo "═══════════════════════════════════════════"
