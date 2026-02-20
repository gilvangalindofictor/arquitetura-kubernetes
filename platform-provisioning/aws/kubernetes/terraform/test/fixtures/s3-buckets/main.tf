# =============================================================================
# S3 Buckets Module Test Fixture
# Used by S3 integration tests (requires AWS credentials)
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.sa_east_1]
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

provider "aws" {
  alias  = "sa_east_1"
  region = "sa-east-1"

  default_tags {
    tags = {
      Environment = "terratest"
      ManagedBy   = "terratest"
      Project     = "dt-003-iac-testing"
    }
  }
}

# Note: Uncomment for full integration tests
# module "s3_buckets" {
#   source = "../../../modules/s3-buckets"
#
#   providers = {
#     aws           = aws
#     aws.sa_east_1 = aws.sa_east_1
#   }
#
#   cluster_name         = "terratest-dt003"
#   aws_account_id       = "123456789012"
#   enable_fct_proposals = false
#   common_tags = {
#     Environment = "terratest"
#     ManagedBy   = "terratest"
#   }
# }
