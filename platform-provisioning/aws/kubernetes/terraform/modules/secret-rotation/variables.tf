################################################################################
# Module: secret-rotation — Variables
# CICD-003: Automated Secret Rotation
################################################################################

variable "namespace" {
  description = "Kubernetes namespace where the secret-rotator CronJob runs"
  type        = string
  default     = "staging-security-vault"
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
  default     = "staging"
}

variable "rotation_schedule" {
  description = "CronJob schedule expression. Default: quarterly at 02:00 UTC on the 1st of Jan, Apr, Jul, Oct (ADR-083 / PCI-DSS 8.2.4)"
  type        = string
  default     = "0 2 1 */3 *"
}

variable "rotator_image" {
  description = "Container image for the secret-rotator pod"
  type        = string
  default     = "vault:1.15.0"
}

variable "vault_addr" {
  description = "Vault server address reachable from the CronJob pod (cluster-local)"
  type        = string
  default     = "http://vault.staging-security-vault.svc.cluster.local:8200"
}

variable "rds_endpoint" {
  description = "RDS PostgreSQL endpoint for ALTER USER statements"
  type        = string
  default     = "k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com"
}

variable "keycloak_url" {
  description = "Keycloak internal service URL for admin API calls"
  type        = string
  default     = "http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local"
}

variable "keycloak_realm" {
  description = "Keycloak realm for OIDC client secret rotation"
  type        = string
  default     = "platform"
}

variable "dry_run" {
  description = "When true, log all rotation steps without applying any changes. Use for testing."
  type        = bool
  default     = false
}

variable "rotation_grace_period_hours" {
  description = "Hours between writing new secret to Vault and old credential expiry. Allows ESO re-sync window."
  type        = number
  default     = 24
}

# GAP-SEC-ESO-001 (FIX-006): CSS name parametrizado para isolar staging/prod.
# Default "vault-backend" mantém backward compatibility. Para prod: "vault-backend-prod".
variable "secret_store_name" {
  description = "ClusterSecretStore name for ExternalSecret references. Use module.external_secrets.cluster_secret_store_name output."
  type        = string
  default     = "vault-backend"
}

variable "log_level" {
  description = "Logging verbosity for the rotation script. INFO or DEBUG."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["INFO", "DEBUG"], var.log_level)
    error_message = "log_level must be INFO or DEBUG."
  }
}
