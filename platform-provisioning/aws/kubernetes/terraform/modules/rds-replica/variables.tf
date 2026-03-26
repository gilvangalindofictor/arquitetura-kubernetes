# =============================================================================
# RDS Cross-Region Read Replica Module — Variables
# GAP-012: Disaster Recovery Multi-Region
# =============================================================================

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster. Used to scope IAM and resource names."
  type        = string
}

variable "environment" {
  description = "Environment label (staging, production). Used in resource names and tags."
  type        = string
}

# ---------------------------------------------------------------------------
# Source (primary) RDS instance
# ---------------------------------------------------------------------------

variable "source_db_identifier" {
  description = "DB instance identifier of the primary RDS instance to replicate from (e.g. 'k8s-platform-prod-postgresql')"
  type        = string
}

# ---------------------------------------------------------------------------
# Replica region
# ---------------------------------------------------------------------------

variable "replica_region" {
  description = "AWS region where the read replica will be created (DR site)"
  type        = string
  default     = "us-west-2"
}

# ---------------------------------------------------------------------------
# Replica instance configuration
# ---------------------------------------------------------------------------

variable "replica_instance_class" {
  description = "RDS instance class for the read replica. Default db.t4g.medium balances cost (~$47/month) with replication throughput."
  type        = string
  default     = "db.t4g.medium"
}

variable "max_allocated_storage" {
  description = "Maximum storage autoscaling limit in GB for the replica"
  type        = number
  default     = 100
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups on the replica. Backups enable point-in-time restore after promotion."
  type        = number
  default     = 7
}

# ---------------------------------------------------------------------------
# Networking — must be in the replica region (us-west-2)
# ---------------------------------------------------------------------------

variable "replica_vpc_id" {
  description = "VPC ID in the replica region (us-west-2) where the DB subnet group and security group will be created"
  type        = string
}

variable "replica_subnet_ids" {
  description = "List of private subnet IDs in the replica region for the DB subnet group (minimum 2 AZs required by AWS)"
  type        = list(string)
}

variable "replica_allowed_cidrs" {
  description = "CIDR blocks allowed to connect to the replica on port 5432 (typically the DR VPC private subnet CIDRs)"
  type        = list(string)
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

variable "enable_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for replication lag, storage space, and replica availability"
  type        = bool
  default     = true
}

variable "replication_lag_threshold_seconds" {
  description = "Seconds of replication lag that triggers the CloudWatch alarm. SLA target is < 60s."
  type        = number
  default     = 60
}

variable "storage_free_threshold_bytes" {
  description = "Free storage space (in bytes) below which the storage alarm fires. Default 4 GB = 4294967296 bytes."
  type        = number
  default     = 4294967296 # 4 GB
}

variable "create_sns_topic" {
  description = "When true, creates a dedicated SNS topic for replica alarms. When false, uses existing_sns_topic_arn."
  type        = bool
  default     = false
}

variable "existing_sns_topic_arn" {
  description = "ARN of an existing SNS topic for replica alerts. Used when create_sns_topic = false."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Optional email address to subscribe to the SNS topic for DR alerts. Leave empty to skip email subscription."
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
  description = "CloudWatch log group retention in days for RDS replica logs (postgresql, upgrade). Default 14d — Mesa Técnica CloudWatch 2026-03-24."
  type        = number
  default     = 14
}
