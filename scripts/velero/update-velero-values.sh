#!/usr/bin/env bash
# Update Velero Helm Values to Prevent IRSA Drift (AÇÃO-002)
# Purpose: Apply correct IAM role and S3 bucket configuration from Terraform
# Resolves: Configuration drift identified in VALIDAÇÃO-002
#
# Prerequisites:
#   - AWS CLI configured with valid credentials
#   - kubectl configured for k8s-platform-prod cluster
#   - Terraform outputs available in environments/staging/
#
# Usage:
#   ./update-velero-values.sh [--dry-run]

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
AWS_REGION="us-east-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/platform-provisioning/aws/kubernetes/terraform/environments/staging"
MANIFESTS_DIR="${PROJECT_ROOT}/platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/velero"

# Parse arguments
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AÇÃO-002: Update Velero Helm Values${NC}"
echo -e "${BLUE}Prevent IRSA Configuration Drift${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Verify prerequisites
echo -e "${YELLOW}[1/6] Verifying prerequisites...${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI not found${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl not found${NC}"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}ERROR: terraform not found${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}ERROR: helm not found${NC}"
    exit 1
fi

# Verify AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}ERROR: AWS credentials not configured or expired${NC}"
    echo -e "${YELLOW}Run: aws sso login${NC}"
    exit 1
fi

# Verify kubectl context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [[ ! "$CURRENT_CONTEXT" =~ $CLUSTER_NAME ]]; then
    echo -e "${RED}ERROR: kubectl not configured for cluster ${CLUSTER_NAME}${NC}"
    echo -e "${YELLOW}Current context: ${CURRENT_CONTEXT}${NC}"
    echo -e "${YELLOW}Run: aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo ""

# Step 2: Get Terraform outputs
echo -e "${YELLOW}[2/6] Retrieving Terraform outputs...${NC}"

cd "$TERRAFORM_DIR"

# Check if Terraform state exists
if ! terraform state list &> /dev/null; then
    echo -e "${RED}ERROR: Terraform state not found. Run 'terraform init' first.${NC}"
    exit 1
fi

# Get Velero configuration from Terraform
VELERO_ROLE_ARN=$(terraform output -raw velero_role_arn 2>/dev/null)
VELERO_BUCKET_NAME=$(terraform output -raw velero_bucket_name 2>/dev/null)

if [ -z "$VELERO_ROLE_ARN" ] || [ -z "$VELERO_BUCKET_NAME" ]; then
    echo -e "${RED}ERROR: Failed to retrieve Terraform outputs${NC}"
    echo -e "${YELLOW}Ensure module.velero_dr_staging is deployed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Terraform outputs retrieved${NC}"
echo -e "  IAM Role ARN: ${VELERO_ROLE_ARN}"
echo -e "  S3 Bucket: ${VELERO_BUCKET_NAME}"
echo ""

# Step 3: Get current Velero configuration
echo -e "${YELLOW}[3/6] Checking current Velero configuration...${NC}"

# Get current ServiceAccount annotation
CURRENT_ROLE_ARN=$(kubectl get sa velero-server -n "$VELERO_NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")

# Get current BackupStorageLocation bucket
CURRENT_BUCKET=$(kubectl get backupstoragelocation default -n "$VELERO_NAMESPACE" -o jsonpath='{.spec.objectStorage.bucket}' 2>/dev/null || echo "")

