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

# GAP-SEC-ESO-001 (FIX-006): CSS name parametrizado para isolar staging/prod.
# Default "vault-backend" mantém backward compatibility. Para prod: "vault-backend-prod".
variable "secret_store_name" {
  description = "ClusterSecretStore name for ExternalSecret references. Use module.external_secrets.cluster_secret_store_name output."
  type        = string
  default     = "vault-backend"
}
