#!/bin/bash
################################################################################
# Marco 0: Script Incremental - Adicionar 3ª Availability Zone
################################################################################
# Descrição: Script para adicionar us-east-1c à VPC existente (vpc-0b1396a59c417c1f0)
#            de forma incremental, sem impactar recursos existentes.
# Autor: DevOps Team
# Data: 2026-01-22
# Pré-requisito: VPC existente com us-east-1a e us-east-1b configuradas
################################################################################

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configurações
VPC_ID="vpc-0b1396a59c417c1f0"
REGION="us-east-1"
NEW_AZ="us-east-1c"
OUTPUT_DIR="./marco0-incremental-1c"
TERRAFORM_DIR="${OUTPUT_DIR}/terraform"

# CIDRs para nova AZ (baseado no mapeamento do diário de bordo)
PUBLIC_SUBNET_1C_CIDR="10.0.42.0/24"   # eks-public-1c
PRIVATE_SUBNET_1C_CIDR="10.0.54.0/24"  # eks-private-1c
DB_SUBNET_1C_CIDR="10.0.55.0/24"       # eks-db-1c

# Modo de execução
DRY_RUN="${DRY_RUN:-true}"  # Default: dry-run habilitado

echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Marco 0: Adicionar 3ª AZ (us-east-1c) - Incremental║${NC}"
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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

check_prerequisites() {
    log_info "Verificando pré-requisitos..."

    # AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI não encontrado"
        exit 1
    fi

    # Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform não encontrado"
        exit 1
    fi

    # Credenciais AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "Credenciais AWS inválidas"
        exit 1
    fi

    # VPC existe
    if ! aws ec2 describe-vpcs --vpc-ids ${VPC_ID} --region ${REGION} &> /dev/null; then
        log_error "VPC ${VPC_ID} não encontrada"
        exit 1
    fi

    log_success "Pré-requisitos OK"
}

validate_cidr_availability() {
    log_info "Validando disponibilidade dos CIDRs..."

    local all_subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --region ${REGION} \
        --query 'Subnets[*].CidrBlock' \
        --output text)

    for cidr in ${PUBLIC_SUBNET_1C_CIDR} ${PRIVATE_SUBNET_1C_CIDR} ${DB_SUBNET_1C_CIDR}; do
        if echo "${all_subnets}" | grep -q "${cidr}"; then
            log_error "CIDR ${cidr} já está em uso!"
            exit 1
        fi
    done

    log_success "CIDRs ${PUBLIC_SUBNET_1C_CIDR}, ${PRIVATE_SUBNET_1C_CIDR}, ${DB_SUBNET_1C_CIDR} disponíveis"
}

get_existing_resources() {
    log_info "Mapeando recursos existentes..."

    # Internet Gateway
    IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
        --region ${REGION} \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text)

    if [ -z "${IGW_ID}" ] || [ "${IGW_ID}" == "None" ]; then
        log_error "Internet Gateway não encontrado na VPC"
        exit 1
    fi

    log_success "Internet Gateway encontrado: ${IGW_ID}"
}

create_terraform_structure() {
    log_info "Criando estrutura Terraform..."

    mkdir -p ${TERRAFORM_DIR}/modules/{subnets-1c,nat-gateway-1c,route-tables-1c}

    cat > ${TERRAFORM_DIR}/main.tf <<'EOF'
# Marco 0 - Incremental: Adicionar us-east-1c
# VPC Existente: vpc-0b1396a59c417c1f0
# Estratégia: Adicionar APENAS recursos novos, zero impacto em existentes

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
    key            = "marco0/incremental-1c/terraform.tfstate"
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
      Marco       = "0-incremental"
      AZ          = "us-east-1c"
    }
  }
}

# Data Sources: Recursos existentes (não gerenciados)
data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_internet_gateway" "existing" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

# Módulo: Novas Subnets em us-east-1c
module "subnets_1c" {
  source = "./modules/subnets-1c"

  vpc_id    = data.aws_vpc.existing.id
  az        = var.new_az

  public_cidr  = var.public_subnet_1c_cidr
  private_cidr = var.private_subnet_1c_cidr
  db_cidr      = var.db_subnet_1c_cidr
}

