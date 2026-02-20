# =============================================================================
# VPC Module Test Fixture
# Used by VPC integration tests (requires AWS credentials)
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "terratest"
      ManagedBy   = "terratest"
      Project     = "dt-003-iac-testing"
    }
  }
}

module "vpc" {
  source   = "../../../modules/vpc"
  vpc_cidr = "10.99.0.0/16"
  vpc_name = "terratest-vpc-dt003"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr
}
