#!/bin/bash

# ==============================================================================
# Validation Script for Observability Platform
#
# This script checks if all the necessary tools are installed and if the
# AWS credentials are configured correctly. It also provides a dry-run
# for Terraform and Helm to catch potential configuration errors before
# applying them to the cluster.
# ==============================================================================

# --- Colors for output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---
check_command() {
    command -v "$1" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✔ $1 is installed.${NC}"
        return 0
    else
        echo -e "${RED}✖ $1 is not installed. Please install it before proceeding.${NC}"
        return 1
    fi
}

# --- 1. Check Prerequisites ---
echo -e "${YELLOW}--- Checking Prerequisites ---${NC}"
all_checks_passed=true

check_command "aws" || all_checks_passed=false
check_command "terraform" || all_checks_passed=false
check_command "kubectl" || all_checks_passed=false
check_command "helm" || all_checks_passed=false

if [ "$all_checks_passed" = false ]; then
    echo -e "\n${RED}Some prerequisites are missing. Please install them and run the script again.${NC}"
    exit 1
fi
echo -e "${GREEN}All prerequisites are installed.${NC}\n"


# --- 2. Check AWS Configuration ---
echo -e "${YELLOW}--- Checking AWS Configuration ---${NC}"
if aws sts get-caller-identity > /dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}✔ AWS credentials are valid.${NC}"
    echo -e "AWS Account ID: ${GREEN}${ACCOUNT_ID}${NC}"
else
    echo -e "${RED}✖ AWS credentials are not configured or are invalid.${NC}"
    echo -e "Please run 'aws configure' or set up your environment variables."
    exit 1
fi
echo ""


# --- 3. Validate Terraform ---
echo -e "${YELLOW}--- Validating Terraform Configuration ---${NC}"
cd ../terraform

# Replace placeholders in variables.tf if they exist
# This is a simple check; a more robust solution would use sed or similar
if grep -q "YOUR_ACCOUNT_ID" variables.tf; then
    echo -e "${YELLOW}Placeholder 'YOUR_ACCOUNT_ID' found in variables.tf. This should be replaced before applying.${NC}"
fi

terraform init -reconfigure > /dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}✖ Terraform init failed.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Terraform init successful.${NC}"

terraform validate
if [ $? -ne 0 ]; then
    echo -e "${RED}✖ Terraform validation failed.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Terraform configuration is valid.${NC}"

echo -e "\n${YELLOW}Running Terraform Plan (dry-run)...${NC}"
terraform plan
echo -e "${GREEN}✔ Terraform plan completed. Review the output above to ensure the changes are expected.${NC}"
cd ../validation
echo ""


# --- 4. Validate Helm ---
echo -e "${YELLOW}--- Validating Helm Charts ---${NC}"
cd ../helm

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts > /dev/null 2>&1
helm repo add grafana https://grafana.github.io/helm-charts > /dev/null 2>&1
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts > /dev/null 2>&1
helm repo update > /dev/null
echo -e "${GREEN}✔ Helm repositories updated.${NC}"

echo -e "\n${YELLOW}Performing Helm dry-run for all charts...${NC}"
helm lint ./kube-prometheus-stack
helm template kube-prometheus-stack ./kube-prometheus-stack --dry-run > /dev/null
if [ $? -ne 0 ]; then echo -e "${RED}✖ Dry-run failed for kube-prometheus-stack.${NC}"; else echo -e "${GREEN}✔ Dry-run successful for kube-prometheus-stack.${NC}"; fi

helm lint ./opentelemetry-collector
helm template opentelemetry-collector ./opentelemetry-collector --dry-run > /dev/null
if [ $? -ne 0 ]; then echo -e "${RED}✖ Dry-run failed for opentelemetry-collector.${NC}"; else echo -e "${GREEN}✔ Dry-run successful for opentelemetry-collector.${NC}"; fi

helm lint ./loki
helm template loki ./loki --dry-run > /dev/null
if [ $? -ne 0 ]; then echo -e "${RED}✖ Dry-run failed for loki.${NC}"; else echo -e "${GREEN}✔ Dry-run successful for loki.${NC}"; fi

helm lint ./tempo
helm template tempo ./tempo --dry-run > /dev/null
if [ $? -ne 0 ]; then echo -e "${RED}✖ Dry-run failed for tempo.${NC}"; else echo -e "${GREEN}✔ Dry-run successful for tempo.${NC}"; fi

cd ../validation
echo ""

# --- Completion ---
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}      Validation Script Completed!      ${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "If all checks passed, you are ready to deploy the infrastructure."
echo -e "1. Run 'terraform apply' in the 'infra/terraform' directory."
echo -e "2. Configure kubectl to point to your new EKS cluster."
echo -e "3. Run 'helm install' for each chart in the 'infra/helm' directory."
