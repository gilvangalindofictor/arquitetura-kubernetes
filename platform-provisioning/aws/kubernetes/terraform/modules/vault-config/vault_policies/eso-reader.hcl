# Policy for External Secrets Operator
# Read-only access to KV v2 paths
# Used by K8s ServiceAccount: external-secrets-system/external-secrets
# Security: Granular path restriction (ADR-032)
# Updated: 2026-02-18 — add sonarqube/*, grafana/*
# Updated: 2026-02-19 — add gitlab/*
# Updated: 2026-02-20 — add argocd/* (V-002 remediation)
# Updated: 2026-03-06 — add staging/backstage/* (ADR-055 Backstage IDP)
# Updated: 2026-03-09 — add redis/*, velero/*, monitoring/*, postgresql-admin/*, secret-rotator/* (SEC-MIG-001 GAP fix)

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

# Updated: 2026-03-06 — add staging/backstage/* (ADR-055 Backstage IDP)
path "secret/data/staging/backstage/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/staging/backstage/*" {
  capabilities = ["read", "list"]
}

# Updated: 2026-03-09 — SEC-MIG-001 GAP fix: paths referenced by ESO but missing from policy
# Root cause: ExternalSecrets were created for these paths but policy was never updated.
# Actual Vault paths discovered from ExternalSecret specs (not assumed paths):
#   alertmanager-slack-webhook => secret/monitoring/alertmanager
#   secret-rotator-rds-admin   => secret/postgresql-admin/password
#   secret-rotator-vault-token => secret/secret-rotator/token

path "secret/data/redis/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/redis/*" {
  capabilities = ["read", "list"]
}

path "secret/data/velero/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/velero/*" {
  capabilities = ["read", "list"]
}

path "secret/data/monitoring/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/monitoring/*" {
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

path "secret/data/alertmanager/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/alertmanager/*" {
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
