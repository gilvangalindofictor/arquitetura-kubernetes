# -----------------------------------------------------------------------------
# Variables - Kube-Prometheus-Stack Module
# -----------------------------------------------------------------------------

variable "namespace" {
  description = "Namespace Kubernetes para o stack de monitoramento"
  type        = string
  default     = "monitoring"
}

variable "chart_version" {
  description = "Versão do Helm chart kube-prometheus-stack"
  type        = string
  default     = "69.4.0"
}

# -----------------------------------------------------------------------------
# Prometheus
# -----------------------------------------------------------------------------

variable "prometheus_storage_size" {
  description = "Tamanho do volume de armazenamento do Prometheus"
  type        = string
  default     = "20Gi"
}

variable "prometheus_retention" {
  description = "Tempo de retenção de métricas no Prometheus"
  type        = string
  default     = "15d"
}

# -----------------------------------------------------------------------------
# Grafana
# -----------------------------------------------------------------------------

variable "grafana_admin_password" {
  description = "Senha do admin do Grafana"
  type        = string
  sensitive   = true
}

variable "grafana_storage_size" {
  description = "Tamanho do volume de armazenamento do Grafana"
  type        = string
  default     = "5Gi"
}

variable "grafana_ingress_enabled" {
  description = "Habilitar Ingress para o Grafana"
  type        = bool
  default     = false
}

variable "grafana_ingress_host" {
  description = "Hostname para o Ingress do Grafana"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Alertmanager
# -----------------------------------------------------------------------------

variable "alertmanager_storage_size" {
  description = "Tamanho do volume de armazenamento do Alertmanager"
  type        = string
  default     = "2Gi"
}
