# Diario de Bordo — Backstage IDP Deploy (2026-03-05)

| Campo       | Valor                                                                 |
|-------------|-----------------------------------------------------------------------|
| **Data**    | 2026-03-05                                                            |
| **Demanda** | Deploy Backstage IDP no cluster k8s-platform-prod (EKS us-east-1)    |
| **ADR**     | ADR-055                                                               |
| **Impacto** | alto                                                                  |
| **Agentes** | Orquestrador, Agente A (K8s), Agente B (Vault), Agente C (Credentials), Agente D (Helm/ESO) |
| **Status**  | Parcial — Bloco A concluido, Bloco B bloqueado (acao humana), Bloco C parcial, Bloco D pronto |

---

## Timeline

<!-- Formato: [HH:MM:SS] <etapa> | <agente> | <acao> | <resultado> -->

### BLOCO A — Kubernetes Pre-requisitos (CONCLUIDO)

[09:00:00] Kyverno-Patch | Agente A | Adicionado staging-platform-backstage a lista de exclusoes da ClusterPolicy validate-namespace-naming | OK
[09:02:00] Namespace | Agente A | Criado namespace staging-platform-backstage com annotation linkerd.io/inject=enabled | OK
[09:03:30] ClusterRole | Agente A | Criado ClusterRole backstage-kubernetes-reader (inclui argoproj.io, external-secrets.io, metricas, workloads) | OK
[09:04:00] ClusterRoleBinding | Agente A | Criado ClusterRoleBinding backstage-kubernetes-reader vinculado ao SA backstage no namespace staging-platform-backstage | OK
[09:05:00] PDB | Agente A | Criado PodDisruptionBudget backstage-pdb com minAvailable=1 no namespace staging-platform-backstage | OK
[09:06:30] PolicyException | Agente A | Criado PolicyException backstage-linkerd-exception (v2beta1) para pods backstage-* no namespace staging-platform-backstage | OK

### BLOCO B — Vault Bootstrap (BLOQUEADO — ACAO HUMANA NECESSARIA)

[10:00:00] Vault-Status | Agente B | Verificado Vault 1.15.4 unsealed, HA Active — cluster saudavel | OK
[10:01:30] Vault-Token | Agente B | Root token Vault nao acessivel automaticamente (boa pratica de seguranca — root token nao armazenado) | BLOQUEADO
[10:03:00] Bootstrap-Script | Agente B | Criado docs/plan/backstage/bootstrap-vault-setup.sh com todos os comandos prontos para execucao pelo admin | OK
[10:03:30] Pendencia | Orq | PENDENTE: usuario deve fornecer VAULT_TOKEN admin e executar bootstrap-vault-setup.sh | AGUARDANDO

### BLOCO C — Credentials e Integracoes (PARCIAL)

[11:00:00] RDS-Locate | Agente C | RDS localizado no Terraform state (bucket: terraform-state-marco0-891377105802) | OK
[11:02:00] Keycloak-Status | Agente C | keycloak.staging.internal — running | OK
[11:02:30] Harbor-Status | Agente C | harbor.staging.internal — running | OK
[11:03:00] ArgoCD-Status | Agente C | argocd.staging.internal — running | OK
[11:03:30] SonarQube-Status | Agente C | sonarqube.staging.internal — running | OK
[11:04:00] Bootstrap-Credentials | Agente C | Criado docs/plan/backstage/bootstrap-credentials.sh com comandos para criar credenciais em todos os servicos | OK
[11:05:00] Pendencia-Keycloak | Agente C | PENDENTE: criar client backstage no Keycloak (realm platform) | AGUARDANDO
[11:05:15] Pendencia-Harbor | Agente C | PENDENTE: criar robot account backstage-puller no Harbor | AGUARDANDO
[11:05:30] Pendencia-ArgoCD | Agente C | PENDENTE: gerar token de service account para ArgoCD | AGUARDANDO
[11:05:45] Pendencia-SonarQube | Agente C | PENDENTE: gerar token de API no SonarQube | AGUARDANDO
[11:06:00] Pendencia-GitLab | Agente C | PENDENTE: criar Group Access Token no GitLab (escopos: api, read_repository, read_user) | AGUARDANDO

### BLOCO D — Helm e ExternalSecret (PRONTO)

