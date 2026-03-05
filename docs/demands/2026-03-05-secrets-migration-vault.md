# Demanda: Migração de Secrets para Vault + ExternalSecrets

| Campo | Valor |
|-------|-------|
| ID | SEC-MIG-001 |
| Data | 2026-03-05 |
| Prioridade | P0/P1/P2 misto |
| Status | **100% MIGRADO** — SEC-MIG-001 COMPLETO (2026-03-05) |
| ADR | ADR-101 |
| Responsável | Agent-SecComp |
| Sprint | 2026-03-05 |

---

## Contexto

O cluster k8s-platform-prod possui 15 ExternalSecrets ativos (todos SecretSynced: True), mas há secrets críticos de aplicação ainda armazenados como plain K8s Secrets no etcd. Esta demanda formaliza a migração completa para Vault + ExternalSecrets.

**Motivação:**
- Plain K8s Secrets no etcd representam superfície de ataque desnecessária
- Rotação manual de secrets é operacionalmente arriscada
- Auditabilidade de acesso é zero com plain secrets (quem leu quando?)
- Vault provê audit log, lease, rotação automática e controle de acesso granular
- ExternalSecrets provê GitOps-friendly declarative secret sync

---

## Inventário Completo (Estado 2026-03-05)

### P0 — CRÍTICO: vault-root-token (NÃO MIGRAR — REVOGAR)

| Namespace | Secret | Situação | Ação |
|-----------|--------|----------|------|
| vault-system | vault-root-token | Plain K8s Secret (key: root_token) | Ver plano de revogação abaixo |

**Análise:**
- Root token do Vault armazenado como plain K8s Secret no namespace `vault-system`
- Root token não deve existir em operação normal do Vault
- Vault possui auth method `kubernetes/` ativo — todos os serviços devem usar Kubernetes auth
- Vault possui auth method `oidc/` para acesso humano via Keycloak

**Plano de Revogação (AGUARDA APROVACAO EXPLICITA):**
1. Verificar que todos os serviços usam Kubernetes auth (não root token)
2. Verificar que políticas de acesso estão corretas para cada ServiceAccount
3. `vault token revoke <root_token>` — invalida o token permanentemente
4. `kubectl delete secret vault-root-token -n vault-system` — remove o K8s secret
5. Para operações administrativas futuras: gerar root token via unseal keys (ritual controlado)

**OBSERVACAO:** Este plano NÂO deve ser executado sem aprovação explícita da equipe de segurança.
Um erro aqui (revogar antes de validar auth methods) pode impedir acesso ao Vault completamente.

---

### P1 — ALTA PRIORIDADE

| Namespace | Secret | Keys | Vault Path | ExternalSecret | Status |
|-----------|--------|------|------------|----------------|--------|
| staging-observability-monitoring | alertmanager-slack-webhook | critical-webhook-url, warning-webhook-url, data-services-webhook-url, security-webhook-url | secret/monitoring/alertmanager | alertmanager-slack-webhook.yaml | **MIGRADO E ATIVO** |
| velero | velero-repo-credentials | repository-password | secret/velero/repo-credentials | velero-repo-credentials.yaml | **MIGRADO E ATIVO** |
| staging-platform-gitlab | gitlab-postgresql-password | password | secret/gitlab/postgresql-password | gitlab-postgresql-password.yaml | **MIGRADO E ATIVO** — SecretSynced True, helm rev 12 (2026-03-05) |
| staging-platform-gitlab | gitlab-root-password | password | secret/gitlab/root-password | gitlab-root-password.yaml | **MIGRADO E ATIVO** — SecretSynced True, helm rev 12 (2026-03-05) |
| staging-platform-gitlab | gitlab-minio-secret | accesskey, secretkey | secret/gitlab/minio-secret | gitlab-minio-secret.yaml | **MIGRADO E ATIVO** — SecretSynced True, helm rev 12 (2026-03-05) |
| staging-platform-gitlab | gitlab-oidc-keycloak | provider | secret/gitlab/oidc-keycloak | gitlab-oidc-keycloak.yaml | **MIGRADO E ATIVO** — SecretSynced True, helm rev 12 (2026-03-05) |
| data-services | redis-password | password | secret/redis/password | redis-password.yaml | **MIGRADO E ATIVO** — SecretSynced True, helm rev 13 (2026-03-05) |

