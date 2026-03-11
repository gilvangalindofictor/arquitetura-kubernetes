# Demanda: CI/CD Onboarding Automatizado via Manifesto Base

**Data:** 2026-03-11
**Prioridade:** HIGH (arquitetural / plataforma)
**Status:** PLANEJAMENTO COMPLETO — PRONTO PARA EXECUCAO
**ADR:** ADR-104 (a ser criado)
**Referencias:** ADR-055, ADR-102, ADR-047, ADR-048, ADR-049, ADR-081-085, GOV-001, GOV-009, GOV-011
**Agentes:** Orquestrador, Performance, AWS, Security, TF, Documentation
**Marco:** Marco 5 — Self-Service Platform

## Problema

Onboarding de novas aplicacoes no cluster Kubernetes exige 2-4 dias de trabalho manual: criacao de namespace, configuracao de banco, Redis, RabbitMQ, Vault secrets, Keycloak client, ExternalSecrets e ArgoCD Application. Processo propenso a erros, inconsistencias de naming e falta de padronizacao entre dominios.

## Scope

Criar sistema declarativo de onboarding via Manifesto Base YAML (`.platform/manifest.yaml`), acionado por pipeline GitLab CI, que executa scripts idempotentes para provisionar automaticamente todos os recursos necessarios. Reduzir tempo de onboarding para < 15 minutos, habilitando self-service para desenvolvedores via Backstage IDP (futuro M2).

## Fluxo Arquitetural

```
Dev → Backstage (form) ou manual → .platform/manifest.yaml no repo do app
  → PR staging → Pipeline CI valida schema + naming (ADR-048)
  → Checkout repo centralizado (domains/platform-core/app-provisioning)
  → Executa scripts idempotentes na ordem:
    1. provision-namespace.sh (namespace + ResourceQuota + LimitRange + NetworkPolicy)
    2. provision-vault.sh (path KV v2 + policy + AppRole)
    3. provision-externalsecrets.sh (ExternalSecret CR)
    4. [paralelo] provision-postgresql.sh | provision-redis.sh | provision-rabbitmq.sh | provision-keycloak.sh
    5. provision-argocd.sh (Application + Project)
  → ArgoCD sync → App running no cluster
```

## Schema do Manifesto Base (.platform/manifest.yaml)

```yaml
apiVersion: platform.k8s/v1
kind: ApplicationManifest

metadata:
  name: ""                    # kebab-case (ADR-048), max 63 chars
  domain: ""                  # platform|integration|data|operations|shared-services (ADR-047)
  product: ""                 # agrupa microservicos
  type: ""                    # etl|api-rest|worker|frontend|cronjob
  owner: ""                   # {domain}-team
  description: ""
  tags: []

dependencies:
  database:
    enabled: false             # default negativo
    type: "shared"             # shared|dedicated
    name: ""                   # auto-gerado se vazio
    extensions: []
  redis:
    enabled: false
    mode: "standalone"         # standalone|sentinel
  rabbitmq:
    enabled: false
    replicas: 1
    vhosts: []
  keycloak:
    enabled: false
    clientType: "confidential" # confidential|public
    redirectUris: []

resources:
  requests:
    cpu: ""                    # vazio = preset do tipo
    memory: ""
  limits:
    cpu: ""
    memory: ""
  replicas:
    min: 0
    max: 0

config:
  port: 0
  healthCheck:
    liveness: ""
    readiness: ""
  ingress:
    enabled: false
    host: ""
    class: "internal"          # internal|external
    tls: true
  env: {}
  secretKeys: []
  schedule: ""                 # apenas cronjob

observability:
  metrics:
    enabled: false
    path: "/metrics"
    port: 0
  tracing:
    enabled: false
```

## Decisoes da Mesa Tecnica (2026-03-11)

### P1 — Presets de Recursos por Tipo de App (baseados em consumo real do cluster)

| Tipo | CPU Req | CPU Lim | Mem Req | Mem Lim | Replicas Min/Max |
|------|---------|---------|---------|---------|------------------|
| api-rest | 100m | 400m | 128Mi | 512Mi | 2 / 8 |
| worker | 100m | 400m | 128Mi | 512Mi | 1 / 6 |
| etl | 200m | 800m | 256Mi | 1Gi | 1 / 4 |
| frontend | 50m | 200m | 64Mi | 256Mi | 2 / 6 |
| cronjob | 100m | 500m | 128Mi | 512Mi | n/a |

Staging: 0.5x CPU req, 0.75x mem req, min 1 replica.

### P2 — ResourceQuotas por Namespace

| Pattern | req.cpu | req.mem | lim.cpu | lim.mem | pods |
|---------|---------|---------|---------|---------|------|
| staging-* (padrao) | 2 | 4Gi | 4 | 8Gi | 30 |
| staging-data-* | 3 | 6Gi | 6 | 12Gi | 30 |
| prod-* (padrao) | 4 | 8Gi | 8 | 16Gi | 50 |
| prod-integration-* | 6 | 12Gi | 12 | 24Gi | 75 |
| prod-data-* | 8 | 16Gi | 16 | 32Gi | 50 |

