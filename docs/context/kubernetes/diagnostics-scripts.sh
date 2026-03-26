#!/bin/bash
# ============================================================
# Kubernetes Monitoring Diagnostics Script
# Gerado por: Monitoring Orchestrator
# Data: 2026-03-24
# Uso: ./diagnostics-scripts.sh [staging|prod|all]
# ============================================================

set -e

PROFILE="k8s-platform-prod"
REGION="us-east-1"
CONTEXT_PROD="arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod"
CONTEXT_STAGING="k8s-platform-staging"
OUTPUT_DIR="/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/context/kubernetes/diag-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUTPUT_DIR"
echo "Output directory: $OUTPUT_DIR"

# ============================================================
# FUNÇÃO: Check auth
# ============================================================
check_auth() {
    echo "=== Checking AWS Auth ==="
    aws sts get-caller-identity --profile "$PROFILE" 2>&1 || {
        echo "ERROR: AWS auth failed. Run: aws sso login --profile $PROFILE"
        exit 1
    }
}

# ============================================================
# FUNÇÃO: Update kubeconfig
# ============================================================
update_kubeconfig() {
    echo "=== Updating kubeconfig ==="
    aws eks update-kubeconfig --region "$REGION" --name k8s-platform-staging --profile "$PROFILE" 2>&1
    aws eks update-kubeconfig --region "$REGION" --name k8s-platform-prod --profile "$PROFILE" 2>&1
}

# ============================================================
# FASE 1: Overview Global
# ============================================================
phase1_overview() {
    local CONTEXT=$1
    local ENV=$2
    echo ""
    echo "============================================================"
    echo "FASE 1: Overview Global — $ENV"
    echo "============================================================"

    echo "--- Nodes ---"
    kubectl --context "$CONTEXT" get nodes -o wide 2>&1 | tee "$OUTPUT_DIR/${ENV}-nodes.txt"

    echo ""
    echo "--- All pods (non-Running/Completed) ---"
    kubectl --context "$CONTEXT" get pods -A -o wide 2>&1 | grep -vE "Running|Completed|NAMESPACE" | tee "$OUTPUT_DIR/${ENV}-pods-abnormal.txt"

    echo ""
    echo "--- Pods Summary per Namespace ---"
    kubectl --context "$CONTEXT" get pods -A --no-headers 2>&1 | awk '{print $1, $4}' | sort | uniq -c | sort -rn | tee "$OUTPUT_DIR/${ENV}-pods-summary.txt"
}

# ============================================================
# FASE 1: P1 — vault-prod-0 Investigation
# ============================================================
investigate_vault_p1() {
    local CONTEXT=$CONTEXT_PROD
    echo ""
    echo "============================================================"
    echo "P1 INVESTIGATION: vault-prod-0"
    echo "============================================================"

    echo "--- Pod describe ---"
    kubectl --context "$CONTEXT" -n prod-security-vault describe pod vault-prod-0 2>&1 | tee "$OUTPUT_DIR/prod-vault-pod-describe.txt"

    echo ""
    echo "--- PVC list ---"
    kubectl --context "$CONTEXT" -n prod-security-vault get pvc -o wide 2>&1 | tee "$OUTPUT_DIR/prod-vault-pvc.txt"

    echo ""
    echo "--- PV list ---"
    kubectl --context "$CONTEXT" -n prod-security-vault get pv 2>&1 | tee "$OUTPUT_DIR/prod-vault-pv.txt"

    echo ""
    echo "--- StatefulSet status ---"
    kubectl --context "$CONTEXT" -n prod-security-vault get statefulset 2>&1 | tee "$OUTPUT_DIR/prod-vault-sts.txt"

    echo ""
    echo "--- Events ---"
    kubectl --context "$CONTEXT" -n prod-security-vault get events --sort-by='.lastTimestamp' 2>&1 | tail -30 | tee "$OUTPUT_DIR/prod-vault-events.txt"

    echo ""
    echo "--- EBS Volume Status ---"
    aws ec2 describe-volumes \
        --volume-ids vol-065f3b18bebee9fc0 \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'Volumes[0].{State:State,AZ:AvailabilityZone,Attachments:Attachments,Size:Size,VolumeId:VolumeId}' \
        --output json 2>&1 | tee "$OUTPUT_DIR/prod-vault-ebs-volume.txt"
}

