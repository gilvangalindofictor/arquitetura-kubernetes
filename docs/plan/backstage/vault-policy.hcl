# =============================================================================
# Vault policy: backstage-policy
# Role: backstage (Kubernetes auth method)
# Cluster: k8s-platform-prod (EKS, us-east-1)
# Namespace SA: staging-platform-backstage
# Criado: 2026-03-05
# ADR: ADR-055
#
# Aplicar:
#   vault policy write backstage-policy vault-policy.hcl
#
# Criar role Kubernetes auth:
#   vault write auth/kubernetes/role/backstage \
#     bound_service_account_names=backstage \
#     bound_service_account_namespaces=staging-platform-backstage \
#     policies=backstage-policy \
#     ttl=1h
#
# NOTA (MEDIO-1): Nao existe action oficial do Scaffolder para escrever no
# Vault KV v2 (RFC #32600 aberto). As capabilities create/update abaixo
# serao usadas por action customizada catalog:vault:write-namespace.
# =============================================================================

# -----------------------------------------------------------------------------
# Listar paths disponiveis (plugin Vault UI — navegacao sem expor valores)
# -----------------------------------------------------------------------------
path "secret/metadata/*" {
  capabilities = ["list"]
}

# -----------------------------------------------------------------------------
# Ler secrets da plataforma (integracoes externas — uso dos plugins)
# Ex: tokens ArgoCD, SonarQube, Harbor robot account
# -----------------------------------------------------------------------------
path "secret/data/platform/integrations/*" {
  capabilities = ["read"]
}

# -----------------------------------------------------------------------------
# Listar secrets por app (UI list-only — nao expoe valores)
# -----------------------------------------------------------------------------
path "secret/metadata/staging/+/*" {
  capabilities = ["list"]
}

# -----------------------------------------------------------------------------
# Scaffolder: criar namespace de nova app no Vault KV v2
# Usado pela action customizada catalog:vault:write-namespace (MEDIO-1)
# -----------------------------------------------------------------------------
path "secret/data/staging/+/*" {
  capabilities = ["create", "update"]
}

# -----------------------------------------------------------------------------
# Scaffolder: criar policy de nova app
# Necessario para o template criar policy isolada por servico
# -----------------------------------------------------------------------------
path "sys/policies/acl/+*" {
  capabilities = ["create", "update", "read"]
}

# -----------------------------------------------------------------------------
# Scaffolder: criar AppRole de nova app
# Necessario para o template criar AppRole isolada por servico
# -----------------------------------------------------------------------------
path "auth/approle/role/+*" {
  capabilities = ["create", "update", "read"]
}
