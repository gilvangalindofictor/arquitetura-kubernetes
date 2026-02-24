#!/bin/bash
# migrate-operator-crd.sh - Pattern D: Operator-Managed CRD Migration
# Usage: ./migrate-operator-crd.sh <old-namespace> <new-namespace> <crd-kind> <cr-name>
#
# Example:
#   ./migrate-operator-crd.sh data-services staging-data-infrastructure rabbitmqclusters k8s-platform-prod-rabbitmq
#
# Pattern D: Used for operator-managed workloads (RabbitMQ, Redis)
# - rabbitmq-system (operator namespace)
# - redis-operator (operator namespace)
# - data-services (CR instances)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Arguments
OLD_NS="${1:-}"
NEW_NS="${2:-}"
CRD_KIND="${3:-}"
CR_NAME="${4:-}"

# Configuration
SNAPSHOT_CLASS="${SNAPSHOT_CLASS:-ebs-csi-snapshot-class}"
STORAGE_CLASS="${STORAGE_CLASS:-gp3}"

# Validation
if [ -z "$OLD_NS" ] || [ -z "$NEW_NS" ] || [ -z "$CRD_KIND" ] || [ -z "$CR_NAME" ]; then
  echo -e "${RED}Error: Missing required arguments${NC}"
  echo "Usage: $0 <old-namespace> <new-namespace> <crd-kind> <cr-name>"
  echo ""
  echo "Examples:"
  echo "  $0 data-services staging-data-infrastructure rabbitmqclusters k8s-platform-prod-rabbitmq"
  echo "  $0 data-services staging-data-infrastructure redis redis"
  exit 1
fi

# Logging
LOG_FILE="migration-crd-${OLD_NS}-to-${NEW_NS}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "Pattern D: Operator-Managed CRD Migration"
echo "=================================================="
echo "Old Namespace: $OLD_NS"
echo "New Namespace: $NEW_NS"
echo "CRD Kind:      $CRD_KIND"
echo "CR Name:       $CR_NAME"
echo "Start Time:    $(date)"
echo "=================================================="
echo ""

# Function: Check prerequisites
check_prerequisites() {
  echo -e "${YELLOW}[1/9] Checking prerequisites...${NC}"

  # Check commands
  for cmd in kubectl jq; do
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

  # Check CRD exists
  if ! kubectl get crd "$CRD_KIND" &> /dev/null; then
    echo -e "${RED}Error: CRD $CRD_KIND not found${NC}"
    echo "Available CRDs:"
    kubectl get crd | grep -E "(rabbitmq|redis)"
    exit 1
  fi

  # Check CR exists
  if ! kubectl get "$CRD_KIND" "$CR_NAME" -n "$OLD_NS" &> /dev/null; then
    echo -e "${RED}Error: CR $CR_NAME ($CRD_KIND) not found in $OLD_NS${NC}"
    echo "Available CRs in $OLD_NS:"
    kubectl get "$CRD_KIND" -n "$OLD_NS" 2>/dev/null || echo "None"
    exit 1
  fi

  echo -e "${GREEN}✓ Prerequisites OK${NC}"
  echo ""
}

