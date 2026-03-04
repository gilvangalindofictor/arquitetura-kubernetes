#!/bin/bash
# =============================================================================
# GAP-005: Validação End-to-End dos Pré-Requisitos do Pipeline CI/CD
# =============================================================================
# Verifica o estado de todos os componentes necessários para o smoke test:
#   1. GitLab Runner (kubernetes executor)
#   2. Credentials ESO (ExternalSecret → gitlab-ci-credentials)
#   3. Harbor Registry (staging-platform-harbor)
#   4. SonarQube (staging-platform-sonarqube)
#   5. ArgoCD (staging-platform-argocd)
#
# Uso:
#   bash scripts/cicd/validate-pipeline-e2e.sh
#   bash scripts/cicd/validate-pipeline-e2e.sh --json   # output JSON
#
# Saída:
#   - Status de cada componente (OK / WARN / FAIL)
#   - Resumo final com contagem de OK/WARN/FAIL
#   - Código de saída: 0=tudo OK, 1=algum FAIL, 2=algum WARN
#
# Demanda: GAP-005 — Pipeline End-to-End Validation
# =============================================================================

set -euo pipefail

# ── Configuração ──────────────────────────────────────────────────────────────
GITLAB_NS="${GITLAB_NS:-gitlab-staging}"
HARBOR_NS="${HARBOR_NS:-staging-platform-harbor}"
SONAR_NS="${SONAR_NS:-staging-platform-sonarqube}"
ARGOCD_NS="${ARGOCD_NS:-staging-platform-argocd}"
OUTPUT_JSON="${1:-}"

# ── Contadores ────────────────────────────────────────────────────────────────
COUNT_OK=0
COUNT_WARN=0
COUNT_FAIL=0
declare -a RESULTS=()

# ── Funções auxiliares ────────────────────────────────────────────────────────
ok() {
  local msg="$1"
  echo "  [OK]   ${msg}"
  COUNT_OK=$((COUNT_OK + 1))
  RESULTS+=("OK|${msg}")
}

warn() {
  local msg="$1"
  echo "  [WARN] ${msg}"
  COUNT_WARN=$((COUNT_WARN + 1))
  RESULTS+=("WARN|${msg}")
}

fail() {
  local msg="$1"
  echo "  [FAIL] ${msg}"
  COUNT_FAIL=$((COUNT_FAIL + 1))
  RESULTS+=("FAIL|${msg}")
}

# ── Cabeçalho ─────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " GAP-005: CI/CD End-to-End Pre-Requisite Validation"
echo "============================================================"
echo " Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo " Cluster:   k8s-platform-prod (EKS 1.34)"
echo "============================================================"

# =============================================================================
# CHECK 1: GitLab Pods
# =============================================================================
echo ""
echo "[1/5] Verificando GitLab (namespace: ${GITLAB_NS})..."

GITLAB_PODS=$(kubectl get pods -n "${GITLAB_NS}" --no-headers 2>&1)
if echo "${GITLAB_PODS}" | grep -q "Running"; then
  RUNNING_COUNT=$(echo "${GITLAB_PODS}" | grep -c "Running" || true)
  TOTAL_COUNT=$(echo "${GITLAB_PODS}" | grep -v "Completed\|Terminating" | wc -l | tr -d ' ')
  ok "GitLab pods: ${RUNNING_COUNT}/${TOTAL_COUNT} Running"
else
  fail "Nenhum pod GitLab Running no namespace ${GITLAB_NS}"
fi

# GitLab Runner
echo ""
echo "  Runner..."
RUNNER_POD=$(kubectl get pods -n "${GITLAB_NS}" -l app=gitlab-gitlab-runner --no-headers 2>&1)
if echo "${RUNNER_POD}" | grep -q "1/1.*Running"; then
  RUNNER_NAME=$(echo "${RUNNER_POD}" | awk '{print $1}')
  RUNNER_RESTARTS=$(echo "${RUNNER_POD}" | awk '{print $4}')
  ok "Runner pod: ${RUNNER_NAME} — Running (restarts: ${RUNNER_RESTARTS})"

  # Verificar logs de registro
  RUNNER_LOGS=$(kubectl logs -n "${GITLAB_NS}" -l app=gitlab-gitlab-runner --tail=20 2>&1)
  if echo "${RUNNER_LOGS}" | grep -qE "registered|Configuration loaded|Initializing executor"; then
    ok "Runner logs: inicializado com sucesso"
  else
    warn "Runner logs: padrão de inicialização não detectado"
    echo "    Últimas linhas do log:"
    echo "${RUNNER_LOGS}" | tail -5 | sed 's/^/      /'
  fi

  # Warning de long polling (não crítico)
  if echo "${RUNNER_LOGS}" | grep -q "Long polling issues"; then
    warn "Runner: long polling issue detectado (request_concurrency=1)"
    echo "    Recomendação: aumentar request_concurrency para 2-4"
  fi
else
  fail "Runner pod não está Running: ${RUNNER_POD}"
