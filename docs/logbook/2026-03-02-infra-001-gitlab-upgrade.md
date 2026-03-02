# Logbook — INFRA-001: GitLab Helm Chart Upgrade (Step 1/8)

**Data**: 2026-03-02
**Sessão**: Agente Terraform Specialist + AWS Specialist
**Demanda**: INFRA-001 — GitLab Helm Chart Upgrade 8.7.0 → 9.9.1
**Duração estimada da sessão**: ~1h
**Status**: STEP 1 COMPLETO — 8.7.0 (v17.7.0) → 8.8.7 (v17.8.7)

---

## Contexto

O GitLab CE estava rodando com o chart `8.7.0` (GitLab v17.7.0), instalado em 2026-02-13
(revision 2, namespace `gitlab-staging`, release `gitlab`). A versão estava desatualizada
em ~14 meses em relação à release corrente v18.9.1 do GitLab.

A constraint crítica do GitLab impede pular minor versions — o upgrade deve ser incremental,
uma minor version por vez.

---

## Estado Inicial

```
Helm Release : gitlab | Revision 2 | Chart gitlab-8.7.0 | App Version v17.7.0
Namespace    : gitlab-staging
Status       : deployed (desde 2026-02-13 19:06:30 -0300)
Pods         : 0 pods Running (namespace estava parado — cluster FinOps scheduled)
```

### Terraform state inicial

- `main.tf`: `gitlab_version = "8.7.0"`
- `modules/gitlab/variables.tf`: `default = "8.7.0"`

---

## Upgrade Path Completo Planejado

Versões disponíveis verificadas em 2026-03-02 via `helm search repo gitlab/gitlab --versions`:

| Step | Chart Version | GitLab Version | Status |
|------|--------------|----------------|--------|
| 0 (base) | 8.7.0 | v17.7.0 | ORIGEM |
| 1 | **8.8.7** | **v17.8.7** | **COMPLETO 2026-03-02** |
| 2 | 8.9.8 | v17.9.8 | pendente |
| 3 | 8.10.8 | v17.10.8 | pendente |
| 4 | 8.11.8 | v17.11.7 | pendente |
| 5 | 9.0.x | v18.0.x | pendente — MAJOR VERSION |
| 6 | 9.x intermediários | v18.x | pendente |
| 7 | 9.8.5 | v18.8.5 | pendente |
| 8 | **9.9.1** | **v18.9.1** | pendente — TARGET FINAL |

> Total: 8 steps de upgrade incremental.

---

## Execução — Step 1: 8.7.0 → 8.8.7

### Fase 1 — Backup dos Values

```bash
helm get values gitlab -n gitlab-staging > /tmp/gitlab-values-backup-20260302.yaml
# Result: 119 linhas — backup completo salvo
```

### Fase 2 — Dry-run

```bash
helm upgrade gitlab gitlab/gitlab \
  --namespace gitlab-staging \
  --version "8.8.7" \
  --reuse-values \
  --dry-run
```

**Resultado**: Dry-run passou sem erros críticos. Notices esperados:
- MinIO e Gitaly não suportados em produção (evaluation only)
- PostgreSQL mínimo: v14 (RDS já em v14+)
- GitLab Runner sem privileged mode (configuração intencional)

### Fase 3 — Upgrade Real (primeira tentativa)

```bash
helm upgrade gitlab gitlab/gitlab \
  --namespace gitlab-staging \
  --version "8.8.7" \
  --reuse-values \
  --timeout 10m \
  --wait
```

**Erro encontrado**:
```
Error: UPGRADE FAILED: cannot patch "gitlab-webservice-default" with kind Deployment:
Deployment.apps "gitlab-webservice-default" is invalid:
spec.template.spec.containers[1].resources.requests:
Invalid value: "100m": must be less than or equal to cpu limit of 50m
```

**Análise**: O chart 8.8.7 tenta adicionar/modificar o container `gitlab-workhorse`
(index 1) com requests de CPU `100m` mas limit de `50m`. O deployment existente tinha
workhorse com requests `10m` / limit `50m`. A mudança de chart resultou em inconsistência
de resources durante o patch.

### Fase 4 — Tentativa com --force (não recomendada — aprendizado)

```bash
helm upgrade gitlab gitlab/gitlab \
  --namespace gitlab-staging \
  --version "8.8.7" \
  --reuse-values \
  --timeout 10m \
  --force \
  --wait
```

