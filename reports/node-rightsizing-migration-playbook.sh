#!/bin/bash
#
# Node Rightsizing Migration Playbook
# Date: 2026-02-27
# Cluster: k8s-platform-prod
# Migration: T3 → R5 instance family
#
# USAGE:
#   Phase 1: ./node-rightsizing-migration-playbook.sh phase1
#   Phase 2: ./node-rightsizing-migration-playbook.sh phase2
#   Phase 3: ./node-rightsizing-migration-playbook.sh phase3
#   Rollback: ./node-rightsizing-migration-playbook.sh rollback <phase>
#

set -euo pipefail

# Configuration
CLUSTER_NAME="k8s-platform-prod"
REGION="us-east-1"
DRAIN_GRACE_PERIOD=120
STATEFULSET_GRACE_PERIOD=300

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    # Check eksctl
    if ! command -v eksctl &> /dev/null; then
        log_error "eksctl not found. Please install eksctl first."
        exit 1
    fi

    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot access cluster. Please check kubeconfig."
        exit 1
    fi

    # Check current context
    current_context=$(kubectl config current-context)
    log_info "Current context: $current_context"

    # Verify cluster name
    if [[ "$current_context" != *"$CLUSTER_NAME"* ]]; then
        log_warn "Current context does not match expected cluster name: $CLUSTER_NAME"
        read -p "Continue anyway? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_error "Aborted by user"
            exit 1
        fi
    fi

    log_info "Prerequisites check passed"
}

verify_node_health() {
    log_info "Verifying node health..."

    # Check for NotReady nodes
    not_ready=$(kubectl get nodes --no-headers | grep -v Ready | wc -l)
    if [ "$not_ready" -gt 0 ]; then
        log_error "$not_ready nodes are not in Ready state"
        kubectl get nodes
        exit 1
    fi

    # Check for unhealthy pods
    unhealthy=$(kubectl get pods --all-namespaces --field-selector status.phase!=Running,status.phase!=Succeeded | grep -v Completed | wc -l)
    if [ "$unhealthy" -gt 0 ]; then
        log_warn "$unhealthy pods are not in Running/Succeeded state"
        kubectl get pods --all-namespaces --field-selector status.phase!=Running,status.phase!=Succeeded
        read -p "Continue anyway? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_error "Aborted by user"
            exit 1
        fi
    fi

    log_info "Node health check passed"
}

create_backup() {
    local namespace=$1
    local backup_name="node-migration-$(date +%Y%m%d-%H%M%S)"

    log_info "Creating Velero backup: $backup_name"

    if command -v velero &> /dev/null; then
        velero backup create "$backup_name" \
            --include-namespaces="$namespace" \
            --wait
        log_info "Backup created: $backup_name"
    else
        log_warn "Velero not found. Skipping backup creation."
    fi
}

wait_for_node_ready() {
    local node_label=$1
    local timeout=300
    local elapsed=0

    log_info "Waiting for nodes with label $node_label to be ready..."

    while [ $elapsed -lt $timeout ]; do
        ready_count=$(kubectl get nodes -l "$node_label" --no-headers | grep Ready | wc -l)
        total_count=$(kubectl get nodes -l "$node_label" --no-headers | wc -l)

        if [ "$ready_count" -eq "$total_count" ] && [ "$total_count" -gt 0 ]; then
            log_info "All $total_count nodes are ready"
            return 0
        fi

        sleep 10
        elapsed=$((elapsed + 10))
    done

    log_error "Timeout waiting for nodes to be ready"
    return 1
}

cordon_nodes() {
    local instance_type=$1

    log_info "Cordoning nodes with instance type: $instance_type"

    nodes=$(kubectl get nodes -o json | jq -r ".items[] | select(.metadata.labels[\"node.kubernetes.io/instance-type\"] == \"$instance_type\") | .metadata.name")

    for node in $nodes; do
        log_info "Cordoning node: $node"
        kubectl cordon "$node"
    done
}

