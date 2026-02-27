#!/bin/bash
# Deploy Promtail to enable log shipping to Loki
# This script deploys Promtail as a DaemonSet to collect logs from pods

set -euo pipefail

NAMESPACE="staging-observability-monitoring"
RELEASE_NAME="promtail"
CHART_VERSION="6.16.6"

echo "================================================================"
echo "Promtail Deployment - Log Shipper for Loki"
echo "================================================================"
echo ""

# Check if Helm is available
if ! command -v helm &> /dev/null; then
    echo "❌ ERROR: helm command not found"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ ERROR: kubectl command not found"
    exit 1
fi

# Add Grafana Helm repo
echo "1. Adding Grafana Helm repository..."
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update grafana

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "❌ ERROR: Namespace $NAMESPACE does not exist"
    exit 1
fi

# Deploy Promtail
echo ""
echo "2. Deploying Promtail $CHART_VERSION..."
helm upgrade --install "$RELEASE_NAME" grafana/promtail \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    --values /home/gilvangalindo/projects/Arquitetura/Kubernetes/apps/staging/monitoring/promtail/values.yaml \
    --wait \
    --timeout 5m

# Verify deployment
echo ""
echo "3. Verifying Promtail deployment..."
sleep 5

PROMTAIL_PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=promtail --no-headers | wc -l)
PROMTAIL_READY=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=promtail --no-headers | grep -c "1/1" || echo "0")

echo "   - Total pods: $PROMTAIL_PODS"
echo "   - Ready pods: $PROMTAIL_READY"

if [ "$PROMTAIL_READY" -eq "$PROMTAIL_PODS" ] && [ "$PROMTAIL_PODS" -gt 0 ]; then
    echo ""
    echo "✅ Promtail deployed successfully!"
    echo ""
    echo "Promtail is now collecting logs from:"
    echo "  - tracing-test namespace"
    echo "  - staging-observability-monitoring namespace"
    echo ""
    echo "Logs are being shipped to: loki-gateway.staging-observability-monitoring.svc.cluster.local"
    echo ""
    echo "⏱️  Allow 30-60 seconds for logs to be ingested into Loki"
else
    echo ""
    echo "⚠️  WARNING: Not all Promtail pods are ready"
    echo "Check pod status with:"
    echo "  kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=promtail"
    exit 1
fi

echo ""
echo "================================================================"
echo "Next Steps:"
echo "1. Wait 60 seconds for log ingestion"
echo "2. Re-run correlation test script"
echo "3. Verify logs appear in Loki with trace_id fields"
echo "================================================================"
