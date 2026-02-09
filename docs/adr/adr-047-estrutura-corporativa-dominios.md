# ADR 047 — Estrutura Corporativa de Domínios de Negócio

## Data
2026-02-09

## Status
Proposto 📋

## Contexto

O projeto Kubernetes já possui uma **Camada 1 (Técnica)** consolidada com 6 domínios de plataforma (platform-core, cicd-platform, observability, data-services, secrets-management, security) definidos no ADR-002. Esses domínios fornecem infraestrutura compartilhada para suportar aplicações corporativas.

Agora, no Marco 0 do Quickstart AWS EKS, precisamos estruturar a **Camada 2 (Aplicações de Negócio)** seguindo princípios de Domain-Driven Design (DDD), organizando aplicações por **produtos/linhas de negócio** ao invés de categorias técnicas (ETL, Gateway, Utils).

**Filosofia Arquitetural**: "Se começar certo, quando grande já está certo"
- Mesmo sem times estruturados hoje (Marco 0), projetar como se tivéssemos times organizados por domínios corporativos
- Preparar estrutura GitLab, Kubernetes e RBAC para futura implementação do Backstage (Fase 4)
- Organização corporativa > Organização técnica (alinhamento com negócio)

**Aplicações Identificadas**:
- **iPaaS**: 9 microserviços Go/.NET (BFF REST/gRPC/SOAP, MS Core-Comm, Jobs, Notifications, Validation, Peers, Orchestrator)
- **ETL Hatch**: 151 extractors, API Gateway GraphQL, Web UI React, Anexos Service
- **ETL VemSoft**: ETL workers
- **BucketConnector**: Helm chart para S3 API
- **RPA Platform**: Orquestrador de automações (futuro)
- **Serviços Universais**: Notification (Email/Slack/Teams), Files (Generators), Calendar

## Problema

Como organizar aplicações corporativas em Kubernetes garantindo:
1. **Alinhamento com negócio**: Estrutura reflete produtos/linhas de negócio (não funções técnicas)
2. **Escalabilidade**: Suportar crescimento de produtos sem refatoração
3. **Autonomia**: Cada domínio tem ownership completo (código + infra + deploy)
4. **Governança**: Naming conventions, RBAC, labels consistentes
5. **Backstage-ready**: Preparar catálogo de serviços desde o início
6. **Complementaridade**: Coexistir com domínios técnicos do ADR-002 sem conflitos

## Decisões

### 1. Definição de 5 Domínios Corporativos

#### Domain 1: PLATFORM
**Descrição**: Infraestrutura compartilhada (herdada do ADR-002)
**Responsabilidade**: Observabilidade, CI/CD, Secrets, Security
**Componentes**:
- Prometheus, Grafana, Loki, Tempo, OpenTelemetry (observability)
- GitLab, ArgoCD, SonarQube, Backstage (cicd-platform)
- Vault (secrets-management)
- Kyverno, Falco (security)

**Ownership Futuro**: **Platform Team** (SRE, Platform Engineers)
**Namespaces Kubernetes**: `shared-observability`, `staging-platform-cicd`, `prod-platform-cicd`, `shared-security`, `shared-secrets`

---

#### Domain 2: INTEGRATION
**Descrição**: Domínio de Integrações - iPaaS (Integration Platform as a Service)
**Responsabilidade**: Integrações entre sistemas SaaS, orquestração de workflows, adaptadores de protocolos
**Produtos**:
- **iPaaS**: 9 microserviços para integração

**Componentes iPaaS**:
1. ipaas-bff-rest (BFF REST API - Go)
2. ipaas-bff-grpc (BFF gRPC Gateway - Go)
3. ipaas-bff-soap (BFF SOAP Adapter - Go)
4. ipaas-ms-core-comm (Core Communications - Go)
5. ipaas-ms-jobs (Job Scheduler - Go)
6. ipaas-ms-notifications (Notifications Engine - Go)
7. ipaas-ms-validation (Validation Engine - Go)
8. ipaas-ms-peers (Peer Management - Go)
9. ipaas-orchestrator (Orchestrator - .NET + Dapr)

