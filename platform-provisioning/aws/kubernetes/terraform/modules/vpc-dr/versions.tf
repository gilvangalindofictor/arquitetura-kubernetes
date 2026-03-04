terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      # This module deploys exclusively to the DR region via provider alias "aws.dr".
      # The calling environment must pass an aliased provider:
      #
      #   provider "aws" {
      #     alias  = "us-west-2"
      #     region = "us-west-2"
      #   }
      #
      #   module "vpc_dr_staging" {
      #     source = "../../modules/vpc-dr"
      #     providers = {
      #       aws.dr = aws.us-west-2
      #     }
      #     environment          = "staging"
      #     db_subnet_group_name = "k8s-platform-dr-db-subnet-group"
      #   }
      #
      # Outputs (vpc_id, db_subnet_group_name) feed into the rds-replica module.
      configuration_aliases = [aws.dr]
    }
  }
}
