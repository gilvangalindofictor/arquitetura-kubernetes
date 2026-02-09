# Software Architecture Document (SAD) - Projeto Kubernetes

> **Versão**: 1.3
> **Data de Criação**: 2025-12-30
> **Última Atualização**: 2026-02-09
> **Status**: � **CONGELADO** (Freeze #3)
> **Versão Anterior**: 1.2 (congelada 2026-01-05, descongelada para v1.3)
> **Metodologia**: AI-First (Engenharia Reversa do iPaaS)
> **Fonte Suprema**: Este documento é a autoridade máxima para decisões arquiteturais sistêmicas

---

## 📋 Visão Geral do SAD

O **Software Architecture Document (SAD)** define as **decisões arquiteturais sistêmicas** da Plataforma Corporativa Kubernetes. Ele é a fonte suprema para:
- Princípios arquiteturais obrigatórios
- Decisões que afetam múltiplos domínios
- Regras de herança e contratos entre domínios
- Validações contra violações (Architect Guardian)

**Escopo**: Plataforma corporativa com 6 domínios especializados, cloud-agnostic obrigatória, isolamento rigoroso.

**Princípios Fundamentais**:
1. **Cloud-Agnostic Obrigatório**: Sem dependências de recursos nativos de clouds específicas
2. **Isolamento de Domínios**: Namespaces, RBAC, Network Policies, Service Mesh por domínio
3. **Governança AI-First**: Hooks obrigatórios, rastreabilidade total, ADRs para decisões
4. **Escalabilidade e Segurança Desde o Início**: Melhores práticas incorporadas
5. **Custo Controlado**: Priorizar open source, otimização de recursos

**Mudanças v1.0 → v1.1**:
- Adicionadas diretrizes práticas para cloud-agnostic (ADR-020)
- Esclarecido escopo de provisionamento de clusters
- Definidos padrões de storage classes e object storage
- Validação contra domínio observability

**Mudanças v1.1 → v1.2**:
- ADR-021 criado (Escolha do Orquestrador de Containers - Kubernetes)
- Decisão fundamental que estava implícita agora documentada explicitamente
- Justificativa: Kubernetes vs Swarm, Nomad, ECS, Cloud Run, Container Apps
- Validação: Kubernetes é o Único que atende ADR-003 (cloud-agnostic) + ecossistema maduro

**Mudanças v1.2 → v1.3**:
- **CAMADA 2 (Aplicações Corporativas)** adicionada ao SAD
- ADR-047 criado (Estrutura Corporativa de Domínios de Negócio)
- ADR-048 criado (Naming Conventions Determinísticas)
- ADR-049 criado (Governança e RBAC para Domínios Corporativos)
- Clarificação: SAD v1.0-1.2 define Camada 1 (Domínios Técnicos - infraestrutura de plataforma)
- Nova Camada 2: 5 domínios corporativos (Platform, Integration, Data, Operations, Shared Services)
- Organização por produtos/linhas de negócio (Domain-Driven Design), não por categorias técnicas
- Naming conventions determinísticas com regex (validáveis automaticamente)
- RBAC consistente entre GitLab ↔ Kubernetes ↔ Backstage
- Preparação para Backstage Software Catalog (Fase 4)

## 🏗️ Princípios Arquiteturais Sistêmicos

### 1. Cloud-Agnostic e Portabilidade
- **Decisão**: Plataforma deve operar em EKS/GKE/AKS/on-prem sem modificações
- **Justificativa**: Flexibilidade, redução de vendor lock-in, migração fácil
- **Implicações**:
  - **Clusters Kubernetes**: Provisionados EXTERNAMENTE aos domínios (ver ADR-020)
  - **Domínios**: Assumem cluster existente e usam apenas APIs Kubernetes nativas
  - **Storage**: Classes parametrizadas por variáveis (gp3, pd-standard, managed-premium, local-path)
  - **Object Storage**: Abstração genérica (S3-compatible: MinIO, AWS S3, GCS, Azure Blob)
  - **IaC**: Terraform com providers intercambiáveis, sem recursos cloud-específicos nos domínios
  - **Service Mesh**: Agnóstico de cloud (Linkerd, Istio)
- **Referência**: ADR-003 (Cloud-Agnostic e Portabilidade), ADR-020 (Provisionamento de Clusters)

### 2. Isolamento e Segurança
- **Decisão**: Cada domínio opera em isolamento completo
- **Justificativa**: Segurança, manutenibilidade, escalabilidade independente
- **Implicações**:
  - Namespaces dedicados por domínio
  - RBAC granular por ServiceAccount
  - Network Policies deny-all por padrão
  - Service Mesh com sidecar isolation
- **Referência**: ADR-005 (Segurança Sistêmica), ADR-014 (Compliance Regulatória)

### 3. IaC e GitOps
- **Decisão**: Terraform + Helm + ArgoCD como padrão
- **Justificativa**: Rastreabilidade, automação, consistência
- **Implicações**:
  - **Clusters**: Provisionados por IaC separada (fora dos domínios)
  - **Domínios**: Terraform apenas para recursos Kubernetes nativos (namespaces, RBAC, services)
  - **Storage**: Classes definidas por variáveis `var.storage_class_name`
  - **Secrets**: Managed externamente (Vault, External Secrets Operator)
  - **GitOps**: Deployments via ArgoCD com drift detection
  - **State**: Remote state obrigatório (S3-compatible + locking)
- **Referência**: ADR-004 (IaC e GitOps), ADR-020 (Provisionamento de Clusters)

### 4. Observabilidade Transversal
- **Decisão**: OpenTelemetry como padrão único
- **Justificativa**: Métricas, logs, traces unificados
- **Implicações**:
  - Todos os domínios exportam métricas via OTEL
  - Dashboards padronizados
  - Alertas centralizados
- **Referência**: ADR-006 (Observabilidade Transversal)

### 5. Escalabilidade e Performance
- **Decisão**: Horizontal + Vertical scaling obrigatório
- **Justificativa**: Custo-otimizado, alta disponibilidade
- **Implicações**:
  - HPA para scaling horizontal
  - VPA para vertical (CPU/memory)
  - Testes de carga obrigatórios
- **Referência**: ADR-008 (Escalabilidade e Performance), ADR-016 (Escalabilidade Vertical)

### 6. Disaster Recovery e HA
- **Decisão**: Multi-region, backup automatizado
- **Justificativa**: Business continuity, compliance
- **Implicações**:
  - Velero para backup/restore
  - RTO/RPO definidos por domínio
  - Testes de failover regulares
- **Referência**: ADR-013 (Disaster Recovery)

### 7. Multi-Tenancy e Governança
- **Decisão**: Isolamento por equipe dentro de domínios
- **Justificativa**: Suporte a múltiplas equipes, governança
- **Implicações**:
  - Namespaces por equipe
  - Resource Quotas
  - Processos para mudanças manuais
- **Referência**: ADR-015 (Multi-Tenancy), ADR-018 (Treinamento e Capacitação)

---

## 🏢 Domínios da Plataforma

### Estrutura Geral
Cada domínio segue padrão isolado:
- **Namespace**: `k8s-{domain}`
- **RBAC**: ServiceAccounts dedicadas
- **Network**: Policies deny-all + allow específicos
- **Observabilidade**: Métricas exportadas para domínio observability
- **Backup**: Velero schedules por domínio

### 1. platform-core (Fundação)
**Responsabilidade**: Gateway, autenticação, service mesh, certificados
**Stack**: Kong, Keycloak, Linkerd, cert-manager, NGINX
**Contratos**:
- Fornece autenticação para todos os domínios
- Service mesh transversal (sidecar injection)
- Certificados TLS para ingress

### 2. cicd-platform (Esteira CI/CD) - 🎯 Primeiro Objetivo
**Responsabilidade**: CI/CD completo, governança via Backstage
**Stack**: GitLab, SonarQube, ArgoCD, Backstage
**Contratos**:
- Consome secrets de secrets-management
- Deploy em todos os domínios via ArgoCD
- Catálogo de apps via Backstage

### 3. observability (Monitoramento Full-Stack)
**Responsabilidade**: Métricas, logs, traces, visualização
**Stack**: OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Kiali
**Contratos**:
- Consome métricas de todos os domínios
- Fornece dashboards e alertas
- Service mesh observability

### 4. data-services (Serviços de Dados)
**Responsabilidade**: DBaaS, CacheaaS, MQaaS com HA
**Stack**: PostgreSQL, Redis, RabbitMQ, Velero
**Contratos**:
- Fornece dados para aplicações via cicd-platform
- Backup automatizado
- Observabilidade via exporters

### 5. secrets-management (Cofre de Senhas)
**Responsabilidade**: Cofre integrado com CI/CD
**Stack**: HashiCorp Vault ou External Secrets Operator
**Contratos**:
- Fornece secrets para cicd-platform
- Rotação automática
- Auditoria de acessos

### 6. security (Policies e Compliance)
**Responsabilidade**: Runtime security, policies, vulnerability scanning
**Stack**: OPA/Kyverno, Falco, Trivy
**Contratos**:
- Policies aplicadas transversalmente
- Scans integrados ao CI/CD
- Compliance auditing

---

## 🏢 Camada 2: Domínios Corporativos (Aplicações de Negócio)

### Visão Geral

**⚠️ NOVA CAMADA (v1.3)**: A partir do SAD v1.3, a arquitetura é organizada em **duas camadas complementares**:

- **Camada 1 (Domínios Técnicos)**: Infraestrutura de plataforma (seção anterior) — observability, platform-core, cicd-platform, data-services, secrets-management, security
- **Camada 2 (Domínios Corporativos)**: Aplicações de negócio organizadas por **produtos/linhas de negócio** (Domain-Driven Design)

**Referência**: ADR-047 (Estrutura Corporativa de Domínios de Negócio)

### Princípio de Organização: Domain-Driven Design (DDD)

**Decisão**: Organizar aplicações por **domínios de negócio** (produtos/linhas de negócio), não por categorias técnicas (ETL, Gateway, Utils).

**Justificativa**:
- Alinhamento com estrutura organizacional da empresa
- Ownership claro por domínio de negócio
- Escalabilidade: adicionar novos produtos sem refatoração
- Backstage-ready: catálogo reflete organização corporativa

**Rejeita**: Categorias técnicas (gateway, etl, utils) que não refletem estrutura de negócio

### 5 Domínios Corporativos

#### Domain 1: PLATFORM
**Descrição**: Infraestrutura compartilhada (herda Camada 1)
**Responsabilidade**: Observabilidade, CI/CD, Secrets, Security
**Namespaces**: `shared-observability`, `staging-platform-cicd`, `prod-platform-cicd`
**Ownership**: Platform Team

#### Domain 2: INTEGRATION
**Descrição**: Domínio de Integrações - iPaaS (Integration Platform as a Service)
**Responsabilidade**: Integrações entre sistemas SaaS, orquestração de workflows
**Produtos**: iPaaS (9 microserviços: BFF REST/gRPC/SOAP, MS Core-Comm, Jobs, Notifications, Validation, Peers, Orchestrator)
**Namespaces**: `staging-integration-ipaas`, `prod-integration-ipaas`
**Ownership**: Integration Team

#### Domain 3: DATA
**Descrição**: Domínio de Dados - ETL, Data Warehouse, Analytics
**Responsabilidade**: Extração, transformação, carga de dados; catálogo; qualidade; governança
**Produtos**: Hatch ETL (151 extractors + API GraphQL + Web UI), VemSoft ETL, Data Platform (futuro)
**Namespaces**: `staging-data-hatch`, `prod-data-hatch`, `staging-data-vemsoft`, `prod-data-vemsoft`
**Ownership**: Data Team

#### Domain 4: OPERATIONS
**Descrição**: Domínio de Operações - Gestão de Processos, Execução, Fulfillment
**Responsabilidade**: Orquestração de processos de negócio, execução de tarefas, fulfillment
**Produtos**: Process Management (futuro), Fulfillment (futuro), Operational Monitoring (futuro)
**Namespaces**: `staging-operations-process`, `prod-operations-process`, `staging-operations-fulfillment`, `prod-operations-fulfillment`
**Ownership**: Operations Team

#### Domain 5: SHARED-SERVICES
**Descrição**: Serviços compartilhados universais consumidos por todos os domínios
**Responsabilidade**: Files (S3, Generators), Notification (Email/Slack/Teams), Calendar, Automation (RPA)
**Produtos**: BucketConnector, File Generators (Word/PDF/Excel/CSV), Notification Gateway, Calendar API, RPA Platform (futuro)
**Namespaces**: `staging-shared-files`, `prod-shared-files`, `staging-shared-notification`, `prod-shared-notification`
**Ownership**: Shared Services Team

### Diferenciação: Camada 1 vs Camada 2

| Aspecto | Camada 1: Domínios Técnicos | Camada 2: Domínios Corporativos |
|---------|----------------------------|----------------------------------|
| **Foco** | Infraestrutura de plataforma | Aplicações de negócio |
| **Organização** | Por função técnica | Por produto/linha de negócio |
| **Exemplos** | observability, cicd-platform | integration (iPaaS), data (Hatch) |
| **Ownership** | Platform Team | Domain Teams (Integration, Data, etc) |
| **Localização Git** | `/domains/{technical-domain}/` | `/corporate-domains/{business-domain}/` |
| **Namespaces K8s** | `shared-*`, `*-platform-*` | `{env}-{business-domain}-{product}` |
| **Consumidores** | Todas as aplicações | Usuários finais, outros domínios |
| **Mudanças** | Raras, impacto alto | Frequentes, impacto isolado |

### Naming Conventions (Determinísticas)

**Referência**: ADR-048 (Naming Conventions Determinísticas)

**GitLab**:
```
Formato: ^(domains|corporate-domains)/[a-z0-9-]+(/[a-z0-9-]+)*$
Exemplos:
  ✅ corporate-domains/integration/ipaas-bff-rest
  ✅ corporate-domains/data/hatch/hatch-etl
  ✅ corporate-domains/shared-services/files/bucketconnector
```

**Kubernetes Namespaces**:
```
Formato: ^(staging|prod|shared)-(platform|integration|data|operations|shared)(-[a-z0-9-]+)?$
Exemplos:
  ✅ staging-integration-ipaas
  ✅ prod-data-hatch
  ✅ staging-shared-files
```

**Labels Obrigatórias**:
```yaml
app.kubernetes.io/name: ^[a-z0-9-]+$
app.kubernetes.io/part-of: ^[a-z0-9-]+-[a-z0-9-]+$
domain: ^(platform|integration|data|operations|shared-services)$
owner: ^[a-z0-9-]+-team$
product: ^[a-z0-9-]+$
```

### RBAC e Governança

**Referência**: ADR-049 (Governança e RBAC para Domínios Corporativos)

**Princípio**: RBAC consistente entre GitLab ↔ Kubernetes ↔ Backstage

**GitLab RBAC**:
- Cada time tem **Maintainer** no seu domínio, **Reporter** nos demais
- Exemplo: `integration-team` tem Maintainer em `corporate-domains/integration/*`

**Kubernetes RBAC**:
- Cada time tem **namespace-admin** nos seus namespaces, **viewer** nos demais
- Exemplo: `integration-team` tem namespace-admin em `staging-integration-ipaas` e `prod-integration-ipaas`

**Enforcement**:
- Pre-push hooks (GitLab): Validam naming conventions
- Kyverno policies (Kubernetes): Validam labels obrigatórias
- CI/CD validation (Backstage): Valida catalog-info.yaml

### Interação Camada 1 ↔ Camada 2

**Exemplo: iPaaS BFF-REST** (Camada 2: Integration)

```
iPaaS BFF-REST (Application)
├─ Usa: Prometheus + Grafana (Camada 1: observability)
├─ Usa: ArgoCD para deploy (Camada 1: cicd-platform)
├─ Usa: Vault para secrets (Camada 1: secrets-management)
├─ Usa: PostgreSQL (Camada 1: data-services)
└─ Usa: Notification API (Camada 2: Shared Services)
```

**Contratos**:
- Camada 2 **CONSOME** serviços da Camada 1 (via contratos documentados)
- Camada 2 **NÃO MODIFICA** Camada 1 (ownership separado)
- Comunicação cross-domain via APIs REST, eventos, métricas (Service Mesh)

---

## 🤝 Contratos entre Domínios

### Regras Gerais
- **Sem Dependências Diretas**: Comunicação via APIs REST, métricas, eventos
- **Contratos Documentados**: Versionados no SAD
- **SLAs Definidos**: Uptime, latência, throughput
- **Testes de Contrato**: Validação obrigatória em FASE 4

### Contratos Específicos

#### platform-core ↔ Todos
- **Autenticação**: JWT/OAuth2 via Keycloak
- **Certificados**: TLS via cert-manager
- **Service Mesh**: Sidecar injection obrigatória

#### cicd-platform ↔ Todos
- **Deploy**: ArgoCD applications por domínio
- **Secrets**: Integração com secrets-management
- **Quality Gates**: SonarQube scans obrigatórios

#### observability ↔ Todos
- **Métricas**: OpenTelemetry exporters obrigatórios
- **Logs**: Loki drains padronizados
- **Traces**: Tempo spans unificados

#### data-services ↔ cicd-platform
- **Databases**: Conexões via secrets
- **Backup**: Schedules via Velero
- **Monitoring**: Exporters para Prometheus

#### secrets-management ↔ cicd-platform
- **Injection**: Secrets via external-secrets
- **Rotation**: Automática via policies
- **Audit**: Logs para compliance

#### security ↔ Todos
- **Policies**: OPA/Kyverno admission controllers
- **Scanning**: Trivy integrado ao CI
- **Runtime**: Falco alerts para observability

---

## 📏 Regras de Herança

### Padrões Obrigatórios
1. **Certificados**: Sempre via cert-manager (platform-core)
2. **Autenticação**: Sempre via Keycloak (platform-core)
3. **Service Mesh**: Sempre Linkerd/Istio (platform-core)
4. **Observabilidade**: Sempre OpenTelemetry (observability)
5. **IaC**: Sempre Terraform + Helm
6. **GitOps**: Sempre ArgoCD
7. **RBAC**: Sempre granular por ServiceAccount
8. **Network Policies**: Sempre deny-all + allow específicos
9. **Backup**: Sempre Velero schedules
10. **Tests**: Sempre testes de carga (K6/Locust)

### Exceções
- Apenas com ADR aprovado pelo Architect Guardian
- Documentadas no SAD com justificativa

---

## 📊 Métricas de Sucesso Sistêmicas

| Métrica | Target | Validação |
|---------|--------|-----------|
| Cloud-Agnostic | 100% | Sem recursos nativos |
| Isolamento Domínios | 100% | Namespaces/RBAC/Network Policies |
| Uptime SLA | 99.9% | Por domínio |
| RTO/RPO | <4h/<1h | Disaster Recovery |
| Compliance | 100% | Auditoria automática |
| Custo Otimizado | <10% waste | FinOps monitoring |
| Onboarding Tempo | <1 semana | Treinamento + Backstage |

---

## 🔒 SAD Freeze Process

### Quando Congelar
- Após criação de todos os ADRs sistêmicos
- Após validação de todas as lacunas críticas
- Após aprovação do Architect Guardian

### Como Congelar
1. Commit estruturado: `[freeze](sad): sad v1.1 - diretrizes cloud-agnostic atualizadas`
2. Tag: `sad-v1.1-freeze-2`
3. Log: Atualizar docs/logs/log-de-progresso.md
4. Comunicação: Documentar mudanças v1.0 → v1.1

### Pós-Freeze
- Mudanças apenas via novo ADR + descongelamento
- Validação obrigatória contra SAD atualizado
- Drift detection automática
- Histórico de freezes em sad-freeze-record.md

---

## 📚 Referências

### ADRs Relacionados

#### Camada 1: Domínios Técnicos
- ADR-001: Setup, Governança e Método
- **ADR-002**: Estrutura de Domínios Técnicos (v1.3 - atualizado com referência à Camada 2)
- **ADR-003**: Cloud-Agnostic e Portabilidade (v1.1 - atualizado)
- **ADR-004**: IaC e GitOps (v1.1 - atualizado)
- ADR-005: Segurança Sistêmica
- ADR-006: Observabilidade Transversal
- ADR-007: Service Mesh
- ADR-008: Escalabilidade e Performance
- ADR-013: Disaster Recovery
- ADR-014: Compliance Regulatória
- ADR-015: Multi-Tenancy
- ADR-016: Escalabilidade Vertical
- ADR-017: Integrações Externas
- ADR-018: Treinamento e Capacitação
- ADR-019: FinOps e Otimização de Custos
- ADR-020: Provisionamento de Clusters e Escopo de Domínios
- ADR-021: Escolha do Orquestrador de Containers (Kubernetes)

#### Camada 2: Domínios Corporativos (v1.3 - NOVO)
- **ADR-047**: Estrutura Corporativa de Domínios de Negócio ✨ **NOVO**
- **ADR-048**: Naming Conventions Determinísticas ✨ **NOVO**
- **ADR-049**: Governança e RBAC para Domínios Corporativos ✨ **NOVO**

### Documentos de Contexto
- [Context Generator](docs/context/context-generator.md)
- [Copilot Context](ai-contexts/copilot-context.md)
- [Execution Plan](docs/plan/execution-plan.md)
- [FASE 1 Checklist](docs/plan/fase-1-checklist.md)

---
 + CTO
**Data Criação**: 2025-12-30 (v1.0)
**Última Atualização**: 2026-01-05 (v1.1)
**Status**: 🔒 **CONGELADO** (Freeze #2
**Data**: 2025-12-30
**Status**: Rascunho → SAD FREEZE 🔒 (próximo passo)</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\sad.md