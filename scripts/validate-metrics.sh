#!/bin/bash
# Validate Prometheus Metrics Collection
# Checks ServiceMonitors and Prometheus targets for all platform components
# Usage: ./validate-metrics.sh

set -e

echo "📊 Prometheus Metrics Validation"
echo "=================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}❌ kubectl not found${NC}"
  exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo -e "${YELLOW}⚠️  jq not found (optional, skipping JSON parsing)${NC}"
  JQ_AVAILABLE=false
else
  JQ_AVAILABLE=true
fi

echo "🔍 Step 1: Checking ServiceMonitors"
echo "-----------------------------------"

SERVICEMONITORS=$(kubectl get servicemonitor -A -o json 2>/dev/null || echo '{"items":[]}')
SM_COUNT=$(echo "$SERVICEMONITORS" | jq '.items | length' 2>/dev/null || echo "0")

if [ "$SM_COUNT" -eq 0 ]; then
  echo -e "${YELLOW}⚠️  No ServiceMonitors found${NC}"
else
  echo -e "${GREEN}✅ Found $SM_COUNT ServiceMonitors:${NC}"
  echo ""
  
  kubectl get servicemonitor -A -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
LABELS:.metadata.labels | grep -v "^$" || true
fi

echo ""
echo "🎯 Step 2: Expected ServiceMonitors"
echo "-----------------------------------"

EXPECTED_SERVICEMONITORS=(
  "kube-prometheus-stack:kube-prometheus-stack-operator"
  "kube-prometheus-stack:kube-prometheus-stack-prometheus"
  "kube-prometheus-stack:kube-prometheus-stack-kube-state-metrics"
  "kube-prometheus-stack:kube-prometheus-stack-prometheus-node-exporter"
  "harbor-system:harbor"
  "vault-system:vault"
  "external-secrets-system:external-secrets"
  "gitlab-staging:gitlab"
)

MISSING_COUNT=0

for sm in "${EXPECTED_SERVICEMONITORS[@]}"; do
  NAMESPACE=$(echo "$sm" | cut -d: -f1)
  NAME=$(echo "$sm" | cut -d: -f2)
  
  EXISTS=$(kubectl get servicemonitor -n "$NAMESPACE" "$NAME" 2>/dev/null && echo "true" || echo "false")
  
  if [ "$EXISTS" == "true" ]; then
    echo -e "${GREEN}✅${NC} $NAMESPACE/$NAME"
  else
    echo -e "${RED}❌${NC} $NAMESPACE/$NAME (missing)"
    ((MISSING_COUNT++))
  fi
done

echo ""
echo "🔗 Step 3: Prometheus Targets API"
echo "-----------------------------------"

# Port-forward Prometheus (background)
echo "Setting up port-forward to Prometheus..."
kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-prometheus 9091:9090 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

# Check targets
TARGETS_URL="http://localhost:9091/api/v1/targets"
echo "Fetching targets from: $TARGETS_URL"
echo ""

TARGETS_RESPONSE=$(curl -s "$TARGETS_URL" 2>/dev/null || echo '{"status":"error"}')
TARGETS_STATUS=$(echo "$TARGETS_RESPONSE" | jq -r '.status' 2>/dev/null || echo "error")

if [ "$TARGETS_STATUS" == "success" ]; then
  ACTIVE_COUNT=$(echo "$TARGETS_RESPONSE" | jq '[.data.activeTargets[] | select(.health == "up")] | length' 2>/dev/null || echo "0")
  DOWN_COUNT=$(echo "$TARGETS_RESPONSE" | jq '[.data.activeTargets[] | select(.health == "down")] | length' 2>/dev/null || echo "0")
  
  echo -e "${GREEN}✅ Active Targets (up): $ACTIVE_COUNT${NC}"
  echo -e "${RED}❌ Down Targets: $DOWN_COUNT${NC}"
  echo ""
  
  if [ "$DOWN_COUNT" -gt 0 ]; then
    echo "🔴 Down Targets Details:"
    echo "$TARGETS_RESPONSE" | jq -r '.data.activeTargets[] | select(.health == "down") | 
      "\(.labels.job) - \(.labels.namespace) - \(.lastError)"' 2>/dev/null || true
  fi
else
  echo -e "${YELLOW}⚠️  Unable to fetch Prometheus targets (Prometheus not running?)${NC}"
fi

# Cleanup port-forward
kill $PF_PID 2>/dev/null || true
wait $PF_PID 2>/dev/null || true

echo ""
echo "📈 Step 4: Grafana Datasource Check"
echo "-----------------------------------"

GRAFANA_DATASOURCES=$(kubectl get configmap -n kube-prometheus-stack \
  grafana-datasources -o json 2>/dev/null || echo '{}')

if [ "$(echo "$GRAFANA_DATASOURCES" | jq 'has("data")' 2>/dev/null)" == "true" ]; then
  echo -e "${GREEN}✅ Grafana datasources ConfigMap exists${NC}"
  
  PROMETHEUS_DS=$(echo "$GRAFANA_DATASOURCES" | jq -r '.data."datasource.yaml"' 2>/dev/null | \
    grep -i "prometheus" || echo "")
  
  if [ -n "$PROMETHEUS_DS" ]; then
    echo -e "${GREEN}✅ Prometheus datasource configured in Grafana${NC}"
  else
    echo -e "${YELLOW}⚠️  Prometheus datasource not found in Grafana config${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  Grafana datasources ConfigMap not found${NC}"
fi

echo ""
echo "=========================================="
echo "📊 VALIDATION SUMMARY"
echo "=========================================="
echo "ServiceMonitors found:     $SM_COUNT"
echo "ServiceMonitors missing:   $MISSING_COUNT"
echo "Prometheus targets (up):   ${ACTIVE_COUNT:-N/A}"
echo "Prometheus targets (down): ${DOWN_COUNT:-N/A}"
echo ""

if [ "$MISSING_COUNT" -eq 0 ] && [ "${DOWN_COUNT:-0}" -eq 0 ]; then
  echo -e "${GREEN}✅ All metrics validation checks passed!${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  Some metrics checks failed. Review details above.${NC}"
  exit 1
fi
