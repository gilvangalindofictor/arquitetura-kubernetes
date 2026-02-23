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
#   realms/platform.tf  → keycloak_realm.platform
#   clients/gitlab.tf   → keycloak_openid_client.gitlab[0]
#   clients/argocd.tf   → keycloak_openid_client.argocd[0]
#   clients/grafana.tf  → keycloak_openid_client.grafana[0]
#                         keycloak_generic_protocol_mapper.grafana_groups[0]
#                         keycloak_group.grafana_admins[0]
#
# Terraform treats all .tf files in a directory as a single module,
# so no explicit includes are needed.
