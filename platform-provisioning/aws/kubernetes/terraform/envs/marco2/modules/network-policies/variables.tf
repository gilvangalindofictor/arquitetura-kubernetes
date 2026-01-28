# =============================================================================
# VARIABLES - Network Policies Module
# =============================================================================

variable "namespaces" {
  description = "List of namespaces to apply Network Policies"
  type        = list(string)
  default     = ["monitoring", "cert-manager", "kube-system"]
}

variable "enable_default_deny" {
  description = "Enable default deny-all policy per namespace"
  type        = bool
  default     = false # Start with false, enable after allow policies are working
}

variable "enable_dns_policy" {
  description = "Enable allow-dns policy for CoreDNS access"
  type        = bool
  default     = true
}

variable "enable_api_server_policy" {
  description = "Enable allow-api-server policy for Kubernetes API access"
  type        = bool
  default     = true
}

variable "enable_prometheus_scraping" {
  description = "Enable Prometheus scraping policies"
  type        = bool
  default     = true
}

variable "enable_loki_ingestion" {
  description = "Enable Fluent Bit to Loki policies"
  type        = bool
  default     = true
}

variable "enable_grafana_datasources" {
  description = "Enable Grafana to datasources policies"
  type        = bool
  default     = true
}

variable "enable_cert_manager_egress" {
  description = "Enable Cert-Manager egress policies"
  type        = bool
  default     = true
}

variable "prometheus_namespace" {
  description = "Namespace where Prometheus is deployed"
  type        = string
  default     = "monitoring"
}

variable "loki_namespace" {
  description = "Namespace where Loki is deployed"
  type        = string
  default     = "monitoring"
}

variable "grafana_namespace" {
  description = "Namespace where Grafana is deployed"
  type        = string
  default     = "monitoring"
}

variable "cert_manager_namespace" {
  description = "Namespace where Cert-Manager is deployed"
  type        = string
  default     = "cert-manager"
}

variable "kube_dns_namespace" {
  description = "Namespace where CoreDNS is deployed"
  type        = string
  default     = "kube-system"
}