**Dependencies**: PostgreSQL (RDS external), Redis (via data-services), RabbitMQ (via data-services)

**Ownership Futuro**: **Integration Team** (Backend Engineers, Integration Specialists)
**Namespaces Kubernetes**: `staging-integration-ipaas`, `prod-integration-ipaas`
**GitLab Structure**: `/corporate-domains/integration/`

---

#### Domain 3: DATA
**Descrição**: Domínio de Dados - ETL, Data Warehouse, Analytics, Governança de Dados
**Responsabilidade**: Extração, transformação, carga de dados; catálogo de dados; qualidade de dados
**Produtos**:
- **Hatch ETL**: Sistema ETL com 151 extractors
- **VemSoft ETL**: ETL workers legado
- **Data Platform** (futuro): Catálogo, qualidade, governança

**Componentes Hatch**:
1. hatch-etl (ETL workers - 151 extractors)
2. hatch-api-gateway (GraphQL + REST API)
3. hatch-web (React Web UI)
4. hatch-anexos-service (Anexos cataloging)
5. hatch-redis (Redis queue)

**Componentes VemSoft**:
1. vemsoft-etl (ETL workers)

**Dependencies**: PostgreSQL (RDS external ou operator), S3 bucket (anexos storage)

**Ownership Futuro**: **Data Team** (Data Engineers, Analytics Engineers)
**Namespaces Kubernetes**: `staging-data-hatch`, `prod-data-hatch`, `staging-data-vemsoft`, `prod-data-vemsoft`
**GitLab Structure**: `/corporate-domains/data/hatch/`, `/corporate-domains/data/vemsoft/`

---

#### Domain 4: OPERATIONS
**Descrição**: Domínio de Operações - Gestão de Processos, Execução, Fulfillment, Monitoramento Operacional
**Responsabilidade**: Orquestração de processos de negócio, execução de tarefas, fulfillment de pedidos
**Produtos** (futuros):
- **Process Management**: API de processos, frontend de gestão, workers de execução
- **Fulfillment**: API de fulfillment, workers
- **Operational Monitoring**: Dashboard operacional, alertas

**Componentes Process Management** (futuro):
1. process-api (API de processos)
2. process-frontend (Frontend de gestão)
3. process-worker (Workers de execução)

**Ownership Futuro**: **Operations Team** (Product Managers, Ops Engineers, Business Analysts)
**Namespaces Kubernetes**: `staging-operations-process`, `prod-operations-process`, `staging-operations-fulfillment`, `prod-operations-fulfillment`
**GitLab Structure**: `/corporate-domains/operations/`

---

#### Domain 5: SHARED-SERVICES
**Descrição**: Serviços compartilhados universais consumidos por todos os domínios
**Responsabilidade**: Serviços de suporte (Files, Notification, Calendar, Automation/RPA)
**Produtos**:
- **Files**: Storage S3, geração de documentos (Word, PDF, Excel, CSV)
- **Notification**: Gateway de notificações (Email/SMTP/SES, Slack, MS Teams)
- **Calendar**: API de calendário, feriados, integrações corporativas
- **Automation** (RPA): Plataforma de automação de processos robóticos

**Componentes Files**:
1. bucketconnector (S3 API - Helm chart existente)
2. file-generator-word (Geração de Word)
3. file-generator-pdf (Geração de PDF)
4. file-generator-excel (Geração de Excel)
5. file-generator-csv (Geração de CSV)
6. file-templates-api (API de templates)

**Componentes Notification**:
1. notification-gateway (Gateway de notificações)
2. notification-email (Adaptador Email - SMTP/SES)
3. notification-slack (Adaptador Slack)
4. notification-teams (Adaptador MS Teams)
5. notification-templates (Templates engine)
6. notification-worker (Worker de fila)

