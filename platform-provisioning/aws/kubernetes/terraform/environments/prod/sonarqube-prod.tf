# =============================================================================
# DEPRECATED (ADR-050 2026-03-27): SonarQube reclassificado como PLATFORM-SHARED.
# Instancia unica em staging-platform-sonarqube serve staging+prod.
# Namespace prod-platform-sonarqube esvaziado em 2026-03-27 (helm uninstall + ExternalSecret deleted).
# GitLab CI pipeline ja aponta para instancia staging (sonarqube.staging.internal).
# GAP-CONF-021 FECHADO — instancia prod desnecessaria.
# =============================================================================
#
# module "sonarqube_prod" {
#   source = "../../modules/sonarqube"
#
#   depends_on = [
#     module.postgresql_prod
#   ]
#
#   cluster_name    = local.cluster_name
#   namespace       = "prod-platform-sonarqube"
#   postgresql_host = module.postgresql_prod.rds_address
#
#   # ALB Ingress — prod
#   ingress_enabled    = true
#   domain             = "sonarqube.alvocard.com.br"
#   ingress_group_name = "platform-prod"
#
#   # SAML desabilitado — requer Keycloak prod realm "platform" configurado
#   # Habilitar quando GAP-IPAAS-STAGING-001 resolver Keycloak realm prod
#   saml_enabled = false
#
#   # GitLab OAuth2 — compartilhado (GitLab e shared staging<->prod)
#   gitlab_oauth_enabled = true
#   gitlab_url           = "http://gitlab.staging.internal" # GitLab shared instance
#   gitlab_allow_signup  = false
#   gitlab_groups_sync   = true
#
#   # Storage
#   storage_class = "gp3"
#
#   # Monitoring
#   enable_monitoring = true
#
#   # ECR Pull-Through Cache
#   ecr_registry = "891377105802.dkr.ecr.us-east-1.amazonaws.com"
#
#   # ClusterSecretStore prod (FIX-006 parametrizado)
#   secret_store_name = "vault-backend"
#
#   # Tags
#   common_tags = local.k8s_common_tags
# }