# Módulo: NAT Gateway em us-east-1c (OPCIONAL - custo +$32/mês)
module "nat_gateway_1c" {
  source = "./modules/nat-gateway-1c"

  count = var.enable_nat_gateway_1c ? 1 : 0

  vpc_id               = data.aws_vpc.existing.id
  public_subnet_id     = module.subnets_1c.public_subnet_id
  internet_gateway_id  = data.aws_internet_gateway.existing.id
  az                   = var.new_az
}

# Módulo: Route Tables para us-east-1c
module "route_tables_1c" {
  source = "./modules/route-tables-1c"

  vpc_id              = data.aws_vpc.existing.id
  internet_gateway_id = data.aws_internet_gateway.existing.id

  # Se NAT Gateway foi criado, usar ele; senão, usar NAT de us-east-1a como fallback
  nat_gateway_id = var.enable_nat_gateway_1c ? module.nat_gateway_1c[0].nat_gateway_id : var.fallback_nat_gateway_id

  public_subnet_id  = module.subnets_1c.public_subnet_id
  private_subnet_id = module.subnets_1c.private_subnet_id
  db_subnet_id      = module.subnets_1c.db_subnet_id
}
EOF

    cat > ${TERRAFORM_DIR}/variables.tf <<EOF
variable "region" {
  description = "AWS Region"
  type        = string
  default     = "${REGION}"
}

variable "vpc_id" {
  description = "VPC ID existente"
  type        = string
  default     = "${VPC_ID}"
}

variable "new_az" {
  description = "Nova Availability Zone a adicionar"
  type        = string
  default     = "${NEW_AZ}"
}

variable "public_subnet_1c_cidr" {
  description = "CIDR para subnet pública em us-east-1c"
  type        = string
  default     = "${PUBLIC_SUBNET_1C_CIDR}"
}

variable "private_subnet_1c_cidr" {
  description = "CIDR para subnet privada EKS em us-east-1c"
  type        = string
  default     = "${PRIVATE_SUBNET_1C_CIDR}"
}

variable "db_subnet_1c_cidr" {
  description = "CIDR para subnet de banco de dados em us-east-1c"
  type        = string
  default     = "${DB_SUBNET_1C_CIDR}"
}

variable "enable_nat_gateway_1c" {
  description = "Criar NAT Gateway dedicado para us-east-1c? (custo: +\$32/mês)"
  type        = bool
  default     = false  # Default: usar NAT de us-east-1a como fallback (economia)
}

variable "fallback_nat_gateway_id" {
  description = "NAT Gateway ID de fallback (us-east-1a) se enable_nat_gateway_1c=false"
  type        = string
  default     = "nat-03512e5ee0642dcf2"  # NAT de us-east-1a existente
}
EOF

    cat > ${TERRAFORM_DIR}/outputs.tf <<'EOF'
output "public_subnet_1c_id" {
  description = "ID da subnet pública em us-east-1c"
  value       = module.subnets_1c.public_subnet_id
}

output "private_subnet_1c_id" {
  description = "ID da subnet privada EKS em us-east-1c"
  value       = module.subnets_1c.private_subnet_id
}

output "db_subnet_1c_id" {
  description = "ID da subnet de DB em us-east-1c"
  value       = module.subnets_1c.db_subnet_id
}

output "nat_gateway_1c_id" {
  description = "ID do NAT Gateway em us-east-1c (se criado)"
  value       = var.enable_nat_gateway_1c ? module.nat_gateway_1c[0].nat_gateway_id : "não criado (usando fallback)"
}

output "nat_gateway_1c_public_ip" {
  description = "IP público do NAT Gateway em us-east-1c (se criado)"
  value       = var.enable_nat_gateway_1c ? module.nat_gateway_1c[0].public_ip : "N/A"
}

output "route_table_public_1c_id" {
  description = "ID da route table pública em us-east-1c"
  value       = module.route_tables_1c.public_route_table_id
}

output "route_table_private_1c_id" {
  description = "ID da route table privada em us-east-1c"
  value       = module.route_tables_1c.private_route_table_id
}
EOF

    log_success "Estrutura Terraform criada"
}

