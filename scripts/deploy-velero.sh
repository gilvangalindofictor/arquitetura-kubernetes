#!/bin/bash
# Velero Backup/DR Deployment Script
# GAP-003 Implementation
# Author: Platform Team
# Date: 2026-02-25

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
TERRAFORM_DIR="${PROJECT_ROOT}/platform-provisioning/aws/kubernetes/terraform"
MANIFESTS_DIR="${TERRAFORM_DIR}/kubectl-manifests/velero"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install: https://aws.amazon.com/cli/"
        exit 1
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi

    # Check terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Please install: https://www.terraform.io/downloads"
        exit 1
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "Helm not found. Please install: https://helm.sh/docs/intro/install/"
        exit 1
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Please install: sudo apt-get install jq"
        exit 1
    fi

    log_success "All prerequisites met"
}

# Verify AWS authentication
verify_aws_auth() {
    log_info "Verifying AWS authentication..."

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS authentication failed. Please run: aws sso login --profile k8s-platform-staging"
        exit 1
    fi

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log_success "Authenticated to AWS account: ${ACCOUNT_ID}"
}

# Verify Kubernetes access
verify_k8s_access() {
    log_info "Verifying Kubernetes access..."

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Kubernetes cluster not accessible. Please configure kubeconfig."
        exit 1
    fi

    CLUSTER_NAME=$(kubectl config current-context)
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    log_success "Connected to cluster: ${CLUSTER_NAME} (${NODE_COUNT} nodes)"
}

# Apply Terraform infrastructure
apply_terraform() {
    log_info "Applying Terraform infrastructure..."

    cd "${TERRAFORM_DIR}"

    # Check if module exists
    if [ ! -d "modules/velero-backup" ]; then
        log_error "Velero Terraform module not found at: modules/velero-backup"
        exit 1
    fi

    # Terraform init
    log_info "Running terraform init..."
    terraform init -upgrade > /dev/null 2>&1

    # Terraform plan
    log_info "Running terraform plan..."
    terraform plan -out=velero-backup.tfplan

    # Prompt for confirmation
    echo ""
    read -p "Do you want to apply these changes? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi

    # Terraform apply
    log_info "Running terraform apply..."
    terraform apply velero-backup.tfplan

    # Get outputs
    export VELERO_ROLE_ARN=$(terraform output -raw velero_role_arn 2>/dev/null || echo "")
    export VELERO_BUCKET=$(terraform output -raw velero_bucket_name 2>/dev/null || echo "")

    if [ -z "${VELERO_ROLE_ARN}" ] || [ -z "${VELERO_BUCKET}" ]; then
        log_error "Failed to retrieve Terraform outputs. Check if module outputs are configured."
        exit 1
    fi

    log_success "Terraform applied successfully"
    log_info "Velero IAM Role ARN: ${VELERO_ROLE_ARN}"
    log_info "Velero S3 Bucket: ${VELERO_BUCKET}"

    cd - > /dev/null
}

# Install Velero CLI
install_velero_cli() {
    log_info "Installing Velero CLI..."

    # Check if already installed
    if command -v velero &> /dev/null; then
        CURRENT_VERSION=$(velero version --client-only 2>/dev/null | grep 'Client:' | awk '{print $2}' || echo "unknown")
        log_info "Velero CLI already installed: ${CURRENT_VERSION}"
        return
    fi

    # Download and install
    VELERO_VERSION="v1.15.1"
    VELERO_URL="https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz"

    log_info "Downloading Velero CLI ${VELERO_VERSION}..."
    curl -fsSL "${VELERO_URL}" | tar -xz -C /tmp

    log_info "Installing Velero CLI to /usr/local/bin..."
    sudo mv "/tmp/velero-${VELERO_VERSION}-linux-amd64/velero" /usr/local/bin/
    sudo chmod +x /usr/local/bin/velero

    # Verify installation
    INSTALLED_VERSION=$(velero version --client-only 2>/dev/null | grep 'Client:' | awk '{print $2}' || echo "unknown")
    log_success "Velero CLI installed: ${INSTALLED_VERSION}"
}

