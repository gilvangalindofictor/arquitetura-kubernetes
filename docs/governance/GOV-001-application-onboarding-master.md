# GOV-001: Application Onboarding Master Guide

> **Versão**: 2.0
> **Data**: 2026-03-11
> **Status**: Ativo
> **Referências**: ADR-047, ADR-048, ADR-049, ADR-104, GOVERNANCE.md, CICD-006
> **Audiência**: Desenvolvedores, Tech Leads, Platform Team
> **Alteração v2.0**: Incorpora onboarding declarativo via Manifesto Base (`.platform/manifest.yaml`) — ADR-104, CICD-006

---

## Visão Geral

Guia consolidado para **onboarding de novas aplicações** na Plataforma Kubernetes.
Unifica naming conventions, provisionamento de recursos, CI/CD, observabilidade e segurança.

**Documentos Complementares**:
- [application-onboarding.md](./application-onboarding.md) — Processo detalhado (passo a passo)
- [argocd-applicationset-onboarding.md](./argocd-applicationset-onboarding.md) — GitOps onboarding
- [naming-conventions.md](./naming-conventions.md) — Naming conventions completas
- [rbac-matrix.md](./rbac-matrix.md) — Matriz RBAC
- [../demands/2026-03-11-cicd-onboarding-manifesto-base.md](../demands/2026-03-11-cicd-onboarding-manifesto-base.md) — CICD-006: Onboarding Automatizado via Manifesto Base
- [../adr/adr-104-cicd-onboarding-manifesto-base.md](../adr/adr-104-cicd-onboarding-manifesto-base.md) — ADR-104: Decisões técnicas (presets, aprovação, schema)

> **⚡ Self-Service disponível (Marco 5):** O processo declarativo via Manifesto Base (`Fase 0` abaixo) é o método preferencial a partir de 2026-03-11. O checklist das fases 1–5 permanece como referência para provisionamento manual ou exceções.

---

## Onboarding via Manifesto Base (Método Preferencial — Self-Service)

> Disponível a partir de **Marco 5** (2026-03-11). Substitui o processo manual das Fases 1–5 para a maioria dos casos. Ref: ADR-104, CICD-006.

### Como funciona

```
Dev → cria .platform/manifest.yaml no repo do app
  → PR staging → Pipeline CI valida schema + naming (ADR-048)
  → Checkout domains/platform-core/app-provisioning
  → Executa scripts idempotentes automaticamente:
    1. provision-namespace.sh  (namespace + ResourceQuota + LimitRange + NetworkPolicy)
    2. provision-vault.sh      (path KV v2 + policy + AppRole)
    3. provision-externalsecrets.sh  (ExternalSecret CRs)
    4. [paralelo] provision-postgresql.sh | provision-redis.sh |
                 provision-rabbitmq.sh | provision-keycloak.sh
    5. provision-argocd.sh     (Application + AppProject)
  → ArgoCD sync → App running no cluster em < 15 minutos
```

### Estrutura mínima do `.platform/manifest.yaml`

```yaml
apiVersion: platform.k8s/v1
kind: ApplicationManifest

metadata:
  name: "minha-app"           # kebab-case (ADR-048), max 63 chars
  domain: "data"              # platform|integration|data|operations|shared-services
  product: "minha-app"
  type: "api-rest"             # etl|api-rest|worker|frontend|cronjob
  owner: "data-team"
  description: "Descrição da aplicação"

dependencies:
  database:
    enabled: true              # false = não provisiona PostgreSQL
  redis:
    enabled: false
  rabbitmq:
    enabled: false
  keycloak:
    enabled: false

# resources: omitir = usa preset do tipo (ADR-104/P1)
# replicas: omitir = usa preset do tipo (ADR-104/P1)
```

### Presets por tipo de aplicação (ADR-104/P1)

| Tipo | CPU Req | CPU Lim | Mem Req | Mem Lim | Replicas staging/prod |
|------|---------|---------|---------|---------|----------------------|
| api-rest | 100m | 400m | 128Mi | 512Mi | 1 / 2 |
| worker | 100m | 400m | 128Mi | 512Mi | 1 / 1 |
| etl | 200m | 800m | 256Mi | 1Gi | 1 / 1 |
| frontend | 50m | 200m | 64Mi | 256Mi | 1 / 2 |
| cronjob | 100m | 500m | 128Mi | 512Mi | n/a |

