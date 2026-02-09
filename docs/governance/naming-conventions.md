# Naming Conventions Detalhadas

> **Versão**: 1.0
> **Data**: 2026-02-09
> **Referência**: ADR-048, GOVERNANCE.md

---

## 📋 Visão Geral

Este documento expande as **naming conventions determinísticas** definidas no [GOVERNANCE.md](./GOVERNANCE.md) e [ADR-048](../adr/adr-048-naming-conventions-deterministicas.md), fornecendo mais exemplos e casos específicos.

**Princípio**: Todas as convenções são baseadas em **regex validáveis** automaticamente.

---

## 🔤 Convenções Gerais

### Formato Base: lowercase-kebab-case

**Regex**: `^[a-z0-9-]+$`

**Proibido**:
- ❌ UPPERCASE ou MixedCase
- ❌ underscore `_`
- ❌ camelCase ou PascalCase
- ❌ Espaços
- ❌ Caracteres especiais (exceto hífen `-`)

**Separadores**:
- **Hífen `-`**: Palavras dentro de um nome (`ipaas-bff-rest`)
- **Slash `/`**: Hierarquia (grupos GitLab, paths)
- **Ponto `.`**: DNS FQDN (`service.namespace.svc.cluster.local`)

### Comprimentos Máximos

| Recurso | Limite | Razão |
|---------|--------|-------|
| GitLab Group | 63 chars | GitLab limitation |
| GitLab Repo | 100 chars | GitLab limitation |
| Kubernetes Namespace | 63 chars | RFC 1123 DNS Label |
| Kubernetes Label Value | 63 chars | Kubernetes limitation |
| Helm Chart Name | 53 chars | K8s Service Name limit |
| Backstage Entity Name | 63 chars | Backstage convention |

---

## 🗂️ GitLab Naming

### Grupos Raiz

