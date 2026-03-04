# =============================================================================
# VPC DR Module — Variables
# GAP-012: Disaster Recovery Multi-Region (Phase 2)
# =============================================================================

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix used in all resource names (e.g. 'k8s-platform')"
  type        = string
  default     = "k8s-platform"
}

variable "environment" {
  description = "Environment name (staging, production). Used in resource tags."
  type        = string
}

# ---------------------------------------------------------------------------
# Region
# ---------------------------------------------------------------------------

variable "dr_region" {
  description = "AWS region for the DR VPC (destination region for RDS replica and Velero CRR)"
  type        = string
  default     = "us-west-2"
}

# ---------------------------------------------------------------------------
# Network CIDRs
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the DR VPC. Must not overlap with primary VPC (10.0.0.0/16)."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block (e.g. '10.1.0.0/16')."
  }
}

variable "rds_subnet_cidr_az_a" {
  description = "CIDR block for the RDS private subnet in AZ-a of the DR region."
  type        = string
  default     = "10.1.128.0/20"

  validation {
    condition     = can(cidrnetmask(var.rds_subnet_cidr_az_a))
    error_message = "rds_subnet_cidr_az_a must be a valid CIDR block (e.g. '10.1.128.0/20')."
  }
}

variable "rds_subnet_cidr_az_b" {
  description = "CIDR block for the RDS private subnet in AZ-b of the DR region."
  type        = string
  default     = "10.1.144.0/20"

  validation {
    condition     = can(cidrnetmask(var.rds_subnet_cidr_az_b))
    error_message = "rds_subnet_cidr_az_b must be a valid CIDR block (e.g. '10.1.144.0/20')."
  }
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------

variable "db_subnet_group_name" {
  description = "Name of the RDS DB subnet group created in the DR region."
  type        = string
  default     = "k8s-platform-dr-db-subnet-group"
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Common tags applied to all resources. Merged with module-specific tags."
  type        = map(string)
  default = {
    Project     = "k8s-platform"
    ManagedBy   = "terraform"
    Environment = "production"
    Purpose     = "dr-region"
  }
}
