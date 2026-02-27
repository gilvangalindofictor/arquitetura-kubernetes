# GOV-011: Backstage Catalog Template & Preparation

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo (Preparação desde Marco 0, deployment Marco 4+)
> **Referências**: ADR-047, backstage-standards.md
> **Audiência**: Desenvolvedores, Platform Team

---

## Visão Geral

Backstage é o developer portal para catalogar todos os serviços, APIs e recursos da plataforma.
Desde Marco 0, toda aplicação é preparada com `catalog-info.yaml` para integração futura.

**Referência**: [backstage-standards.md](./backstage-standards.md) — Template completo.

---

## Entity Model

```
Domain (5 domínios corporativos)
  └── System (agrupamento lógico de componentes)
       └── Component (serviço, library, website)
            ├── API (providesApis)
            └── Resource (dependsOn: postgres, redis, rabbitmq)
```

### Domínios

| Domain | Descrição |
|--------|-----------|
| `platform` | Infraestrutura compartilhada |
| `integration` | iPaaS, APIs, integrações SaaS |
| `data` | ETL, Analytics, Data Lake |
| `operations` | Process Management, Fulfillment |
| `shared-services` | Files, Notifications, Automation |

---

## Naming Conventions

| Entity | Pattern | Exemplo |
|--------|---------|---------|
| **Domain** | `^(platform\|integration\|data\|operations\|shared-services)$` | `integration` |
| **System** | `^{domain}-[a-z0-9-]+$` | `integration-ipaas` |
| **Component** | `^[a-z0-9-]+$` | `ipaas-bff-rest` |
| **API** | `^[a-z0-9-]+-api$` | `ipaas-rest-api` |
| **Resource** | `^(postgres\|redis\|rabbitmq)-[a-z0-9-]+$` | `postgres-ipaas` |

---

## catalog-info.yaml Template

Cada repositório DEVE ter um `catalog-info.yaml` na raiz:

```yaml
# /{produto}/catalog-info.yaml

# --- Domain (um por domínio, no repo principal) ---
apiVersion: backstage.io/v1alpha1
kind: Domain
metadata:
  name: {domain}
  description: "{domain-description}"
  tags: [{domain}, {tags}]
spec:
  owner: {domain}-team

---
# --- System ---
apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: {domain}-{produto}
  description: "{produto-description}"
  tags: [{domain}, {tags}]
  annotations:
    backstage.io/source-location: "url:https://gitlab.{company}/corporate-domains/{domain}/{produto}"
spec:
  owner: {domain}-team
  domain: {domain}

---
# --- Component ---
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: {produto}
  description: "{component-description}"
  tags: [{language}, {framework}, {tags}]
  annotations:
    backstage.io/kubernetes-label-selector: "app.kubernetes.io/name={produto}"
    backstage.io/source-location: "url:https://gitlab.{company}/corporate-domains/{domain}/{produto}"
spec:
  type: service                      # service | library | website
  lifecycle: production              # production | experimental | deprecated
  owner: {domain}-team
  system: {domain}-{produto}
  providesApis:
    - {produto}-api                  # Se expõe API
  dependsOn:
    - resource:postgres-{produto}    # Se usa PostgreSQL
    - resource:redis-{produto}       # Se usa Redis
    - resource:rabbitmq-{produto}    # Se usa RabbitMQ
```

---

## Resource Templates

### PostgreSQL Resource

```yaml
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: postgres-{produto}
  description: "PostgreSQL database for {produto}"
spec:
  type: database
  owner: {domain}-team
  system: {domain}-{produto}
```

### Redis Resource

```yaml
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: redis-{produto}
  description: "Redis instance for {produto}"
spec:
  type: cache
  owner: {domain}-team
  system: {domain}-{produto}
```

### RabbitMQ Resource

```yaml
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: rabbitmq-{produto}
  description: "RabbitMQ cluster for {produto}"
spec:
  type: message-queue
  owner: {domain}-team
  system: {domain}-{produto}
```

---

## API Template

```yaml
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: {produto}-api
  description: "{produto} REST API"
  tags: [rest, api]
spec:
  type: openapi                      # openapi | grpc | graphql | asyncapi
  lifecycle: production
  owner: {domain}-team
  system: {domain}-{produto}
  definition: |
    openapi: "3.0.0"
    info:
      title: {produto} API
      version: "1.0.0"
    paths:
      /health:
        get:
          summary: Health check
          responses:
            '200':
              description: OK
```

---

## Labels Kubernetes (Backstage-Compatible)

```yaml
metadata:
  labels:
    app.kubernetes.io/name: "{produto}"
    app.kubernetes.io/part-of: "{domain}-{produto}"
    domain: "{domain}"
    owner: "{domain}-team"
  annotations:
    backstage.io/kubernetes-id: "{domain}-{produto}"
    backstage.io/domain: "{domain}"
```

---

## Exemplo Completo: RPA Exemplo (Data Domain)

```yaml
# corporate-domains/data/rpa-exemplo/catalog-info.yaml

apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: data-rpa-exemplo
  description: "RPA Exemplo - Robotic Process Automation"
  tags: [data, rpa, python]
  annotations:
    backstage.io/source-location: "url:https://gitlab.company.com/corporate-domains/data/rpa-exemplo"
spec:
  owner: data-team
  domain: data

---
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: rpa-exemplo
  description: "RPA Exemplo Python Application"
  tags: [python, fastapi, rpa]
  annotations:
    backstage.io/kubernetes-label-selector: "app.kubernetes.io/name=rpa-exemplo"
spec:
  type: service
  lifecycle: production
  owner: data-team
  system: data-rpa-exemplo
  providesApis: [rpa-exemplo-api]
  dependsOn:
    - resource:postgres-rpa-exemplo
    - resource:redis-rpa-exemplo

---
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: postgres-rpa-exemplo
  description: "PostgreSQL database for RPA Exemplo"
spec:
  type: database
  owner: data-team
  system: data-rpa-exemplo

---
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: redis-rpa-exemplo
  description: "Redis cache for RPA Exemplo"
spec:
  type: cache
  owner: data-team
  system: data-rpa-exemplo

---
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: rpa-exemplo-api
  description: "RPA Exemplo REST API"
  tags: [rest, fastapi]
spec:
  type: openapi
  lifecycle: production
  owner: data-team
  system: data-rpa-exemplo
  definition: |
    openapi: "3.0.0"
    info:
      title: RPA Exemplo API
      version: "1.0.0"
```

---

## Onboarding Checklist (Backstage)

| # | Tarefa | Responsável |
|---|--------|-------------|
| 1 | Criar `catalog-info.yaml` na raiz do repo | Desenvolvedor |
| 2 | Definir System, Component, APIs, Resources | Desenvolvedor |
| 3 | Adicionar labels Backstage-compatible nos K8s manifests | Desenvolvedor |
| 4 | Validar naming conventions (GOV-001) | Automatizado |
| 5 | Registrar location no Backstage catalog | Platform Team |

---

## Referências

- [backstage-standards.md](./backstage-standards.md) — Template original
- [ADR-047: Estrutura Corporativa de Domínios](../adr/adr-047-estrutura-corporativa-dominios.md)
- [Backstage System Model](https://backstage.io/docs/features/software-catalog/system-model)
- [GOV-001: Application Onboarding](./GOV-001-application-onboarding-master.md)
