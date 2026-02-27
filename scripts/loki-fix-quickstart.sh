#!/bin/bash
set -euo pipefail

# ============================================================================
# LOKI FIX QUICKSTART SCRIPT
# ============================================================================
# Purpose: Automated fix for Loki CrashLoopBackOff (deprecated shared_store)
# Protocol: @docs/prompts/executor-terraform.md — Mesa Técnica Virtual
# Date: 2026-02-27
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="staging-observability-monitoring"
RELEASE_NAME="loki"
CHART_VERSION="6.53.0"
VALUES_FILE="docs/migrations/wave5-monitoring/loki-values-updated.yaml"

# ============================================================================
# FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

print_header "PRE-FLIGHT CHECKS"

print_step "Checking values file..."
if [ ! -f "$VALUES_FILE" ]; then
    print_error "Values file not found: $VALUES_FILE"
    exit 1
fi

if ! grep -q "delete_request_store: s3" "$VALUES_FILE"; then
    print_error "Values file missing required fix"
    exit 1
fi
print_success "Values file validated"

print_step "Current Loki pod status:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki

echo ""
echo -e "${YELLOW}Ready to execute Helm upgrade with corrected values${NC}"
echo "Press Enter to continue or Ctrl+C to cancel..."
read

# ============================================================================
# HELM UPGRADE
# ============================================================================

print_header "EXECUTING HELM UPGRADE"

print_step "Running Helm upgrade..."
helm upgrade "$RELEASE_NAME" grafana/loki \
    -n "$NAMESPACE" \
    -f "$VALUES_FILE" \
    --version "$CHART_VERSION" \
    --wait \
    --timeout 5m

print_success "Helm upgrade completed"

# ============================================================================
# VALIDATION
# ============================================================================

print_header "VALIDATION"

print_step "Waiting 10s for pods to stabilize..."
sleep 10

print_step "Pod status after upgrade:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki

print_step "Checking for CrashLoopBackOff..."
CRASH_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)

if [ "$CRASH_COUNT" -eq 0 ]; then
    print_success "All Loki pods healthy!"
else
    print_warning "$CRASH_COUNT pod(s) not Running - check with: kubectl describe pod -n $NAMESPACE"
fi

print_header "COMPLETE"
echo "Monitor pods: kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=loki -w"
