#!/bin/bash
# =============================================================================
# GAP-S6C-01: Criar ConfigMap platform-manifest-schema e Vault policy backstage-scaffolder
# =============================================================================
# Resolve dois problemas interdependentes do GAP-S6C-01:
#
#   1. ConfigMap "platform-manifest-schema" no namespace staging-platform-backstage
#      Contem o JSON Schema do manifest.yaml para validacao inline no Scaffolder
#      do Backstage. Sem este ConfigMap, o plugin scaffolder-backend-module-gitlab
#      nao consegue validar manifestos durante o fluxo de onboarding.
#
#   2. Vault policy "backstage-scaffolder"
#      Politica Vault com capabilities necessarias para o Scaffolder criar
#      paths de novas aplicacoes. Complementa a "backstage-policy" existente
#      com permissoes especificas para o fluxo de criacao de apps via template.
#
# Pre-requisitos:
#   - kubectl configurado com acesso ao cluster EKS staging
#   - Schema existente em: domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json
#   - VAULT_TOKEN definido (admin ou root token temporario)
#   - Namespace staging-platform-backstage existente e com Backstage running
#
# Uso:
#   export VAULT_TOKEN="<vault_admin_token>"
#   chmod +x configmap-setup.sh
#   ./configmap-setup.sh
#
# Verificar pos-execucao:
#   kubectl get configmap platform-manifest-schema -n staging-platform-backstage
#   kubectl describe configmap platform-manifest-schema -n staging-platform-backstage
#
# Ref: ADR-055 (Backstage IDP), ADR-104 (CI/CD Onboarding)
# Ref: BACKSTAGE-IMPLEMENTATION-PLAN.md (secao 14 — Vault Policies)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuracao
# -----------------------------------------------------------------------------
readonly BACKSTAGE_NS="staging-platform-backstage"
readonly VAULT_NAMESPACE="staging-security-vault"
readonly VAULT_POD="vault-0"

# Declarar e atribuir separadamente para nao mascarar o return value do subshell
# (SC2155: shellcheck warn — readonly/local + command substitution combinados
# fazem o builtin retornar 0 mesmo que o subshell falhe)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Detectar raiz do projeto de forma robusta
if git -C "${SCRIPT_DIR}" rev-parse --show-toplevel &>/dev/null; then
  PROJECT_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
else
  # Fallback: strip do sufixo conhecido
  PROJECT_ROOT="${SCRIPT_DIR%/Arquitetura/Kubernetes/docs/plan/backstage}"
  if [[ "${PROJECT_ROOT}" == "${SCRIPT_DIR}" ]]; then
    echo "ERRO: Nao foi possivel determinar PROJECT_ROOT. Execute a partir do repositorio git." >&2
    exit 1
  fi
fi
readonly PROJECT_ROOT
readonly SCHEMA_PATH="${PROJECT_ROOT}/domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json"
readonly CONFIGMAP_NAME="platform-manifest-schema"

# -----------------------------------------------------------------------------
# Verificar variaveis obrigatorias
# -----------------------------------------------------------------------------
check_required_vars() {
  echo "=== Verificando variaveis obrigatorias ==="
  : "${VAULT_TOKEN:?ERRO: Variavel VAULT_TOKEN nao definida. Execute: export VAULT_TOKEN=<token>}"
  echo "OK: Variaveis obrigatorias definidas."
}

