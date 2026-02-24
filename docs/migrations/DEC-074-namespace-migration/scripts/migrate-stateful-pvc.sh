#!/bin/bash
# migrate-stateful-pvc.sh - Pattern C: StatefulSet with PVCs Migration
# Usage: ./migrate-stateful-pvc.sh <old-namespace> <new-namespace> <helm-release> <helm-chart-repo/chart-name>
#
# Example:
#   ./migrate-stateful-pvc.sh harbor-system staging-platform-harbor k8s-platform-prod-harbor harbor/harbor
#
# Pattern C: Used for stateful services with PVCs (HIGH RISK)
# - gitlab-staging, harbor-system, monitoring, vault-system, data-services

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Arguments
OLD_NS="${1:-}"
NEW_NS="${2:-}"
HELM_RELEASE="${3:-}"
HELM_CHART="${4:-}"

# Configuration
SNAPSHOT_CLASS="${SNAPSHOT_CLASS:-ebs-csi-snapshot-class}"
STORAGE_CLASS="${STORAGE_CLASS:-gp3}"
TIMEOUT_SNAPSHOT="${TIMEOUT_SNAPSHOT:-20m}"
TIMEOUT_PODS="${TIMEOUT_PODS:-30m}"

# Validation
if [ -z "$OLD_NS" ] || [ -z "$NEW_NS" ] || [ -z "$HELM_RELEASE" ] || [ -z "$HELM_CHART" ]; then
  echo -e "${RED}Error: Missing required arguments${NC}"
  echo "Usage: $0 <old-namespace> <new-namespace> <helm-release> <helm-chart>"
  exit 1
fi

# Logging
LOG_FILE="migration-stateful-${OLD_NS}-to-${NEW_NS}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "Pattern C: StatefulSet + PVC Migration (HIGH RISK)"
echo "=================================================="
echo "Old Namespace:   $OLD_NS"
echo "New Namespace:   $NEW_NS"
echo "Helm Release:    $HELM_RELEASE"
echo "Helm Chart:      $HELM_CHART"
echo "Snapshot Class:  $SNAPSHOT_CLASS"
echo "Storage Class:   $STORAGE_CLASS"
echo "Start Time:      $(date)"
echo "=================================================="
echo ""
echo -e "${RED}WARNING: This is a HIGH RISK migration with potential data loss!${NC}"
echo -e "${YELLOW}Press Ctrl+C to abort, or Enter to continue...${NC}"
read -r

# Function: Check prerequisites
check_prerequisites() {
  echo -e "${YELLOW}[1/10] Checking prerequisites...${NC}"

  # Check commands
  for cmd in kubectl helm jq; do
    if ! command -v "$cmd" &> /dev/null; then
      echo -e "${RED}Error: $cmd not found${NC}"
      exit 1
    fi
  done

  # Check namespaces
  if ! kubectl get namespace "$OLD_NS" &> /dev/null; then
    echo -e "${RED}Error: Old namespace $OLD_NS does not exist${NC}"
    exit 1
  fi

  if kubectl get namespace "$NEW_NS" &> /dev/null; then
    echo -e "${RED}Error: New namespace $NEW_NS already exists${NC}"
    exit 1
  fi

  # Check VolumeSnapshotClass
  if ! kubectl get volumesnapshotclass "$SNAPSHOT_CLASS" &> /dev/null; then
    echo -e "${RED}Error: VolumeSnapshotClass $SNAPSHOT_CLASS not found${NC}"
    exit 1
  fi

  echo -e "${GREEN}✓ Prerequisites OK${NC}"
  echo ""
}