fi

# =============================================================================
# CHECK 2: Credentials ESO
# =============================================================================
echo ""
echo "[2/5] Verificando Credentials ESO (ExternalSecret → gitlab-ci-credentials)..."

# ExternalSecret
ESO_STATUS=$(kubectl get externalsecret gitlab-ci-credentials -n "${GITLAB_NS}" \
  -o jsonpath='{.status.conditions[0].type}' 2>&1 || echo "NOT_FOUND")
ESO_READY=$(kubectl get externalsecret gitlab-ci-credentials -n "${GITLAB_NS}" \
  -o jsonpath='{.status.conditions[0].status}' 2>&1 || echo "unknown")
ESO_STORE=$(kubectl get externalsecret gitlab-ci-credentials -n "${GITLAB_NS}" \
  -o jsonpath='{.spec.secretStoreRef.name}' 2>&1 || echo "unknown")

if [[ "${ESO_STATUS}" == "Ready" && "${ESO_READY}" == "True" ]]; then
  ok "ExternalSecret gitlab-ci-credentials: Ready=True (store: ${ESO_STORE})"
elif [[ "${ESO_STATUS}" == "NOT_FOUND" ]]; then
  fail "ExternalSecret gitlab-ci-credentials não encontrado no namespace ${GITLAB_NS}"
else
  warn "ExternalSecret gitlab-ci-credentials: ${ESO_STATUS}=${ESO_READY} (store: ${ESO_STORE})"
fi

# Secret existência
SECRET_EXISTS=$(kubectl get secret gitlab-ci-credentials -n "${GITLAB_NS}" \
  --no-headers 2>&1 | awk '{print $1}')
if [[ "${SECRET_EXISTS}" == "gitlab-ci-credentials" ]]; then
  SECRET_KEYS=$(kubectl get secret gitlab-ci-credentials -n "${GITLAB_NS}" \
    -o jsonpath='{.data}' 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(d.keys()))" 2>/dev/null || echo "unknown")
  ok "Secret gitlab-ci-credentials: EXISTS (keys: ${SECRET_KEYS})"
else
  fail "Secret gitlab-ci-credentials não encontrado"
fi

# Verificar se runner tem envFrom configurado
RUNNER_DEPLOYMENT=$(kubectl get deployment gitlab-gitlab-runner -n "${GITLAB_NS}" \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom}' 2>&1 || echo "[]")
if echo "${RUNNER_DEPLOYMENT}" | grep -q "gitlab-ci-credentials"; then
  ok "Runner deployment: envFrom → gitlab-ci-credentials configurado"
else
  warn "Runner deployment: envFrom com gitlab-ci-credentials não detectado"
  echo "    Verificar: kubectl get deployment gitlab-gitlab-runner -n ${GITLAB_NS} -o yaml | grep -A5 envFrom"
fi

# =============================================================================
# CHECK 3: Harbor Registry
# =============================================================================
echo ""
echo "[3/5] Verificando Harbor (namespace: ${HARBOR_NS})..."

HARBOR_PODS=$(kubectl get pods -n "${HARBOR_NS}" --no-headers 2>&1)
if [[ -z "${HARBOR_PODS}" ]] || echo "${HARBOR_PODS}" | grep -q "No resources"; then
  warn "Harbor: nenhum pod encontrado em ${HARBOR_NS} — verificar namespace"
  # Tentar harbor-system
  HARBOR_PODS_ALT=$(kubectl get pods -n harbor-system --no-headers 2>&1)
  if echo "${HARBOR_PODS_ALT}" | grep -q "Running"; then
    ok "Harbor: pods encontrados em harbor-system (namespace alternativo)"
    echo "${HARBOR_PODS_ALT}" | grep "Running" | awk '{print "      " $1 " — " $3}' | head -5
  else
    fail "Harbor: nenhum pod Running encontrado"
  fi
else
  HARBOR_RUNNING=$(echo "${HARBOR_PODS}" | grep -c "Running" || true)
  HARBOR_TOTAL=$(echo "${HARBOR_PODS}" | grep -v "Completed\|Terminating" | wc -l | tr -d ' ')
  ok "Harbor pods: ${HARBOR_RUNNING}/${HARBOR_TOTAL} Running"
  echo "${HARBOR_PODS}" | grep "Running" | awk '{print "      " $1 " — " $3}' | head -6
fi

# =============================================================================
# CHECK 4: SonarQube
# =============================================================================
echo ""
echo "[4/5] Verificando SonarQube (namespace: ${SONAR_NS})..."

SONAR_PODS=$(kubectl get pods -n "${SONAR_NS}" --no-headers 2>&1)
if [[ -z "${SONAR_PODS}" ]] || echo "${SONAR_PODS}" | grep -q "No resources"; then
  warn "SonarQube: nenhum pod encontrado em ${SONAR_NS}"
