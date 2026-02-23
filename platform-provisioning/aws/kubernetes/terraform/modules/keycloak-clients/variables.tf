# =============================================================================
# Keycloak Clients Module — Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Provider Authentication
# -----------------------------------------------------------------------------

variable "keycloak_url" {
  description = "Keycloak URL. WSL-safe: use http://localhost:18080 with active port-forward. Pattern: kubectl port-forward svc/keycloak-keycloakx-http 18080:80 -n keycloak"
  type        = string
  default     = "http://localhost:18080"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password. Retrieve from K8s secret: kubectl get secret keycloak-admin-password -n keycloak -o jsonpath='{.data.password}' | base64 -d"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Realm
# -----------------------------------------------------------------------------

variable "realm" {
  description = "Keycloak realm name where clients are managed"
  type        = string
  default     = "platform"
}

# -----------------------------------------------------------------------------
# Environment / Domain
# -----------------------------------------------------------------------------

variable "domain_suffix" {
  description = "Domain suffix for redirect URIs and web origins. Example: staging.internal"
  type        = string
  default     = "staging.internal"
}

variable "environment" {
  description = "Environment name for labels and tags"
  type        = string
  default     = "staging"
}

variable "cluster_name" {
  description = "EKS cluster name, used in resource labels"
  type        = string
  default     = "k8s-platform-prod"
}

# -----------------------------------------------------------------------------
# Client: GitLab
# -----------------------------------------------------------------------------

variable "gitlab_enabled" {
  description = "Enable GitLab OIDC client management"
  type        = bool
  default     = true
}

variable "gitlab_namespace" {
  description = "Kubernetes namespace for GitLab"
  type        = string
  default     = "gitlab-staging"
}

# -----------------------------------------------------------------------------
# Client: ArgoCD
# -----------------------------------------------------------------------------

variable "argocd_enabled" {
  description = "Enable ArgoCD OIDC client management"
  type        = bool
  default     = true
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

# -----------------------------------------------------------------------------
# Client: Grafana
# -----------------------------------------------------------------------------

variable "grafana_enabled" {
  description = "Enable Grafana OIDC client management"
  type        = bool
  default     = true
}

variable "grafana_namespace" {
  description = "Kubernetes namespace for Grafana"
  type        = string
  default     = "monitoring"
}

# -----------------------------------------------------------------------------
# Group: grafana-admins
# Replaces null_resource.keycloak_grafana_admins_group (Python port-forward hack)
# -----------------------------------------------------------------------------

variable "grafana_admins_group_enabled" {
  description = "Enable creation of grafana-admins group with OIDC group membership mapper on the grafana client"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Common Tags
# -----------------------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to Kubernetes resources managed by this module"
  type        = map(string)
  default     = {}
}
