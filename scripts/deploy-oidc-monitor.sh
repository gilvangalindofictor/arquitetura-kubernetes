#!/usr/bin/env bash

################################################################################
# OIDC Monitor Deployment Script
# Purpose: Deploy and configure OIDC monitoring system
# Usage: ./deploy-oidc-monitor.sh [OPTIONS]
# Author: Platform Team
# Date: 2026-02-12
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
NAMESPACE="monitoring"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

create_namespace() {
    log_info "Creating namespace: $NAMESPACE"

    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warn "Namespace $NAMESPACE already exists"
    else
        kubectl create namespace "$NAMESPACE"
        log_success "Namespace created"
    fi
}

update_configmap() {
    log_info "Updating ConfigMap with monitoring script..."

    kubectl create configmap oidc-monitor-script \
        --from-file=oidc-monitor.sh="${SCRIPT_DIR}/oidc-monitor.sh" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    log_success "ConfigMap updated"
}

configure_slack() {
    local webhook_url="$1"

    if [[ -z "$webhook_url" ]]; then
        log_warn "No Slack webhook URL provided. Skipping Slack configuration."
        log_info "To configure later, run:"
        echo "  kubectl create secret generic oidc-monitor-slack \\"
        echo "    --from-literal=webhook-url='YOUR_WEBHOOK_URL' \\"
        echo "    --namespace=$NAMESPACE \\"
        echo "    --dry-run=client -o yaml | kubectl apply -f -"
        return
    fi

    log_info "Configuring Slack webhook..."

    kubectl create secret generic oidc-monitor-slack \
        --from-literal=webhook-url="$webhook_url" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    log_success "Slack webhook configured"
}

deploy_resources() {
    log_info "Deploying OIDC monitor resources..."

    kubectl apply -f "${PROJECT_ROOT}/k8s/monitoring/oidc-monitor-cronjob.yaml"

    log_success "Resources deployed"
}

verify_deployment() {
    log_info "Verifying deployment..."

    echo ""
    log_info "CronJobs:"
    kubectl get cronjobs -n "$NAMESPACE" -l app=oidc-monitor

    echo ""
    log_info "ServiceAccount:"
    kubectl get serviceaccount -n "$NAMESPACE" oidc-monitor

    echo ""
    log_info "PVC:"
    kubectl get pvc -n "$NAMESPACE" oidc-monitor-logs

    echo ""
    log_info "Secrets:"
    kubectl get secret -n "$NAMESPACE" oidc-monitor-slack 2>/dev/null || log_warn "Slack secret not configured"

    log_success "Deployment verification complete"
}

run_manual_test() {
    log_info "Running manual test..."

    local job_name="oidc-monitor-test-$(date +%s)"

    kubectl create job "$job_name" \
        --from=job/oidc-monitor-manual \
        -n "$NAMESPACE"

    log_info "Waiting for job to complete (timeout: 5m)..."

    if kubectl wait --for=condition=complete --timeout=300s "job/$job_name" -n "$NAMESPACE"; then
        log_success "Test job completed successfully"
        echo ""
        log_info "Job logs:"
        kubectl logs -n "$NAMESPACE" "job/$job_name" --tail=50
    else
        log_error "Test job failed or timed out"
        echo ""
        log_info "Job logs:"
        kubectl logs -n "$NAMESPACE" "job/$job_name" --tail=50
        exit 1
    fi
}

show_usage() {
    cat <<EOF
OIDC Monitor Deployment Script

Usage: $0 [OPTIONS]

Options:
  -s, --slack-webhook URL   Slack webhook URL for alerts
  -t, --test                Run a manual test after deployment
  -u, --update-only         Only update ConfigMap (skip full deployment)
  -h, --help                Show this help message

Examples:
  # Full deployment with Slack
  $0 --slack-webhook https://hooks.slack.com/services/YOUR/WEBHOOK/URL

  # Deployment without Slack
  $0

  # Update ConfigMap only
  $0 --update-only

  # Deploy and run test
  $0 --test

EOF
}

main() {
    local slack_webhook=""
    local run_test=false
    local update_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--slack-webhook)
                slack_webhook="$2"
                shift 2
                ;;
            -t|--test)
                run_test=true
                shift
                ;;
            -u|--update-only)
                update_only=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    echo ""
    echo "========================================="
    echo "OIDC Monitor Deployment"
    echo "========================================="
    echo ""

    check_prerequisites

    if [[ "$update_only" = true ]]; then
        log_info "Running update-only mode"
        update_configmap
        log_success "Update complete"
        exit 0
    fi

    create_namespace
    update_configmap
    configure_slack "$slack_webhook"
    deploy_resources
    verify_deployment

    if [[ "$run_test" = true ]]; then
        echo ""
        run_manual_test
    fi

    echo ""
    echo "========================================="
    echo "Deployment Complete!"
    echo "========================================="
    echo ""
    log_info "Next steps:"
    echo "  1. Verify CronJobs are scheduled:"
    echo "     kubectl get cronjobs -n $NAMESPACE"
    echo ""
    echo "  2. Run a manual test:"
    echo "     kubectl create job oidc-test-\$(date +%s) --from=job/oidc-monitor-manual -n $NAMESPACE"
    echo ""
    echo "  3. View logs:"
    echo "     kubectl logs -n $NAMESPACE job/oidc-test-<timestamp>"
    echo ""
    echo "  4. Check reports:"
    echo "     kubectl exec -n $NAMESPACE <pod> -- ls -lh /var/log/oidc-monitor/reports/"
    echo ""
    log_info "For more information, see: docs/runbooks/oidc-monitoring.md"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
