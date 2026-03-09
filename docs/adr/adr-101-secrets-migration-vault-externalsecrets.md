# ADR-101: Secrets Migration — Vault + ExternalSecrets as Single Source of Truth

| Campo | Valor |
|-------|-------|
| ID | ADR-101 |
| Data | 2026-03-05 |
| Status | Accepted |
| Contexto | k8s-platform-prod, EKS 1.34 |
| Autor | Agent-SecComp |
| Revisores | Platform Team |
| Tags | security, secrets, vault, externalsecrets, compliance |

---

## Contexto e Problema

O cluster k8s-platform-prod possui secrets de aplicação armazenados como plain K8s Secrets no etcd. Embora o etcd seja protegido por encryption-at-rest, plain secrets apresentam riscos:

1. **Acesso RBAC excessivamente amplo**: qualquer SA com `get` em secrets pode ler credenciais
2. **Zero auditabilidade**: nenhum log de quem leu qual secret, quando
3. **Rotação manual**: sem mecanismo automatizado de rotação
4. **GitOps friction**: valores em base64 não devem estar em repositórios Git
5. **Compliance**: CIS Benchmark K8s recomenda secrets externos para credenciais de aplicação

O cluster já possui 15 ExternalSecrets operacionais (SecretSynced: True) e Vault com KV v2 em produção. A infraestrutura está pronta — falta migrar os secrets restantes.

---

## Decisão

**Migrar todos os secrets de credenciais de aplicação para Vault KV v2, sincronizados via ExternalSecrets Operator usando o ClusterSecretStore `vault-backend`.**

Exceções (não migrar):
- `kubernetes.io/tls` secrets (gerados pelo cert-manager, já tem ciclo de vida próprio)
- `kubernetes.io/service-account-token` (gerenciados pelo K8s automaticamente)
- `sh.helm.release.*` (metadados Helm, não contêm credenciais de aplicação)
- Secrets de bootstrap de bootstrap (vault-root-token: tratar separadamente — revogar, não migrar)

---

## Alternativas Consideradas

### Alternativa A: Sealed Secrets (Bitnami)
- Pro: valores criptografados podem ficar no Git
- Con: rotação requer commit + deploy; sem audit log de acesso; dependência de chave RSA local
- **Rejeitado**: Vault já deployado, menor benefício incremental

### Alternativa B: AWS Secrets Manager + External Secrets
- Pro: serviço gerenciado, sem operação de Vault
- Con: custo por secret ($0.40/secret/mês × 50+ secrets = ~$240/ano); latência adicional cross-VPC; já temos Vault
- **Rejeitado**: Vault já deployado e operacional

### Alternativa C: Continuar com plain K8s Secrets
- Con: todos os problemas descritos no contexto
- **Rejeitado**: não atende compliance nem segurança

### Decisao: Vault + ExternalSecrets (opção D)
- Vault já operacional com KV v2, auto-unseal KMS, HA ativo
- ExternalSecrets já operacional com 15 secrets sincronizados
- Kubernetes auth method ativo (sem necessidade de root token)
- Audit log via Vault audit backend
- Rotação automática via Vault leases ou scripts CICD-003

---

## Consequências

### Positivas
- **Auditabilidade completa**: Vault audit log registra cada leitura/escrita de secret
- **Rotação centralizada**: CICD-003 script de rotação usa Vault API; ExternalSecrets sincroniza automaticamente
- **Segregação de acesso**: política eso-reader granular por path; humans via OIDC policy separada
- **GitOps-safe**: ExternalSecret YAMLs sem valores sensíveis podem ir ao Git
- **Compliance**: CIS Benchmark K8s 5.4.1 (prefer secrets in external vault); ISO 27001 A.9 access control
- **Zero-trust posture**: secrets não existem no etcd — ExternalSecrets recria sob demanda

### Negativas / Riscos
- **Dependência de Vault**: se Vault ficar indisponível, ExternalSecrets não consegue sincronizar; refreshInterval ameniza (cache local existe)
- **Complexidade operacional**: mais peças móveis; time precisa entender ESO + Vault
- **Migração GitLab**: secrets Helm-generated requerem coordenação com helm upgrade (risco de downtime se mal executado)
- **vault-root-token**: precisa de processo controlado de revogação; revogar prematuramente pode bloquear operações de administração

