#!/usr/bin/env bash
# Velero Configuration Drift Detection
# Purpose: Detect configuration drift between Terraform state and live Kubernetes resources
# Use Case: CI/CD pipeline validation, scheduled audits
#
# Exit Codes:
#   0 - No drift detected
#   1 - Drift detected (requires remediation)
#   2 - Error (prerequisites not met, cluster unavailable)
#
# Usage:
#   ./check-velero-drift.sh [--json] [--auto-fix]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="k8s-platform-prod"
VELERO_NAMESPACE="velero"
TERRAFORM_DIR="/home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging"

# Parse arguments
JSON_OUTPUT=false
AUTO_FIX=false

for arg in "$@"; do
    case $arg in
        --json)
            JSON_OUTPUT=true
            ;;
        --auto-fix)
            AUTO_FIX=true
            ;;
        --help|-h)
            echo "Usage: $0 [--json] [--auto-fix]"
            echo ""
            echo "Options:"
            echo "  --json      Output results in JSON format"
            echo "  --auto-fix  Automatically fix detected drift (requires confirmation)"
            echo "  --help,-h   Show this help message"
            exit 0
            ;;
    esac
done

# Logging functions
log_info() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

log_warning() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $1"
    fi
}

log_error() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${RED}[ERROR]${NC} $1" >&2
    fi
}

# Initialize drift tracking
DRIFT_DETECTED=false
DRIFT_ISSUES=()

# Step 1: Verify prerequisites
log_info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found"
    exit 2
fi

if ! command -v terraform &> /dev/null; then
    log_error "terraform not found"
    exit 2
fi

if ! kubectl cluster-info &> /dev/null; then
    log_error "Kubernetes cluster not accessible"
    exit 2
fi

# Step 2: Get expected configuration from Terraform
log_info "Retrieving expected configuration from Terraform..."

cd "$TERRAFORM_DIR"

if ! terraform state list &> /dev/null; then
    log_error "Terraform state not found"
    exit 2
fi

EXPECTED_ROLE_ARN=$(terraform output -raw velero_role_arn 2>/dev/null)
EXPECTED_BUCKET=$(terraform output -raw velero_bucket_name 2>/dev/null)

if [ -z "$EXPECTED_ROLE_ARN" ] || [ -z "$EXPECTED_BUCKET" ]; then
    log_error "Failed to retrieve Terraform outputs"
    exit 2
fi

log_info "Expected configuration:"
log_info "  IAM Role ARN: ${EXPECTED_ROLE_ARN}"
log_info "  S3 Bucket: ${EXPECTED_BUCKET}"

# Step 3: Get current configuration from Kubernetes
log_info "Retrieving current configuration from Kubernetes..."

CURRENT_ROLE_ARN=$(kubectl get sa velero-server -n "$VELERO_NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
CURRENT_BUCKET=$(kubectl get backupstoragelocation default -n "$VELERO_NAMESPACE" -o jsonpath='{.spec.objectStorage.bucket}' 2>/dev/null || echo "")
BSL_STATUS=$(kubectl get backupstoragelocation default -n "$VELERO_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [ -z "$CURRENT_ROLE_ARN" ]; then
    log_error "Failed to retrieve current ServiceAccount annotation"
    exit 2
fi

if [ -z "$CURRENT_BUCKET" ]; then
    log_error "Failed to retrieve current BackupStorageLocation bucket"
    exit 2
fi

log_info "Current configuration:"
log_info "  IAM Role ARN: ${CURRENT_ROLE_ARN}"
log_info "  S3 Bucket: ${CURRENT_BUCKET}"
log_info "  BSL Status: ${BSL_STATUS}"

# Step 4: Detect drift
log_info "Checking for configuration drift..."

if [[ "$CURRENT_ROLE_ARN" != "$EXPECTED_ROLE_ARN" ]]; then
    DRIFT_DETECTED=true
    DRIFT_ISSUES+=("IAM_ROLE_ARN_MISMATCH")
    log_warning "Drift detected: IAM Role ARN mismatch"
    log_warning "  Expected: ${EXPECTED_ROLE_ARN}"
    log_warning "  Current:  ${CURRENT_ROLE_ARN}"
fi

if [[ "$CURRENT_BUCKET" != "$EXPECTED_BUCKET" ]]; then
    DRIFT_DETECTED=true
    DRIFT_ISSUES+=("S3_BUCKET_MISMATCH")
    log_warning "Drift detected: S3 Bucket mismatch"
    log_warning "  Expected: ${EXPECTED_BUCKET}"
    log_warning "  Current:  ${CURRENT_BUCKET}"
fi

if [[ "$BSL_STATUS" != "Available" ]]; then
    DRIFT_DETECTED=true
    DRIFT_ISSUES+=("BSL_NOT_AVAILABLE")
    log_warning "Drift detected: BackupStorageLocation not Available"
    log_warning "  Status: ${BSL_STATUS}"
fi

# Step 5: Output results
if [[ "$JSON_OUTPUT" == "true" ]]; then
    # JSON output for automation
    cat <<EOF
{
  "drift_detected": $([ "$DRIFT_DETECTED" == "true" ] && echo "true" || echo "false"),
  "drift_issues": [$(IFS=,; echo "\"${DRIFT_ISSUES[*]:-}\"" | sed 's/" "/","/g')],
  "expected": {
    "iam_role_arn": "${EXPECTED_ROLE_ARN}",
    "s3_bucket": "${EXPECTED_BUCKET}"
  },
  "current": {
    "iam_role_arn": "${CURRENT_ROLE_ARN}",
    "s3_bucket": "${CURRENT_BUCKET}",
    "bsl_status": "${BSL_STATUS}"
  },
  "cluster": "${CLUSTER_NAME}",
  "namespace": "${VELERO_NAMESPACE}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
else
    # Human-readable output
    echo ""
    echo "=========================================="
    if [[ "$DRIFT_DETECTED" == "true" ]]; then
        echo -e "${RED}Configuration Drift Detected${NC}"
    else
        echo -e "${GREEN}No Drift Detected${NC}"
    fi
    echo "=========================================="
    echo ""

    if [[ "$DRIFT_DETECTED" == "true" ]]; then
        echo "Drift Issues:"
        for issue in "${DRIFT_ISSUES[@]}"; do
            echo "  - ${issue}"
        done
        echo ""
        echo "Remediation:"
        echo "  Run: ./scripts/velero/update-velero-values.sh"
        echo ""
    else
        echo "✓ IAM Role ARN: Correct"
        echo "✓ S3 Bucket: Correct"
        echo "✓ BackupStorageLocation: Available"
        echo ""
    fi
fi

# Step 6: Auto-fix (if requested)
if [[ "$DRIFT_DETECTED" == "true" ]] && [[ "$AUTO_FIX" == "true" ]]; then
    log_info "Auto-fix enabled. Applying remediation..."

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    UPDATE_SCRIPT="${SCRIPT_DIR}/update-velero-values.sh"

    if [ -f "$UPDATE_SCRIPT" ]; then
        log_info "Running update-velero-values.sh..."
        bash "$UPDATE_SCRIPT"
    else
        log_error "Update script not found: ${UPDATE_SCRIPT}"
        exit 2
    fi
fi

# Exit with appropriate code
if [[ "$DRIFT_DETECTED" == "true" ]]; then
    exit 1
else
    exit 0
fi
