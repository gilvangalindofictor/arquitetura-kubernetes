# -----------------------------------------------------------------------------
# Keycloak Module Variables
# SSO Platform for OIDC authentication (ArgoCD, SonarQube, GitLab)
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Kubernetes namespace for Keycloak"
  type        = string
  default     = "keycloak"
}

variable "keycloak_chart_version" {
  description = "Codecentric KeycloakX Helm chart version (Keycloak 26.x Quarkus)"
  type        = string
  default     = "7.1.7"
}

# WSL2 DNS workaround: set helm_chart_local_path to use a local .tgz instead of remote repository.
# Example: "/home/user/.cache/helm/repository/keycloakx-7.1.7.tgz"
# When set, helm_repository is ignored (set to null in the resource).
variable "helm_chart_local_path" {
  description = "Optional: local path to chart .tgz file. Overrides remote repository (WSL2 DNS workaround)."
  type        = string
  default     = ""
}

variable "replicas" {
  description = "Number of Keycloak replicas (HA)"
  type        = number
  default     = 2
}

variable "postgresql_host" {
  description = "PostgreSQL host (RDS endpoint or Kubernetes service name)"
  type        = string
}

variable "postgresql_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "postgresql_database" {
  description = "PostgreSQL database name"
  type        = string
  default     = "keycloak"
}

variable "postgresql_username" {
  description = "PostgreSQL username for Keycloak"
  type        = string
  default     = "keycloak_user"
}

variable "enable_monitoring" {
  description = "Enable Prometheus ServiceMonitor (ADR-006)"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
  default     = "staging"
}

variable "keycloak_hostname" {
  description = "Public hostname for Keycloak (e.g., keycloak.staging.internal)"
  type        = string
  default     = "keycloak.staging.internal"
}

variable "monitoring_namespace" {
  description = "Namespace for monitoring/ServiceMonitor"
  type        = string
  default     = "staging-observability-monitoring"
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for ALB HTTPS ingress (AWS Certificate Manager)"
  type        = string
}

# GAP-SEC-ESO-001 (2026-03-23): CSS name parametrizado para isolar staging/prod.
# Default "vault-backend" mantém backward compatibility. Para prod: "vault-backend-prod".
variable "secret_store_name" {
  description = "ClusterSecretStore name for ExternalSecret references. Use module.external_secrets.cluster_secret_store_name output."
  type        = string
  default     = "vault-backend"
}

# ECR Pull-Through Cache
variable "ecr_registry" {
  description = "ECR registry prefix for pull-through cache (e.g. 891377105802.dkr.ecr.us-east-1.amazonaws.com). Empty string uses upstream registries."
  type        = string
  default     = ""
}
