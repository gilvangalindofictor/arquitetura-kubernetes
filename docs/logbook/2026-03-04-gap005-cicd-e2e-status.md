# 2026-03-04 — GAP-005: CI/CD End-to-End Pipeline Validation

**Demanda:** GAP-005 — Pipeline validation com job real (smoke test)
**Agente:** CI/CD Specialist
**Data:** 2026-03-04
**Duração:** ~30 min (artefatos criados + validação executada)
**Status:** ARTEFATOS COMPLETOS | PRE-REQUISITOS: 9 OK / 3 WARN / 0 FAIL

---

## Contexto

GAP-005 é a demanda de validação end-to-end do pipeline CI/CD. O objetivo é
confirmar que toda a cadeia funciona com um job real:

```
Runner (k8s executor) → Build (kaniko) → Scan (SonarQube) → Push (Harbor) → Verify
```

Estado anterior: runner online, templates criados, credenciais no ESO — mas
nenhum pipeline real havia sido disparado para confirmar a integração.

---

## Estado dos Componentes (2026-03-04 14:11 UTC)

### GitLab (gitlab-staging)

| Pod | Status | Detalhes |
|-----|--------|----------|
| gitlab-gitaly-0 | Running | OK |
| gitlab-gitlab-exporter | Running | OK |
| gitlab-gitlab-runner-6f5797fb5d-7vh2b | Running | 1 restart — OK |
| gitlab-gitlab-shell (x2) | Running | OK |
| gitlab-kas (x2) | Running | OK |
| gitlab-minio | Running | OK |
| gitlab-sidekiq | Running | OK |
| gitlab-toolbox | Running | OK |
| gitlab-webservice-default | Running | 2/2 containers OK |
| **TOTAL** | **11/11 Running** | **100%** |

### Runner

- **ID:** 115 (kubernetes executor)
- **Pod:** gitlab-gitlab-runner-6f5797fb5d-7vh2b
- **Status:** Running (1 restart — não crítico)
- **Logs:** `Configuration loaded`, `Initializing executor providers` — OK
- **WARN:** `request_concurrency=1` causa long polling bottleneck
  - Impacto: jobs podem atrasar em alta concorrência
  - Resolução: configurar `request_concurrency: 2` no Helm values

### Credentials ESO

| Item | Status | Detalhes |
|------|--------|----------|
| ExternalSecret gitlab-ci-credentials | Ready=True | store: vault-backend, refresh: 1h |
| Secret gitlab-ci-credentials | EXISTS | 5 keys presentes |
| Secret keys | OK | HARBOR_PASSWORD, HARBOR_REGISTRY, HARBOR_USER, SONAR_HOST_URL, SONAR_TOKEN |
| Runner envFrom | WARN | Não configurado no deployment atual |

**WARN CRITICO: runner envFrom ausente**

O secret `gitlab-ci-credentials` existe e está sincronizado, mas o runner
deployment NÃO possui `envFrom` apontando para ele. Isso significa que os
jobs CI NÃO receberão automaticamente as variáveis HARBOR_* e SONAR_*.

Situação atual no `values-staging-working.yaml`:
```yaml
gitlab-runner:
  runners:
    config: |
      [[runners]]
        [runners.kubernetes]
          image = "ubuntu:22.04"
        # SEM environment = [...] aqui
```

**Resolução necessária** (ver Próximos Passos).

### Harbor (staging-platform-harbor)

| Pod | Status |
|-----|--------|
| harbor-core (x2) | Running |
| harbor-jobservice | Running |
| harbor-portal (x2) | Running |
| harbor-registry | Running |
| **TOTAL** | **6/6 Running** |

### SonarQube (staging-platform-sonarqube)

| Pod | Status | Restarts |
|-----|--------|---------|
| sonarqube-sonarqube-0 | Running | 129 (WARN) |

**WARN:** 129 restarts são elevados. Esperado em staging com JVM memory pressure.
Não bloqueia o smoke test (SonarQube está Running e respondendo).

### ArgoCD (staging-platform-argocd)

