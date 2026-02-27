terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      # This module uses a provider alias "aws.replica" for the us-west-2 bucket.
      # The calling environment must pass a provider block with that alias:
      #
      #   provider "aws" {
      #     alias  = "replica"
      #     region = "us-west-2"
      #   }
      #
      #   module "velero_dr_staging" {
      #     source = "../../modules/velero-dr"
      #     providers = {
      #       aws         = aws
      #       aws.replica = aws.us-west-2
      #     }
      #     ...
      #   }
      configuration_aliases = [aws.replica]
    }
  }
}
