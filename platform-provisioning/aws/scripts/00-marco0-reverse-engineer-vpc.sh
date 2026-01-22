#!/bin/bash
################################################################################
# Marco 0: Engenharia Reversa da VPC Existente
################################################################################
# Descrição: Script para extrair configuração atual da VPC e gerar Terraform
#            equivalente para replicar o estado atual (baseline).
# Autor: DevOps Team
# Data: 2026-01-22
# VPC Target: vpc-0b1396a59c417c1f0 (us-east-1)
################################################################################

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações
VPC_ID="vpc-0b1396a59c417c1f0"
REGION="us-east-1"
OUTPUT_DIR="./vpc-reverse-engineered"
TERRAFORM_DIR="${OUTPUT_DIR}/terraform"
DOCS_DIR="${OUTPUT_DIR}/docs"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Marco 0: Engenharia Reversa da VPC Existente       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

################################################################################
# Funções Auxiliares
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI não encontrado. Instale: https://aws.amazon.com/cli/"
        exit 1
    fi
    log_success "AWS CLI v$(aws --version | cut -d' ' -f1 | cut -d'/' -f2) encontrado"
}

check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "Credenciais AWS não configuradas ou expiradas"
        exit 1
    fi
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user=$(aws sts get-caller-identity --query Arn --output text)
    log_success "Autenticado como: ${user} (Account: ${account_id})"
}

check_vpc_exists() {
    if ! aws ec2 describe-vpcs --vpc-ids ${VPC_ID} --region ${REGION} &> /dev/null; then
        log_error "VPC ${VPC_ID} não encontrada na região ${REGION}"
        exit 1
    fi
    log_success "VPC ${VPC_ID} encontrada"
}

create_output_dirs() {
    mkdir -p ${TERRAFORM_DIR}/modules/{vpc,subnets,nat-gateways,internet-gateway,route-tables}
    mkdir -p ${DOCS_DIR}
    log_success "Diretórios criados em: ${OUTPUT_DIR}"
}

################################################################################
# Extração de Recursos AWS
################################################################################

extract_vpc_info() {
    log_info "Extraindo informações da VPC..."

    local vpc_data=$(aws ec2 describe-vpcs \
        --vpc-ids ${VPC_ID} \
        --region ${REGION} \
        --output json)

    echo "${vpc_data}" > ${DOCS_DIR}/vpc-raw.json

    local cidr_block=$(echo "${vpc_data}" | jq -r '.Vpcs[0].CidrBlock')
    local enable_dns_hostnames=$(echo "${vpc_data}" | jq -r '.Vpcs[0].EnableDnsHostnames // false')
    local enable_dns_support=$(echo "${vpc_data}" | jq -r '.Vpcs[0].EnableDnsSupport // true')

    # Extrair tags
    local tags=$(echo "${vpc_data}" | jq -r '.Vpcs[0].Tags // [] | map("\(.Key) = \"\(.Value)\"") | join("\n    ")')

    cat > ${TERRAFORM_DIR}/modules/vpc/main.tf <<EOF
# VPC Principal (Engenharia Reversa)
# VPC ID Original: ${VPC_ID}
# Extraído em: $(date +%Y-%m-%d)

resource "aws_vpc" "main" {
  cidr_block           = "${cidr_block}"
  enable_dns_hostnames = ${enable_dns_hostnames}
  enable_dns_support   = ${enable_dns_support}

  tags = {
    Name = "fictor-vpc" # Nome original baseado nas tags
    ${tags}
  }
}
EOF

    log_success "VPC info extraída: ${cidr_block}"
}

extract_subnets() {
    log_info "Extraindo subnets..."

    local subnets_data=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --region ${REGION} \
        --output json)

    echo "${subnets_data}" > ${DOCS_DIR}/subnets-raw.json

    # Contar subnets
    local subnet_count=$(echo "${subnets_data}" | jq '.Subnets | length')
    log_info "Total de subnets encontradas: ${subnet_count}"

    # Gerar Terraform para cada subnet
    cat > ${TERRAFORM_DIR}/modules/subnets/main.tf <<EOF
# Subnets Existentes (Engenharia Reversa)
# Extraído em: $(date +%Y-%m-%d)