# Function: Backup current state
backup_current_state() {
  echo -e "${YELLOW}[2/10] Backing up current state...${NC}"

  BACKUP_DIR="backup-${OLD_NS}-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"

  # Export Helm values
  echo "Exporting Helm values for $HELM_RELEASE..."
  helm get values "$HELM_RELEASE" -n "$OLD_NS" > "$BACKUP_DIR/helm-values.yaml"
  helm get manifest "$HELM_RELEASE" -n "$OLD_NS" > "$BACKUP_DIR/helm-manifest.yaml"

  # Export all resources
  echo "Exporting all resources from $OLD_NS..."
  kubectl get all -n "$OLD_NS" -o yaml > "$BACKUP_DIR/all-resources.yaml"

  # Export PVC details
  echo "Exporting PVC details..."
  kubectl get pvc -n "$OLD_NS" -o json > "$BACKUP_DIR/pvcs.json"
  kubectl get pvc -n "$OLD_NS" -o yaml > "$BACKUP_DIR/pvcs.yaml"

  # Document PVC inventory
  PVC_COUNT=$(kubectl get pvc -n "$OLD_NS" --no-headers | wc -l)
  echo "Found $PVC_COUNT PVC(s) in $OLD_NS:"
  kubectl get pvc -n "$OLD_NS" -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,STATUS:.status.phase

  # Calculate total storage
  TOTAL_STORAGE=$(kubectl get pvc -n "$OLD_NS" -o json | jq -r '[.items[].spec.resources.requests.storage | gsub("Gi";"") | tonumber] | add')
  echo ""
  echo "Total storage: ${TOTAL_STORAGE}Gi"

  # Estimate snapshot time (rule of thumb: 1GB = 1-2 minutes)
  ESTIMATED_TIME=$((TOTAL_STORAGE * 2))
  echo -e "${BLUE}Estimated snapshot time: ~${ESTIMATED_TIME} minutes${NC}"

  # Document current state
  cat > "$BACKUP_DIR/state-snapshot.txt" <<EOF
Migration Date: $(date)
Old Namespace: $OLD_NS
New Namespace: $NEW_NS
Helm Release: $HELM_RELEASE
PVC Count: $PVC_COUNT
Total Storage: ${TOTAL_STORAGE}Gi

StatefulSets:
$(kubectl get statefulsets -n "$OLD_NS" 2>/dev/null || echo "None")

PVCs:
$(kubectl get pvc -n "$OLD_NS")

Pods:
$(kubectl get pods -n "$OLD_NS" -o wide)
EOF

  echo -e "${GREEN}✓ Backup saved to $BACKUP_DIR/${NC}"
  echo ""
}

# Function: Create VolumeSnapshots
create_volume_snapshots() {
  echo -e "${YELLOW}[3/10] Creating VolumeSnapshots for all PVCs...${NC}"

  SNAPSHOT_DIR="$BACKUP_DIR/snapshots"
  mkdir -p "$SNAPSHOT_DIR"

  # Get all PVCs
  kubectl get pvc -n "$OLD_NS" -o json | jq -r '.items[] | .metadata.name' | while read -r pvc_name; do
    SNAPSHOT_NAME="${pvc_name}-snapshot-$(date +%Y%m%d-%H%M%S)"

    echo "Creating snapshot for PVC: $pvc_name → $SNAPSHOT_NAME"

    # Create VolumeSnapshot manifest
    cat > "$SNAPSHOT_DIR/${pvc_name}-snapshot.yaml" <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $SNAPSHOT_NAME
  namespace: $OLD_NS
  labels:
    migration-source-ns: $OLD_NS
    migration-target-ns: $NEW_NS
    migration-date: "$(date +%Y-%m-%d)"
spec:
  volumeSnapshotClassName: $SNAPSHOT_CLASS
  source:
    persistentVolumeClaimName: $pvc_name
EOF

    # Apply snapshot
    kubectl apply -f "$SNAPSHOT_DIR/${pvc_name}-snapshot.yaml"

    # Store snapshot name for later use
    echo "$SNAPSHOT_NAME" >> "$SNAPSHOT_DIR/snapshot-list.txt"
  done

  echo ""
  echo -e "${BLUE}Waiting for all snapshots to be ready...${NC}"
  echo "This may take 10-30 minutes depending on PVC size."

  # Wait for all snapshots
  while read -r snapshot_name; do
    echo "Waiting for snapshot: $snapshot_name"
    kubectl wait --for=condition=readyToUse \
      volumesnapshot/"$snapshot_name" \
      -n "$OLD_NS" \
      --timeout="$TIMEOUT_SNAPSHOT" || {
        echo -e "${RED}Error: Snapshot $snapshot_name failed${NC}"
        kubectl describe volumesnapshot "$snapshot_name" -n "$OLD_NS"
        exit 1
      }
    echo -e "${GREEN}✓ Snapshot $snapshot_name ready${NC}"
  done < "$SNAPSHOT_DIR/snapshot-list.txt"

  echo ""
  echo -e "${GREEN}✓ All VolumeSnapshots created and ready${NC}"
  echo ""
}

