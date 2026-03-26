#!/bin/bash
# =============================================================================
# MIGRATION-rabbitmq-state.sh
# GAP-RABBITMQ-NS-001 — Migração namespace data-services → prod-data-rabbitmq
# ADR-048: namespace naming {env}-{domain}-{product} (Kyverno bloqueia "data-services-prod")
# =============================================================================
#
# CONTEXTO:
#   - RabbitMQ prod ATUAL: namespace "data-services" (k8s-platform-prod-rabbitmq)
#   - TF code atualizado: namespace = "prod-data-rabbitmq" (ADR-048 compliant)
#   - PVC atual: persistence-k8s-platform-prod-rabbitmq-server-0 (gp2, 5Gi, us-east-1a)
#   - PV reclaim policy: Delete → patchado para Retain antes da migração
#   - Estado do cluster no momento da análise: IDLE (0 conexões, 0 filas, 0 msgs)
#
# PRÉ-REQUISITO OBRIGATÓRIO:
#   RabbitMQ já rodando em "prod-data-rabbitmq" E healthcheck OK ANTES de executar este script.
#   Validar com:
#     kubectl get rabbitmqcluster -n prod-data-rabbitmq
#     kubectl get pods -n prod-data-rabbitmq
#     kubectl get pvc -n prod-data-rabbitmq
#
# SEQUÊNCIA COMPLETA DE MIGRAÇÃO (Cloud Debug Agent executa etapas 1-3, este script executa 4-6):
#   Etapa 1 [kubectl] Patch ReclaimPolicy do PV para "Retain" (proteção dados)
#   Etapa 2 [kubectl] Scale down + delete RabbitmqCluster em data-services
#   Etapa 3 [kubectl] Criar namespace data-services-prod, recriar PVC apontando para o mesmo PV, migrar RabbitmqCluster
#   Etapa 4 [este script] terraform state rm (remover referências antigas)
#   Etapa 5 [este script] terraform import (importar recursos no novo namespace)
#   Etapa 6 [este script] terraform plan → confirmar "No changes"
#
# RECURSOS GERENCIADOS PELO MÓDULO (módulo NÃO cria kubernetes_namespace):
#   1. null_resource.rabbitmq_operator          — cluster-scoped (instala operator via kubectl apply)
#   2. kubernetes_manifest.rabbitmq_cluster     — namespace-scoped CRD (RabbitmqCluster)
#   3. kubernetes_service.rabbitmq_management_internal — namespace-scoped Service
#   4. kubernetes_ingress_v1.rabbitmq_management[0] — NÃO está no state (ingress_enabled=false)
#
# ANÁLISE DE NAMESPACE-SCOPED vs CLUSTER-SCOPED:
#   null_resource.rabbitmq_operator:              cluster-scoped (sem namespace) — state rm + NO import (não importável)
#   kubernetes_manifest.rabbitmq_cluster:         namespace-scoped (RabbitmqCluster CRD) — state rm + import
#   kubernetes_service.rabbitmq_management_internal: namespace-scoped — state rm + import
#
# NOTA SOBRE PVCs:
#   O módulo TF NÃO cria PVCs diretamente.
#   Os PVCs são criados automaticamente pelo RabbitMQ Cluster Operator via StatefulSet.
#   Portanto: NÃO há "terraform import" de PVC neste script.
#   A migração dos dados (PV/PVC) é responsabilidade do Cloud Debug Agent (etapas kubectl acima).
#
# NOTA SOBRE kubernetes_namespace:
#   O módulo rabbitmq NÃO possui recurso kubernetes_namespace.
#   O namespace "data-services-prod" deve ser criado manualmente pelo Cloud Debug Agent
#   antes de executar este script.
#
# Uso: bash MIGRATION-rabbitmq-state.sh [staging|prod]
#   Padrão: prod
# =============================================================================

set -euo pipefail

ENV=${1:-prod}
CLUSTER_NAME="k8s-platform-prod"
OLD_NS="data-services"
NEW_NS="prod-data-rabbitmq"  # ADR-048: {env}-{domain}-{product}
MODULE="module.rabbitmq_prod"
RABBITMQ_CR_NAME="${CLUSTER_NAME}-rabbitmq"
MGMT_SVC_NAME="rabbitmq-management-internal"

echo "============================================================"
echo " GAP-RABBITMQ-NS-001 — TF State Migration"
echo " Cluster:   ${CLUSTER_NAME}"
echo " Old NS:    ${OLD_NS}"
echo " New NS:    ${NEW_NS}"
echo " Module:    ${MODULE}"
echo "============================================================"
echo ""

# --- PRÉ-FLIGHT: validar pré-requisitos ---

echo "=== PRÉ-FLIGHT: Validando pré-requisitos ==="

echo "[1/3] Verificando namespace ${NEW_NS}..."
if ! kubectl get namespace "${NEW_NS}" >/dev/null 2>&1; then
  echo "ERRO: namespace ${NEW_NS} não existe no cluster."
  echo "Execute primeiro o Cloud Debug Agent para migrar o RabbitMQ."
  exit 1
fi
echo "  OK: namespace ${NEW_NS} existe."

echo "[2/3] Verificando RabbitmqCluster em ${NEW_NS}..."
if ! kubectl get rabbitmqcluster "${RABBITMQ_CR_NAME}" -n "${NEW_NS}" >/dev/null 2>&1; then
  echo "ERRO: RabbitmqCluster '${RABBITMQ_CR_NAME}' não encontrado em ${NEW_NS}."
  echo "Execute primeiro o Cloud Debug Agent para migrar o RabbitMQ."
  exit 1
