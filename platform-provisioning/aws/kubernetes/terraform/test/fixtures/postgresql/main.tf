# =============================================================================
# PostgreSQL Module Test Fixture
# Used by PostgreSQL integration tests (requires AWS credentials + VPC)
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
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

# Note: The PostgreSQL provider cannot be configured at plan time
# because it needs the RDS endpoint which doesn't exist yet.
# This fixture is primarily used for `terraform validate` and `terraform plan`.

variable "vpc_id" {
  description = "Pre-existing VPC ID for testing"
  type        = string
  default     = "vpc-test123"
}

variable "private_subnet_ids" {
  description = "Pre-existing subnet IDs for testing"
  type        = list(string)
  default     = ["subnet-test1", "subnet-test2"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.99.1.0/24", "10.99.2.0/24"]
}

# Note: Full module instantiation requires a real VPC and subnets.
# This fixture is for validation purposes.
# Uncomment for full integration tests:
#
# module "postgresql" {
#   source               = "../../../modules/postgresql"
#   cluster_name         = "terratest-dt003"
#   vpc_id               = var.vpc_id
#   vpc_cidr             = "10.99.0.0/16"
#   private_subnet_ids   = var.private_subnet_ids
#   private_subnet_cidrs = var.private_subnet_cidrs
#   instance_class       = "db.t3.micro"
#   allocated_storage    = 20
#   max_allocated_storage = 50
#   common_tags = {
#     Environment = "terratest"
#     ManagedBy   = "terratest"
#   }
# }
