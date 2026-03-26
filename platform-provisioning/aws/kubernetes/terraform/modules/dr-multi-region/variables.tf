# =============================================================================
# DR Multi-Region Module — Variables
# GAP-012 Phase 2: VPC + RDS Read Replica in us-west-2
# =============================================================================

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster. Used to scope resource names and tags."
  type        = string
}

variable "environment" {
  description = "Environment name (staging, production). Used in resource names and tags."
  type        = string
}

# ---------------------------------------------------------------------------
# Region configuration
# ---------------------------------------------------------------------------

variable "primary_region" {
  description = "AWS region of the primary infrastructure (us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "AWS region for the DR site (us-west-2)"
  type        = string
  default     = "us-west-2"
}

# ---------------------------------------------------------------------------
# DR VPC configuration (us-west-2)
# ---------------------------------------------------------------------------

variable "dr_vpc_cidr" {
  description = "CIDR block for the DR VPC in us-west-2. Must NOT overlap with primary VPC (10.0.0.0/16). Default 10.1.0.0/16 mirrors structure with offset."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.dr_vpc_cidr, 0))
    error_message = "dr_vpc_cidr must be a valid CIDR block (e.g., 10.1.0.0/16)."
  }
}

variable "dr_public_subnets" {
  description = "Public subnet configurations for DR VPC. Minimum 2 AZs required for RDS subnet group."
  type = list(object({
    cidr_block        = string
    availability_zone = string
    name_suffix       = string
  }))
  default = [
    {
      cidr_block        = "10.1.1.0/24"
      availability_zone = "us-west-2a"
      name_suffix       = "public-2a"
    },
    {
      cidr_block        = "10.1.2.0/24"
      availability_zone = "us-west-2b"
      name_suffix       = "public-2b"
    }
  ]
}

variable "dr_private_subnets" {
  description = "Private subnet configurations for DR VPC. Used for RDS read replica and future EKS DR cluster."
  type = list(object({
    cidr_block        = string
    availability_zone = string
    name_suffix       = string
  }))
  default = [
    {
      cidr_block        = "10.1.10.0/24"
      availability_zone = "us-west-2a"
      name_suffix       = "private-2a"
    },
    {
      cidr_block        = "10.1.11.0/24"
      availability_zone = "us-west-2b"
      name_suffix       = "private-2b"
    },
    {
      cidr_block        = "10.1.12.0/24"
      availability_zone = "us-west-2c"
      name_suffix       = "private-2c"
    }
  ]
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway in the DR VPC for outbound internet from private subnets. Set false to save cost when only RDS replica is needed."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# VPC Peering (primary <-> DR)
# ---------------------------------------------------------------------------

variable "enable_vpc_peering" {
  description = "Create a VPC peering connection between primary (us-east-1) and DR (us-west-2) VPCs. Required for cross-VPC access and future EKS DR."
  type        = bool
  default     = true
}

variable "primary_vpc_id" {
  description = "VPC ID of the primary cluster in us-east-1. Required when enable_vpc_peering = true."
  type        = string
  default     = ""
}

variable "primary_vpc_cidr" {
  description = "CIDR block of the primary VPC in us-east-1. Used for route table entries in the DR VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# ---------------------------------------------------------------------------
# RDS Read Replica
# ---------------------------------------------------------------------------

variable "enable_rds_replica" {
  description = "Create an RDS cross-region read replica in us-west-2. Requires VPC + private subnets to be created first."
  type        = bool
  default     = true
}

variable "source_db_identifier" {
  description = "DB instance identifier of the primary RDS instance in us-east-1 to replicate (e.g., 'k8s-platform-prod-postgresql')"
  type        = string
}

variable "replica_instance_class" {
  description = "RDS instance class for the read replica. Default db.t4g.medium balances cost (~$47/month) with replication throughput."
  type        = string
  default     = "db.t4g.medium"
}

variable "replica_max_allocated_storage" {
  description = "Maximum storage autoscaling limit in GB for the read replica"
  type        = number
  default     = 100
}

variable "replica_backup_retention_period" {
  description = "Number of days to retain automated backups on the replica (enables point-in-time restore after promotion)"
  type        = number
  default     = 7
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

variable "enable_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for RDS replication lag, storage, and availability"
  type        = bool
  default     = true
}

variable "replication_lag_threshold_seconds" {
  description = "Seconds of replication lag that triggers the CloudWatch alarm. SLA target < 60s."
  type        = number
  default     = 60
}

variable "create_sns_topic" {
  description = "When true, creates a dedicated SNS topic for DR alerts. When false, uses existing_sns_topic_arn."
  type        = bool
  default     = true
}

variable "existing_sns_topic_arn" {
  description = "ARN of an existing SNS topic for DR alerts. Used when create_sns_topic = false."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Optional email address to subscribe to DR alerts SNS topic. Leave empty to skip."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources created by this module"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days for RDS DR replica logs (postgresql, upgrade). Default 14d — Mesa Técnica CloudWatch 2026-03-24."
  type        = number
  default     = 14
}