# Install Velero via Helm
install_velero_helm() {
    log_info "Installing Velero via Helm..."

    # Add Helm repository
    log_info "Adding vmware-tanzu Helm repository..."
    helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts > /dev/null 2>&1
    helm repo update > /dev/null 2>&1

    # Template values.yaml
    log_info "Rendering Helm values..."
    cd "${MANIFESTS_DIR}"

    if [ ! -f "values.yaml" ]; then
        log_error "Helm values file not found at: ${MANIFESTS_DIR}/values.yaml"
        exit 1
    fi

    sed -e "s|\${VELERO_ROLE_ARN}|${VELERO_ROLE_ARN}|g" \
        -e "s|\${VELERO_BUCKET_NAME}|${VELERO_BUCKET}|g" \
        values.yaml > values-rendered.yaml

    # Verify templated values
    if ! grep -q "${VELERO_ROLE_ARN}" values-rendered.yaml; then
        log_error "Failed to template VELERO_ROLE_ARN in values.yaml"
        exit 1
    fi

    if ! grep -q "${VELERO_BUCKET}" values-rendered.yaml; then
        log_error "Failed to template VELERO_BUCKET_NAME in values.yaml"
        exit 1
    fi

    # Install Velero
    log_info "Deploying Velero to Kubernetes..."
    helm upgrade --install velero vmware-tanzu/velero \
        --namespace velero \
        --create-namespace \
        --values values-rendered.yaml \
        --wait \
        --timeout 5m

    # Wait for pods to be ready
    log_info "Waiting for Velero pods to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=velero \
        -n velero \
        --timeout=300s

    # Verify Velero version
    log_info "Verifying Velero installation..."
    sleep 5  # Give server time to start
    velero version

    log_success "Velero installed successfully"
    cd - > /dev/null
}

# Deploy backup schedules
deploy_backup_schedules() {
    log_info "Deploying backup schedules..."

    cd "${MANIFESTS_DIR}"

    if [ ! -f "backup-schedules.yaml" ]; then
        log_error "Backup schedules file not found at: ${MANIFESTS_DIR}/backup-schedules.yaml"
        exit 1
    fi

    kubectl apply -f backup-schedules.yaml

    # Verify schedules created
    log_info "Verifying backup schedules..."
    sleep 2
    velero schedule get

    SCHEDULE_COUNT=$(velero schedule get -o json | jq '.items | length')
    log_success "${SCHEDULE_COUNT} backup schedules deployed"

    cd - > /dev/null
}

# Deploy restore testing CronJob
deploy_restore_testing() {
    log_info "Deploying automated restore testing..."

    cd "${MANIFESTS_DIR}"

    if [ ! -f "restore-testing-cronjob.yaml" ]; then
        log_error "Restore testing file not found at: ${MANIFESTS_DIR}/restore-testing-cronjob.yaml"
        exit 1
    fi

    kubectl apply -f restore-testing-cronjob.yaml

    # Verify CronJob created
    log_info "Verifying restore testing CronJob..."
    kubectl get cronjob -n velero velero-restore-test

    log_success "Restore testing CronJob deployed"

    cd - > /dev/null
}

# Run manual backup test
run_backup_test() {
    log_info "Running manual backup test..."

    BACKUP_NAME="test-backup-$(date +%Y%m%d%H%M%S)"

    log_info "Creating backup: ${BACKUP_NAME}"
    velero backup create "${BACKUP_NAME}" \
        --include-namespaces cert-manager \
        --wait \
        --timeout 10m

    # Check backup status
    BACKUP_STATUS=$(velero backup get "${BACKUP_NAME}" -o jsonpath='{.status.phase}')

    if [ "${BACKUP_STATUS}" = "Completed" ]; then
        log_success "Backup test PASSED: ${BACKUP_NAME}"
    else
        log_error "Backup test FAILED: ${BACKUP_NAME} (status: ${BACKUP_STATUS})"
        velero backup describe "${BACKUP_NAME}" --details
        exit 1
    fi

    # Verify backup in S3
    log_info "Verifying backup in S3..."
    aws s3 ls "s3://${VELERO_BUCKET}/backups/${BACKUP_NAME}/" --recursive | head -5

    # Export backup name for restore test
    export TEST_BACKUP_NAME="${BACKUP_NAME}"
}