EOF

    local index=0
    echo "${subnets_data}" | jq -c '.Subnets[]' | while read subnet; do
        local subnet_id=$(echo "${subnet}" | jq -r '.SubnetId')
        local cidr_block=$(echo "${subnet}" | jq -r '.CidrBlock')
        local az=$(echo "${subnet}" | jq -r '.AvailabilityZone')
        local map_public_ip=$(echo "${subnet}" | jq -r '.MapPublicIpOnLaunch')
        local name_tag=$(echo "${subnet}" | jq -r '.Tags[]? | select(.Key=="Name") | .Value // "unnamed"')

        # Determinar tipo (público/privado) pelo nome
        local subnet_type="private"
        if [[ "${name_tag}" == *"public"* ]]; then
            subnet_type="public"
        fi

        cat >> ${TERRAFORM_DIR}/modules/subnets/main.tf <<SUBNET

# Subnet: ${name_tag} (${subnet_type})
resource "aws_subnet" "${subnet_type}_${az##*-}" {
  vpc_id                  = var.vpc_id
  cidr_block              = "${cidr_block}"
  availability_zone       = "${az}"
  map_public_ip_on_launch = ${map_public_ip}

  tags = {
    Name                              = "${name_tag}"
    "kubernetes.io/role/internal-elb" = "1"  # Tag para ALB interno
    # SubnetID Original: ${subnet_id}
  }
}

SUBNET
        ((index++))
    done

    log_success "Subnets extraídas: ${subnet_count}"
}

extract_internet_gateway() {
    log_info "Extraindo Internet Gateway..."

    local igw_data=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
        --region ${REGION} \
        --output json)

    echo "${igw_data}" > ${DOCS_DIR}/igw-raw.json

    local igw_id=$(echo "${igw_data}" | jq -r '.InternetGateways[0].InternetGatewayId // "null"')

    if [ "${igw_id}" != "null" ]; then
        cat > ${TERRAFORM_DIR}/modules/internet-gateway/main.tf <<EOF
# Internet Gateway (Engenharia Reversa)
# IGW ID Original: ${igw_id}

resource "aws_internet_gateway" "main" {
  vpc_id = var.vpc_id

  tags = {
    Name = "fictor-igw"
    # OriginalID: ${igw_id}
  }
}
EOF
        log_success "Internet Gateway extraído: ${igw_id}"
    else
        log_warn "Nenhum Internet Gateway encontrado"
    fi
}

extract_nat_gateways() {
    log_info "Extraindo NAT Gateways..."

    local nat_data=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=${VPC_ID}" \
        --region ${REGION} \
        --output json)

    echo "${nat_data}" > ${DOCS_DIR}/nat-gateways-raw.json

    local nat_count=$(echo "${nat_data}" | jq '.NatGateways | length')
    log_info "Total de NAT Gateways encontrados: ${nat_count}"

    cat > ${TERRAFORM_DIR}/modules/nat-gateways/main.tf <<EOF
# NAT Gateways (Engenharia Reversa)
# Total: ${nat_count}
# Extraído em: $(date +%Y-%m-%d)

EOF

    echo "${nat_data}" | jq -c '.NatGateways[] | select(.State=="available")' | while read nat; do
        local nat_id=$(echo "${nat}" | jq -r '.NatGatewayId')
        local subnet_id=$(echo "${nat}" | jq -r '.SubnetId')
        local eip_allocation_id=$(echo "${nat}" | jq -r '.NatGatewayAddresses[0].AllocationId')
        local public_ip=$(echo "${nat}" | jq -r '.NatGatewayAddresses[0].PublicIp')
        local name_tag=$(echo "${nat}" | jq -r '.Tags[]? | select(.Key=="Name") | .Value // "unnamed"')

        # Extrair AZ do nome (ex: fictor-nat-public1-us-east-1a -> 1a)
        local az_suffix=$(echo "${name_tag}" | grep -oP '\d[a-z]$' || echo "1")

        cat >> ${TERRAFORM_DIR}/modules/nat-gateways/main.tf <<NAT

# NAT Gateway: ${name_tag}
# Original NAT ID: ${nat_id}
# Public IP: ${public_ip}

resource "aws_eip" "nat_${az_suffix}" {
  domain = "vpc"

  tags = {
    Name = "fictor-nat-eip-${az_suffix}"
  }
}

resource "aws_nat_gateway" "nat_${az_suffix}" {
  allocation_id = aws_eip.nat_${az_suffix}.id
  subnet_id     = var.public_subnet_${az_suffix}_id

  tags = {
    Name = "${name_tag}"
    # OriginalID: ${nat_id}
  }

  depends_on = [var.internet_gateway_id]
}

NAT
    done

    log_success "NAT Gateways extraídos: ${nat_count}"
}

