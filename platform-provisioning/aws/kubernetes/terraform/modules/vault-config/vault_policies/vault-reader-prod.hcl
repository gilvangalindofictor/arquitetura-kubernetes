# Policy: vault-reader-prod
# Read-only access for authenticated PROD platform users
# GAP-CONF-014 (P1) + FIX-009 Phase 1: Replace secret/data/* wildcard
# Date: 2026-03-26 | Security & Resilience Specialist
#
# Phase 1: prod/* + shared service paths (read-only)
# Phase 2 TODO: Migrate all secrets to prod/service/*

# --- Environment-scoped secrets (prod only) ---
path "secret/data/prod/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/prod/*" {
  capabilities = ["read", "list"]
}

# --- Shared service secrets (read-only — not yet env-prefixed) ---
path "secret/data/keycloak/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/keycloak/*" {
  capabilities = ["read", "list"]
}

path "secret/data/harbor/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/harbor/*" {
  capabilities = ["read", "list"]
}

path "secret/data/grafana/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/grafana/*" {
  capabilities = ["read", "list"]
}

path "secret/data/gitlab/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/gitlab/*" {
  capabilities = ["read", "list"]
}

path "secret/data/argocd/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/argocd/*" {
  capabilities = ["read", "list"]
}

path "secret/data/sonarqube/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/sonarqube/*" {
  capabilities = ["read", "list"]
}

path "secret/data/redis/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/redis/*" {
  capabilities = ["read", "list"]
}

path "secret/data/monitoring/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/monitoring/*" {
  capabilities = ["read", "list"]
}

path "secret/data/alertmanager/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/alertmanager/*" {
  capabilities = ["read", "list"]
}

path "secret/data/velero/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/velero/*" {
  capabilities = ["read", "list"]
}

path "secret/data/postgresql-admin/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/postgresql-admin/*" {
  capabilities = ["read", "list"]
}

path "secret/data/secret-rotator/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/secret-rotator/*" {
  capabilities = ["read", "list"]
}

path "secret/data/rds/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/rds/*" {
  capabilities = ["read", "list"]
}

path "secret/data/vault/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/vault/*" {
  capabilities = ["read", "list"]
}

# --- System paths ---
path "sys/health" {
  capabilities = ["read"]
}
