# STAGING Environment Variables Definition

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for resources"
  type        = string
}

variable "state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "base_tags" {
  description = "Base tags applied to all resources"
  type        = map(string)
}

#------------------------------------------------------------------------------
# PostgreSQL RDS Variables
#------------------------------------------------------------------------------

variable "postgresql_instance_class" {
  description = "RDS instance class for PostgreSQL"
  type        = string
  default     = "db.t3.micro"
}

variable "postgresql_allocated_storage" {
  description = "Initial storage allocation in GB"
  type        = number
  default     = 20
}

variable "postgresql_max_allocated_storage" {
  description = "Maximum storage allocation in GB"
  type        = number
  default     = 50
}

#------------------------------------------------------------------------------
# Redis Variables
#------------------------------------------------------------------------------

variable "redis_replicas" {
  description = "Number of Redis replicas"
  type        = number
  default     = 1
}

variable "redis_pvc_size" {
  description = "PVC size for Redis"
  type        = string
  default     = "5Gi"
}

#------------------------------------------------------------------------------
# RabbitMQ Variables
#------------------------------------------------------------------------------

variable "rabbitmq_replicas" {
  description = "Number of RabbitMQ replicas"
  type        = number
  default     = 1
}

variable "rabbitmq_pvc_size" {
  description = "PVC size for RabbitMQ"
  type        = string
  default     = "5Gi"
}

#------------------------------------------------------------------------------
# FinOps Variables
#------------------------------------------------------------------------------

variable "finops_alert_email" {
  description = "Email for FinOps alerts"
  type        = string
}

#------------------------------------------------------------------------------
# Vault Variables
#------------------------------------------------------------------------------

variable "vault_root_token" {
  description = "Vault root token for initial configuration (from init or K8s secret)"
  type        = string
  sensitive   = true
}

variable "vault_oidc_client_secret" {
  description = "Keycloak client secret for Vault OIDC SSO (from Keycloak vault client)"
  type        = string
  sensitive   = true
  default     = ""
}

# Grafana OIDC — migrado de hardcode para Vault KV (P0-A ESO gap, 2026-02-19)
variable "grafana_oidc_client_secret" {
  description = "Keycloak client secret for Grafana OIDC (migrated from hardcode to Vault KV secret/grafana/oidc)"
  type        = string
  sensitive   = true
  default     = ""
}

# V-001 Remediation: Grafana admin password → Vault KV (2026-02-20)
variable "grafana_admin_password" {
  description = "Grafana admin password (V-001: seeds Vault KV secret/grafana/admin, replaces hardcoded 'admin')"
  type        = string
  sensitive   = true
  default     = ""
}

# SonarQube PostgreSQL — resolve TODO sonarqube/main.tf (P0-B ESO gap, 2026-02-19)
variable "sonarqube_postgresql_password" {
  description = "SonarQube PostgreSQL user password (from SM staging/postgresql/sonarqube-password)"
  type        = string
  sensitive   = true
  default     = ""
}

# GitLab PostgreSQL — FIX-GAP-GITLAB-WEBSERVICE-2026-03-24
variable "gitlab_postgresql_password" {
  description = "GitLab PostgreSQL user password (source: AWS SM staging/postgresql/gitlab-password; rotated outside TF 2026-02-09)"
  type        = string
  sensitive   = true
  default     = ""
}

# Harbor PostgreSQL — migrado de AWS SM para Vault KV (P1 ESO gap, 2026-02-19)
variable "harbor_postgresql_password" {
  description = "Harbor PostgreSQL user password (migrated from AWS SM staging/postgresql/gitlab-password to Vault KV secret/harbor/postgresql)"
  type        = string
  sensitive   = true
  default     = ""
}

# ArgoCD PostgreSQL — V-002 remediation (2026-02-20)
variable "argocd_postgresql_password" {
  description = "ArgoCD PostgreSQL user password (V-002: migrated to Vault KV secret/argocd/postgresql)"
  type        = string
  sensitive   = true
  default     = ""
}

