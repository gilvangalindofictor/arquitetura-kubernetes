# Software Architecture Document (SAD) - Projeto Kubernetes

> **Versão**: 1.2
> **Data de Criação**: 2025-12-30
> **Última Atualização**: 2026-01-05
> **Status**: � **CONGELADO** (Freeze #3)
> **Versão Anterior**: 1.1 (congelada 2026-01-05, descongelada para v1.2)
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
- ADR-001: Setup, Governança e Método
- ADR-002: Estrutura de Domínios
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
- **ADR-020**: Provisionamento de Clusters e Escopo de Domínios ✨ **NOVO**

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