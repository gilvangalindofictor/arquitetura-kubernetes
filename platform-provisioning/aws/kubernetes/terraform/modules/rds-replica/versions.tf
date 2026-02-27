terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      # This module provisions all resources in the replica region (us-west-2).
      # The calling environment must pass the replica provider alias:
      #
      #   provider "aws" {
      #     alias  = "us-west-2"
      #     region = "us-west-2"
      #   }
      #
      #   module "rds_replica_staging" {
      #     source = "../../modules/rds-replica"
      #     providers = {
      #       aws = aws.us-west-2
      #     }
      #     ...
      #   }
      #
      # Note: data.aws_db_instance.primary cross-region lookup is performed via
      # the default provider (us-east-1) by Terraform; the replica resources use
      # the aliased provider passed by the caller.
    }
  }
}