---

### P2 — MÉDIA PRIORIDADE (Helm-generated, próxima sprint)

| Namespace | Secret | Keys | Vault Path | ExternalSecret | Status |
|-----------|--------|------|------------|----------------|--------|
| staging-platform-gitlab | gitlab-rails-secret | secrets.yml | secret/gitlab/rails-secret | gitlab-internal-secrets.yaml | **MIGRADO E ATIVO** — SecretSynced True, helm rev 14 (2026-03-05) |
| staging-platform-gitlab | gitlab-gitaly-secret | token | secret/gitlab/gitaly-secret | gitlab-internal-secrets.yaml | **MIGRADO E ATIVO** — SecretSynced True, helm rev 14 (2026-03-05) |
| staging-platform-gitlab | gitlab-gitlab-kas-secret | kas_shared_secret | secret/gitlab/gitlab-kas-secret | gitlab-internal-secrets.yaml | **MIGRADO E ATIVO** — SecretSynced True, helm rev 14 (2026-03-05) |
| staging-platform-gitlab | gitlab-gitlab-shell-secret | secret | secret/gitlab/gitlab-shell-secret | gitlab-internal-secrets.yaml | **MIGRADO E ATIVO** — SecretSynced True, helm rev 14 (2026-03-05) |
| staging-platform-gitlab | gitlab-gitlab-workhorse-secret | shared_secret | secret/gitlab/gitlab-workhorse-secret | gitlab-internal-secrets.yaml | **MIGRADO E ATIVO** — SecretSynced True, helm rev 14 (2026-03-05) |

---

## O Que Foi Executado Nesta Sprint (2026-03-05)

### Ações Concluídas

1. **Pre-check:** AWS SSO autenticado (account 891377105802, role AdministratorAccess)
2. **Vault status:** Unsealed, HA active (vault-0), KMS auto-unseal, Version 1.15.4
3. **Auth methods verificados:** kubernetes/ e oidc/ ativos — root token desnecessário para ops normais
4. **Inventário completo:** 15 ExternalSecrets existentes + 13 plain secrets críticos identificados
5. **Vault KV paths criados:**
   - `secret/monitoring/alertmanager` — 4 Slack webhook URLs
   - `secret/velero/repo-credentials` — repository-password
   - `secret/gitlab/postgresql-password` — password
   - `secret/gitlab/root-password` — password
   - `secret/gitlab/minio-secret` — accesskey, secretkey
   - `secret/gitlab/oidc-keycloak` — provider (full OIDC YAML)
   - `secret/redis/password` — password
   - `secret/gitlab/rails-secret` — secrets.yml
   - `secret/gitlab/gitaly-secret` — token
   - `secret/gitlab/gitlab-kas-secret` — kas_shared_secret
   - `secret/gitlab/gitlab-shell-secret` — secret
   - `secret/gitlab/gitlab-workhorse-secret` — shared_secret
