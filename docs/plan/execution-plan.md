# Plano de Execução - Projeto Kubernetes

> **Última Atualização**: 2026-01-22
> **SAD**: v1.2 🔒 CONGELADO (Freeze #3 - 2026-01-05)

## Fases Concluídas

- ✅ **Fase 0**: Setup do Sistema (2025-12-30)
- ✅ **Fase 1**: Concepção do SAD (2026-01-05 - SAD v1.2 congelado)

## Fase Atual

- 🔄 **Fase 2**: Criação dos Domínios (Em Progresso)

## Objetivo Principal
Estabelecer uma **plataforma corporativa de engenharia robusta e escalável** usando Kubernetes como base de articulação tecnológica do departamento, fornecendo:
1. **Esteira CI/CD completa** (GitLab + SonarQube + ArgoCD + Backstage) — **Primeiro Objetivo**
2. **Observabilidade full-stack** (OpenTelemetry → Prometheus/Loki/Tempo → Grafana/Kiali)
3. **Serviços de dados gerenciados** (PostgreSQL, Redis, RabbitMQ com HA, backup, alarmes)
4. **Governança via Backstage** (catálogo + criação automatizada de aplicações)
5. **Segurança corporativa** (Kong, Keycloak, Service Mesh, Vault, OPA/Kyverno, Falco)

---

## FASE 0 — SETUP DO SISTEMA ✅ (Concluída)

### Realizações
- [x] Estrutura `/docs` criada (context, adr, plan, skills, agents, mcp, logs, prompts)
- [x] Estrutura `/SAD/docs` criada (context, adrs, architecture)
- [x] Estrutura `/domains` criada
- [x] Context Generator criado
- [x] ADR-001 (Setup e Governança) criado
- [x] ADR-002 (Estrutura de Domínios) criado
- [x] Orchestrator Guide adaptado para Kubernetes
- [x] Prompts especializados criados (develop-feature, bugfix, refactoring, domain-creation, automatic-audit)
- [x] Agentes copiados de Observabilidade
- [x] Skills copiados de Observabilidade
- [x] MCP tools copiado
- [x] Domínio Observability integrado (migrado do projeto Observabilidade)
- [x] Copilot Context criado

---

## FASE 1 — CONCEPÇÃO DO SAD ✅ (Concluída em 2026-01-05)

### Objetivo
Criar o **SAD (Software Architecture Document)** com todas as decisões arquiteturais sistêmicas que regerão os domínios.

### Tasks

#### 1.1 Criar SAD.md ✅

- [x] Definir visão arquitetural sistêmica
- [x] Decisões sobre cloud-agnostic (Kubernetes como base)
- [x] Estratégia de IaC (Terraform + Helm)
- [x] Modelo de namespaces e isolamento
- [x] Estratégia de segurança (RBAC, Network Policies, secrets)
- [x] Estratégia de observabilidade transversal
- [x] Estratégia de CI/CD (GitOps)

#### 1.2 Criar ADRs Sistêmicos ✅

- [x] ADR-003: Cloud-Agnostic OBRIGATÓRIO (sem recursos nativos de cloud)
- [x] ADR-004: Infraestrutura como Código (Terraform cloud-agnostic + Helm)
- [x] ADR-005: Estratégia de Segurança Base (RBAC, Network Policies, Pod Security Standards)
- [x] ADR-006: Observabilidade Transversal (OpenTelemetry como padrão)
- [x] ADR-007: Service Mesh (Istio vs Linkerd com sidecar isolation)
- [x] ADR-008: Escalabilidade e Performance
- [x] ADR-009: Disaster Recovery
- [x] ADR-010: Compliance Regulatória
- [x] ADR-011: FinOps e Custo
- [x] ADR-012: Isolamento de Ambientes (dev/hml/prd via namespaces + RBAC)
- [x] ADR-013: Contratos entre Domínios
- [x] ADR-020: Provisionamento de Clusters Kubernetes
- [x] ADR-021: Escolha do Orquestrador (Kubernetes)

#### 1.3 Definir Regras de Herança ✅

- [x] Criar `/SAD/docs/architecture/inheritance-rules.md`
- [x] Documentar o que domínios DEVEM herdar do SAD
- [x] Documentar o que domínios PODEM customizar

#### 1.4 Definir Contratos Entre Domínios ✅

- [x] Criar `/SAD/docs/architecture/domain-contracts.md`
- [x] Documentar interfaces permitidas entre domínios
- [x] Exemplos: Observability pode monitorar Networking via métricas Prometheus

#### 1.5 SAD FREEZE ✅

- [x] Revisão completa do SAD
- [x] Validação com Architect Guardian
- [x] Aprovação explícita do usuário
- [x] Criar `/SAD/docs/sad-freeze-record.md`
- [x] **Freeze #1**: SAD v1.0 (2025-12-30)
- [x] **Freeze #2**: SAD v1.1 (2026-01-05) - ADR-020
- [x] **Freeze #3**: SAD v1.2 (2026-01-05) - ADR-021

**Critério de Conclusão**: ✅ SAD v1.2 congelado e aprovado.

---

## FASE 2 — CRIAÇÃO DOS DOMÍNIOS (Em Progresso)

### Objetivo
Estruturar todos os 6 domínios da plataforma seguindo padrões do SAD.

### Pré-Requisito
**⚠️ Antes de deployar domínios, é necessário provisionar cluster:**

#### 0. Provisionamento do Cluster (Novo)
- [x] Criar estrutura `/platform-provisioning/azure/` (2026-01-05)
- [ ] Implementar Terraform para AKS (azurerm provider)
- [ ] Implementar VNet + Subnets
- [ ] Implementar storage classes e Blob Storage
- [ ] Documentar outputs para domínios
- [ ] Provisionar cluster de desenvolvimento
- [ ] Validar conectividade e outputs

**Referências**:
- [Platform Provisioning README](../../platform-provisioning/README.md)
- [Azure README](../../platform-provisioning/azure/README.md)
- [ADR-020: Provisionamento de Clusters](../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)

### Tasks

#### 2.1 Validar Domínio Observability ✅ (Concluída - 2026-01-05)

- [x] Domínio já migrado do projeto Observabilidade
- [x] Verificar aderência completa ao SAD (FASE 1)
- [x] Atualizar contexto se necessário
- [x] Documentar contratos com outros domínios
- [x] Validação #1 contra SAD v1.0
- [x] Validação #2 contra SAD v1.1
- [x] Validação #3 contra SAD v1.2 + ADR-021
- [x] Consolidação e remoção de artefatos desnecessários

**Resultado**:
- ✅ Stack técnico conforme (OpenTelemetry, Prometheus, Grafana, Loki, Tempo)
- ✅ Contratos entre domínios alinhados com SAD
- ✅ Terraform refatorado para cloud-agnostic (ADR-006)
- ✅ **Status**: APROVADO - Conformidade Total com SAD v1.2

**Artefatos**:
- [`/domains/observability/docs/adr/adr-003-validacao-sad.md`](../../domains/observability/docs/adr/adr-003-validacao-sad.md)
- [`/domains/observability/docs/adr/adr-004-revalidacao-sad-v11.md`](../../domains/observability/docs/adr/adr-004-revalidacao-sad-v11.md)
- [`/domains/observability/docs/adr/adr-005-revalidacao-sad-v12.md`](../../domains/observability/docs/adr/adr-005-revalidacao-sad-v12.md)
- [`/domains/observability/docs/adr/adr-006-refatoracao-terraform-cloud-agnostic.md`](../../domains/observability/docs/adr/adr-006-refatoracao-terraform-cloud-agnostic.md)
- [`/domains/observability/docs/VALIDATION-REPORT.md`](../../domains/observability/docs/VALIDATION-REPORT.md)

#### 2.2 Criar Domínio platform-core ✅ (Concluída - 2026-01-05)

- [x] Criar estrutura base em `/domains/platform-core`
- [x] Criar contexto do domínio (Kong, Keycloak, Service Mesh, cert-manager)
- [x] Criar plano de execução
- [x] Criar ADR de criação (ADR-001: Estrutura Inicial)
- [x] Documentar integrações: auth com cicd-platform, service mesh com todos

#### 2.3 Criar Domínio cicd-platform ✅ (Concluída - 2026-01-05) 🎯

- [x] Criar estrutura base em `/domains/cicd-platform`
- [x] Criar contexto do domínio (GitLab, SonarQube, ArgoCD, Backstage)
- [x] Criar plano de execução
- [x] Criar ADR de criação (ADR-001: Estrutura Inicial)
- [x] Documentar workflow: Backstage → GitLab → SonarQube → ArgoCD → K8s
- [x] Documentar integração com secrets-management (injeção de credenciais)

#### 2.4 Criar Domínio data-services ✅ (Concluída - 2026-01-05)

- [x] Criar estrutura base em `/domains/data-services`
- [x] Criar contexto do domínio (PostgreSQL, Redis, RabbitMQ, Velero)
- [x] Criar plano de execução
- [x] Criar ADR de criação (ADR-001: Estrutura Inicial)
- [x] Documentar estratégia HA + backup + alarmes
- [x] Documentar exportadores de métricas para observability

#### 2.5 Criar Domínio secrets-management ✅ (Concluída - 2026-01-05)

- [x] Criar estrutura base em `/domains/secrets-management`
- [x] Criar contexto do domínio (Vault ou External Secrets Operator)
- [x] Criar plano de execução
- [x] Criar ADR de criação (ADR-001: Estrutura Inicial)
- [x] Documentar integração com cicd-platform (injeção automática)
- [x] Documentar estratégia de rotação e auditoria
- [ ] **Pendência**: ADR-002 - Mesa técnica sobre secrets na imagem vs external

#### 2.6 Criar Domínio security ✅ (Concluída - 2026-01-05)

- [x] Criar estrutura base em `/domains/security`
- [x] Criar contexto do domínio (OPA/Kyverno, Falco, Trivy, RBAC, Network Policies)
- [x] Criar plano de execução
- [x] Criar ADR de criação (ADR-001: Estrutura Inicial)
- [x] Documentar policies obrigatórias
- [x] Documentar integração Trivy com cicd-platform
- [x] Documentar runtime monitoring com Falco
- [ ] **Pendência**: ADR-002 - Escolha Kyverno vs OPA

**Critério de Conclusão**: ✅ Todos os 6 domínios estruturados com documentação básica (2026-01-05)

**Status Fase 2**: 🔄 **Em Progresso** - Estruturação completa, aguardando provisionamento de cluster para implementação

---

## FASE 3 — EXECUÇÃO POR DOMÍNIO

### Objetivo
Evolução isolada de cada domínio com governança pelo SAD.

### Tasks (Por Domínio)

#### 3.1 Domínio platform-core (Fundação)
- [ ] Implementar Kong (API Gateway) via Terraform + Helm
- [ ] Implementar Keycloak (autenticação centralizada) via Operator
- [ ] Decidir e implementar Service Mesh (Istio vs Linkerd)
- [ ] Configurar cert-manager para certificados TLS automatizados
- [ ] Deploy NGINX Ingress Controller
- [ ] Testes de autenticação e roteamento
- [ ] Runbooks operacionais
- [ ] Deploy em hml/prd

#### 3.2 Domínio cicd-platform (🎯 Primeiro Objetivo - Esteira CI/CD)
- [ ] Deploy GitLab self-hosted via Helm
- [ ] Configurar GitLab CI com runners Kubernetes
- [ ] Deploy SonarQube via Helm
- [ ] Integrar SonarQube com GitLab CI
- [ ] Deploy ArgoCD via Helm
- [ ] Deploy Backstage Spotify via Helm
- [ ] Configurar Backstage: catálogo + templates + integração GitLab
  - [ ] Criar templates Backstage para stack polyglot (Go, .NET, Python, Node.js)
- [ ] Testar pipeline end-to-end: Backstage → GitLab → SonarQube → ArgoCD → K8s
- [ ] Integrar com secrets-management (injeção automática)
- [ ] Runbooks operacionais
- [ ] Deploy em hml/prd
- **Resultado Esperado**: Pipeline CI/CD funcionando end-to-end para stack polyglot (Go, .NET, Python, Node.js)
- [ ] Implementar OpenTelemetry Collector como coletor central
- [ ] Deploy Prometheus + Alertmanager via Operator
- [ ] Deploy Grafana via Helm
- [ ] Deploy Loki via Helm (logs)
- [ ] Deploy Tempo via Helm (traces)
- [ ] Deploy Kiali via Helm (service mesh observability)
- [ ] Configurar dashboards Grafana (golden signals)
- [ ] Integrar com todos os domínios (exportadores, collectors)
- [ ] Configurar alarmística (Alertmanager)
- [ ] Testes de coleta de métricas/logs/traces
- [ ] Runbooks operacionais
- [ ] Deploy em hml/prd

#### 3.4 Domínio data-services (DBaaS, CacheaaS, MQaaS)
- [ ] Implementar PostgreSQL via Operator (Zalando, CrunchyData, CloudNativePG)
- [ ] Configurar PostgreSQL HA (replicação)
- [ ] Implementar Redis via Operator (Redis Operator)
- [ ] Configurar Redis cluster mode
- [ ] Implementar RabbitMQ via Operator (RabbitMQ Cluster Operator)
- [ ] Configurar RabbitMQ HA
- [ ] Deploy Velero para backup automatizado
- [ ] Configurar exportadores Prometheus para todos os databases
- [ ] Integrar com observability (métricas + logs)
- [ ] Configurar Alertmanager para alarmística
- [ ] Testes de HA, backup e restore
- [ ] Runbooks operacionais
- [ ] Deploy em hml/prd

#### 3.5 Domínio secrets-management (Cofre de Senhas)
- [ ] **Mesa Técnica**: Avaliar secrets na imagem vs external
- [ ] Decidir: HashiCorp Vault vs External Secrets Operator
- [ ] Deploy solução escolhida via Helm
- [ ] Configurar integração com cicd-platform (injeção automática)
- [ ] Configurar rotação automática de credenciais
- [ ] Configurar auditoria de acessos
- [ ] Testes de injeção em pipelines
- [ ] Runbooks operacionais
- [ ] Deploy em hml/prd

#### 3.6 Domínio security (Segurança e Compliance)
- [ ] Decidir: OPA vs Kyverno
- [ ] Deploy policy engine escolhido
- [ ] Implementar policies obrigatórias (RBAC, Network Policies, Pod Security)
- [ ] Deploy Falco para runtime security
- [ ] Integrar Trivy com cicd-platform (scan em pipelines)
- [ ] Configurar RBAC centralizado por namespace
- [ ] Implementar Network Policies rigorosas
- [ ] Implementar Pod Security Standards
- [ ] Testes de compliance
- [ ] Runbooks operacionais
- [ ] Deploy em hml/prd

**Critério de Conclusão**: Todos os 6 domínios operacionais em produção.

---

## FASE 4 — INTEGRAÇÃO E VALIDAÇÃO

### Objetivo
Validar integração entre domínios e operação completa.

### Tasks
- [ ] Testes de integração multi-domínio
- [ ] Validação de contratos entre domínios
- [ ] Testes de carga e performance
- [ ] Validação de segurança end-to-end
- [ ] Auditoria automática (via `automatic-audit.md`)
- [ ] Revisão de custos (FinOps)

**Critério de Conclusão**: Sistema integrado e validado.

---

## FASE 5 — DOCUMENTAÇÃO E HANDOVER

### Objetivo
Finalizar documentação e preparar para operação.

### Tasks
- [ ] Runbooks completos para todos os domínios
- [ ] Documentação de troubleshooting
- [ ] Guias de onboarding
- [ ] Disaster recovery procedures
- [ ] Treinamento de equipes
- [ ] Handover para operação

**Critério de Conclusão**: Documentação completa e equipe treinada.

---

## Dependências

- Conta AWS/GCP/Azure com permissões adequadas (ou cluster on-prem)
- Kubernetes cluster disponível (EKS/GKE/AKS/Kind/Minikube)
- Terraform instalado (ou via Docker)
- Helm instalado (ou via Docker)
- kubectl instalado (ou via Docker)

---

## Critérios de Sucesso Globais

- ✅ Estrutura base criada (FASE 0)
- ⏳ SAD congelado com decisões sistêmicas (FASE 1)
- ⏳ 6 domínios estruturados e documentados (FASE 2)
- ⏳ Pipeline Python CI/CD end-to-end funcionando via Backstage → GitLab → SonarQube → ArgoCD (FASE 3.2)
- ⏳ OpenTelemetry coletando métricas/logs/traces de todos os domínios (FASE 3.3)
- ⏳ PostgreSQL, Redis, RabbitMQ operacionais com HA e backup (FASE 3.4)
- ⏳ Cofre de secrets integrado com CI/CD (FASE 3.5)
- ⏳ Policies OPA/Kyverno validando deploys em todos os domínios (FASE 3.6)
- ⏳ Sistema integrado validado (FASE 4)
- ⏳ Documentação completa e equipe treinada (FASE 5)

---

## Princípios Arquiteturais Obrigatórios

### 1. Cloud-Agnostic OBRIGATÓRIO
- ❌ Sem usar recursos nativos de cloud (AWS RDS, GCP Cloud SQL, Azure Cosmos, etc.)
- ✅ 100% Kubernetes nativo (operadores para PostgreSQL, Redis, RabbitMQ)
- ✅ Migrável entre qualquer cloud (AWS, GCP, Azure) ou on-premises

### 2. Escalabilidade Desde o Início
- Arquitetura preparada para crescimento
- Mesmo usando pouco inicialmente, estrutura é corporativa
- Service mesh, API Gateway, autenticação centralizada desde D0

### 3. Melhores Práticas Obrigatórias
- Service Mesh com sidecar (isolamento entre namespaces)
- API Gateway (Kong) como ponto de entrada
- Autenticação centralizada (Keycloak)
- Secrets management (Vault) integrado com CI/CD
- Observabilidade (OpenTelemetry) em todos os domínios
- Backup automatizado (Velero) para stateful workloads
- Policies (OPA/Kyverno) validando todos os deploys
- Runtime security (Falco) monitorando todos os namespaces

### 4. Governança AI-First Mantida
- SAD como fonte suprema
- ADRs obrigatórios para decisões sistêmicas
- Hooks pre/post para validações
- Architect Guardian validando arquitetura
- Rastreabilidade total (commits, logs, ADRs)
- ⏳ Todos os domínios estruturados (FASE 2)
- ⏳ Domínio Observability operacional (FASE 3)
- ⏳ Pelo menos 2 domínios adicionais operacionais (FASE 3)
- ⏳ Integração validada (FASE 4)
- ⏳ Documentação completa (FASE 5)

---

## Riscos Identificados

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| Complexidade multi-domínio | Alto | Isolamento claro, documentação extensiva, Architect Guardian |
| Custo de múltiplos domínios | Médio | FinOps desde o início, monitoramento de custos |
| Curva de aprendizado | Médio | Documentação extensiva, runbooks, treinamento |
| Drift arquitetural | Alto | Auditoria automática frequente, Architect Guardian |
| Acoplamento não autorizado entre domínios | Alto | Validação de contratos, code review rigoroso |

---

## Políticas Anti-Alucinação

- Consultar `/docs/context/context-generator.md` antes de qualquer ação
- Verificar ADR mais recente antes de mudanças arquiteturais
- Executar mudanças apenas dentro do escopo autorizado
- Em caso de dúvida técnica ou conflito, acionar Gestor ou Architect Guardian
- Sempre validar contra SAD congelado

---

## Histórico de Atualizações

- **2026-01-22**: Atualização pós-validação - Fase 1 marcada como concluída, Fase 2 em progresso
- **2026-01-05**: Fase 1 concluída (SAD v1.2 congelado), Fase 2 iniciada (6 domínios estruturados)
- **2025-12-30**: Fase 0 concluída (Setup do Sistema)