# Get current BackupStorageLocation status
BSL_STATUS=$(kubectl get backupstoragelocation default -n "$VELERO_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

echo -e "Current configuration:"
echo -e "  IAM Role ARN: ${CURRENT_ROLE_ARN}"
echo -e "  S3 Bucket: ${CURRENT_BUCKET}"
echo -e "  BSL Status: ${BSL_STATUS}"
echo ""

# Step 4: Check if update is needed
echo -e "${YELLOW}[4/6] Checking if update is needed...${NC}"

UPDATE_NEEDED=false

if [[ "$CURRENT_ROLE_ARN" != "$VELERO_ROLE_ARN" ]]; then
    echo -e "${RED}⚠ IAM Role ARN mismatch detected!${NC}"
    echo -e "  Expected: ${VELERO_ROLE_ARN}"
    echo -e "  Current: ${CURRENT_ROLE_ARN}"
    UPDATE_NEEDED=true
fi

if [[ "$CURRENT_BUCKET" != "$VELERO_BUCKET_NAME" ]]; then
    echo -e "${RED}⚠ S3 Bucket mismatch detected!${NC}"
    echo -e "  Expected: ${VELERO_BUCKET_NAME}"
    echo -e "  Current: ${CURRENT_BUCKET}"
    UPDATE_NEEDED=true
fi

if [[ "$UPDATE_NEEDED" == "false" ]]; then
    echo -e "${GREEN}✓ Configuration is correct. No update needed.${NC}"
    echo ""
    echo -e "${BLUE}Summary:${NC}"
    echo -e "  - IAM Role ARN: ✓ Correct"
    echo -e "  - S3 Bucket: ✓ Correct"
    echo -e "  - BSL Status: ${BSL_STATUS}"
    exit 0
fi

echo ""

# Step 5: Render Helm values
echo -e "${YELLOW}[5/6] Rendering Helm values with correct configuration...${NC}"

cd "$MANIFESTS_DIR"

if [ ! -f "values.yaml" ]; then
    echo -e "${RED}ERROR: Helm values file not found at: ${MANIFESTS_DIR}/values.yaml${NC}"
    exit 1
fi

# Template values.yaml with Terraform outputs
sed -e "s|\${VELERO_ROLE_ARN}|${VELERO_ROLE_ARN}|g" \
    -e "s|\${VELERO_BUCKET_NAME}|${VELERO_BUCKET_NAME}|g" \
    values.yaml > /tmp/velero-values-rendered.yaml

# Verify templated values
if ! grep -q "${VELERO_ROLE_ARN}" /tmp/velero-values-rendered.yaml; then
    echo -e "${RED}ERROR: Failed to template VELERO_ROLE_ARN in values.yaml${NC}"
    exit 1
fi

if ! grep -q "${VELERO_BUCKET_NAME}" /tmp/velero-values-rendered.yaml; then
    echo -e "${RED}ERROR: Failed to template VELERO_BUCKET_NAME in values.yaml${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Helm values rendered successfully${NC}"
echo ""

# Show diff of what will change
echo -e "${BLUE}Configuration changes:${NC}"
if [[ "$CURRENT_ROLE_ARN" != "$VELERO_ROLE_ARN" ]]; then
    echo -e "  ServiceAccount annotation:"
    echo -e "    ${RED}- ${CURRENT_ROLE_ARN}${NC}"
    echo -e "    ${GREEN}+ ${VELERO_ROLE_ARN}${NC}"
fi
if [[ "$CURRENT_BUCKET" != "$VELERO_BUCKET_NAME" ]]; then
    echo -e "  BackupStorageLocation bucket:"
    echo -e "    ${RED}- ${CURRENT_BUCKET}${NC}"
    echo -e "    ${GREEN}+ ${VELERO_BUCKET_NAME}${NC}"
fi
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}DRY RUN MODE: No changes will be applied${NC}"
    echo ""
    echo "Rendered values preview (first 50 lines):"
    head -50 /tmp/velero-values-rendered.yaml
    exit 0
fi

# Step 6: Apply Helm upgrade
echo -e "${YELLOW}[6/6] Applying Helm upgrade...${NC}"
echo -e "${YELLOW}This will update Velero with the correct IRSA configuration.${NC}"
echo -e "${YELLOW}Existing backups and schedules will NOT be affected.${NC}"
echo ""
read -p "Continue? (yes/no): " -r CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "${RED}Aborted by user${NC}"
    exit 1
fi

# Add Velero Helm repository
echo "Updating Helm repository..."
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts &> /dev/null || true
helm repo update &> /dev/null

# Apply Helm upgrade
echo "Applying Helm upgrade..."
helm upgrade velero vmware-tanzu/velero \
    --namespace "$VELERO_NAMESPACE" \
    --values /tmp/velero-values-rendered.yaml \
    --reuse-values=false \
    --wait \
    --timeout 5m

echo -e "${GREEN}✓ Helm upgrade completed${NC}"
echo ""

# Verify updated configuration
echo -e "${YELLOW}Verifying updated configuration...${NC}"
sleep 5  # Wait for changes to propagate

