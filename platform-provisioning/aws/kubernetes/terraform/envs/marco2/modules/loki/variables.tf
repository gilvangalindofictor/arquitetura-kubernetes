# -----------------------------------------------------------------------------
# Variables - Loki Module
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "region" {
  description = "Região AWS onde o cluster está provisionado"
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace Kubernetes para o Loki"
  type        = string
  default     = "monitoring"
}

variable "service_account_name" {
  description = "Nome da Service Account Kubernetes"
  type        = string
  default     = "loki"
}

variable "chart_version" {
  description = "Versão do Helm chart do Loki"
  type        = string
  default     = "5.42.0"
}

# -----------------------------------------------------------------------------
# Storage Configuration
# -----------------------------------------------------------------------------

variable "retention_days" {
  description = "Número de dias para reter logs no S3 (lifecycle policy)"
  type        = number
  default     = 30
}

variable "enable_versioning" {
  description = "Habilitar versioning no S3 bucket (aumenta custos)"
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "StorageClass para PVCs (write e backend components)"
  type        = string
  default     = "gp3"
}

variable "write_pvc_size" {
  description = "Tamanho do PVC para o write component"
  type        = string
  default     = "10Gi"
}

variable "backend_pvc_size" {
  description = "Tamanho do PVC para o backend component (compactor)"
  type        = string
  default     = "10Gi"
}

# -----------------------------------------------------------------------------
# Replication and Scaling
# -----------------------------------------------------------------------------

variable "replication_factor" {
  description = "Fator de replicação para Loki (deve ser <= write_replicas)"
  type        = number
  default     = 2
}

variable "read_replicas" {
  description = "Número de réplicas para o read component (query path)"
  type        = number
  default     = 2
}

variable "write_replicas" {
  description = "Número de réplicas para o write component (ingestion path)"
  type        = number
  default     = 2
}

variable "backend_replicas" {
  description = "Número de réplicas para o backend component (compactor, etc.)"
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags a serem aplicadas nos recursos AWS"
  type        = map(string)
  default     = {}
}