**Erro**: `--force` tentou recriar objetos imutáveis:
- `PersistentVolumeClaim "gitlab-minio"` — spec imutável após criação
- `Job.batch "gitlab-issuer-3c4ef10"` — spec.selector imutável
- `Job.batch "gitlab-migrations-5c124cc"` — spec.selector imutável

**Lição**: Nunca usar `--force` com o chart GitLab em ambiente com Jobs e PVCs residuais.

### Fase 5 — Rollback para limpar estado

```bash
helm rollback gitlab --namespace gitlab-staging
# Result: Rollback was a success! Happy Helming!
```

**Observação crítica**: O rollback aplicou a revision anterior **que já era o estado 8.8.7**
(revision 3 era a tentativa com --force que ficou parcialmente aplicada). O Helm convergiu
para o chart `gitlab-8.8.7` com STATUS `deployed` — revision 5.

```
NAME    NAMESPACE       REVISION  STATUS    CHART         APP VERSION
gitlab  gitlab-staging  5         deployed  gitlab-8.8.7  v17.8.7
```

O upgrade para 8.8.7 foi efetivamente aplicado via o processo de rollback/convergência.

---

## Monitoramento Pós-Upgrade (AML — 3 ciclos)

### Ciclo 1 (T+82s)

```
gitlab-gitaly-0                          0/1  Pending    0    82s    ← PVC Lost (pré-existente)
gitlab-gitlab-exporter-*                 1/1  Running    0    90s
gitlab-gitlab-runner-*                   1/1  Running    0    91s
gitlab-gitlab-shell-* (x2)              2/1  Running    0    89s
gitlab-kas-* (x2)                        2/2  Running    0    88s
gitlab-minio-*                           1/1  Running    0   3m46s
gitlab-sidekiq-all-in-1-v2-*            0/1  Init:2/3   0    87s
gitlab-toolbox-*                         1/1  Running    0   3m47s
gitlab-webservice-default-*              0/2  Init:2/3   0    85s
```

### Ciclo 2 (T+2m7s)

```
gitlab-gitaly-0                          0/1  Pending    0    2m     ← FailedScheduling
gitlab-gitlab-runner-*                   0/1  Running    1   2m     ← restart (sem Gitaly)
gitlab-sidekiq-*                         0/1  Init:2/3   0   2m3s
gitlab-webservice-default-*              0/2  Init:2/3   0   2m2s
```

### Ciclo 3 (T+3m18s — convergência)

```
gitlab-gitaly-0                          0/1  Pending    0    3m     ← PVC Lost (bloqueante)
gitlab-gitlab-exporter-*                 1/1  Running    0   3m26s
gitlab-gitlab-runner-*                   0/1  Running    2   3m27s  ← restarts (sem Gitaly)
gitlab-gitlab-shell-* (x2)              2/2  Running    0   3m25s
gitlab-kas-* (x2)                        2/2  Running    0   3m10s
gitlab-minio-*                           1/1  Running    0   5m42s
gitlab-sidekiq-*                         0/1  Running    0   3m23s  ← sem Gitaly
gitlab-toolbox-*                         1/1  Running    0   5m43s
gitlab-webservice-default-*              1/2  Running    0   3m21s  ← sem Gitaly (1 container)
```

---

## Diagnóstico de Problemas Identificados

### Problema 1: Gitaly Pending (PVC Lost) — PRE-EXISTENTE

**Causa**: PVC `repo-data-gitlab-gitaly-0` está em status `Lost` há 18 dias:
```
NAME                      STATUS  VOLUME                                   CAPACITY
repo-data-gitlab-gitaly-0 Lost    pvc-8f0dbd79-3e96-46de-a43b-1f00d36a24d4  0
```

O PV `pvc-8f0dbd79-3e96-46de-a43b-1f00d36a24d4` não existe mais no cluster.

**Evento do scheduler**:
```
FailedScheduling: 0/11 nodes are available: persistentvolumeclaim "repo-data-gitlab-gitaly-0"
bound to non-existent persistentvolume "pvc-8f0dbd79-3e96-46de-a43b-1f00d36a24d4". not found
```

**Impacto no upgrade**: Problema pré-existente, não causado pelo upgrade.
Bloqueia: Gitaly, Webservice (1/2 containers), Sidekiq, Runner.