**Componentes Calendar**:
1. calendar-api (API de calendário)
2. calendar-holidays (Serviço de feriados)
3. calendar-integration (Integração calendários corporativos)

**Componentes Automation** (futuro):
1. automation-orchestrator (Orquestrador de bots)
2. automation-runtime (Runtime de automações)
3. automation-scheduler (Scheduler)
4. automation-dashboard (Dashboard)
5. automation-worker (Workers)

**Ownership Futuro**: **Shared Services Team** (Fullstack Engineers, DevOps)
**Namespaces Kubernetes**: `staging-shared-files`, `prod-shared-files`, `staging-shared-notification`, `prod-shared-notification`, `staging-shared-calendar`, `prod-shared-calendar`, `staging-shared-automation`, `prod-shared-automation`
**GitLab Structure**: `/corporate-domains/shared-services/`

---

### 2. Diferenciação: Domínios Técnicos vs Domínios Corporativos

**Duas Camadas Complementares**:

| Aspecto | Camada 1: Domínios Técnicos (ADR-002) | Camada 2: Domínios Corporativos (ADR-047) |
|---------|----------------------------------------|-------------------------------------------|
| **Foco** | Infraestrutura de plataforma | Aplicações de negócio |
| **Organização** | Por função técnica | Por produto/linha de negócio |
| **Exemplos** | observability, cicd-platform, secrets-management | integration (iPaaS), data (Hatch), shared-services (Files) |
| **Ownership** | Platform Team (infra) | Domain Teams (produto) |
| **Localização Git** | `/domains/{technical-domain}/` | `/corporate-domains/{business-domain}/` |
| **Namespaces K8s** | `shared-*`, `*-platform-*` | `{env}-{business-domain}-{product}` |
| **Consumidores** | Todas as aplicações corporativas | Usuários finais, outros domínios |
| **Mudanças** | Raras, impacto alto | Frequentes, impacto isolado |

**Exemplo de Interação**:
```
Aplicação: iPaaS BFF-REST (Camada 2: INTEGRATION)
├─ Usa: Prometheus + Grafana (Camada 1: observability)
├─ Usa: ArgoCD para deploy (Camada 1: cicd-platform)
├─ Usa: Vault para secrets (Camada 1: secrets-management)
├─ Usa: PostgreSQL (Camada 1: data-services)
└─ Usa: Notification API (Camada 2: SHARED-SERVICES)
```

---

### 3. Critérios de Classificação de Aplicações

Para classificar uma nova aplicação em um domínio corporativo:

#### Pergunta 1: **Qual é o propósito principal?**
- **Integração entre sistemas** → INTEGRATION
- **Processamento de dados (ETL, analytics)** → DATA
- **Orquestração de processos de negócio** → OPERATIONS
- **Serviço universal consumido por múltiplos domínios** → SHARED-SERVICES
- **Infraestrutura de plataforma** → PLATFORM (Camada 1)

#### Pergunta 2: **Quem são os consumidores?**
- **Sistemas SaaS externos/internos** → INTEGRATION
- **Analistas de dados, cientistas de dados** → DATA
- **Equipes operacionais, fulfillment** → OPERATIONS
- **Todos os domínios (transversal)** → SHARED-SERVICES
- **Times de desenvolvimento (transversal)** → PLATFORM

#### Pergunta 3: **Qual é a natureza do dado processado?**
- **Mensagens, eventos, chamadas API** → INTEGRATION
- **Dados brutos, transformações, análises** → DATA
- **Tarefas, workflows, estados de processo** → OPERATIONS
- **Arquivos, notificações, calendários** → SHARED-SERVICES

#### Pergunta 4: **Qual é a frequência de mudança?**
- **Alta (evolução de produto)** → Domínio Corporativo (2, 3, 4, 5)
- **Baixa (estabilidade de plataforma)** → PLATFORM (Camada 1)