drain_node() {
    local node=$1
    local grace_period=$2

    log_info "Draining node: $node (grace period: ${grace_period}s)"

    kubectl drain "$node" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --grace-period="$grace_period" \
        --timeout=15m

    log_info "Node drained: $node"
}

verify_pods_rescheduled() {
    local namespace=$1
    local timeout=300
    local elapsed=0

    log_info "Verifying pods rescheduled in namespace: $namespace"

    while [ $elapsed -lt $timeout ]; do
        pending=$(kubectl get pods -n "$namespace" --field-selector status.phase=Pending --no-headers | wc -l)

        if [ "$pending" -eq 0 ]; then
            log_info "All pods rescheduled successfully"
            return 0
        fi

        log_warn "$pending pods still pending..."
        sleep 10
        elapsed=$((elapsed + 10))
    done

    log_error "Timeout waiting for pods to reschedule"
    kubectl get pods -n "$namespace" --field-selector status.phase=Pending
    return 1
}

delete_node_group() {
    local node_group=$1

    log_warn "About to delete node group: $node_group"
    read -p "Are you sure? This cannot be undone. (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_error "Aborted by user"
        exit 1
    fi

    log_info "Deleting node group: $node_group"
    eksctl delete nodegroup \
        --cluster="$CLUSTER_NAME" \
        --name="$node_group" \
        --region="$REGION" \
        --drain=false

    log_info "Node group deleted: $node_group"
}

#
# PHASE 1: System Pool (t3.medium → r5.large)
#
phase1_migrate() {
    log_info "=== PHASE 1: System Pool Migration ==="
    log_info "Migrating: 3x t3.medium → 2x r5.large"

    check_prerequisites
    verify_node_health

    # Create backup
    create_backup "kube-system,staging-observability-monitoring"

    # Create new node group
    log_info "Creating r5.large node group..."
    eksctl create nodegroup \
        --cluster="$CLUSTER_NAME" \
        --name="system-r5-large" \
        --region="$REGION" \
        --node-type=r5.large \
        --nodes=2 \
        --nodes-min=2 \
        --nodes-max=3 \
        --node-labels="node-role=system,workload-type=infrastructure" \
        --node-volume-size=100 \
        --node-volume-type=gp3 \
        --managed

    # Wait for nodes to be ready
    wait_for_node_ready "node-role=system" || exit 1

    # Cordon old nodes
    cordon_nodes "t3.medium"

    # Get t3.medium nodes
    t3_medium_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels["node.kubernetes.io/instance-type"] == "t3.medium") | .metadata.name')

    # Drain nodes one by one
    for node in $t3_medium_nodes; do
        drain_node "$node" "$DRAIN_GRACE_PERIOD"

        # Wait 2 minutes between nodes
        log_info "Waiting 2 minutes before draining next node..."
        sleep 120

        # Verify system workloads healthy
        verify_pods_rescheduled "kube-system" || exit 1
        verify_pods_rescheduled "staging-observability-monitoring" || exit 1
    done

    # Final validation
    log_info "Running final validation checks..."
    sleep 60

    kubectl get pods -n kube-system -o wide
    kubectl get pods -n staging-observability-monitoring -o wide | grep -E "(prometheus|grafana|loki)"

    log_info "Phase 1 migration completed successfully!"
    log_warn "Monitor cluster for 7 days before proceeding to Phase 2"
    log_warn "To delete old node group after validation: ./node-rightsizing-migration-playbook.sh cleanup phase1"
}