# ArgoCD OIDC — V-002 remediation (2026-02-20)
variable "argocd_oidc_client_secret" {
  description = "Keycloak client secret for ArgoCD OIDC (V-002: migrated to Vault KV secret/argocd/oidc)"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# Keycloak Variables
#------------------------------------------------------------------------------

variable "keycloak_postgresql_password" {
  description = "Keycloak PostgreSQL password (stored in Vault)"
  type        = string
  sensitive   = true
  default     = "" # If empty, random password will be generated
}

# TASK-002: Keycloak provider authentication (mrparkers/keycloak)
# V-006: Migrado para ESO (2026-02-24)
# Pass via: export TF_VAR_keycloak_admin_password=$(kubectl get secret keycloak-admin-credentials -n keycloak -o jsonpath='{.data.password}' | base64 -d)
variable "keycloak_admin_password" {
  description = "Keycloak admin password for mrparkers/keycloak provider. Retrieved from K8s secret keycloak-admin-credentials in namespace keycloak."
  type        = string
  sensitive   = true
  default     = ""
}

# V-004 Remediation: Harbor admin password → Vault KV (2026-02-25)
variable "harbor_admin_password" {
  description = "Harbor admin password (V-004: seeds Vault KV secret/harbor/admin, ESO: harbor-admin-credentials)"
  type        = string
  sensitive   = true
  default     = ""
}

# V-005 Remediation: Harbor Redis password → Vault KV (2026-02-25)
variable "harbor_redis_password" {
  description = "Harbor Redis password (V-005: seeds Vault KV secret/harbor/redis, ESO: harbor-redis-credentials)"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# WAF v2 + DDoS Protection Variables (GAP-010)
#------------------------------------------------------------------------------

variable "waf_alb_arn" {
  description = "ARN of the ALB to associate with WAF. Leave empty ('') to auto-resolve via data.aws_lb.ingress_alb tag lookup. Set explicitly when the ALB does not yet exist or the tag lookup returns multiple results."
  type        = string
  default     = ""
}

variable "waf_rate_limit" {
  description = "Maximum number of requests per IP per 5-minute window before the WAF rate-limit rule fires (BLOCK 429). Staging: 1000 (lenient). Production: consider 500."
  type        = number
  default     = 1000
}

variable "waf_enable_geo_blocking" {
  description = "Enable WAF geographic blocking rule (Priority 20). Set to false during testing from geo-blocked locations."
  type        = bool
  default     = true
}

variable "waf_blocked_countries" {
  description = "ISO 3166-1 alpha-2 country codes to block at WAF layer. Defaults to CN (China), RU (Russia), KP (North Korea) — historically high attack origination."
  type        = list(string)
  default     = ["CN", "RU", "KP"]
}

variable "waf_log_retention_days" {
  description = "Number of days to retain WAF log objects in the S3 bucket created by the module. Must be one of: 1, 3, 7, 14, 30, 60, 90, 180, 365."
  type        = number
  default     = 90
}

#------------------------------------------------------------------------------
# GAP-012: DR Multi-Region Variables
#------------------------------------------------------------------------------

variable "dr_enable_rds_replica" {
  description = "Enable RDS cross-region read replica in us-west-2 (GAP-012). Set to true only after dr_vpc_id, dr_subnet_ids and dr_allowed_cidrs are populated. Costs ~$50/month."
  type        = bool
  default     = false
}

variable "dr_rds_replica_instance_class" {
  description = "RDS instance class for the cross-region read replica. Default db.t4g.medium (~$47/month) is sufficient for staging DR."
  type        = string
  default     = "db.t4g.medium"
}

variable "dr_vpc_id" {
  description = "VPC ID in us-west-2 for the RDS read replica subnet group and security group. Required when dr_enable_rds_replica = true."
  type        = string
  default     = ""
}

variable "dr_subnet_ids" {
  description = "List of private subnet IDs in us-west-2 for the RDS read replica DB subnet group. Requires at least 2 subnets in different AZs."
  type        = list(string)
  default     = []
}

variable "dr_allowed_cidrs" {
  description = "CIDR blocks in us-west-2 allowed to connect to the RDS read replica on port 5432 (typically the DR VPC private subnet CIDRs)."
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# Backstage IDP Variables (ADR-055)
# Equalizado: 2026-03-06 (implantado manualmente em 2026-03-05)
# Vault paths: secret/staging/backstage/{database,keycloak,gitlab,argocd,
#              sonarqube,vault,eks,session}
# ESO ExternalSecret: backstage-secrets (staging-platform-backstage)
#------------------------------------------------------------------------------

variable "backstage_db_password" {
  description = "PostgreSQL password for Backstage database (ADR-055: seeds Vault KV secret/staging/backstage/database)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_keycloak_client_secret" {
  description = "Keycloak OIDC client secret for Backstage (ADR-055/ADR-046: seeds Vault KV secret/staging/backstage/keycloak)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_gitlab_token" {
  description = "GitLab Group Access Token for Backstage (ADR-055/ALTO-2: Group AT obrigatório, seeds Vault KV secret/staging/backstage/gitlab)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_argocd_token" {
  description = "ArgoCD API token for Backstage plugin (ADR-055: seeds Vault KV secret/staging/backstage/argocd)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_sonarqube_token" {
  description = "SonarQube API token for Backstage plugin (ADR-055: seeds Vault KV secret/staging/backstage/sonarqube)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_auth_session_secret" {
  description = "Random session secret for Backstage auth (ADR-055: seeds Vault KV secret/staging/backstage/session)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_harbor_robot_token" {
  description = "Harbor robot account token for Backstage Harbor plugin (robot$backstage-puller)"
  type        = string
  sensitive   = true
  default     = ""
}

# GAP-BACKSTAGE-PROD-INTEGRATION: ArgoCD prod API token (2026-03-27)
variable "backstage_argocd_prod_token" {
  description = "ArgoCD prod API token for Backstage multi-instance plugin (backstage account, read-only)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Hatch ETL — Vault KV secret provisioning
# GAP-TF-01/02: hatch_etl_enabled=true applied (2026-03-13)
# Vault paths: secret/staging/hatch-etl/{database,redis,api}
# Passed via TF_VAR_* in CI/CD pipeline or terraform.tfvars (sensitive values)
# -----------------------------------------------------------------------------

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
  default     = "redis.staging-data-infrastructure.svc.cluster.local"
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

#------------------------------------------------------------------------------
# PostgreSQL Provider — Local Override (port-forward / VPC tunnel)
# Use when running TF locally to bypass VPC-only RDS constraint.
# Example: -var postgresql_host_override=localhost (with kubectl port-forward active)
#------------------------------------------------------------------------------

variable "postgresql_host_override" {
  description = "Override PostgreSQL provider host for local TF runs via port-forward. Default null = use VPC RDS address."
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Docker Hub — ECR Pull-Through Cache credentials
# Stored in AWS Secrets Manager (required by ECR API, not Vault)
#------------------------------------------------------------------------------

variable "docker_hub_username" {
  description = "Docker Hub username for ECR pull-through cache authentication"
  type        = string
  sensitive   = true
  default     = ""
}

variable "docker_hub_access_token" {
  description = "Docker Hub access token (PAT) for ECR pull-through cache authentication"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# Alertmanager Webhook — Slack / Teams / PagerDuty
#------------------------------------------------------------------------------

variable "alertmanager_webhook_url" {
  description = "URL do webhook para Alertmanager (Slack/Teams/PagerDuty). Vazio = sem notificações. Definir via TF_VAR_alertmanager_webhook_url."
  type        = string
  default     = ""
  sensitive   = true
}