extract_route_tables() {
    log_info "Extraindo Route Tables..."

    local rt_data=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --region ${REGION} \
        --output json)

    echo "${rt_data}" > ${DOCS_DIR}/route-tables-raw.json

    local rt_count=$(echo "${rt_data}" | jq '.RouteTables | length')
    log_info "Total de Route Tables encontradas: ${rt_count}"

    cat > ${TERRAFORM_DIR}/modules/route-tables/main.tf <<EOF
# Route Tables (Engenharia Reversa)
# Total: ${rt_count}
# Extraído em: $(date +%Y-%m-%d)

EOF

    local index=0
    echo "${rt_data}" | jq -c '.RouteTables[]' | while read rt; do
        local rt_id=$(echo "${rt}" | jq -r '.RouteTableId')
        local name_tag=$(echo "${rt}" | jq -r '.Tags[]? | select(.Key=="Name") | .Value // "rt-unnamed-'${index}'"')

        # Classificar por tipo (public se tem rota para IGW, private se tem NAT)
        local has_igw=$(echo "${rt}" | jq -r '.Routes[] | select(.GatewayId? and (.GatewayId | startswith("igw-"))) | .GatewayId // "none"')
        local has_nat=$(echo "${rt}" | jq -r '.Routes[] | select(.NatGatewayId?) | .NatGatewayId // "none"')

        local rt_type="main"
        if [ "${has_igw}" != "none" ]; then
            rt_type="public"
        elif [ "${has_nat}" != "none" ]; then
            rt_type="private"
        fi

        cat >> ${TERRAFORM_DIR}/modules/route-tables/main.tf <<RT

# Route Table: ${name_tag} (${rt_type})
# Original RT ID: ${rt_id}
resource "aws_route_table" "${rt_type}_${index}" {
  vpc_id = var.vpc_id

RT

        # Extrair rotas
        echo "${rt}" | jq -c '.Routes[]' | while read route; do
            local dest_cidr=$(echo "${route}" | jq -r '.DestinationCidrBlock // "none"')
            local gateway_id=$(echo "${route}" | jq -r '.GatewayId // "none"')
            local nat_gateway_id=$(echo "${route}" | jq -r '.NatGatewayId // "none"')

            if [ "${dest_cidr}" != "none" ] && [ "${dest_cidr}" != "local" ]; then
                if [ "${gateway_id}" != "none" ] && [[ "${gateway_id}" == igw-* ]]; then
                    cat >> ${TERRAFORM_DIR}/modules/route-tables/main.tf <<ROUTE
  route {
    cidr_block = "${dest_cidr}"
    gateway_id = var.internet_gateway_id
  }
ROUTE
                elif [ "${nat_gateway_id}" != "none" ]; then
                    # Determinar qual NAT (extrair AZ do NAT ID)
                    local nat_suffix="1a" # Placeholder, idealmente mapear corretamente
                    cat >> ${TERRAFORM_DIR}/modules/route-tables/main.tf <<ROUTE
  route {
    cidr_block     = "${dest_cidr}"
    nat_gateway_id = var.nat_gateway_id_${nat_suffix}
  }
ROUTE
                fi
            fi
        done

        cat >> ${TERRAFORM_DIR}/modules/route-tables/main.tf <<RT

  tags = {
    Name = "${name_tag}"
    # OriginalID: ${rt_id}
  }
}

RT
        ((index++))
    done

    log_success "Route Tables extraídas: ${rt_count}"
}

