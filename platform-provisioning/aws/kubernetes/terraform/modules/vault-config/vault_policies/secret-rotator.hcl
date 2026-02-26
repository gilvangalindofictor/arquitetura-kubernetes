# Policy: secret-rotator
# Automated secret rotation CronJob permissions
# Used by K8s ServiceAccount: vault-system/secret-rotator
# Implements CICD-003: Quarterly Secret Rotation Automation
# ADR: ADR-083
# Created: 2026-02-26

# ------------------------------------------------------------------------------
# PostgreSQL credentials — read current + write rotated
# Covers: keycloak, gitlab, harbor, sonarqube databases
# ------------------------------------------------------------------------------

path "secret/data/keycloak/postgresql" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/keycloak/postgresql" {
  capabilities = ["read", "list"]
}

path "secret/data/gitlab/postgresql" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/gitlab/postgresql" {
  capabilities = ["read", "list"]
}

path "secret/data/harbor/postgresql" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/harbor/postgresql" {
  capabilities = ["read", "list"]
}

path "secret/data/sonarqube/postgresql" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/sonarqube/postgresql" {
  capabilities = ["read", "list"]
}

# RDS admin credentials — needed to execute ALTER USER on target databases
path "secret/data/postgresql-admin/*" {
  capabilities = ["read"]
}

path "secret/metadata/postgresql-admin/*" {
  capabilities = ["read", "list"]
}

# ------------------------------------------------------------------------------
# Keycloak admin credentials — read current + write rotated
# ------------------------------------------------------------------------------

path "secret/data/keycloak/admin" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/keycloak/admin" {
  capabilities = ["read", "list"]
}

# ------------------------------------------------------------------------------
# OIDC client secrets — read current + write rotated
# Covers: grafana, argocd, harbor, gitlab, vault, sonarqube
# ------------------------------------------------------------------------------

path "secret/data/grafana/oidc" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/grafana/oidc" {
  capabilities = ["read", "list"]
}

path "secret/data/argocd/oidc" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/argocd/oidc" {
  capabilities = ["read", "list"]
}

path "secret/data/harbor/oidc" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/harbor/oidc" {
  capabilities = ["read", "list"]
}

path "secret/data/gitlab/oidc" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/gitlab/oidc" {
  capabilities = ["read", "list"]
}

path "secret/data/vault/oidc" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/vault/oidc" {
  capabilities = ["read", "list"]
}

path "secret/data/sonarqube/saml" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/sonarqube/saml" {
  capabilities = ["read", "list"]
}

# ------------------------------------------------------------------------------
# Rotation job own token — used to store job state and last rotation timestamp
# ------------------------------------------------------------------------------

path "secret/data/secret-rotator/*" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/secret-rotator/*" {
  capabilities = ["read", "list"]
}

# ------------------------------------------------------------------------------
# Token capabilities — needed for token self-renewal during long rotation runs
# ------------------------------------------------------------------------------

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
