# -----------------------------------------------------------------------------
# Variables - Promtail Module
# Promtail DaemonSet logging agent (no IRSA needed — no direct AWS access)
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "namespace" {
  description = "Namespace Kubernetes para o Promtail"
  type        = string
  default     = "staging-observability-monitoring"
}

variable "chart_version" {
  description = "Versao do Helm chart do Promtail"
  type        = string
  default     = "6.16.6"
}

variable "loki_url" {
  description = "URL do endpoint Loki Gateway para envio de logs"
  type        = string
}

variable "loki_tenant_id" {
  description = "Tenant ID para autenticacao multi-tenant no Loki (vazio = single-tenant)"
  type        = string
  default     = ""
}

variable "additional_tolerations" {
  description = "Toleracoes adicionais para o DaemonSet Promtail"
  type = list(object({
    key      = string
    operator = string
    value    = optional(string, "")
    effect   = string
  }))
  default = []
}

variable "node_selector" {
  description = "NodeSelector para o DaemonSet Promtail"
  type        = map(string)
  default     = {}
}

variable "resources_requests_cpu" {
  description = "CPU request para cada pod Promtail"
  type        = string
  default     = "50m"
}

variable "resources_requests_memory" {
  description = "Memory request para cada pod Promtail"
  type        = string
  default     = "64Mi"
}

variable "resources_limits_cpu" {
  description = "CPU limit para cada pod Promtail"
  type        = string
  default     = "200m"
}

variable "resources_limits_memory" {
  description = "Memory limit para cada pod Promtail"
  type        = string
  default     = "128Mi"
}

variable "enable_service_monitor" {
  description = "Habilitar ServiceMonitor para integracao com kube-prometheus-stack"
  type        = bool
  default     = true
}

variable "service_monitor_labels" {
  description = "Labels adicionais no ServiceMonitor para selecao pelo Prometheus"
  type        = map(string)
  default = {
    release = "kube-prometheus-stack"
  }
}

variable "extra_scrape_configs" {
  description = "Configuracoes extras de scrape para o Promtail (YAML raw)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Corporate Labels (ADR-048)
# -----------------------------------------------------------------------------

variable "domain" {
  description = "Domain label para agrupar recursos por area funcional (ADR-048)"
  type        = string
  default     = "platform"
}

variable "owner" {
  description = "Owner label para identificar time responsavel (ADR-048)"
  type        = string
  default     = "platform-team"
}

variable "environment" {
  description = "Environment label para identificar ambiente (staging/production)"
  type        = string
  default     = "staging"
}
