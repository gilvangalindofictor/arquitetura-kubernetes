# =============================================================================
# DATA SERVICES DOMAIN - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# CLUSTER INPUTS (from platform-provisioning)
# -----------------------------------------------------------------------------

variable "cluster_endpoint" {
  description = "Kubernetes cluster API endpoint (output de /platform-provisioning/)"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "Kubernetes cluster CA certificate base64 encoded (output de /platform-provisioning/)"
  type        = string
  sensitive   = true
}

variable "storage_class_name" {
  description = "StorageClass para PVCs (gp3 AWS, managed-premium Azure, pd-ssd GCP)"
  type        = string
  default     = "gp3"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
}

# -----------------------------------------------------------------------------
# COMPONENT VERSIONS
# -----------------------------------------------------------------------------

variable "postgres_operator_version" {
  description = "Zalando Postgres Operator chart version"
  type        = string
  default     = "1.10.1"
}

variable "redis_operator_version" {
  description = "Redis Operator chart version"
  type        = string
  default     = "0.15.1"
}

variable "rabbitmq_operator_version" {
  description = "RabbitMQ Cluster Operator chart version"
  type        = string
  default     = "3.12.0"
}

variable "velero_version" {
  description = "Velero chart version"
  type        = string
  default     = "5.2.0"
}

# -----------------------------------------------------------------------------
# VELERO BACKUP CONFIGURATION
# -----------------------------------------------------------------------------

variable "velero_backup_bucket" {
  description = "S3-compatible bucket para backups Velero (ex: k8s-backups-production)"
  type        = string
}

variable "velero_region" {
  description = "Region do bucket S3 (ignorado por Minio, mas obrigatório para AWS/Azure/GCP)"
  type        = string
  default     = "us-east-1"
}

variable "velero_s3_url" {
  description = "URL do S3-compatible endpoint (ex: https://minio.example.com para Minio, https://s3.amazonaws.com para AWS)"
  type        = string
}

variable "velero_s3_access_key" {
  description = "Access Key para S3-compatible storage"
  type        = string
  sensitive   = true
}

variable "velero_s3_secret_key" {
  description = "Secret Key para S3-compatible storage"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# MONITORING
# -----------------------------------------------------------------------------

variable "enable_monitoring" {
  description = "Habilitar ServiceMonitors (Prometheus)"
  type        = bool
  default     = true
}
