variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "5.51.6"
}

variable "replicas" {
  description = "Number of ArgoCD server replicas"
  type        = number
  default     = 2
}

variable "keycloak_url" {
  description = "Keycloak base URL for OIDC"
  type        = string
}

variable "keycloak_client_id" {
  description = "Keycloak OIDC client ID"
  type        = string
  default     = "argocd"
}

variable "ingress_enabled" {
  description = "Enable ALB ingress"
  type        = bool
  default     = false
}

variable "domain" {
  description = "Domain for ArgoCD (e.g., argocd.example.com)"
  type        = string
  default     = ""
}

variable "ingress_group_name" {
  description = "ALB Ingress group name para compartilhar ALB entre serviços"
  type        = string
  default     = ""
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