**Casos Especiais**:
- **Aplicações legadas não enquadradas**: Criar novo domínio ou refatorar para encaixar
- **Serviços híbridos (ex: RPA com integração)**: Escolher domínio primário (SHARED-SERVICES > INTEGRATION)
- **Dúvidas**: Consultar RFC (Request for Comments) no GitLab Issues

---

### 4. Naming Conventions (Determinísticas)

#### GitLab Groups/Repos
**Formato**: `^(platform|integration|data|operations|shared-services)/[a-z0-9-]+$`

**Estrutura**:
```
/corporate-domains/{domain}/{product-or-service}/
```

**Exemplos Válidos**:
- ✅ `integration/ipaas-bff-rest`
- ✅ `data/hatch/hatch-etl`
- ✅ `shared-services/files/bucketconnector`
- ✅ `operations/process-management/process-api`

**Exemplos Inválidos**:
- ❌ `Integration/iPaaS-BFF-REST` (uppercase não permitido)
- ❌ `gateway/ipaas-bff-rest` (domínio 'gateway' não existe)
- ❌ `integration/iPaaS_BFF_REST` (underscore não permitido)

#### Kubernetes Namespaces
**Formato**: `^(staging|prod|shared)-(platform|integration|data|operations|shared)(-[a-z0-9-]+)?$`

**Exemplos Válidos**:
- ✅ `staging-integration-ipaas`
- ✅ `prod-data-hatch`
- ✅ `shared-observability` (domínio técnico da Camada 1)
- ✅ `staging-shared-files`

**Exemplos Inválidos**:
- ❌ `staging-gateway-ipaas` (domínio 'gateway' não existe)
- ❌ `Staging-Integration-iPaaS` (uppercase não permitido)
- ❌ `staging_integration_ipaas` (underscore não permitido)

#### Labels Kubernetes (Obrigatórias)
```yaml
# CNCF Recommended (OBRIGATÓRIO)
app.kubernetes.io/name: ^[a-z0-9-]+$           # Nome da aplicação
app.kubernetes.io/instance: ^[a-z0-9-]+$       # Instância única
app.kubernetes.io/version: ^\d+\.\d+\.\d+$     # Semver: 1.0.0
app.kubernetes.io/component: ^(api|worker|frontend|backend|database|cache)$
app.kubernetes.io/part-of: ^[a-z0-9-]+-[a-z0-9-]+$  # Ex: integration-ipaas
app.kubernetes.io/managed-by: ^(helm|argocd|terraform)$

# Governança Corporativa (OBRIGATÓRIO)
environment: ^(staging|prod|dev)$
domain: ^(platform|integration|data|operations|shared-services)$
owner: ^[a-z0-9-]+-team$                       # Ex: integration-team
cost-center: ^[a-z0-9-]+$
product: ^[a-z0-9-]+$                          # Ex: ipaas, hatch, bucketconnector
```

#### Backstage Entities
**Formato**:
```yaml
Domain: ^(platform|integration|data|operations|shared-services)$
System: ^[a-z0-9-]+-[a-z0-9-]+$                # Ex: integration-ipaas, data-hatch
Component: ^[a-z0-9-]+$                        # Ex: ipaas-bff-rest, hatch-etl
Owner: ^[a-z0-9-]+-team$                       # Ex: integration-team, data-team
```

---

### 5. RBAC por Domínio Corporativo

**Princípio**: Cada domínio tem um time com ownership completo (GitLab + Kubernetes)

