# =============================================================================
# S3 Buckets Module Variables
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

# TASK-004: FCT Proposals Bucket
variable "enable_fct_proposals" {
  description = "Enable FCT proposals bucket creation (TASK-004)"
  type        = bool
  default     = false
}

variable "fct_proposals_region" {
  description = "AWS region for fct-proposals bucket (sa-east-1 for LGPD compliance)"
  type        = string
  default     = "sa-east-1"
}
