# Policy: vault-admin
# Full secrets management for platform administrators
# Bound to Keycloak group: vault-admins (OIDC auth)
# Security: no path "*" — explicit paths only (ADR-032 least-privilege)
#
# =============================================================================
# FIX-009: ENVIRONMENT ISOLATION PLAN (2026-03-25)
# =============================================================================
# PROBLEM: This policy grants secret/* (CRUD) — any vault-admins group member
#          can create/read/update/delete secrets in ANY environment.
#          A staging admin can modify prod secrets and vice-versa.
#
# REQUIRED CHANGES (execute when prod OIDC is enabled):
#
#   1. Create vault-admin-staging.hcl and vault-admin-prod.hcl:
#      - vault-admin-staging: secret/data/staging/*, secret/metadata/staging/*,
#        + shared service paths (keycloak/*, harbor/*, etc.) with CRUD
#      - vault-admin-prod: secret/data/prod/*, secret/metadata/prod/*,
#        + shared service paths with CRUD
#      - Both retain sys/policies/acl (read/list), sys/mounts, sys/auth, auth/*
#
#   2. In main.tf, change vault_policy.vault_admin:
#      - name   = "vault-admin-${var.environment}"
#      - policy = templatefile("${path.module}/vault_policies/vault-admin-${var.environment}.hcl", {
#          environment = var.environment
#        })
#
#   3. Update OIDC role "admin" in main.tf:
#      - role_name      = "admin-${var.environment}"
#      - token_policies = ["vault-admin-${var.environment}"]
#      - bound_claims.groups = "vault-admins-${var.environment}" (requires Keycloak group split)
#
#   4. BLOCKER: Same as vault-reader — secret paths are not consistently env-prefixed.
#      See vault-reader.hcl FIX-009 comments for full analysis.
#
#   5. ADDITIONAL BLOCKER: Keycloak group "vault-admins" must be split into
#      "vault-admins-staging" and "vault-admins-prod" groups. This requires
#      Keycloak realm config changes + user re-assignment.
#
# EXECUTION ORDER:
#   Phase 1: Split env-prefixed paths only (staging/*, prod/*) — quick-win
#   Phase 2: Migrate all secrets to ${environment}/service/* — full isolation
#   Phase 3: Split Keycloak groups per environment
# =============================================================================

path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policies/acl" {
  capabilities = ["read", "list"]
}

path "sys/mounts" {
  capabilities = ["read", "list"]
}

path "sys/mounts/*" {
  capabilities = ["read"]
}

path "sys/auth" {
  capabilities = ["read", "list"]
}

path "sys/auth/*" {
  capabilities = ["read", "list"]
}

path "sys/health" {
  capabilities = ["read"]
}

path "auth/*" {
  capabilities = ["read", "list"]
}
