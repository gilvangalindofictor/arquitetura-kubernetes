# Histórico de Estratégias Técnicas — 2026-03-02

## Sessão: Execução de Demandas em Paralelo

### INFRA-001: GitLab Upgrade Path

**Caminho de upgrade:** 8.7.0 → 8.8.7 → 8.9.8 → 8.10.8 → 8.11.8 → 9.0.x → 9.9.1

**Lições aprendidas:**

1. Nunca usar `--force` no helm upgrade GitLab (quebra Jobs imutáveis e PVCs)
2. `--reuse-values` sozinho não atualiza imagens se `global.gitlabVersion` estiver cached
3. Sempre usar `--set global.gitlabVersion=X.Y.Z` explícito durante upgrades de versão
4. Job `gitlab-gitlab-upgrade-check` em Failed state bloqueia pre-upgrade hook → `kubectl delete job` antes de retry
5. GitLab Runner: `runnerRegistrationToken: ""` nas Helm values → `isAuthToken=true` → sem REGISTER_LOCKED env var

**Runner com auth token (glrt-):**

- nginx-ingress desabilitado → CI_SERVER_URL deve usar `:8181` (workhorse), não `:80`
- `runnerRegistrationToken: ""` (chave presente mas vazia) → isAuthToken=true → sem flags deprecadas na registration
- Token real em `runner-token` key do secret `gitlab-gitlab-runner-secret` (gerenciado pelo shared-secrets job)

**Fix Gitaly PVC Lost:**

- Delete PVC em estado Lost + helm upgrade `--reuse-values` → chart recria PVC automaticamente
- Novo PVC recebe novo PV gp3 provisionado dinamicamente pelo StorageClass

---

### GAP-007: Kyverno Enforcement Mode

- Apenas ClusterPolicies em `audit` com 0 violations podem ser promovidas para `enforce`
- `validationFailureAction: Enforce` apenas bloqueia recursos NOVOS, não retroativamente
- Sequência segura: audit → validar 0 violations por 7d → enforce

---

### CICD-001: Harbor Trivy Blocking

- Harbor em OIDC mode bloqueia Basic auth → bypass via db_auth temporário no PostgreSQL
- Trivy deve ser habilitado via helm upgrade com `--set trivy.enabled=true`
- 5 projetos configurados: library, root, platform-apps, microservices, infrastructure

---

### Padrões Gerais de Helm Upgrade (GitLab)

| Situação | Ação |
| -------- | ---- |
| PVC Lost bloqueia StatefulSet | Delete PVC + helm upgrade reuse-values |
| Job stale em Failed bloqueia hook | kubectl delete job antes do upgrade |
| Imagens não atualizam com --reuse-values | Adicionar --set global.gitlabVersion=X.Y.Z |
| Runner CrashLoop com glrt- token | runnerRegistrationToken: "" + gitlabUrl com porta explícita |
| Deployment resource requests > limits | Não usar --force; ajustar values antes do upgrade |
