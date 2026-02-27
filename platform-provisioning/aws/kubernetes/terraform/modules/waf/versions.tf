# =============================================================================
# WAF Module - Provider Version Constraints
# GAP-010: AWS WAF v2 + DDoS Protection for iPaaS ALB
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
