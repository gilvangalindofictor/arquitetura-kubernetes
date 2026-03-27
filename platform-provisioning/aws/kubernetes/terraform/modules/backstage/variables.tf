# -----------------------------------------------------------------------------
# Backstage IDP Module Variables
# Developer portal for platform engineering (ADR-055)
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

variable "aws_account_id" {
  description = "AWS account ID (used for IRSA role ARN)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Backstage"
  type        = string
  default     = "staging-platform-backstage"
}

variable "backstage_chart_version" {
  description = "Backstage Helm chart version (backstage/backstage)"
  type        = string
  default     = "2.6.3"
}

variable "backstage_image_tag" {
  description = "Backstage application image tag"
  type        = string
  default     = "1.48.0"
}

variable "backstage_image_registry" {
  description = "Container registry for Backstage image"
  type        = string
  default     = "harbor.staging.internal"
}

variable "replicas" {
  description = "Number of Backstage replicas (M4: aumentar para 2 em HA)"
  type        = number
  default     = 1
}

variable "keycloak_host" {
  description = "Keycloak external host (browser-resolvable, ADR-046)"
  type        = string
  default     = "keycloak.staging.internal"
}

variable "gitlab_host" {
  description = "GitLab host for catalog discovery and ALTO-2 integration"
  type        = string
  default     = "gitlab.staging.internal"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

# Vault KV v2 secret path prefix (environment-scoped).
# Default "staging/backstage" mantém backward compatibility com staging.
# Para prod: "prod/backstage".
variable "vault_secret_prefix" {
  description = "Vault KV v2 secret path prefix for Backstage secrets (e.g. staging/backstage or prod/backstage)"
  type        = string
  default     = "staging/backstage"
}

# GAP-SEC-ESO-001 (FIX-006): CSS name parametrizado para isolar staging/prod.
# Default "vault-backend" mantém backward compatibility. Para prod: "vault-backend-prod".
variable "secret_store_name" {
  description = "ClusterSecretStore name for ExternalSecret references. Use module.external_secrets.cluster_secret_store_name output."
  type        = string
  default     = "vault-backend"
}

# -----------------------------------------------------------------------------
# Vault Secret Variables (sensitive=true — NUNCA hardcode)
# Seeding: vault_kv_secret_v2 resources no main.tf
# Pattern: TF_VAR_xxx via CI/CD secrets ou kubectl get secret + base64 -d
# -----------------------------------------------------------------------------

variable "backstage_db_host" {
  description = "PostgreSQL RDS host endpoint for Backstage database"
  type        = string
}

variable "backstage_db_user" {
  description = "PostgreSQL user for Backstage database"
  type        = string
  default     = "backstage_user"
}

variable "backstage_db_password" {
  description = "PostgreSQL password for Backstage database (seeds Vault KV secret/staging/backstage/database)"
  type        = string
  sensitive   = true
}

variable "backstage_db_port" {
  description = "PostgreSQL port for Backstage database"
  type        = number
  default     = 5432
}

variable "backstage_keycloak_client_id" {
  description = "Keycloak OIDC client ID for Backstage (ADR-046)"
  type        = string
  default     = "backstage"
}

variable "backstage_keycloak_client_secret" {
  description = "Keycloak OIDC client secret for Backstage (seeds Vault KV secret/staging/backstage/keycloak)"
  type        = string
  sensitive   = true
}

variable "backstage_gitlab_token" {
  description = "GitLab Group Access Token for Backstage catalog discovery (ALTO-2: Group AT, não OAuth token)"
  type        = string
  sensitive   = true
}

variable "backstage_argocd_url" {
  description = "ArgoCD server URL for Backstage ArgoCD plugin"
  type        = string
  default     = "http://argocd-server.staging-platform-argocd.svc.cluster.local"
}

variable "backstage_argocd_token" {
  description = "ArgoCD API token for Backstage plugin (seeds Vault KV secret/staging/backstage/argocd)"
  type        = string
  sensitive   = true
}

variable "backstage_sonarqube_url" {
  description = "SonarQube base URL for Backstage plugin"
  type        = string
  default     = "http://sonarqube-sonarqube.sonarqube.svc.cluster.local:9000"
}

variable "backstage_sonarqube_token" {
  description = "SonarQube API token for Backstage plugin (seeds Vault KV secret/staging/backstage/sonarqube)"
  type        = string
  sensitive   = true
}

variable "backstage_vault_addr" {
  description = "Vault address for Backstage plugin (internal cluster DNS)"
  type        = string
  default     = "http://vault.staging-security-vault.svc.cluster.local:8200"
}

variable "backstage_eks_cluster_url" {
  description = "EKS cluster API server URL for Backstage Kubernetes plugin"
  type        = string
}

variable "backstage_auth_session_secret" {
  description = "Random session secret for Backstage auth (seeds Vault KV secret/staging/backstage/session)"
  type        = string
  sensitive   = true
}

variable "backstage_harbor_url" {
  description = "Harbor registry URL for Backstage Harbor plugin"
  type        = string
  default     = "https://harbor.staging.internal"
}

variable "backstage_harbor_robot_token" {
  description = "Harbor robot account token for Backstage Harbor plugin (robot$backstage-puller)"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# GAP-BACKSTAGE-PROD-INTEGRATION: Prod environment integration variables
# Backstage staging is PLATFORM-SHARED — must integrate with both staging + prod
# Credentials stored in Vault staging (backstage runs in staging namespace)
# Added: 2026-03-27
# -----------------------------------------------------------------------------

variable "backstage_argocd_prod_url" {
  description = "ArgoCD prod server URL for Backstage ArgoCD plugin (multi-instance)"
  type        = string
  default     = "http://argocd-prod-server.prod-platform-argocd.svc.cluster.local"
}

variable "backstage_argocd_prod_token" {
  description = "ArgoCD prod API token for Backstage plugin (seeds Vault KV secret/staging/backstage/argocd-prod)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_keycloak_prod_base_url" {
  description = "Keycloak prod base URL for Backstage catalog keycloakOrg provider"
  type        = string
  default     = "http://keycloak-keycloakx-http.prod-platform-keycloak.svc.cluster.local/auth"
}

variable "backstage_keycloak_prod_realm" {
  description = "Keycloak prod realm name for Backstage catalog keycloakOrg provider"
  type        = string
  default     = "platform"
}

variable "backstage_vault_prod_addr" {
  description = "Vault prod address for Backstage integration (internal cluster DNS)"
  type        = string
  default     = "http://vault-prod.prod-security-vault.svc.cluster.local:8200"
}