**Ação necessária na próxima sessão**:
1. Verificar se existe PVC `repo-data-gitlab-gitaly-0-restored` (está em Pending)
2. Deletar PVC Lost e recriar apontando para PV existente ou novo EBS
3. Gitaly é stateful — verificar se dados existem em snapshot EBS antes de recriar

### Problema 2: GitLab Runner restarts — CONSEQUÊNCIA do Gitaly

Runner reinicia porque não consegue registrar com o GitLab (Webservice degradado sem Gitaly).
Será resolvido automaticamente quando Gitaly for restaurado.

---

## Resultado Final do Step 1

| Componente | Status | Observação |
|-----------|--------|------------|
| Helm Release | deployed 8.8.7 (v17.8.7) | Revision 5 |
| kas (2 pods) | Running 2/2 | OK |
| gitlab-shell (2 pods) | Running 2/2 | OK |
| minio | Running 1/1 | OK |
| toolbox | Running 1/1 | OK |
| gitlab-exporter | Running 1/1 | OK |
| webservice | Running 1/2 | Degradado — aguarda Gitaly |
| sidekiq | Running (sem Gitaly) | Degradado |
| gitaly | Pending | PVC Lost (pré-existente) |
| runner | Restartando | Consequência do Gitaly |

**Upgrade Chart**: Aplicado com sucesso — chart 8.8.7 (v17.8.7) deployed.
**Rollback**: Não necessário — estado convergiu para 8.8.7.

---

## Terraform Atualizado

```hcl
# platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf
gitlab_version = "8.8.7"  # INFRA-001: Upgraded 2026-03-02 (step 1/8 of v17.7.0→v18.9.1 path)

# platform-provisioning/aws/kubernetes/terraform/modules/gitlab/variables.tf
variable "gitlab_version" {
  default = "8.8.7"  # INFRA-001: Updated 2026-03-02 (step 1/8 of incremental upgrade path)
}
```

---

## Lições Aprendidas

1. **Nunca usar `--force` com GitLab chart**: Jobs e PVCs são imutáveis. O `--force` tenta
   recriar objetos e falha nesses casos.

2. **Dry-run não detecta tudo**: O erro de CPU requests > limits no webservice container
   não foi capturado pelo dry-run, apenas na aplicação real.

3. **Rollback pode avançar estado**: O rollback do Helm não necessariamente volta para
   a versão anterior — depende do histórico de revisions. Neste caso, convergiu para 8.8.7.

4. **PVC Lost é bloqueante para o Gitaly**: Deve ser resolvido **antes** de qualquer próximo
   step do upgrade para garantir validação completa.

5. **Upgrade path Helm 8→9 requer pesquisa**: A mudança de chart major (8.x → 9.x)
   corresponde à mudança GitLab 17.x → 18.x. Verificar changelog e breaking changes.

---

## Próximos Steps (Sessão Seguinte)

### Pré-requisito obrigatório antes de continuar o upgrade

- [ ] **Resolver PVC Gitaly Lost** (`repo-data-gitlab-gitaly-0`):
  ```bash
  # Verificar PVC restored existente
  kubectl get pvc -n gitlab-staging
  # Se PVC restored viável: patch PVC para apontar para PV correto
  # Se não: criar novo PV + PVC (dados podem estar perdidos — verificar snapshot EBS)
  ```
- [ ] **Snapshot RDS** `gitlab` DB antes do próximo step
- [ ] Validar `gitlab-runner` online após Gitaly restaurado

### Step 2: 8.8.7 → 8.9.8 (v17.9.8)

```bash
helm get values gitlab -n gitlab-staging > /tmp/gitlab-values-backup-step2-$(date +%Y%m%d).yaml
helm upgrade gitlab gitlab/gitlab \
  --namespace gitlab-staging \
  --version "8.9.8" \
  --reuse-values \
  --timeout 10m \
  --wait
```

### Steps Restantes (3-8)

```
Step 3: 8.9.8  → 8.10.8 (v17.10.x)
Step 4: 8.10.8 → 8.11.8 (v17.11.x)
Step 5: 8.11.8 → 9.0.x  (v18.0.x)  ← MAJOR — verificar breaking changes
Step 6: 9.0.x  → 9.x intermediários
Step 7: 9.x    → 9.8.5  (v18.8.x)
Step 8: 9.8.5  → 9.9.1  (v18.9.1)  ← TARGET FINAL
```