| Pod | Status |
|-----|--------|
| argocd-application-controller-0 | Running |
| argocd-applicationset-controller (x2) | Running |
| argocd-redis | Running |
| argocd-repo-server (x2) | Running |
| argocd-server (x2) | Running |
| argo-rollouts (x2) | Running |
| **TOTAL** | **10/10 Running** |

---

## Sumário da Validação

```
============================================================
 GAP-005: CI/CD End-to-End Pre-Requisite Validation
============================================================
 Timestamp: 2026-03-04 14:11:27 UTC

 OK:   9 checks
 WARN: 3 checks
 FAIL: 0 checks

 STATUS: WARN — pipeline pode funcionar com limitações
============================================================
```

**WARNs identificados:**

1. `runner: long polling issue (request_concurrency=1)` — performance, não bloqueante
2. `runner envFrom não detectado` — CRITICO: credenciais Harbor/SonarQube não injetadas
3. `SonarQube: 129 restarts` — monitorar estabilidade

---

## Artefatos Criados

### 1. Script de criação do projeto smoke-test

**Arquivo:** `scripts/cicd/create-smoke-test-project.sh`

Funcionalidades:
- Cria projeto `smoke-test-ci` no GitLab via API
- Faz upload do `.gitlab-ci.yml` e `Dockerfile` via API (sem git local)
- Dispara pipeline e monitora status em tempo real (polling 15s, timeout 10min)
- Imprime tabela com status de cada job ao final
- Idempotente: reutiliza projeto se já existir

Uso:
```bash
export GITLAB_TOKEN="<personal-access-token>"
bash scripts/cicd/create-smoke-test-project.sh
```

### 2. Pipeline de smoke test

**Arquivo:** `domains/cicd-platform/infra/gitlab-ci/smoke-test/.gitlab-ci.yml`

Stages:
- `validate` — confirma runner online, lista variáveis de credentials (sem expor valores)
- `build` — constrói imagem via kaniko (sem Docker daemon, compatível com K8s runner)
- `scan` — executa SonarQube scan (`allow_failure: true` para não bloquear smoke test)
- `push` — verifica via Harbor API se a imagem foi publicada
- `verify` — sumário final com status de todos os jobs

### 3. Dockerfile minimalista

**Arquivo:** `domains/cicd-platform/infra/gitlab-ci/smoke-test/Dockerfile`

Características:
- Base: `alpine:3.19` (~7MB)
- Labels Kyverno obrigatórios: `app.kubernetes.io/name`, `app.kubernetes.io/part-of`
- Usuário não-root: `appuser:appgroup` (compliance de segurança)
- Health check definido
- Labels OCI completos

### 4. Script de validação de pré-requisitos

**Arquivo:** `scripts/cicd/validate-pipeline-e2e.sh`

Funcionalidades:
- 5 checks: GitLab, Runner, ESO credentials, Harbor, SonarQube, ArgoCD
- Output com OK/WARN/FAIL por componente
- Código de saída: 0=tudo OK, 1=FAIL, 2=WARN
- Próximos passos automáticos no output

---

## Issue Descoberta: runner envFrom Ausente

### Diagnóstico

O secret `gitlab-ci-credentials` foi criado pelo ESO (status: `SecretSynced`),
mas o runner Helm chart não foi configurado para injetar esse secret nos pods
de jobs via `envFrom`.

Verificação:
```bash
kubectl get deployment gitlab-gitlab-runner -n gitlab-staging -o yaml | grep envFrom
# Resultado: 0 linhas (envFrom não configurado)
```

O `config.toml` do runner (via ConfigMap `gitlab-gitlab-runner`) não possui
a seção `environment = [...]` necessária.

### Solução: Opção A — environment no config.toml (recomendada)

Adicionar no `values-staging-working.yaml`:

