terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

# Get EKS cluster info
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

# Get VPC information directly (VPC was created manually, not via Terraform)
data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
}

# Import EKS data from Marco1 (if needed)
data "terraform_remote_state" "marco1" {
  backend = "s3"
  config = {
    bucket = "terraform-state-marco0-891377105802"
    key    = "marco1/terraform.tfstate"
    region = "us-east-1"
  }
}

# PostgreSQL RDS Module
module "postgresql" {
  source = "./modules/postgresql"

  cluster_name          = var.cluster_name
  vpc_id                = var.vpc_id
  vpc_cidr              = data.aws_vpc.existing.cidr_block
  private_subnet_ids    = data.aws_subnets.private.ids
  instance_class        = var.postgresql_instance_class
  allocated_storage     = var.postgresql_allocated_storage
  max_allocated_storage = var.postgresql_max_allocated_storage
  common_tags           = var.common_tags
}

# Redis Module
module "redis" {
  source = "./modules/redis"

  cluster_name  = var.cluster_name
  replicas      = var.redis_replicas
  pvc_size      = var.redis_pvc_size
  storage_class = "gp2"
  common_tags   = var.common_tags
}

# RabbitMQ Module
module "rabbitmq" {
  source = "./modules/rabbitmq"

  cluster_name  = var.cluster_name
  replicas      = var.rabbitmq_replicas
  pvc_size      = var.rabbitmq_pvc_size
  storage_class = "gp2"
  common_tags   = var.common_tags
}

# S3 Buckets Module
module "s3_buckets" {
  source = "./modules/s3-buckets"

  cluster_name   = var.cluster_name
  aws_account_id = var.aws_account_id
  common_tags    = var.common_tags
}