#
# PHASE 2: Workloads Pool (t3.large → r5.xlarge)
#
phase2_migrate() {
    log_info "=== PHASE 2: Workloads Pool Migration ==="
    log_info "Migrating: 6x t3.large → 4x r5.xlarge"

    check_prerequisites
    verify_node_health

    # Create backup
    create_backup "staging-platform-gitlab,staging-platform-sonarqube,staging-platform-argocd"

    # Create new node group
    log_info "Creating r5.xlarge node group..."
    eksctl create nodegroup \
        --cluster="$CLUSTER_NAME" \
        --name="workloads-r5-xlarge" \
        --region="$REGION" \
        --node-type=r5.xlarge \
        --nodes=4 \
        --nodes-min=3 \
        --nodes-max=6 \
        --node-labels="node-role=workloads,workload-type=general" \
        --node-volume-size=150 \
        --node-volume-type=gp3 \
        --managed

    # Wait for nodes to be ready
    wait_for_node_ready "node-role=workloads" || exit 1

    # Cordon old nodes
    cordon_nodes "t3.large"

    # Get t3.large nodes
    t3_large_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels["node.kubernetes.io/instance-type"] == "t3.large") | .metadata.name')

    # Identify high-memory node first (ip-10-0-148-10)
    high_memory_node=$(kubectl top nodes --no-headers | sort -k4 -rh | head -1 | awk '{print $1}')
    log_info "Migrating high-memory node first: $high_memory_node"

    drain_node "$high_memory_node" "$STATEFULSET_GRACE_PERIOD"

    # Wait 10 minutes for StatefulSets to reschedule
    log_info "Waiting 10 minutes for StatefulSets to stabilize..."
    sleep 600

    verify_pods_rescheduled "staging-platform-gitlab" || exit 1
    verify_pods_rescheduled "staging-platform-sonarqube" || exit 1

    # Drain remaining nodes in pairs
    remaining_nodes=$(echo "$t3_large_nodes" | grep -v "$high_memory_node")
    count=0

    for node in $remaining_nodes; do
        drain_node "$node" "$DRAIN_GRACE_PERIOD"
        count=$((count + 1))

        # After every 2 nodes, wait and verify
        if [ $((count % 2)) -eq 0 ]; then
            log_info "Waiting 5 minutes before next batch..."
            sleep 300
            verify_node_health
        fi
    done

    # Final validation
    log_info "Running final validation checks..."
    sleep 120

    kubectl get pods --all-namespaces -o wide | grep -E "(gitlab|sonarqube|loki|argocd|vault)"

    # Check Loki chunks-cache (was failing before)
    loki_cache=$(kubectl get pods -n staging-observability-monitoring -o wide | grep loki-chunks-cache || true)
    if [ -z "$loki_cache" ]; then
        log_warn "Loki chunks-cache not found. May need manual intervention."
    else
        log_info "Loki chunks-cache status:"
        echo "$loki_cache"
    fi

    log_info "Phase 2 migration completed successfully!"
    log_warn "Monitor cluster for 7 days before proceeding to Phase 3"
    log_warn "To delete old node group after validation: ./node-rightsizing-migration-playbook.sh cleanup phase2"
}

