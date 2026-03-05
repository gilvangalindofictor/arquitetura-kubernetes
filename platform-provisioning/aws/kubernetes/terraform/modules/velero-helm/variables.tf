# =============================================================================
# Velero Helm Release Module — Variables
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name (used for tagging and resource identification)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where Velero is deployed"
  type        = string
  default     = "velero"
}

variable "chart_version" {
  description = "Velero Helm chart version to deploy"
  type        = string
  default     = "8.1.0"
}

variable "irsa_role_arn" {
  description = "IAM role ARN for Velero IRSA (output from velero-dr module: velero_role_arn)"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for Velero backups (output from velero-dr module: bucket_name)"
  type        = string
}

variable "s3_region" {
  description = "AWS region of the primary S3 backup bucket"
  type        = string
  default     = "us-east-1"
}

variable "node_selector" {
  description = "Node selector for the Velero server deployment"
  type        = map(string)
  default = {
    workload = "applications"
  }
}

variable "tolerations" {
  description = "Tolerations for the Velero server deployment"
  type = list(object({
    key      = optional(string)
    operator = string
    value    = optional(string)
    effect   = optional(string)
  }))
  default = [
    {
      key      = "workload"
      operator = "Equal"
      value    = "platform"
      effect   = "NoSchedule"
    }
  ]
}

variable "velero_plugin_aws_version" {
  description = "Velero AWS plugin image tag"
  type        = string
  default     = "v1.11.0"
}

variable "log_level" {
  description = "Velero server log level (debug, info, warning, error)"
  type        = string
  default     = "info"
}

variable "backup_retention_period" {
  description = "Default backup retention period (e.g. 720h for 30 days)"
  type        = string
  default     = "720h"
}

variable "deploy_node_agent" {
  description = "Deploy the Velero node-agent DaemonSet (required for file-system backups)"
  type        = bool
  default     = true
}

variable "enable_csi" {
  description = "Enable CSI snapshot support feature flag"
  type        = bool
  default     = true
}

variable "metrics_enabled" {
  description = "Enable Prometheus metrics endpoint"
  type        = bool
  default     = true
}

variable "service_monitor_enabled" {
  description = "Create a ServiceMonitor for kube-prometheus-stack scraping"
  type        = bool
  default     = true
}

variable "service_monitor_labels" {
  description = "Additional labels for the ServiceMonitor (must match Prometheus selector)"
  type        = map(string)
  default = {
    release = "kube-prometheus-stack"
  }
}
