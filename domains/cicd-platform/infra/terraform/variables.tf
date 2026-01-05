# CI/CD Platform Domain - Variables

# ===== CLUSTER INPUTS =====
variable "cluster_endpoint" {
  type        = string
  description = "Kubernetes API endpoint (from platform-provisioning)"
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Cluster CA certificate (from platform-provisioning)"
  sensitive   = true
}

variable "storage_class_name" {
  type        = string
  description = "Storage class (gp3/managed-premium/pd-ssd)"
  default     = "gp3"
}

# ===== DOMAINS =====
variable "gitlab_domain" {
  type        = string
  description = "GitLab domain (e.g., gitlab.example.com)"
}

variable "sonarqube_domain" {
  type        = string
  description = "SonarQube domain"
}

variable "harbor_domain" {
  type        = string
  description = "Harbor domain"
}

variable "argocd_domain" {
  type        = string
  description = "ArgoCD domain"
}

variable "backstage_domain" {
  type        = string
  description = "Backstage domain"
}

variable "keycloak_url" {
  type        = string
  description = "Keycloak URL from platform-core (for OIDC)"
}

# ===== SECRETS =====
variable "harbor_admin_password" {
  type        = string
  description = "Harbor admin password"
  sensitive   = true
}

variable "backstage_db_password" {
  type        = string
  description = "Backstage PostgreSQL password"
  sensitive   = true
}

variable "gitlab_token" {
  type        = string
  description = "GitLab token for Backstage integration"
  sensitive   = true
}

# ===== VERSIONS =====
variable "gitlab_version" {
  type    = string
  default = "7.7.0"
}

variable "sonarqube_version" {
  type    = string
  default = "10.3.0"
}

variable "harbor_version" {
  type    = string
  default = "1.14.0"
}

variable "argocd_version" {
  type    = string
  default = "5.51.6"
}

variable "backstage_version" {
  type    = string
  default = "1.7.0"
}

variable "enable_monitoring" {
  type    = bool
  default = true
}
