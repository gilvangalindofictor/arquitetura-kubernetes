# ADR 048 — Naming Conventions Determinísticas

## Data
2026-02-09

## Status
Proposto 📋

## Contexto

Com a definição de **5 domínios corporativos** (ADR-047) e **6 domínios técnicos** (ADR-002), precisamos de naming conventions **determinísticas** (baseadas em regex, não ambíguas, validáveis automaticamente) para garantir consistência em:
- **GitLab**: Grupos, subgrupos, repositórios
- **Kubernetes**: Namespaces, labels, annotations
- **Backstage**: Domains, Systems, Components, APIs
- **Helm**: Chart names, release names
- **ArgoCD**: Application names, Project names

**Problema Atual**:
- Sem regex definido para validação automática
- Ambiguidade entre naming de domínios técnicos vs corporativos
- Risco de violação de convenções sem enforcement

**Filosofia**: "Naming is hard, but deterministic naming is enforceable"
- Convenções baseadas em regex (validáveis programaticamente)
- Exemplos válidos vs inválidos claros
- Enforcement via pre-push hooks (GitLab), Admission Controllers (Kubernetes), CI/CD validation (Backstage)

## Problema

Como garantir naming conventions consistentes e validáveis automaticamente em todo o ecossistema (GitLab, Kubernetes, Backstage) para:
1. **Distinguir** domínios técnicos (Camada 1) vs corporativos (Camada 2)
2. **Validar** automaticamente via regex
3. **Enforcear** via tooling (pre-push hooks, Kyverno, CI/CD)
4. **Escalar** para centenas de aplicações sem ambiguidade
5. **Integrar** com Backstage Software Catalog (Fase 4)

## Decisões

### 1. Princípios Gerais de Naming

#### Regra Fundamental
```
Formato: lowercase-kebab-case
Regex: ^[a-z0-9-]+$
Proibido: UPPERCASE, underscore_, camelCase, PascalCase
```

#### Convenção de Separadores
- **Hífen `-`**: Separador de palavras dentro de um nome
  - Exemplo: `ipaas-bff-rest`, `hatch-api-gateway`
- **Slash `/`**: Separador hierárquico (grupos, namespaces)
  - Exemplo: `integration/ipaas-bff-rest`, `data/hatch/hatch-etl`
- **Ponto `.`**: Separador de domínios DNS (FQDN)
  - Exemplo: `ipaas-bff-rest.staging-integration-ipaas.svc.cluster.local`

#### Comprimento Máximo
```yaml
GitLab Group: 63 caracteres
GitLab Repo: 100 caracteres
Kubernetes Namespace: 63 caracteres (RFC 1123 DNS Label)
Kubernetes Label Value: 63 caracteres
Helm Chart Name: 53 caracteres (Kubernetes Service Name limit)
ArgoCD Application: 253 caracteres (Kubernetes Annotation limit)
Backstage Entity Name: 63 caracteres
```

---

### 2. GitLab Naming Conventions

#### 2.1 Grupos Raiz (Root Groups)

**Camada 1: Domínios Técnicos** (infraestrutura)
```
Formato: /domains/{technical-domain}
Regex: ^domains/[a-z0-9-]+$

Domínios Válidos:
- domains/observability
- domains/platform-core
- domains/cicd-platform
- domains/data-services
- domains/secrets-management
- domains/security
```

**Camada 2: Domínios Corporativos** (aplicações)
```
Formato: /corporate-domains/{business-domain}
Regex: ^corporate-domains/(platform|integration|data|operations|shared-services)$

Domínios Válidos:
- corporate-domains/platform
- corporate-domains/integration
- corporate-domains/data
- corporate-domains/operations
- corporate-domains/shared-services
```

#### 2.2 Subgrupos e Repositórios

**Formato Geral**:
```
/{group-root}/{domain}/{product-or-service}/{repo-name}

Regex: ^(domains|corporate-domains)/[a-z0-9-]+(/[a-z0-9-]+)*$
```