#
# PHASE 3: Critical Pool (t3.xlarge → r5.xlarge)
#
phase3_migrate() {
    log_info "=== PHASE 3: Critical Pool Migration ==="
    log_info "Migrating: 2x t3.xlarge → 2x r5.xlarge"
    log_warn "This phase includes 5-minute planned downtime for Vault/RabbitMQ"

    read -p "Confirm planned downtime window approved? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_error "Aborted by user"
        exit 1
    fi

    check_prerequisites
    verify_node_health

    # Create comprehensive backup
    log_info "Creating comprehensive backup (this may take 5-10 minutes)..."
    create_backup "staging-security-vault,staging-data-infrastructure"

    # Verify Vault status before migration
    log_info "Verifying Vault status..."
    kubectl exec -n staging-security-vault vault-0 -- vault status || true

    # Create new node group with critical taint
    log_info "Creating r5.xlarge node group with critical taint..."
    eksctl create nodegroup \
        --cluster="$CLUSTER_NAME" \
        --name="critical-r5-xlarge" \
        --region="$REGION" \
        --node-type=r5.xlarge \
        --nodes=2 \
        --nodes-min=2 \
        --nodes-max=3 \
        --node-labels="node-role=critical,workload-type=data-services" \
        --node-taints="workload=critical:NoSchedule" \
        --node-volume-size=200 \
        --node-volume-type=gp3 \
        --managed

    # Wait for nodes to be ready
    wait_for_node_ready "node-role=critical" || exit 1

    # Cordon old nodes
    cordon_nodes "t3.xlarge"

    # Get t3.xlarge nodes
    t3_xlarge_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels["node.kubernetes.io/instance-type"] == "t3.xlarge") | .metadata.name')

    # Drain first critical node (Vault HA can tolerate 1 replica down)
    first_node=$(echo "$t3_xlarge_nodes" | head -1)
    log_warn "PLANNED DOWNTIME STARTS NOW"

    drain_node "$first_node" "$STATEFULSET_GRACE_PERIOD"

    # Wait for Vault HA failover
    log_info "Waiting for Vault HA failover (60 seconds)..."
    sleep 60

    # Verify Vault unsealed
    vault_status=$(kubectl exec -n staging-security-vault vault-0 -- vault status 2>&1 || true)
    if echo "$vault_status" | grep -q "Sealed.*false"; then
        log_info "Vault is unsealed and healthy"
    else
        log_error "Vault may be sealed or unhealthy:"
        echo "$vault_status"
        log_error "ABORTING MIGRATION - manual intervention required"
        exit 1
    fi

    # Drain second critical node
    second_node=$(echo "$t3_xlarge_nodes" | tail -1)
    drain_node "$second_node" "$STATEFULSET_GRACE_PERIOD"

    # Wait for all critical services
    log_info "Waiting for critical services to stabilize (5 minutes)..."
    sleep 300

    # Comprehensive validation
    log_info "Running comprehensive validation checks..."

    # Verify Vault
    kubectl get pods -n staging-security-vault -o wide
    vault_unsealed=$(kubectl exec -n staging-security-vault vault-0 -- vault status | grep Sealed | grep false | wc -l)
    if [ "$vault_unsealed" -eq 0 ]; then
        log_error "Vault is sealed! Manual unseal required."
        log_error "Run: kubectl exec -n staging-security-vault vault-0 -- vault operator unseal"
        exit 1
    fi

    # Verify RabbitMQ
    kubectl get pods -n staging-data-infrastructure -o wide | grep rabbitmq

    # Verify ExternalSecrets synced
    es_synced=$(kubectl get externalsecrets --all-namespaces --no-headers | grep SecretSynced | wc -l)
    log_info "ExternalSecrets synced: $es_synced/10"
    if [ "$es_synced" -lt 10 ]; then
        log_warn "Some ExternalSecrets are not synced. Check manually:"
        kubectl get externalsecrets --all-namespaces
    fi

    log_warn "PLANNED DOWNTIME ENDED"
    log_info "Phase 3 migration completed successfully!"
    log_warn "Monitor cluster for 14 days before finalizing"
    log_warn "To delete old node group after validation: ./node-rightsizing-migration-playbook.sh cleanup phase3"
}

#
# CLEANUP: Delete old node groups after validation
#
cleanup_phase() {
    local phase=$1

    case $phase in
        phase1)
            delete_node_group "system-t3-medium"
            ;;
        phase2)
            delete_node_group "workloads-t3-large"
            ;;
        phase3)
            delete_node_group "critical-t3-xlarge"
            ;;
        *)
            log_error "Unknown phase: $phase"
            exit 1
            ;;
    esac
}

