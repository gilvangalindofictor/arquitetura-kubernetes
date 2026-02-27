#!/bin/bash
set -euo pipefail

# Script para aplicar dashboards Marco 4 no Grafana via ConfigMaps
# Data: 2026-02-24
# Autor: Claude Code

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="monitoring"

echo "========================================="
echo "Marco 4 Dashboards Deployment"
echo "========================================="
echo "Namespace: $NAMESPACE"
echo "Dashboard directory: $SCRIPT_DIR"
echo ""

# Verificar se estamos conectados ao cluster
if ! kubectl cluster-info &>/dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "Please authenticate first (aws sso login or similar)"
    exit 1
fi

# Verificar se namespace existe
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "ERROR: Namespace $NAMESPACE does not exist"
    exit 1
fi

# Função para criar ConfigMap a partir de JSON
create_configmap() {
    local dashboard_file=$1
    local dashboard_name=$(basename "$dashboard_file" .json)
    local configmap_name="${dashboard_name}-dashboard"

    echo "Creating ConfigMap: $configmap_name"

    # Criar ConfigMap
    kubectl create configmap "$configmap_name" \
        --from-file="$dashboard_file" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | \
    kubectl label --local -f - \
        grafana_dashboard=1 \
        --dry-run=client -o yaml | \
    kubectl annotate --local -f - \
        description="Marco 4 Dashboard: $dashboard_name" \
        --dry-run=client -o yaml | \
    kubectl apply -f -

    echo "✓ ConfigMap $configmap_name created/updated"
}

# Aplicar cada dashboard
echo "Applying dashboards..."
echo ""

DASHBOARDS=(
    "gitlab-cicd-overview.json"
    "argocd-sync-status.json"
    "sonarqube-quality-metrics.json"
    "keycloak-sso-usage.json"
    "harbor-registry-overview.json"
    "trace-log-correlation-demo.json"
)

for dashboard in "${DASHBOARDS[@]}"; do
    dashboard_path="$SCRIPT_DIR/$dashboard"

    if [ -f "$dashboard_path" ]; then
        create_configmap "$dashboard_path"
    else
        echo "WARNING: Dashboard not found: $dashboard_path"
    fi
    echo ""
done

echo "========================================="
echo "Deployment Summary"
echo "========================================="

# Listar ConfigMaps criados
echo "ConfigMaps with label grafana_dashboard=1:"
kubectl get configmaps -n "$NAMESPACE" -l grafana_dashboard=1 | grep -E 'marco4|gitlab|argocd|sonarqube|keycloak' || echo "None found"

echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo "1. Wait ~30s for Grafana to auto-import dashboards"
echo "2. Access Grafana UI and navigate to Dashboards"
echo "3. Look for dashboards tagged with 'marco4'"
echo "4. Verify panels are showing data (not 'No data')"
echo ""
echo "Troubleshooting:"
echo "- Check Grafana logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=grafana"
echo "- Verify Prometheus scraping: kubectl get servicemonitors -A"
echo "- Check datasource config: Grafana UI -> Configuration -> Data Sources"
echo ""
echo "Deployment complete!"
