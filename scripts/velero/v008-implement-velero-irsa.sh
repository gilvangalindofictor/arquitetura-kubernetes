#!/usr/bin/env bash
# V-008: Velero IRSA Migration Implementation Script
# Purpose: Deploy Velero with IRSA (IAM Roles for Service Accounts)
# Eliminates hardcoded S3 credentials, uses AWS OIDC provider
#
# Prerequisites:
#   - AWS CLI configured with valid credentials
#   - kubectl configured for k8s-platform-prod cluster
#   - Terraform initialized in environments/staging/
#
# Usage:
#   ./v008-implement-velero-irsa.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="k8s-platform-prod"
VELERO_NAMESPACE="velero"
BUCKET_NAME="${CLUSTER_NAME}-velero-backups"
AWS_REGION="us-east-1"
TF_DIR="/home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}V-008: Velero IRSA Migration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Step 1: Verify prerequisites
echo -e "${YELLOW}[1/7] Verifying prerequisites...${NC}"

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
    echo -e "${YELLOW}Run: aws sso login --profile k8s-platform-prod${NC}"
    exit 1
fi

# Verify kubectl context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [[ ! "$CURRENT_CONTEXT" =~ $CLUSTER_NAME ]]; then
    echo -e "${RED}ERROR: kubectl not configured for cluster ${CLUSTER_NAME}${NC}"
    echo -e "${YELLOW}Run: aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo ""

# Step 2: Apply Terraform to create IAM Role + S3 Bucket
echo -e "${YELLOW}[2/7] Creating IAM Role and S3 Bucket via Terraform...${NC}"

cd "$TF_DIR"

# Source environment variables if available
if [ -f /tmp/v004-006-env.sh ]; then
    source /tmp/v004-006-env.sh
fi

# Terraform plan
terraform plan -target=module.velero_dr_staging -out=v008-velero-irsa.tfplan

echo -e "${YELLOW}Review the plan above. Continue? (yes/no)${NC}"
read -r CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "${RED}Aborted by user${NC}"
    exit 1
fi

# Terraform apply
terraform apply v008-velero-irsa.tfplan

# Get outputs
VELERO_ROLE_ARN=$(terraform output -raw velero_role_arn)
BUCKET_NAME=$(terraform output -raw velero_bucket_name)

echo -e "${GREEN}✓ IAM Role created: ${VELERO_ROLE_ARN}${NC}"
echo -e "${GREEN}✓ S3 Bucket created: ${BUCKET_NAME}${NC}"
echo ""

# Step 3: Create Velero namespace
echo -e "${YELLOW}[3/7] Creating Velero namespace...${NC}"

kubectl create namespace "$VELERO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ Namespace ${VELERO_NAMESPACE} ready${NC}"
echo ""

# Step 4: Install Velero via Helm
echo -e "${YELLOW}[4/7] Installing Velero via Helm...${NC}"

# Add Velero Helm repository
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Create Helm values with IRSA configuration
cat > /tmp/velero-values.yaml <<EOF
# Velero Helm Chart Values (V-008 IRSA)
# No static credentials - uses IRSA

credentials:
  useSecret: false

serviceAccount:
  server:
    create: true
    name: velero-server
    annotations:
      eks.amazonaws.com/role-arn: ${VELERO_ROLE_ARN}

configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: ${BUCKET_NAME}
      config:
        region: ${AWS_REGION}
        serverSideEncryption: AES256
      accessMode: ReadWrite
      default: true

  volumeSnapshotLocation:
    - name: default
      provider: aws
      config:
        region: ${AWS_REGION}

  backupRetentionPeriod: 720h  # 30 days
  logLevel: info
  features: EnableCSI

initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.11.0
    imagePullPolicy: IfNotPresent
    volumeMounts:
      - mountPath: /target
        name: plugins

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

nodeSelector:
  workload: system

tolerations:
  - key: workload
    operator: Equal
    value: system
    effect: NoSchedule

metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    additionalLabels:
      release: kube-prometheus-stack

cleanUpCRDs: false
schedules: {}

deployNodeAgent: true
nodeAgent:
  podVolumePath: /var/lib/kubelet/pods
  privileged: false
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  tolerations:
    - operator: Exists

