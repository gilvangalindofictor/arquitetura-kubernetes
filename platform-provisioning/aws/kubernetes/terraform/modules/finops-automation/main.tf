# 💰 FinOps Automation - Main Resources
# Multi-agent validated: AWS, Terraform, FinOps, Security specialists
# ADR-024: EventBridge + Lambda architecture chosen vs CronJobs/Instance Scheduler

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local variables for resource naming
locals {
  name_prefix = "finops-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Owner       = "DevOps-Team"
    }
  )

  # Security Specialist requirement: Security tags validation
  required_tags = [
    "Project",
    "Environment",
    "ManagedBy",
    "SecurityReview",
    "Compliance",
    "DataClassification",
    "Owner"
  ]
}

# Validate required tags exist
resource "null_resource" "validate_tags" {
  lifecycle {
    precondition {
      condition = alltrue([
        for tag in local.required_tags :
        contains(keys(local.common_tags), tag)
      ])
      error_message = "Missing required security tags: ${join(", ", [for tag in local.required_tags : tag if !contains(keys(local.common_tags), tag)])}"
    }
  }
}
