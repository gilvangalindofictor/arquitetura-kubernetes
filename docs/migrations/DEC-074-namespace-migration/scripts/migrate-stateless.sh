#!/bin/bash
# migrate-stateless.sh - Pattern A: Stateless Service Migration
# Usage: ./migrate-stateless.sh <old-namespace> <new-namespace> <helm-release> [helm-chart-repo/chart-name]
#
# Example:
#   ./migrate-stateless.sh cert-manager staging-security-certmanager cert-manager jetstack/cert-manager
#
# Pattern A: Used for stateless services with no PVCs
# - cert-manager, external-secrets-system, kyverno, redis-operator, test namespaces

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Arguments
OLD_NS="${1:-}"
NEW_NS="${2:-}"
HELM_RELEASE="${3:-}"
HELM_CHART="${4:-}"

# Validation
if [ -z "$OLD_NS" ] || [ -z "$NEW_NS" ] || [ -z "$HELM_RELEASE" ]; then
  echo -e "${RED}Error: Missing required arguments${NC}"
  echo "Usage: $0 <old-namespace> <new-namespace> <helm-release> [helm-chart]"
  exit 1
fi

# Logging
LOG_FILE="migration-${OLD_NS}-to-${NEW_NS}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "Pattern A: Stateless Service Migration"
echo "=================================================="
echo "Old Namespace: $OLD_NS"
echo "New Namespace: $NEW_NS"
echo "Helm Release:  $HELM_RELEASE"
echo "Helm Chart:    ${HELM_CHART:-N/A}"
echo "Start Time:    $(date)"
echo "=================================================="
echo ""

# Function: Check prerequisites
check_prerequisites() {
  echo -e "${YELLOW}[1/8] Checking prerequisites...${NC}"

  if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
  fi

  if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm not found${NC}"
    exit 1
  fi

  if ! kubectl get namespace "$OLD_NS" &> /dev/null; then
    echo -e "${RED}Error: Old namespace $OLD_NS does not exist${NC}"
    exit 1
  fi

  if kubectl get namespace "$NEW_NS" &> /dev/null; then
    echo -e "${RED}Error: New namespace $NEW_NS already exists${NC}"
    exit 1
  fi

  echo -e "${GREEN}✓ Prerequisites OK${NC}"
  echo ""
}

# Function: Backup current state
backup_current_state() {
  echo -e "${YELLOW}[2/8] Backing up current state...${NC}"

  BACKUP_DIR="backup-${OLD_NS}-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"

  # Export Helm values
  if helm list -n "$OLD_NS" | grep -q "$HELM_RELEASE"; then
    echo "Exporting Helm values for $HELM_RELEASE..."
    helm get values "$HELM_RELEASE" -n "$OLD_NS" > "$BACKUP_DIR/helm-values.yaml"
    helm get manifest "$HELM_RELEASE" -n "$OLD_NS" > "$BACKUP_DIR/helm-manifest.yaml"
    echo -e "${GREEN}✓ Helm values exported${NC}"
  else
    echo -e "${YELLOW}Warning: Helm release $HELM_RELEASE not found in $OLD_NS${NC}"
  fi

  # Export all resources
  echo "Exporting all resources from $OLD_NS..."
  kubectl get all -n "$OLD_NS" -o yaml > "$BACKUP_DIR/all-resources.yaml" 2>/dev/null || true

  # Export CRDs (if any)
  echo "Exporting Custom Resources..."
  kubectl get crd -o name | while read -r crd; do
    CRD_NAME=$(echo "$crd" | cut -d'/' -f2)
    kubectl get "$crd" -n "$OLD_NS" -o yaml > "$BACKUP_DIR/cr-${CRD_NAME}.yaml" 2>/dev/null || true
  done

  # Document current state
  cat > "$BACKUP_DIR/state-snapshot.txt" <<EOF
Migration Date: $(date)
Old Namespace: $OLD_NS
New Namespace: $NEW_NS
Helm Release: $HELM_RELEASE

Pod Count:
$(kubectl get pods -n "$OLD_NS" --no-headers | wc -l)

Pods:
$(kubectl get pods -n "$OLD_NS" -o wide)

Services:
$(kubectl get svc -n "$OLD_NS")

Ingress:
$(kubectl get ingress -n "$OLD_NS" 2>/dev/null || echo "None")
EOF

  echo -e "${GREEN}✓ Backup saved to $BACKUP_DIR/${NC}"
  echo ""
}

# Function: Create new namespace
create_new_namespace() {
  echo -e "${YELLOW}[3/8] Creating new namespace $NEW_NS...${NC}"

  # Extract labels from old namespace
  OLD_LABELS=$(kubectl get namespace "$OLD_NS" -o jsonpath='{.metadata.labels}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')

  # Create namespace
  kubectl create namespace "$NEW_NS"

  # Apply labels (preserve existing labels from old namespace)
  if [ -n "$OLD_LABELS" ]; then
    IFS=',' read -ra LABEL_ARRAY <<< "$OLD_LABELS"
    for label in "${LABEL_ARRAY[@]}"; do
      kubectl label namespace "$NEW_NS" "$label" --overwrite
    done
  fi

  # Add migration metadata
  kubectl label namespace "$NEW_NS" \
    migration-source="$OLD_NS" \
    migration-date="$(date +%Y-%m-%d)" \
    migration-pattern="A-stateless" \
    --overwrite

  echo -e "${GREEN}✓ Namespace $NEW_NS created with labels${NC}"
  echo ""
}