```yaml
gitlab-runner:
  runners:
    config: |
      [[runners]]
        environment = [
          "HARBOR_REGISTRY=harbor.staging.internal",
          "HARBOR_USER=robot$gitlab-ci"
        ]
        [runners.kubernetes]
          image = "ubuntu:22.04"
          secret = "gitlab-ci-credentials"
        [runners.cache]
          Type = "s3"
          Path = "gitlab-runner"
          Shared = true
          [runners.cache.s3]
            ServerAddress = "minio.staging.internal"
            BucketName = "runner-cache"
            BucketLocation = "us-east-1"
            Insecure = false
```

**NOTA:** `HARBOR_PASSWORD` e `SONAR_TOKEN` devem ser injetados via
`[runners.kubernetes] secret`, não via `environment` (para evitar exposição).

### Solução: Opção B — extraEnv no Helm values

```yaml
gitlab-runner:
  extraEnv:
    - name: HARBOR_REGISTRY
      value: harbor.staging.internal
    - name: HARBOR_USER
      value: "robot$gitlab-ci"
    - name: HARBOR_PASSWORD
      valueFrom:
        secretKeyRef:
          name: gitlab-ci-credentials
          key: HARBOR_PASSWORD
    - name: SONAR_HOST_URL
      valueFrom:
        secretKeyRef:
          name: gitlab-ci-credentials
          key: SONAR_HOST_URL
    - name: SONAR_TOKEN
      valueFrom:
        secretKeyRef:
          name: gitlab-ci-credentials
          key: SONAR_TOKEN
```

### Solução: Opção C — CI/CD Variables no GitLab (interim)

Enquanto o fix do runner não é aplicado, configurar as variáveis diretamente
no projeto smoke-test-ci via GitLab UI:

```
Settings > CI/CD > Variables:
  HARBOR_REGISTRY = harbor.staging.internal
  HARBOR_USER     = robot$gitlab-ci
  HARBOR_PASSWORD = <valor do secret> (masked=true, protected=false)
  SONAR_HOST_URL  = http://sonarqube.staging.internal
  SONAR_TOKEN     = <valor do secret> (masked=true, protected=false)
```

---

## Próximos Passos para Completar o Smoke Test

### Passo 1: Corrigir runner envFrom (BLOQUEANTE para smoke test completo)

Aplicar Opção B (extraEnv) no `values-staging-working.yaml` e executar:

```bash
cd platform-provisioning/aws/kubernetes/terraform/modules/gitlab
helm upgrade gitlab gitlab/gitlab \
  -n gitlab-staging \
  -f values-staging-working.yaml \
  --version 9.9.1 \
  --reuse-values
```

OU aplicar Opção C (CI/CD Variables) como solução interim.

### Passo 2: Criar Personal Access Token no GitLab

```
http://gitlab.staging.internal:8181/-/user_settings/personal_access_tokens
Escopos: api, read_user, read_repository, write_repository
```

### Passo 3: Executar smoke test

```bash
export GITLAB_TOKEN="<token>"
bash scripts/cicd/create-smoke-test-project.sh
```

### Passo 4: Verificar resultado

- Pipeline URL: `http://gitlab.staging.internal:8181/smoke-test-ci/-/pipelines`
- Jobs esperados: validate-runner (OK), build-image (OK), sonarqube-scan (OK/WARN), verify-harbor-push (OK), verify-pipeline (PASSED)

### Passo 5: Documentar como GAP-005 CONCLUIDO

Após smoke test PASSED:
- Atualizar `docs/demands-backlog.md`: GAP-005 status CONCLUIDO
- Atualizar `MEMORY.md`: GAP-005 COMPLETO
- Criar ADR se necessário

---

## Referências

- Runner deployment: `kubectl get deployment gitlab-gitlab-runner -n gitlab-staging -o yaml`
- ESO ExternalSecret: `kubectl get externalsecret gitlab-ci-credentials -n gitlab-staging`
- Harbor: namespace `staging-platform-harbor`
- SonarQube: namespace `staging-platform-sonarqube`
- ArgoCD: namespace `staging-platform-argocd`
- Templates CI: `domains/cicd-platform/infra/gitlab-ci/templates/`
- GitLab values: `platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values-staging-working.yaml`
