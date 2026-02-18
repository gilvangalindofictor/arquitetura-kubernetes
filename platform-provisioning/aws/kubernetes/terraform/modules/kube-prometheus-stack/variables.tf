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

variable "grafana_ingress_group_name" {
  description = "ALB Ingress group name para compartilhar ALB entre serviços"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Grafana OIDC / Keycloak SSO
# -----------------------------------------------------------------------------

variable "grafana_oidc_enabled" {
  description = "Habilitar autenticação OIDC via Keycloak no Grafana"
  type        = bool
  default     = false
}

variable "grafana_keycloak_url" {
  description = "URL base do Keycloak (ex: http://keycloak.staging.internal/auth)"
  type        = string
  default     = ""
}

variable "grafana_keycloak_client_id" {
  description = "Client ID do Keycloak para o Grafana"
  type        = string
  default     = "grafana"
}

variable "grafana_keycloak_client_secret" {
  description = "Client Secret do Keycloak para o Grafana (lido do Vault via ExternalSecret)"
  type        = string
  sensitive   = true
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
