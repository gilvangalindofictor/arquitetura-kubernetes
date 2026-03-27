# Demanda: Healthcheck Onboarding E2E — Teste da Esteira de Plataforma

**Data**: 2026-03-27
**Status**: EM ANDAMENTO (75% Fase 1)
**Autor**: Platform Architect + DevOps Lead

---

## Objetivo

Testar a esteira completa de onboarding de aplicacoes (do Backstage template ao deploy em staging) usando 3 aplicacoes healthchecker (Go, Python, .NET).

## Abordagem: Bottom-up

Em vez de depender do Backstage UI, testar de baixo para cima:
1. Criar repos no GitLab via API
2. Criar aplicacao healthchecker
3. Push para GitLab
4. Pipeline roda automaticamente
5. Scripts de provisioning criam tudo
6. Verificar deploy em staging

---

## FASE 1: Fix GitLab Runner + Infra

### Problema 1: Runner CrashLoopBackOff (RESOLVIDO)
- **Causa**: GitLab webservice retornando 500 na API /runners/verify
- **Causa raiz**: `ActiveRecord::NoDatabaseError` — GitLab Rails nao conectava ao RDS
- **Analise**: `gitlab_user` atingiu CONNECTION LIMIT de 10
- **Fix**: `ALTER ROLE gitlab_user CONNECTION LIMIT 50` via postgres_admin
- **Resultado**: Runner 1/1 Running, registrado e operacional

### Problema 2: Runner RBAC pods/attach (RESOLVIDO)
- **Causa**: Role `gitlab-gitlab-runner` nao tinha `pods/attach` nas resources
- **Fix**: `kubectl patch role gitlab-gitlab-runner -n staging-platform-gitlab --type=json -p='[{"op":"replace","path":"/rules/0/resources","value":["pods","pods/exec","pods/log","pods/attach"]}]'`
- **Resultado**: Executor pods conseguem attach

### Problema 3: PodSecurity baseline vs privileged DinD (RESOLVIDO)
- **Causa**: Namespace staging-platform-gitlab tem PodSecurity "baseline:latest" que bloqueia privileged=true
- **Fix**: Migrado de Docker-in-Docker para Kaniko (gcr.io/kaniko-project/executor:debug) — nao requer privileged
- **Resultado**: Build sem privileged mode

### Problema 4: Credentials nao injetadas em executor pods (RESOLVIDO)
- **Causa**: envFrom no runner deployment so afeta o pod do runner, NAO os executor pods criados para cada job
- **Fix**: Adicionado `environment` vars no runner config.template.toml + pod_spec strategic merge patch com envFrom
- **Resultado**: HARBOR_REGISTRY, HARBOR_USER, HARBOR_PASSWORD disponiveis nos executor pods

### Problema 5: Harbor HTTPS vs HTTP (RESOLVIDO na CI, pendente push)
- **Causa**: Kaniko tenta HTTPS por default, Harbor staging (harbor-core) expoe apenas HTTP na porta 80
- **Fix**: Adicionado `--insecure --insecure-pull --skip-tls-verify --skip-tls-verify-pull` ao Kaniko executor
- **Status**: Fix codificado, push pendente (Gitaly pod Pending por falta de CPU)

### Problema 6: Sidekiq nao transiciona status dos jobs (PARCIAL)
- **Causa**: Durante indisponibilidade do DB, runner completa job mas o status update via API retorna 500. Job fica "stuck" em running no GitLab
- **Workaround**: Script Ruby via `rails runner` para forcar transicao: `job.success!` ou `job.update_columns(status: 'failed')`
- **Fix permanente**: Pendente — requer restart do sidekiq (pod Pending por falta de CPU)

### Problema 7: Gitaly Pending (BLOQUEADOR ATIVO)
- **Causa**: Node selector `eks.amazonaws.com/nodegroup=system` com taint tolerance, mas system nodes sem CPU/memoria suficiente
- **Impacto**: Sem Gitaly, nao e possivel fazer git push (commits via API ou git clone)
- **Fix**: Escalar o nodegroup system (ASG max_size) ou mover Gitaly para workloads nodegroup

---

## FASE 2: App Go Healthchecker

