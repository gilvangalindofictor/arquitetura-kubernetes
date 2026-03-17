# =============================================================================
# Vault policy: backstage-scaffolder
# Role: backstage (Kubernetes auth method)
# Namespace SA: staging-platform-backstage
# Criado via: configmap-setup.sh (GAP-S6C-01)
#
# Complementa backstage-policy com capabilities para o Scaffolder criar
# namespaces de novas apps via action customizada catalog:vault:write-namespace
# Ref: ADR-055, MEDIO-1 (RFC #32600)
# =============================================================================

# Listar todos os paths de secrets (navegacao UI)
path "secret/metadata/*" {
  capabilities = ["list"]
}

# Ler secrets de integracoes da plataforma (ArgoCD, GitLab, SonarQube, Harbor)
path "secret/data/platform/integrations/*" {
  capabilities = ["read"]
}

# Listar secrets por ambiente (UI list-only — nao expoe valores)
path "secret/metadata/staging/+/*" {
  capabilities = ["read", "list"]
}

# Scaffolder: criar e atualizar namespace KV v2 de novas apps no staging
# Usado pela action catalog:vault:write-namespace (MEDIO-1)
path "secret/data/staging/+/*" {
  capabilities = ["create", "update", "read", "list"]
}

# Scaffolder: criar policies isoladas por servico
path "sys/policies/acl/+*" {
  capabilities = ["create", "update", "read"]
}

# Scaffolder: criar e ler AppRoles para novas apps
path "auth/approle/role/+*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Scaffolder: gerar role-id e secret-id para AppRoles criadas
path "auth/approle/role/+/role-id" {
  capabilities = ["read"]
}
path "auth/approle/role/+/secret-id" {
  capabilities = ["create", "update"]
}

# Kubernetes auth: criar roles de novas apps (vincula SA ao AppRole/policy)
path "auth/kubernetes/role/+*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
