variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs for Security Group ingress (least privilege)"
  type        = list(string)
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small" # FinOps: Start small, scale up when needed ($315.36/year saved)
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Max allocated storage in GB"
  type        = number
  default     = 500
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for RDS (doubles compute cost). Recommended: false for staging, true for production."
  type        = bool
  default     = false # FinOps: Single-AZ default, override per environment (DT-004)
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "master_password_override" {
  description = "Override for the master password (used when RDS was created outside TF with a different password)"
  type        = string
  default     = null
  sensitive   = true
}

variable "additional_databases" {
  description = "List of additional databases to create (with user/password)"
  type = list(object({
    name     = string
    username = string
    password = string
  }))
  default = []
}

variable "deletion_protection" {
  description = "Enable deletion protection for RDS instance (DT-004). Recommended: true for production, false for staging."
  type        = bool
  default     = false
}

variable "allow_major_version_upgrade" {
  description = "Allow major version upgrades for RDS instance (INFRA-002). Required for PostgreSQL 14→16 upgrade. Set to true only during planned upgrade windows."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply RDS modifications immediately instead of during next maintenance window (INFRA-002). Set to true only during planned upgrade windows to avoid unexpected downtime."
  type        = bool
  default     = false
}