### Camadas de aprovação de recursos (ADR-104/P5)

```
Camada 1: AUTO       — recursos ≤ preset do tipo → pipeline aceita automaticamente
Camada 2: TECH LEAD  — recursos > preset, ≤ hard cap → exige 1 Maintainer no MR
Camada 3: BLOCK      — recursos > hard cap (4Gi mem / 2000m CPU) → pipeline bloqueia
                       (Kyverno ClusterPolicy enforce-resource-hard-cap)
```

Para solicitar exception ao hard cap: abra MR com label `resource-exception` e justificativa técnica.

### Pontos de entrada

| Ação | Comando / Local |
|------|-----------------|
| Criar manifesto | Copiar `domains/platform-core/app-provisioning/templates/manifest-template.yaml` |
| Validar manualmente | `bash scripts/validation/validate-manifest.sh --manifest .platform/manifest.yaml` |
| Executar provisionamento | Pipeline CI (automático no push para `staging`) |
| Configurar env production | `bash scripts/onboarding/setup-gitlab-environments.sh --project-path "grupo/app" --env all` |

---

## Checklist de Onboarding (Processo Manual / Exceções)

> Use este checklist para casos não cobertos pelo Manifesto Base ou para referência de auditoria.

### Fase 1: Planejamento

| # | Tarefa | Responsável | Referência |
|---|--------|-------------|------------|
| 1 | Definir domínio corporativo (platform/integration/data/operations/shared-services) | Product Owner | ADR-047 |
| 2 | Definir nome do produto (kebab-case) | Tech Lead | ADR-048 |
| 3 | Validar naming contra regex: `^[a-z0-9-]+$` | Automatizado | naming-conventions.md |
| 4 | Definir recursos necessários (PostgreSQL, Redis, RabbitMQ) | Tech Lead | GOV-002/003/004 |
| 5 | Definir requisitos de autenticação (Keycloak client) | Tech Lead | GOV-005 |

### Fase 2: Provisionamento de Infraestrutura

| # | Tarefa | Responsável | Referência |
|---|--------|-------------|------------|
| 6 | Criar namespace Kubernetes: `{env}-{domain}-{produto}` | Platform Team | GOVERNANCE.md |
| 7 | Provisionar database PostgreSQL (se necessário) | Platform Team | GOV-002, ADR-060 |
| 8 | Provisionar Redis instance (se necessário) | Platform Team | GOV-003, ADR-061 |
| 9 | Provisionar RabbitMQ cluster (se necessário) | Platform Team | GOV-004, ADR-062 |
| 10 | Criar secrets no Vault + ExternalSecrets | Platform Team | GOV-006 |
| 11 | Criar Keycloak client OIDC (se necessário) | Platform Team | GOV-005 |

### Fase 3: CI/CD e GitOps

| # | Tarefa | Responsável | Referência |
|---|--------|-------------|------------|
| 12 | Criar repositório GitLab: `corporate-domains/{domain}/{produto}` | Tech Lead | ADR-048 |
| 13 | Configurar `.gitlab-ci.yml` com security template | Desenvolvedor | GOV-009, CICD-001 |
| 13a | Criar `.platform/manifest.yaml` (onboarding declarativo) | Desenvolvedor | ADR-104, CICD-006 |
| 14 | Criar Helm chart com labels obrigatórias | Desenvolvedor | GOVERNANCE.md |
| 15 | Criar ArgoCD Application (ou usar manifesto base — automático) | Platform Team | GOV-007, ADR-104 |
| 16 | Validar pipeline: SAST/DAST/Trivy/TruffleHog + resource approval | CI/CD | GOV-009, ADR-104/P5 |
| 16a | Configurar environment protection rules (staging auto / production manual) | Platform Team | ADR-104, GAP-017 |

### Fase 4: Observabilidade