upgradeCRDs: true

kubectl:
  image:
    repository: docker.io/bitnami/kubectl
    tag: 1.34.0
EOF

# Install Velero
helm upgrade --install velero vmware-tanzu/velero \
  --namespace "$VELERO_NAMESPACE" \
  --values /tmp/velero-values.yaml \
  --version 8.1.0 \
  --wait \
  --timeout 10m

echo -e "${GREEN}✓ Velero installed${NC}"
echo ""

# Step 5: Verify ServiceAccount annotation
echo -e "${YELLOW}[5/7] Verifying ServiceAccount IRSA annotation...${NC}"

SA_ANNOTATION=$(kubectl get sa velero-server -n "$VELERO_NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')

if [[ "$SA_ANNOTATION" == "$VELERO_ROLE_ARN" ]]; then
    echo -e "${GREEN}✓ ServiceAccount annotation correct: ${SA_ANNOTATION}${NC}"
else
    echo -e "${RED}ERROR: ServiceAccount annotation mismatch${NC}"
    echo -e "  Expected: ${VELERO_ROLE_ARN}"
    echo -e "  Got: ${SA_ANNOTATION}"
    exit 1
fi

echo ""

# Step 6: Verify IRSA assume role
echo -e "${YELLOW}[6/7] Verifying IRSA assume role...${NC}"

sleep 10  # Wait for pod to be fully ready

VELERO_POD=$(kubectl get pods -n "$VELERO_NAMESPACE" -l app.kubernetes.io/name=velero -o jsonpath='{.items[0].metadata.name}')

if [ -z "$VELERO_POD" ]; then
    echo -e "${RED}ERROR: Velero pod not found${NC}"
    exit 1
fi

echo "Testing AWS STS assume role from Velero pod..."
ASSUME_ROLE_OUTPUT=$(kubectl exec -n "$VELERO_NAMESPACE" "$VELERO_POD" -- aws sts get-caller-identity 2>&1 || true)

if echo "$ASSUME_ROLE_OUTPUT" | grep -q "assumed-role"; then
    echo -e "${GREEN}✓ IRSA assume role successful${NC}"
    echo "$ASSUME_ROLE_OUTPUT"
else
    echo -e "${RED}ERROR: IRSA assume role failed${NC}"
    echo "$ASSUME_ROLE_OUTPUT"
    exit 1
fi

echo ""

# Step 7: Create test backup
echo -e "${YELLOW}[7/7] Creating test backup...${NC}"

# Install velero CLI if not present
if ! command -v velero &> /dev/null; then
    echo "Installing Velero CLI..."
    VELERO_VERSION="v1.15.1"
    wget "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz" -O /tmp/velero.tar.gz
    tar -xzf /tmp/velero.tar.gz -C /tmp
    sudo mv "/tmp/velero-${VELERO_VERSION}-linux-amd64/velero" /usr/local/bin/
    rm -rf /tmp/velero*
fi

# Create test backup
velero backup create test-irsa-$(date +%Y%m%d-%H%M%S) \
  --include-namespaces kube-system \
  --wait

# Verify backup status
BACKUP_STATUS=$(velero backup get --selector='velero.io/test=true' -o json | jq -r '.items[0].status.phase')

if [[ "$BACKUP_STATUS" == "Completed" ]]; then
    echo -e "${GREEN}✓ Test backup completed successfully${NC}"
else
    echo -e "${RED}WARNING: Test backup status: ${BACKUP_STATUS}${NC}"
fi

# List backups
echo ""
echo "Recent backups:"
velero backup get | head -10

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}V-008 Implementation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Summary:"
echo "  - IAM Role: ${VELERO_ROLE_ARN}"
echo "  - S3 Bucket: ${BUCKET_NAME}"
echo "  - Namespace: ${VELERO_NAMESPACE}"
echo "  - IRSA: ✓ Enabled"
echo "  - Credentials: None (IRSA-based)"
echo ""
echo "Next steps:"
echo "  1. Configure backup schedules (see kubectl-manifests/velero/backup-schedules.yaml)"
echo "  2. Test restore functionality"
echo "  3. Monitor backups: velero backup get"
echo "  4. Update demands-backlog.md: V-008 → ✅ COMPLETO"
echo ""
