# -----------------------------------------------------------------------------
# VPA Module Variables
# -----------------------------------------------------------------------------

variable "release_name" {
  description = "Helm release name for VPA"
  type        = string
  default     = "vpa"
}

variable "chart_version" {
  description = "VPA Helm chart version"
  type        = string
  default     = "4.4.6"
}

variable "namespace" {
  description = "Kubernetes namespace for VPA components"
  type        = string
  default     = "kube-system"
}

variable "recommender_enabled" {
  description = "Enable VPA recommender component (computes resource recommendations)"
  type        = bool
  default     = true
}

variable "updater_enabled" {
  description = "Enable VPA updater component (auto-applies recommendations - use with caution)"
  type        = bool
  default     = false
}

variable "admission_controller_enabled" {
  description = "Enable VPA admission controller (mutates pod specs on creation)"
  type        = bool
  default     = false
}

variable "prometheus_address" {
  description = "Prometheus service address for metrics storage backend"
  type        = string
  default     = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