create_subnets_module() {
    log_step "Criando módulo de Subnets para us-east-1c..."

    cat > ${TERRAFORM_DIR}/modules/subnets-1c/main.tf <<'EOF'
# Módulo: Subnets para us-east-1c
# 3 subnets: public, private (EKS nodes), db (RDS/ElastiCache)

resource "aws_subnet" "public_1c" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.public_cidr
  availability_zone       = var.az
  map_public_ip_on_launch = true

  tags = {
    Name                                           = "eks-public-1c"
    "kubernetes.io/role/elb"                       = "1"  # Tag para ALB público
    "kubernetes.io/cluster/k8s-platform-prod"      = "shared"
  }
}

resource "aws_subnet" "private_1c" {
  vpc_id            = var.vpc_id
  cidr_block        = var.private_cidr
  availability_zone = var.az

  tags = {
    Name                                           = "eks-private-1c"
    "kubernetes.io/role/internal-elb"              = "1"  # Tag para ALB interno
    "kubernetes.io/cluster/k8s-platform-prod"      = "shared"
  }
}

resource "aws_subnet" "db_1c" {
  vpc_id            = var.vpc_id
  cidr_block        = var.db_cidr
  availability_zone = var.az

  tags = {
    Name = "eks-db-1c"
    Tier = "data"
  }
}
EOF

    cat > ${TERRAFORM_DIR}/modules/subnets-1c/variables.tf <<'EOF'
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "az" {
  description = "Availability Zone"
  type        = string
}

variable "public_cidr" {
  description = "CIDR para subnet pública"
  type        = string
}

variable "private_cidr" {
  description = "CIDR para subnet privada"
  type        = string
}

variable "db_cidr" {
  description = "CIDR para subnet de banco de dados"
  type        = string
}
EOF

    cat > ${TERRAFORM_DIR}/modules/subnets-1c/outputs.tf <<'EOF'
output "public_subnet_id" {
  description = "ID da subnet pública"
  value       = aws_subnet.public_1c.id
}

output "private_subnet_id" {
  description = "ID da subnet privada"
  value       = aws_subnet.private_1c.id
}

output "db_subnet_id" {
  description = "ID da subnet de DB"
  value       = aws_subnet.db_1c.id
}
EOF

    log_success "Módulo subnets-1c criado"
}

create_nat_gateway_module() {
    log_step "Criando módulo de NAT Gateway para us-east-1c..."

    cat > ${TERRAFORM_DIR}/modules/nat-gateway-1c/main.tf <<'EOF'
# Módulo: NAT Gateway para us-east-1c (OPCIONAL)
# Custo adicional: ~$32/mês

# Elastic IP para NAT Gateway
resource "aws_eip" "nat_1c" {
  domain = "vpc"

  tags = {
    Name = "eks-nat-1c"
  }

  depends_on = [var.internet_gateway_id]
}

# NAT Gateway
resource "aws_nat_gateway" "nat_1c" {
  allocation_id = aws_eip.nat_1c.id
  subnet_id     = var.public_subnet_id

  tags = {
    Name = "eks-nat-gateway-1c"
    AZ   = var.az
  }

  depends_on = [var.internet_gateway_id]
}
EOF

    cat > ${TERRAFORM_DIR}/modules/nat-gateway-1c/variables.tf <<'EOF'
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_id" {
  description = "ID da subnet pública onde o NAT será criado"
  type        = string
}

variable "internet_gateway_id" {
  description = "ID do Internet Gateway (dependência)"
  type        = string
}

variable "az" {
  description = "Availability Zone"
  type        = string
}
EOF

    cat > ${TERRAFORM_DIR}/modules/nat-gateway-1c/outputs.tf <<'EOF'
output "nat_gateway_id" {
  description = "ID do NAT Gateway"
  value       = aws_nat_gateway.nat_1c.id
}

output "public_ip" {
  description = "IP público do NAT Gateway"
  value       = aws_eip.nat_1c.public_ip
}
EOF

    log_success "Módulo nat-gateway-1c criado"
}

create_route_tables_module() {
    log_step "Criando módulo de Route Tables para us-east-1c..."

    cat > ${TERRAFORM_DIR}/modules/route-tables-1c/main.tf <<'EOF'
# Módulo: Route Tables para us-east-1c

# Route Table para subnet PÚBLICA
resource "aws_route_table" "public_1c" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.internet_gateway_id
  }

  tags = {
    Name = "eks-public-rt-1c"
    Tier = "public"
  }
}