# Function: Backup current state
backup_current_state() {
  echo -e "${YELLOW}[2/9] Backing up current state...${NC}"

  BACKUP_DIR="backup-crd-${OLD_NS}-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"

  # Export CR definition
  echo "Exporting CR: $CRD_KIND/$CR_NAME..."
  kubectl get "$CRD_KIND" "$CR_NAME" -n "$OLD_NS" -o yaml > "$BACKUP_DIR/cr-${CR_NAME}.yaml"

  # Export CR JSON (easier parsing)
  kubectl get "$CRD_KIND" "$CR_NAME" -n "$OLD_NS" -o json > "$BACKUP_DIR/cr-${CR_NAME}.json"

  # Check if CR manages a StatefulSet
  echo ""
  echo "Checking for managed StatefulSets..."
  STS_NAME=$(kubectl get statefulsets -n "$OLD_NS" -o json | \
    jq -r --arg cr "$CR_NAME" '.items[] | select(.metadata.ownerReferences[]?.name == $cr) | .metadata.name' || echo "")

  if [ -n "$STS_NAME" ]; then
    echo "Found StatefulSet managed by CR: $STS_NAME"
    kubectl get statefulset "$STS_NAME" -n "$OLD_NS" -o yaml > "$BACKUP_DIR/statefulset-${STS_NAME}.yaml"

    # Export PVCs (if any)
    PVC_COUNT=$(kubectl get pvc -n "$OLD_NS" -l "app.kubernetes.io/instance=$CR_NAME" --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$PVC_COUNT" -gt 0 ]; then
      echo "Found $PVC_COUNT PVC(s) managed by StatefulSet:"
      kubectl get pvc -n "$OLD_NS" -l "app.kubernetes.io/instance=$CR_NAME"
      kubectl get pvc -n "$OLD_NS" -l "app.kubernetes.io/instance=$CR_NAME" -o yaml > "$BACKUP_DIR/pvcs.yaml"
    else
      # Try alternative label selector
      PVC_COUNT=$(kubectl get pvc -n "$OLD_NS" --no-headers 2>/dev/null | grep "$CR_NAME" | wc -l || echo "0")
      if [ "$PVC_COUNT" -gt 0 ]; then
        echo "Found $PVC_COUNT PVC(s) (by name match):"
        kubectl get pvc -n "$OLD_NS" | grep "$CR_NAME"
        kubectl get pvc -n "$OLD_NS" -o yaml > "$BACKUP_DIR/pvcs.yaml"
      fi
    fi
  else
    echo "No StatefulSet managed by CR (operator may be stateless)"
  fi

  # Document current state
  cat > "$BACKUP_DIR/state-snapshot.txt" <<EOF
Migration Date: $(date)
Old Namespace: $OLD_NS
New Namespace: $NEW_NS
CRD Kind: $CRD_KIND
CR Name: $CR_NAME
StatefulSet: ${STS_NAME:-None}
PVC Count: ${PVC_COUNT:-0}

CR Status:
$(kubectl get "$CRD_KIND" "$CR_NAME" -n "$OLD_NS" -o jsonpath='{.status}' | jq .)

Pods:
$(kubectl get pods -n "$OLD_NS" -l "app.kubernetes.io/instance=$CR_NAME")

Services:
$(kubectl get svc -n "$OLD_NS" -l "app.kubernetes.io/instance=$CR_NAME" 2>/dev/null || echo "None")
EOF

  echo -e "${GREEN}✓ Backup saved to $BACKUP_DIR/${NC}"
  echo ""
}

# Function: Create VolumeSnapshots (if PVCs exist)
create_volume_snapshots() {
  echo -e "${YELLOW}[3/9] Creating VolumeSnapshots (if PVCs exist)...${NC}"

  # Get PVC count
  PVC_COUNT=$(kubectl get pvc -n "$OLD_NS" --no-headers 2>/dev/null | grep -c "$CR_NAME" || echo "0")

  if [ "$PVC_COUNT" -eq 0 ]; then
    echo "No PVCs found (operator may be stateless or use external storage)"
    echo "Skipping snapshot creation."
    echo ""
    return 0
  fi

  SNAPSHOT_DIR="$BACKUP_DIR/snapshots"
  mkdir -p "$SNAPSHOT_DIR"

  # Create snapshots for each PVC
  kubectl get pvc -n "$OLD_NS" --no-headers | grep "$CR_NAME" | awk '{print $1}' | while read -r pvc_name; do
    SNAPSHOT_NAME="${pvc_name}-snapshot-$(date +%Y%m%d-%H%M%S)"

    echo "Creating snapshot for PVC: $pvc_name → $SNAPSHOT_NAME"

    cat > "$SNAPSHOT_DIR/${pvc_name}-snapshot.yaml" <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $SNAPSHOT_NAME
  namespace: $OLD_NS
spec:
  volumeSnapshotClassName: $SNAPSHOT_CLASS
  source:
    persistentVolumeClaimName: $pvc_name
EOF

    kubectl apply -f "$SNAPSHOT_DIR/${pvc_name}-snapshot.yaml"
    echo "$SNAPSHOT_NAME" >> "$SNAPSHOT_DIR/snapshot-list.txt"
  done

  # Wait for snapshots
  if [ -f "$SNAPSHOT_DIR/snapshot-list.txt" ]; then
    echo ""
    echo "Waiting for snapshots to be ready..."
    while read -r snapshot_name; do
      kubectl wait --for=condition=readyToUse \
        volumesnapshot/"$snapshot_name" \
        -n "$OLD_NS" \
        --timeout=20m || {
          echo -e "${RED}Error: Snapshot $snapshot_name failed${NC}"
          exit 1
        }
      echo -e "${GREEN}✓ Snapshot $snapshot_name ready${NC}"
    done < "$SNAPSHOT_DIR/snapshot-list.txt"
  fi

  echo -e "${GREEN}✓ VolumeSnapshots created${NC}"
  echo ""
}

# Function: Create new namespace
create_new_namespace() {
  echo -e "${YELLOW}[4/9] Creating new namespace $NEW_NS...${NC}"

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
    migration-pattern="D-operator-crd" \
    --overwrite

  echo -e "${GREEN}✓ Namespace $NEW_NS created${NC}"
  echo ""
}

# Function: Restore PVCs from snapshots
restore_pvcs_from_snapshots() {
  echo -e "${YELLOW}[5/9] Restoring PVCs from snapshots (if applicable)...${NC}"

  if [ ! -f "$SNAPSHOT_DIR/snapshot-list.txt" ]; then
    echo "No snapshots to restore (skipping)"
    echo ""
    return 0
  fi

  RESTORE_DIR="$BACKUP_DIR/restored-pvcs"
  mkdir -p "$RESTORE_DIR"

  # Get PVC details
  kubectl get pvc -n "$OLD_NS" --no-headers | grep "$CR_NAME" | while read -r line; do
    PVC_NAME=$(echo "$line" | awk '{print $1}')
    PVC_SIZE=$(echo "$line" | awk '{print $4}')
    SNAPSHOT_NAME=$(grep "^${PVC_NAME}-snapshot" "$SNAPSHOT_DIR/snapshot-list.txt")

    echo "Restoring PVC: $PVC_NAME ($PVC_SIZE) from snapshot: $SNAPSHOT_NAME"

    cat > "$RESTORE_DIR/${PVC_NAME}.yaml" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NEW_NS
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

    kubectl apply -f "$RESTORE_DIR/${PVC_NAME}.yaml"
  done

  # Wait for PVCs
  if [ -n "$(ls -A "$RESTORE_DIR" 2>/dev/null)" ]; then
    echo ""
    echo "Waiting for PVCs to be Bound..."
    kubectl wait --for=condition=bound pvc --all -n "$NEW_NS" --timeout=10m || {
      echo -e "${RED}Error: PVCs failed to bind${NC}"
      exit 1
    }
    echo -e "${GREEN}✓ PVCs restored${NC}"
  fi

  echo ""
}

# Function: Recreate CR in new namespace
recreate_cr_in_new_namespace() {
  echo -e "${YELLOW}[6/9] Recreating CR in new namespace...${NC}"

  # Clean CR definition (remove status, uid, resourceVersion)
  jq 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.generation, .metadata.managedFields, .status) |
      .metadata.namespace = $newns' \
    --arg newns "$NEW_NS" \
    "$BACKUP_DIR/cr-${CR_NAME}.json" > "$BACKUP_DIR/cr-${CR_NAME}-new.json"

  # Apply CR to new namespace
  echo "Applying CR $CRD_KIND/$CR_NAME to $NEW_NS..."
  kubectl apply -f "$BACKUP_DIR/cr-${CR_NAME}-new.json"

  echo ""
  echo "Waiting for operator to reconcile..."
  sleep 10

  # Check CR status
  echo "CR status in new namespace:"
  kubectl get "$CRD_KIND" "$CR_NAME" -n "$NEW_NS" -o jsonpath='{.status}' | jq . || echo "Status not available yet"

  echo -e "${GREEN}✓ CR created in new namespace${NC}"
  echo ""
}

