# Platform Provisioning - AWS EKS Cluster
# Terraform configuration for provisioning AWS infrastructure

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration (uncomment when ready for remote state)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "platform-provisioning/aws/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project      = "kubernetes-platform"
      ManagedBy    = "terraform"
      Repository   = "platform-provisioning-aws"
      Provisioning = "cluster"
    }
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  vpc_name = var.vpc_name
  region   = var.aws_region
}

# EKS Module
module "eks" {
  source = "./modules/eks"

  cluster_name = var.cluster_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnet_ids
}

# S3 Buckets for long-term storage (used by all domains)
module "s3" {
  source = "./modules/s3"

  project_name = "kubernetes-platform"
  buckets      = var.s3_buckets
}

# IAM Roles for Kubernetes Service Accounts (IRSA)
module "iam" {
  source = "./modules/iam"

  project_name      = "kubernetes-platform"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.cluster_oidc_issuer_url
  s3_bucket_arns    = module.s3.bucket_arns
  namespaces        = var.kubernetes_namespaces

  depends_on = [module.eks, module.s3]
}

# Argo Rollouts — Progressive Delivery (CICD-005 / ADR-085)
# Co-located in argocd namespace (namespace managed by argocd module)
# Canary + Blue-Green strategies with Prometheus-driven automated rollback
# Deploy AFTER argocd module (namespace must exist)
module "argo_rollouts" {
  source = "./modules/argo-rollouts"

  cluster_name        = var.cluster_name
  namespace           = "argocd"
  chart_version       = "2.35.0"
  controller_replicas = 2 # HA
  metrics_enabled     = true
  dashboard_enabled   = true
  prometheus_url      = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
  dashboard_port      = 3100
  metrics_port        = 8090

  # Uncomment when argocd module is added to this file:
  # depends_on = [module.argocd]
}

# =============================================================================
# DR Multi-Region — GAP-012 Phase 2 (ADR-090)
# =============================================================================
# Provisions VPC + RDS read replica in us-west-2 for disaster recovery.
# Phase 1 (S3 CRR + Velero) is deployed via velero-dr module.
#
# >>> Uncomment when us-west-2 VPC approved by CTO <<<
# >>> Prerequisites: Review ADR-090, confirm CIDR allocation, cost approval <<<
#
# provider "aws" {
#   alias  = "dr"
#   region = "us-west-2"
#
#   default_tags {
#     tags = {
#       Project      = "kubernetes-platform"
#       ManagedBy    = "terraform"
#       Repository   = "platform-provisioning-aws"
#       Provisioning = "dr-multi-region"
#     }
#   }
# }
#
# module "dr_multi_region" {
#   source = "./modules/dr-multi-region"
#
#   providers = {
#     aws    = aws
#     aws.dr = aws.dr
#   }
#
#   cluster_name         = var.cluster_name
#   environment          = "staging"
#   primary_region       = "us-east-1"
#   dr_region            = "us-west-2"
#
#   # DR VPC — 10.1.0.0/16 (non-overlapping with primary 10.0.0.0/16)
#   dr_vpc_cidr          = "10.1.0.0/16"
#   enable_nat_gateway   = false  # Enable when EKS DR cluster is deployed
#
#   # VPC Peering — primary <-> DR
#   enable_vpc_peering   = true
#   primary_vpc_id       = module.vpc.vpc_id
#   primary_vpc_cidr     = "10.0.0.0/16"
#
#   # RDS Read Replica — cross-region PostgreSQL
#   enable_rds_replica       = true
#   source_db_identifier     = "k8s-platform-prod-postgresql"
#   replica_instance_class   = "db.t4g.medium"
#   replica_max_allocated_storage   = 100
#   replica_backup_retention_period = 7
#
#   # Monitoring
#   enable_cloudwatch_alarms = true
#   create_sns_topic         = true
#   alert_email              = "gilvan.galindo@fctconsig.com.br"
#
#   common_tags = {
#     GAP         = "GAP-012"
#     Phase       = "Phase-2"
#     Environment = "staging"
#   }
#
#   depends_on = [module.vpc, module.eks]
# }