UPDATED_ROLE_ARN=$(kubectl get sa velero-server -n "$VELERO_NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
UPDATED_BUCKET=$(kubectl get backupstoragelocation default -n "$VELERO_NAMESPACE" -o jsonpath='{.spec.objectStorage.bucket}' 2>/dev/null || echo "")
UPDATED_BSL_STATUS=$(kubectl get backupstoragelocation default -n "$VELERO_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

echo -e "Updated configuration:"
echo -e "  IAM Role ARN: ${UPDATED_ROLE_ARN}"
echo -e "  S3 Bucket: ${UPDATED_BUCKET}"
echo -e "  BSL Status: ${UPDATED_BSL_STATUS}"
echo ""

# Validation
VALIDATION_PASSED=true

if [[ "$UPDATED_ROLE_ARN" != "$VELERO_ROLE_ARN" ]]; then
    echo -e "${RED}✗ IAM Role ARN validation failed${NC}"
    VALIDATION_PASSED=false
else
    echo -e "${GREEN}✓ IAM Role ARN: Correct${NC}"
fi

if [[ "$UPDATED_BUCKET" != "$VELERO_BUCKET_NAME" ]]; then
    echo -e "${RED}✗ S3 Bucket validation failed${NC}"
    VALIDATION_PASSED=false
else
    echo -e "${GREEN}✓ S3 Bucket: Correct${NC}"
fi

if [[ "$UPDATED_BSL_STATUS" != "Available" ]]; then
    echo -e "${YELLOW}⚠ BackupStorageLocation status: ${UPDATED_BSL_STATUS}${NC}"
    echo -e "${YELLOW}  Waiting for BSL to become Available (up to 60s)...${NC}"

    # Wait for BSL to become Available
    for i in {1..12}; do
        sleep 5
        UPDATED_BSL_STATUS=$(kubectl get backupstoragelocation default -n "$VELERO_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "$UPDATED_BSL_STATUS" == "Available" ]]; then
            echo -e "${GREEN}✓ BackupStorageLocation: Available${NC}"
            break
        fi
        if [[ $i -eq 12 ]]; then
            echo -e "${RED}✗ BackupStorageLocation validation failed (timeout)${NC}"
            echo -e "${YELLOW}  Current status: ${UPDATED_BSL_STATUS}${NC}"
            VALIDATION_PASSED=false
        fi
    done
else
    echo -e "${GREEN}✓ BackupStorageLocation: Available${NC}"
fi

echo ""

if [[ "$VALIDATION_PASSED" != "true" ]]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Update completed with validation errors${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check Velero logs: kubectl logs -n velero deployment/velero -f"
    echo "  2. Describe BSL: kubectl describe backupstoragelocation default -n velero"
    echo "  3. Verify IAM role: aws iam get-role --role-name k8s-platform-prod-velero-dr-role"
    echo "  4. Verify S3 bucket: aws s3 ls s3://${VELERO_BUCKET_NAME}/"
    exit 1
fi

# Test backup creation (optional)
echo -e "${YELLOW}Testing backup creation (optional)...${NC}"
read -p "Create a test backup to verify functionality? (yes/no): " -r TEST_CONFIRM

if [[ "$TEST_CONFIRM" == "yes" ]]; then
    if ! command -v velero &> /dev/null; then
        echo -e "${YELLOW}Velero CLI not found. Skipping test backup.${NC}"
    else
        TEST_BACKUP_NAME="test-post-update-$(date +%Y%m%d-%H%M%S)"
        echo "Creating test backup: ${TEST_BACKUP_NAME}"

        velero backup create "$TEST_BACKUP_NAME" \
            --include-namespaces staging-governance-test \
            --wait \
            --timeout 5m || true

        TEST_BACKUP_STATUS=$(velero backup get "$TEST_BACKUP_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

        if [[ "$TEST_BACKUP_STATUS" == "Completed" ]]; then
            echo -e "${GREEN}✓ Test backup created successfully${NC}"
        else
            echo -e "${YELLOW}⚠ Test backup status: ${TEST_BACKUP_STATUS}${NC}"
        fi
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AÇÃO-002 Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Summary:"
echo "  - IAM Role ARN: ✓ ${VELERO_ROLE_ARN}"
echo "  - S3 Bucket: ✓ ${VELERO_BUCKET_NAME}"
echo "  - BackupStorageLocation: ✓ Available"
echo "  - Deployment Method: Terraform + Helm"
echo ""
echo "Configuration drift has been resolved. Future 'helm upgrade' commands"
echo "will use the correct values from Terraform outputs via deploy-velero.sh."
echo ""
echo "Recommendations:"
echo "  1. Document Velero deployment method in runbook"
echo "  2. Add drift detection to CI/CD pipeline"
echo "  3. Use deploy-velero.sh script for all future Velero updates"
echo ""
