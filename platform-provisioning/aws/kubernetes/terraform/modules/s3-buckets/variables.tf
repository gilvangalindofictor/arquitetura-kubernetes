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

# DEC-2026-03-24: GitLab Artifacts Bucket (shared — managed by prod state)
# Set to false in staging to avoid duplicate management of k8s-platform-gitlab-artifacts-ACCOUNT
# Set to true (default) in prod — the single source of truth for this bucket
variable "enable_gitlab_artifacts" {
  description = "Enable GitLab artifacts bucket and IAM policy creation. Set to false in staging since the bucket is shared and managed by the prod state (module.s3_buckets_prod). Default: true."
  type        = bool
  default     = true
}