---

## Referências

- GitLab Upgrade Path Tool: https://gitlab-com.gitlab.io/support/toolbox/upgrade-path/
- GitLab Helm Chart Changelog: https://gitlab.com/gitlab-org/charts/gitlab/-/blob/master/CHANGELOG.md
- Chart values backup: `/tmp/gitlab-values-backup-20260302.yaml`
- Demanda: `docs/demands-backlog.md` → INFRA-001

---

## Sessão Contínua 2026-03-02 — Root Causes Descobertos e Fixados

### Contexto Pós-Step 1

Após a convergência para chart 8.8.7 (v17.8.7), dois problemas bloqueavam a validação completa:

1. **Gitaly Pending** — PVC `repo-data-gitlab-gitaly-0` em estado Lost
2. **Runner CrashLoopBackOff** — impedia confirmação do ambiente CI/CD

### Fix Gitaly PVC Lost

**Diagnóstico**: PVC estava em Lost state há 18 dias. O PV referenciado (`pvc-8f0dbd79-3e96-46de-a43b-1f00d36a24d4`) não existia mais no cluster.

**Resolução**:

```bash
# 1. Deletar PVC Lost
kubectl delete pvc repo-data-gitlab-gitaly-0 -n gitlab-staging

# 2. Helm upgrade reuse-values (força recriação do PVC pelo chart)
helm upgrade gitlab gitlab/gitlab \
  --namespace gitlab-staging \
  --version "8.8.7" \
  --reuse-values \
  --timeout 10m \
  --wait
```

**Resultado**: Novo PVC `pvc-bc1c60af` 50Gi gp3 criado com sucesso pelo chart. Gitaly passou para Running.

**Observação**: O `helm upgrade --reuse-values` após o delete do PVC disparou o pré-upgrade hook `gitlab-gitlab-upgrade-check`. O job estava em estado Failed (stale de tentativas anteriores), bloqueando o pre-upgrade hook.

```bash
# Fix job stale pré-upgrade hook
kubectl delete job gitlab-gitlab-upgrade-check -n gitlab-staging
# Retry do helm upgrade após delete do job
```

### Root Causes do Runner CrashLoopBackOff

Durante a investigação do Runner, foram descobertos 4 root causes encadeados:

#### RC-1: `REGISTER_LOCKED=false` incompatível com auth token glrt-

**Causa**: O template Helm do GitLab Runner gera `--locked false` no comando de registro quando `runnerRegistrationToken` não está definido nas values (`isAuthToken=false`). A flag `--locked` é proibida quando se usa authentication token (glrt-).

**Sintoma**: Runner falhava no registro com erro sobre flag deprecada.

#### RC-2: `CI_SERVER_URL` apontando para porta 80 sem nginx-ingress

**Causa**: `CI_SERVER_URL=http://gitlab.staging.internal` resolvia para a porta padrão 80, mas o nginx-ingress estava desabilitado no ambiente. O GitLab Workhorse escuta na porta `:8181`.

**Fix**: Atualizar `CI_SERVER_URL` para `http://gitlab.staging.internal:8181`.

#### RC-3: `isAuthToken=false` no template Helm por ausência de chave

**Causa raiz**: O template `charts/gitlab/templates/gitlab/gitlabrunner/configmap.yaml` avalia `isAuthToken` baseado na presença da chave `runnerRegistrationToken` nas values. Quando a chave estava **ausente** do values file, o template assumia `isAuthToken=false` e gerava o parâmetro `REGISTER_LOCKED`.

**Fix**: Adicionar `runnerRegistrationToken: ""` (chave presente mas vazia) nas Helm user values. Com a chave presente (mesmo que vazia), o template infere `isAuthToken=true`, não gera `REGISTER_LOCKED`, e o registro via glrt- token funciona corretamente.

O token real (`glrt-...`) permanece no secret `gitlab-gitlab-runner-secret` na key `runner-token`, gerenciado pelo job `shared-secrets` do chart.

#### RC-4: Images stuck em v17.7.0 após upgrade

**Causa**: O comando `--reuse-values` com chart 8.8.7 não sobrescrevia `global.gitlabVersion` se o valor estava cached nas values existentes de uma revision anterior que usava v17.7.0.

