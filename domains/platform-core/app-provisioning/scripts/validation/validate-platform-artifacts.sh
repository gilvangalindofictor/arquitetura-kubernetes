#!/bin/bash
# =============================================================================
# validate-platform-artifacts.sh — Valida artefatos obrigatórios de plataforma
# =============================================================================
# Descricao: Verifica que o repositorio da aplicacao possui os artefatos
#            minimos exigidos pela plataforma conforme manifest.yaml.
# Uso:       ./validate-platform-artifacts.sh <manifest-path>
# Deps:      yq
# Ref:       GAP-PLAT-CI-01 | 2026-03-18
# =============================================================================

set -euo pipefail

MANIFEST_PATH="${1:-}"

if [[ -z "$MANIFEST_PATH" ]] || [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "ERRO: Manifesto nao encontrado: ${MANIFEST_PATH:-<vazio>}"
    exit 1
fi

ERRORS=0

check() {
    local description="$1"
    local condition="$2"  # 0=ok, 1=fail
    if [[ "$condition" == "1" ]]; then
        echo "❌ FALHA: $description"
        ERRORS=$((ERRORS + 1))
    else
        echo "✅ OK: $description"
    fi
}

echo "=== Validando artefatos de plataforma ==="
echo "Manifesto: $MANIFEST_PATH"
echo ""

# ---- Artefatos obrigatórios para TODAS as apps ----
echo "--- Artefatos obrigatórios ---"

# catalog-info.yaml
if [[ -f "catalog-info.yaml" ]]; then
    check "catalog-info.yaml existe" "0"
else
    check "catalog-info.yaml existe" "1"
fi

# Dockerfile
DOCKERFILE_FOUND=0
for f in Dockerfile "$(dirname "$MANIFEST_PATH")/../../Dockerfile" "src/Dockerfile"; do
    [[ -f "$f" ]] && DOCKERFILE_FOUND=1 && break
done
if [[ $DOCKERFILE_FOUND -eq 1 ]]; then
    check "Dockerfile existe" "0"
else
    check "Dockerfile existe" "1"
fi

# k8s/kustomization.yaml (ou .njk)
KUSTOMIZE_FOUND=0
for f in k8s/base/kustomization.yaml k8s/base/kustomization.yaml.njk k8s/kustomization.yaml; do
    [[ -f "$f" ]] && KUSTOMIZE_FOUND=1 && break
done
if [[ $KUSTOMIZE_FOUND -eq 1 ]]; then
    check "k8s/kustomization.yaml (ou .njk) existe" "0"
else
    check "k8s/kustomization.yaml (ou .njk) existe" "1"
fi

# ---- Artefatos condicionais baseados no manifest ----
echo ""
echo "--- Artefatos condicionais ---"

METRICS_ENABLED=$(yq '.observability.metrics.enabled // false' "$MANIFEST_PATH" 2>/dev/null || echo "false")
if [[ "$METRICS_ENABLED" == "true" ]]; then
    SM_FOUND=0
    for f in k8s/base/servicemonitor.yaml k8s/base/servicemonitor.yaml.njk; do
        [[ -f "$f" ]] && SM_FOUND=1 && break
    done
    if [[ $SM_FOUND -eq 1 ]]; then
        check "ServiceMonitor existe (metrics.enabled=true)" "0"
    else
        check "ServiceMonitor existe (metrics.enabled=true)" "1"
    fi
fi

INGRESS_ENABLED=$(yq '.config.ingress.enabled // false' "$MANIFEST_PATH" 2>/dev/null || echo "false")
if [[ "$INGRESS_ENABLED" == "true" ]]; then
    ING_FOUND=0
    for f in k8s/base/ingress.yaml k8s/base/ingress.yaml.njk k8s/overlays/staging/ingress.yaml; do
        [[ -f "$f" ]] && ING_FOUND=1 && break
    done
    if [[ $ING_FOUND -eq 1 ]]; then
        check "Ingress YAML existe (ingress.enabled=true)" "0"
    else
        check "Ingress YAML existe (ingress.enabled=true)" "1"
    fi
fi

echo ""
echo "=== Resultado: ${ERRORS} falha(s) ==="

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi

echo "Todos os artefatos de plataforma validados com sucesso!"
