# -----------------------------------------------------------------------------
# VPN Site-to-Site Module - Provider Version Constraints
# Fase 7: FortiGate VPN connection to AWS VPC
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