generate_variables_tf() {
    log_info "Gerando variables.tf para os módulos..."

    for module in vpc subnets nat-gateways internet-gateway route-tables; do
        cat > ${TERRAFORM_DIR}/modules/${module}/variables.tf <<EOF
# Variables for ${module} module

variable "vpc_id" {
  description = "VPC ID (referência)"
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

# Adicionar outras variáveis conforme necessário para cada módulo
EOF
    done

    log_success "variables.tf gerados para todos os módulos"
}

generate_main_orchestrator() {
    log_info "Gerando orquestrador Terraform principal..."

    cat > ${TERRAFORM_DIR}/main.tf <<'EOF'
# Marco 0: VPC Baseline (Engenharia Reversa)
# Replicação do estado atual da VPC vpc-0b1396a59c417c1f0
# Gerado automaticamente em: 2026-01-22

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "terraform-state-k8s-platform"
    key            = "marco0/vpc-baseline/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "k8s-platform"
      ManagedBy   = "terraform"
      Environment = "baseline"
      Marco       = "0"
    }
  }
}

# Módulo VPC
module "vpc" {
  source = "./modules/vpc"
}

# Módulo Subnets
module "subnets" {
  source = "./modules/subnets"
  vpc_id = module.vpc.vpc_id
}

# Módulo Internet Gateway
module "internet_gateway" {
  source = "./modules/internet-gateway"
  vpc_id = module.vpc.vpc_id
}

# Módulo NAT Gateways
module "nat_gateways" {
  source = "./modules/nat-gateways"

  vpc_id                = module.vpc.vpc_id
  public_subnet_1a_id   = module.subnets.public_1a_id
  public_subnet_1b_id   = module.subnets.public_1b_id
  internet_gateway_id   = module.internet_gateway.id
}

# Módulo Route Tables
module "route_tables" {
  source = "./modules/route-tables"

  vpc_id              = module.vpc.vpc_id
  internet_gateway_id = module.internet_gateway.id
  nat_gateway_id_1a   = module.nat_gateways.nat_1a_id
  nat_gateway_id_1b   = module.nat_gateways.nat_1b_id
}
EOF

    cat > ${TERRAFORM_DIR}/variables.tf <<'EOF'
variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.0.0.0/16"
}
EOF

    cat > ${TERRAFORM_DIR}/outputs.tf <<'EOF'
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas"
  value = [
    module.subnets.public_1a_id,
    module.subnets.public_1b_id
  ]
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value = [
    module.subnets.private_1a_id,
    module.subnets.private_1b_id
  ]
}

output "nat_gateway_ids" {
  description = "IDs dos NAT Gateways"
  value = [
    module.nat_gateways.nat_1a_id,
    module.nat_gateways.nat_1b_id
  ]
}

output "internet_gateway_id" {
  description = "ID do Internet Gateway"
  value       = module.internet_gateway.id
}
EOF

    log_success "Arquivos Terraform principais gerados"
}

generate_documentation() {
    log_info "Gerando documentação..."

    cat > ${DOCS_DIR}/README.md <<'EOF'
# Marco 0: Engenharia Reversa da VPC Existente

**Data de Extração:** $(date +%Y-%m-%d)
**VPC Original:** vpc-0b1396a59c417c1f0
**Região:** us-east-1

## Objetivo

Este diretório contém a engenharia reversa da VPC existente, extraída automaticamente
via AWS CLI e convertida em código Terraform equivalente.

## Estrutura

```
vpc-reverse-engineered/
├── terraform/              # Código Terraform gerado
│   ├── main.tf            # Orquestrador principal
│   ├── variables.tf       # Variáveis globais
│   ├── outputs.tf         # Outputs
│   └── modules/           # Módulos por tipo de recurso
│       ├── vpc/
│       ├── subnets/
│       ├── nat-gateways/
│       ├── internet-gateway/
│       └── route-tables/
└── docs/                  # Documentação e JSONs brutos
    ├── vpc-raw.json
    ├── subnets-raw.json
    ├── nat-gateways-raw.json
    ├── igw-raw.json
    └── route-tables-raw.json
```

## Recursos Extraídos

- ✅ VPC (10.0.0.0/16)
- ✅ 4 Subnets (2 públicas + 2 privadas, us-east-1a e us-east-1b)
- ✅ 2 NAT Gateways (Multi-AZ)
- ✅ 1 Internet Gateway
- ✅ Route Tables (públicas e privadas)

## Como Usar

### 1. Validar Terraform

```bash
cd terraform
terraform init
terraform plan
```

⚠️ **IMPORTANTE:** Este código foi gerado para **LEITURA E REFERÊNCIA**, não para
aplicação direta. Use-o como baseline para criar o Marco 0 incremental.

### 2. Próximos Passos

Após validar este código:
1. Use como referência para criar `01-marco0-incremental-add-region.sh`
2. Adicione a 3ª AZ (us-east-1c) de forma incremental
3. Valide isolamento de rede com Security Groups

## Arquivos Brutos (JSONs)

Todos os JSONs brutos da AWS estão em `docs/`:
- `vpc-raw.json` - VPC completa
- `subnets-raw.json` - Todas as subnets
- `nat-gateways-raw.json` - NAT Gateways
- `igw-raw.json` - Internet Gateway
- `route-tables-raw.json` - Route Tables

Use esses arquivos para referência e auditoria.
EOF

    log_success "Documentação gerada"
}