**Exemplos Válidos** (Camada 2: Corporativo):
```
✅ corporate-domains/integration/ipaas-bff-rest
✅ corporate-domains/integration/ipaas-orchestrator
✅ corporate-domains/integration/ipaas-gitops
✅ corporate-domains/data/hatch/hatch-etl
✅ corporate-domains/data/hatch/hatch-api-gateway
✅ corporate-domains/data/hatch/hatch-gitops
✅ corporate-domains/data/vemsoft/vemsoft-etl
✅ corporate-domains/shared-services/files/bucketconnector
✅ corporate-domains/shared-services/files/file-generator-pdf
✅ corporate-domains/shared-services/notification/notification-gateway
✅ corporate-domains/operations/process-management/process-api
```

**Exemplos Inválidos**:
```
❌ corporate-domains/Integration/iPaaS-BFF-REST   (uppercase)
❌ corporate-domains/gateway/ipaas-bff-rest       (domínio 'gateway' não existe)
❌ corporate-domains/integration/iPaaS_BFF_REST   (underscore)
❌ CorporateDomains/integration/ipaas-bff-rest    (camelCase)
❌ corporate_domains/integration/ipaas-bff-rest   (underscore no root)
```

#### 2.3 Repos Especiais: GitOps

**Formato**:
```
/{domain}/{product}-gitops

Regex: ^(domains|corporate-domains)/[a-z0-9-]+/[a-z0-9-]+-gitops$
```

**Exemplos**:
```
✅ corporate-domains/integration/ipaas-gitops
✅ corporate-domains/data/hatch/hatch-gitops
✅ corporate-domains/shared-services/files/files-gitops
```

#### 2.4 Repos Especiais: Helm Charts

**Formato**:
```
/{domain}/{product}-helm-charts

Regex: ^(domains|corporate-domains)/[a-z0-9-]+/[a-z0-9-]+-helm-charts$
```

**Exemplos**:
```
✅ corporate-domains/integration/ipaas-helm-charts
✅ corporate-domains/data/hatch/hatch-helm-charts
```

---

### 3. Kubernetes Naming Conventions

#### 3.1 Namespaces

**Formato Geral**:
```
{ambiente}-{dominio}-{produto}

Regex: ^(dev|staging|prod|shared)-(platform|integration|data|operations|shared)(-[a-z0-9-]+)?$
```

**Ambientes**:
- `dev`: Desenvolvimento local/remoto
- `staging`: Homologação/QA
- `prod`: Produção
- `shared`: Compartilhado entre ambientes (ex: observability)

**Domínios** (short names):
- `platform`: Domínio técnico Platform (observability, cicd, security)
- `integration`: Domínio corporativo Integration (iPaaS)
- `data`: Domínio corporativo Data (Hatch, VemSoft)
- `operations`: Domínio corporativo Operations (Process, Fulfillment)
- `shared`: Domínio corporativo Shared Services (Files, Notification, Calendar, Automation)

**Exemplos Válidos** (Camada 2: Corporativo):
```
✅ staging-integration-ipaas
✅ prod-integration-ipaas
✅ staging-data-hatch
✅ prod-data-hatch
✅ staging-data-vemsoft
✅ prod-data-vemsoft
✅ staging-shared-files
✅ prod-shared-files
✅ staging-shared-notification
✅ prod-shared-notification
✅ staging-operations-process
✅ prod-operations-fulfillment
```

**Exemplos Válidos** (Camada 1: Técnico):
```
✅ shared-observability
✅ staging-platform-cicd
✅ prod-platform-cicd
✅ shared-security
✅ shared-secrets
```

**Exemplos Inválidos**:
```
❌ staging-gateway-ipaas         (domínio 'gateway' não existe)
❌ Staging-Integration-iPaaS     (uppercase)
❌ staging_integration_ipaas     (underscore)
❌ integration-ipaas-staging     (ordem errada)
❌ staging-ipaas                 (falta domínio)
```

#### 3.2 Labels (Obrigatórias)