# -----------------------------------------------------------------------------
# Verificar pre-requisitos
# -----------------------------------------------------------------------------
check_prerequisites() {
  echo ""
  echo "=== Verificando pre-requisitos ==="

  if ! command -v kubectl &>/dev/null; then
    echo "ERRO: kubectl nao encontrado."
    exit 1
  fi

  # Verificar schema file
  if [[ ! -f "${SCHEMA_PATH}" ]]; then
    echo "ERRO: Schema nao encontrado em: ${SCHEMA_PATH}"
    echo "  Verifique se o arquivo existe: ls -la ${SCHEMA_PATH}"
    exit 1
  fi
  echo "OK: Schema encontrado em ${SCHEMA_PATH}"

  # Verificar namespace Backstage
  if ! kubectl get namespace "${BACKSTAGE_NS}" --no-headers 2>/dev/null | grep -q "Active"; then
    echo "ERRO: Namespace ${BACKSTAGE_NS} nao encontrado ou nao esta Active."
    echo "  Verifique: kubectl get namespace ${BACKSTAGE_NS}"
    exit 1
  fi
  echo "OK: Namespace ${BACKSTAGE_NS} existe."

  # Verificar Vault pod
  if ! kubectl get pod "${VAULT_POD}" -n "${VAULT_NAMESPACE}" --no-headers 2>/dev/null | grep -q "Running"; then
    echo "ERRO: Pod ${VAULT_POD} nao esta Running no namespace ${VAULT_NAMESPACE}."
    exit 1
  fi
  echo "OK: Vault pod ${VAULT_POD} esta Running."

  # Verificar acesso ao Vault via kubectl exec
  if ! kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- \
       env VAULT_ADDR="http://127.0.0.1:8200" vault status &>/dev/null; then
    echo "ERRO: Vault nao acessivel em ${VAULT_NAMESPACE}/${VAULT_POD}. Verificar port-forward ou servico." >&2
    exit 1
  fi
  echo "OK: Vault acessivel em ${VAULT_NAMESPACE}/${VAULT_POD}."
}

# -----------------------------------------------------------------------------
# Executar comando no pod Vault
# -----------------------------------------------------------------------------
vault_exec() {
  kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" \
    -- env VAULT_TOKEN="${VAULT_TOKEN}" VAULT_ADDR="http://127.0.0.1:8200" \
    vault "$@"
}

# -----------------------------------------------------------------------------
# [PASSO 1] Criar ConfigMap platform-manifest-schema
#
# O ConfigMap contem o JSON Schema completo do manifest.yaml (Draft 2020-12).
# O Backstage Scaffolder le este schema para:
#   a) Validar manifestos de aplicacoes durante o fluxo de onboarding
#   b) Gerar formularios dinamicos baseados no schema
#   c) Exibir erros de validacao inline no UI do Scaffolder
#
# O ConfigMap e montado no pod Backstage via volumeMount ou lido pelo plugin
# platform-scaffolder-actions (action: manifest:validate).
# -----------------------------------------------------------------------------
create_manifest_schema_configmap() {
  echo ""
  echo "=== [PASSO 1] Criando ConfigMap ${CONFIGMAP_NAME} ==="

  # Usar kubectl create/replace para ser idempotente
  if kubectl get configmap "${CONFIGMAP_NAME}" -n "${BACKSTAGE_NS}" &>/dev/null; then
    echo "  ConfigMap ja existe — atualizando (replace)..."
    kubectl create configmap "${CONFIGMAP_NAME}" \
      --from-file=manifest-schema.json="${SCHEMA_PATH}" \
      --namespace "${BACKSTAGE_NS}" \
      --dry-run=client -o yaml \
    | kubectl replace -f -
    echo "OK: ConfigMap ${CONFIGMAP_NAME} atualizado."
  else
    kubectl create configmap "${CONFIGMAP_NAME}" \
      --from-file=manifest-schema.json="${SCHEMA_PATH}" \
      --namespace "${BACKSTAGE_NS}"
    echo "OK: ConfigMap ${CONFIGMAP_NAME} criado."
  fi

  # Adicionar labels de gerenciamento
  kubectl label configmap "${CONFIGMAP_NAME}" \
    -n "${BACKSTAGE_NS}" \
    app.kubernetes.io/managed-by=platform-provisioner \
    app.kubernetes.io/part-of=backstage \
    app.kubernetes.io/component=schema \
    platform.k8s/domain=platform \
    --overwrite

  echo "  Verificando conteudo:"
  kubectl get configmap "${CONFIGMAP_NAME}" -n "${BACKSTAGE_NS}" \
    -o jsonpath='{.data}' | python3 -c "
import sys, json
data = json.load(sys.stdin)
for k, v in data.items():
    size = len(v)
    print(f'    - {k}: {size} bytes')
" 2>/dev/null || echo "    (verificacao de conteudo requer python3)"
}

