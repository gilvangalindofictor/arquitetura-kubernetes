#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Validation Script - Marco 2 Fase 4 (Logging: Loki + Fluent Bit)
# -----------------------------------------------------------------------------

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${GREEN}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------

print_header "Pre-flight Checks"

if ! command_exists aws; then
    print_error "AWS CLI not installed"
    exit 1
fi
print_success "AWS CLI installed"

if ! command_exists kubectl; then
    print_error "kubectl not installed"
    exit 1
fi
print_success "kubectl installed"

if ! command_exists terraform; then
    print_error "Terraform not installed"
    exit 1
fi
print_success "Terraform installed"

# Check AWS credentials
print_header "AWS Credentials"
if aws sts get-caller-identity >/dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS credentials valid (Account: $ACCOUNT_ID)"
else
    print_error "AWS credentials not configured or invalid"
    echo "Run: export AWS_PROFILE=k8s-platform-prod"
    exit 1
fi

# Check kubectl context
print_header "Kubernetes Context"
if kubectl cluster-info >/dev/null 2>&1; then
    CURRENT_CONTEXT=$(kubectl config current-context)
    print_success "kubectl connected (Context: $CURRENT_CONTEXT)"
else
    print_error "kubectl not configured or cluster unreachable"
    echo "Run: aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod --profile k8s-platform-prod"
    exit 1
fi

# -----------------------------------------------------------------------------
# S3 Bucket Validation
# -----------------------------------------------------------------------------

print_header "S3 Bucket Validation"

S3_BUCKET="k8s-platform-loki-${ACCOUNT_ID}"

if aws s3 ls "s3://${S3_BUCKET}" >/dev/null 2>&1; then
    print_success "S3 bucket exists: ${S3_BUCKET}"

    # Check lifecycle policy
    if aws s3api get-bucket-lifecycle-configuration --bucket "${S3_BUCKET}" >/dev/null 2>&1; then
        EXPIRATION_DAYS=$(aws s3api get-bucket-lifecycle-configuration --bucket "${S3_BUCKET}" --query 'Rules[0].Expiration.Days' --output text)
        print_success "Lifecycle policy configured (${EXPIRATION_DAYS} days retention)"
    else
        print_warning "Lifecycle policy not found"
    fi

    # Check encryption
    if aws s3api get-bucket-encryption --bucket "${S3_BUCKET}" >/dev/null 2>&1; then
        ENCRYPTION=$(aws s3api get-bucket-encryption --bucket "${S3_BUCKET}" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)
        print_success "Encryption enabled (${ENCRYPTION})"
    else
        print_warning "Encryption not configured"
    fi
else
    print_warning "S3 bucket not found (will be created by Terraform)"
fi

# -----------------------------------------------------------------------------
# IAM Role Validation
# -----------------------------------------------------------------------------

print_header "IAM Role Validation"

IAM_ROLE="LokiS3Role-k8s-platform-prod"

if aws iam get-role --role-name "${IAM_ROLE}" >/dev/null 2>&1; then
    ROLE_ARN=$(aws iam get-role --role-name "${IAM_ROLE}" --query 'Role.Arn' --output text)
    print_success "IAM role exists: ${ROLE_ARN}"

    # Check attached policies
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "${IAM_ROLE}" --query 'AttachedPolicies[*].PolicyName' --output text)
    if [[ -n "$ATTACHED_POLICIES" ]]; then
        print_success "Attached policies: ${ATTACHED_POLICIES}"
    else
        print_warning "No policies attached to role"
    fi
else
    print_warning "IAM role not found (will be created by Terraform)"
fi

# -----------------------------------------------------------------------------
# Loki Pods Validation
# -----------------------------------------------------------------------------

print_header "Loki Pods Validation"

