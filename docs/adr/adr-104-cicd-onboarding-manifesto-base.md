# ADR-104 — CI/CD Onboarding Automatizado via Manifesto Base

| Campo | Valor |
|---|---|
| **Status** | Accepted |
| **Data** | 2026-03-11 |
| **Autores** | Mesa Tecnica (DevOps, Platform, SRE) |
| **Revisores** | Arquitetura |
| **Relacionados** | ADR-047 (Dominios), ADR-048 (Naming), ADR-049 (RBAC Dominios), ADR-055 (FinOps/Security), ADR-102 (Backstage IDP), GOV-001 |

---

## Contexto

Onboarding de novas aplicacoes no cluster Kubernetes exige 2-4 dias de trabalho manual: criacao de namespace, configuracao de banco, Redis, RabbitMQ, Vault secrets, Keycloak client, ExternalSecrets e ArgoCD Application. Processo propenso a erros, inconsistencias de naming e falta de padronizacao entre dominios.

A plataforma necessita de um mecanismo declarativo e self-service que permita aos desenvolvedores provisionar todos os recursos necessarios de forma automatizada, padronizada e auditavel.

## Decisao

Criar sistema declarativo de onboarding via Manifesto Base YAML (`.platform/manifest.yaml`), acionado por pipeline GitLab CI, que executa scripts idempotentes para provisionar automaticamente todos os recursos necessarios. O manifesto segue o schema `apiVersion: platform.k8s/v1`, kind `ApplicationManifest`.

### Fluxo Arquitetural

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

## Decisoes da Mesa Tecnica (2026-03-11)

### P1 — Presets de Recursos por Tipo de App

Baseados em consumo real do cluster. Aplicados quando o manifesto nao especifica valores explicitos de recursos.

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

### P3 — Localizacao do Manifesto: `.platform/manifest.yaml`

Justificativa: alinha com `.github/`, `.gitlab/`, extensivel, nao polui raiz do repositorio.

### P4 — Estrutura do Repositorio de Scripts: `domains/platform-core/app-provisioning`

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
- Migration: script v1-to-v2.sh + CI detecta versao automaticamente

### P7 — Status dos Operators

| Operator | Status | Versao |
|----------|--------|--------|
| RabbitMQ | OPERACIONAL | 2.19.0 (12 CRDs) |
| Redis | OPERACIONAL | OT v0.23.0 (4 CRDs) |

### P8 — ServiceAccount para Pipeline CI

- SA: `platform-provisioner` em namespace `cicd-argocd`
- ClusterRole: least privilege (namespaces, services, secrets, RBAC, CRDs Redis/RabbitMQ, ArgoCD, ESO)
- Vault: Kubernetes Auth, role `platform-provisioner`, TTL 30min
- Keycloak: Admin REST API via credenciais Vault
- PostgreSQL: psql via admin password do Vault
- GitLab Runner: 2/2 Running (verificado 2026-03-11)

## Restricoes

- Default negativo: tudo desligado, recursos minimos
- Pipeline de infra roda SEMPRE (idempotente)
- Remocao de recursos: MANUAL (sem destroy automatizado)
- Sem rollback: corrigir manifesto e re-executar
- Credenciais SEMPRE via Vault/ESO
- Naming conventions ADR-048 enforced por Kyverno

## Consequencias

### Positivas

- Reducao de tempo de onboarding de 2-4 dias para < 15 minutos
- Padronizacao cross-domain: todos os dominios seguem o mesmo schema e fluxo
- Self-service para desenvolvedores via Backstage IDP (futuro Marco 2)
- Auditabilidade: todas as decisoes de provisionamento declaradas em YAML versionado no Git
- Presets evitam over-provisioning e alinham com FinOps

### Riscos e Mitigacoes

| Risco | Prob | Impacto | Mitigacao |
|-------|------|---------|-----------|
| Scripts nao-idempotentes | Media | Alto | Testes 2x em CI, padrao check-before-create |
| Schema evolui e quebra manifestos | Media | Alto | Versionamento apiVersion, migration scripts |
| Vault indisponivel | Baixa | Critico | Vault HA, retry com backoff |
| Credenciais RDS expostas | Baixa | Critico | Vault only, mascarar logs CI |
| Pipeline lenta (>15min) | Media | Medio | Paralelizar data services, cache tools |

## Micro-Sprints de Implementacao

| Sprint | Titulo | Escopo |
|--------|--------|--------|
| S0 | Fundacao | Presets, ResourceQuotas, estrutura repo scripts |
| S1 | Schema + Validacao | JSON Schema, parser, naming, stage validate |
| S2 | Namespace + Vault + ESO | Scripts namespace, Vault paths, ExternalSecrets |
| S3 | Data Services | PostgreSQL, Redis, RabbitMQ scripts idempotentes |
| S4 | Keycloak + ArgoCD | OIDC client, ArgoCD Application |
| S5 | E2E + App Piloto | Pipeline completa, testes, documentacao, onboarding piloto |
| S6 | Backstage (futuro M2) | Scaffolder gera manifesto automaticamente |

## Referencias

- ADR-047 — Estrutura Corporativa de Dominios
- ADR-048 — Naming Conventions Deterministicas
- ADR-049 — Governanca RBAC Dominios Corporativos
- ADR-055 — FinOps Security Groups Remediation
- ADR-102 — Backstage IDP Strategy
- GOV-001 — Governanca de Plataforma
- Manifesto base: `docs/demands/2026-03-11-cicd-onboarding-manifesto-base.md`