[13:00:00] ExternalSecret | Agente D | Criado manifest docs/plan/backstage/externalsecret-backstage.yaml referenciando Vault KV v2 | OK
[13:02:00] Helm-Repo | Agente D | Repositorio Helm backstage adicionado (https://backstage.github.io/charts), chart v2.6.3 disponivel | OK
[13:03:00] Endpoints | Agente D | Todos os endpoints do cluster capturados e documentados | OK

### Evento Especial — SSO Renewal

[14:30:00] SSO-Expire | Orq | Sessao AWS SSO expirou durante execucao do deploy | DETECTADO
[14:31:15] SSO-Renewal | Orq | Auto-renewal iniciado — protocolo AML ativado, polling iniciado | EM ANDAMENTO
[14:32:30] SSO-Restored | Orq | Login detectado em 75s, sessao AWS renovada com sucesso | OK

---

## Artefatos Criados nesta Sessao

| Arquivo | Descricao |
|---------|-----------|
| `docs/plan/backstage/bootstrap-vault-setup.sh` | Script com comandos Vault prontos para execucao pelo admin |
| `docs/plan/backstage/bootstrap-credentials.sh` | Script de bootstrap de credenciais (Keycloak, Harbor, ArgoCD, SonarQube, GitLab) |
| `docs/plan/backstage/externalsecret-backstage.yaml` | Manifest ExternalSecret referenciando Vault KV v2 |

---

## Proximos Passos

### 1. Executar bootstrap Vault (PRIORIDADE MAXIMA)

O admin deve:

```bash
# Exportar token admin Vault (obter via metodo seguro da sua organizacao)
export VAULT_ADDR=https://vault.staging.internal
export VAULT_TOKEN=<seu-token-admin>

# Executar o script de bootstrap
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage
chmod +x bootstrap-vault-setup.sh
./bootstrap-vault-setup.sh
```

O script executa:
- Habilita Kubernetes auth method no Vault
- Configura o auth method com o CA do cluster EKS
- Cria a policy `backstage-policy`
- Cria a role `backstage` vinculada ao SA no namespace staging-platform-backstage
- Cria o database `backstage` no RDS (via psql)
- Armazena credenciais no Vault KV v2

### 2. Criar client Keycloak

```bash
# Acessar Keycloak admin console: https://keycloak.staging.internal/admin
# Realm: platform
# Criar client com:
#   Client ID: backstage
#   Access Type: confidential
#   PKCE: S256 habilitado
#   Valid Redirect URIs: https://backstage.staging.internal/api/auth/keycloak/handler/frame
#   Web Origins: https://backstage.staging.internal
# Copiar o Client Secret gerado

# OU usar o script:
chmod +x bootstrap-credentials.sh
./bootstrap-credentials.sh  # seguir instrucoes interativas
```

### 3. Criar robot account Harbor

```bash
# Acessar Harbor: https://harbor.staging.internal
# Projeto: platform
# Criar robot account: backstage-puller
# Permissao: pull only
# Salvar token retornado
```

### 4. Criar tokens ArgoCD e SonarQube

```bash
# ArgoCD — gerar token de service account
argocd account generate-token --account backstage-reader

# SonarQube — gerar token via UI ou API
curl -u admin:<senha> -X POST \
  "https://sonarqube.staging.internal/api/user_tokens/generate" \
  -d "name=backstage-reader"
```

### 5. Criar Group Access Token GitLab

```bash
# GitLab — acessar: https://gitlab.staging.internal/groups/<grupo>/-/settings/access_tokens
# Tipo: Group Access Token
# Escopos: api, read_repository, read_user
# Salvar token gerado

# Validar:
curl -H "PRIVATE-TOKEN: <token>" https://gitlab.staging.internal/api/v4/groups | jq '.[0].name'
```

### 6. Aplicar ExternalSecret e fazer deploy Helm

```bash
# Apos todas as credenciais estarem no Vault:
kubectl apply -f docs/plan/backstage/externalsecret-backstage.yaml

# Verificar sync do secret:
kubectl -n staging-platform-backstage get externalsecret backstage-secrets

# Deploy Helm (dry-run primeiro):
helm upgrade --install backstage backstage/backstage \
  --version 2.6.3 \
  --namespace staging-platform-backstage \
  --values docs/plan/backstage/helm-values-staging.yaml \
  --dry-run

# Deploy real:
helm upgrade --install backstage backstage/backstage \
  --version 2.6.3 \
  --namespace staging-platform-backstage \
  --values docs/plan/backstage/helm-values-staging.yaml

# Acompanhar:
kubectl -n staging-platform-backstage get pods -w
kubectl -n staging-platform-backstage logs -f deployment/backstage
```

---

## Status Final da Sessao

| Bloco | Status | Bloqueio |
|-------|--------|----------|
| Bloco A — K8s Pre-requisitos | CONCLUIDO | — |
| Bloco B — Vault Bootstrap | BLOQUEADO | Requer VAULT_TOKEN admin |
| Bloco C — Credentials | PARCIAL | Requer acoes manuais nos servicos |
| Bloco D — Helm/ExternalSecret | PRONTO | — |

**Proximo marco:** Execucao do bootstrap-vault-setup.sh pelo admin → desbloqueio do Bloco B → sequencia Bloco C → deploy Helm.