if kubectl get namespace monitoring >/dev/null 2>&1; then
    print_success "Namespace 'monitoring' exists"

    # Check Loki pods
    LOKI_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=loki --no-headers 2>/dev/null | wc -l)

    if [[ $LOKI_PODS -gt 0 ]]; then
        print_success "Found ${LOKI_PODS} Loki pods"

        # Check pod status
        kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

        # Count Running pods
        RUNNING_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=loki -o json | jq -r '.items[] | select(.status.phase=="Running") | .metadata.name' | wc -l)
        EXPECTED_PODS=8  # 2 read + 2 write + 2 backend + 2 gateway

        if [[ $RUNNING_PODS -eq $EXPECTED_PODS ]]; then
            print_success "All ${EXPECTED_PODS} Loki pods Running"
        else
            print_warning "${RUNNING_PODS}/${EXPECTED_PODS} pods Running"
        fi
    else
        print_warning "No Loki pods found (not deployed yet)"
    fi
else
    print_warning "Namespace 'monitoring' not found"
fi

# -----------------------------------------------------------------------------
# Fluent Bit DaemonSet Validation
# -----------------------------------------------------------------------------

print_header "Fluent Bit DaemonSet Validation"

if kubectl get namespace monitoring >/dev/null 2>&1; then
    FLUENT_BIT_PODS=$(kubectl get daemonset -n monitoring fluent-bit --no-headers 2>/dev/null | awk '{print $2}')

    if [[ -n "$FLUENT_BIT_PODS" ]]; then
        DESIRED=$(echo $FLUENT_BIT_PODS | cut -d'/' -f2)
        READY=$(echo $FLUENT_BIT_PODS | cut -d'/' -f1)

        if [[ $READY -eq $DESIRED ]]; then
            print_success "Fluent Bit DaemonSet: ${READY}/${DESIRED} pods ready"
        else
            print_warning "Fluent Bit DaemonSet: ${READY}/${DESIRED} pods ready"
        fi

        kubectl get daemonset -n monitoring fluent-bit
    else
        print_warning "Fluent Bit DaemonSet not found (not deployed yet)"
    fi
fi

# -----------------------------------------------------------------------------
# Loki API Validation
# -----------------------------------------------------------------------------

print_header "Loki API Validation"

if kubectl get svc -n monitoring loki-gateway >/dev/null 2>&1; then
    print_success "Loki Gateway service exists"

    # Test Loki API (labels endpoint)
    print_header "Testing Loki API (port-forward required)"
    echo "To test manually, run:"
    echo "  kubectl port-forward -n monitoring svc/loki-gateway 3100:3100"
    echo "  curl -s http://localhost:3100/loki/api/v1/labels"
else
    print_warning "Loki Gateway service not found"
fi

# -----------------------------------------------------------------------------
# Grafana Datasource Validation
# -----------------------------------------------------------------------------

print_header "Grafana Datasource Validation"

if kubectl get deployment -n monitoring kube-prometheus-stack-grafana >/dev/null 2>&1; then
    print_success "Grafana deployment exists"
    echo "To validate Loki datasource:"
    echo "  1. kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    echo "  2. Access http://localhost:3000"
    echo "  3. Go to Configuration > Data sources"
    echo "  4. Check 'Loki' datasource"
else
    print_warning "Grafana not found"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

print_header "Validation Summary"

echo "
Next Steps:
1. If Terraform not applied yet:
   cd platform-provisioning/aws/kubernetes/terraform/envs/marco2
   export AWS_PROFILE=k8s-platform-prod
   terraform plan
   terraform apply

2. Wait for all pods to be Running (~5 minutes)

3. Test log ingestion:
   kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=50

4. Test log query in Grafana:
   - Port-forward: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
   - Access: http://localhost:3000
   - Explore > Loki > Query: {namespace=\"monitoring\"}

5. Validate log correlation:
   - Open a trace in Tempo
   - Click 'Logs for this span' button
   - Should open Loki with filtered logs

For more details, see:
- ADR-005: docs/adr/adr-005-logging-strategy.md
- Deploy Checklist: DEPLOY-CHECKLIST.md
"