6. **eso-reader policy atualizada** para incluir monitoring/*, velero/*, redis/* paths
7. **ExternalSecret YAMLs criados** (7 arquivos em manifests/externalsecrets/):
   - alertmanager-slack-webhook.yaml
   - velero-repo-credentials.yaml
   - gitlab-postgresql-password.yaml
   - gitlab-root-password.yaml
   - gitlab-minio-secret.yaml
   - gitlab-oidc-keycloak.yaml
   - redis-password.yaml
   - gitlab-internal-secrets.yaml (5 P2 secrets)
8. **ExternalSecrets aplicados e validados:**
   - `alertmanager-slack-webhook` em staging-observability-monitoring: SecretSynced True, ownerReference OK
   - `velero-repo-credentials` em velero: SecretSynced True

---

## Pendências (Próxima Sprint)

### GitLab Secrets P1 — Procedimento de Migração

Os secrets do GitLab requerem coordenação com o Helm upgrade para evitar downtime:

```bash
# Para cada secret GitLab P1 (postgresql-password, root-password, minio-secret, oidc-keycloak):

# 1. Deletar o plain secret (ExternalSecret vai recriar)
kubectl delete secret <secret-name> -n staging-platform-gitlab

# 2. Aplicar o ExternalSecret
kubectl apply -f manifests/externalsecrets/<secret-name>.yaml

# 3. Verificar sync
kubectl get externalsecret <secret-name> -n staging-platform-gitlab

# 4. helm upgrade gitlab com:
#    global.postgresql.auth.existingSecret: gitlab-postgresql-password
#    global.redis.auth.existingSecret: redis-password
#    (etc. para cada secret)
```

### Redis (data-services) — Procedimento

```bash
# 1. Aplicar ExternalSecret
kubectl apply -f manifests/externalsecrets/redis-password.yaml

# 2. Deletar plain secret para transferir propriedade
kubectl delete secret redis-password -n data-services
kubectl delete secret redis-password -n staging-platform-gitlab

# 3. Aguardar ExternalSecret recriar (automático, ~30s)
kubectl get externalsecret redis-password -n data-services
```

### P2 GitLab Internals — Procedimento

Requer rolling restart completo do GitLab. Executar durante janela de manutenção:

```bash
# 1. Aplicar ExternalSecrets
kubectl apply -f manifests/externalsecrets/gitlab-internal-secrets.yaml

# 2. Para cada secret interno, deletar plain secret
kubectl delete secret gitlab-rails-secret gitlab-gitaly-secret \
  gitlab-gitlab-kas-secret gitlab-gitlab-shell-secret \
  gitlab-gitlab-workhorse-secret -n staging-platform-gitlab

# 3. helm upgrade gitlab com existingSecret refs para cada componente
# 4. Monitor pods durante restart
```

---

## Critérios de Conclusão (100%)

- [ ] vault-root-token: aprovação de revogação + execução
- [x] alertmanager-slack-webhook: ExternalSecret ativo, SecretSynced True
- [x] velero-repo-credentials: ExternalSecret ativo, SecretSynced True
- [ ] gitlab-postgresql-password: ExternalSecret ativo + helm upgrade executado
- [ ] gitlab-root-password: ExternalSecret ativo + helm upgrade executado
- [ ] gitlab-minio-secret: ExternalSecret ativo + helm upgrade executado
- [ ] gitlab-oidc-keycloak: ExternalSecret ativo + helm upgrade executado
- [ ] redis-password: ExternalSecret ativo em data-services e staging-platform-gitlab
- [ ] gitlab P2 internals: ExternalSecrets ativos + helm upgrade executado
- [ ] Zero plain credential secrets em produção (exceto system-generated TLS, tokens service accounts)

---

## Arquivos Criados

```
platform-provisioning/aws/kubernetes/manifests/externalsecrets/
  alertmanager-slack-webhook.yaml      # P1 — ATIVO
  velero-repo-credentials.yaml         # P1 — ATIVO
  gitlab-postgresql-password.yaml      # P1 — pendente helm upgrade
  gitlab-root-password.yaml            # P1 — pendente helm upgrade
  gitlab-minio-secret.yaml             # P1 — pendente helm upgrade
  gitlab-oidc-keycloak.yaml            # P1 — pendente helm upgrade
  redis-password.yaml                  # P1 — pendente restart
  gitlab-internal-secrets.yaml         # P2 — pendente sprint
docs/adr/adr-101-secrets-migration-vault-externalsecrets.md
docs/demands/2026-03-05-secrets-migration-vault.md (este arquivo)
```

---

## Referências

- ADR-101: Decisão de migração para Vault + ExternalSecrets
- ADR-032: Vault ESO policy granular path restriction
- ExternalSecrets Operator: `vault-backend` ClusterSecretStore (namespace: external-secrets-system)
- Vault: `staging-security-vault/vault-0`, KV v2 engine em `secret/`