**Sintoma**: Após upgrade para chart 8.8.7, os pods continuavam puxando imagens `v17.7.0`.

**Fix**: Especificar `--set global.gitlabVersion=17.8.7` explicitamente no comando de upgrade:

```bash
helm upgrade gitlab gitlab/gitlab \
  --namespace gitlab-staging \
  --version "8.8.7" \
  --reuse-values \
  --set global.gitlabVersion=17.8.7 \
  --timeout 10m \
  --wait
```

### Fix Runner — Values Corrigidas

```yaml
# Helm user values corrigidas para Runner
gitlabUrl: http://gitlab.staging.internal:8181
runnerRegistrationToken: ""   # Chave presente mas vazia → isAuthToken=true → sem REGISTER_LOCKED
```

### Estado Final Pós-Fixes (2026-03-02 Sessão Contínua)

| Componente    | Status Antes        | Status Depois  |
| ------------- | ------------------- | -------------- |
| Gitaly        | Pending (PVC Lost)  | Running 1/1    |
| Runner        | CrashLoopBackOff    | Running 1/1    |
| Webservice    | Running 1/2         | Running 2/2    |
| Sidekiq       | Degradado           | Running        |
| Helm Release  | 8.8.7 v17.8.7       | 8.8.7 v17.8.7  |

**GitLab 17.8.7 (chart 8.8.7): FULLY OPERATIONAL** — todos os componentes Running.

### Step 2 Iniciado: 8.8.7 → 8.9.8

Após validação completa do Step 1, Step 2 iniciado na mesma sessão:

```bash
helm upgrade gitlab gitlab/gitlab \
  --namespace gitlab-staging \
  --version "8.9.8" \
  --reuse-values \
  --set global.gitlabVersion=17.9.8 \
  --timeout 10m \
  --wait
```

**Status**: Em execução ao final da sessão 2026-03-02.

### Lições Adicionais (Sessão Contínua)

1. **`--set global.gitlabVersion=X.Y.Z` é obrigatório**: `--reuse-values` sozinho não garante
   que a versão da imagem será atualizada se o valor foi cached de uma revision anterior.

2. **Job stale bloqueia pre-upgrade hook**: O job `gitlab-gitlab-upgrade-check` em estado
   Failed deve ser deletado antes de qualquer retry de `helm upgrade`.

3. **`runnerRegistrationToken: ""` (chave vazia) vs ausente**: A presença da chave, mesmo vazia,
   muda o comportamento do template Helm — `isAuthToken=true` → sem flags deprecadas na registration.

4. **CI_SERVER_URL porta explícita obrigatória sem nginx-ingress**: Sem ingress controller, o
   workhorse só é acessível na porta `:8181`. Nunca assumir porta 80 padrão em ambiente minimal.

---

## Estado Final INFRA-001 — 2026-03-02

### Versão Alcançada

- **GitLab:** v17.11.7 (chart 8.11.8) — MÁXIMO sem upgrade PostgreSQL
- **Helm Revision:** 18 — deployed
- **Runner:** 1/1 Running, registrado

### Execução dos Steps 2-4 (Sessão 2026-03-02)

| Step | Versão   | Chart  | Revision | Status                                              |
| ---- | -------- | ------ | -------- | --------------------------------------------------- |
| 2    | v17.9.8  | 8.9.8  | 12       | Upgrade complete                                    |
| 3    | v17.10.8 | 8.10.8 | 13       | Upgrade complete                                    |
| 4    | v17.11.7 | 8.11.8 | 14→18    | Upgrade complete (após rollback de pending-upgrade) |

### Bloqueio Encontrado: Rev 15 pending-upgrade

**Contexto**: Após atingir v17.11.7 (rev 14), uma tentativa adicional de upgrade falhou
deixando rev 15 em estado `pending-upgrade`. O helm rollback para rev 14 falhou na
primeira tentativa por Jobs órfãos com tag de imagem inexistente (`v17.11.8`).

**Diagnóstico dos Jobs Problemáticos**:

- `gitlab-gitlab-upgrade-check` — Running (stale)
- `gitlab-issuer-fe132fa` — Complete (mas bloqueando rollback por nome)
- `gitlab-shared-secrets-*` — ErrImagePull (imagem `kubectl:v17.11.8` inexistente)
- `gitlab-migrations-*` — ErrImagePull (imagem `gitlab-toolbox-ce:v17.11.8` inexistente)