**CNCF Recommended Labels** (kubernetes.io):
```yaml
app.kubernetes.io/name:
  regex: ^[a-z0-9-]+$
  max_length: 63
  description: Nome da aplicação (ex: ipaas-bff-rest)
  examples:
    - ipaas-bff-rest
    - hatch-etl
    - bucketconnector

app.kubernetes.io/instance:
  regex: ^[a-z0-9-]+$
  max_length: 63
  description: Instância única (ex: staging-ipaas-bff-rest)
  examples:
    - staging-ipaas-bff-rest
    - prod-hatch-etl

app.kubernetes.io/version:
  regex: ^\d+\.\d+\.\d+$
  description: Semantic versioning (major.minor.patch)
  examples:
    - 1.0.0
    - 2.3.5
    - 0.1.0-beta

app.kubernetes.io/component:
  regex: ^(api|worker|frontend|backend|database|cache|scheduler|gateway)$
  description: Componente arquitetural
  examples:
    - api
    - worker
    - frontend

app.kubernetes.io/part-of:
  regex: ^[a-z0-9-]+-[a-z0-9-]+$
  max_length: 63
  description: Sistema ao qual pertence (Backstage System)
  examples:
    - integration-ipaas
    - data-hatch
    - shared-files

app.kubernetes.io/managed-by:
  regex: ^(helm|argocd|terraform|kubectl)$
  description: Ferramenta de gestão
  examples:
    - helm
    - argocd
```

**Governança Corporativa Labels** (custom):
```yaml
environment:
  regex: ^(dev|staging|prod)$
  description: Ambiente de execução
  examples:
    - staging
    - prod

domain:
  regex: ^(platform|integration|data|operations|shared-services)$
  description: Domínio corporativo (ADR-047)
  examples:
    - integration
    - data
    - shared-services

owner:
  regex: ^[a-z0-9-]+-team$
  max_length: 63
  description: Time responsável (Backstage ownership)
  examples:
    - integration-team
    - data-team
    - shared-services-team

cost-center:
  regex: ^[a-z0-9-]+$
  max_length: 63
  description: Centro de custo (FinOps)
  examples:
    - engineering
    - data-analytics
    - operations

product:
  regex: ^[a-z0-9-]+$
  max_length: 63
  description: Produto dentro do domínio
  examples:
    - ipaas
    - hatch
    - bucketconnector
```

**Exemplo Completo de Labels**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ipaas-bff-rest
  namespace: staging-integration-ipaas
  labels:
    # CNCF Recommended
    app.kubernetes.io/name: ipaas-bff-rest
    app.kubernetes.io/instance: staging-ipaas-bff-rest
    app.kubernetes.io/version: "1.2.0"
    app.kubernetes.io/component: api
    app.kubernetes.io/part-of: integration-ipaas
    app.kubernetes.io/managed-by: helm

    # Governança Corporativa
    environment: staging
    domain: integration
    owner: integration-team
    cost-center: engineering
    product: ipaas
```

#### 3.3 Annotations (Backstage - Fase 4)

**Formato**:
```yaml
backstage.io/kubernetes-id:
  regex: ^[a-z0-9-]+-[a-z0-9-]+$
  description: System ID no Backstage
  examples:
    - integration-ipaas
    - data-hatch

backstage.io/kubernetes-label-selector:
  format: label_query
  description: Label selector para descoberta de recursos
  examples:
    - "app.kubernetes.io/part-of=integration-ipaas"
    - "app.kubernetes.io/name=hatch-etl"

backstage.io/domain:
  regex: ^(platform|integration|data|operations|shared-services)$
  description: Domínio corporativo no Backstage
  examples:
    - integration
    - data
```

**Exemplo**:
```yaml
annotations:
  backstage.io/kubernetes-id: integration-ipaas
  backstage.io/kubernetes-label-selector: "app.kubernetes.io/part-of=integration-ipaas"
  backstage.io/domain: integration
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

---

### 4. Backstage Naming Conventions (Fase 4)

#### 4.1 Entities

**Domain**:
```yaml
metadata:
  name:
    regex: ^(platform|integration|data|operations|shared-services)$
    description: Nome do domínio corporativo
    examples:
      - integration
      - data
      - shared-services
```

**System**:
```yaml
metadata:
  name:
    regex: ^[a-z0-9-]+-[a-z0-9-]+$
    max_length: 63
    description: Nome do sistema ({dominio}-{produto})
    examples:
      - integration-ipaas
      - data-hatch
      - shared-files
```