#### GitLab RBAC (por grupo)
```yaml
platform-team:
  access:
    - platform/* (Maintainer)              # Full access à plataforma
    - integration/* (Reporter)             # Read-only (troubleshooting)
    - data/* (Reporter)                    # Read-only (troubleshooting)
    - operations/* (Reporter)              # Read-only (troubleshooting)
    - shared-services/* (Reporter)         # Read-only (troubleshooting)

integration-team:
  access:
    - integration/* (Maintainer)           # Full access ao domínio Integration
    - platform/observability (Reporter)    # Read-only (metrics, logs)
    - shared-services/* (Reporter)         # Read-only (consomem shared services)

data-team:
  access:
    - data/* (Maintainer)                  # Full access ao domínio Data
    - platform/observability (Reporter)    # Read-only (metrics, logs)
    - integration/* (Reporter)             # Read-only (consomem iPaaS)
    - shared-services/* (Reporter)         # Read-only (consomem shared services)

operations-team:
  access:
    - operations/* (Maintainer)            # Full access ao domínio Operations
    - platform/observability (Reporter)    # Read-only (metrics, logs)
    - integration/* (Reporter)             # Read-only (consomem iPaaS)
    - data/* (Reporter)                    # Read-only (consomem dados)
    - shared-services/* (Reporter)         # Read-only (consomem shared services)

shared-services-team:
  access:
    - shared-services/* (Maintainer)       # Full access aos serviços compartilhados
    - platform/observability (Reporter)    # Read-only (metrics, logs)
```

**Níveis de Acesso GitLab**:
- **Owner**: Full control (você hoje, CTO futuro)
- **Maintainer**: Merge, deploy, manage repo (futuros tech leads)
- **Developer**: Push, create MR (futuros desenvolvedores)
- **Reporter**: Read-only, create issues (futuros QA, suporte)

#### Kubernetes RBAC (por namespace)
```yaml
ClusterRoles:
  cluster-admin:           # Acesso total ao cluster (Platform Team)
  namespace-admin:         # Admin no namespace (Tech Leads de cada domínio)
  developer:               # Deploy, debug, logs (Developers)
  viewer:                  # Read-only (QA, Support)

RoleBindings (exemplo):
  namespace: staging-integration-ipaas
  subjects:
    - kind: Group
      name: integration-team
      apiGroup: rbac.authorization.k8s.io
  roleRef:
    kind: ClusterRole
    name: namespace-admin
```

---

### 6. Estratégia GitOps (ArgoCD - Fase 4)

**Princípio**: 1 repo GitOps por domínio/produto

**Estrutura GitOps Repos**:
```
corporate-domains/integration/ipaas-gitops/
├─ base/                    # Manifests base (comuns staging + prod)
│  ├─ namespace.yaml
│  ├─ resourcequota.yaml
│  └─ networkpolicy.yaml
├─ staging/                 # Overlays staging
│  ├─ kustomization.yaml
│  └─ deployments/
│     ├─ ipaas-bff-rest.yaml
│     └─ ...
└─ prod/                    # Overlays prod
   ├─ kustomization.yaml
   └─ deployments/
```

**ArgoCD Application**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: integration-ipaas-staging
  namespace: argocd
spec:
  project: integration                       # 1 ArgoCD Project por domínio
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

### 7. Preparação para Backstage (Fase 4)

**Filosofia**: Preparar estrutura desde Marco 0, mesmo sem Backstage instalado

**catalog-info.yaml** (exemplo: Integration/iPaaS):
```yaml
apiVersion: backstage.io/v1alpha1
kind: Domain
metadata:
  name: integration
  description: Domínio de Integrações - iPaaS para integrações SaaS
  tags:
    - integration
    - ipaas
    - saas
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
    - event-driven
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
  description: iPaaS REST BFF - Frontend Backend for REST APIs
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
  dependsOn:
    - component:ipaas-orchestrator
    - resource:postgres-ipaas
```

