# Policy: vault-reader
# Read-only access to all secrets for authenticated platform users
# Default role for any Keycloak-authenticated user (OIDC auth)
# Note: eso-reader is for ESO ServiceAccount (K8s auth) — this is for human operators
#
# =============================================================================
# FIX-009: ENVIRONMENT ISOLATION PLAN (2026-03-25)
# =============================================================================
# PROBLEM: This policy grants secret/data/* — any OIDC-authenticated user can
#          read ALL secrets across ALL environments (staging + prod).
#          A staging operator can read prod secrets and vice-versa.
#
# CURRENT STATE: oidc_enabled=false in prod, so this only affects staging today.
#                But when prod OIDC is enabled, both envs will share this policy.
#
# REQUIRED CHANGES (execute when prod OIDC is enabled):
#
#   1. Create vault-reader-staging.hcl and vault-reader-prod.hcl:
#      - vault-reader-staging: secret/data/staging/*, secret/data/keycloak/*,
#        secret/data/harbor/*, secret/data/grafana/*, secret/data/gitlab/*,
#        secret/data/argocd/*, secret/data/sonarqube/*, secret/data/monitoring/*,
#        + matching secret/metadata/* paths
#      - vault-reader-prod: secret/data/prod/*, + same service paths above
#        (services are shared — keycloak, harbor, etc. are not env-prefixed in Vault)
#
#   2. In main.tf, change vault_policy.vault_reader:
#      - name   = "vault-reader-${var.environment}"
#      - policy = templatefile("${path.module}/vault_policies/vault-reader-${var.environment}.hcl", {
#          environment = var.environment
#        })
#
#   3. Update OIDC role "reader" in main.tf:
#      - role_name      = "reader-${var.environment}"
#      - token_policies = ["vault-reader-${var.environment}"]
#
#   4. BLOCKER: Vault secret paths are NOT consistently env-prefixed.
#      Services like keycloak/*, harbor/*, grafana/* are shared paths (no env prefix).
#      Only hatch-etl and backstage use ${environment}/ prefix.
#      True isolation requires EITHER:
#        a) Migrating ALL secrets to ${environment}/service/* paths (BREAKING — ESO remoteRefs change)
#        b) Accepting that service-level secrets (keycloak/*, harbor/*) are shared across envs
#           and only isolating env-prefixed paths (partial fix)
#
#   5. RECOMMENDED APPROACH: Option (b) first as quick-win, then Option (a) in Q2 2026.
#      Quick-win: split env-prefixed paths (staging/*, prod/*) into separate policies.
#      Full fix: migrate all secrets to ${environment}/service/* namespace.
#
# RISK: Modifying policy names requires re-binding OIDC auth roles. If done incorrectly,
#       Keycloak SSO users lose Vault access. Test in staging first, 48h soak, then prod.
# =============================================================================

path "secret/data/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

path "sys/health" {
  capabilities = ["read"]
}
