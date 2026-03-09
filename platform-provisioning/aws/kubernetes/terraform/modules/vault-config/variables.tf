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
# Grafana Admin Password (Vault KV seed — V-001 remediation)
# -----------------------------------------------------------------------------

variable "grafana_admin_password" {
  description = "Grafana admin password (V-001: migrated from hardcoded 'admin' to Vault KV)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Grafana OIDC credentials (Vault KV seed)
# -----------------------------------------------------------------------------

variable "grafana_oidc_client_id" {
  description = "Keycloak client ID for Grafana OIDC"
  type        = string
  default     = "grafana"
}

variable "grafana_oidc_client_secret" {
  description = "Keycloak client secret for Grafana OIDC (migrated from staging/main.tf hardcode)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# SonarQube PostgreSQL credentials (Vault KV seed)
# -----------------------------------------------------------------------------

variable "sonarqube_postgresql_password" {
  description = "SonarQube PostgreSQL user password (from SM staging/postgresql/sonarqube-password)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "sonarqube_postgresql_username" {
  description = "SonarQube PostgreSQL username"
  type        = string
  default     = "sonarqube_user"
}

variable "sonarqube_postgresql_host" {
  description = "SonarQube PostgreSQL host (RDS endpoint via ExternalName)"
  type        = string
  default     = "postgresql-external.default.svc.cluster.local"
}

variable "sonarqube_postgresql_port" {
  description = "SonarQube PostgreSQL port"
  type        = string
  default     = "5432"
}

variable "sonarqube_postgresql_database" {
  description = "SonarQube PostgreSQL database name"
  type        = string
  default     = "sonarqube"
}

# -----------------------------------------------------------------------------
# Harbor PostgreSQL credentials (Vault KV seed)
# -----------------------------------------------------------------------------

variable "harbor_postgresql_password" {
  description = "Harbor PostgreSQL user password (migrated from AWS SM staging/postgresql/gitlab-password)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "harbor_postgresql_username" {
  description = "Harbor PostgreSQL username"
  type        = string
  default     = "harbor_user"
}

variable "harbor_postgresql_host" {
  description = "Harbor PostgreSQL host"
  type        = string
  default     = "postgresql-external.default.svc.cluster.local"
}

variable "harbor_postgresql_port" {
  description = "Harbor PostgreSQL port"
  type        = string
  default     = "5432"
}

variable "harbor_postgresql_database" {
  description = "Harbor PostgreSQL database name"
  type        = string
  default     = "harbor"
}

# -----------------------------------------------------------------------------
# Harbor Admin Password (Vault KV seed) — V-004 remediation
# -----------------------------------------------------------------------------

variable "harbor_admin_password" {
  description = "Harbor admin user password (V-004: migrated to Vault KV)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Harbor Redis Password (Vault KV seed) — V-005 remediation
# -----------------------------------------------------------------------------

variable "harbor_redis_password" {
  description = "Harbor Redis password (V-005: migrated to Vault KV)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Keycloak Admin Password (Vault KV seed) — V-006 remediation
# -----------------------------------------------------------------------------

variable "keycloak_admin_password" {
  description = "Keycloak admin user password (V-006: migrated to Vault KV)"
  type        = string
  sensitive   = true
  default     = ""
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

# -----------------------------------------------------------------------------
# ArgoCD PostgreSQL credentials (Vault KV seed) — V-002 remediation
# -----------------------------------------------------------------------------

variable "argocd_postgresql_password" {
  description = "ArgoCD PostgreSQL user password (V-002: migrated to Vault KV)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "argocd_postgresql_username" {
  description = "ArgoCD PostgreSQL username"
  type        = string
  default     = "argocd_user"
}

variable "argocd_postgresql_host" {
  description = "ArgoCD PostgreSQL host (RDS endpoint via ExternalName)"
  type        = string
  default     = "postgresql-external.default.svc.cluster.local"
}

variable "argocd_postgresql_port" {
  description = "ArgoCD PostgreSQL port"
  type        = string
  default     = "5432"
}

variable "argocd_postgresql_database" {
  description = "ArgoCD PostgreSQL database name"
  type        = string
  default     = "argocd"
}

# -----------------------------------------------------------------------------
# ArgoCD OIDC credentials (Vault KV seed) — V-002 remediation
# -----------------------------------------------------------------------------

variable "argocd_oidc_client_id" {
  description = "Keycloak client ID for ArgoCD OIDC"
  type        = string
  default     = "argocd"
}

variable "argocd_oidc_client_secret" {
  description = "Keycloak client secret for ArgoCD OIDC (V-002: migrated to Vault KV)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Hatch ETL secrets (app-level, staging namespace)
# Vault paths: secret/staging/hatch/{database,redis,api}
# ESO ExternalSecrets: hatch-database-credentials, hatch-redis-connection, hatch-api-credentials
# -----------------------------------------------------------------------------

variable "hatch_etl_enabled" {
  description = "Enable Hatch ETL secrets provisioning in Vault"
  type        = bool
  default     = false
}

variable "hatch_etl_db_host" {
  description = "Hatch ETL PostgreSQL host (RDS endpoint)"
  type        = string
  default     = ""
}

variable "hatch_etl_db_password" {
  description = "Hatch ETL PostgreSQL user password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "hatch_etl_db_name" {
  description = "Hatch ETL database name"
  type        = string
  default     = "hatch_dw"
}

variable "hatch_etl_redis_host" {
  description = "Hatch ETL Redis host"
  type        = string
  default     = "redis.data-services.svc.cluster.local"
}

variable "hatch_etl_redis_password" {
  description = "Hatch ETL Redis password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "hatch_etl_api_base_url" {
  description = "Hatch external API base URL"
  type        = string
  default     = "https://backendhatchbank.hatchst.com.br"
}

variable "hatch_etl_api_username" {
  description = "Hatch external API username"
  type        = string
  sensitive   = true
  default     = ""
}

variable "hatch_etl_api_password" {
  description = "Hatch external API password"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Alertmanager Teams Webhook URLs
# Vault path: secret/monitoring/alertmanager
# ESO ExternalSecret: alertmanager-teams-webhook (staging-observability-monitoring)
# Note: Values are REPLACE_ placeholders; real URLs must be set manually in Vault
#       after TF import. lifecycle { ignore_changes = [data_json] } prevents
#       Terraform from overwriting URLs set directly in Vault.
# Added: 2026-03-09 — migrate from manual Vault secret to TF-managed (Teams rename)
# -----------------------------------------------------------------------------
variable "alertmanager_teams_webhook_critical" {
  description = "Microsoft Teams webhook URL for CRITICAL alerts"
  type        = string
  sensitive   = true
  default     = "REPLACE_TEAMS_WEBHOOK_URL_CRITICAL"
}

variable "alertmanager_teams_webhook_warning" {
  description = "Microsoft Teams webhook URL for WARNING alerts"
  type        = string
  sensitive   = true
  default     = "REPLACE_TEAMS_WEBHOOK_URL_WARNING"
}

variable "alertmanager_teams_webhook_data_services" {
  description = "Microsoft Teams webhook URL for DATA_SERVICES alerts"
  type        = string
  sensitive   = true
  default     = "REPLACE_TEAMS_WEBHOOK_URL_DATA_SERVICES"
}

variable "alertmanager_teams_webhook_security" {
  description = "Microsoft Teams webhook URL for SECURITY alerts"
  type        = string
  sensitive   = true
  default     = "REPLACE_TEAMS_WEBHOOK_URL_SECURITY"
}
