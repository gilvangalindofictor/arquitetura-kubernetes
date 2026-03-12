#!/usr/bin/env bash
# =============================================================================
# provision-namespace.sh — Step 1 do fluxo arquitetural (thin wrapper)
# =============================================================================
# Ref:         ADR-104, GAP-D2-02
# Correcao:    O fluxo arquitetural define este script como ponto de entrada do
#              Step 1. A implementacao real reside em scripts/onboarding/create-namespace.sh
#              (Namespace + ResourceQuota + LimitRange + NetworkPolicy).
#              Este wrapper delega integralmente para aquele script, mantendo
#              o naming canonico sem duplicar logica.
#
# Uso:         ./provision-namespace.sh --name <ns> --domain <d> --product <p>
#                                       --env <e> --owner <o> [--dry-run]
#                                       [--sa-name <sa>] [--sa-namespace <ns>]
#
# Parametros:  Identicos a create-namespace.sh (todos repassados via "$@")
#   --name         Nome do namespace (obrigatorio)
#   --domain       Dominio da aplicacao (obrigatorio)
#   --product      Nome do produto/app (obrigatorio)
#   --env          Ambiente: staging | prod (obrigatorio)
#   --owner        Owner/squad responsavel (obrigatorio)
#   --dry-run      Simula execucao sem criar recursos
#   --sa-name      Nome do ServiceAccount (default: platform-provisioner)
#   --sa-namespace Namespace do ServiceAccount (default: platform-system)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONBOARDING_SCRIPT="${SCRIPT_DIR}/../onboarding/create-namespace.sh"

if [[ ! -f "${ONBOARDING_SCRIPT}" ]]; then
    echo "[ERROR] create-namespace.sh nao encontrado em: ${ONBOARDING_SCRIPT}" >&2
    exit 1
fi

# Delega todos os argumentos para create-namespace.sh
exec bash "${ONBOARDING_SCRIPT}" "$@"