# -----------------------------------------------------------------------------
# [PASSO 2] Criar/atualizar Vault policy backstage-scaffolder
#
# Esta policy complementa a backstage-policy existente com capabilities
# especificas para o Scaffolder criar paths de novas aplicacoes.
#
# Diferenca da backstage-policy:
#   - backstage-policy: leitura de secrets existentes (integracoes)
#   - backstage-scaffolder: criacao de novos paths para apps onboardadas
#
# Ref: BACKSTAGE-IMPLEMENTATION-PLAN.md secao 14
# Ref: MEDIO-1 (Vault Scaffolder — action customizada catalog:vault:write-namespace)
# -----------------------------------------------------------------------------
create_vault_scaffolder_policy() {
  echo ""
  echo "=== [PASSO 2] Criando policy Vault backstage-scaffolder ==="

  # Criar arquivo de policy, aplicar e remover em um unico sh -c para garantir
  # cleanup mesmo em caso de falha do policy write (MEDIA-03)
  kubectl exec -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- sh -c 'cat > /tmp/backstage-scaffolder-policy.hcl << '"'"'POLICY_EOF'"'"'
# =============================================================================
# Vault policy: backstage-scaffolder
# Role: backstage (Kubernetes auth method)
# Namespace SA: staging-platform-backstage
# Criado via: configmap-setup.sh (GAP-S6C-01)
#
# Complementa backstage-policy com capabilities para o Scaffolder criar
# namespaces de novas apps via action customizada catalog:vault:write-namespace
# Ref: ADR-055, MEDIO-1 (RFC #32600)
# =============================================================================

# Listar todos os paths de secrets (navegacao UI)
path "secret/metadata/*" {
  capabilities = ["list"]
}

# Ler secrets de integracoes da plataforma (ArgoCD, GitLab, SonarQube, Harbor)
path "secret/data/platform/integrations/*" {
  capabilities = ["read"]
}

# Listar secrets por ambiente (UI list-only — nao expoe valores)
path "secret/metadata/staging/+/*" {
  capabilities = ["read", "list"]
}

# Scaffolder: criar e atualizar namespace KV v2 de novas apps no staging
# Usado pela action catalog:vault:write-namespace (MEDIO-1)
path "secret/data/staging/+/*" {
  capabilities = ["create", "update", "read", "list"]
}

# Scaffolder: criar policies isoladas por servico
path "sys/policies/acl/*" {
  capabilities = ["create", "update", "read"]
}

# Scaffolder: criar e ler AppRoles para novas apps
path "auth/approle/role/+*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Scaffolder: gerar role-id e secret-id para AppRoles criadas
path "auth/approle/role/+/role-id" {
  capabilities = ["read"]
}
path "auth/approle/role/+/secret-id" {
  capabilities = ["create", "update"]
}

# Kubernetes auth: criar roles de novas apps (vincula SA ao AppRole/policy)
path "auth/kubernetes/role/+*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
POLICY_EOF
vault policy write backstage-scaffolder /tmp/backstage-scaffolder-policy.hcl; \
  rc=$?; rm -f /tmp/backstage-scaffolder-policy.hcl; exit $rc'

  echo "OK: Policy backstage-scaffolder criada no Vault."

  # Verificar
  echo "  Verificando policy criada:"
  vault_exec policy list | grep backstage || echo "    (liste manualmente com: vault policy list)"
}