**Component**:
```yaml
metadata:
  name:
    regex: ^[a-z0-9-]+$
    max_length: 63
    description: Nome do componente (aplicação individual)
    examples:
      - ipaas-bff-rest
      - hatch-etl
      - bucketconnector
```

**API**:
```yaml
metadata:
  name:
    regex: ^[a-z0-9-]+-api$
    max_length: 63
    description: Nome da API
    examples:
      - ipaas-rest-api
      - hatch-graphql-api
```

**Resource** (Database, Cache, Queue):
```yaml
metadata:
  name:
    regex: ^(postgres|redis|rabbitmq)-[a-z0-9-]+$
    max_length: 63
    description: Nome do recurso
    examples:
      - postgres-ipaas
      - redis-hatch
      - rabbitmq-integration
```

#### 4.2 Exemplo Completo de catalog-info.yaml

```yaml
apiVersion: backstage.io/v1alpha1
kind: Domain
metadata:
  name: integration
  description: Domínio de Integrações - iPaaS
  tags:
    - integration
    - ipaas
spec:
  owner: integration-team

---
apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: integration-ipaas
  description: iPaaS - Integration Platform as a Service
  tags:
    - integration
    - microservices
  annotations:
    backstage.io/source-location: url:https://gitlab.company.com/corporate-domains/integration
spec:
  owner: integration-team
  domain: integration

---
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: ipaas-bff-rest
  description: iPaaS REST BFF
  tags:
    - api
    - rest
    - golang
  annotations:
    backstage.io/kubernetes-label-selector: "app.kubernetes.io/name=ipaas-bff-rest"
    backstage.io/source-location: url:https://gitlab.company.com/corporate-domains/integration/ipaas-bff-rest
spec:
  type: service
  lifecycle: production
  owner: integration-team
  system: integration-ipaas
  providesApis:
    - ipaas-rest-api
```

---

### 5. Helm Naming Conventions

#### 5.1 Chart Name

**Formato**:
```
{product-or-service}

Regex: ^[a-z0-9-]+$
Max Length: 53 caracteres (Kubernetes Service Name limit)
```

**Exemplos**:
```
✅ ipaas-bff-rest
✅ hatch-etl
✅ bucketconnector
✅ notification-gateway
```

#### 5.2 Release Name

**Formato**:
```
{product-or-service}-{environment}

Regex: ^[a-z0-9-]+-(dev|staging|prod)$
Max Length: 53 caracteres
```

**Exemplos**:
```
✅ ipaas-bff-rest-staging
✅ hatch-etl-prod
✅ bucketconnector-staging
```

#### 5.3 Chart Version

**Formato**: Semantic Versioning
```
Regex: ^\d+\.\d+\.\d+$
Examples:
  - 1.0.0
  - 2.3.5
  - 0.1.0
```

#### 5.4 values.yaml Conventions

**Naming de Variáveis**:
```yaml
# Use camelCase para variáveis Helm
replicaCount: 3
image:
  repository: registry.company.com/ipaas-bff-rest
  tag: "1.2.0"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

labels:
  # Labels seguem convenção Kubernetes (kebab-case)
  app.kubernetes.io/name: ipaas-bff-rest
  domain: integration
  owner: integration-team
```

---

### 6. ArgoCD Naming Conventions

#### 6.1 Application Name

**Formato**:
```
{domain}-{product}-{environment}

Regex: ^[a-z0-9-]+-[a-z0-9-]+-(dev|staging|prod)$
Max Length: 253 caracteres
```

**Exemplos**:
```
✅ integration-ipaas-staging
✅ integration-ipaas-prod
✅ data-hatch-staging
✅ data-hatch-prod
✅ shared-files-staging
```

#### 6.2 Project Name

**Formato**:
```
{domain}

Regex: ^(platform|integration|data|operations|shared-services)$
```

**Exemplos**:
```
✅ integration
✅ data
✅ shared-services
```

**1 ArgoCD Project por domínio corporativo**

#### 6.3 Exemplo ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: integration-ipaas-staging
  namespace: argocd
  labels:
    domain: integration
    product: ipaas
    environment: staging