### Repo GitLab
- **Grupo**: platform-tests (ID: 25)
- **Projeto**: healthcheck-go (ID: 10)
- **Path**: platform-tests/healthcheck-go

### Arquivos criados (7 commits no main)
1. `main.go` — healthchecker Go com checks para PostgreSQL, Redis, RabbitMQ
2. `go.mod` / `go.sum` — dependencias Go
3. `Dockerfile` — multi-stage build (golang:1.22-alpine -> distroless)
4. `.platform/manifest.yaml` — manifesto da plataforma (schema v1 compliant)
5. `.gitlab-ci.yml` — pipeline com validate + build (Kaniko) + deploy (kubectl)
6. `catalog-info.yaml` — registro Backstage
7. `README.md` — documentacao

### Pipeline
- **Validate:manifest**: PASSA (yq valida manifesto, extrai metadata)
- **Build:image**: Kaniko com Harbor insecure registry (fix aplicado, push pendente)
- **Deploy:staging**: kubectl set image (requer namespace provisionado)

### Manifest .platform/manifest.yaml
```yaml
apiVersion: platform.k8s/v1
kind: ApplicationManifest
metadata:
  name: healthcheck-go
  domain: shared-services
  product: platform-tests
  type: api-rest
  owner: platform-team
dependencies:
  database: { enabled: true, type: shared, name: healthcheck_go }
  redis: { enabled: true, mode: standalone }
  rabbitmq: { enabled: true, replicas: 1, vhosts: [healthcheck-go] }
resources:
  requests: { cpu: 50m, memory: 64Mi }
  limits: { cpu: 200m, memory: 128Mi }
  replicas: { min: 1, max: 2 }
config:
  port: 8080
  healthCheck: { liveness: /healthz, readiness: /ready }
  ingress: { enabled: true, host: healthcheck-go.staging.internal, class: internal, tls: true }
```

---

## Fixes na Esteira (codificados nesta sessao)

| # | Fix | Onde | Status |
|---|-----|------|--------|
| 1 | gitlab_user CONNECTION LIMIT 10→50 | RDS PostgreSQL | APLICADO |
| 2 | Role pods/attach | Role gitlab-gitlab-runner | APLICADO |
| 3 | DinD → Kaniko | .gitlab-ci.yml template | CODIFICADO |
| 4 | envFrom → runner environment + pod_spec | ConfigMap gitlab-gitlab-runner | APLICADO |
| 5 | Kaniko --insecure | .gitlab-ci.yml | CODIFICADO (push pendente) |
| 6 | Sidekiq force transition | Script Ruby workaround | MANUAL |

---

## Proximos Passos

1. **Desbloquear Gitaly**: Escalar system nodegroup ou ajustar resources do Gitaly StatefulSet
2. **Push fix #5**: Kaniko insecure registry para Harbor HTTP
3. **Completar build:image**: Primeira build com sucesso no Harbor
4. **Provisionar namespace**: Executar create-app.sh com o manifesto
5. **Deploy staging**: Verificar pod Running com health checks
6. **Repetir para Python**: Flask healthchecker
7. **Repetir para .NET**: ASP.NET Minimal API healthchecker

---

## GAPs Identificados nesta Sessao

| GAP | Descricao | Prioridade |
|-----|-----------|------------|
| GAP-RUNNER-RBAC | Role do runner nao tinha pods/attach | P0 — RESOLVIDO |
| GAP-RUNNER-ENVFROM | envFrom do runner nao injeta em executor pods | P0 — RESOLVIDO |
| GAP-HARBOR-NO-TLS | Harbor staging expoe apenas HTTP, Kaniko espera HTTPS | P1 — WORKAROUND |
| GAP-PODSEC-DIND | PodSecurity baseline bloqueia DinD privileged | P0 — RESOLVIDO (Kaniko) |
| GAP-SIDEKIQ-STUCK | Job status nao transiciona quando DB esta indisponivel | P1 |
| GAP-GITALY-RESOURCES | Gitaly pod Pending por falta de CPU no system nodegroup | P0 — BLOQUEADOR |
| GAP-DB-CONNLIMIT | gitlab_user com CONNECTION LIMIT=10 insuficiente | P0 — RESOLVIDO |