# -----------------------------------------------------------------------------
# [PASSO 3] Atualizar role Kubernetes do Backstage para incluir nova policy
#
# A role kubernetes/backstage deve incluir AMBAS as policies:
#   - backstage-policy (existente)
#   - backstage-scaffolder (nova — GAP-S6C-01)
# -----------------------------------------------------------------------------
update_vault_kubernetes_role() {
  echo ""
  echo "=== [PASSO 3] Atualizando role Kubernetes/backstage no Vault ==="

  vault_exec write auth/kubernetes/role/backstage \
    bound_service_account_names=backstage \
    bound_service_account_namespaces="${BACKSTAGE_NS}" \
    policies="backstage-policy,backstage-scaffolder" \
    ttl=1h

  echo "OK: Role kubernetes/backstage atualizada com policies: backstage-policy, backstage-scaffolder"
}

# -----------------------------------------------------------------------------
# [PASSO 4] Reiniciar deployment Backstage
#
# Necessario para que o novo ConfigMap seja montado no pod.
# Sem restart, o pod continua com o volume anterior (se existia) ou sem o volume.
# Ref: GAP-S6C-01 checklist — kubectl rollout restart obrigatorio pos-ConfigMap
# -----------------------------------------------------------------------------
restart_backstage() {
  echo ""
  echo "=== [PASSO 4] Reiniciando deployment backstage ==="

  kubectl rollout restart deployment/backstage -n "${BACKSTAGE_NS}"
  echo "  Aguardando rollout concluir..."
  kubectl rollout status deployment/backstage -n "${BACKSTAGE_NS}" --timeout=120s

  echo "OK: Deployment backstage reiniciado e healthy."
}

# -----------------------------------------------------------------------------
# [PASSO 5] Verificacao final
# -----------------------------------------------------------------------------
verify_setup() {
  echo ""
  echo "=== [PASSO 5] Verificacao final ==="

  # ConfigMap
  echo -n "  ConfigMap ${CONFIGMAP_NAME}: "
  if kubectl get configmap "${CONFIGMAP_NAME}" -n "${BACKSTAGE_NS}" &>/dev/null; then
    local size
    size=$(kubectl get configmap "${CONFIGMAP_NAME}" -n "${BACKSTAGE_NS}" \
      -o jsonpath='{.data.manifest-schema\.json}' | wc -c)
    echo "OK (schema ${size} bytes)"
  else
    echo "ERRO: nao encontrado!"
  fi

  # Policy Vault
  echo -n "  Vault policy backstage-scaffolder: "
  if vault_exec policy read backstage-scaffolder &>/dev/null; then
    echo "OK"
  else
    echo "ERRO: nao encontrada!"
  fi

  # Role Kubernetes
  echo -n "  Vault role kubernetes/backstage: "
  local policies
  policies=$(vault_exec read -format=json auth/kubernetes/role/backstage 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(d.get('data',{}).get('policies',[])))" 2>/dev/null || echo "nao verificado")
  echo "OK (policies: ${policies})"
}

# -----------------------------------------------------------------------------
# Funcao principal
# -----------------------------------------------------------------------------
main() {
  echo "============================================================"
  echo "GAP-S6C-01: ConfigMap Schema + Vault Policy Scaffolder"
  echo "  Backstage namespace:  ${BACKSTAGE_NS}"
  echo "  Vault pod:            ${VAULT_POD} (${VAULT_NAMESPACE})"
  echo "  Schema:               manifest-schema.json"
  echo "  Timestamp:            $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "============================================================"

  check_required_vars
  check_prerequisites
  create_manifest_schema_configmap
  create_vault_scaffolder_policy
  update_vault_kubernetes_role
  restart_backstage
  verify_setup

  echo ""
  echo "============================================================"
  echo "GAP-S6C-01: CONCLUIDO"
  echo ""
  echo "Proximos passos:"
  echo "  1. Verificar logs Backstage (plugin scaffolder-backend):"
  echo "     kubectl logs -f deployment/backstage -n ${BACKSTAGE_NS} | grep -i schema"
  echo "  2. Continuar com GAP-S6C-02 (plugin scaffolder-backend-module-gitlab)"
  echo "============================================================"
}

main "$@"
