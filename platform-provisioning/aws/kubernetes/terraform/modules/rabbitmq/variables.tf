# =============================================================================
# RabbitMQ Module Variables
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for RabbitMQ deployment"
  type        = string
  default     = "default"
}

variable "replicas" {
  description = "Number of RabbitMQ nodes in cluster"
  type        = number
  default     = 3
}

variable "pvc_size" {
  description = "RabbitMQ PVC size per node"
  type        = string
  default     = "10Gi"
}

variable "storage_class" {
  description = "Storage class for PVCs"
  type        = string
  default     = "gp2"
}

variable "enable_monitoring" {
  description = "Enable Prometheus ServiceMonitor"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Ingress
# -----------------------------------------------------------------------------

variable "ingress_enabled" {
  description = "Habilitar ALB Ingress para o RabbitMQ Management UI"
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Hostname para o Ingress do RabbitMQ (e.g., rabbitmq.staging.internal)"
  type        = string
  default     = ""
}

variable "ingress_group_name" {
  description = "ALB Ingress group name para compartilhar ALB entre serviços"
  type        = string
  default     = ""
}

variable "ingress_extra_hosts" {
  description = "Lista de hostnames adicionais para dual-host Ingress (DNS Fase 7 migration)"
  type        = list(string)
  default     = []
}

variable "ingress_certificate_arns" {
  description = "Lista de ARNs de certificados ACM para o Ingress (comma-separated no annotation). Se vazio, usa certificate-arn padrão do ALB."
  type        = list(string)
  default     = []
}