spec:
  project: integration
  source:
    repoURL: https://gitlab.company.com/corporate-domains/integration/ipaas-gitops.git
    targetRevision: main
    path: staging
  destination:
    server: https://kubernetes.default.svc
    namespace: staging-integration-ipaas
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

### 7. Service DNS Names (Kubernetes)

**Formato FQDN**:
```
{service-name}.{namespace}.svc.cluster.local

Regex: ^[a-z0-9-]+\.[a-z0-9-]+\.svc\.cluster\.local$
```

**Exemplos**:
```
✅ ipaas-bff-rest.staging-integration-ipaas.svc.cluster.local
✅ hatch-api-gateway.prod-data-hatch.svc.cluster.local
✅ notification-gateway.prod-shared-notification.svc.cluster.local
```

**Short Names** (dentro do mesmo namespace):
```
{service-name}

Exemplos:
✅ ipaas-bff-rest
✅ hatch-api-gateway
```

**Cross-Namespace** (dentro do mesmo cluster):
```
{service-name}.{namespace}

Exemplos:
✅ ipaas-bff-rest.staging-integration-ipaas
✅ notification-gateway.prod-shared-notification
```

---

### 8. Git Branch Naming

**Formato**:
```
{type}/{issue-id}-{short-description}

Regex: ^(feature|bugfix|hotfix|release|chore)/[0-9]+-[a-z0-9-]+$
```

**Types**:
- `feature/`: Nova funcionalidade
- `bugfix/`: Correção de bug
- `hotfix/`: Correção urgente em produção
- `release/`: Branch de release
- `chore/`: Tarefas de manutenção

**Exemplos**:
```
✅ feature/123-add-rest-api
✅ bugfix/456-fix-null-pointer
✅ hotfix/789-critical-security-patch
✅ release/1.2.0
✅ chore/101-update-dependencies
```

---

### 9. Git Commit Message Convention

**Formato**:
```
[{domain}:{type}] {description}

Regex: ^\[(platform|integration|data|operations|shared-services):(feat|fix|chore|docs|refactor|test)\] .+$
```

**Types**:
- `feat`: Nova funcionalidade
- `fix`: Correção de bug
- `chore`: Manutenção (dependencies, configs)
- `docs`: Documentação
- `refactor`: Refatoração
- `test`: Testes

**Exemplos**:
```
✅ [integration:feat] add REST API endpoint for iPaaS
✅ [data:fix] fix null pointer in hatch-etl
✅ [shared-services:chore] update bucketconnector dependencies
✅ [integration:docs] document ipaas-orchestrator architecture
✅ [data:refactor] refactor hatch-api-gateway error handling
```

---

### 10. Environment Variables Naming

**Formato**: SCREAMING_SNAKE_CASE
```
Regex: ^[A-Z][A-Z0-9_]*$
```

**Exemplos**:
```
✅ ENVIRONMENT
✅ LOG_LEVEL
✅ POSTGRES_HOST
✅ POSTGRES_PORT
✅ POSTGRES_DATABASE
✅ REDIS_HOST
✅ RABBITMQ_URL
✅ AWS_REGION
✅ S3_BUCKET_NAME
```

**Prefixos por Domínio**:
```
IPAAS_*       # iPaaS específico
HATCH_*       # Hatch específico
NOTIFICATION_* # Notification específico
```

---

### 11. Secrets Naming (Kubernetes)

**Formato**:
```
{product}-{resource}-{type}

Regex: ^[a-z0-9-]+-(postgres|redis|rabbitmq|s3|api)-(credentials|config|tls)$
```

**Exemplos**:
```
✅ ipaas-postgres-credentials
✅ hatch-redis-credentials
✅ bucketconnector-s3-credentials
✅ notification-smtp-credentials
✅ ipaas-bff-rest-tls
✅ hatch-api-gateway-tls
```

---

### 12. ConfigMaps Naming (Kubernetes)

**Formato**:
```
{product}-{component}-config

Regex: ^[a-z0-9-]+-config$
```

**Exemplos**:
```
✅ ipaas-bff-rest-config
✅ hatch-etl-config
✅ notification-gateway-config
```

---

## Validação Automática

### Regex por Recurso (Resumo)

