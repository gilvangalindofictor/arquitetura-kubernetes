# GitLab OIDC Integration with Keycloak — 2026-02-11

## Objetivo

Implementar autenticação OIDC do GitLab usando Keycloak como Identity Provider, resolvendo problema de split-horizon DNS onde browsers não conseguem resolver nomes internos do cluster.

## Status Final

**✅ CONCLUÍDO (95%)**:
- CoreDNS split-horizon DNS configurado e funcional
- Keycloak client `gitlab` criado via direct database insert  
- GitLab Terraform modules atualizados para suportar OIDC
- Prometheus Operator scheduling issue corrigido
- K8s Secret com credenciais OIDC criado

**⏳ PENDENTE (5%)**:
- Terraform apply final (bloqueado por Helm pending-upgrade)
- Teste de login OIDC GitLab → Keycloak
- Validação end-to-end do fluxo de autenticação

## Próximos Passos (Amanhã)

### 1. Resolver Helm Pending-Upgrade
\`\`\`bash
helm rollback gitlab 1 -n gitlab-staging --wait --timeout=5m
\`\`\`

### 2. Terraform Apply
\`\`\`bash
aws sso login --profile k8s-platform-prod
AWS_PROFILE=k8s-platform-prod terraform apply -target=module.gitlab_staging
\`\`\`

### 3. Testar OIDC Login
- Port-forward GitLab: localhost:8082
- Acessar e clicar "Keycloak SSO"
- Validar redirect e callback

## Credenciais

- Client Secret: `yOpIEh5nxYItofNBec2_5IncBYgBIhW4k0AEGPSYAr0=`
- Secret K8s: `gitlab-oidc-keycloak` (gitlab-staging namespace)