else
  if echo "${SONAR_PODS}" | grep -q "1/1.*Running"; then
    SONAR_NAME=$(echo "${SONAR_PODS}" | grep "Running" | awk '{print $1}')
    SONAR_RESTARTS=$(echo "${SONAR_PODS}" | grep "Running" | awk '{print $4}')
    ok "SonarQube pod: ${SONAR_NAME} — Running (restarts: ${SONAR_RESTARTS})"

    # Restarts elevados são esperados no staging (restart de JVM)
    RESTART_NUM=$(echo "${SONAR_RESTARTS}" | grep -oE '^[0-9]+' || echo "0")
    if [[ "${RESTART_NUM}" -gt 50 ]]; then
      warn "SonarQube: ${RESTART_NUM} restarts — monitorar estabilidade"
    fi
  else
    warn "SonarQube pod não está em Running/1/1"
    echo "${SONAR_PODS}" | sed 's/^/      /'
  fi
fi

# =============================================================================
# CHECK 5: ArgoCD
# =============================================================================
echo ""
echo "[5/5] Verificando ArgoCD (namespace: ${ARGOCD_NS})..."

ARGOCD_PODS=$(kubectl get pods -n "${ARGOCD_NS}" --no-headers 2>&1)
if [[ -z "${ARGOCD_PODS}" ]] || echo "${ARGOCD_PODS}" | grep -q "No resources"; then
  warn "ArgoCD: nenhum pod encontrado em ${ARGOCD_NS}"
else
  ARGOCD_RUNNING=$(echo "${ARGOCD_PODS}" | grep -c "Running" || true)
  ARGOCD_TOTAL=$(echo "${ARGOCD_PODS}" | grep -v "Completed\|Terminating" | wc -l | tr -d ' ')
  if [[ "${ARGOCD_RUNNING}" -gt 0 ]]; then
    ok "ArgoCD pods: ${ARGOCD_RUNNING}/${ARGOCD_TOTAL} Running"
    echo "${ARGOCD_PODS}" | grep "Running" | grep -v "argo-rollouts" | awk '{print "      " $1 " — " $3}' | head -6
  else
    fail "ArgoCD: nenhum pod Running"
    echo "${ARGOCD_PODS}" | sed 's/^/      /'
  fi
fi

# ArgoCD server especificamente
ARGOCD_SERVER=$(kubectl get pods -n "${ARGOCD_NS}" \
  -l app.kubernetes.io/name=argocd-server --no-headers 2>&1)
if echo "${ARGOCD_SERVER}" | grep -q "Running"; then
  SERVER_COUNT=$(echo "${ARGOCD_SERVER}" | grep -c "Running" || true)
  ok "ArgoCD server: ${SERVER_COUNT} pod(s) Running"
else
  warn "ArgoCD server pod não localizado (verificar label app.kubernetes.io/name=argocd-server)"
fi

# =============================================================================
# SUMÁRIO FINAL
# =============================================================================
echo ""
echo "============================================================"
echo " SUMÁRIO — GAP-005 Pre-Requisite Validation"
echo "============================================================"
printf " OK:   %d checks\n" "${COUNT_OK}"
printf " WARN: %d checks\n" "${COUNT_WARN}"
printf " FAIL: %d checks\n" "${COUNT_FAIL}"
echo "------------------------------------------------------------"

TOTAL_CHECKS=$((COUNT_OK + COUNT_WARN + COUNT_FAIL))
if [[ "${COUNT_FAIL}" -gt 0 ]]; then
  echo " STATUS: FAIL — ${COUNT_FAIL} componente(s) indisponível(is)"
  echo " Pipeline smoke test bloqueado até resolução dos FAILs."
  EXIT_CODE=1
elif [[ "${COUNT_WARN}" -gt 0 ]]; then
  echo " STATUS: WARN — pipeline pode funcionar com limitações"
  echo " Smoke test parcial possível; algumas validações podem ser puladas."
  EXIT_CODE=2
else
  echo " STATUS: OK — todos os componentes disponíveis"
  echo " Pipeline end-to-end PRONTO para smoke test."
  EXIT_CODE=0
fi

echo ""
echo " PROXIMOS PASSOS:"
if [[ "${COUNT_FAIL}" -eq 0 ]]; then
  echo "   1. Gerar Personal Access Token no GitLab:"
  echo "      ${GITLAB_URL:-http://gitlab.staging.internal:8181}/-/user_settings/personal_access_tokens"
  echo "      Escopos: api, read_user, read_repository, write_repository"
  echo ""
  echo "   2. Executar o script de criação do projeto smoke-test:"
  echo "      export GITLAB_TOKEN='<seu-token>'"
  echo "      bash scripts/cicd/create-smoke-test-project.sh"
  echo ""
  echo "   3. Acompanhar o pipeline em:"
  echo "      ${GITLAB_URL:-http://gitlab.staging.internal:8181}/smoke-test-ci/-/pipelines"
else
  echo "   Resolver os FAILs acima antes de executar o smoke test."
fi

echo "============================================================"
echo ""

exit "${EXIT_CODE}"
