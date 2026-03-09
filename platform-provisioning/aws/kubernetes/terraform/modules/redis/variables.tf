# =============================================================================
# Redis Module Variables
# COMPATÍVEL COM VERSÃO BITNAMI (zero breaking changes)
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Redis deployment"
  type        = string
  default     = "data-services"
}

variable "replicas" {
  description = "Number of Redis replicas (master + replicas total)"
  type        = number
  default     = 3
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

variable "monitoring_namespace" {
  description = "Kubernetes namespace where Prometheus/kube-prometheus-stack is deployed"
  type        = string
  default     = "monitoring"
}

variable "tolerations" {
  description = "Tolerations for Redis pods (scheduling on tainted nodes)"
  type = list(object({
    key      = string
    operator = string
    effect   = string
    value    = optional(string)
  }))
  default = []
}
