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


# --- 3. Validate Terraform (Platform Services) ---
echo -e "${YELLOW}--- Validating Terraform Configuration (Platform Services) ---${NC}"

# Navegar para o diretório correto (Marco 2 - Platform Services)
TERRAFORM_DIR="../../../../platform-provisioning/aws/kubernetes/terraform/envs/marco2"
cd "$TERRAFORM_DIR" || {
    echo -e "${RED}✖ Failed to navigate to Terraform directory: $TERRAFORM_DIR${NC}"
    exit 1
}

# Validar se terraform.tfvars existe
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}⚠ terraform.tfvars not found. Using default values from variables.tf${NC}"
fi

# Verificar se credenciais AWS estão configuradas
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}✖ AWS credentials not configured. Platform Services require AWS access.${NC}"
    echo -e "${YELLOW}Run: aws sso login --profile k8s-platform-prod${NC}"
    exit 1
fi

# Terraform init
echo -e "${YELLOW}Running terraform init...${NC}"
terraform init -reconfigure > /dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}✖ Terraform init failed.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Terraform init successful.${NC}"

# Terraform validate
terraform validate
if [ $? -ne 0 ]; then
    echo -e "${RED}✖ Terraform validation failed.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Terraform configuration is valid.${NC}"

# Terraform fmt -check (validar formatação)
echo -e "${YELLOW}Checking Terraform code formatting...${NC}"
terraform fmt -check -recursive > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✔ All Terraform files are properly formatted.${NC}"
else
    echo -e "${YELLOW}⚠ Some Terraform files need formatting. Run: terraform fmt -recursive${NC}"
fi

# Terraform plan (dry-run)
echo -e "\n${YELLOW}Running Terraform Plan (dry-run)...${NC}"
terraform plan -compact-warnings
if [ $? -ne 0 ]; then
    echo -e "${RED}✖ Terraform plan failed.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Terraform plan completed. Review the output above to ensure the changes are expected.${NC}"

# Voltar para o diretório de validação
cd - > /dev/null
echo ""


# --- 4. Validate Helm (Application Deployments) ---
echo -e "${YELLOW}--- Validating Helm Charts (Applications) ---${NC}"

# Nota: Platform Services (Prometheus, Grafana, Cert-Manager, ALB Controller) são gerenciados via Terraform
# Esta seção valida apenas Application Deployments que usam Helm diretamente

echo -e "${YELLOW}Updating Helm repositories...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts > /dev/null 2>&1
helm repo add grafana https://grafana.github.io/helm-charts > /dev/null 2>&1
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts > /dev/null 2>&1
helm repo add gitlab https://charts.gitlab.io > /dev/null 2>&1
helm repo add bitnami https://charts.bitnami.com/bitnami > /dev/null 2>&1
helm repo update > /dev/null 2>&1
echo -e "${GREEN}✔ Helm repositories updated.${NC}"

# Verificar se existem charts de aplicações para validar
if [ -d "../helm" ]; then
    cd ../helm || exit 1

    echo -e "\n${YELLOW}Performing Helm dry-run for application charts...${NC}"

    # Validar apenas charts que existem (aplicações futuras)
    # Platform Services (kube-prometheus-stack, etc.) NÃO são validados aqui
    # pois são gerenciados via Terraform

    if [ -d "./opentelemetry-collector" ]; then
        helm lint ./opentelemetry-collector
        helm template opentelemetry-collector ./opentelemetry-collector --dry-run > /dev/null
        if [ $? -ne 0 ]; then
            echo -e "${RED}✖ Dry-run failed for opentelemetry-collector.${NC}"
        else
            echo -e "${GREEN}✔ Dry-run successful for opentelemetry-collector.${NC}"
        fi
    fi

    if [ -d "./loki" ]; then
        helm lint ./loki
        helm template loki ./loki --dry-run > /dev/null
        if [ $? -ne 0 ]; then
            echo -e "${RED}✖ Dry-run failed for loki.${NC}"
        else
            echo -e "${GREEN}✔ Dry-run successful for loki.${NC}"
        fi
    fi

    if [ -d "./tempo" ]; then
        helm lint ./tempo
        helm template tempo ./tempo --dry-run > /dev/null
        if [ $? -ne 0 ]; then
            echo -e "${RED}✖ Dry-run failed for tempo.${NC}"
        else
            echo -e "${GREEN}✔ Dry-run successful for tempo.${NC}"
        fi
    fi

    cd ../validation || exit 1
else
    echo -e "${YELLOW}⚠ No application Helm charts found in ../helm directory.${NC}"
    echo -e "${YELLOW}Platform Services are managed via Terraform (validated in step 3).${NC}"
fi
echo ""

# --- Completion ---
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}      Validation Script Completed!      ${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "If all checks passed, you are ready to deploy the infrastructure."
echo -e ""
echo -e "${YELLOW}Deployment Steps:${NC}"
echo -e "1. Platform Services (Terraform):"
echo -e "   cd ../../../../platform-provisioning/aws/kubernetes/terraform/envs/marco2"
echo -e "   terraform apply"
echo -e ""
echo -e "2. Configure kubectl:"
echo -e "   aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod --profile k8s-platform-prod"
echo -e ""
echo -e "3. Verify Platform Services:"
echo -e "   kubectl get pods -n kube-system"
echo -e "   kubectl get pods -n cert-manager"
echo -e "   kubectl get pods -n monitoring"
echo -e ""
echo -e "4. Application Deployments (Helm - when ready):"
echo -e "   helm install <app-name> <chart> -f values-prod.yaml"
echo -e ""
echo -e "${YELLOW}Note:${NC} Platform Services (ALB Controller, Cert-Manager, Prometheus/Grafana) are managed via Terraform."
echo -e "      Application deployments (GitLab, Redis, RabbitMQ) use Helm directly."