| # | Tarefa | Responsável | Referência |
|---|--------|-------------|------------|
| 17 | Instrumentar com OpenTelemetry (métricas, logs, traces) | Desenvolvedor | GOV-008 |
| 18 | Criar ServiceMonitor para Prometheus | Desenvolvedor | GOV-008 |
| 19 | Configurar alertas no Grafana | Platform Team | GOV-008 |
| 20 | Validar logs no Loki (formato JSON estruturado) | Desenvolvedor | GOV-008 |

### Fase 5: Segurança e Rede

| # | Tarefa | Responsável | Referência |
|---|--------|-------------|------------|
| 21 | Criar NetworkPolicies (least-privilege) | Platform Team | GOV-010 |
| 22 | Validar TLS/HTTPS em ingress | Platform Team | GOV-010 |
| 23 | Registrar no Backstage catalog | Desenvolvedor | GOV-011 |

---

## Labels Kubernetes Obrigatórias

Toda aplicação DEVE ter os seguintes labels (validados via Kyverno):

```yaml
metadata:
  labels:
    # Obrigatórias (Kyverno enforce)
    app.kubernetes.io/name: "{produto}"
    app.kubernetes.io/part-of: "{domain}-{produto}"
    app.kubernetes.io/managed-by: "argocd"
    domain: "{domain}"
    owner: "{domain}-team"

    # Recomendadas (FinOps)
    app.kubernetes.io/version: "v1.0.0"
    cost-center: "{domain}"

  annotations:
    # Backstage integration
    backstage.io/kubernetes-id: "{domain}-{produto}"
    backstage.io/domain: "{domain}"
```

**Validação**:
```bash
# Verificar labels obrigatórias
kubectl get pods -n {namespace} -o jsonpath='{.items[*].metadata.labels}' | jq
```

---

## Namespace Naming

```yaml
Formato: {env}-{domain}-{produto}
Regex: ^(staging|prod)-(platform|integration|data|operations|shared-services)-[a-z0-9-]+$

Exemplos Válidos:
✅ staging-data-rpa-exemplo
✅ prod-integration-ipaas
✅ staging-shared-services-files

Exemplos Inválidos:
❌ rpa-exemplo              # Falta env e domain
❌ staging-rpa-exemplo      # Falta domain
❌ Staging-Data-Rpa         # Uppercase não permitido
```

---

## Quick Reference: Naming por Recurso

| Recurso | Formato | Exemplo |
|---------|---------|---------|
| **Namespace** | `{env}-{domain}-{produto}` | `staging-data-rpa-exemplo` |
| **GitLab Repo** | `corporate-domains/{domain}/{produto}` | `corporate-domains/data/rpa-exemplo` |
| **Helm Release** | `{produto}` | `rpa-exemplo` |
| **PostgreSQL DB** | `{produto}` (snake_case) | `rpa_exemplo` |
| **Redis CR** | `{produto}-redis` | `rpa-exemplo-redis` |
| **RabbitMQ CR** | `{produto}-rabbitmq` | `rpa-exemplo-rabbitmq` |
| **Vault Path** | `secret/{domain}/{produto}/*` | `secret/data/rpa-exemplo/db-password` |
| **Backstage Component** | `{produto}` | `rpa-exemplo` |

---

## Referências

- [application-onboarding.md](./application-onboarding.md) — Processo detalhado
- [GOVERNANCE.md](./GOVERNANCE.md) — Governança geral
- [naming-conventions.md](./naming-conventions.md) — Naming conventions completas
- [ADR-047: Estrutura Corporativa](../adr/adr-047-estrutura-corporativa-dominios.md)
- [ADR-048: Naming Conventions](../adr/adr-048-naming-conventions-deterministicas.md)
- [ADR-049: RBAC Governança](../adr/adr-049-governanca-rbac-dominios-corporativos.md)
- [ADR-104: CI/CD Onboarding Manifesto Base](../adr/adr-104-cicd-onboarding-manifesto-base.md) — Presets, aprovação 3 camadas, schema v1
- [CICD-006: Onboarding Automatizado via Manifesto Base](../demands/2026-03-11-cicd-onboarding-manifesto-base.md) — Sprint S0–S5 COMPLETO (21/22 GAPs resolvidos)