# Associar subnet pública à route table pública
resource "aws_route_table_association" "public_1c" {
  subnet_id      = var.public_subnet_id
  route_table_id = aws_route_table.public_1c.id
}

# Route Table para subnet PRIVADA (EKS nodes)
resource "aws_route_table" "private_1c" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.nat_gateway_id
  }

  tags = {
    Name = "eks-private-rt-1c"
    Tier = "private"
  }
}

# Associar subnet privada à route table privada
resource "aws_route_table_association" "private_1c" {
  subnet_id      = var.private_subnet_id
  route_table_id = aws_route_table.private_1c.id
}

# Route Table para subnet de DB
resource "aws_route_table" "db_1c" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.nat_gateway_id
  }

  tags = {
    Name = "eks-db-rt-1c"
    Tier = "data"
  }
}

# Associar subnet de DB à route table de DB
resource "aws_route_table_association" "db_1c" {
  subnet_id      = var.db_subnet_id
  route_table_id = aws_route_table.db_1c.id
}
EOF

    cat > ${TERRAFORM_DIR}/modules/route-tables-1c/variables.tf <<'EOF'
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "internet_gateway_id" {
  description = "ID do Internet Gateway"
  type        = string
}

variable "nat_gateway_id" {
  description = "ID do NAT Gateway (novo ou fallback)"
  type        = string
}

variable "public_subnet_id" {
  description = "ID da subnet pública"
  type        = string
}

variable "private_subnet_id" {
  description = "ID da subnet privada"
  type        = string
}

variable "db_subnet_id" {
  description = "ID da subnet de DB"
  type        = string
}
EOF

    cat > ${TERRAFORM_DIR}/modules/route-tables-1c/outputs.tf <<'EOF'
output "public_route_table_id" {
  description = "ID da route table pública"
  value       = aws_route_table.public_1c.id
}

output "private_route_table_id" {
  description = "ID da route table privada"
  value       = aws_route_table.private_1c.id
}

output "db_route_table_id" {
  description = "ID da route table de DB"
  value       = aws_route_table.db_1c.id
}
EOF

    log_success "Módulo route-tables-1c criado"
}

