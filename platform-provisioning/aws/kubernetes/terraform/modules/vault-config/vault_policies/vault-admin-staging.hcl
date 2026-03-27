# Policy: vault-admin-staging
# Platform administrators — STAGING environment only
# Bound to Keycloak group: vault-admins (OIDC auth)
# GAP-CONF-014 (P1) + FIX-009 Phase 1: Replace secret/* wildcard with explicit paths
# Date: 2026-03-26 | Security & Resilience Specialist
#
# =============================================================================
# FIX-009 Phase 1: Split env-prefixed paths only (quick-win)
# Phase 2 TODO: Migrate all secrets to ${environment}/service/* for full isolation
# Phase 3 TODO: Split Keycloak groups per environment
# =============================================================================

# --- Environment-scoped secrets (staging only) ---
path "secret/data/staging/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/staging/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# --- Shared service secrets (CRUD — services not yet env-prefixed) ---
# These paths are shared across environments until Phase 2 migration.
# Keycloak
path "secret/data/keycloak/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/keycloak/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Harbor
path "secret/data/harbor/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/harbor/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Grafana
path "secret/data/grafana/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/grafana/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# GitLab
path "secret/data/gitlab/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/gitlab/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# ArgoCD
path "secret/data/argocd/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/argocd/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# SonarQube
path "secret/data/sonarqube/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/sonarqube/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Redis
path "secret/data/redis/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/redis/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Monitoring / Alertmanager
path "secret/data/monitoring/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/monitoring/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/alertmanager/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/alertmanager/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Velero
path "secret/data/velero/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/velero/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# PostgreSQL Admin
path "secret/data/postgresql-admin/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/postgresql-admin/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Secret Rotator
path "secret/data/secret-rotator/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/secret-rotator/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# RDS
path "secret/data/rds/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/rds/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Vault (self-referential secrets like OIDC)
path "secret/data/vault/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/vault/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# --- DENY prod-scoped secrets (staging admin cannot touch prod) ---
# NOTE: HCL deny is implicit — paths not listed are denied.
# prod/* paths are NOT included, so staging admin cannot access them.

# --- System paths (retained from original vault-admin.hcl) ---
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