**corporate-domains/** (fixo)

```
Formato: corporate-domains/{domain}
Regex: ^corporate-domains/(platform|integration|data|operations|shared-services)$

Exemplos Válidos:
✅ corporate-domains/platform
✅ corporate-domains/integration
✅ corporate-domains/data
✅ corporate-domains/operations
✅ corporate-domains/shared-services

Exemplos Inválidos:
❌ corporate-domains/gateway          (domínio não existe)
❌ CorporateDomains/integration       (uppercase)
❌ corporate_domains/integration      (underscore)
```

### Repositórios

**Formato**: `corporate-domains/{domain}/{product-or-service}`

```
Regex: ^corporate-domains/(platform|integration|data|operations|shared-services)/[a-z0-9-]+(/[a-z0-9-]+)*$

Exemplos Válidos - Integration:
✅ corporate-domains/integration/ipaas-bff-rest
✅ corporate-domains/integration/ipaas-bff-grpc
✅ corporate-domains/integration/ipaas-orchestrator
✅ corporate-domains/integration/ipaas-helm-charts
✅ corporate-domains/integration/ipaas-gitops

Exemplos Válidos - Data:
✅ corporate-domains/data/hatch/hatch-etl
✅ corporate-domains/data/hatch/hatch-api-gateway
✅ corporate-domains/data/hatch/hatch-web
✅ corporate-domains/data/vemsoft/vemsoft-etl

Exemplos Válidos - Shared Services:
✅ corporate-domains/shared-services/files/bucketconnector
✅ corporate-domains/shared-services/files/file-generator-pdf
✅ corporate-domains/shared-services/notification/notification-gateway
✅ corporate-domains/shared-services/calendar/calendar-api

Exemplos Inválidos:
❌ corporate-domains/Integration/iPaaS-BFF-REST    (uppercase)
❌ corporate-domains/integration/iPaaS_BFF_REST    (underscore)
❌ corporate-domains/gateway/ipaas-bff-rest        (domínio não existe)
❌ integration/ipaas-bff-rest                      (falta prefixo corporate-domains)
```

### Repos Especiais: GitOps

**Formato**: `{domain}/{product}-gitops`

```
Regex: ^corporate-domains/(platform|integration|data|operations|shared-services)/[a-z0-9-]+-gitops$

Exemplos:
✅ corporate-domains/integration/ipaas-gitops
✅ corporate-domains/data/hatch/hatch-gitops
✅ corporate-domains/shared-services/files/files-gitops
```

### Repos Especiais: Helm Charts

**Formato**: `{domain}/{product}-helm-charts`

```
Regex: ^corporate-domains/(platform|integration|data|operations|shared-services)/[a-z0-9-]+-helm-charts$

Exemplos:
✅ corporate-domains/integration/ipaas-helm-charts
✅ corporate-domains/data/hatch/hatch-helm-charts
```

---

## ☸️ Kubernetes Naming

### Namespaces

**Formato**: `{environment}-{domain}-{product}`

```
Regex: ^(dev|staging|prod|shared)-(platform|integration|data|operations|shared)(-[a-z0-9-]+)?$

Ambientes:
- dev: Desenvolvimento
- staging: Homologação/QA
- prod: Produção
- shared: Compartilhado entre ambientes

Domínios (short):
- platform: Platform (observability, cicd, security)
- integration: Integration (iPaaS)
- data: Data (Hatch, VemSoft)
- operations: Operations (Process, Fulfillment)
- shared: Shared Services (Files, Notification)

Exemplos Válidos - Integration:
✅ staging-integration-ipaas
✅ prod-integration-ipaas

Exemplos Válidos - Data:
✅ staging-data-hatch
✅ prod-data-hatch
✅ staging-data-vemsoft
✅ prod-data-vemsoft

Exemplos Válidos - Shared Services:
✅ staging-shared-files
✅ prod-shared-files
✅ staging-shared-notification
✅ prod-shared-notification
✅ staging-shared-calendar
✅ prod-shared-calendar

Exemplos Válidos - Platform (Camada 1):
✅ shared-observability
✅ staging-platform-cicd
✅ prod-platform-cicd

Exemplos Inválidos:
❌ staging-gateway-ipaas           (domínio 'gateway' não existe)
❌ Staging-Integration-iPaaS       (uppercase)
❌ staging_integration_ipaas       (underscore)
❌ integration-ipaas-staging       (ordem errada)
❌ staging-ipaas                   (falta domínio)
```

### Services

**Formato**: `{service-name}` (lowercase-kebab-case)

```
Regex: ^[a-z0-9-]+$
Max Length: 63 chars (RFC 1123 DNS Label)

Exemplos Válidos:
✅ ipaas-bff-rest
✅ hatch-api-gateway
✅ notification-gateway
✅ bucketconnector

Exemplos Inválidos:
❌ iPaaS-BFF-REST        (uppercase)
❌ ipaas_bff_rest        (underscore)
❌ iPaasBffRest          (camelCase)
```

### Service DNS Names (FQDN)

**Formato**: `{service}.{namespace}.svc.cluster.local`

```
Regex: ^[a-z0-9-]+\.[a-z0-9-]+\.svc\.cluster\.local$

Exemplos Válidos:
✅ ipaas-bff-rest.staging-integration-ipaas.svc.cluster.local
✅ hatch-api-gateway.prod-data-hatch.svc.cluster.local
✅ notification-gateway.prod-shared-notification.svc.cluster.local

Short Names (mesmo namespace):
✅ ipaas-bff-rest

Cross-Namespace (mesmo cluster):
✅ ipaas-bff-rest.staging-integration-ipaas
✅ notification-gateway.prod-shared-notification
```

### Secrets

**Formato**: `{product}-{resource}-{type}`

```
Regex: ^[a-z0-9-]+-(postgres|redis|rabbitmq|s3|api|smtp)-(credentials|config|tls)$

Exemplos Válidos:
✅ ipaas-postgres-credentials
✅ hatch-redis-credentials
✅ bucketconnector-s3-credentials
✅ notification-smtp-credentials
✅ ipaas-bff-rest-tls
✅ hatch-api-gateway-tls

Exemplos Inválidos:
❌ iPaaS-Postgres-Credentials    (uppercase)
❌ ipaas_postgres_credentials    (underscore)
```

### ConfigMaps

**Formato**: `{product}-{component}-config`

```
Regex: ^[a-z0-9-]+-config$

Exemplos Válidos:
✅ ipaas-bff-rest-config
✅ hatch-etl-config
✅ notification-gateway-config

Exemplos Inválidos:
❌ iPaaS-BFF-REST-Config    (uppercase)
❌ ipaas_bff_rest_config    (underscore)
```

---

## 🏷️ Kubernetes Labels

### CNCF Recommended Labels (Obrigatórias)

#### app.kubernetes.io/name

```yaml
regex: ^[a-z0-9-]+$
max_length: 63
description: Nome da aplicação

Exemplos Válidos:
✅ ipaas-bff-rest
✅ hatch-etl
✅ bucketconnector
✅ notification-gateway

Exemplos Inválidos:
❌ iPaaS-BFF-REST    (uppercase)
❌ ipaas_bff_rest    (underscore)
```

#### app.kubernetes.io/instance

```yaml
regex: ^[a-z0-9-]+$
max_length: 63
description: Instância única (geralmente {env}-{name})

Exemplos Válidos:
✅ staging-ipaas-bff-rest
✅ prod-hatch-etl
✅ staging-bucketconnector

Exemplos Inválidos:
❌ Staging-iPaaS-BFF-REST    (uppercase)
❌ staging_ipaas_bff_rest    (underscore)
```

#### app.kubernetes.io/version

```yaml
regex: ^\d+\.\d+\.\d+$
description: Semantic Versioning (major.minor.patch)

Exemplos Válidos:
✅ 1.0.0
✅ 2.3.5
✅ 0.1.0

Exemplos Inválidos:
❌ v1.0.0       (prefixo 'v' não permitido no label)
❌ 1.0          (falta patch version)
❌ 1.0.0-beta   (sufixo não permitido no label, use annotation)
```

#### app.kubernetes.io/component

```yaml
regex: ^(api|worker|frontend|backend|database|cache|scheduler|gateway)$
description: Componente arquitetural

Valores Válidos:
✅ api
✅ worker
✅ frontend
✅ backend
✅ database
✅ cache
✅ scheduler
✅ gateway

Valores Inválidos:
❌ API           (uppercase)
❌ rest-api      (usar 'api')
❌ background-job (usar 'worker')
```

#### app.kubernetes.io/part-of

```yaml
regex: ^[a-z0-9-]+-[a-z0-9-]+$
max_length: 63
description: Sistema ao qual pertence (Backstage System)

Exemplos Válidos:
✅ integration-ipaas
✅ data-hatch
✅ shared-files
✅ operations-process

Exemplos Inválidos:
❌ Integration-iPaaS    (uppercase)
❌ integration_ipaas    (underscore)
❌ ipaas                (falta domínio)
```

#### app.kubernetes.io/managed-by

```yaml
regex: ^(helm|argocd|terraform|kubectl)$
description: Ferramenta de gestão

Valores Válidos:
✅ helm
✅ argocd
✅ terraform
✅ kubectl

Valores Inválidos:
❌ Helm      (uppercase)
❌ manual    (usar 'kubectl')
```

### Governança Corporativa Labels (Obrigatórias)

#### environment

```yaml
regex: ^(dev|staging|prod)$
description: Ambiente de execução

Valores Válidos:
✅ dev
✅ staging
✅ prod

Valores Inválidos:
❌ development    (usar 'dev')
❌ production     (usar 'prod')
❌ test           (usar 'staging')
```

#### domain

```yaml
regex: ^(platform|integration|data|operations|shared-services)$
description: Domínio corporativo

Valores Válidos:
✅ platform
✅ integration
✅ data
✅ operations
✅ shared-services

Valores Inválidos:
❌ Integration      (uppercase)
❌ gateway          (domínio não existe, usar 'integration')
❌ etl              (domínio não existe, usar 'data')
❌ utils            (domínio não existe, usar 'shared-services')
```

#### owner

```yaml
regex: ^[a-z0-9-]+-team$
max_length: 63
description: Time responsável (Backstage ownership)

Exemplos Válidos:
✅ integration-team
✅ data-team
✅ shared-services-team
✅ operations-team

Exemplos Inválidos:
❌ Integration-Team     (uppercase)
❌ integration_team     (underscore)
❌ integration          (falta sufixo '-team')
```

#### cost-center

```yaml
regex: ^[a-z0-9-]+$
max_length: 63
description: Centro de custo (FinOps)

Exemplos Válidos:
✅ engineering
✅ data-analytics
✅ operations
✅ cc-12345

Exemplos Inválidos:
❌ Engineering    (uppercase)
❌ data_analytics (underscore)
```

#### product

```yaml
regex: ^[a-z0-9-]+$
max_length: 63
description: Produto dentro do domínio

Exemplos Válidos:
✅ ipaas
✅ hatch
✅ bucketconnector
✅ notification

Exemplos Inválidos:
❌ iPaaS           (uppercase)
❌ bucket_connector (underscore)
```

---

## 🎭 Backstage Naming

### Domain

```yaml
metadata.name:
  regex: ^(platform|integration|data|operations|shared-services)$

Exemplos:
✅ integration
✅ data
✅ shared-services
```

### System

```yaml
metadata.name:
  regex: ^[a-z0-9-]+-[a-z0-9-]+$
  max_length: 63

Exemplos Válidos:
✅ integration-ipaas
✅ data-hatch
✅ shared-files
✅ operations-process

Exemplos Inválidos:
❌ Integration-iPaaS    (uppercase)
❌ integration_ipaas    (underscore)
❌ ipaas                (falta domínio prefix)
```

### Component

```yaml
metadata.name:
  regex: ^[a-z0-9-]+$
  max_length: 63

Exemplos Válidos:
✅ ipaas-bff-rest
✅ hatch-etl
✅ bucketconnector

Exemplos Inválidos:
❌ iPaaS-BFF-REST    (uppercase)
❌ ipaas_bff_rest    (underscore)
```

### API

```yaml
metadata.name:
  regex: ^[a-z0-9-]+-api$
  max_length: 63

Exemplos Válidos:
✅ ipaas-rest-api
✅ hatch-graphql-api
✅ notification-api

Exemplos Inválidos:
❌ iPaaS-REST-API     (uppercase)
❌ ipaas_rest_api     (underscore)
❌ ipaas-rest         (falta sufixo '-api')
```

---

## 🎁 Helm Naming

### Chart Name

```yaml
regex: ^[a-z0-9-]+$
max_length: 53

Exemplos Válidos:
✅ ipaas-bff-rest
✅ hatch-etl
✅ bucketconnector

Exemplos Inválidos:
❌ iPaaS-BFF-REST    (uppercase)
❌ ipaas_bff_rest    (underscore)
```

### Release Name

```yaml
regex: ^[a-z0-9-]+-(dev|staging|prod)$
max_length: 53

Exemplos Válidos:
✅ ipaas-bff-rest-staging
✅ hatch-etl-prod
✅ bucketconnector-staging

Exemplos Inválidos:
❌ iPaaS-BFF-REST-staging    (uppercase)
❌ ipaas-bff-rest            (falta sufixo environment)
❌ staging-ipaas-bff-rest    (ordem errada)
```

---

## 🔀 Git Naming

### Branch Names

```yaml
regex: ^(feature|bugfix|hotfix|release|chore)/[0-9]+-[a-z0-9-]+$

Exemplos Válidos:
✅ feature/123-add-rest-api
✅ bugfix/456-fix-null-pointer
✅ hotfix/789-critical-security-patch
✅ release/1.2.0
✅ chore/101-update-dependencies

Exemplos Inválidos:
❌ Feature/123-Add-REST-API    (uppercase)
❌ feature/add-rest-api        (falta issue ID)
❌ feature/123_add_rest_api    (underscore)
```

### Commit Messages

```yaml
regex: ^\[(platform|integration|data|operations|shared-services):(feat|fix|chore|docs|refactor|test)\] .+$

Exemplos Válidos:
✅ [integration:feat] add REST API endpoint for iPaaS
✅ [data:fix] fix null pointer in hatch-etl
✅ [shared-services:chore] update bucketconnector dependencies

Exemplos Inválidos:
❌ Add REST API endpoint                 (falta prefix [domain:type])
❌ [Integration:feat] add REST API       (uppercase)
❌ [integration] add REST API            (falta type)
```

---

## 📊 Validação

### Scripts de Validação

```bash
# Validar naming GitLab
./scripts/governance/validate-naming.sh <repo-path>

# Validar namespaces Kubernetes
kubectl get ns -o json | jq -r '.items[].metadata.name' | ./scripts/governance/validate-naming.sh --type namespace

# Validar labels Kubernetes
./scripts/governance/validate-labels.sh <namespace>

# Validar Backstage catalog
./scripts/governance/validate-backstage.sh catalog-info.yaml
```

### Kyverno Policies

Localização: `/domains/security/infra/kyverno/policies/`

- `validate-namespace-naming.yaml`
- `require-corporate-labels.yaml`
- `validate-service-naming.yaml`

---

## 📚 Referências

- [ADR-048: Naming Conventions Determinísticas](../adr/adr-048-naming-conventions-deterministicas.md)
- [GOVERNANCE.md](./GOVERNANCE.md)
- [RFC 1123: DNS Label Names](https://tools.ietf.org/html/rfc1123)
- [Kubernetes Labels Best Practices](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [CNCF Recommended Labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)
- [Backstage System Model](https://backstage.io/docs/features/software-catalog/system-model)
