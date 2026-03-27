# =============================================================================
# Backstage Prod — Module invocation
#
# DEPRECATED (2026-03-27 — ADR-050): Backstage reclassificado como PLATFORM-SHARED (Tier 2).
# Instancia unica em staging-platform-backstage serve staging+prod.
# Namespace prod-platform-backstage esvaziado em 2026-03-27 (workloads, secrets,
# ExternalSecrets, Ingress, ConfigMaps, Helm releases deletados).
# Namespace PRESERVADO para reuso futuro.
#
# HISTORICO:
#   2026-03-26: Vault secrets prod criados (9/9), module codificado, TF apply pendente
#   2026-03-27: Module COMENTADO — Backstage e PLATFORM-SHARED por ADR-050 decision tree:
#               "E consumido por multiplos ambientes?" -> NAO (developer portal/catalogo,
#               nao serve workloads de negocio). Instancia unica suficiente.
#
# GAP-BACKSTAGE-PROD-INTEGRATION (P2): Backstage staging NAO integra com ArgoCD prod
#   nem Keycloak prod. Se futuramente necessario, adicionar env vars para endpoints prod
#   no modulo staging (nao reativar este modulo).
#
# BLOQUEADORES RESOLVIDOS (2026-03-26):
#   1. Vault secrets prod CRIADOS (9/9):
#      - secret/prod/backstage/database    (backstage_prod user, dedicated DB)
#      - secret/prod/backstage/keycloak    (new client-secret generated)
#      - secret/prod/backstage/gitlab      (shared GitLab PAT)
#      - secret/prod/backstage/argocd      (prod ArgoCD admin token)
#      - secret/prod/backstage/sonarqube   (shared SonarQube token)
#      - secret/prod/backstage/vault       (prod Vault addr)
#      - secret/prod/backstage/eks         (shared EKS cluster URL)
#      - secret/prod/backstage/session     (new session secret generated)
#      - secret/prod/backstage/harbor      (shared Harbor robot account)
#   2. ClusterSecretStore vault-backend-prod: Ready=True (eso-reader policy covers prod/backstage/*)
#   3. Keycloak prod: client "backstage" TBD (client-secret pre-generated in Vault)
#   4. RDS prod: database "backstage_prod" + user "backstage_prod" CRIADOS
#   5. Imagem backstage: Harbor prod TBD (using harbor.prod.internal)
#   6. ExternalSecret pre-validation: 15/15 keys synced (Ready=True)
#
# PREREQUISITOS SENSÍVEIS (TF_VAR_xxx) — mantidos para referencia:
#   TF_VAR_backstage_prod_db_password
#   TF_VAR_backstage_prod_keycloak_client_secret
#   TF_VAR_backstage_prod_gitlab_token
#   TF_VAR_backstage_prod_argocd_token
#   TF_VAR_backstage_prod_sonarqube_token
#   TF_VAR_backstage_prod_auth_session_secret
#   TF_VAR_backstage_prod_harbor_robot_token
# =============================================================================

# -----------------------------------------------------------------------------
# Variables para Backstage prod — DEPRECATED (mantidas com default="" para
# evitar erro caso referenciadas em outputs ou outros modulos)
# -----------------------------------------------------------------------------

variable "backstage_prod_db_password" {
  description = "DEPRECATED — Backstage prod desativado (ADR-050 PLATFORM-SHARED)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_prod_keycloak_client_secret" {
  description = "DEPRECATED — Backstage prod desativado (ADR-050 PLATFORM-SHARED)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_prod_gitlab_token" {
  description = "DEPRECATED — Backstage prod desativado (ADR-050 PLATFORM-SHARED)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_prod_argocd_token" {
  description = "DEPRECATED — Backstage prod desativado (ADR-050 PLATFORM-SHARED)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_prod_sonarqube_token" {
  description = "DEPRECATED — Backstage prod desativado (ADR-050 PLATFORM-SHARED)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_prod_auth_session_secret" {
  description = "DEPRECATED — Backstage prod desativado (ADR-050 PLATFORM-SHARED)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backstage_prod_harbor_robot_token" {
  description = "DEPRECATED — Backstage prod desativado (ADR-050 PLATFORM-SHARED)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Module: Backstage Prod — COMENTADO (ADR-050 PLATFORM-SHARED 2026-03-27)
#
# DEPRECATED: Backstage reclassificado como PLATFORM-SHARED.
# Instancia unica em staging-platform-backstage serve staging+prod.
# Namespace prod-platform-backstage esvaziado em 2026-03-27.
# NAO reativar sem decisao explicita da mesa tecnica.
# -----------------------------------------------------------------------------

# module "backstage_prod" {
#   source = "../../modules/backstage"
#
#   depends_on = [
#     module.external_secrets_prod,
#     module.vault_config_prod,
#   ]
#
#   # Cluster info
#   cluster_name   = local.cluster_name
#   aws_account_id = var.aws_account_id
#   aws_region     = var.aws_region
#   namespace      = "prod-platform-backstage"
#
#   # Backstage chart + image
#   backstage_chart_version  = "2.6.3"
#   backstage_image_tag      = "1.48.0-oidc"
#   backstage_image_registry = "harbor.prod.internal"
#   replicas                 = 2 # HA: PDB minAvailable=1
#
#   # External service hosts (prod URLs)
#   keycloak_host = "keycloak.prod.internal"
#   gitlab_host   = "gitlab.staging.internal" # GitLab e shared (mesma instancia staging)
#
#   # Vault secret prefix (prod isolation)
#   vault_secret_prefix = "prod/backstage"
#
#   # PostgreSQL RDS (prod-isolated — backstage_prod database + user)
#   backstage_db_host     = module.postgresql_prod.rds_address
#   backstage_db_user     = "backstage_prod"
#   backstage_db_password = var.backstage_prod_db_password
#   backstage_db_port     = 5432
#
#   # Keycloak OIDC
#   backstage_keycloak_client_id     = "backstage"
#   backstage_keycloak_client_secret = var.backstage_prod_keycloak_client_secret
#
#   # GitLab (ALTO-2: Group Access Token obrigatorio)
#   backstage_gitlab_token = var.backstage_prod_gitlab_token
#
#   # ArgoCD plugin (aponta para ArgoCD prod)
#   backstage_argocd_url   = "http://argocd-server.prod-platform-argocd.svc.cluster.local"
#   backstage_argocd_token = var.backstage_prod_argocd_token
#
#   # SonarQube plugin (SonarQube e shared)
#   backstage_sonarqube_url   = "http://sonarqube-sonarqube.sonarqube.svc.cluster.local:9000"
#   backstage_sonarqube_token = var.backstage_prod_sonarqube_token
#
#   # Vault plugin (prod Vault)
#   backstage_vault_addr = "http://vault-prod.prod-security-vault.svc.cluster.local:8200"
#
#   # EKS cluster URL
#   backstage_eks_cluster_url = "https://EC913B145BF356481CBE823532F09150.gr7.us-east-1.eks.amazonaws.com"
#
#   # Session secret
#   backstage_auth_session_secret = var.backstage_prod_auth_session_secret
#
#   # Harbor plugin
#   backstage_harbor_url         = "https://harbor.prod.internal"
#   backstage_harbor_robot_token = var.backstage_prod_harbor_robot_token
#
#   # ClusterSecretStore prod (GAP-SEC-ESO-001)
#   secret_store_name = module.external_secrets_prod.cluster_secret_store_name
#
#   common_tags = local.k8s_common_tags
# }
