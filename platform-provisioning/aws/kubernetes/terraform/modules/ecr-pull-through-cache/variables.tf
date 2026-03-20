#------------------------------------------------------------------------------
# Variables — ECR Pull-Through Cache Module
#------------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for ECR and VPC endpoints"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID for ECR ARN construction"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name, used for resource naming"
  type        = string
}

variable "node_role_name" {
  description = "IAM role name of EKS worker nodes (for policy attachment)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for VPC endpoints"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for VPC endpoint ENIs"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for VPC endpoints"
  type        = list(string)
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

# --- Feature Flags ---

variable "enable_vpc_endpoints" {
  description = "Create VPC endpoints for ECR API and DKR"
  type        = bool
  default     = true
}

variable "enable_ecr_public" {
  description = "Enable pull-through cache for ECR Public (public.ecr.aws)"
  type        = bool
  default     = true
}

variable "enable_quay" {
  description = "Enable pull-through cache for Quay.io"
  type        = bool
  default     = true
}

variable "enable_ghcr" {
  description = "Enable pull-through cache for GitHub Container Registry (ghcr.io)"
  type        = bool
  default     = true
}

variable "enable_k8s" {
  description = "Enable pull-through cache for Kubernetes Registry (registry.k8s.io)"
  type        = bool
  default     = true
}

variable "enable_docker_hub" {
  description = "Enable pull-through cache for Docker Hub (registry-1.docker.io)"
  type        = bool
  default     = false
}

variable "docker_hub_username" {
  description = "Docker Hub username for authenticated pulls"
  type        = string
  default     = ""
  sensitive   = true
}

variable "docker_hub_access_token" {
  description = "Docker Hub access token (PAT) for authenticated pulls"
  type        = string
  default     = ""
  sensitive   = true
}