# Function: Create new namespace
create_new_namespace() {
  echo -e "${YELLOW}[4/10] Creating new namespace $NEW_NS...${NC}"

  # Extract labels from old namespace
  OLD_LABELS=$(kubectl get namespace "$OLD_NS" -o jsonpath='{.metadata.labels}' | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')

  # Create namespace
  kubectl create namespace "$NEW_NS"

  # Apply labels
  if [ -n "$OLD_LABELS" ]; then
    IFS=',' read -ra LABEL_ARRAY <<< "$OLD_LABELS"
    for label in "${LABEL_ARRAY[@]}"; do
      kubectl label namespace "$NEW_NS" "$label" --overwrite 2>/dev/null || true
    done
  fi

  # Add migration metadata
  kubectl label namespace "$NEW_NS" \
    migration-source="$OLD_NS" \
    migration-date="$(date +%Y-%m-%d)" \
    migration-pattern="C-stateful-pvc" \
    --overwrite

  echo -e "${GREEN}✓ Namespace $NEW_NS created${NC}"
  echo ""
}

# Function: Restore PVCs from snapshots
restore_pvcs_from_snapshots() {
  echo -e "${YELLOW}[5/10] Restoring PVCs from snapshots in new namespace...${NC}"

  RESTORE_DIR="$BACKUP_DIR/restored-pvcs"
  mkdir -p "$RESTORE_DIR"

  # Iterate through PVCs
  kubectl get pvc -n "$OLD_NS" -o json | jq -c '.items[]' | while read -r pvc; do
    PVC_NAME=$(echo "$pvc" | jq -r '.metadata.name')
    PVC_SIZE=$(echo "$pvc" | jq -r '.spec.resources.requests.storage')
    SNAPSHOT_NAME=$(grep "^${PVC_NAME}-snapshot" "$SNAPSHOT_DIR/snapshot-list.txt")

    echo "Restoring PVC: $PVC_NAME ($PVC_SIZE) from snapshot: $SNAPSHOT_NAME"

    # Create PVC manifest with dataSource
    cat > "$RESTORE_DIR/${PVC_NAME}.yaml" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NEW_NS
  labels:
    migration-source-ns: $OLD_NS
    migration-date: "$(date +%Y-%m-%d)"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $PVC_SIZE
  storageClassName: $STORAGE_CLASS
  dataSource:
    name: $SNAPSHOT_NAME
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

    # Apply PVC
    kubectl apply -f "$RESTORE_DIR/${PVC_NAME}.yaml"
  done

  echo ""
  echo -e "${BLUE}Waiting for all PVCs to be Bound...${NC}"

  # Wait for all PVCs
  kubectl get pvc -n "$OLD_NS" -o json | jq -r '.items[].metadata.name' | while read -r pvc_name; do
    echo "Waiting for PVC: $pvc_name"
    kubectl wait --for=condition=bound \
      pvc/"$pvc_name" \
      -n "$NEW_NS" \
      --timeout="$TIMEOUT_SNAPSHOT" || {
        echo -e "${RED}Error: PVC $pvc_name failed to bind${NC}"
        kubectl describe pvc "$pvc_name" -n "$NEW_NS"
        exit 1
      }
    echo -e "${GREEN}✓ PVC $pvc_name bound${NC}"
  done

  echo ""
  echo -e "${GREEN}✓ All PVCs restored and bound${NC}"
  echo ""
}

# Function: Deploy Helm chart to new namespace
deploy_helm_chart() {
  echo -e "${YELLOW}[6/10] Deploying Helm chart to new namespace...${NC}"

  echo "Deploying $HELM_CHART as $HELM_RELEASE in $NEW_NS..."
  helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" \
    -n "$NEW_NS" \
    -f "$BACKUP_DIR/helm-values.yaml" \
    --timeout "$TIMEOUT_PODS" \
    --wait || {
      echo -e "${RED}Error: Helm deployment failed${NC}"
      echo "Checking pod status:"
      kubectl get pods -n "$NEW_NS"
      echo ""
      echo "Recent events:"
      kubectl get events -n "$NEW_NS" --sort-by='.lastTimestamp' | tail -20
      exit 1
    }

  echo -e "${GREEN}✓ Helm chart deployed${NC}"
  echo ""
}

