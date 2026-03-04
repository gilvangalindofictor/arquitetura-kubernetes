#!/bin/bash
# =============================================================================
# GAP-005: Vault Unseal Gate — Pre-flight check antes do runner helm upgrade
# =============================================================================
# Verifica que TODOS os pré-requisitos estão ativos antes de executar
# helm upgrade gitlab (que reinicia o runner e força ESO re-sync do secret).
#
# Se Vault estiver sealed quando o runner reiniciar:
#   - ESO NÃO consegue pull de secret/gitlab-ci/harbor e secret/gitlab-ci/sonar
#   - Secret gitlab-ci-credentials fica desatualizado/ausente
#   - Runner pod inicia SEM as variáveis CI/CD (HARBOR_*, SONAR_*)
#   - Todos os jobs de CI falham (push Harbor, SonarQube scan)
#
# Pré-requisitos para PASS:
#   1. kubectl configurado e acessível
#   2. Vault pod Running em staging-security-vault
#   3. Vault UNSEALED (KMS auto-unseal = padrão, mas pode falhar se KMS estiver indisponível)
#   4. ExternalSecret gitlab-ci-credentials = Ready (SecretSynced)
#   5. Secret gitlab-ci-credentials existe com 5 keys
#   6. ESO controller Running
#
# Uso:
#   bash scripts/cicd/gap005-vault-unseal-gate.sh
#   bash scripts/cicd/gap005-vault-unseal-gate.sh --quiet   # apenas exit code
#   bash scripts/cicd/gap005-vault-unseal-gate.sh --fix     # tenta remediar issues
#
# Exit codes:
#   0 = PASS (todos os checks OK, prosseguir com helm upgrade)
#   1 = FAIL (bloqueante, não prosseguir)
#   2 = WARN (não bloqueante, prosseguir com cautela)
#
# Demanda: GAP-005 — CI/CD End-to-End Pipeline Validation
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------
QUIET="${1:-}"
FIX_MODE="${1:-}"
VAULT_NS="staging-security-vault"
GITLAB_NS="gitlab-staging"
ESO_NS="staging-security-externalsecrets"
EXTERNAL_SECRET_NAME="gitlab-ci-credentials"
SECRET_NAME="gitlab-ci-credentials"
EXPECTED_KEYS=5

PASS=0
WARN=0
FAIL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# ---------------------------------------------------------------------------
# Funções de report
# ---------------------------------------------------------------------------
check_ok()   { [[ "$QUIET" != "--quiet" ]] && echo -e "  ${GREEN}OK${NC}   $1"; ((PASS++)) || true; }
check_warn() { [[ "$QUIET" != "--quiet" ]] && echo -e "  ${YELLOW}WARN${NC} $1"; ((WARN++)) || true; }
check_fail() { [[ "$QUIET" != "--quiet" ]] && echo -e "  ${RED}FAIL${NC} $1"; ((FAIL++)) || true; }

