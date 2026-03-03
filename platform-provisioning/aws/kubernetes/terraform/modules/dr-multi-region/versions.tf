# =============================================================================
# DR Multi-Region Module — Provider Requirements
# GAP-012 Phase 2: VPC + RDS Read Replica in us-west-2
# =============================================================================
# This module provisions resources in TWO AWS regions:
#   - aws         (default) = us-east-1 (primary, for data lookups)
#   - aws.dr      = us-west-2 (DR site, where VPC + subnets are created)
#
# The calling root module must pass the DR provider:
#
#   provider "aws" {
#     alias  = "dr"
#     region = "us-west-2"
#   }
#
#   module "dr_multi_region" {
#     source = "./modules/dr-multi-region"
#     providers = {
#       aws    = aws
#       aws.dr = aws.dr
#     }
#     ...
#   }
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [aws.dr]
    }
  }
}