# Function: Wait for reconciliation
wait_for_reconciliation() {
  echo -e "${YELLOW}[7/9] Waiting for operator to reconcile CR...${NC}"

  echo "Waiting for StatefulSet to be created..."
  TIMEOUT=300
  ELAPSED=0

  while [ $ELAPSED -lt $TIMEOUT ]; do
    STS_COUNT=$(kubectl get statefulsets -n "$NEW_NS" -l "app.kubernetes.io/instance=$CR_NAME" --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$STS_COUNT" -gt 0 ]; then
      echo -e "${GREEN}✓ StatefulSet created by operator${NC}"
      break
    fi

    echo "Waiting... ($ELAPSED/${TIMEOUT}s)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
  done

  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${RED}Error: Operator did not create StatefulSet within timeout${NC}"
    echo "Check operator logs:"
    # Try to find operator pod
    OPERATOR_POD=$(kubectl get pods --all-namespaces -l "app.kubernetes.io/name=${CRD_KIND%-*}-operator" -o name | head -1 || echo "")
    if [ -n "$OPERATOR_POD" ]; then
      echo "kubectl logs $OPERATOR_POD --tail=50"
    fi
    exit 1
  fi

  echo ""
  echo "Waiting for pods to be ready..."
  kubectl wait --for=condition=Ready pod -l "app.kubernetes.io/instance=$CR_NAME" -n "$NEW_NS" --timeout=10m || {
    echo -e "${RED}Error: Pods did not become ready${NC}"
    kubectl get pods -n "$NEW_NS" -l "app.kubernetes.io/instance=$CR_NAME"
    exit 1
  }

  echo -e "${GREEN}✓ CR reconciled, pods ready${NC}"
  echo ""
}

# Function: Validate CR and data
validate_cr_and_data() {
  echo -e "${YELLOW}[8/9] Validating CR and data...${NC}"

  # Check CR status
  echo "CR status:"
  kubectl get "$CRD_KIND" "$CR_NAME" -n "$NEW_NS"

  # Check pods
  echo ""
  echo "Pods:"
  kubectl get pods -n "$NEW_NS" -l "app.kubernetes.io/instance=$CR_NAME"

  # Check services
  echo ""
  echo "Services:"
  kubectl get svc -n "$NEW_NS" -l "app.kubernetes.io/instance=$CR_NAME" 2>/dev/null || echo "No services found"

  # Check PVCs
  echo ""
  echo "PVCs:"
  kubectl get pvc -n "$NEW_NS" 2>/dev/null || echo "No PVCs"

  # Application-specific validation
  echo ""
  echo -e "${YELLOW}Application-specific validation:${NC}"

  case "$CRD_KIND" in
    rabbitmqclusters|rabbitmqcluster)
      echo "RabbitMQ validation:"
      echo "1. Management UI accessible:"
      MGMT_SVC=$(kubectl get svc -n "$NEW_NS" -l "app.kubernetes.io/instance=$CR_NAME" --no-headers | grep management | awk '{print $1}' || echo "")
      if [ -n "$MGMT_SVC" ]; then
        echo "   kubectl port-forward -n $NEW_NS svc/$MGMT_SVC 15672:15672"
        echo "   Then open: http://localhost:15672"
      fi
      echo "2. Check queues/exchanges:"
      POD=$(kubectl get pods -n "$NEW_NS" -l "app.kubernetes.io/instance=$CR_NAME" -o name | head -1)
      if [ -n "$POD" ]; then
        echo "   kubectl exec -n $NEW_NS $POD -- rabbitmqctl list_queues"
      fi
      ;;
    redis|redisclusters)
      echo "Redis validation:"
      POD=$(kubectl get pods -n "$NEW_NS" -l "app.kubernetes.io/instance=$CR_NAME" -o name | head -1)
      if [ -n "$POD" ]; then
        echo "1. PING test:"
        echo "   kubectl exec -n $NEW_NS $POD -- redis-cli PING"
        echo "2. Check keys:"
        echo "   kubectl exec -n $NEW_NS $POD -- redis-cli DBSIZE"
      fi
      ;;
  esac

  echo ""
  echo -e "${GREEN}✓ Validation complete${NC}"
  echo ""
}

