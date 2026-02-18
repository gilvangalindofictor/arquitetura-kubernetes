# Policy: vault-reader
# Read-only access to all secrets for authenticated platform users
# Default role for any Keycloak-authenticated user (OIDC auth)
# Note: eso-reader is for ESO ServiceAccount (K8s auth) — this is for human operators

path "secret/data/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

path "sys/health" {
  capabilities = ["read"]
}
