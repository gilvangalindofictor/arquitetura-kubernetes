# =============================================================================
# Keycloak Clients Module — Outputs
# Used by vault-config module to cross-reference client IDs
# =============================================================================

# -----------------------------------------------------------------------------
# Realm
# -----------------------------------------------------------------------------

output "realm_id" {
  description = "Keycloak platform realm UUID"
  value       = keycloak_realm.platform.id
}

output "realm_name" {
  description = "Keycloak platform realm name"
  value       = keycloak_realm.platform.realm
}

# -----------------------------------------------------------------------------
# GitLab Client
# -----------------------------------------------------------------------------

output "gitlab_client_id" {
  description = "GitLab OIDC client UUID in Keycloak (NOT the clientId string 'gitlab')"
  value       = var.gitlab_enabled ? keycloak_openid_client.gitlab[0].id : null
}

output "gitlab_client_client_id" {
  description = "GitLab OIDC clientId string (always 'gitlab')"
  value       = var.gitlab_enabled ? keycloak_openid_client.gitlab[0].client_id : null
}

# -----------------------------------------------------------------------------
# ArgoCD Client
# -----------------------------------------------------------------------------

output "argocd_client_id" {
  description = "ArgoCD OIDC client UUID in Keycloak"
  value       = var.argocd_enabled ? keycloak_openid_client.argocd[0].id : null
}

output "argocd_client_client_id" {
  description = "ArgoCD OIDC clientId string (always 'argocd')"
  value       = var.argocd_enabled ? keycloak_openid_client.argocd[0].client_id : null
}

# -----------------------------------------------------------------------------
# Grafana Client
# -----------------------------------------------------------------------------

output "grafana_client_id" {
  description = "Grafana OIDC client UUID in Keycloak"
  value       = var.grafana_enabled ? keycloak_openid_client.grafana[0].id : null
}

output "grafana_client_client_id" {
  description = "Grafana OIDC clientId string (always 'grafana')"
  value       = var.grafana_enabled ? keycloak_openid_client.grafana[0].client_id : null
}

# -----------------------------------------------------------------------------
# Groups
# -----------------------------------------------------------------------------

output "grafana_admins_group_id" {
  description = "grafana-admins group UUID in Keycloak platform realm. Used to add users via Keycloak UI or API."
  value       = var.grafana_admins_group_enabled ? keycloak_group.grafana_admins[0].id : null
}

output "grafana_admins_group_name" {
  description = "grafana-admins group name"
  value       = var.grafana_admins_group_enabled ? keycloak_group.grafana_admins[0].name : null
}

# -----------------------------------------------------------------------------
# Groups Mapper
# -----------------------------------------------------------------------------

output "grafana_groups_mapper_id" {
  description = "oidc-group-membership-mapper ID for groups claim on grafana client"
  value       = var.grafana_enabled && var.grafana_admins_group_enabled ? keycloak_generic_protocol_mapper.grafana_groups[0].id : null
}
