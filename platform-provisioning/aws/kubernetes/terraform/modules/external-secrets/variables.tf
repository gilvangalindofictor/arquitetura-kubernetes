# -----------------------------------------------------------------------------
# External Secrets Operator Module Variables
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for External Secrets Operator"
  type        = string
  default     = "external-secrets-system"
}

variable "eso_chart_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "0.9.11"
}

variable "replicas" {
  description = "Number of ESO replicas"
  type        = number
  default     = 1
}

variable "vault_addr" {
  description = "Vault service address"
  type        = string
}

variable "enable_monitoring" {
  description = "Enable Prometheus ServiceMonitor"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
  default     = "staging"
}

variable "monitoring_namespace" {
  description = "Namespace for monitoring/ServiceMonitor"
  type        = string
  default     = "staging-observability-monitoring"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
