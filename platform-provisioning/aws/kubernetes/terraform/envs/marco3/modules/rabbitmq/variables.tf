# =============================================================================
# RabbitMQ Module Variables
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for RabbitMQ deployment"
  type        = string
  default     = "default"
}

variable "replicas" {
  description = "Number of RabbitMQ nodes in cluster"
  type        = number
  default     = 3
}

variable "pvc_size" {
  description = "RabbitMQ PVC size per node"
  type        = string
  default     = "10Gi"
}

variable "storage_class" {
  description = "Storage class for PVCs"
  type        = string
  default     = "gp2"
}

variable "enable_monitoring" {
  description = "Enable Prometheus ServiceMonitor"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