```yaml
GitLab:
  group: ^(domains|corporate-domains)/[a-z0-9-]+$
  repo: ^(domains|corporate-domains)/[a-z0-9-]+(/[a-z0-9-]+)*$

Kubernetes:
  namespace: ^(dev|staging|prod|shared)-(platform|integration|data|operations|shared)(-[a-z0-9-]+)?$
  label_name: ^[a-z0-9-]+$
  label_domain: ^(platform|integration|data|operations|shared-services)$
  label_owner: ^[a-z0-9-]+-team$

Backstage:
  domain: ^(platform|integration|data|operations|shared-services)$
  system: ^[a-z0-9-]+-[a-z0-9-]+$
  component: ^[a-z0-9-]+$

Helm:
  chart_name: ^[a-z0-9-]+$
  release_name: ^[a-z0-9-]+-(dev|staging|prod)$

ArgoCD:
  application: ^[a-z0-9-]+-[a-z0-9-]+-(dev|staging|prod)$
  project: ^(platform|integration|data|operations|shared-services)$

Git:
  branch: ^(feature|bugfix|hotfix|release|chore)/[0-9]+-[a-z0-9-]+$
  commit: ^\[(platform|integration|data|operations|shared-services):(feat|fix|chore|docs|refactor|test)\] .+$
```

### Scripts de Validação

Localização: `/scripts/governance/`

**1. validate-naming.sh** (GitLab)
```bash
#!/bin/bash
# Valida naming conventions em repos GitLab

REPO_PATH="$1"
REGEX="^(domains|corporate-domains)/[a-z0-9-]+(/[a-z0-9-]+)*$"

if [[ ! "$REPO_PATH" =~ $REGEX ]]; then
  echo "❌ Erro: Naming convention violada"
  echo "Formato esperado: (domains|corporate-domains)/{domain}/{product}"
  echo "Recebido: $REPO_PATH"
  exit 1
fi

echo "✅ Naming convention OK: $REPO_PATH"
```

**2. validate-labels.sh** (Kubernetes)
```bash
#!/bin/bash
# Valida labels obrigatórias em recursos Kubernetes

NAMESPACE="$1"

kubectl get pods -n "$NAMESPACE" -o json | jq -r '
  .items[] |
  select(.metadata.labels["domain"] == null or .metadata.labels["owner"] == null) |
  .metadata.name
' | while read pod; do
  if [ -n "$pod" ]; then
    echo "❌ Erro: Pod $pod sem labels obrigatórias (domain, owner)"
    exit 1
  fi
done

echo "✅ Todos os pods têm labels obrigatórias"
```

**3. validate-backstage.sh** (Backstage catalog)
```bash
#!/bin/bash
# Valida catalog-info.yaml contra schema Backstage

CATALOG_FILE="$1"

# Valida schema YAML
yq eval '.apiVersion' "$CATALOG_FILE" | grep -q "backstage.io/v1alpha1" || {
  echo "❌ Erro: apiVersion inválido"
  exit 1
}

# Valida owner format
OWNER=$(yq eval '.spec.owner' "$CATALOG_FILE")
if [[ ! "$OWNER" =~ ^[a-z0-9-]+-team$ ]]; then
  echo "❌ Erro: owner deve seguir formato {domain}-team"
  echo "Recebido: $OWNER"
  exit 1
fi

echo "✅ catalog-info.yaml válido"
```

---

## Enforcement

### GitLab: Pre-Push Hook

Localização: `.git/hooks/pre-push` (ou CI/CD pipeline)

```bash
#!/bin/bash
# Pre-push hook para validar naming conventions

REPO_NAME=$(git remote get-url origin | sed 's/.*\///' | sed 's/\.git$//')
EXPECTED_REGEX="^[a-z0-9-]+$"

if [[ ! "$REPO_NAME" =~ $EXPECTED_REGEX ]]; then
  echo "❌ PUSH BLOQUEADO: Nome do repo violou naming convention"
  echo "Esperado: lowercase-kebab-case"
  echo "Recebido: $REPO_NAME"
  exit 1
fi

echo "✅ Naming convention OK"
```

### Kubernetes: Kyverno Policy

