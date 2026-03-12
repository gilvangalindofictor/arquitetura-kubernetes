#!/usr/bin/env bash
# =============================================================================
# backstage-tf-import.sh
# GAP-003: Importa os 4 recursos criados manualmente em 2026-03-05/06
# para o Terraform state, evitando 409 Conflict no próximo terraform apply.
#
# Cluster : k8s-platform-prod (EKS us-east-1, conta 891377105802)
# Módulo  : platform-provisioning/aws/kubernetes/terraform/modules/backstage/
# State   : terraform-state-marco0-891377105802
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuração — ajuste se necessário
# ---------------------------------------------------------------------------
MODULE_PREFIX="${MODULE_PREFIX:-module.backstage}"

# Diretório raiz do Terraform que chama o módulo backstage.
# Ajuste este caminho para o root module correto do seu repositório.
TF_DIR="${TF_DIR:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform}"

# ---------------------------------------------------------------------------
# Funções auxiliares
# ---------------------------------------------------------------------------
log_info()  { echo "[INFO]  $(date '+%Y-%m-%dT%H:%M:%S') $*"; }
log_ok()    { echo "[OK]    $(date '+%Y-%m-%dT%H:%M:%S') $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%dT%H:%M:%S') $*" >&2; }

import_resource() {
  local description="$1"
  local address="$2"
  local id="$3"

  log_info "Importando: ${description}"
  log_info "  Endereço : ${address}"
  log_info "  ID       : ${id}"

  if terraform import "${address}" "${id}"; then
    log_ok "Import concluído: ${description}"
  else
    log_error "Falha ao importar: ${description}"
    log_error "Endereço: ${address} | ID: ${id}"
    exit 1
  fi
  echo
}

# ---------------------------------------------------------------------------
# Pré-checks
# ---------------------------------------------------------------------------
log_info "=== GAP-003: Backstage Terraform Import ==="
echo

if [[ ! -d "${TF_DIR}" ]]; then
  log_error "Diretório Terraform não encontrado: ${TF_DIR}"
  log_error "Exporte TF_DIR com o caminho correto antes de executar este script."
  exit 1
fi

if ! command -v terraform &>/dev/null; then
  log_error "terraform não encontrado no PATH."
  exit 1
fi

log_info "TF_DIR       : ${TF_DIR}"
log_info "MODULE_PREFIX: ${MODULE_PREFIX}"
echo

cd "${TF_DIR}"
log_info "Working directory: $(pwd)"
echo

# ---------------------------------------------------------------------------
# Verifica se o state já contém algum dos recursos (evita re-import acidental)
# ---------------------------------------------------------------------------
log_info "Verificando recursos já presentes no state..."
EXISTING=$(terraform state list 2>/dev/null | grep "^${MODULE_PREFIX}\." || true)

if [[ -n "${EXISTING}" ]]; then
  log_info "Recursos do módulo já no state:"
  echo "${EXISTING}" | sed 's/^/  /'
  echo
  log_info "Recursos já existentes serão pulados automaticamente pelo terraform import."
  echo
fi

# ---------------------------------------------------------------------------
# Import 1 — kubernetes_namespace.backstage
# Namespace: staging-platform-backstage
# ID       : <nome do namespace>
# ---------------------------------------------------------------------------
import_resource \
  "kubernetes_namespace.backstage (ns: staging-platform-backstage)" \
  "${MODULE_PREFIX}.kubernetes_namespace.backstage" \
  "staging-platform-backstage"

# ---------------------------------------------------------------------------
# Import 2 — kubernetes_cluster_role.backstage_kubernetes_reader
# ClusterRole: backstage-kubernetes-reader (cluster-scoped)
# ID         : <nome do ClusterRole>
# ---------------------------------------------------------------------------
import_resource \
  "kubernetes_cluster_role.backstage_kubernetes_reader" \
  "${MODULE_PREFIX}.kubernetes_cluster_role.backstage_kubernetes_reader" \
  "backstage-kubernetes-reader"

# ---------------------------------------------------------------------------
# Import 3 — kubernetes_pod_disruption_budget_v1.backstage_pdb
# Namespace: staging-platform-backstage | Nome: backstage-pdb
# ID       : namespace/name
# ---------------------------------------------------------------------------
import_resource \
  "kubernetes_pod_disruption_budget_v1.backstage_pdb (pdb: backstage-pdb)" \
  "${MODULE_PREFIX}.kubernetes_pod_disruption_budget_v1.backstage_pdb" \
  "staging-platform-backstage/backstage-pdb"

# ---------------------------------------------------------------------------
# Import 4 — kubectl_manifest.backstage_linkerd_exception
# Kyverno PolicyException (CRD namespaced)
# ID: apiVersion/kind/namespace/name
# ---------------------------------------------------------------------------
import_resource \
  "kubectl_manifest.backstage_linkerd_exception (Kyverno PolicyException)" \
  "${MODULE_PREFIX}.kubectl_manifest.backstage_linkerd_exception" \
  "kyverno.io/v2beta1/PolicyException/staging-platform-backstage/backstage-linkerd-exception"

# ---------------------------------------------------------------------------
# Verificação pós-import: drift restante
# ---------------------------------------------------------------------------
log_info "=== Todos os imports concluídos. Verificando drift restante... ==="
echo
log_info "Executando: terraform plan -target=${MODULE_PREFIX}"
echo "-------------------------------------------------------------------"
terraform plan -target="${MODULE_PREFIX}" 2>&1 | tail -20
echo "-------------------------------------------------------------------"
echo
log_ok "=== GAP-003 resolvido. Verifique a saída do plan acima. ==="
log_info "Resultado esperado: 'No changes. Your infrastructure matches the configuration.'"
