# =============================================================================
# VARIABLES - Cluster Autoscaler Module
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to install Cluster Autoscaler"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "cluster-autoscaler"
}

variable "chart_version" {
  description = "Version of the cluster-autoscaler Helm chart"
  type        = string
  default     = "9.37.0"
}

variable "kubernetes_version" {
  description = "Kubernetes version (e.g., 1.31) - used for image tag matching"
  type        = string
}

# -----------------------------------------------------------------------------
# Autoscaling Configuration
# -----------------------------------------------------------------------------

variable "scale_down_enabled" {
  description = "Enable scale-down of nodes"
  type        = bool
  default     = true
}

variable "scale_down_delay_after_add" {
  description = "How long after scale up that scale down evaluation resumes"
  type        = string
  default     = "10m" # Wait 10 minutes after scaling up
}

variable "scale_down_unneeded_time" {
  description = "How long a node should be unneeded before it is eligible for scale down"
  type        = string
  default     = "10m" # Conservative: 10 minutes
}

variable "scale_down_utilization_threshold" {
  description = "Node utilization level below which a node can be considered for scale down"
  type        = string
  default     = "0.5" # 50% utilization threshold
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags for AWS resources"
  type        = map(string)
  default     = {}
}