# Run manual restore test
run_restore_test() {
    log_info "Running manual restore test..."

    RESTORE_NAME="test-restore-$(date +%Y%m%d%H%M%S)"

    log_info "Creating restore: ${RESTORE_NAME}"
    velero restore create "${RESTORE_NAME}" \
        --from-backup "${TEST_BACKUP_NAME}" \
        --namespace-mappings cert-manager:velero-restore-test \
        --wait \
        --timeout 10m

    # Check restore status
    RESTORE_STATUS=$(velero restore get "${RESTORE_NAME}" -o jsonpath='{.status.phase}')

    if [ "${RESTORE_STATUS}" = "Completed" ]; then
        log_success "Restore test PASSED: ${RESTORE_NAME}"
    else
        log_error "Restore test FAILED: ${RESTORE_NAME} (status: ${RESTORE_STATUS})"
        velero restore describe "${RESTORE_NAME}" --details
        exit 1
    fi

    # Verify restored resources
    log_info "Verifying restored resources..."
    RESOURCE_COUNT=$(kubectl get all -n velero-restore-test --no-headers 2>/dev/null | wc -l || echo "0")
    log_info "Restored ${RESOURCE_COUNT} resources in test namespace"

    # Cleanup
    log_info "Cleaning up test resources..."
    kubectl delete namespace velero-restore-test --timeout=60s 2>/dev/null || true
    velero restore delete "${RESTORE_NAME}" --confirm
    velero backup delete "${TEST_BACKUP_NAME}" --confirm

    log_success "Manual restore test completed"
}

# Print summary
print_summary() {
    echo ""
    echo "=========================================="
    log_success "Velero Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Deployment Summary:"
    echo "  - S3 Bucket: ${VELERO_BUCKET}"
    echo "  - IAM Role ARN: ${VELERO_ROLE_ARN}"
    echo "  - Backup Schedules: 4 (daily, weekly, hourly, monthly)"
    echo "  - Automated Testing: Weekly (Sunday 05:00 UTC)"
    echo ""
    echo "Next Steps:"
    echo "  1. Monitor first backup: $(date -u -d 'tomorrow 02:00' '+%Y-%m-%d 02:00 UTC')"
    echo "  2. Review DR runbook: docs/runbooks/disaster-recovery.md"
    echo "  3. Configure Slack notifications (optional)"
    echo "  4. Schedule simulated DR drill"
    echo ""
    echo "Useful Commands:"
    echo "  - List backups: velero backup get"
    echo "  - List schedules: velero schedule get"
    echo "  - Check S3: aws s3 ls s3://${VELERO_BUCKET}/backups/"
    echo "  - Velero logs: kubectl logs -n velero deployment/velero -f"
    echo ""
    echo "Documentation:"
    echo "  - ADR-079: docs/adr/adr-079-velero-backup-dr-implementation.md"
    echo "  - Logbook: docs/logbook/2026-02-25-gap-003-velero-backup-dr-implementation.md"
    echo "  - DR Runbook: docs/runbooks/disaster-recovery.md"
    echo ""
    echo "=========================================="
}

# Main execution
main() {
    echo "=========================================="
    echo "Velero Backup/DR Deployment - GAP-003"
    echo "=========================================="
    echo ""

    # Run all steps
    check_prerequisites
    verify_aws_auth
    verify_k8s_access
    apply_terraform
    install_velero_cli
    install_velero_helm
    deploy_backup_schedules
    deploy_restore_testing
    run_backup_test
    run_restore_test
    print_summary

    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"