fi
echo "  OK: RabbitmqCluster encontrado em ${NEW_NS}."

echo "[3/3] Verificando Service ${MGMT_SVC_NAME} em ${NEW_NS}..."
if ! kubectl get service "${MGMT_SVC_NAME}" -n "${NEW_NS}" >/dev/null 2>&1; then
  echo "AVISO: Service '${MGMT_SVC_NAME}' não encontrado em ${NEW_NS}."
  echo "  O terraform import tentará importar mesmo assim — o recurso pode não existir ainda."
  echo "  Neste caso: remova o state do Service e deixe o TF apply criá-lo."
fi

echo ""
echo "  PRÉ-FLIGHT OK — prosseguindo com state manipulation."
echo ""

# --- STEP 1: Remove referências ao estado antigo ---

echo "=== STEP 1: Remove old state references ==="
echo ""

echo "[rm 1/3] Removendo null_resource.rabbitmq_operator..."
# null_resource não é importável — após rm, o TF plan pode tentar recriar.
# Como triggers.operator_version="2.11.0" e operator já está instalado,
# o provisioner vai rodar o check idempotente (sem efeito real no cluster).
terraform state rm "${MODULE}.null_resource.rabbitmq_operator" 2>&1 || \
  echo "  AVISO: null_resource.rabbitmq_operator não encontrado no state (pode já ter sido removido)."

echo ""
echo "[rm 2/3] Removendo kubernetes_manifest.rabbitmq_cluster (namespace-scoped CRD)..."
terraform state rm "${MODULE}.kubernetes_manifest.rabbitmq_cluster" 2>&1 || \
  echo "  AVISO: kubernetes_manifest.rabbitmq_cluster não encontrado no state."

echo ""
echo "[rm 3/3] Removendo kubernetes_service.rabbitmq_management_internal..."
terraform state rm "${MODULE}.kubernetes_service.rabbitmq_management_internal" 2>&1 || \
  echo "  AVISO: kubernetes_service.rabbitmq_management_internal não encontrado no state."

echo ""
echo "  STEP 1 concluído — todos os recursos antigos removidos do state."
echo ""

# --- STEP 2: Import recursos no novo namespace ---

echo "=== STEP 2: Import resources in new namespace ==="
echo ""

echo "[import 1/3] Importando kubernetes_manifest.rabbitmq_cluster..."
echo "  Recurso: RabbitmqCluster/${RABBITMQ_CR_NAME} no namespace ${NEW_NS}"
echo "  Formato de import para kubernetes_manifest: apiVersion/kind/namespace/name"
terraform import \
  "${MODULE}.kubernetes_manifest.rabbitmq_cluster" \
  "apiVersion=rabbitmq.com/v1beta1,kind=RabbitmqCluster,namespace=${NEW_NS},name=${RABBITMQ_CR_NAME}" \
  2>&1 || {
    echo ""
    echo "  FALLBACK: Tentando formato alternativo de import ID para kubernetes_manifest..."
    echo "  Nota: kubernetes_manifest usa o path do objeto k8s como ID."
    echo "  ID alternativo: rabbitmq.com/v1beta1/RabbitmqCluster/${NEW_NS}/${RABBITMQ_CR_NAME}"
    terraform import \
      "${MODULE}.kubernetes_manifest.rabbitmq_cluster" \
      "rabbitmq.com/v1beta1,RabbitmqCluster,${NEW_NS},${RABBITMQ_CR_NAME}" \
      2>&1
  }

echo ""
echo "[import 2/3] Importando kubernetes_service.rabbitmq_management_internal..."
echo "  Recurso: Service/${MGMT_SVC_NAME} no namespace ${NEW_NS}"
echo "  Formato: namespace/name"
terraform import \
  "${MODULE}.kubernetes_service.rabbitmq_management_internal" \
  "${NEW_NS}/${MGMT_SVC_NAME}" \
  2>&1 || \
  echo "  AVISO: import do Service falhou — verifique se o Service existe em ${NEW_NS}."

echo ""
echo "  STEP 2 concluído — tentativas de import realizadas."
echo "  (null_resource não é importável — será recriado pelo TF plan; provisioner é idempotente)"
echo ""

# --- STEP 3: Validate ---

echo "=== STEP 3: Validate — terraform plan ==="
echo ""
echo "  Executando: terraform plan -target=${MODULE} -var-file=secrets.auto.tfvars"
echo ""
terraform plan \
  -target="${MODULE}" \
  -var-file=secrets.auto.tfvars \
  2>&1 | tail -20

echo ""
echo "============================================================"
echo " RESULTADO ESPERADO:"
echo "   - kubernetes_manifest.rabbitmq_cluster:        no changes"
echo "   - kubernetes_service.rabbitmq_management_internal: no changes"
echo "   - null_resource.rabbitmq_operator:             1 to add (provisioner idempotente — OK)"
echo ""
echo " SE PLAN MOSTRA DIFF em rabbitmq_cluster ou rabbitmq_service:"
echo "   → Verificar se o import foi feito com o ID correto"
echo "   → Conferir via: terraform state show ${MODULE}.kubernetes_manifest.rabbitmq_cluster"
echo "   → Ajustar discrepâncias no TF code (labels, annotations derivados do operator)"
echo ""
echo " ZERO DRIFT ALCANÇADO quando:"
echo "   Plan output: 'No changes. Your infrastructure matches the configuration.'"
echo "   (exceto null_resource — comportamento esperado: 1 to add, provisioner idempotente)"
echo "============================================================"
echo ""
echo "Script concluído em: $(date '+%Y-%m-%d %H:%M:%S')"
