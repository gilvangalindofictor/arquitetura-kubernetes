#!/bin/bash
# rollback.sh - Universal Rollback Script for Namespace Migrations
# Usage: ./rollback.sh <new-namespace> <old-namespace> [delete-snapshots]
#
# Example:
#   ./rollback.sh staging-platform-harbor harbor-system
#   ./rollback.sh staging-platform-harbor harbor-system delete-snapshots

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Arguments
NEW_NS="${1:-}"
OLD_NS="${2:-}"
DELETE_SNAPSHOTS="${3:-keep}"

# Validation
if [ -z "$NEW_NS" ] || [ -z "$OLD_NS" ]; then
  echo -e "${RED}Error: Missing required arguments${NC}"
  echo "Usage: $0 <new-namespace> <old-namespace> [delete-snapshots]"
  echo ""
  echo "Examples:"
  echo "  $0 staging-platform-harbor harbor-system"
  echo "  $0 staging-platform-harbor harbor-system delete-snapshots"
  exit 1
fi

# Logging
LOG_FILE="rollback-${NEW_NS}-to-${OLD_NS}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "ROLLBACK: Namespace Migration"
echo "=================================================="
echo "New Namespace (TO DELETE): $NEW_NS"
echo "Old Namespace (TO KEEP):   $OLD_NS"
echo "Delete Snapshots:          $DELETE_SNAPSHOTS"
echo "Start Time:                $(date)"
echo "=================================================="
echo ""
echo -e "${RED}WARNING: This will DELETE namespace $NEW_NS!${NC}"
echo -e "${YELLOW}Press Ctrl+C to abort, or Enter to continue...${NC}"
read -r

# Function: Check prerequisites
check_prerequisites() {
  echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"

  if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
  fi

  # Check new namespace exists (to delete)
  if ! kubectl get namespace "$NEW_NS" &> /dev/null; then
    echo -e "${RED}Error: New namespace $NEW_NS does not exist (nothing to rollback)${NC}"
    exit 1
  fi

  # Check old namespace exists (should remain)
  if ! kubectl get namespace "$OLD_NS" &> /dev/null; then
    echo -e "${RED}Error: Old namespace $OLD_NS does not exist!${NC}"
    echo "This is CRITICAL - old namespace was deleted prematurely!"
    echo "Recovery required from backups/snapshots."
    exit 1
  fi

  echo -e "${GREEN}✓ Prerequisites OK${NC}"
  echo ""
}

# Function: Backup new namespace state (for audit)
backup_new_namespace() {
  echo -e "${YELLOW}[2/5] Backing up new namespace state (audit trail)...${NC}"

  BACKUP_DIR="rollback-backup-${NEW_NS}-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"

  # Export all resources
  echo "Exporting resources from $NEW_NS..."
  kubectl get all -n "$NEW_NS" -o yaml > "$BACKUP_DIR/all-resources.yaml" 2>/dev/null || true
  kubectl get pvc -n "$NEW_NS" -o yaml > "$BACKUP_DIR/pvcs.yaml" 2>/dev/null || true
  kubectl get externalsecrets -n "$NEW_NS" -o yaml > "$BACKUP_DIR/externalsecrets.yaml" 2>/dev/null || true

  # Document reason for rollback
  cat > "$BACKUP_DIR/rollback-reason.txt" <<EOF
Rollback Date: $(date)
New Namespace (deleted): $NEW_NS
Old Namespace (restored): $OLD_NS

Rollback Reason:
(Manually document why rollback was necessary)

Pod Status Before Rollback:
$(kubectl get pods -n "$NEW_NS" 2>/dev/null || echo "No pods")

Events:
$(kubectl get events -n "$NEW_NS" --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || echo "No events")
EOF

  echo -e "${GREEN}✓ Backup saved to $BACKUP_DIR/${NC}"
  echo ""
}

# Function: Delete new namespace
delete_new_namespace() {
  echo -e "${YELLOW}[3/5] Deleting new namespace $NEW_NS...${NC}"

  # Final confirmation
  echo -e "${RED}FINAL WARNING: Deleting namespace $NEW_NS in 5 seconds...${NC}"
  echo "Press Ctrl+C to abort"
  for i in 5 4 3 2 1; do
    echo "$i..."
    sleep 1
  done

  echo "Deleting namespace $NEW_NS..."
  kubectl delete namespace "$NEW_NS" --timeout=5m || {
    echo -e "${YELLOW}Warning: Namespace deletion timed out or failed${NC}"
    echo "Resources may be stuck in terminating state."
    echo "Check with: kubectl get namespace $NEW_NS"
    echo "Force delete if needed: kubectl delete namespace $NEW_NS --grace-period=0 --force"
    exit 1
  }

  # Wait for namespace deletion
  echo "Waiting for namespace deletion to complete..."
  TIMEOUT=300
  ELAPSED=0
  while kubectl get namespace "$NEW_NS" &> /dev/null; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
      echo -e "${RED}Error: Namespace deletion did not complete within 5 minutes${NC}"
      echo "Namespace may be stuck. Manual intervention required."
      exit 1
    fi
    echo "Waiting... ($ELAPSED/${TIMEOUT}s)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
  done

  echo -e "${GREEN}✓ Namespace $NEW_NS deleted${NC}"
  echo ""
}

