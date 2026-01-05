# Platform Core Domain - Variables (Cloud-Agnostic)

# ===== CLUSTER INPUTS (from platform-provisioning) =====

variable "cluster_endpoint" {
  type        = string
  description = "Kubernetes API endpoint (from platform-provisioning output)"
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Cluster CA certificate base64 encoded (from platform-provisioning output)"
  sensitive   = true
}

variable "storage_class_name" {
  type        = string
  description = "Storage class name (gp3 for AWS, managed-premium for Azure, pd-ssd for GCP)"
  default     = "gp3"
}

# ===== COMPONENT VERSIONS =====

variable "cert_manager_version" {
  type        = string
  description = "cert-manager Helm chart version"
  default     = "v1.13.3"
}

variable "ingress_nginx_version" {
  type        = string
  description = "NGINX Ingress Controller Helm chart version"
  default     = "4.9.0"
}

variable "linkerd_version" {
  type        = string
  description = "Linkerd control plane Helm chart version"
  default     = "1.16.11"
}

variable "linkerd_viz_version" {
  type        = string
  description = "Linkerd viz Helm chart version"
  default     = "30.12.11"
}

variable "keycloak_version" {
  type        = string
  description = "Keycloak Helm chart version (Bitnami)"
  default     = "18.4.0"
}

variable "kong_version" {
  type        = string
  description = "Kong Helm chart version"
  default     = "2.35.0"
}

# ===== KEYCLOAK CONFIGURATION =====

variable "keycloak_domain" {
  type        = string
  description = "Keycloak domain (e.g., keycloak.example.com)"
}

variable "keycloak_admin_user" {
  type        = string
  description = "Keycloak admin username"
  default     = "admin"
}

variable "keycloak_admin_password" {
  type        = string
  description = "Keycloak admin password (produção: usar External Secrets)"
  sensitive   = true
}

variable "keycloak_db_password" {
  type        = string
  description = "Keycloak PostgreSQL password (produção: usar External Secrets)"
  sensitive   = true
}

# ===== KONG CONFIGURATION =====

variable "kong_db_password" {
  type        = string
  description = "Kong PostgreSQL password (produção: usar External Secrets)"
  sensitive   = true
}

# ===== CERT-MANAGER CONFIGURATION =====

variable "letsencrypt_email" {
  type        = string
  description = "Email for Let's Encrypt notifications"
}

# ===== LINKERD CONFIGURATION =====

variable "linkerd_trust_anchor_pem" {
  type        = string
  description = "Linkerd trust anchor certificate (PEM format)"
  sensitive   = true
  default     = ""
}

# ===== MONITORING =====

variable "enable_monitoring" {
  type        = bool
  description = "Enable Prometheus ServiceMonitors for observability integration"
  default     = true
}

# ===== DOMAIN CONFIGURATION =====

variable "environments" {
  type        = list(string)
  description = "Environment identifiers (not used in platform-core, but kept for consistency)"
  default     = ["platform-core"]
}
