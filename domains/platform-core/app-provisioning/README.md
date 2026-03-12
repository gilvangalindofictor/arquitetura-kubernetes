# App Provisioning — Onboarding Automatizado via Manifesto Base

> **Dominio**: platform-core
> **Sprint**: S0 (Fundacao)
> **GAP**: GAP-002
> **Ref**: ADR-048, ADR-104, Mesa Tecnica 2026-03-11

Sistema declarativo de onboarding de aplicacoes no cluster Kubernetes. O desenvolvedor declara um `.platform/manifest.yaml` no repositorio da aplicacao e a pipeline CI executa scripts idempotentes que provisionam automaticamente todos os recursos necessarios.

## Estrutura

```
app-provisioning/
  scripts/
    onboarding/
      create-app.sh            # Orquestrador principal — le manifesto e executa fluxo
      create-namespace.sh      # Namespace + ResourceQuota + LimitRange + NetworkPolicy
      create-argocd-app.sh     # ArgoCD Application + AppProject
    provisioning/
      provision-database.sh    # PostgreSQL: database, users, Secret, ExternalSecret, Vault
      provision-redis.sh       # Redis: CR via Operator, Secret, ExternalSecret, Vault
      provision-rabbitmq.sh    # RabbitMQ: vhost, user, exchanges, DLQ, Secret, Vault
      provision-vault.sh       # Vault: KV paths, policy, Kubernetes auth role
      provision-keycloak.sh    # Keycloak: OIDC client, Secret, Vault
    validation/
      validate-manifest.sh     # Valida YAML, apiVersion, campos obrigatorios, hard caps
      validate-naming.sh       # Valida naming conventions ADR-048 (kebab-case, 63 chars)
      validate-labels.sh       # Valida campos para labels Kubernetes obrigatorias
  schemas/v1/
    manifest-schema.json       # JSON Schema placeholder (GAP-003, Sprint S1)
  templates/
    manifest-template.yaml     # Template do .platform/manifest.yaml
    gitlab-ci-template.yml     # Template de pipeline CI com stages validate + provision
  presets/
    etl.yaml                   # CPU 200m/800m, Mem 256Mi/1Gi, Replicas 1/4
    api-rest.yaml              # CPU 100m/400m, Mem 128Mi/512Mi, Replicas 2/8
    worker.yaml                # CPU 100m/400m, Mem 128Mi/512Mi, Replicas 1/6
    frontend.yaml              # CPU 50m/200m, Mem 64Mi/256Mi, Replicas 2/6
    cronjob.yaml               # CPU 100m/500m, Mem 128Mi/512Mi, Replicas n/a
  migrations/                  # Vazio — futuro v1->v2
  tests/                       # Vazio — futuro testes automatizados
```

## Fluxo de Onboarding

```
Dev cria .platform/manifest.yaml no repo do app
  |
  v
PR staging -> Pipeline CI:
  1. validate:manifest   — schema + naming ADR-048 + labels
  2. provision:onboarding — checkout este repo + executa create-app.sh
  |
  v
create-app.sh le manifesto e executa:
  Step 1: Validacao (validate-manifest + validate-naming + validate-labels)
  Step 2: Resolve presets de recursos por tipo (P1)
  Step 3: Cria namespace + ResourceQuota P2 + LimitRange + NetworkPolicy
  Step 4: Provisiona Vault path + policy + Kubernetes auth role
  Step 5: [paralelo] database | redis | rabbitmq | keycloak (se enabled)
  Step 6: Cria ArgoCD Application + AppProject
  |
  v
ArgoCD sync -> App running no cluster
```

## Presets de Recursos (P1)

| Tipo | CPU Req | CPU Lim | Mem Req | Mem Lim | Replicas Min/Max |
|------|---------|---------|---------|---------|------------------|
| api-rest | 100m | 400m | 128Mi | 512Mi | 2 / 8 |
| worker | 100m | 400m | 128Mi | 512Mi | 1 / 6 |
| etl | 200m | 800m | 256Mi | 1Gi | 1 / 4 |
| frontend | 50m | 200m | 64Mi | 256Mi | 2 / 6 |
| cronjob | 100m | 500m | 128Mi | 512Mi | n/a |

**Staging**: 0.5x CPU request, 0.75x memory request, min 1 replica.

## Principios

- **Idempotente**: Todos scripts usam padrao check-before-create. Executar 2x produz mesmo resultado.
- **Default negativo**: Tudo desligado por default. Recursos minimos.
- **Env-agnostic**: Scripts recebem ambiente como parametro, nao hardcodam.
- **Declarativo**: Manifesto YAML e a unica fonte de verdade.
- **Sem destroy**: Remocao de recursos e MANUAL. Scripts apenas criam/atualizam.

## Uso Rapido

```bash
# 1. Copie o template para o repo da app
cp templates/manifest-template.yaml /seu-repo/.platform/manifest.yaml

# 2. Preencha o manifesto

# 3. Execute onboarding (ou via pipeline CI)
./scripts/onboarding/create-app.sh --manifest /seu-repo/.platform/manifest.yaml --env staging

# 4. Dry-run para simular
./scripts/onboarding/create-app.sh --manifest /seu-repo/.platform/manifest.yaml --dry-run
```

## Dependencias

- `kubectl` >= 1.28
- `yq` >= 4.0
- `vault` CLI (opcional, para provisioning Vault)
- `openssl` (para geracao de passwords)
- `curl` + `jq` (para Keycloak provisioning)

## Roadmap

| Sprint | Escopo | Status |
|--------|--------|--------|
| S0 | Estrutura repo, presets, scripts iniciais | ATUAL |
| S1 | JSON Schema completo (GAP-003), stage validate | PENDENTE |
| S2 | Namespace + Vault + ESO scripts completos | PENDENTE |
| S3 | Data services (PostgreSQL, Redis, RabbitMQ) | PENDENTE |
| S4 | Keycloak + ArgoCD | PENDENTE |
| S5 | E2E + App piloto (ETL/Hatch) | PENDENTE |
| S6 | Backstage IDP (futuro M2) | PENDENTE |