#
# ROLLBACK: Restore old node groups
#
rollback_phase() {
    local phase=$1

    log_warn "=== ROLLBACK: $phase ==="

    case $phase in
        phase1)
            log_info "Uncordoning t3.medium nodes..."
            kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels["node.kubernetes.io/instance-type"] == "t3.medium") | .metadata.name' | xargs -I {} kubectl uncordon {}

            log_info "Cordoning r5.large nodes..."
            kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels["node.kubernetes.io/instance-type"] == "r5.large") | .metadata.name' | xargs -I {} kubectl cordon {}

            log_info "Draining r5.large nodes..."
            kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels["node.kubernetes.io/instance-type"] == "r5.large") | .metadata.name' | xargs -I {} kubectl drain {} --ignore-daemonsets --delete-emptydir-data --grace-period=120

            log_info "Deleting r5.large node group..."
            delete_node_group "system-r5-large"
            ;;

        phase2)
            log_info "Uncordoning t3.large nodes..."
            kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels["node.kubernetes.io/instance-type"] == "t3.large") | .metadata.name' | xargs -I {} kubectl uncordon {}

            log_info "Cordoning r5.xlarge workload nodes..."
            kubectl get nodes -l node-role=workloads -o json | jq -r '.items[] | select(.metadata.labels["node.kubernetes.io/instance-type"] == "r5.xlarge") | .metadata.name' | xargs -I {} kubectl cordon {}

            log_info "Draining r5.xlarge workload nodes..."
            kubectl get nodes -l node-role=workloads -o json | jq -r '.items[] | select(.metadata.labels["node.kubernetes.io/instance-type"] == "r5.xlarge") | .metadata.name' | xargs -I {} kubectl drain {} --ignore-daemonsets --delete-emptydir-data --grace-period=300

            log_info "Deleting r5.xlarge workload node group..."
            delete_node_group "workloads-r5-xlarge"
            ;;

        phase3)
            log_warn "Phase 3 rollback requires Velero restore!"
            log_info "1. Scale up old t3.xlarge node group"
            log_info "2. Restore Vault backup: velero restore create --from-backup <backup-name>"
            log_info "3. Unseal Vault manually if needed"
            log_info "4. Delete r5.xlarge critical node group"

            read -p "Proceed with automated rollback? (yes/no): " confirm
            if [[ "$confirm" != "yes" ]]; then
                log_error "Manual rollback required. Exiting."
                exit 1
            fi

            # Emergency rollback
            log_info "Scaling up old t3.xlarge node group..."
            eksctl scale nodegroup \
                --cluster="$CLUSTER_NAME" \
                --name="critical-t3-xlarge" \
                --nodes=2 \
                --region="$REGION"

            wait_for_node_ready "instance-type=t3.xlarge" || exit 1

            log_info "Force-rescheduling Vault pods..."
            kubectl delete pod -n staging-security-vault vault-0 vault-1 vault-2 --grace-period=0 --force || true

            sleep 120

            log_warn "Verify Vault status manually:"
            kubectl get pods -n staging-security-vault
            log_warn "If Vault is sealed, run: kubectl exec -n staging-security-vault vault-0 -- vault operator unseal"
            ;;

        *)
            log_error "Unknown phase: $phase"
            exit 1
            ;;
    esac

    log_info "Rollback completed. Verify cluster health manually."
}

#
# MAIN
#
main() {
    local action=${1:-}
    local phase=${2:-}

    case $action in
        phase1)
            phase1_migrate
            ;;
        phase2)
            phase2_migrate
            ;;
        phase3)
            phase3_migrate
            ;;
        cleanup)
            if [ -z "$phase" ]; then
                log_error "Usage: $0 cleanup <phase1|phase2|phase3>"
                exit 1
            fi
            cleanup_phase "$phase"
            ;;
        rollback)
            if [ -z "$phase" ]; then
                log_error "Usage: $0 rollback <phase1|phase2|phase3>"
                exit 1
            fi
            rollback_phase "$phase"
            ;;
        *)
            echo "Usage: $0 <phase1|phase2|phase3|cleanup|rollback> [phase]"
            echo ""
            echo "Actions:"
            echo "  phase1          - Migrate system pool (t3.medium → r5.large)"
            echo "  phase2          - Migrate workloads pool (t3.large → r5.xlarge)"
            echo "  phase3          - Migrate critical pool (t3.xlarge → r5.xlarge)"
            echo "  cleanup <phase> - Delete old node group after validation"
            echo "  rollback <phase> - Rollback to old node group"
            echo ""
            echo "Examples:"
            echo "  $0 phase1"
            echo "  $0 cleanup phase1"
            echo "  $0 rollback phase2"
            exit 1
            ;;
    esac
}

main "$@"
