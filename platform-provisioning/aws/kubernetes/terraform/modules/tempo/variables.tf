# -----------------------------------------------------------------------------
# Variables - Tempo Module
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Cluster Configuration
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Kubernetes namespace para deploy do Tempo"
  type        = string
  default     = "monitoring"
}

variable "service_account_name" {
  description = "Nome do Service Account Kubernetes para Tempo"
  type        = string
  default     = "tempo"
}

# -----------------------------------------------------------------------------
# Helm Chart Configuration
# -----------------------------------------------------------------------------

variable "chart_version" {
  description = "Versão do Helm chart tempo-distributed (>= 1.50.0)"
  type        = string
  default     = "1.61.3"
}

# -----------------------------------------------------------------------------
# Storage Configuration (S3)
# -----------------------------------------------------------------------------

variable "retention_days" {
  description = "Retention period para traces em dias (default: 7 days - ADR-020)"
  type        = number
  default     = 7

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 90
    error_message = "Retention days deve estar entre 1 e 90 dias."
  }
}

variable "enable_versioning" {
  description = "Habilitar versionamento no bucket S3 (default: false para economia)"
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "StorageClass para PVCs (Ingester WAL, Compactor cache)"
  type        = string
  default     = "gp2"
}

variable "ingester_pvc_size" {
  description = "Tamanho do PVC para Ingester Write-Ahead Log (FinOps: 10Gi vs 20Gi)"
  type        = string
  default     = "10Gi"
}

variable "compactor_pvc_size" {
  description = "Tamanho do PVC para Compactor cache (FinOps: 10Gi vs 20Gi)"
  type        = string
  default     = "10Gi"
}

# -----------------------------------------------------------------------------
# Replication Configuration
# -----------------------------------------------------------------------------

variable "distributor_replicas" {
  description = "Número de replicas do Tempo Distributor"
  type        = number
  default     = 2
}

variable "ingester_replicas" {
  description = "Número de replicas do Tempo Ingester"
  type        = number
  default     = 2
}

variable "querier_replicas" {
  description = "Número de replicas do Tempo Querier"
  type        = number
  default     = 2
}

variable "compactor_replicas" {
  description = "Número de replicas do Tempo Compactor"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------

variable "enable_network_policies" {
  description = "Habilitar Network Policies Calico (4 policies: otel-ingress, otel-to-tempo, grafana-to-tempo, tempo-to-s3)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags para recursos AWS"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "k8s-platform"
    Marco       = "marco2"
    Fase        = "8"
    ManagedBy   = "terraform"
  }
}