# Function: Verify old namespace operational
verify_old_namespace() {
  echo -e "${YELLOW}[4/5] Verifying old namespace $OLD_NS operational...${NC}"

  # Check pods
  echo "Checking pods in $OLD_NS..."
  POD_COUNT=$(kubectl get pods -n "$OLD_NS" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")

  if [ "$POD_COUNT" -eq 0 ]; then
    echo -e "${RED}Warning: No running pods in old namespace!${NC}"
    echo "This may be expected if workload is stateless or scaled down."
  else
    echo "Found $POD_COUNT running pod(s) in $OLD_NS:"
    kubectl get pods -n "$OLD_NS" --field-selector=status.phase=Running
  fi

  # Check services
  echo ""
  echo "Services in $OLD_NS:"
  kubectl get svc -n "$OLD_NS" 2>/dev/null || echo "No services"

  # Check ingress
  echo ""
  echo "Ingress in $OLD_NS:"
  kubectl get ingress -n "$OLD_NS" 2>/dev/null || echo "No ingress"

  # Test service endpoints
  echo ""
  echo "Testing service endpoints..."
  SVC_COUNT=$(kubectl get svc -n "$OLD_NS" --no-headers 2>/dev/null | wc -l || echo "0")
  if [ "$SVC_COUNT" -gt 0 ]; then
    kubectl get svc -n "$OLD_NS" -o json | jq -r '.items[] | select(.spec.type != "ExternalName") | .metadata.name' | while read -r svc; do
      ENDPOINTS=$(kubectl get endpoints "$svc" -n "$OLD_NS" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
      if [ -n "$ENDPOINTS" ]; then
        echo -e "${GREEN}✓ Service $svc has endpoints: $ENDPOINTS${NC}"
      else
        echo -e "${YELLOW}⚠ Service $svc has NO endpoints${NC}"
      fi
    done
  fi

  echo ""
  echo -e "${GREEN}✓ Old namespace $OLD_NS verified${NC}"
  echo ""
}

# Function: Cleanup snapshots (optional)
cleanup_snapshots() {
  echo -e "${YELLOW}[5/5] Cleanup snapshots...${NC}"

  if [ "$DELETE_SNAPSHOTS" != "delete-snapshots" ]; then
    echo "Keeping VolumeSnapshots (use 'delete-snapshots' argument to remove)"
    echo ""
    echo "To manually delete snapshots later:"
    echo "  kubectl get volumesnapshot -n $OLD_NS"
    echo "  kubectl delete volumesnapshot -n $OLD_NS <snapshot-name>"
    echo ""
    return 0
  fi

  # Find snapshots related to migration
  SNAPSHOT_COUNT=$(kubectl get volumesnapshot -n "$OLD_NS" --no-headers 2>/dev/null | wc -l || echo "0")

  if [ "$SNAPSHOT_COUNT" -eq 0 ]; then
    echo "No VolumeSnapshots found in $OLD_NS"
    echo ""
    return 0
  fi

  echo "Found $SNAPSHOT_COUNT VolumeSnapshot(s) in $OLD_NS:"
  kubectl get volumesnapshot -n "$OLD_NS"
  echo ""
  echo -e "${YELLOW}Delete all snapshots? (y/N)${NC}"
  read -r CONFIRM

  if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
    echo "Deleting all VolumeSnapshots in $OLD_NS..."
    kubectl delete volumesnapshot --all -n "$OLD_NS" || {
      echo -e "${YELLOW}Warning: Some snapshots failed to delete${NC}"
    }
    echo -e "${GREEN}✓ Snapshots deleted${NC}"
  else
    echo "Snapshots retained (manual cleanup required)"
  fi

  echo ""
}

# Function: Summary
show_summary() {
  echo "=================================================="
  echo -e "${GREEN}✓ ROLLBACK COMPLETE${NC}"
  echo "=================================================="
  echo ""
  echo "Status:"
  echo "  New Namespace: $NEW_NS (DELETED)"
  echo "  Old Namespace: $OLD_NS (OPERATIONAL)"
  echo ""
  echo "Old namespace status:"
  kubectl get all -n "$OLD_NS" 2>/dev/null | head -20
  echo ""
  echo "Next Steps:"
  echo "1. Verify application functionality in $OLD_NS"
  echo "2. Test ingress endpoints (should route to old namespace)"
  echo "3. Investigate root cause of migration failure"
  echo "4. Review rollback audit trail: $BACKUP_DIR/"
  echo "5. Update documentation (migration failed, rollback successful)"
  echo "6. Schedule retry migration (after root cause fixed)"
  echo ""
  echo "Post-Mortem Checklist:"
  echo "[ ] Why did migration fail?"
  echo "[ ] What was the rollback trigger?"
  echo "[ ] Was data integrity compromised?"
  echo "[ ] How to prevent in next attempt?"
  echo "[ ] Update migration scripts/patterns?"
  echo ""
  echo "End Time: $(date)"
  echo "Log File: $LOG_FILE"
  echo "Audit:    $BACKUP_DIR/"
  echo "=================================================="
}

# Main execution
main() {
  check_prerequisites
  backup_new_namespace
  delete_new_namespace
  verify_old_namespace
  cleanup_snapshots
  show_summary
}

# Run rollback
main
