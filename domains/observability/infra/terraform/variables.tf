# =============================================================================
# INPUTS FROM PLATFORM PROVISIONING (Obrigatórios)
# =============================================================================

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint from platform-provisioning"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64) from platform-provisioning"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Cluster name from platform-provisioning (for authentication)"
  type        = string
}

# =============================================================================
# STORAGE CONFIGURATION (Parametrizado - Cloud-Agnostic)
# =============================================================================

variable "storage_class_name" {
  description = "Default storage class from platform-provisioning (gp3, managed-premium, pd-ssd)"
  type        = string
}

variable "storage_class_fast" {
  description = "Fast storage class from platform-provisioning (io2, premium-ssd, etc)"
  type        = string
  default     = null
}

# =============================================================================
# OBJECT STORAGE (S3-Compatible - Parametrizado)
# =============================================================================

variable "object_storage_endpoint" {
  description = "S3-compatible endpoint from platform-provisioning"
  type        = string
}

variable "s3_bucket_metrics" {
  description = "S3 bucket for Prometheus long-term metrics from platform-provisioning"
  type        = string
}

variable "s3_bucket_logs" {
  description = "S3 bucket for Loki logs from platform-provisioning"
  type        = string
}

variable "s3_bucket_traces" {
  description = "S3 bucket for Tempo traces from platform-provisioning"
  type        = string
}

variable "s3_bucket_backups" {
  description = "S3 bucket for Velero backups from platform-provisioning"
  type        = string
}

# =============================================================================
# DOMAIN CONFIGURATION
# =============================================================================

variable "environments" {
  description = "Environments to deploy (dev, hml, prd)"
  type        = list(string)
  default     = ["dev", "hml", "prd"]
}

variable "domain_name" {
  description = "Domain name for ingress (optional)"
  type        = string
  default     = ""
}

# =============================================================================
# OBSERVABILITY STACK CONFIGURATION
# =============================================================================

variable "prometheus_retention_days" {
  description = "Prometheus metrics retention (days)"
  type        = number
  default     = 15
}

variable "loki_retention_days" {
  description = "Loki logs retention (days)"
  type        = number
  default     = 7
}

variable "tempo_retention_days" {
  description = "Tempo traces retention (days)"
  type        = number
  default     = 3
}

variable "grafana_admin_password" {
  description = "Grafana admin password (use Vault/Secrets Manager)"
  type        = string
  sensitive   = true
  default     = null
}

# =============================================================================
# RESOURCE LIMITS (Cloud-Agnostic)
# =============================================================================

variable "prometheus_storage_size" {
  description = "Prometheus PVC size"
  type        = string
  default     = "50Gi"
}

variable "loki_storage_size" {
  description = "Loki PVC size"
  type        = string
  default     = "20Gi"
}

variable "tempo_storage_size" {
  description = "Tempo PVC size"
  type        = string
  default     = "10Gi"
}