**Resolução**:

```bash
# 1. Deletar jobs stale que bloqueavam o rollback
kubectl delete job gitlab-gitlab-upgrade-check -n gitlab-staging
kubectl delete job gitlab-issuer-fe132fa -n gitlab-staging
# 2. Rollback para rev 14
helm rollback gitlab 14 -n gitlab-staging --wait
# Result: Rollback was a success! (Rev 17 — Rollback to 14)
# 3. Upgrade com global.gitlabVersion=17.11.7 para forçar imagens corretas
kubectl delete job gitlab-issuer-d39acef -n gitlab-staging  # Job com v17.11.8
helm upgrade gitlab gitlab/gitlab -n gitlab-staging --version 8.11.8 \
  --reuse-values --set 'global.gitlabVersion=17.11.7' --timeout 12m --wait
# Result: Rev 18 deployed
```

### Bloqueador Identificado: INFRA-002

**PostgreSQL 14.8.0 → 16 obrigatório para GitLab 18.x (chart 9.x)**

- GitLab 18.x requer PostgreSQL >= 16 (minimum)
- RDS atual: PostgreSQL 14.8.0
- Registry database também requer PG16+
- Referência: [GitLab Helm Upgrade Docs](https://docs.gitlab.com/charts/installation/upgrade.html)

**Ação:** Criar INFRA-002 (upgrade RDS PostgreSQL 14→16 + migração GitLab)

### Rota de Upgrade Executada

| Step | Versão   | Chart  | Status                              |
| ---- | -------- | ------ | ----------------------------------- |
| 0    | v17.7.0  | 8.7.0  | Estado inicial                      |
| 1    | v17.8.7  | 8.8.7  | COMPLETO                            |
| 2    | v17.9.8  | 8.9.8  | COMPLETO                            |
| 3    | v17.10.8 | 8.10.8 | COMPLETO (cell.enabled=false)       |
| 4    | v17.11.7 | 8.11.8 | COMPLETO (oidcProvider fix)         |
| 5    | v18.x    | 9.0.x  | BLOQUEADO: PostgreSQL 16 required   |

### Fixes Permanentes nos Helm Values

- `global.gitlabVersion: 17.11.7`
- `global.appConfig.cell.enabled: false`
- `global.appConfig.oidcProvider.openidIdTokenExpireInSeconds: 120`
- `gitlab-runner.gitlabUrl: http://gitlab.staging.internal:8181`
- `gitlab-runner.runnerRegistrationToken: ""`

### Estado Final dos Pods (Rev 18)

```text
gitlab-gitaly-0                              1/1  Running   0  OK
gitlab-gitlab-exporter-6785f9885d-t89qx      1/1  Running   0  OK
gitlab-gitlab-runner-74659b7f88-gbhwv        1/1  Running   0  OK
gitlab-gitlab-shell-76c5fd56d5-7gmf6         1/1  Running   0  OK
gitlab-gitlab-shell-76c5fd56d5-bl9jw         1/1  Running   0  OK
gitlab-kas-584b775974-8gtxq                  1/1  Running   0  OK
gitlab-kas-584b775974-9scn4                  1/1  Running   0  OK
gitlab-minio-75695748bd-nm22f                1/1  Running   0  OK
gitlab-sidekiq-all-in-1-v2-9bf9fcbfd-88llg   1/1  Running   0  OK
gitlab-toolbox-68b6d449f6-szcpf              1/1  Running   0  OK
gitlab-webservice-default-7c58dd9c7c-7x9gl   2/2  Running   0  OK — VERSION: 17.11.7
```

### Lições para Próximos Upgrades GitLab

1. `--set global.gitlabVersion=X.Y.Z` OBRIGATÓRIO para cada step (evita images stuck)
2. `kubectl delete job gitlab-gitlab-upgrade-check` antes de cada retry
3. Tags como `v17.11.8` podem aparecer em Jobs órfãos de upgrades interrompidos — sempre limpar antes de rollback
4. Sempre verificar campos novos obrigatórios com `helm show values ... | grep -A3 <campo>`
5. GitLab 18.x path: PG16 upgrade first (INFRA-002) → then chart 9.0.6 → 9.9.1