# ============================================================
# FASE 1: Componentes críticos staging
# ============================================================
check_staging_components() {
    local CONTEXT=$CONTEXT_STAGING
    echo ""
    echo "============================================================"
    echo "STAGING: Componentes Críticos"
    echo "============================================================"

    NAMESPACES=(
        "staging-platform-gitlab"
        "staging-observability-monitoring"
        "staging-platform-sonarqube"
        "staging-platform-backstage"
        "staging-data-harbor"
        "staging-data-hatch"
        "staging-data-infrastructure"
        "linkerd"
        "linkerd-viz"
        "calico-system"
        "vault-system"
        "kyverno"
        "argocd"
        "cert-manager"
        "external-dns"
        "kube-system"
    )

    for NS in "${NAMESPACES[@]}"; do
        echo ""
        echo "--- Namespace: $NS ---"
        kubectl --context "$CONTEXT" -n "$NS" get pods -o wide --no-headers 2>&1 | \
            awk '{printf "  %-50s %-10s %-20s %s\n", $1, $4, $6, $8}' | \
            tee -a "$OUTPUT_DIR/staging-all-components.txt"
    done
}

# ============================================================
# FASE 1: Componentes prod
# ============================================================
check_prod_components() {
    local CONTEXT=$CONTEXT_PROD
    echo ""
    echo "============================================================"
    echo "PROD: Componentes Críticos"
    echo "============================================================"

    NAMESPACES=(
        "prod-security-vault"
        "prod-data-rabbitmq"
        "prod-platform-harbor"
        "production"
    )

    for NS in "${NAMESPACES[@]}"; do
        echo ""
        echo "--- Namespace: $NS ---"
        kubectl --context "$CONTEXT" -n "$NS" get pods -o wide --no-headers 2>&1 | \
            awk '{printf "  %-50s %-10s %-20s %s\n", $1, $4, $6, $8}' | \
            tee -a "$OUTPUT_DIR/prod-all-components.txt"
    done
}

# ============================================================
# FASE 1: ExternalSecrets check
# ============================================================
check_external_secrets() {
    local CONTEXT=$CONTEXT_PROD
    echo ""
    echo "============================================================"
    echo "ExternalSecrets — Status"
    echo "============================================================"

    echo "--- ESO Controller ---"
    kubectl --context "$CONTEXT" get pods -A -l app.kubernetes.io/name=external-secrets 2>&1 | tee "$OUTPUT_DIR/eso-controller.txt"

    echo ""
    echo "--- ExternalSecrets não sincronizados ---"
    kubectl --context "$CONTEXT" get externalsecrets -A -o wide 2>&1 | grep -v SecretSynced | tee "$OUTPUT_DIR/eso-not-synced.txt" || echo "All synced"
}

# ============================================================
# FASE 1: ArgoCD — apps fora de sync
# ============================================================
check_argocd() {
    local CONTEXT=$CONTEXT_STAGING
    echo ""
    echo "============================================================"
    echo "ArgoCD — Applications"
    echo "============================================================"

    kubectl --context "$CONTEXT" -n argocd get applications -o wide 2>&1 | tee "$OUTPUT_DIR/argocd-apps.txt"
}

# ============================================================
# MAIN
# ============================================================
main() {
    check_auth
    update_kubeconfig

    TARGET="${1:-all}"

    if [[ "$TARGET" == "staging" || "$TARGET" == "all" ]]; then
        phase1_overview "$CONTEXT_STAGING" "staging"
        check_staging_components
    fi

    if [[ "$TARGET" == "prod" || "$TARGET" == "all" ]]; then
        phase1_overview "$CONTEXT_PROD" "prod"
        check_prod_components
        investigate_vault_p1
        check_external_secrets
    fi

    check_argocd

    echo ""
    echo "============================================================"
    echo "Diagnostics complete. Output saved to: $OUTPUT_DIR"
    echo "============================================================"
}

main "$@"
