# -----------------------------------------------------------------------------
# Vault Module Variables
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Kubernetes namespace for Vault"
  type        = string
  default     = "vault-system"
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  type        = string
}

variable "vault_chart_version" {
  description = "Vault Helm chart version"
  type        = string
  default     = "0.27.0"
}

variable "replicas" {
  description = "Number of Vault replicas (1 for staging, 3 for prod)"
  type        = number
  default     = 1
}

variable "storage_class" {
  description = "Storage class for Vault PVCs"
  type        = string
  default     = "gp2"
}

variable "pvc_size" {
  description = "Size of Vault PVC"
  type        = string
  default     = "10Gi"
}

variable "enable_monitoring" {
  description = "Enable Prometheus ServiceMonitor"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for Vault server pods"
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}
