# 01 - Infraestrutura Base AWS

**Épico A** | **Esforço: 20 person-hours** | **Sprint 1**

> ⚠️ **Abordagem CLI-First:** Este documento oferece múltiplas opções de provisionamento.
> **Recomendação:** Use Terraform (Opção A) ou AWS CLI (Opção B) para ambientes de produção.
> O Console AWS (Opção C) é fornecido apenas como referência visual.

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Abordagem Terraform (Recomendada)](#2-abordagem-terraform-recomendada)
3. [Task A.1: VPC Multi-AZ (6h)](#3-task-a1-vpc-multi-az-6h)
4. [Task A.2: EKS Cluster e Node Groups (8h)](#4-task-a2-eks-cluster-e-node-groups-8h)
5. [Task A.3: StorageClass e PVC Templates (2h)](#5-task-a3-storageclass-e-pvc-templates-2h)
6. [Task A.4: IAM Roles e RBAC (4h)](#6-task-a4-iam-roles-e-rbac-4h)
7. [Validação e Definition of Done](#7-validação-e-definition-of-done)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Visão Geral

### Objetivo

Provisionar toda a infraestrutura base AWS necessária para hospedar a plataforma Kubernetes:

- **VPC** com subnets públicas, privadas e de dados em 3 AZs
- **EKS Cluster** com 3 node groups especializados
- **StorageClass** gp3 para volumes persistentes
- **IAM Roles** com princípio de menor privilégio

### Arquitetura de Rede

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           VPC: 10.0.0.0/16                                  │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AVAILABILITY ZONE: us-east-1a                     │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │ Public Subnet   │  │ Private Subnet  │  │ Data Subnet     │     │   │
│  │  │ 10.0.1.0/24     │  │ 10.0.11.0/24    │  │ 10.0.21.0/24    │     │   │
│  │  │ • NAT Gateway   │  │ • EKS Nodes     │  │ • RDS           │     │   │
│  │  │ • ALB           │  │                 │  │                 │     │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AVAILABILITY ZONE: us-east-1b                     │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │ Public Subnet   │  │ Private Subnet  │  │ Data Subnet     │     │   │
│  │  │ 10.0.2.0/24     │  │ 10.0.12.0/24    │  │ 10.0.22.0/24    │     │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AVAILABILITY ZONE: us-east-1c                     │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │ Public Subnet   │  │ Private Subnet  │  │ Data Subnet     │     │   │
│  │  │ 10.0.3.0/24     │  │ 10.0.13.0/24    │  │ 10.0.23.0/24    │     │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Node Groups

| Node Group | Instance Type | vCPU | RAM | Nodes | Propósito |
|------------|--------------|------|-----|-------|-----------|
| `system` | t3.medium | 2 | 4GB | 2 (2-4) | Sistema: CoreDNS, controllers |
| `workloads` | t3.large | 2 | 8GB | 3 (2-6) | Aplicações: Redis, RabbitMQ |
| `critical` | t3.xlarge | 4 | 16GB | 2 (2-4) | Crítico: GitLab, Databases |

---

## 2. Abordagem Terraform (Recomendada)

> 🚀 **CLI-First:** Esta seção permite provisionar toda a infraestrutura base com um único comando.

### 2.1 Pré-requisitos

```bash
# Verificar ferramentas instaladas
terraform version  # >= 1.5.0
aws --version      # >= 2.0
kubectl version    # >= 1.28

# Configurar credenciais AWS
aws configure
aws sts get-caller-identity
```

### 2.2 Estrutura do Projeto Terraform

```
terraform/
├── 01-vpc-eks/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars
└── modules/
    └── (módulos reutilizáveis)
```

### 2.3 Terraform: VPC + EKS Completo

Crie o arquivo `terraform/01-vpc-eks/main.tf`:

```hcl
# terraform/01-vpc-eks/main.tf

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "k8s-platform-terraform-state"
    key    = "vpc-eks/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "k8s-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# VPC Module
# -----------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = "10.0.0.0/16"

  azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets  = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod"
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # VPC Endpoint para S3
  enable_s3_endpoint = true

  # Tags para EKS
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = 1
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = 1
  }
}

# -----------------------------------------------------------------------------
# EKS Module
# -----------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_irsa = true

  # Encryption at rest
  cluster_encryption_config = {
    resources = ["secrets"]
  }

  # Control plane logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent                 = true
      service_account_role_arn    = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # Node Groups
  eks_managed_node_groups = {
    system = {
      name           = "system"
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      disk_size      = 30

      labels = {
        "node-type" = "system"
        "workload"  = "platform"
      }
    }

    workloads = {
      name           = "workloads"
      instance_types = ["t3.large"]
      min_size       = 2
      max_size       = 6
      desired_size   = 3
      disk_size      = 50

      labels = {
        "node-type" = "workloads"
        "workload"  = "applications"
      }
    }

    critical = {
      name           = "critical"
      instance_types = ["t3.xlarge"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      disk_size      = 100

      labels = {
        "node-type" = "critical"
        "workload"  = "databases"
      }

      taints = [{
        key    = "workload"
        value  = "critical"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true
}

# -----------------------------------------------------------------------------
# IRSA para EBS CSI Driver
# -----------------------------------------------------------------------------
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# -----------------------------------------------------------------------------
# Security Group para RDS
# -----------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security Group para RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }
}
```

Crie o arquivo `terraform/01-vpc-eks/variables.tf`:

```hcl
# terraform/01-vpc-eks/variables.tf

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "k8s-platform"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
  default     = "k8s-platform-prod"
}
```

Crie o arquivo `terraform/01-vpc-eks/outputs.tf`:

```hcl
# terraform/01-vpc-eks/outputs.tf

output "vpc_id" {
  description = "ID da VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "IDs das subnets privadas"
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "IDs das subnets de database"
  value       = module.vpc.database_subnets
}

output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group do cluster EKS"
  value       = module.eks.cluster_security_group_id
}

output "rds_security_group_id" {
  description = "Security group para RDS"
  value       = aws_security_group.rds.id
}

output "configure_kubectl" {
  description = "Comando para configurar kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
```

### 2.4 Executar Terraform

```bash
cd terraform/01-vpc-eks

# Inicializar (baixar providers e módulos)
terraform init

# Planejar (verificar o que será criado)
terraform plan -out=tfplan

# Aplicar (criar recursos)
terraform apply tfplan

# Configurar kubectl
$(terraform output -raw configure_kubectl)

# Verificar
kubectl get nodes
```

### 2.5 Validação Pós-Terraform

```bash
#!/bin/bash
# scripts/validate-infra.sh

set -euo pipefail

echo "🔍 Validando infraestrutura provisionada..."

# VPC
VPC_ID=$(terraform output -raw vpc_id)
echo "✅ VPC: $VPC_ID"

# Subnets
PRIVATE_SUBNETS=$(terraform output -json private_subnets | jq -r '.[]')
echo "✅ Subnets privadas: $(echo $PRIVATE_SUBNETS | wc -w)"

# EKS
CLUSTER_NAME=$(terraform output -raw cluster_name)
CLUSTER_STATUS=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.status" --output text)
if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
  echo "✅ Cluster EKS: $CLUSTER_NAME ($CLUSTER_STATUS)"
else
  echo "❌ Cluster não está ACTIVE: $CLUSTER_STATUS"
  exit 1
fi

# Nodes
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [[ $NODE_COUNT -ge 7 ]]; then
  echo "✅ Nodes: $NODE_COUNT"
else
  echo "⚠️ Nodes: $NODE_COUNT (esperado >= 7)"
fi

echo "🎉 Infraestrutura validada com sucesso!"
```

---

> 📋 **Nota:** Se preferir não usar Terraform, as seções abaixo fornecem alternativas via AWS CLI e Console.

---

## 3. Task A.1: VPC Multi-AZ (6h)

### 3.1 Criar VPC e Subnets

#### Opção A: AWS CLI (Recomendado)

```bash
#!/bin/bash
# scripts/create-vpc.sh

set -euo pipefail

PROJECT_NAME="k8s-platform-prod"
REGION="us-east-1"
VPC_CIDR="10.0.0.0/16"

echo "🌐 Criando VPC e componentes de rede..."

# 1. Criar VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc},{Key=Project,Value=k8s-platform},{Key=Environment,Value=prod}]" \
  --query 'Vpc.VpcId' --output text)
echo "✅ VPC criada: $VPC_ID"

# Habilitar DNS
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support

# 2. Criar Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
echo "✅ Internet Gateway: $IGW_ID"

# 3. Criar Subnets Públicas
for i in 1 2 3; do
  AZ="us-east-1$(echo $i | tr '123' 'abc')"
  CIDR="10.0.${i}.0/24"
  SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $CIDR \
    --availability-zone $AZ \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-${AZ}},{Key=kubernetes.io/cluster/${PROJECT_NAME},Value=shared},{Key=kubernetes.io/role/elb,Value=1}]" \
    --query 'Subnet.SubnetId' --output text)
  echo "✅ Subnet pública $AZ: $SUBNET_ID"
done

# 4. Criar Subnets Privadas
for i in 1 2 3; do
  AZ="us-east-1$(echo $i | tr '123' 'abc')"
  CIDR="10.0.1${i}.0/24"
  SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $CIDR \
    --availability-zone $AZ \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-${AZ}},{Key=kubernetes.io/cluster/${PROJECT_NAME},Value=shared},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
    --query 'Subnet.SubnetId' --output text)
  echo "✅ Subnet privada $AZ: $SUBNET_ID"
done

# 5. Criar Subnets de Database
for i in 1 2 3; do
  AZ="us-east-1$(echo $i | tr '123' 'abc')"
  CIDR="10.0.2${i}.0/24"
  SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $CIDR \
    --availability-zone $AZ \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-db-${AZ}}]" \
    --query 'Subnet.SubnetId' --output text)
  echo "✅ Subnet database $AZ: $SUBNET_ID"
done

# 6. Criar NAT Gateway
PUBLIC_SUBNET=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*1a*" \
  --query 'Subnets[0].SubnetId' --output text)

EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
NAT_GW=$(aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET \
  --allocation-id $EIP_ALLOC \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-nat}]" \
  --query 'NatGateway.NatGatewayId' --output text)
echo "✅ NAT Gateway: $NAT_GW (aguarde ficar 'available')"

# 7. Criar Route Tables
# Route table pública
RTB_PUBLIC=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-rtb}]" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PUBLIC --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

# Associar subnets públicas
for SUBNET in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*" --query 'Subnets[*].SubnetId' --output text); do
  aws ec2 associate-route-table --route-table-id $RTB_PUBLIC --subnet-id $SUBNET
done
echo "✅ Route table pública configurada"

# Route table privada (aguardar NAT Gateway ficar available)
echo "⏳ Aguardando NAT Gateway ficar available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW

RTB_PRIVATE=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-rtb}]" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PRIVATE --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW

# Associar subnets privadas e de database
for SUBNET in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" --query 'Subnets[*].SubnetId' --output text); do
  aws ec2 associate-route-table --route-table-id $RTB_PRIVATE --subnet-id $SUBNET
done
for SUBNET in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*db*" --query 'Subnets[*].SubnetId' --output text); do
  aws ec2 associate-route-table --route-table-id $RTB_PRIVATE --subnet-id $SUBNET
done
echo "✅ Route table privada configurada"

# 8. Criar VPC Endpoint para S3
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.${REGION}.s3 \
  --route-table-ids $RTB_PRIVATE \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${PROJECT_NAME}-s3-endpoint}]"
echo "✅ VPC Endpoint S3 criado"

# Exportar variáveis
echo ""
echo "📋 Variáveis para próximos passos:"
echo "export VPC_ID=$VPC_ID"
echo "export NAT_GW=$NAT_GW"
```

#### Opção B: Console AWS (Referência Visual)

> ⚠️ **Nota:** Prefira a Opção A (CLI) ou Terraform para ambientes de produção.

**Passo a passo no Console AWS:**

1. Acesse o Console AWS: https://console.aws.amazon.com/
2. Certifique-se de estar na região **us-east-1** (N. Virginia)
3. Na barra de busca, digite `VPC` e clique em **VPC**
4. Clique em **Create VPC**
5. Selecione **VPC and more** (wizard completo)
6. Preencha os campos:

   **Name tag auto-generation:**
   | Campo | Valor |
   |-------|-------|
   | **Auto-generate** | ✅ Marcar |
   | **Name** | `k8s-platform-prod` |

   **IPv4 CIDR block:**
   | Campo | Valor |
   |-------|-------|
   | **IPv4 CIDR** | `10.0.0.0/16` |

   **IPv6 CIDR block:**
   | Campo | Valor |
   |-------|-------|
   | **IPv6 CIDR block** | No IPv6 CIDR block |

   **Tenancy:**
   | Campo | Valor |
   |-------|-------|
   | **Tenancy** | Default |

   **Number of Availability Zones:**
   | Campo | Valor |
   |-------|-------|
   | **Number of AZs** | 3 |

   **Number of public subnets:**
   | Campo | Valor |
   |-------|-------|
   | **Public subnets** | 3 |

   **Number of private subnets:**
   | Campo | Valor |
   |-------|-------|
   | **Private subnets** | 3 |

   **NAT gateways:**
   | Campo | Valor |
   |-------|-------|
   | **NAT gateways** | In 1 AZ |

   > **Nota FinOps:** Para alta disponibilidade total, use "1 per AZ" (+$80/mês)

   **VPC endpoints:**
   | Campo | Valor |
   |-------|-------|
   | **S3 Gateway** | ✅ Marcar |

   **DNS options:**
   | Campo | Valor |
   |-------|-------|
   | **Enable DNS hostnames** | ✅ Marcar |
   | **Enable DNS resolution** | ✅ Marcar |

7. Revise o diagrama gerado automaticamente
8. Clique em **Create VPC**
9. Aguarde a criação (2-3 minutos)

**Contexto:** O wizard cria automaticamente subnets, route tables, internet gateway, NAT gateway e VPC endpoint para S3.

---

### 2.2 Criar Subnets de Dados (RDS)

O wizard não cria subnets específicas para dados. Vamos criar manualmente:

**Passo a passo no Console AWS:**

1. No VPC Dashboard, menu lateral, clique em **Subnets**
2. Clique em **Create subnet**
3. Preencha:

   **VPC ID:**
   | Campo | Valor |
   |-------|-------|
   | **VPC** | Selecione `k8s-platform-prod-vpc` |

   **Subnet 1:**
   | Campo | Valor |
   |-------|-------|
   | **Subnet name** | `k8s-platform-prod-db-us-east-1a` |
   | **Availability Zone** | `us-east-1a` |
   | **IPv4 CIDR block** | `10.0.21.0/24` |

4. Clique em **Add new subnet**

   **Subnet 2:**
   | Campo | Valor |
   |-------|-------|
   | **Subnet name** | `k8s-platform-prod-db-us-east-1b` |
   | **Availability Zone** | `us-east-1b` |
   | **IPv4 CIDR block** | `10.0.22.0/24` |

5. Clique em **Add new subnet**

   **Subnet 3:**
   | Campo | Valor |
   |-------|-------|
   | **Subnet name** | `k8s-platform-prod-db-us-east-1c` |
   | **Availability Zone** | `us-east-1c` |
   | **IPv4 CIDR block** | `10.0.23.0/24` |

6. Clique em **Create subnet**

---

### 2.3 Associar Subnets de Dados à Route Table Privada

1. Selecione uma das subnets de dados criadas
2. Clique na aba **Route table**
3. Clique em **Edit route table association**
4. Selecione a route table **privada** (a que tem rota para NAT Gateway)
5. Clique em **Save**
6. Repita para as outras 2 subnets de dados

---

### 2.4 Adicionar Tags para EKS

As subnets precisam de tags específicas para o EKS criar load balancers:

**Subnets Públicas (para ALB externo):**

1. Selecione CADA subnet **pública** (uma por vez)
2. Clique na aba **Tags**
3. Clique em **Manage tags**
4. Adicione as tags:

   | Key | Value |
   |-----|-------|
   | `kubernetes.io/cluster/k8s-platform-prod` | `shared` |
   | `kubernetes.io/role/elb` | `1` |

5. Clique em **Save**

**Subnets Privadas (para nodes e ALB interno):**

1. Selecione CADA subnet **privada** (uma por vez)
2. Adicione as tags:

   | Key | Value |
   |-----|-------|
   | `kubernetes.io/cluster/k8s-platform-prod` | `shared` |
   | `kubernetes.io/role/internal-elb` | `1` |

3. Clique em **Save**

**Via CLI (mais rápido):**

```bash
# Obter IDs das subnets
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=k8s-platform-prod-vpc" --query "Vpcs[0].VpcId" --output text)

# Subnets públicas
PUBLIC_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*" --query "Subnets[*].SubnetId" --output text)

for subnet in $PUBLIC_SUBNETS; do
  aws ec2 create-tags --resources $subnet --tags \
    Key=kubernetes.io/cluster/k8s-platform-prod,Value=shared \
    Key=kubernetes.io/role/elb,Value=1
  echo "Tagged public subnet: $subnet"
done

# Subnets privadas
PRIVATE_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" --query "Subnets[*].SubnetId" --output text)

for subnet in $PRIVATE_SUBNETS; do
  aws ec2 create-tags --resources $subnet --tags \
    Key=kubernetes.io/cluster/k8s-platform-prod,Value=shared \
    Key=kubernetes.io/role/internal-elb,Value=1
  echo "Tagged private subnet: $subnet"
done
```

---

### 2.5 Criar Security Groups

**Security Group para EKS Cluster:**

1. No VPC Dashboard, menu lateral, clique em **Security groups**
2. Clique em **Create security group**
3. Preencha:

   | Campo | Valor |
   |-------|-------|
   | **Security group name** | `k8s-platform-prod-eks-cluster-sg` |
   | **Description** | `Security Group para EKS Control Plane` |
   | **VPC** | Selecione `k8s-platform-prod-vpc` |

4. **Inbound rules:** Deixe vazio (será configurado pelo EKS)

5. **Outbound rules:**
   | Type | Destination | Description |
   |------|-------------|-------------|
   | All traffic | 0.0.0.0/0 | Allow all outbound |

6. **Tags:**
   | Key | Value |
   |-----|-------|
   | `Name` | `k8s-platform-prod-eks-cluster-sg` |
   | `Project` | `k8s-platform` |
   | `Environment` | `prod` |

7. Clique em **Create security group**

**Security Group para RDS:**

1. Clique em **Create security group**
2. Preencha:

   | Campo | Valor |
   |-------|-------|
   | **Security group name** | `k8s-platform-prod-rds-sg` |
   | **Description** | `Security Group para RDS PostgreSQL` |
   | **VPC** | Selecione `k8s-platform-prod-vpc` |

3. **Inbound rules:**
   | Type | Port | Source | Description |
   |------|------|--------|-------------|
   | PostgreSQL | 5432 | `k8s-platform-prod-eks-cluster-sg` | EKS to RDS |

4. **Tags:**
   | Key | Value |
   |-----|-------|
   | `Name` | `k8s-platform-prod-rds-sg` |
   | `Project` | `k8s-platform` |

5. Clique em **Create security group**

---

### 2.6 Documentar IDs Criados

Anote os seguintes IDs para uso posterior:

```bash
# Obter e salvar IDs
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=k8s-platform-prod-vpc" --query "Vpcs[0].VpcId" --output text)
echo "VPC_ID: $VPC_ID"

PRIVATE_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" --query "Subnets[*].SubnetId" --output text | tr '\t' ',')
echo "PRIVATE_SUBNETS: $PRIVATE_SUBNETS"

EKS_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=k8s-platform-prod-eks-cluster-sg" --query "SecurityGroups[0].GroupId" --output text)
echo "EKS_SG: $EKS_SG"

RDS_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=k8s-platform-prod-rds-sg" --query "SecurityGroups[0].GroupId" --output text)
echo "RDS_SG: $RDS_SG"
```

---

## 4. Task A.2: EKS Cluster e Node Groups (8h)

### 4.1 Criar EKS Cluster e Node Groups

#### Opção A: eksctl (Recomendado para CLI)

```bash
#!/bin/bash
# scripts/create-eks.sh

set -euo pipefail

CLUSTER_NAME="k8s-platform-prod"
REGION="us-east-1"

echo "🚀 Criando cluster EKS com eksctl..."

# Criar arquivo de configuração eksctl
cat > eks-cluster-config.yaml <<'EOF'
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: k8s-platform-prod
  region: us-east-1
  version: "1.29"
  tags:
    Project: k8s-platform
    Environment: prod
    Owner: devops-team

vpc:
  id: "${VPC_ID}"  # Substituir pelo VPC_ID criado anteriormente
  subnets:
    private:
      us-east-1a:
        id: "${PRIVATE_SUBNET_1A}"
      us-east-1b:
        id: "${PRIVATE_SUBNET_1B}"
      us-east-1c:
        id: "${PRIVATE_SUBNET_1C}"

iam:
  withOIDC: true

secretsEncryption:
  keyARN: ""  # Opcional: especificar KMS key ARN

cloudWatch:
  clusterLogging:
    enableTypes:
      - api
      - audit
      - authenticator
      - controllerManager
      - scheduler

addons:
  - name: vpc-cni
    version: latest
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
  - name: aws-ebs-csi-driver
    version: latest
    serviceAccountRoleARN: ""  # Será criado automaticamente

managedNodeGroups:
  - name: system
    instanceType: t3.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    volumeSize: 30
    privateNetworking: true
    labels:
      node-type: system
      workload: platform
    tags:
      Project: k8s-platform
      NodeGroup: system

  - name: workloads
    instanceType: t3.large
    desiredCapacity: 3
    minSize: 2
    maxSize: 6
    volumeSize: 50
    privateNetworking: true
    labels:
      node-type: workloads
      workload: applications
    tags:
      Project: k8s-platform
      NodeGroup: workloads

  - name: critical
    instanceType: t3.xlarge
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    volumeSize: 100
    privateNetworking: true
    labels:
      node-type: critical
      workload: databases
    taints:
      - key: workload
        value: critical
        effect: NoSchedule
    tags:
      Project: k8s-platform
      NodeGroup: critical
EOF

# Substituir variáveis no arquivo
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=k8s-platform-prod-vpc" --query "Vpcs[0].VpcId" --output text)
PRIVATE_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*1a*" --query "Subnets[0].SubnetId" --output text)
PRIVATE_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*1b*" --query "Subnets[0].SubnetId" --output text)
PRIVATE_SUBNET_1C=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*1c*" --query "Subnets[0].SubnetId" --output text)

sed -i "s/\${VPC_ID}/$VPC_ID/g" eks-cluster-config.yaml
sed -i "s/\${PRIVATE_SUBNET_1A}/$PRIVATE_SUBNET_1A/g" eks-cluster-config.yaml
sed -i "s/\${PRIVATE_SUBNET_1B}/$PRIVATE_SUBNET_1B/g" eks-cluster-config.yaml
sed -i "s/\${PRIVATE_SUBNET_1C}/$PRIVATE_SUBNET_1C/g" eks-cluster-config.yaml

# Criar cluster
eksctl create cluster -f eks-cluster-config.yaml

# Verificar
kubectl cluster-info
kubectl get nodes

echo "✅ Cluster EKS criado com sucesso!"
```

#### Opção B: AWS CLI (Passo a Passo)

```bash
#!/bin/bash
# scripts/create-eks-cli.sh

set -euo pipefail

CLUSTER_NAME="k8s-platform-prod"
REGION="us-east-1"

# 1. Criar IAM Role para EKS Cluster
echo "📝 Criando IAM Role para EKS Cluster..."

cat > eks-cluster-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name ${CLUSTER_NAME}-cluster-role \
  --assume-role-policy-document file://eks-cluster-trust-policy.json \
  --tags Key=Project,Value=k8s-platform

aws iam attach-role-policy \
  --role-name ${CLUSTER_NAME}-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

CLUSTER_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-cluster-role --query 'Role.Arn' --output text)
echo "✅ Cluster Role: $CLUSTER_ROLE_ARN"

# 2. Criar IAM Role para Node Group
echo "📝 Criando IAM Role para Node Group..."

cat > eks-node-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name ${CLUSTER_NAME}-node-role \
  --assume-role-policy-document file://eks-node-trust-policy.json \
  --tags Key=Project,Value=k8s-platform

for POLICY in AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly AmazonSSMManagedInstanceCore; do
  aws iam attach-role-policy \
    --role-name ${CLUSTER_NAME}-node-role \
    --policy-arn arn:aws:iam::aws:policy/$POLICY
done

NODE_ROLE_ARN=$(aws iam get-role --role-name ${CLUSTER_NAME}-node-role --query 'Role.Arn' --output text)
echo "✅ Node Role: $NODE_ROLE_ARN"

# 3. Obter IDs de recursos
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${CLUSTER_NAME}-vpc" --query "Vpcs[0].VpcId" --output text)
PRIVATE_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" --query "Subnets[*].SubnetId" --output text | tr '\t' ',')
EKS_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${CLUSTER_NAME}-eks-cluster-sg" --query "SecurityGroups[0].GroupId" --output text)

# 4. Criar Cluster EKS
echo "🚀 Criando Cluster EKS (isso leva ~15 minutos)..."

aws eks create-cluster \
  --name $CLUSTER_NAME \
  --role-arn $CLUSTER_ROLE_ARN \
  --resources-vpc-config subnetIds=${PRIVATE_SUBNETS},securityGroupIds=${EKS_SG},endpointPublicAccess=true,endpointPrivateAccess=true \
  --kubernetes-version 1.29 \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' \
  --tags Project=k8s-platform,Environment=prod

echo "⏳ Aguardando cluster ficar ACTIVE..."
aws eks wait cluster-active --name $CLUSTER_NAME
echo "✅ Cluster ACTIVE!"

# 5. Atualizar kubeconfig
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# 6. Criar Node Groups
echo "📦 Criando Node Groups..."

for NG in "system:t3.medium:2:4:2:30" "workloads:t3.large:2:6:3:50" "critical:t3.xlarge:2:4:2:100"; do
  IFS=':' read -r NAME INSTANCE MIN MAX DESIRED DISK <<< "$NG"

  LABELS="node-type=$NAME"
  TAINTS=""
  if [[ "$NAME" == "critical" ]]; then
    TAINTS="workload=critical:NoSchedule"
  fi

  aws eks create-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NAME \
    --scaling-config minSize=$MIN,maxSize=$MAX,desiredSize=$DESIRED \
    --disk-size $DISK \
    --subnets $(echo $PRIVATE_SUBNETS | tr ',' ' ') \
    --instance-types $INSTANCE \
    --node-role $NODE_ROLE_ARN \
    --labels $LABELS \
    ${TAINTS:+--taints "$TAINTS"} \
    --tags Project=k8s-platform,NodeGroup=$NAME

  echo "✅ Node Group '$NAME' criado"
done

echo "⏳ Aguardando Node Groups ficarem ACTIVE..."
for NG in system workloads critical; do
  aws eks wait nodegroup-active --cluster-name $CLUSTER_NAME --nodegroup-name $NG
done

echo "🎉 Cluster e Node Groups criados com sucesso!"
kubectl get nodes
```

#### Opção C: Console AWS (Referência Visual)

> ⚠️ **Nota:** Prefira as opções A ou B para ambientes de produção.

### 4.1.1 Criar IAM Role para EKS Cluster (Console)

**Passo a passo no Console AWS:**

1. Na barra de busca, digite `IAM` e clique em **IAM**
2. No menu lateral, clique em **Roles**
3. Clique em **Create role**
4. Preencha:

   **Step 1 - Select trusted entity:**
   | Campo | Valor |
   |-------|-------|
   | **Trusted entity type** | AWS service |
   | **Use case** | EKS |
   | **Use case (dropdown)** | EKS - Cluster |

5. Clique em **Next**

   **Step 2 - Add permissions:**
   - A policy `AmazonEKSClusterPolicy` já estará selecionada

6. Clique em **Next**

   **Step 3 - Name, review, and create:**
   | Campo | Valor |
   |-------|-------|
   | **Role name** | `k8s-platform-eks-cluster-role` |
   | **Description** | `IAM Role para EKS Control Plane` |

7. **Tags:**
   | Key | Value |
   |-----|-------|
   | `Project` | `k8s-platform` |
   | `Environment` | `prod` |

8. Clique em **Create role**

---

### 3.2 Criar IAM Role para EKS Node Group

1. Em **Roles**, clique em **Create role**
2. Preencha:

   **Step 1:**
   | Campo | Valor |
   |-------|-------|
   | **Trusted entity type** | AWS service |
   | **Use case** | EC2 |

3. Clique em **Next**

   **Step 2 - Add permissions:**
   Busque e selecione:
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEKS_CNI_Policy`
   - `AmazonEC2ContainerRegistryReadOnly`
   - `AmazonSSMManagedInstanceCore`

4. Clique em **Next**

   **Step 3:**
   | Campo | Valor |
   |-------|-------|
   | **Role name** | `k8s-platform-eks-node-role` |
   | **Description** | `IAM Role para EKS Worker Nodes` |

5. **Tags:** (mesmas do cluster role)

6. Clique em **Create role**

---

### 3.3 Criar Cluster EKS

**Passo a passo no Console AWS:**

1. Na barra de busca, digite `EKS` e clique em **Elastic Kubernetes Service**
2. Clique em **Add cluster** → **Create**
3. Preencha:

   **Step 1 - Configure cluster:**

   | Campo | Valor |
   |-------|-------|
   | **Name** | `k8s-platform-prod` |
   | **Kubernetes version** | `1.29` (ou mais recente estável) |
   | **Cluster service role** | Selecione `k8s-platform-eks-cluster-role` |

   **Secrets encryption:**
   | Campo | Valor |
   |-------|-------|
   | **Turn on envelope encryption** | ✅ Marcar |
   | **KMS key** | Criar nova ou selecionar existente |

   **Tags:**
   | Key | Value |
   |-----|-------|
   | `Project` | `k8s-platform` |
   | `Environment` | `prod` |
   | `Owner` | `devops-team` |

4. Clique em **Next**

   **Step 2 - Specify networking:**

   | Campo | Valor |
   |-------|-------|
   | **VPC** | Selecione `k8s-platform-prod-vpc` |
   | **Subnets** | Selecione TODAS as subnets **privadas** (3) |
   | **Security groups** | Selecione `k8s-platform-prod-eks-cluster-sg` |
   | **Cluster endpoint access** | Public and private |

   **Advanced settings:**
   | Campo | Valor |
   |-------|-------|
   | **Public access CIDR** | Adicione IPs permitidos (ex: `203.0.113.0/24`) |

   > **Segurança:** Restrinja o acesso público apenas aos IPs do seu escritório

5. Clique em **Next**

   **Step 3 - Configure observability:**

   | Campo | Valor |
   |-------|-------|
   | **API server** | ✅ Marcar |
   | **Audit** | ✅ Marcar |
   | **Authenticator** | ✅ Marcar |
   | **Controller manager** | ✅ Marcar |
   | **Scheduler** | ✅ Marcar |

6. Clique em **Next**

   **Step 4 - Select add-ons:**

   Selecione todos os add-ons padrão:
   - ✅ Amazon VPC CNI
   - ✅ CoreDNS
   - ✅ kube-proxy
   - ✅ Amazon EBS CSI Driver

7. Clique em **Next**

   **Step 5 - Configure selected add-ons settings:**
   - Deixe as configurações padrão
   - Selecione versões mais recentes

8. Clique em **Next** → **Create**

9. **Aguarde a criação** (15-20 minutos)

---

### 3.4 Configurar kubectl

Após o cluster estar `Active`:

```bash
# Atualizar kubeconfig
aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod

# Verificar conexão
kubectl cluster-info

# Saída esperada:
# Kubernetes control plane is running at https://xxxxx.gr7.us-east-1.eks.amazonaws.com
# CoreDNS is running at https://xxxxx.gr7.us-east-1.eks.amazonaws.com/api/v1/...

# Verificar nodes (ainda não haverá nodes)
kubectl get nodes
# No resources found
```

---

### 3.5 Criar Node Group: system

**Passo a passo no Console AWS:**

1. No EKS, clique no cluster `k8s-platform-prod`
2. Aba **Compute** → **Add node group**
3. Preencha:

   **Step 1 - Configure node group:**

   | Campo | Valor |
   |-------|-------|
   | **Name** | `system` |
   | **Node IAM role** | Selecione `k8s-platform-eks-node-role` |

   **Node group scaling configuration:**
   | Campo | Valor |
   |-------|-------|
   | **Desired size** | `2` |
   | **Minimum size** | `2` |
   | **Maximum size** | `4` |

   **Node group update configuration:**
   | Campo | Valor |
   |-------|-------|
   | **Maximum unavailable** | Number → `1` |

   **Labels:**
   | Key | Value |
   |-----|-------|
   | `node-type` | `system` |
   | `workload` | `platform` |

   **Taints:** Deixe vazio

   **Tags:**
   | Key | Value |
   |-----|-------|
   | `Project` | `k8s-platform` |
   | `NodeGroup` | `system` |

4. Clique em **Next**

   **Step 2 - Set compute and scaling configuration:**

   | Campo | Valor |
   |-------|-------|
   | **AMI type** | Amazon Linux 2 (AL2_x86_64) |
   | **Capacity type** | On-Demand |
   | **Instance types** | `t3.medium` |
   | **Disk size** | `30` GB |

5. Clique em **Next**

   **Step 3 - Specify networking:**

   | Campo | Valor |
   |-------|-------|
   | **Subnets** | Selecione as 3 subnets **privadas** |
   | **Configure remote access** | Don't allow remote access to nodes |

   > **Segurança:** Use Session Manager para acesso aos nodes se necessário

6. Clique em **Next** → **Create**

---

### 3.6 Criar Node Group: workloads

1. Em **Compute** → **Add node group**
2. Preencha:

   | Campo | Valor |
   |-------|-------|
   | **Name** | `workloads` |
   | **Node IAM role** | `k8s-platform-eks-node-role` |
   | **Desired size** | `3` |
   | **Minimum size** | `2` |
   | **Maximum size** | `6` |

   **Labels:**
   | Key | Value |
   |-----|-------|
   | `node-type` | `workloads` |
   | `workload` | `applications` |

   **Compute:**
   | Campo | Valor |
   |-------|-------|
   | **Instance types** | `t3.large` |
   | **Disk size** | `50` GB |

3. Complete os passos e clique em **Create**

---

### 3.7 Criar Node Group: critical

1. Em **Compute** → **Add node group**
2. Preencha:

   | Campo | Valor |
   |-------|-------|
   | **Name** | `critical` |
   | **Node IAM role** | `k8s-platform-eks-node-role` |
   | **Desired size** | `2` |
   | **Minimum size** | `2` |
   | **Maximum size** | `4` |

   **Labels:**
   | Key | Value |
   |-----|-------|
   | `node-type` | `critical` |
   | `workload` | `databases` |

   **Taints:**
   | Key | Value | Effect |
   |-----|-------|--------|
   | `workload` | `critical` | `NoSchedule` |

   **Compute:**
   | Campo | Valor |
   |-------|-------|
   | **Instance types** | `t3.xlarge` |
   | **Disk size** | `100` GB |

3. Complete os passos e clique em **Create**

---

### 3.8 Verificar Nodes

Aguarde os node groups ficarem `Active` (5-10 minutos cada):

```bash
# Verificar nodes
kubectl get nodes -o wide

# Saída esperada:
# NAME                             STATUS   ROLES    AGE   VERSION
# ip-10-0-11-xxx.ec2.internal     Ready    <none>   5m    v1.29.0-eks-xxxxx
# ip-10-0-12-xxx.ec2.internal     Ready    <none>   5m    v1.29.0-eks-xxxxx
# ...

# Verificar labels
kubectl get nodes --show-labels | grep node-type

# Verificar taints
kubectl describe nodes | grep -A 5 Taints
```

---

## 5. Task A.3: StorageClass e PVC Templates (2h)

### 4.1 Verificar EBS CSI Driver

```bash
# Verificar se o EBS CSI Driver está instalado
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Saída esperada:
# NAME                                  READY   STATUS    RESTARTS   AGE
# ebs-csi-controller-xxxxxxxxx-xxxxx   6/6     Running   0          10m
# ebs-csi-node-xxxxx                   3/3     Running   0          10m
# ...
```

---

### 4.2 Criar StorageClass gp3

```bash
cat > storageclass-gp3.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
  # Performance otimizada
  iops: "3000"
  throughput: "125"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

kubectl apply -f storageclass-gp3.yaml

# Verificar
kubectl get storageclass
```

---

### 4.3 Remover StorageClass Padrão Anterior

```bash
# Verificar qual é a StorageClass padrão atual
kubectl get storageclass | grep "(default)"

# Se houver outra default, remover a annotation
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# Verificar que gp3 é a default
kubectl get storageclass
# NAME   PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
# gp2    ebs.csi.aws.com   Delete          WaitForFirstConsumer   true                   30m
# gp3 (default)   ebs.csi.aws.com   Delete   WaitForFirstConsumer   true                1m
```

---

### 4.4 Criar PVC Template de Teste

```bash
cat > test-pvc.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 1Gi
EOF

kubectl apply -f test-pvc.yaml

# Verificar (ficará Pending até um pod usar)
kubectl get pvc test-pvc

# Criar pod de teste para provisionar o volume
cat > test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: nginx:alpine
    volumeMounts:
    - mountPath: /data
      name: test-volume
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: test-pvc
EOF

kubectl apply -f test-pod.yaml

# Aguardar e verificar
kubectl get pvc test-pvc
# STATUS deve mudar para Bound

kubectl get pv
# Deve mostrar o PV provisionado

# Limpar
kubectl delete pod test-pod
kubectl delete pvc test-pvc
```

---

## 6. Task A.4: IAM Roles e RBAC (4h)

### 5.1 Criar OIDC Provider para IRSA

IRSA (IAM Roles for Service Accounts) permite que pods assumam roles IAM:

```bash
# Verificar se já existe
CLUSTER_NAME="k8s-platform-prod"
OIDC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
echo "OIDC ID: $OIDC_ID"

# Verificar se o provider existe
aws iam list-open-id-connect-providers | grep $OIDC_ID

# Se não existir, criar
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve --region us-east-1
```

---

### 5.2 Criar Namespaces Básicos

```bash
# Criar namespaces
for ns in gitlab observability redis rabbitmq; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace $ns project=k8s-platform environment=prod
done

# Verificar
kubectl get namespaces --show-labels | grep k8s-platform
```

---

### 5.3 Criar RBAC Básico

**ClusterRole para leitura (observadores):**

```bash
cat > clusterrole-reader.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-platform-reader
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
EOF

kubectl apply -f clusterrole-reader.yaml
```

**ClusterRole para operadores:**

```bash
cat > clusterrole-operator.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-platform-operator
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods/exec", "pods/log", "pods/portforward"]
  verbs: ["get", "create"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses", "networkpolicies"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

kubectl apply -f clusterrole-operator.yaml
```

---

### 5.4 Mapear Usuários IAM para RBAC

Editar o ConfigMap `aws-auth`:

```bash
# Obter ConfigMap atual
kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth-backup.yaml

# Editar para adicionar usuários
kubectl edit configmap aws-auth -n kube-system
```

Adicione na seção `mapUsers`:

```yaml
data:
  mapRoles: |
    - groups:
      - system:bootstrappers
      - system:nodes
      rolearn: arn:aws:iam::ACCOUNT_ID:role/k8s-platform-eks-node-role
      username: system:node:{{EC2PrivateDNSName}}
  mapUsers: |
    - userarn: arn:aws:iam::ACCOUNT_ID:user/admin-user
      username: admin
      groups:
        - system:masters
    - userarn: arn:aws:iam::ACCOUNT_ID:user/operator-user
      username: operator
      groups:
        - k8s-platform-operator
    - userarn: arn:aws:iam::ACCOUNT_ID:user/reader-user
      username: reader
      groups:
        - k8s-platform-reader
```

> **Substitua** `ACCOUNT_ID` pelo seu AWS Account ID

---

### 5.5 Criar RoleBindings

```bash
# Binding para readers
cat > rolebinding-reader.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: k8s-platform-readers
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k8s-platform-reader
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: k8s-platform-reader
EOF

kubectl apply -f rolebinding-reader.yaml

# Binding para operators
cat > rolebinding-operator.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: k8s-platform-operators
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k8s-platform-operator
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: k8s-platform-operator
EOF

kubectl apply -f rolebinding-operator.yaml
```

---

## 7. Validação e Definition of Done

### Checklist de Validação

```bash
# 1. VPC
echo "=== VPC ==="
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=k8s-platform-prod-vpc" --query "Vpcs[0].VpcId"

# 2. Subnets
echo "=== Subnets (9 esperadas) ==="
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].[SubnetId,CidrBlock,Tags[?Key=='Name'].Value|[0]]" --output table

# 3. NAT Gateway
echo "=== NAT Gateway ==="
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[*].[NatGatewayId,State]" --output table

# 4. EKS Cluster
echo "=== EKS Cluster ==="
aws eks describe-cluster --name k8s-platform-prod --query "cluster.[name,status,version]" --output table

# 5. Node Groups
echo "=== Node Groups ==="
aws eks list-nodegroups --cluster-name k8s-platform-prod

# 6. Nodes no cluster
echo "=== Nodes (7 esperados) ==="
kubectl get nodes

# 7. StorageClass
echo "=== StorageClass (gp3 default) ==="
kubectl get storageclass

# 8. Namespaces
echo "=== Namespaces ==="
kubectl get namespaces

# 9. RBAC
echo "=== ClusterRoles ==="
kubectl get clusterroles | grep k8s-platform
```

### Definition of Done - Épico A

- [ ] **VPC e Networking**
  - [ ] VPC criada com CIDR 10.0.0.0/16
  - [ ] 9 subnets criadas (3 public + 3 private + 3 data)
  - [ ] NAT Gateway operacional
  - [ ] Internet Gateway operacional
  - [ ] S3 VPC Endpoint configurado
  - [ ] Tags de EKS nas subnets

- [ ] **EKS Cluster**
  - [ ] Cluster `k8s-platform-prod` com status `Active`
  - [ ] Versão Kubernetes 1.29+
  - [ ] Control plane logs habilitados
  - [ ] Secrets encryption habilitado
  - [ ] `kubectl cluster-info` funciona

- [ ] **Node Groups**
  - [ ] Node group `system` (2 nodes t3.medium) - Active
  - [ ] Node group `workloads` (3 nodes t3.large) - Active
  - [ ] Node group `critical` (2 nodes t3.xlarge) - Active
  - [ ] Todos os 7 nodes com status `Ready`
  - [ ] Labels corretos aplicados
  - [ ] Taints corretos aplicados (critical)

- [ ] **Storage**
  - [ ] EBS CSI Driver operacional
  - [ ] StorageClass `gp3` como default
  - [ ] PVC de teste provisionado com sucesso

- [ ] **IAM e RBAC**
  - [ ] OIDC Provider criado
  - [ ] Role para cluster funcional
  - [ ] Role para nodes funcional
  - [ ] ClusterRoles criados
  - [ ] aws-auth ConfigMap configurado

- [ ] **Documentação**
  - [ ] VPC ID documentado
  - [ ] Subnet IDs documentados
  - [ ] Security Group IDs documentados
  - [ ] Comandos de acesso documentados

---

## 8. Troubleshooting

### Problema: Nodes não aparecem

```bash
# Verificar status do node group
aws eks describe-nodegroup --cluster-name k8s-platform-prod --nodegroup-name system

# Verificar Auto Scaling Group
aws autoscaling describe-auto-scaling-groups --filters "Name=tag:eks:cluster-name,Values=k8s-platform-prod"

# Verificar instâncias EC2
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=k8s-platform-prod" --query "Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]" --output table

# Causas comuns:
# - Subnet sem rota para NAT Gateway
# - Security Group muito restritivo
# - IAM Role sem permissões
```

### Problema: Nodes em NotReady

```bash
# Verificar logs do kubelet
kubectl describe node <node-name>

# Verificar eventos
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Causas comuns:
# - CNI não instalado corretamente
# - Problema de rede (Security Group)
# - Disco cheio
```

### Problema: StorageClass não provisiona

```bash
# Verificar EBS CSI Driver
kubectl get pods -n kube-system | grep ebs

# Verificar logs do controller
kubectl logs -n kube-system -l app=ebs-csi-controller

# Causas comuns:
# - IRSA não configurado para EBS CSI
# - Zona indisponível
# - Limite de volumes EBS
```

### Problema: Acesso negado ao cluster

```bash
# Verificar identidade atual
aws sts get-caller-identity

# Verificar aws-auth ConfigMap
kubectl get configmap aws-auth -n kube-system -o yaml

# Causas comuns:
# - Usuário não mapeado no aws-auth
# - Grupo incorreto no RBAC
# - Credenciais AWS erradas
```

---

## Próximos Passos

Após concluir este documento:

1. Prosseguir para **[03-data-services-helm.md](03-data-services-helm.md)** (RDS, Redis, RabbitMQ)
2. Depois **[02-gitlab-helm-deploy.md](02-gitlab-helm-deploy.md)** (GitLab)

---

**Documento:** 01-infraestrutura-base-aws.md
**Versão:** 1.0
**Última atualização:** 2026-01-19
**Épico:** A
**Esforço:** 20 person-hours
