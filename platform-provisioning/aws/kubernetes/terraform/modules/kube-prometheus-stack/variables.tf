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
  description = "DEPRECATED (V-001): Use grafana_admin_use_existing_secret=true instead. Kept for backward compat."
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_admin_use_existing_secret" {
  description = "Use ExternalSecret (Vault → ESO) for Grafana admin password instead of plaintext (V-001 remediation)"
  type        = bool
  default     = false
}

variable "grafana_admin_existing_secret_name" {
  description = "Name of the K8s Secret created by ESO for Grafana admin credentials"
  type        = string
  default     = "grafana-admin-credentials"
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

# DEPRECATED: grafana_keycloak_client_secret removido (2026-02-19)
# client_secret agora via ESO: grafana-oidc-credentials (Vault: secret/grafana/oidc)
# Mantido com default="" para compatibilidade — remover na próxima major refactor

# -----------------------------------------------------------------------------
# Alertmanager
# -----------------------------------------------------------------------------

variable "alertmanager_storage_size" {
  description = "Tamanho do volume de armazenamento do Alertmanager"
  type        = string
  default     = "2Gi"
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