# Function: Summary
show_summary() {
  echo -e "${YELLOW}[9/9] Migration Summary${NC}"
  echo "=================================================="
  echo -e "${GREEN}✓ CR MIGRATION COMPLETE${NC}"
  echo ""
  echo "Old Namespace: $OLD_NS"
  echo "New Namespace: $NEW_NS"
  echo "CR: $CRD_KIND/$CR_NAME"
  echo ""
  echo "Resources in new namespace:"
  kubectl get "$CRD_KIND","pods,svc,pvc" -n "$NEW_NS" -l "app.kubernetes.io/instance=$CR_NAME" 2>/dev/null || \
    kubectl get "$CRD_KIND","pods,svc,pvc" -n "$NEW_NS" 2>/dev/null
  echo ""
  echo "Next Steps:"
  echo "1. Validate application functionality"
  echo "2. Test service connectivity"
  echo "3. Monitor logs:"
  echo "   kubectl logs -n $NEW_NS -l app.kubernetes.io/instance=$CR_NAME --tail=100 -f"
  echo "4. After validation (7 days), delete old CR:"
  echo "   kubectl delete $CRD_KIND $CR_NAME -n $OLD_NS"
  echo "5. Delete old namespace:"
  echo "   kubectl delete namespace $OLD_NS"
  echo ""
  echo "Rollback (if needed):"
  echo "  kubectl delete $CRD_KIND $CR_NAME -n $NEW_NS"
  echo "  kubectl delete namespace $NEW_NS"
  echo "  # Old namespace $OLD_NS still exists"
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
  create_volume_snapshots
  create_new_namespace
  restore_pvcs_from_snapshots
  recreate_cr_in_new_namespace
  wait_for_reconciliation
  validate_cr_and_data
  show_summary
}

# Run migration
main