create_readme() {
    log_step "Criando README..."

    cat > ${OUTPUT_DIR}/README.md <<'EOF'
# Marco 0 - Incremental: Adicionar us-east-1c

**Data de Criação:** 2026-01-22
**VPC Target:** vpc-0b1396a59c417c1f0
**Nova AZ:** us-east-1c

## Objetivo

Adicionar a 3ª Availability Zone (us-east-1c) à VPC existente de forma **incremental**,
criando apenas recursos novos sem impactar a infraestrutura atual (us-east-1a, us-east-1b).

## Recursos a Criar

### Subnets em us-east-1c

| Subnet | CIDR | Propósito | IPs Disponíveis |
|--------|------|-----------|-----------------|
| eks-public-1c | 10.0.42.0/24 | ALB, Ingress | 256 |
| eks-private-1c | 10.0.54.0/24 | EKS Worker Nodes | 256 |
| eks-db-1c | 10.0.55.0/24 | RDS, ElastiCache | 256 |

### NAT Gateway (OPCIONAL)

- **Custo:** +$32/mês (~R$ 192/mês)
- **Benefício:** Alta disponibilidade total (3 AZs independentes)
- **Alternativa:** Usar NAT de us-east-1a como fallback (economia de custo)

### Route Tables

- Route table pública (via Internet Gateway)
- Route table privada (via NAT Gateway - novo ou fallback)
- Route table de DB (via NAT Gateway - novo ou fallback)

## Como Usar

### 1. Modo Dry-Run (Padrão - Recomendado)

```bash
cd terraform
terraform init
terraform plan
```

Este modo **NÃO aplica mudanças**, apenas mostra o que seria criado.

### 2. Aplicar Mudanças (SEM NAT Gateway dedicado - Economia)

```bash
terraform apply -var="enable_nat_gateway_1c=false"
```

**Economia:** $32/mês (usa NAT de us-east-1a como fallback)

### 3. Aplicar Mudanças (COM NAT Gateway dedicado - HA Total)

```bash
terraform apply -var="enable_nat_gateway_1c=true"
```

**Custo adicional:** +$32/mês
**Benefício:** HA total, cada AZ independente

## Validação Pós-Deploy

```bash
# Verificar subnets criadas
aws ec2 describe-subnets --filters "Name=availability-zone,Values=us-east-1c" --query 'Subnets[*].[SubnetId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table

# Verificar NAT Gateway (se criado)
aws ec2 describe-nat-gateways --filter "Name=subnet-id,Values=<PUBLIC_SUBNET_1C_ID>" --query 'NatGateways[*].[NatGatewayId,State,NatGatewayAddresses[0].PublicIp]' --output table

# Verificar route tables
aws ec2 describe-route-tables --filters "Name=tag:Name,Values=eks-*-rt-1c" --query 'RouteTables[*].[RouteTableId,Tags[?Key==`Name`].Value|[0],Routes[?GatewayId!=`local`].[DestinationCidrBlock,GatewayId,NatGatewayId]]' --output table
```

## Rollback

Se necessário, destruir apenas recursos criados:

```bash
terraform destroy
```

**Segurança:** Este comando destrói APENAS os recursos gerenciados por este módulo
(subnets, NAT, route tables de us-east-1c). Recursos existentes (us-east-1a, us-east-1b)
permanecem intocados.

## Impacto em Recursos Existentes

**✅ ZERO IMPACTO** - Este script é 100% incremental:

- ❌ Não modifica VPC
- ❌ Não modifica subnets de us-east-1a ou us-east-1b
- ❌ Não modifica NAT Gateways existentes
- ❌ Não modifica Internet Gateway
- ❌ Não modifica route tables existentes
- ✅ Cria APENAS recursos novos para us-east-1c

## Próximos Passos

1. ✅ Validar terraform plan
2. ✅ Aplicar com `enable_nat_gateway_1c=false` (economia)
3. ✅ Validar subnets criadas
4. ⏳ Atualizar EKS Node Groups para usar 3 AZs
5. ⏳ Adicionar us-east-1c aos DB Subnet Groups
6. ⏳ Testar distribuição de pods em 3 AZs

## Custo Estimado

| Cenário | Custo Mensal | Observação |
|---------|--------------|------------|
| **SEM NAT dedicado** | $0 | Usa NAT de us-east-1a (fallback) |
| **COM NAT dedicado** | +$32/mês | HA total, cada AZ independente |

**Recomendação inicial:** Começar SEM NAT dedicado, adicionar depois se necessário.
EOF

    log_success "README criado"
}

create_makefile() {
    log_step "Criando Makefile para automação..."

    cat > ${OUTPUT_DIR}/Makefile <<'EOF'
.PHONY: help init plan apply-no-nat apply-with-nat validate destroy clean

help:
	@echo "Marco 0 - Incremental: Adicionar us-east-1c"
	@echo ""
	@echo "Comandos disponíveis:"
	@echo "  make init            - Inicializar Terraform"
	@echo "  make plan            - Visualizar mudanças (dry-run)"
	@echo "  make apply-no-nat    - Aplicar SEM NAT dedicado (economia)"
	@echo "  make apply-with-nat  - Aplicar COM NAT dedicado (+$32/mês)"
	@echo "  make validate        - Validar recursos criados"
	@echo "  make destroy         - Destruir recursos de us-east-1c"
	@echo "  make clean           - Limpar arquivos Terraform"

init:
	cd terraform && terraform init

plan:
	cd terraform && terraform plan -out=tfplan

apply-no-nat:
	@echo "Aplicando SEM NAT Gateway dedicado (usa fallback us-east-1a)"
	cd terraform && terraform apply -var="enable_nat_gateway_1c=false" -auto-approve

apply-with-nat:
	@echo "Aplicando COM NAT Gateway dedicado (+$32/mês)"
	cd terraform && terraform apply -var="enable_nat_gateway_1c=true" -auto-approve

validate:
	@echo "Validando subnets criadas..."
	aws ec2 describe-subnets --filters "Name=availability-zone,Values=us-east-1c" \
		--query 'Subnets[*].[SubnetId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
		--output table
	@echo ""
	@echo "Validando NAT Gateways..."
	aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=eks-nat-gateway-1c" \
		--query 'NatGateways[*].[NatGatewayId,State,NatGatewayAddresses[0].PublicIp]' \
		--output table

destroy:
	@echo "ATENÇÃO: Isso destruirá APENAS recursos de us-east-1c"
	@read -p "Confirmar? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	cd terraform && terraform destroy

clean:
	cd terraform && rm -rf .terraform .terraform.lock.hcl tfplan terraform.tfstate*
EOF

    chmod +x ${OUTPUT_DIR}/Makefile
    log_success "Makefile criado"
}

