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
