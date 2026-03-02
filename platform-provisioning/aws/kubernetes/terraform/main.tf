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
