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

  # Core configuration
  environment     = "staging"
  cluster_name    = var.cluster_name
  rds_instance_id = var.rds_instance_identifier
  asg_names       = var.asg_names

  # Schedules (BRT timezone = UTC-3)
  # Shutdown: 18:00 BRT = 21:00 UTC Monday-Friday
  # Startup:  08:00 BRT = 11:00 UTC Monday-Friday
  startup_schedule  = "cron(0 11 ? * MON-FRI *)"
  shutdown_schedule = "cron(0 21 ? * MON-FRI *)"

  # Automation ENABLED after successful SNS + manual testing (5/5 tests passed)
  enable_automation = true

  # Lambda configuration
  lambda_timeout = 300 # 5 minutes
  lambda_memory  = 512
  lambda_runtime = "python3.11"

  # Circuit breaker
  circuit_breaker_threshold = 3

  # Monitoring & Notifications
  enable_cloudwatch_alarms   = true
  startup_duration_threshold = 600 # 10 minutes
  enable_sns_notifications   = true
  notification_emails        = ["gilvan.galindo@fctconsig.com.br"]
  sns_topic_arn              = "" # Module will create SNS topic automatically

  # Node groups configuration (startup target sizes)
  node_groups_config = {
    system = {
      min_size     = 0
      desired_size = 2
      max_size     = 4
    }
    workloads = {
      min_size     = 0
      desired_size = 3
      max_size     = 6
    }
    critical = {
      min_size     = 0
      desired_size = 2
      max_size     = 4
    }
  }

  # Ownership tags
  owner_email = "devops-team@company.com"
  cost_center = "Infrastructure-Optimization"

  # Additional tags (merged with module security tags)
  tags = {
    Project     = "FinOps-Automation"
    Environment = "staging"
    ManagedBy   = "Terraform"
    Deployment  = "executor-terraform.md"
  }
}