# Function: Wait for pods ready
wait_for_pods_ready() {
  echo -e "${YELLOW}[7/10] Waiting for pods to be ready...${NC}"
  echo -e "${BLUE}This may take 15-30 minutes for large PVCs...${NC}"

  echo "Waiting for all pods in $NEW_NS to be Running..."
  kubectl wait --for=condition=Ready pod --all -n "$NEW_NS" --timeout="$TIMEOUT_PODS" || {
    echo -e "${RED}Error: Pods did not become ready within timeout${NC}"
    echo ""
    echo "Pod status:"
    kubectl get pods -n "$NEW_NS" -o wide
    echo ""
    echo "Pod events:"
    kubectl get events -n "$NEW_NS" --sort-by='.lastTimestamp' | tail -30
    echo ""
    echo "Pod logs (failed pods):"
    kubectl get pods -n "$NEW_NS" --field-selector=status.phase!=Running -o name | while read -r pod; do
      echo "=== Logs for $pod ==="
      kubectl logs "$pod" -n "$NEW_NS" --tail=50 2>&1 || true
    done
    exit 1
  }

  echo -e "${GREEN}✓ All pods ready${NC}"
  echo ""
}

# Function: Validate data integrity
validate_data_integrity() {
  echo -e "${YELLOW}[8/10] Validating data integrity...${NC}"

  # Compare PVC sizes
  echo "PVC size validation:"
  echo ""
  echo "Old namespace:"
  kubectl get pvc -n "$OLD_NS" -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,STATUS:.status.phase
  echo ""
  echo "New namespace:"
  kubectl get pvc -n "$NEW_NS" -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,STATUS:.status.phase
  echo ""

  # Compare PVC count
  OLD_PVC_COUNT=$(kubectl get pvc -n "$OLD_NS" --no-headers | wc -l)
  NEW_PVC_COUNT=$(kubectl get pvc -n "$NEW_NS" --no-headers | wc -l)

  echo "PVC count: Old=$OLD_PVC_COUNT, New=$NEW_PVC_COUNT"

  if [ "$OLD_PVC_COUNT" != "$NEW_PVC_COUNT" ]; then
    echo -e "${RED}Error: PVC count mismatch!${NC}"
    exit 1
  fi

  # Check pod count
  OLD_POD_COUNT=$(kubectl get pods -n "$OLD_NS" --field-selector=status.phase=Running --no-headers | wc -l)
  NEW_POD_COUNT=$(kubectl get pods -n "$NEW_NS" --field-selector=status.phase=Running --no-headers | wc -l)

  echo "Running pod count: Old=$OLD_POD_COUNT, New=$NEW_POD_COUNT"

  # Application-specific validation
  echo ""
  echo -e "${YELLOW}Manual validation required:${NC}"
  echo "1. Check data integrity in pods (file count, checksums, etc.)"
  echo "2. Test application functionality"
  echo "3. Verify no CrashLoopBackOff pods"
  echo ""
  echo "Run these commands for validation:"
  echo ""

  # Get first pod for validation
  FIRST_POD=$(kubectl get pods -n "$NEW_NS" -o name | head -1)
  if [ -n "$FIRST_POD" ]; then
    echo "# Example: Validate file count in PVC"
    echo "kubectl exec -n $NEW_NS $FIRST_POD -- find /data -type f | wc -l"
    echo ""
    echo "# Example: Check logs for errors"
    echo "kubectl logs -n $NEW_NS $FIRST_POD --tail=100"
  fi

  echo ""
  echo -e "${YELLOW}Press Enter after manual validation...${NC}"
  read -r

  echo -e "${GREEN}✓ Data integrity validated${NC}"
  echo ""
}