**Labels Backstage-Compatible** (desde Marco 0):
```yaml
labels:
  # CNCF + Backstage (OBRIGATÓRIO)
  app.kubernetes.io/name: ipaas-bff-rest
  app.kubernetes.io/instance: staging-ipaas-bff-rest
  app.kubernetes.io/version: "1.2.0"
  app.kubernetes.io/component: api
  app.kubernetes.io/part-of: integration-ipaas   # Backstage agrupa por system
  app.kubernetes.io/managed-by: helm

  # Governança Corporativa
  environment: staging
  domain: integration                             # Domínio corporativo
  owner: integration-team                         # Time responsável (Backstage ownership)
  cost-center: engineering
  product: ipaas                                  # Produto dentro do domínio

annotations:
  # Backstage (adicionar quando Backstage for instalado - Fase 4)
  backstage.io/kubernetes-id: integration-ipaas
  backstage.io/kubernetes-label-selector: "app.kubernetes.io/part-of=integration-ipaas"
  backstage.io/domain: integration                # Domínio corporativo no Backstage
```

---

### 8. Processo de Criação de Novo Domínio Corporativo

**Quando criar novo domínio?**
- Aplicação não se encaixa nos 5 domínios existentes
- Novo produto/linha de negócio estratégico
- Volume de aplicações justifica segregação

**Processo**:
1. **Proposta**: Tech Lead cria RFC (Request for Comments) no GitLab Issues
2. **Aprovação**: Platform Team + CTO aprovam RFC
3. **Criação GitLab**:
   - Criar grupo raiz: `/corporate-domains/{novo-dominio}`
   - Adicionar `{novo-dominio}-team` com Maintainer access
4. **Criação Kubernetes**:
   - Criar namespaces: `staging-{novo-dominio}-*`, `prod-{novo-dominio}-*`
   - Aplicar ResourceQuotas e NetworkPolicies
5. **Backstage**:
   - Criar `catalog-info.yaml` com `kind: Domain`
   - Adicionar `owner: {novo-dominio}-team`
6. **Documentação**:
   - Criar ADR sistêmico em `/docs/adr/`
   - Atualizar ADR-047 com novo domínio
   - Criar README.md em `/corporate-domains/{novo-dominio}/`

---

### 9. Processo de Criação de Novo Produto

**Quando criar novo produto?**
- Nova aplicação dentro de domínio existente
- Novo microserviço dentro de sistema existente

**Processo**:
1. **Decisão**: Tech Lead do domínio decide criar novo produto
2. **Estrutura GitLab**:
   - Criar subgrupo: `{dominio}/{novo-produto}`
   - Criar repos: `{novo-produto}-api`, `{novo-produto}-worker`, etc
   - Criar repo GitOps: `{novo-produto}-gitops`
3. **Estrutura Kubernetes**:
   - Criar namespaces (se necessário): `staging-{dominio}-{novo-produto}`
   - Aplicar labels obrigatórias
4. **Backstage**:
   - Criar `catalog-info.yaml` com `kind: System` (se novo sistema) ou `kind: Component`
   - Referenciar `domain: {dominio}`

---

## Alternativas Consideradas

### Alternativa 1: Organização Técnica (Gateway, ETL, Utils)
**Rejeita**:
- Não reflete estrutura de negócio
- Dificulta comunicação com stakeholders não-técnicos
- Categorias técnicas são ambíguas (ex: RPA é Gateway ou Utils?)
- Não escala para centenas de aplicações

### Alternativa 2: Um Domínio "APP" Genérico
**Rejeita**:
- Perde granularidade de ownership
- Dificulta RBAC e segregação
- Não aproveita benefícios de DDD

### Alternativa 3: Estrutura de Diretórios Git Híbrida
**Rejeita**:
- `/domains/` para técnico + `/applications/` para corporativo
- Cria confusão de nomenclatura
- Preferimos Backstage-First (apps via catalog, não diretórios)

### Alternativa 4: Backstage-First com Labels (ESCOLHIDA)
**Aceita**:
- Manter `/domains/` para plataforma técnica (Camada 1)
- Organizar aplicações corporativas via:
  - GitLab: `/corporate-domains/{domain}/{product}/`
  - Backstage: Catalog com `metadata.domain`
  - Kubernetes: Labels `domain`, `product`, `owner`
