#!/bin/bash
# VPA Objects Deployment Script
# WARNING: Only run after VPA controller installation is verified

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔬 VPA Objects Deployment - K8s Platform Staging"
echo "================================================="
echo ""

# Check if VPA CRD exists
if ! kubectl get crd verticalpodautoscalers.autoscaling.k8s.io &>/dev/null; then
    echo "❌ ERROR: VPA CRD not found. Install VPA controller first."
    exit 1
fi

# Check VPA controller pods
echo "✅ Checking VPA controller status..."
if ! kubectl get pods -n kube-system -l app=vpa-recommender &>/dev/null; then
    echo "⚠️  WARNING: VPA recommender not found in kube-system namespace"
fi

echo ""
echo "📊 VPA Objects to deploy:"
echo "  - P0 (Critical): 4 workloads"
echo "  - P1 (Important): 4 workloads"
echo "  - P2 (Desirable): 4 workloads"
echo ""

read -p "Proceed with deployment? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Deployment cancelled."
    exit 0
fi

echo ""
echo "🚀 Deploying P0 - Critical workloads..."
kubectl apply -f "$SCRIPT_DIR/p0-critical.yaml"

echo ""
echo "🚀 Deploying P1 - Important workloads..."
kubectl apply -f "$SCRIPT_DIR/p1-important.yaml"

echo ""
echo "🚀 Deploying P2 - Desirable workloads..."
kubectl apply -f "$SCRIPT_DIR/p2-desirable.yaml"

echo ""
echo "✅ VPA objects deployed successfully!"
echo ""
echo "📈 Verify deployment:"
echo "  kubectl get vpa -A"
echo ""
echo "📊 Check recommendations (after 30 days):"
echo "  kubectl describe vpa -n vault-system vault"
echo "  kubectl describe vpa -n keycloak keycloak"
echo "  kubectl describe vpa -n gitlab-staging gitlab-webservice"
echo "  kubectl describe vpa -n monitoring prometheus"
echo ""
echo "💾 Export snapshot:"
echo "  kubectl get vpa -A -o json > /tmp/vpa-$(date +%Y%m%d).json"
echo ""
