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

# -----------------------------------------------------------------------------
# Cache Configuration
# -----------------------------------------------------------------------------

variable "chunks_cache_allocated_memory" {
  description = <<-EOT
    Memória alocada para o chunksCache do Loki (Memcached -m flag), em MB.
    Valor real medido no cluster: 1024 MB → 1229Mi de uso observado.
    Aumentar se Loki reportar cache misses frequentes (loki_cache_miss_total).
    Drift identificado 2026-03-06 e reconciliado: valor ativo no cluster desde
    importação do helm_release em 2026-03-05.
  EOT
  type        = number
  default     = 1024
}

# -----------------------------------------------------------------------------
# Corporate Labels (ADR-048)
# -----------------------------------------------------------------------------

variable "domain" {
  description = "Domain label para agrupar recursos por área funcional (ADR-048)"
  type        = string
  default     = "operations"
}

variable "owner" {
  description = "Owner label para identificar time responsável (ADR-048)"
  type        = string
  default     = "platform-team"
}

variable "environment" {
  description = "Environment label para identificar ambiente (staging/production)"
  type        = string
  default     = "staging"
}

# ECR Pull-Through Cache
variable "ecr_registry" {
  description = "ECR registry prefix for pull-through cache (e.g. 891377105802.dkr.ecr.us-east-1.amazonaws.com). Empty string uses upstream registries."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Multi-environment IRSA (Trust Policy) — additional service accounts
# -----------------------------------------------------------------------------

variable "additional_irsa_service_accounts" {
  description = <<-EOT
    Lista de service accounts adicionais que podem assumir a IAM Role via IRSA.
    Usado para permitir que SAs de outros namespaces (ex: prod) acessem os mesmos
    recursos S3. Formato: "namespace:service_account_name".
    Exemplo: ["prod-observability-monitoring:loki-prod"]
  EOT
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Multi-environment S3 — additional bucket ARNs
# -----------------------------------------------------------------------------

variable "additional_s3_bucket_arns" {
  description = <<-EOT
    Lista de ARNs de buckets S3 adicionais que a IAM Policy deve permitir acesso.
    Usado quando Loki em prod utiliza bucket separado mas a mesma IAM Role.
    Exemplo: ["arn:aws:s3:::k8s-platform-loki-prod-891377105802"]
  EOT
  type        = list(string)
  default     = []
}
