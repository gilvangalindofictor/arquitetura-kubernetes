# =============================================================================
# Vault Policy: secret-rotation
# CICD-003 | ADR-083 | Quarterly Automated Secret Rotation
#
# Purpose:
#   Grants the secret-rotator CronJob service account the minimum permissions
#   required to perform quarterly credential rotation for all platform services.
#
# Principal:
#   - Kubernetes ServiceAccount: secret-rotator (namespace: staging-security-vault)
#   - Vault Auth Method: kubernetes (k8s-platform-prod cluster)
#
# Usage:
#   vault policy write secret-rotation scripts/vault/vault-rotation-policy.hcl
#   vault policy read secret-rotation
#
# To bind to Kubernetes ServiceAccount:
#   vault write auth/kubernetes/role/secret-rotator \
#     bound_service_account_names=secret-rotator \
#     bound_service_account_namespaces=staging-security-vault \
#     policies=secret-rotation \
#     ttl=1h
# =============================================================================

# ---------------------------------------------------------------------------
# READ: Existing secrets (needed to verify current state before rotation)
# ---------------------------------------------------------------------------

# PostgreSQL credentials for all platform databases
path "secret/data/postgresql-admin/password" {
  capabilities = ["read"]
}

path "secret/data/keycloak/postgresql" {
  capabilities = ["read"]
}

path "secret/data/harbor/postgresql" {
  capabilities = ["read"]
}

path "secret/data/sonarqube/postgresql" {
  capabilities = ["read"]
}

path "secret/data/gitlab/postgresql" {
  capabilities = ["read"]
}

# Keycloak admin credentials
path "secret/data/keycloak/admin" {
  capabilities = ["read"]
}

# OIDC client secrets
path "secret/data/grafana/oidc" {
  capabilities = ["read"]
}

path "secret/data/argocd/oidc" {
  capabilities = ["read"]
}

path "secret/data/harbor/oidc" {
  capabilities = ["read"]
}

path "secret/data/gitlab/oidc" {
  capabilities = ["read"]
}

path "secret/data/vault/oidc" {
  capabilities = ["read"]
}

# SAML secrets (SonarQube)
path "secret/data/sonarqube/saml" {
  capabilities = ["read"]
}

# Harbor admin credentials
path "secret/data/harbor/admin" {
  capabilities = ["read"]
}

# Redis credentials
path "secret/data/harbor/redis" {
  capabilities = ["read"]
}

# GitLab CI variables
path "secret/data/gitlab/ci-variables" {
  capabilities = ["read"]
}

# ---------------------------------------------------------------------------
# WRITE: Update secrets after successful rotation
# ---------------------------------------------------------------------------

# PostgreSQL credentials — write new passwords after ALTER USER
path "secret/data/keycloak/postgresql" {
  capabilities = ["create", "update"]
}

path "secret/data/harbor/postgresql" {
  capabilities = ["create", "update"]
}

path "secret/data/sonarqube/postgresql" {
  capabilities = ["create", "update"]
}

path "secret/data/gitlab/postgresql" {
  capabilities = ["create", "update"]
}

# Keycloak admin — write new password after Keycloak API update
path "secret/data/keycloak/admin" {
  capabilities = ["create", "update"]
}

# OIDC client secrets — write new client secret after Keycloak regenerate
path "secret/data/grafana/oidc" {
  capabilities = ["create", "update"]
}

path "secret/data/argocd/oidc" {
  capabilities = ["create", "update"]
}

path "secret/data/harbor/oidc" {
  capabilities = ["create", "update"]
}

path "secret/data/gitlab/oidc" {
  capabilities = ["create", "update"]
}

path "secret/data/vault/oidc" {
  capabilities = ["create", "update"]
}

# SAML secrets (SonarQube SP certificate / metadata)
path "secret/data/sonarqube/saml" {
  capabilities = ["create", "update"]
}

# Harbor admin — write new password after Harbor API update
path "secret/data/harbor/admin" {
  capabilities = ["create", "update"]
}

# ---------------------------------------------------------------------------
# AUDIT: Write rotation log entry after each run
# Records: rotation_id, date, success/failure per service, next_rotation_date
# ---------------------------------------------------------------------------
path "secret/data/secret-rotator/last-rotation" {
  capabilities = ["create", "update", "read"]
}

path "secret/metadata/secret-rotator/last-rotation" {
  capabilities = ["read", "list"]
}

# ---------------------------------------------------------------------------
# READ self-token (for token renewal during long rotations)
# ---------------------------------------------------------------------------
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# ---------------------------------------------------------------------------
# READ metadata (for secret age monitoring — SecretAgeExceeded alert)
# ---------------------------------------------------------------------------
path "secret/metadata/keycloak/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/harbor/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/sonarqube/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/gitlab/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/grafana/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/argocd/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/postgresql-admin/*" {
  capabilities = ["read", "list"]
}

# ---------------------------------------------------------------------------
# DENY: Explicit deny for destructive operations (principle of least privilege)
# The rotator MUST NOT be able to delete secrets or manage Vault itself.
# ---------------------------------------------------------------------------
path "secret/delete/*" {
  capabilities = ["deny"]
}

path "secret/destroy/*" {
  capabilities = ["deny"]
}

path "sys/*" {
  capabilities = ["deny"]
}

path "auth/*" {
  capabilities = ["deny"]
}

# Exception: allow auth/token/lookup-self and auth/token/renew-self (above)
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
