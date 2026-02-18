# Policy: vault-admin
# Full secrets management for platform administrators
# Bound to Keycloak group: vault-admins (OIDC auth)
# Security: no path "*" — explicit paths only (ADR-032 least-privilege)

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