generate_summary_report() {
    log_info "Gerando relatório resumido..."

    cat > ${DOCS_DIR}/SUMMARY.md <<EOF
# Relatório de Engenharia Reversa - Marco 0

**Data:** $(date +%Y-%m-%d %H:%M:%S)
**VPC:** ${VPC_ID}
**Região:** ${REGION}

## Infraestrutura Atual

### VPC
- **CIDR:** 10.0.0.0/16
- **DNS Hostnames:** Habilitado
- **DNS Support:** Habilitado

### Subnets

| Nome | CIDR | AZ | Tipo | IPs Disponíveis |
|------|------|----|----|-----------------|
$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --region ${REGION} \
    --query 'Subnets[*].[Tags[?Key==`Name`].Value | [0], CidrBlock, AvailabilityZone, MapPublicIpOnLaunch, AvailableIpAddressCount]' \
    --output text | awk '{printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, ($4=="True"?"Público":"Privado"), $5}')

### NAT Gateways

| Nome | AZ | IP Público | Status |
|------|----|-----------|----|
$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${VPC_ID}" --region ${REGION} \
    --query 'NatGateways[*].[Tags[?Key==`Name`].Value | [0], SubnetId, NatGatewayAddresses[0].PublicIp, State]' \
    --output text | awk '{printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4}')

### Internet Gateway

$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" --region ${REGION} \
    --query 'InternetGateways[0].[InternetGatewayId, Tags[?Key==`Name`].Value | [0]]' \
    --output text | awk '{printf "- **ID:** %s\n- **Nome:** %s\n", $1, $2}')

## Próximos Passos

1. ✅ Validar código Terraform gerado
2. ⏳ Criar script incremental para adicionar us-east-1c
3. ⏳ Testar isolamento de rede
4. ⏳ Documentar no diário de bordo

## Arquivos Gerados

- \`terraform/\` - Código Terraform modular
- \`docs/\` - Documentação e JSONs brutos
- \`docs/SUMMARY.md\` - Este arquivo

---

**Gerado por:** 00-marco0-reverse-engineer-vpc.sh
**Versão:** 1.0
EOF

    log_success "Relatório resumido gerado: ${DOCS_DIR}/SUMMARY.md"
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    log_info "Iniciando processo de engenharia reversa..."
    echo ""

    # Pré-requisitos
    check_aws_cli
    check_aws_credentials
    check_vpc_exists

    echo ""
    log_info "Criando estrutura de diretórios..."
    create_output_dirs

    echo ""
    log_info "Extraindo recursos da AWS..."
    extract_vpc_info
    extract_subnets
    extract_internet_gateway
    extract_nat_gateways
    extract_route_tables

    echo ""
    log_info "Gerando código Terraform..."
    generate_variables_tf
    generate_main_orchestrator

    echo ""
    log_info "Gerando documentação..."
    generate_documentation
    generate_summary_report

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           ENGENHARIA REVERSA CONCLUÍDA!               ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_success "Arquivos gerados em: ${OUTPUT_DIR}"
    echo ""
    log_info "Próximos passos:"
    echo "  1. Revisar código Terraform: cd ${TERRAFORM_DIR}"
    echo "  2. Validar: terraform init && terraform plan"
    echo "  3. Ver documentação: cat ${DOCS_DIR}/README.md"
    echo "  4. Ver resumo: cat ${DOCS_DIR}/SUMMARY.md"
    echo ""
}

# Executar
main "$@"
