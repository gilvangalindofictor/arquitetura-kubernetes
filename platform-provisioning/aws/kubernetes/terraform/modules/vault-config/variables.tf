# -----------------------------------------------------------------------------
# Vault Configuration Module Variables
# Post-deployment Vault setup: K8s auth, policies, secrets
# -----------------------------------------------------------------------------

variable "vault_addr" {
  description = "Vault server address (internal K8s service)"
  type        = string
  default     = "http://vault.vault-system.svc.cluster.local:8200"
}

variable "vault_token" {
  description = "Vault root token (from init or K8s secret)"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_host" {
  description = "Kubernetes API server URL (for Vault K8s auth)"
  type        = string
}

variable "kubernetes_ca_cert" {
  description = "Kubernetes cluster CA certificate (base64 encoded)"
  type        = string
}

variable "eso_namespace" {
  description = "External Secrets Operator namespace"
  type        = string
  default     = "external-secrets-system"
}

variable "eso_service_account" {
  description = "ESO ServiceAccount name for Vault auth"
  type        = string
  default     = "external-secrets"
}

variable "keycloak_postgresql_password" {
  description = "Keycloak PostgreSQL password (generated or existing)"
  type        = string
  sensitive   = true
}

variable "keycloak_postgresql_username" {
  description = "Keycloak PostgreSQL username"
  type        = string
  default     = "keycloak_user"
}

variable "keycloak_postgresql_host" {
  description = "Keycloak PostgreSQL host"
  type        = string
  default     = "postgresql-external.default.svc.cluster.local"
}

variable "keycloak_postgresql_port" {
  description = "Keycloak PostgreSQL port"
  type        = string
  default     = "5432"
}

variable "keycloak_postgresql_database" {
  description = "Keycloak PostgreSQL database name"
  type        = string
  default     = "keycloak"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# OIDC Auth Method (Keycloak SSO for Vault UI + CLI)
# -----------------------------------------------------------------------------

variable "oidc_enabled" {
  description = "Enable Vault OIDC auth method with Keycloak"
  type        = bool
  default     = false
}

variable "keycloak_oidc_url" {
  description = "Keycloak OIDC discovery base URL (external, browser-resolvable)"
  type        = string
  default     = "http://keycloak.staging.internal/auth/realms/platform"
}

variable "vault_oidc_client_id" {
  description = "Keycloak client ID for Vault OIDC"
  type        = string
  default     = "vault"
}

variable "vault_oidc_client_secret" {
  description = "Keycloak client secret for Vault OIDC (from Keycloak vault client)"
  type        = string
  sensitive   = true
  default     = ""
}