Localização: `/domains/security/infra/kyverno/policies/validate-labels.yaml`

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-corporate-labels
spec:
  validationFailureAction: enforce
  rules:
  - name: check-labels
    match:
      any:
      - resources:
          kinds:
          - Pod
          - Deployment
          - StatefulSet
          - DaemonSet
    validate:
      message: "Labels obrigatórias faltando: domain, owner, environment"
      pattern:
        metadata:
          labels:
            domain: "platform | integration | data | operations | shared-services"
            owner: "*-team"
            environment: "dev | staging | prod"
```

### Backstage: CI/CD Validation

Pipeline GitLab CI (`.gitlab-ci.yml`):

```yaml
validate-backstage-catalog:
  stage: validate
  script:
    - ./scripts/governance/validate-backstage.sh catalog-info.yaml
  rules:
    - if: '$CI_MERGE_REQUEST_TARGET_BRANCH_NAME == "main"'
      changes:
        - catalog-info.yaml
```

---

## Alternativas Consideradas

### Alternativa 1: CamelCase ou PascalCase
**Rejeita**: Não é padrão Kubernetes (RFC 1123 DNS Labels exige lowercase)

### Alternativa 2: Underscores (_) como separador
**Rejeita**: Não é padrão Kubernetes (DNS labels não permitem underscores)

### Alternativa 3: Naming sem regex (documentação apenas)
**Rejeita**: Não é validável automaticamente, alta probabilidade de violação

### Alternativa 4: Regex + Enforcement (ESCOLHIDA)
**Aceita**: Validável programaticamente, reduz ambiguidade, escalável

---

## Consequências

### Positivas
✅ **Naming determinístico**: Toda convenção tem regex validável
✅ **Enforcement automático**: Pre-push hooks, Kyverno, CI/CD validation
✅ **Redução de ambiguidade**: Exemplos válidos/inválidos claros
✅ **Escalabilidade**: Suporta centenas de aplicações sem confusão
✅ **Integração Backstage**: Labels compatíveis desde Marco 0
✅ **Auditoria**: Scripts podem listar recursos não conformes

### Negativas
⚠️ **Curva de aprendizado**: Developers precisam memorizar regex
⚠️ **Rigidez**: Mudanças em naming requerem migration scripts

### Riscos
🔴 **Risco**: Naming convention muito restritivo impede casos válidos
🟢 **Mitigação**: Processo de exceção (RFC + approval + label `governance-exception`)

🔴 **Risco**: Scripts de validação falham (falsos positivos/negativos)
🟢 **Mitigação**: Testes unitários para regex, revisão por pares

---

## Métricas de Sucesso

✅ **100% dos repos GitLab seguem convenção** (validável via script)
✅ **100% dos namespaces Kubernetes seguem regex** (`kubectl get ns | grep -v REGEX`)
✅ **100% dos recursos têm labels obrigatórias** (`validate-labels.sh` passa)
✅ **0 violações em audit mensal** (automated scan)
✅ **Backstage catalog válido** (CI/CD validation passa em todos os MRs)
✅ **Pre-push hooks bloqueiam 100% de violações no GitLab**
✅ **Kyverno bloqueia 100% de recursos sem labels no Kubernetes**

---

## Referências

- **RFC 1123**: DNS Label Names
- **Kubernetes Labels**: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/
- **CNCF Recommended Labels**: https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/
- **Backstage System Model**: https://backstage.io/docs/features/software-catalog/system-model
- **Semantic Versioning**: https://semver.org/
- **Kyverno Policies**: https://kyverno.io/policies/

---

## Aprovações

- [ ] Usuário (gilvangalindo)
- [ ] Architect Guardian
- [ ] Platform Team (quando formado)

---

## Próximos Passos

1. ✅ Aprovar ADR-048
2. 📋 Criar scripts de validação (`/scripts/governance/`)
3. 📋 Implementar pre-push hooks no GitLab
4. 📋 Deploy Kyverno policies no Kubernetes
5. 📋 Criar CI/CD validation para Backstage catalog
6. 📋 Documentar naming conventions em `/docs/governance/naming-conventions.md` (versão expandida com mais exemplos)
7. 📋 Treinamento para times (quando formados)
