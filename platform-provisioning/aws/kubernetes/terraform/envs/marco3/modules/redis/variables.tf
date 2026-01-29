# =============================================================================
# Redis Module Variables
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Redis deployment"
  type        = string
  default     = "default"
}

variable "replicas" {
  description = "Number of Redis replicas"
  type        = number
  default     = 2
}

variable "pvc_size" {
  description = "Redis PVC size (per pod)"
  type        = string
  default     = "8Gi"
}

variable "storage_class" {
  description = "Storage class for PVCs"
  type        = string
  default     = "gp2"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