# Function: Update ingress
update_ingress() {
  echo -e "${YELLOW}[9/10] Checking ingress configuration...${NC}"

  INGRESS_COUNT=$(kubectl get ingress -n "$NEW_NS" --no-headers 2>/dev/null | wc -l || echo "0")

  if [ "$INGRESS_COUNT" -gt 0 ]; then
    echo "Found $INGRESS_COUNT ingress resource(s):"
    kubectl get ingress -n "$NEW_NS" -o wide
    echo ""
    echo "Test ingress endpoints:"
    kubectl get ingress -n "$NEW_NS" -o jsonpath='{.items[*].spec.rules[*].host}' | tr ' ' '\n' | while read -r host; do
      echo "  curl -I https://$host"
    done
    echo ""
    echo -e "${YELLOW}Test ingress endpoints manually and press Enter...${NC}"
    read -r
  else
    echo "No ingress resources (OK for backend services)"
  fi

  echo ""
}

# Function: Summary
show_summary() {
  echo -e "${YELLOW}[10/10] Migration Summary${NC}"
  echo "=================================================="
  echo -e "${GREEN}✓ MIGRATION COMPLETE${NC}"
  echo ""
  echo "Old Namespace: $OLD_NS (STILL EXISTS - DO NOT DELETE YET)"
  echo "New Namespace: $NEW_NS (OPERATIONAL)"
  echo ""
  echo "PVCs migrated:"
  kubectl get pvc -n "$NEW_NS"
  echo ""
  echo "Pods running:"
  kubectl get pods -n "$NEW_NS"
  echo ""
  echo -e "${YELLOW}CRITICAL: Keep old namespace for 14 days (extended retention)${NC}"
  echo ""
  echo "Next Steps:"
  echo "1. Monitor logs for 48h:"
  echo "   kubectl logs -n $NEW_NS --all-containers --tail=100 -f"
  echo "2. Validate application functionality thoroughly"
  echo "3. Test all ingress endpoints (HTTP 200)"
  echo "4. Monitor metrics in Prometheus/Grafana"
  echo "5. After 14 days validation, schedule old namespace deletion:"
  echo "   kubectl delete namespace $OLD_NS"
  echo "6. After old namespace deleted, cleanup snapshots:"
  echo "   kubectl delete volumesnapshot -n $OLD_NS --all"
  echo ""
  echo "Rollback (if needed before old namespace deletion):"
  echo "  kubectl delete namespace $NEW_NS"
  echo "  # Old namespace $OLD_NS remains operational"
  echo ""
  echo "End Time: $(date)"
  echo "Duration: $(($(date +%s) - $(date -d "$START_TIME" +%s 2>/dev/null || echo 0))) seconds"
  echo "Log File: $LOG_FILE"
  echo "Backup:   $BACKUP_DIR/"
  echo "Snapshots: $SNAPSHOT_DIR/"
  echo "=================================================="
}

# Main execution
main() {
  START_TIME=$(date)
  check_prerequisites
  backup_current_state
  create_volume_snapshots
  create_new_namespace
  restore_pvcs_from_snapshots
  deploy_helm_chart
  wait_for_pods_ready
  validate_data_integrity
  update_ingress
  show_summary
}

# Run migration
main
