#!/bin/bash
# Thin wrapper — provision-argocd.sh em provisioning/ delega para onboarding/
# Mantém consistência de interface: todos os provision-*.sh em scripts/provisioning/
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../onboarding/provision-argocd.sh" "$@"