- Separação clara: infra em Git, apps no Backstage catalog
- Escalabilidade: centenas de apps sem poluir repo de infra

---

## Consequências

### Positivas
✅ **Alinhamento com negócio**: Domínios refletem produtos/linhas de negócio (DDD)
✅ **Comunicação clara**: "Integration Team" é mais claro que "Gateway Team"
✅ **Autonomia**: Cada domínio tem ownership completo (código, infra, deploy)
✅ **Escalabilidade**: Adicionar novos produtos/domínios sem refatoração
✅ **Backstage-ready**: Labels e estrutura preparados desde Marco 0
✅ **RBAC consistente**: GitLab + Kubernetes RBAC espelham organização
✅ **Onboarding simplificado**: Estrutura espelha organograma corporativo
✅ **GitOps natural**: ArgoCD Application aponta para repo GitOps por domínio

### Negativas
⚠️ **Estrutura mais complexa**: Requer disciplina para manter governança
⚠️ **Curva de aprendizado**: Times precisam entender diferença Camada 1 vs 2
⚠️ **Documentação adicional**: Mais ADRs, naming conventions, processos

### Riscos
🔴 **Risco**: Confusão entre domínios técnicos (ADR-002) vs corporativos (ADR-047)
🟢 **Mitigação**: Documentação clara, naming conventions distintos, treinamento

🔴 **Risco**: Violação de naming conventions (GitLab, K8s, labels)
🟢 **Mitigação**: Enforcement via pre-push hooks (GitLab), Kyverno (K8s), CI/CD validation

🔴 **Risco**: RBAC inconsistente entre GitLab e Kubernetes
🟢 **Mitigação**: Scripts de validação (`/scripts/governance/validate-rbac.sh`)

---

## Métricas de Sucesso

✅ **5 domínios corporativos definidos e documentados**
✅ **Naming conventions validadas via regex (100% conformidade)**
✅ **RBAC GitLab configurado por domínio (5 grupos: platform-team, integration-team, data-team, operations-team, shared-services-team)**
✅ **Labels Kubernetes obrigatórias aplicadas em todos os recursos (domain, owner, product)**
✅ **catalog-info.yaml criado para todos os produtos (Backstage-ready)**
✅ **GitOps repos estruturados: 1 repo por domínio/produto**
✅ **Backstage cataloga 5 domínios + sistemas + componentes (Fase 4)**
✅ **Developer Experience**: Time consegue localizar serviços por domínio corporativo (não técnico)
✅ **Auditoria de governança**: Scripts de validação passam sem violações

---

## Referências

- **ADR-002**: Estrutura de Domínios Técnicos (Camada 1)
- **ADR-048**: Naming Conventions Determinísticas (complementar)
- **ADR-049**: Governança e RBAC (complementar)
- **Domain-Driven Design (DDD)**: Eric Evans, "Domain-Driven Design: Tackling Complexity in the Heart of Software"
- **Backstage Documentation**: https://backstage.io/docs/features/software-catalog/
- **CNCF Recommended Labels**: https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/

---

## Aprovações

- [ ] Usuário (gilvangalindo)
- [ ] Architect Guardian
- [ ] Platform Team (quando formado)

---

## Próximos Passos

1. ✅ Aprovar ADR-047
2. 📋 Criar ADR-048 (Naming Conventions Determinísticas)
3. 📋 Criar ADR-049 (Governança e RBAC)
4. 📋 Atualizar SAD v1.2 → v1.3 (adicionar Camada 2)
5. 📋 Criar documentação de governança (`/docs/governance/`)
6. 📋 Criar estrutura GitLab (`/corporate-domains/`)
7. 📋 Implementar scripts de validação (`/scripts/governance/`)
8. 📋 Onboarding de 1ª aplicação por domínio (5 pilotos)
