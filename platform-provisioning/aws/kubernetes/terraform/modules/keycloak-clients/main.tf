# =============================================================================
# Keycloak Clients Module — Main Entry Point
# Purpose: Manage Keycloak realm, clients and groups via Terraform provider
# Provider: mrparkers/keycloak ~> 4.4.0
# Keycloak: 26.5.1 (codecentric/keycloakx 7.1.7)
#
# ARCHITECTURE:
#   modules/keycloak-clients/
#   ├── main.tf          ← this file (wires sub-resources, locals)
#   ├── versions.tf      ← required_providers (mrparkers/keycloak ~> 4.4.0)
#   ├── provider.tf      ← keycloak provider (localhost port-forward, WSL-safe)
#   ├── variables.tf     ← all input variables
#   ├── outputs.tf       ← exported values (client UUIDs, group UUID)
#   ├── realms/
#   │   └── platform.tf  ← keycloak_realm.platform (import existing)
#   └── clients/
#       ├── gitlab.tf    ← keycloak_openid_client.gitlab
#       ├── argocd.tf    ← keycloak_openid_client.argocd
#       └── grafana.tf   ← keycloak_openid_client.grafana
#                           keycloak_generic_protocol_mapper.grafana_groups
#                           keycloak_group.grafana_admins
#
# MIGRATION FROM null_resource:
#   null_resource.keycloak_grafana_admins_group (Python port-forward) →
#     keycloak_group.grafana_admins          (native provider)
#     keycloak_generic_protocol_mapper.grafana_groups (native provider)
#   After import: remove null_resource from environments/staging/main.tf
#
# IMPORT PROCEDURE:
#   See scripts/keycloak/import-clients.sh for the full sequence.
#   Run AFTER `terraform init` in environments/staging/ (mrparkers provider downloaded).
#
# WSL-safe provider pattern (MEMORY.md):
#   keycloak.staging.internal resolves only inside cluster (CoreDNS split-horizon)
#   From WSL2 → use kubectl port-forward → localhost:18080
#   kubectl port-forward svc/keycloak-keycloakx-http 18080:80 -n keycloak &
#
# Keycloak 26.5.1 /auth prefix (MEMORY.md):
#   Provider URL must be: http://localhost:18080  (NO /auth suffix — provider appends it)
#   Admin API internally: /auth/admin/realms/...
#   Token:                /auth/realms/master/protocol/openid-connect/token
#
# ADR: TASK-002-terraform-keycloak-provider.md
# =============================================================================

locals {
  # Realm ID reference (used by clients and mappers)
  # keycloak_realm.platform is defined in realms/platform.tf
  realm_id = keycloak_realm.platform.id
}

# NOTE: All resources are defined in their respective sub-files:
#   realms/platform.tf      → keycloak_realm.platform
#   clients/gitlab.tf       → keycloak_openid_client.gitlab[0]
#   clients/argocd.tf       → keycloak_openid_client.argocd[0]
#   clients/grafana.tf      → keycloak_openid_client.grafana[0]
#                             keycloak_generic_protocol_mapper.grafana_groups[0]
#                             keycloak_group.grafana_admins[0]
#   clients/harbor.tf       → keycloak_openid_client.harbor[0]      (PKCE: S256)
#   clients/vault.tf        → keycloak_openid_client.vault[0]       (PKCE: S256)
#   clients/sonarqube.tf    → keycloak_saml_client.sonarqube[0]     (SAML 2.0, NOT OIDC)
#                             keycloak_saml_user_attribute_protocol_mapper.sonarqube_email[0]
#                             keycloak_saml_user_property_protocol_mapper.sonarqube_name[0]
#
# Terraform treats all .tf files in a directory as a single module,
# so no explicit includes are needed.
#
# CLIENT SUMMARY (6 clients, 1 realm):
#   OIDC (PKCE S256):  gitlab, grafana, harbor, vault
#   OIDC (no PKCE):    argocd  (TODO: enable after TASK-001 ArgoCD upgrade)
#   SAML 2.0:          sonarqube
#
# IMPORT ORDER (scripts/keycloak/import-clients.sh):
#   1. keycloak_realm.platform
#   2. keycloak_openid_client.gitlab[0]
#   3. keycloak_openid_client.argocd[0]
#   4. keycloak_openid_client.grafana[0]
#   5. keycloak_openid_client.harbor[0]
#   6. keycloak_openid_client.vault[0]
#   7. keycloak_saml_client.sonarqube[0]
#   8. keycloak_group.grafana_admins[0]
#   9. keycloak_generic_protocol_mapper.grafana_groups[0]
#  10. keycloak_saml_user_attribute_protocol_mapper.sonarqube_email[0]
#  11. keycloak_saml_user_property_protocol_mapper.sonarqube_name[0]
