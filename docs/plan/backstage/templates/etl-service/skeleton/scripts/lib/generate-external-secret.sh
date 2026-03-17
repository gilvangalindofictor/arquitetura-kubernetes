#!/usr/bin/env bash
# generate-external-secret.sh — Utilitário para gerar ExternalSecret YAML standalone
# Uso: APP_NAME=meu-etl NAMESPACE=staging-data-meu-etl ./generate-external-secret.sh
#
# NOTA: A lógica de geração principal está em provision.sh (função generate_external_secret).
# Este script é um utilitário auxiliar para inspecionar/gerar o ExternalSecret fora do pipeline.
set -euo pipefail

APP_NAME="${APP_NAME:?APP_NAME não definido}"
NAMESPACE="${NAMESPACE:-staging-data-${APP_NAME}}"
export MANIFEST="${MANIFEST:-${CI_PROJECT_DIR:-.}/.platform/manifest.yaml}"

# Delega para provision.sh em modo de geração
# shellcheck source=../provision.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../provision.sh" 2>/dev/null || true

# Gera e imprime o ExternalSecret sem aplicar
DRY_RUN=true VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}" \
  VAULT_TOKEN="${VAULT_TOKEN:-test}" \
  KUBECONFIG="${KUBECONFIG:-/dev/null}" \
  CI_PROJECT_DIR="${CI_PROJECT_DIR:-.}" \
  generate_external_secret 2>/dev/null || echo "Erro: provision.sh não encontrado ou APP_NAME não definido"

echo "# ExternalSecret gerado para $APP_NAME (namespace: $NAMESPACE)"
