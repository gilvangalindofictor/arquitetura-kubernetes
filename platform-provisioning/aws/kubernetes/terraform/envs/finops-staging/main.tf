# FinOps Automation - STAGING Environment
# Automated start/stop for k8s-platform-prod cluster (STAGING usage)
# Economy target: R$ 360/mês (R$ 4.320/ano) - ROI 43.6% Year 1

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "FinOps-Automation"
      Environment = "staging"
      ManagedBy   = "Terraform"
      Owner       = "DevOps-Team"
      CostCenter  = "Platform-Infrastructure"
    }
  }
}

# Data sources for cluster information
data "aws_eks_cluster" "platform" {
  name = var.cluster_name
}

data "aws_autoscaling_groups" "eks_nodes" {
  filter {
    name   = "tag:eks:cluster-name"
    values = [var.cluster_name]
  }
}

# FinOps Automation Module
module "finops_automation" {
  source = "../../modules/finops-automation"

  environment             = "staging"
  cluster_name            = var.cluster_name
  rds_instance_identifier = var.rds_instance_identifier
  asg_names               = var.asg_names

  # Schedules (BRT timezone = UTC-3)
  # Shutdown: 18:00 BRT = 21:00 UTC Monday-Friday
  # Startup:  08:00 BRT = 11:00 UTC Monday-Friday
  shutdown_schedule = "cron(0 21 ? * MON-FRI *)"
  startup_schedule  = "cron(0 11 ? * MON-FRI *)"

  # Circuit breaker configuration
  circuit_breaker_threshold = 3

  # Lambda configuration
  lambda_timeout = 900 # 15 minutes (RDS startup can take 3-5 min)
  lambda_memory  = 512
  lambda_runtime = "python3.12"

  # CloudWatch configuration
  cloudwatch_logs_retention_days   = 30
  alarm_startup_duration_threshold = 600 # 10 minutes

  # Feature flags
  enable_brasilapi_holidays = true
  health_check_enabled      = true

  # Security tags (mandatory)
  tags = {
    Project            = "FinOps-Automation"
    Environment        = "staging"
    ManagedBy          = "Terraform"
    SecurityReview     = "2026-01-30"
    Compliance         = "LGPD-OK"
    DataClassification = "Internal"
    CriticalityTier    = "Medium"
    Owner              = "DevOps-Team"
  }
}
