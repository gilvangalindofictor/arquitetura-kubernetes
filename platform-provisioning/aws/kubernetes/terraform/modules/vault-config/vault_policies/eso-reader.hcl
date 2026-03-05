# Policy for External Secrets Operator
# Read-only access to KV v2 paths
# Used by K8s ServiceAccount: external-secrets-system/external-secrets
# Security: Granular path restriction (ADR-032)
# Updated: 2026-02-18 — add sonarqube/*, grafana/*
# Updated: 2026-02-19 — add gitlab/*
# Updated: 2026-02-20 — add argocd/* (V-002 remediation)

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

path "secret/data/sonarqube/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/sonarqube/*" {
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

# Updated: 2026-03-05 — add staging/hatch/* (hatch-etl app secrets)
path "secret/data/staging/hatch/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/staging/hatch/*" {
  capabilities = ["read", "list"]
}
