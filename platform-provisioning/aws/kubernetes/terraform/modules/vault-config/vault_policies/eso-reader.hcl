# Policy for External Secrets Operator
# Read-only access to secret/keycloak/* (KV v2)
# Used by K8s ServiceAccount: external-secrets-system/external-secrets
# Security: Granular path restriction (ADR-032)

path "secret/data/keycloak/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/keycloak/*" {
  capabilities = ["read", "list"]
}