generate_summary() {
    log_step "Gerando resumo final..."

    cat > ${OUTPUT_DIR}/SUMMARY.md <<EOF
# Resumo: Marco 0 - Incremental (us-east-1c)

**Data:** $(date +%Y-%m-%d %H:%M:%S)
**VPC:** ${VPC_ID}
**Nova AZ:** ${NEW_AZ}

## Recursos Planejados

### ✅ Subnets (3)

| Subnet | CIDR | IPs | Propósito |
|--------|------|-----|-----------|
| eks-public-1c | ${PUBLIC_SUBNET_1C_CIDR} | 256 | ALB, Ingress Controllers |
| eks-private-1c | ${PRIVATE_SUBNET_1C_CIDR} | 256 | EKS Worker Nodes |
| eks-db-1c | ${DB_SUBNET_1C_CIDR} | 256 | RDS, ElastiCache |

### 🔀 NAT Gateway (Opcional)

- **Custo:** +\$32/mês (~R\$ 192/mês)
- **Variável:** \`enable_nat_gateway_1c\`
- **Default:** \`false\` (usa NAT de us-east-1a)

### 🛣️ Route Tables (3)

- Route table pública → Internet Gateway
- Route table privada → NAT Gateway
- Route table DB → NAT Gateway

## Comandos Rápidos

\`\`\`bash
# Inicializar
cd ${OUTPUT_DIR}
make init

# Visualizar mudanças
make plan

# Aplicar SEM NAT dedicado (recomendado inicialmente)
make apply-no-nat

# Aplicar COM NAT dedicado (HA total)
make apply-with-nat

# Validar recursos criados
make validate

# Rollback (se necessário)
make destroy
\`\`\`

## Impacto Financeiro

| Cenário | Custo Adicional | Observação |
|---------|-----------------|------------|
| SEM NAT dedicado | \$0/mês | Usa NAT existente (us-east-1a) |
| COM NAT dedicado | +\$32/mês | HA total, AZ independente |

## Próximos Passos

1. ✅ Terraform plan validado
2. ⏳ Aplicar infraestrutura
3. ⏳ Atualizar EKS cluster para 3 AZs
4. ⏳ Atualizar DB Subnet Groups
5. ⏳ Testar distribuição de workloads
6. ⏳ Documentar no diário de bordo

---

**Gerado por:** 01-marco0-incremental-add-region.sh
EOF

    log_success "Resumo gerado: ${OUTPUT_DIR}/SUMMARY.md"
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    log_info "Iniciando processo incremental..."
    echo ""

    # Verificações
    check_prerequisites
    validate_cidr_availability
    get_existing_resources

    echo ""
    log_info "Gerando código Terraform..."
    create_terraform_structure
    create_subnets_module
    create_nat_gateway_module
    create_route_tables_module

    echo ""
    log_info "Criando documentação..."
    create_readme
    create_makefile
    generate_summary

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     SCRIPT INCREMENTAL CRIADO COM SUCESSO!           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_success "Arquivos gerados em: ${OUTPUT_DIR}"
    echo ""
    log_info "Próximos passos:"
    echo "  1. Revisar código: cd ${OUTPUT_DIR}/terraform"
    echo "  2. Inicializar: make init"
    echo "  3. Planejar: make plan"
    echo "  4. Aplicar (sem NAT): make apply-no-nat"
    echo "  5. Aplicar (com NAT): make apply-with-nat"
    echo ""
    log_warn "Modo atual: DRY_RUN=${DRY_RUN}"
    echo ""
}

# Executar
main "$@"