### P3 — Manifesto: `.platform/manifest.yaml`

Justificativa: alinha com `.github/`, `.gitlab/`, extensivel, nao polui raiz.

### P4 — Repo Scripts: `domains/platform-core/app-provisioning`

```
app-provisioning/
  scripts/
    onboarding/        # create-app, create-namespace, create-argocd-app
    provisioning/      # provision-database, redis, rabbitmq, vault, keycloak
    validation/        # validate-manifest, naming, labels
  schemas/v1/          # JSON Schema do manifesto
  templates/           # Helm base, gitlab-ci, manifest
  presets/             # etl.yaml, api-rest.yaml, worker.yaml, frontend.yaml, cronjob.yaml
  migrations/          # v1→v2
  tests/
```

Branching: main/develop/feature + tags semver. Scripts sao env-agnostic.

### P5 — Aprovacao de Recursos (3 Camadas)

```
Camada 1: AUTO (≤ preset)        → Pipeline aceita automaticamente
Camada 2: TECH LEAD (≤ teto)     → MR Approval GitLab (1 Maintainer do dominio)
Camada 3: PLATFORM TEAM (> teto) → MR com label "resource-exception"
Hard Cap: 4Gi mem / 2000m CPU    → Kyverno Enforce bloqueia
```

### P6 — Versionamento do Schema

- apiVersion: `platform.k8s/v1`
- Validacao: JSON Schema + yq
- Backward compat: N-1 (2 versoes, 6 meses deprecation)
- Migration: script v1-to-v2.sh + CI detecta versao

### P7 — Status dos Operators

| Operator | Status | Versao |
|----------|--------|--------|
| RabbitMQ | OPERACIONAL | 2.19.0 (12 CRDs) |
| Redis | OPERACIONAL | OT v0.23.0 (4 CRDs) |

### P8 — ServiceAccount para Pipeline CI

- SA: `platform-provisioner` em `cicd-argocd`
- ClusterRole: least privilege (namespaces, services, secrets, RBAC, CRDs Redis/RabbitMQ, ArgoCD, ESO)
- Vault: Kubernetes Auth, role `platform-provisioner`, TTL 30min
- Keycloak: Admin REST API via credenciais Vault
- PostgreSQL: psql via admin password do Vault
- ALERTA: GitLab Runner em CrashLoopBackOff — resolver antes

## Micro-Sprints

| Sprint | Titulo | Escopo | Dependencias |
|--------|--------|--------|-------------|
| S0 | Fundacao | Presets, ResourceQuotas, estrutura repo scripts | Aprovacao P1/P2 |
| S1 | Schema + Validacao | JSON Schema, parser, naming, stage validate | S0 |
| S2 | Namespace + Vault + ESO | Scripts namespace, Vault paths, ExternalSecrets | S1, Vault HA, ESO |
| S3 | Data Services | PostgreSQL, Redis, RabbitMQ scripts idempotentes | S2, Operators |
| S4 | Keycloak + ArgoCD | OIDC client, ArgoCD Application | S3 |
| S5 | E2E + App Piloto | Pipeline completa, testes, documentacao, onboarding piloto | S0-S4 |
| S6 | Backstage (futuro M2) | Scaffolder gera manifesto automaticamente | S5, Backstage M2 |

## Riscos

| Risco | Prob | Impacto | Mitigacao |
|-------|------|---------|-----------|
| Scripts nao-idempotentes | Media | Alto | Testes 2x em CI, padrao check-before-create |
| Schema evolui e quebra manifestos | Media | Alto | Versionamento apiVersion, migration scripts |
| Vault indisponivel | Baixa | Critico | Vault HA, retry com backoff |
| Credenciais RDS expostas | Baixa | Critico | Vault only, mascarar logs CI |
| Pipeline lenta (>15min) | Media | Medio | Paralelizar data services, cache tools |
| GitLab Runner CrashLoop | ATUAL | Bloqueador | Resolver antes de Sprint 2 |

## Ambientes

- **staging**: branch staging, deploy automatico, serve como dev+staging
- **producao**: branch main, deploy automatico com environment protection rules no GitLab
- GitFlow: feature → PR staging → testa → PR main → producao

## Restricoes Confirmadas

- Default negativo: tudo desligado, recursos minimos
- Pipeline de infra roda SEMPRE (idempotente)
- Remocao de recursos: MANUAL (sem destroy automatizado)
- Sem rollback: corrigir manifesto e re-executar
- Credenciais SEMPRE via Vault/ESO
- Naming conventions ADR-048 enforced por Kyverno

## Resultado

Planejamento completo com 8 decisoes tecnicas (P1-P8) resolvidas em mesa tecnica, 7 micro-sprints definidas (S0-S6), schema do manifesto base especificado e fluxo arquitetural validado.

## Proximos Passos

1. Criar ADR-104 registrando decisoes desta mesa tecnica
2. Resolver GitLab Runner CrashLoopBackOff (bloqueador)
3. Criar repo `domains/platform-core/app-provisioning` no GitLab
4. Iniciar Sprint 0: presets + ResourceQuotas + estrutura
5. Atualizar GOV-001 com conceito de manifesto base