section() {
  [[ "$QUIET" == "--quiet" ]] && return
  echo ""
  echo -e "${BLUE}${BOLD}▶ $1${NC}"
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
if [[ "$QUIET" != "--quiet" ]]; then
  echo ""
  echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD} GAP-005: Vault Unseal Gate — Pre-flight Checks${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
  echo " Vault NS : $VAULT_NS"
  echo " GitLab NS: $GITLAB_NS"
  echo " ESO NS   : $ESO_NS"
  echo " Secret   : $SECRET_NAME"
  [[ "$FIX_MODE" == "--fix" ]] && echo -e " Mode     : ${YELLOW}--fix (remediação automática ativa)${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
fi

# ---------------------------------------------------------------------------
# CHECK 1: kubectl acessível
# ---------------------------------------------------------------------------
section "CHECK 1: kubectl acessível"

if kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
  check_ok "kubectl responde ao cluster"
else
  check_fail "kubectl não responde — verificar kubeconfig e acesso ao cluster"
  [[ "$QUIET" != "--quiet" ]] && echo "   → Verifique: export KUBECONFIG=~/.kube/config | aws eks update-kubeconfig --name <cluster>"
  # Sem kubectl, todos os demais checks falham — abortar imediatamente
  echo ""
  echo -e "${RED}${BOLD}GATE BLOQUEADO — kubectl inacessível, checks subsequentes impossíveis${NC}"
  exit 1
fi

# ---------------------------------------------------------------------------
# CHECK 2: Vault pod Running
# ---------------------------------------------------------------------------
section "CHECK 2: Vault pod Running"

VAULT_PHASE=$(kubectl get pod vault-0 -n "$VAULT_NS" --request-timeout=10s \
  -o jsonpath='{.status.phase}' 2>/dev/null || echo "NOT_FOUND")

if [[ "$VAULT_PHASE" == "Running" ]]; then
  check_ok "vault-0 está Running em $VAULT_NS"
else
  check_fail "vault-0 não está Running (status atual: $VAULT_PHASE)"
  [[ "$QUIET" != "--quiet" ]] && echo "   → Fix: kubectl describe pod vault-0 -n $VAULT_NS"
  [[ "$QUIET" != "--quiet" ]] && echo "   → Fix: kubectl delete pod vault-0 -n $VAULT_NS (StatefulSet recria)"
fi

# ---------------------------------------------------------------------------
# CHECK 3: Vault UNSEALED
# ---------------------------------------------------------------------------
section "CHECK 3: Vault UNSEALED (KMS auto-unseal)"

if [[ "$VAULT_PHASE" == "Running" ]]; then
  VAULT_STATUS_JSON=$(kubectl exec vault-0 -n "$VAULT_NS" --request-timeout=10s \
    -- vault status -format=json 2>/dev/null || echo "")

  if [[ -z "$VAULT_STATUS_JSON" ]]; then
    check_warn "Não foi possível verificar status do Vault via exec — Vault pode estar inicializando"
    [[ "$QUIET" != "--quiet" ]] && echo "   → Tente manualmente: kubectl exec vault-0 -n $VAULT_NS -- vault status"
  else
    SEALED=$(echo "$VAULT_STATUS_JSON" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(str(d.get('sealed', True)).lower())" 2>/dev/null || echo "unknown")

    if [[ "$SEALED" == "false" ]]; then
      check_ok "Vault UNSEALED (KMS auto-unseal ativo)"
    elif [[ "$SEALED" == "true" ]]; then
      check_fail "Vault SEALED — KMS auto-unseal pode estar falhando"
      [[ "$QUIET" != "--quiet" ]] && echo "   → KMS Key: 272b2c51-4f0c-402a-a075-9006da4e187e"
      [[ "$QUIET" != "--quiet" ]] && echo "   → Logs: kubectl logs vault-0 -n $VAULT_NS | grep -i seal"

      if [[ "$FIX_MODE" == "--fix" ]]; then
        [[ "$QUIET" != "--quiet" ]] && echo -e "   ${YELLOW}--fix: Deletando vault-0 para forçar KMS auto-unseal (~20s)...${NC}"
        kubectl delete pod vault-0 -n "$VAULT_NS" --request-timeout=30s >/dev/null 2>&1 || true
        [[ "$QUIET" != "--quiet" ]] && echo "   Aguardando 25s para KMS auto-unseal..."
        sleep 25
        NEW_PHASE=$(kubectl get pod vault-0 -n "$VAULT_NS" --request-timeout=10s \
          -o jsonpath='{.status.phase}' 2>/dev/null || echo "UNKNOWN")
        [[ "$QUIET" != "--quiet" ]] && echo "   vault-0 status pós-delete: $NEW_PHASE"
      fi
    else
      check_warn "Não foi possível determinar estado de seal do Vault (resposta: $SEALED)"
    fi
  fi
else
  check_warn "CHECK 3 pulado — vault-0 não está Running"
fi

# ---------------------------------------------------------------------------
# CHECK 4: ESO controller Running
# ---------------------------------------------------------------------------
section "CHECK 4: ESO controller Running"

ESO_PHASE=$(kubectl get pod -n "$ESO_NS" --request-timeout=10s \
  -l app.kubernetes.io/name=external-secrets \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NOT_FOUND")

if [[ "$ESO_PHASE" == "Running" ]]; then
  check_ok "ESO controller Running em $ESO_NS"
else
  check_fail "ESO controller não está Running (status: $ESO_PHASE)"
  [[ "$QUIET" != "--quiet" ]] && echo "   → Fix: kubectl rollout restart deployment -n $ESO_NS -l app.kubernetes.io/name=external-secrets"
fi

# ---------------------------------------------------------------------------
# CHECK 5: ExternalSecret Ready
# ---------------------------------------------------------------------------
section "CHECK 5: ExternalSecret '$EXTERNAL_SECRET_NAME' Ready"

ES_TYPE=$(kubectl get externalsecret "$EXTERNAL_SECRET_NAME" -n "$GITLAB_NS" \
  --request-timeout=10s \
  -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "NOT_FOUND")

ES_STATUS=$(kubectl get externalsecret "$EXTERNAL_SECRET_NAME" -n "$GITLAB_NS" \
  --request-timeout=10s \
  -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "NOT_FOUND")

ES_MESSAGE=$(kubectl get externalsecret "$EXTERNAL_SECRET_NAME" -n "$GITLAB_NS" \
  --request-timeout=10s \
  -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "")

if [[ "$ES_TYPE" == "Ready" && "$ES_STATUS" == "True" ]]; then
  check_ok "ExternalSecret '$EXTERNAL_SECRET_NAME' = Ready/True (SecretSynced)"
else
  check_fail "ExternalSecret '$EXTERNAL_SECRET_NAME' não está sincronizado (type=$ES_TYPE, status=$ES_STATUS)"
  [[ "$QUIET" != "--quiet" && -n "$ES_MESSAGE" ]] && echo "   → Mensagem: $ES_MESSAGE"
  [[ "$QUIET" != "--quiet" ]] && echo "   → Debug: kubectl describe externalsecret $EXTERNAL_SECRET_NAME -n $GITLAB_NS"

  if [[ "$FIX_MODE" == "--fix" ]]; then
    [[ "$QUIET" != "--quiet" ]] && echo -e "   ${YELLOW}--fix: Forçando re-sync do ExternalSecret...${NC}"
    kubectl annotate externalsecret "$EXTERNAL_SECRET_NAME" -n "$GITLAB_NS" \
      force-sync="$(date +%s)" --overwrite --request-timeout=10s >/dev/null 2>&1 || true
    [[ "$QUIET" != "--quiet" ]] && echo "   Aguardando 10s para re-sync..."
    sleep 10
    ES_STATUS_NEW=$(kubectl get externalsecret "$EXTERNAL_SECRET_NAME" -n "$GITLAB_NS" \
      --request-timeout=10s \
      -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "UNKNOWN")
    [[ "$QUIET" != "--quiet" ]] && echo "   ExternalSecret status pós-annotate: $ES_STATUS_NEW"
  fi
fi

# ---------------------------------------------------------------------------
# CHECK 6: Secret existe
# ---------------------------------------------------------------------------
section "CHECK 6: Secret '$SECRET_NAME' existe"

if kubectl get secret "$SECRET_NAME" -n "$GITLAB_NS" --request-timeout=10s >/dev/null 2>&1; then
  check_ok "Secret '$SECRET_NAME' encontrado em $GITLAB_NS"
else
  check_fail "Secret '$SECRET_NAME' não encontrado em $GITLAB_NS"
  [[ "$QUIET" != "--quiet" ]] && echo "   → Aguarde ESO sincronizar (depende do CHECK 5)"
  [[ "$QUIET" != "--quiet" ]] && echo "   → Debug: kubectl get externalsecret $EXTERNAL_SECRET_NAME -n $GITLAB_NS -o yaml"
fi

# ---------------------------------------------------------------------------
# CHECK 7: Secret tem 5 keys com valores esperados
# ---------------------------------------------------------------------------
section "CHECK 7: Secret '$SECRET_NAME' tem $EXPECTED_KEYS keys"

if kubectl get secret "$SECRET_NAME" -n "$GITLAB_NS" --request-timeout=10s >/dev/null 2>&1; then
  KEY_COUNT=$(kubectl get secret "$SECRET_NAME" -n "$GITLAB_NS" --request-timeout=10s \
    -o jsonpath='{.data}' 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")

  REQUIRED_KEYS=("HARBOR_REGISTRY" "HARBOR_USER" "HARBOR_PASSWORD" "SONAR_HOST_URL" "SONAR_TOKEN")
  MISSING_KEYS=()

  for KEY in "${REQUIRED_KEYS[@]}"; do
    PRESENT=$(kubectl get secret "$SECRET_NAME" -n "$GITLAB_NS" --request-timeout=10s \
      -o jsonpath="{.data.$KEY}" 2>/dev/null || echo "")
    [[ -z "$PRESENT" ]] && MISSING_KEYS+=("$KEY")
  done

  if [[ "${#MISSING_KEYS[@]}" -eq 0 && "$KEY_COUNT" -ge "$EXPECTED_KEYS" ]]; then
    check_ok "Secret contém $KEY_COUNT/$EXPECTED_KEYS keys (HARBOR_REGISTRY, HARBOR_USER, HARBOR_PASSWORD, SONAR_HOST_URL, SONAR_TOKEN)"
  elif [[ "${#MISSING_KEYS[@]}" -gt 0 ]]; then
    check_fail "Secret incompleto — keys ausentes: ${MISSING_KEYS[*]} ($KEY_COUNT/$EXPECTED_KEYS presentes)"
    [[ "$QUIET" != "--quiet" ]] && echo "   → Verifique os paths no Vault: secret/gitlab-ci/harbor + secret/gitlab-ci/sonar"
    [[ "$QUIET" != "--quiet" ]] && echo "   → Debug: kubectl get secret $SECRET_NAME -n $GITLAB_NS -o yaml | grep -E '^  [A-Z]'"
  else
    check_warn "Secret tem $KEY_COUNT keys (esperado >= $EXPECTED_KEYS) mas todas as keys obrigatórias presentes"
  fi
else
  check_warn "CHECK 7 pulado — Secret não existe (ver CHECK 6)"
fi

# ---------------------------------------------------------------------------
# CHECK 8 (WARN): Runner deployment tem envFrom
# ---------------------------------------------------------------------------
section "CHECK 8 (WARN): Runner possui envFrom configurado"

ENV_FROM=$(kubectl get deployment gitlab-gitlab-runner -n "$GITLAB_NS" --request-timeout=10s \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom}' 2>/dev/null || echo "")

if [[ -n "$ENV_FROM" && "$ENV_FROM" != "null" && "$ENV_FROM" != "[]" ]]; then
  check_ok "Runner já possui envFrom (helm upgrade mantém ou atualiza)"
  [[ "$QUIET" != "--quiet" ]] && echo "   → envFrom: $ENV_FROM"
else
  check_warn "Runner atual NÃO tem envFrom — helm upgrade irá corrigir isso"
  [[ "$QUIET" != "--quiet" ]] && echo "   → Este é o motivo do helm upgrade (não é bloqueante para o gate)"
  [[ "$QUIET" != "--quiet" ]] && echo "   → Após helm upgrade: runner irá ler HARBOR_* e SONAR_* do Secret"
fi

# ---------------------------------------------------------------------------
# Sumário final
# ---------------------------------------------------------------------------
if [[ "$QUIET" != "--quiet" ]]; then
  echo ""
  echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD} GAP-005: Vault Unseal Gate — Resultado${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
  echo -e " ${GREEN}PASS${NC}: $PASS"
  echo -e " ${YELLOW}WARN${NC}: $WARN"
  echo -e " ${RED}FAIL${NC}: $FAIL"
  echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
fi

if [[ $FAIL -gt 0 ]]; then
  [[ "$QUIET" != "--quiet" ]] && echo -e "${RED}${BOLD}GATE BLOQUEADO — Resolva os FAILs antes do helm upgrade${NC}"
  [[ "$QUIET" != "--quiet" ]] && echo "   → Execute com --fix para tentativa automática de remediação"
  [[ "$QUIET" != "--quiet" ]] && echo ""
  exit 1
elif [[ $WARN -gt 0 ]]; then
  [[ "$QUIET" != "--quiet" ]] && echo -e "${YELLOW}${BOLD}GATE APROVADO COM AVISOS — helm upgrade pode prosseguir${NC}"
  [[ "$QUIET" != "--quiet" ]] && echo ""
  exit 2
else
  [[ "$QUIET" != "--quiet" ]] && echo -e "${GREEN}${BOLD}GATE APROVADO — Prosseguir com helm upgrade${NC}"
  [[ "$QUIET" != "--quiet" ]] && echo ""
  exit 0
fi