# Function: Deploy to new namespace
deploy_to_new_namespace() {
  echo -e "${YELLOW}[4/8] Deploying to new namespace...${NC}"

  if [ -n "$HELM_CHART" ]; then
    # Deploy using Helm chart
    echo "Deploying Helm chart $HELM_CHART..."

    if [ -f "$BACKUP_DIR/helm-values.yaml" ]; then
      helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" \
        -n "$NEW_NS" \
        -f "$BACKUP_DIR/helm-values.yaml" \
        --timeout 10m \
        --wait
    else
      echo -e "${YELLOW}Warning: No helm-values.yaml found, deploying with defaults${NC}"
      helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" \
        -n "$NEW_NS" \
        --timeout 10m \
        --wait
    fi

    echo -e "${GREEN}✓ Helm deployment complete${NC}"
  else
    # Deploy using kubectl (manifests)
    echo "Deploying from backup manifests..."

    if [ -f "$BACKUP_DIR/helm-manifest.yaml" ]; then
      # Modify namespace in manifest
      sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" "$BACKUP_DIR/helm-manifest.yaml" | kubectl apply -f -
      echo -e "${GREEN}✓ Manifests applied${NC}"
    else
      echo -e "${YELLOW}Warning: No manifests found, skipping deployment${NC}"
    fi
  fi

  echo ""
}

# Function: Wait for pods ready
wait_for_pods_ready() {
  echo -e "${YELLOW}[5/8] Waiting for pods to be ready...${NC}"

  echo "Waiting for all pods in $NEW_NS to be Running..."
  kubectl wait --for=condition=Ready pod --all -n "$NEW_NS" --timeout=10m || {
    echo -e "${RED}Error: Pods did not become ready within 10 minutes${NC}"
    echo "Current pod status:"
    kubectl get pods -n "$NEW_NS"
    echo ""
    echo "Pod logs (last 50 lines):"
    kubectl logs -n "$NEW_NS" --all-containers --tail=50
    exit 1
  }

  echo -e "${GREEN}✓ All pods ready${NC}"
  echo ""
}

# Function: Validate deployment
validate_deployment() {
  echo -e "${YELLOW}[6/8] Validating deployment...${NC}"

  # Check pod count
  OLD_POD_COUNT=$(kubectl get pods -n "$OLD_NS" --no-headers 2>/dev/null | wc -l || echo "0")
  NEW_POD_COUNT=$(kubectl get pods -n "$NEW_NS" --no-headers 2>/dev/null | wc -l || echo "0")

  echo "Pod count comparison:"
  echo "  Old namespace: $OLD_POD_COUNT pods"
  echo "  New namespace: $NEW_POD_COUNT pods"

  if [ "$NEW_POD_COUNT" -eq 0 ]; then
    echo -e "${RED}Error: No pods running in new namespace${NC}"
    exit 1
  fi

  # Check service endpoints
  echo ""
  echo "Service endpoints in new namespace:"
  kubectl get svc -n "$NEW_NS"

  # Check for CrashLoopBackOff
  CRASH_PODS=$(kubectl get pods -n "$NEW_NS" --field-selector=status.phase!=Running --no-headers 2>/dev/null || true)
  if [ -n "$CRASH_PODS" ]; then
    echo -e "${RED}Warning: Non-running pods detected:${NC}"
    echo "$CRASH_PODS"
  fi

  # Check ingress (if exists)
  if kubectl get ingress -n "$NEW_NS" &> /dev/null; then
    echo ""
    echo "Ingress endpoints:"
    kubectl get ingress -n "$NEW_NS"
  fi

  echo -e "${GREEN}✓ Validation complete${NC}"
  echo ""
}

# Function: Update ingress DNS (if applicable)
update_ingress() {
  echo -e "${YELLOW}[7/8] Checking ingress configuration...${NC}"

  INGRESS_COUNT=$(kubectl get ingress -n "$NEW_NS" --no-headers 2>/dev/null | wc -l || echo "0")

  if [ "$INGRESS_COUNT" -gt 0 ]; then
    echo "Found $INGRESS_COUNT ingress resource(s) in $NEW_NS"
    kubectl get ingress -n "$NEW_NS" -o wide
    echo ""
    echo -e "${YELLOW}Note: Ingress DNS should automatically route to new namespace${NC}"
    echo "Test ingress endpoints manually:"
    kubectl get ingress -n "$NEW_NS" -o jsonpath='{.items[*].spec.rules[*].host}' | tr ' ' '\n' | while read -r host; do
      echo "  curl -I https://$host"
    done
  else
    echo "No ingress resources found (OK for backend services)"
  fi

  echo ""
}

# Function: Summary and next steps
show_summary() {
  echo -e "${YELLOW}[8/8] Migration Summary${NC}"
  echo "=================================================="
  echo -e "${GREEN}✓ Migration COMPLETE${NC}"
  echo ""
  echo "Old Namespace: $OLD_NS (STILL EXISTS)"
  echo "New Namespace: $NEW_NS (OPERATIONAL)"
  echo ""
  echo "Next Steps:"
  echo "1. Validate application functionality in $NEW_NS"
  echo "2. Test ingress endpoints (if applicable)"
  echo "3. Monitor logs for errors:"
  echo "   kubectl logs -n $NEW_NS --all-containers --tail=100 -f"
  echo "4. After 7 days validation, delete old namespace:"
  echo "   kubectl delete namespace $OLD_NS"
  echo ""
  echo "Rollback (if needed):"
  echo "  kubectl delete namespace $NEW_NS"
  echo "  # Old namespace $OLD_NS remains operational"
  echo ""
  echo "End Time: $(date)"
  echo "Log File: $LOG_FILE"
  echo "Backup:   $BACKUP_DIR/"
  echo "=================================================="
}

# Main execution
main() {
  check_prerequisites
  backup_current_state
  create_new_namespace
  deploy_to_new_namespace
  wait_for_pods_ready
  validate_deployment
  update_ingress
  show_summary
}

# Run migration
main