### Mitigações
- Vault HA ativo (vault-0 + replicas); KMS auto-unseal (sem dependência de unseal manual)
- `deletionPolicy: Retain` em todos ExternalSecrets — K8s secret persiste mesmo se Vault temporariamente indisponível
- GitLab migration: executar em janela de manutenção, com rollback plan (backup do plain secret antes de deletar)
- Root token: documentar procedimento de geração emergency via unseal keys antes de revogar

---

## Padrão de Implementação

### Estrutura de paths no Vault (KV v2)

```
secret/
  monitoring/
    alertmanager         # Teams webhook URLs por canal
  velero/
    repo-credentials     # Restic repository encryption password
  gitlab/
    postgresql-password  # GitLab DB password
    root-password        # GitLab admin password
    minio-secret         # S3/MinIO object storage credentials
    oidc-keycloak        # Full OIDC provider YAML for omniauth
    rails-secret         # secrets.yml (secret_key_base, db_key_base, otp_key_base)
    gitaly-secret        # Gitaly auth token
    gitlab-kas-secret    # KAS shared secret
    gitlab-shell-secret  # Shell auth token
    gitlab-workhorse-secret  # Workhorse shared secret
  redis/
    password             # Redis auth password (shared data-services + gitlab)
  # paths já existentes:
  argocd/
  grafana/
  harbor/
  keycloak/
  postgresql-admin/
  secret-rotator/
  sonarqube/
```

### Template ExternalSecret (padrão)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: <secret-name>
  namespace: <target-namespace>
  labels:
    app.kubernetes.io/managed-by: external-secrets
    environment: staging
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: <secret-name>
    creationPolicy: Owner      # ESO owns the K8s secret lifecycle
    deletionPolicy: Retain     # Retain K8s secret if ESO is removed (safety)
  data:
    - secretKey: <k8s-key>
      remoteRef:
        key: secret/data/<vault-path>
        property: <vault-property>
```

### Política Vault (eso-reader — atualizada 2026-03-05)

Paths cobertos: keycloak/*, harbor/*, sonarqube/*, grafana/*, gitlab/*, argocd/*, secret-rotator/*, postgresql-admin/*, monitoring/*, velero/*, redis/*

ServiceAccount: `external-secrets-system/external-secrets` (via Kubernetes auth method)

---

## Status de Migração

| Secret | Prioridade | Vault | ExternalSecret Criado | ExternalSecret Aplicado | Observação |
|--------|-----------|-------|----------------------|------------------------|------------|
| vault-root-token | P0 | N/A | N/A | N/A | REVOGAR — não migrar |
| alertmanager-teams-webhook | P1 | OK | OK | **ATIVO** | SecretSynced True |
| velero-repo-credentials | P1 | OK | OK | **ATIVO** | SecretSynced True |
| gitlab-postgresql-password | P1 | OK | OK | Pendente | Requer helm upgrade GitLab |
| gitlab-root-password | P1 | OK | OK | Pendente | Requer helm upgrade GitLab |
| gitlab-minio-secret | P1 | OK | OK | Pendente | Requer helm upgrade GitLab |
| gitlab-oidc-keycloak | P1 | OK | OK | Pendente | Requer helm upgrade GitLab |
| redis-password | P1 | OK | OK | Pendente | Requer restart Redis |
| gitlab-rails-secret | P2 | OK | OK | Pendente | Requer janela manutenção |
| gitlab-gitaly-secret | P2 | OK | OK | Pendente | Requer janela manutenção |
| gitlab-gitlab-kas-secret | P2 | OK | OK | Pendente | Requer janela manutenção |
| gitlab-gitlab-shell-secret | P2 | OK | OK | Pendente | Requer janela manutenção |
| gitlab-gitlab-workhorse-secret | P2 | OK | OK | Pendente | Requer janela manutenção |

---

## Referências

- [External Secrets Operator docs](https://external-secrets.io/v0.9.0/)
- [Vault KV v2 API](https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2)
- CIS Kubernetes Benchmark v1.8, Control 5.4.1
- ADR-032: Vault ESO policy granular path restriction
- demands/2026-03-05-secrets-migration-vault.md
