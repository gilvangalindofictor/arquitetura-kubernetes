# 📘 Projeto Kubernetes - Contexto Consolidado

> **Última Atualização**: 2026-01-05  
> **Fase Atual**: 2 (Implementação de Domínios)  
> **Status SAD**: v1.2 🔒 CONGELADO (Freeze #3)  
> **Governança**: AI-First com rastreabilidade obrigatória  
> **Orquestrador**: Kubernetes (ADR-021)

---

## 📋 Índice
1. [Visão Geral](#visão-geral)
2. [Status dos Domínios](#status-dos-domínios)
3. [Arquitetura AI](#arquitetura-ai)
4. [Stack Tecnológica](#stack-tecnológica)
5. [Governança e Regras](#governança-e-regras)

---

## 🎯 Visão Geral

### Missão
Estabelecer uma **plataforma corporativa de engenharia robusta e escalável** usando Kubernetes como base de articulação tecnológica do departamento, fornecendo:
- Esteira CI/CD completa (primeiro objetivo)
- Observabilidade full-stack
- Serviços de dados gerenciados (HA, backup, alarmes)
- Governança via Backstage (catálogo + criação automatizada de apps)
- Segurança desde o início (service mesh, API gateway, autenticação centralizada)

### Características
- **Orquestrador: Kubernetes** (ADR-021) - Cloud-agnostic + ecossistema maduro
- **Cloud-Agnostic OBRIGATÓRIO**: Sem recursos nativos de cloud
- **Escalabilidade Multi-Domínio**: Cada domínio evolui independentemente
- **Governança Centralizada**: SAD como fonte suprema, ADRs obrigatórios
- **Rastreabilidade Total**: Hooks, logs, commits estruturados
- **Isolamento**: Namespaces, RBAC, Network Policies, Service Mesh

### Escopo
- ✅ Plataforma Corporativa Kubernetes com melhores práticas
- ✅ Esteira CI/CD: GitLab, SonarQube, Harbor, ArgoCD, Backstage
- ✅ Observabilidade: OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Kiali
- ✅ Serviços de Dados: PostgreSQL, Redis, RabbitMQ (HA, backup)
- ✅ Segurança: Kong, Keycloak, Linkerd, Vault, Kyverno, Falco, Trivy
- ✅ IaC: Terraform + Helm para tudo
- ❌ Desenvolvimento de aplicações de negócio
- ❌ Recursos nativos de clouds específicas

---

## 📊 Status dos Domínios

| Domínio | Terraform | VALIDATION | Conformidade | Deploy Priority | Status |
|---------|-----------|------------|--------------|-----------------|--------|
| **platform-core** | ✅ 550 linhas | ✅ 500 linhas | 88.6% | #1 Fundação | ✅ APROVADO |
| **secrets-management** | ⏳ ADR-002 | ⏳ Pendente | N/A | #2 Crítico | ⚠️ BLOQUEADO |
| **observability** | ✅ Refatorado | ✅ 3 validações | 91.2% | #3 Medium | ✅ APROVADO |
| **cicd-platform** | ✅ 650 linhas | ✅ 700 linhas | 86.4% | #4 Objetivo #1 | ✅ APROVADO |
| **data-services** | ✅ 450 linhas | ✅ 350 linhas | 92.3% | #5 Medium | ✅ APROVADO |
| **security** | ⏳ ADR-002 | ⏳ Pendente | N/A | #6 Medium | ⚠️ BLOQUEADO |
| **MÉDIA (implementados)** | - | - | **89.6%** | - | - |

### Decisões Pendentes
1. **secrets-management**: Vault vs External Secrets Operator (Recomendação: Vault - ADR-003 alignment)
2. **security**: Kyverno vs OPA Gatekeeper (Recomendação: Kyverno - simplicidade)

### Conformidade por ADR (Domínios Implementados)

| ADR | Título | Conformidade Média |
|-----|--------|-------------------|
| ADR-003 | Cloud-Agnostic | 100% ✅ |
| ADR-004 | IaC/GitOps | 100% ✅ |
| ADR-005 | Segurança | 73.3% ⚠️ |
| ADR-006 | Observabilidade | 96.7% ✅ |
| ADR-020 | Platform Provisioning | 100% ✅ |
| ADR-021 | Kubernetes | 96.7% ✅ |
| **MÉDIA** | | **94.4%** |

**Nota**: Gap comum ADR-005 (RBAC granular, Network Policies) é não-bloqueante, roadmap Sprint+1.

---

## 🤖 Arquitetura AI

### Camadas de Governança

```
┌─────────────────────────────────────────────┐
│            USUÁRIO (Você)                   │
│                 ↓↑                          │
└─────────────────────────────────────────────┘
                  ↓↑
┌─────────────────────────────────────────────┐
│       ORCHESTRATOR GUIDE (Maestro)          │
│  - Conduz fases incrementais                │
│  - Exige confirmações explícitas            │
└─────────────────────────────────────────────┘
                  ↓↑
┌─────────────────────────────────────────────┐
│   ARCHITECT GUARDIAN (Validador SAD)        │
│  - Valida contra SAD v1.2                   │
│  - Bloqueia violações                       │
│  - Autoridade arquitetural máxima           │
└─────────────────────────────────────────────┘
                  ↓↑
┌─────────────────────────────────────────────┐
│          CAMADA DE AGENTES                  │
│  Arquiteto | Desenvolvedor | Gestor         │
│  Revisor | Executor-MCP | Facilitador       │
└─────────────────────────────────────────────┘
                  ↓↑
┌─────────────────────────────────────────────┐
│       CAMADA DE CONTEXTO                    │
│  SAD v1.2 | ADRs | Domain Contracts         │
│  Context Generator | Logs                   │
└─────────────────────────────────────────────┘
```

### Ferramentas Disponíveis
- **MCP Tools**: Docker, GitHub, filesystem
- **Skills**: Arquitetura, código, brainstorm, requisitos, testes
- **Prompts**: Orchestrator, develop-feature, bugfix, refactoring, domain-creation, automatic-audit
- **Hooks**: Pre-commit validation, SAD compliance check

---

## 🏗️ Stack Tecnológica

### platform-core (Fundação)
- **Kong** 2.35.0 - API Gateway (2 réplicas, PostgreSQL)
- **Keycloak** 18.4.0 - Authentication OIDC (2 réplicas, PostgreSQL)
- **Linkerd** 1.16.11 - Service Mesh mTLS (HA control plane)
- **cert-manager** 1.13.3 - TLS Certificates (Let's Encrypt HTTP-01)
- **NGINX Ingress** 4.9.0 - Ingress Controller (2 réplicas, LoadBalancer)

**Contratos Providos**: Authentication (99.95% SLA), Gateway (99.9%), Service Mesh (99.9%), Certificates (99.9%), Ingress (99.9%)

### cicd-platform (Esteira DevOps)
- **GitLab CE** 7.7.0 - Git + CI (2 réplicas webservice, PostgreSQL, Redis, Minio S3)
- **SonarQube** 10.3.0 - Code Quality (PostgreSQL, 20Gi storage)
- **Harbor** 1.14.0 - Registry (100Gi, Trivy scanning, Chartmuseum)
- **ArgoCD** 5.51.6 - GitOps (2 réplicas, Keycloak OIDC)
- **Backstage** 1.7.0 - Developer Portal (GitLab integration, Software Templates)

**Contratos Providos**: Git Repository (99.5% SLA), CI (10 concurrent runners), Registry (100Gi), GitOps (99.9%), Developer Catalog

### observability (Monitoramento)
- **OpenTelemetry Collector** - Traces + Metrics + Logs unificados
- **Prometheus** - Time-series metrics storage
- **Grafana** - Visualização + Dashboards
- **Loki** - Log aggregation
- **Tempo** - Distributed tracing
- **Kiali** - Service Mesh observability

**Contratos Providos**: Metrics Storage (99.9% SLA), Visualization, Log Aggregation, Trace Storage

### data-services (Operators)
- **Zalando Postgres Operator** 1.10.1 - PostgreSQL HA (Patroni + Spilo)
- **Redis Cluster Operator** 0.15.1 - Redis HA (cluster mode)
- **RabbitMQ Cluster Operator** 3.12.0 - RabbitMQ HA (quorum queues)
- **Velero** 5.2.0 - Kubernetes Backup/Restore (S3-compatible)

**Contratos Providos**: PostgreSQL as a Service (99.9% SLA), Redis as a Service, RabbitMQ as a Service, Backup/Restore (RPO 24h, RTO <1h)

### secrets-management (Pendente ADR-002)
- **Opção 1**: HashiCorp Vault (cloud-agnostic, dynamic secrets, PKI) ✅ Recomendado
- **Opção 2**: External Secrets Operator (simplicidade, cloud KMS dependency)

**Contratos Providos**: Secrets Injection, Dynamic Secrets, PKI/TLS

### security (Pendente ADR-002)
- **Opção 1**: Kyverno (YAML policies, validation/mutation/generation) ✅ Recomendado
- **Opção 2**: OPA Gatekeeper (Rego, flexibilidade)
- **Falco** - Runtime security monitoring
- **Trivy Operator** - Vulnerability scanning
- **Network Policies** - L3/L4 firewall rules

**Contratos Providos**: Policy Enforcement, Runtime Security, Vulnerability Scanning, Network Segmentation

---

## 📐 Governança e Regras

### SAD (System Architecture Document)
- **Versão Atual**: v1.2 🔒 CONGELADO (Freeze #3)
- **ADRs Sistêmicos**: 13 decisões arquiteturais fundamentais
- **Localização**: `/SAD/docs/sad.md` + `/SAD/docs/adrs/`
- **Autoridade**: Architect Guardian valida contra SAD

### ADRs Sistêmicos Implementados
- **ADR-003**: Cloud-Agnostic (100% conformidade)
- **ADR-004**: IaC/GitOps (Terraform + Helm + ArgoCD)
- **ADR-005**: Segurança Sistêmica (Linkerd mTLS, RBAC, Network Policies)
- **ADR-006**: Observabilidade Transversal (ServiceMonitors obrigatórios)
- **ADR-007**: Service Mesh (Linkerd escolhido)
- **ADR-020**: Platform Provisioning (separação cloud vs workloads)
- **ADR-021**: Kubernetes as Platform

### Regras Permanentes
1. **Nunca extrapolar escopo sem aprovação explícita**
2. **Consultar ADRs antes de mudanças arquiteturais**
3. **Nunca agir sem contexto (validar com SAD e domain docs)**
4. **Decisões exigem rastreabilidade**: Commits estruturados + ADRs + logs
5. **Isolamento por domínio**: Independência com padrões centralizados
6. **Cloud-agnostic obrigatório**: Zero recursos nativos de clouds (AWS/Azure/GCP)
7. **IaC completo**: Nenhuma configuração manual em produção
8. **ServiceMonitors habilitados**: Observabilidade em todos os componentes
9. **Linkerd injection**: `linkerd.io/inject=enabled` em todos os workloads

### Estrutura do Projeto

```
Kubernetes/
├── platform-provisioning/        # Cloud-specific (clusters, VPCs, IAM)
│   ├── aws/
│   ├── azure/
│   └── gcp/
│
├── domains/                      # Cloud-agnostic (workloads)
│   ├── platform-core/
│   ├── cicd-platform/
│   ├── observability/
│   ├── data-services/
│   ├── secrets-management/
│   └── security/
│
├── SAD/                          # Governança centralizada
│   └── docs/
│       ├── sad.md                # SAD v1.2 congelado
│       ├── adrs/                 # 13 ADRs sistêmicos
│       └── architecture/         # Contratos e herança
│
├── docs/                         # Documentação técnica
│   ├── agents/                   # 7 agentes AI
│   ├── prompts/                  # 6 prompts principais
│   ├── skills/                   # 5 skills técnicas
│   ├── plan/                     # Plano de execução
│   └── logs/                     # Log de progresso
│
└── PROJECT-CONTEXT.md            # Este arquivo (contexto consolidado)
```

### Gaps Conhecidos (Sprint+1 Roadmap)
1. **RBAC Granular**: ServiceAccounts com least-privilege (4 domínios)
2. **Network Policies**: Implementar para 6 domínios (L3/L4 firewall)
3. **Velero Credentials**: Migrar de Kubernetes Secrets para Vault
4. **HPA/VPA**: Após 2 semanas de métricas (observar padrões)
5. **GitLab OIDC**: Integração com Keycloak (ArgoCD já implementado)

---

## 🚀 Próximos Passos

### Sprint Atual (85% Completo)
- [x] Terraform cloud-agnostic para platform-core, cicd-platform, data-services
- [x] VALIDATION-REPORTs completos (89.6% conformidade média)
- [ ] ADR-002 secrets-management (Vault vs ESO)
- [ ] ADR-002 security (Kyverno vs OPA)

### Sprint+1
**Semana 1-2**: Secrets Management
- [ ] Criar ADR-002 Vault architecture
- [ ] Terraform Vault cluster HA (3 réplicas, Consul backend, auto-unsealing)
- [ ] VALIDATION-REPORT secrets-management
- [ ] Deploy e integração com platform-core

**Semana 3-4**: Security
- [ ] Criar ADR-002 Kyverno policies
- [ ] Terraform Kyverno, Falco, Trivy Operator
- [ ] Implementar Network Policies (6 domínios)
- [ ] VALIDATION-REPORT security

**Remediação de Gaps**: RBAC, Network Policies, Velero credentials, HPA/VPA

### Deploy Order (Sprint+2)
```
1. platform-core (#1)
   ↓
2. secrets-management (#2)
   ↓
3. observability (#3)
   ↓
4. cicd-platform (#4)
   ↓
5. data-services (#5)
   ↓
6. security (#6)
```

---

## 📈 Métricas de Qualidade

### Arquivos Criados (Session 2026-01-05)
- **Total**: 24 arquivos
- **Terraform**: ~1,650 linhas (3 domínios)
- **VALIDATION-REPORTs**: ~1,550 linhas
- **Documentação**: 12 docs (READMEs, ADRs, logs)

### Cobertura
- **Domínios Implementados**: 4/6 (67%) - observability, platform-core, cicd-platform, data-services
- **Conformidade SAD v1.2**: 89.6% média
- **Gaps Bloqueantes**: 0
- **Gaps Não-Bloqueantes**: 6 (RBAC, Network Policies, HPA/VPA, Velero credentials, GitLab OIDC)

---

## 📚 Referências Rápidas

### Documentos Principais
- **SAD v1.2**: [/SAD/docs/sad.md](SAD/docs/sad.md)
- **ADRs Sistêmicos**: [/SAD/docs/adrs/](SAD/docs/adrs/)
- **Contratos de Domínio**: [/SAD/docs/architecture/domain-contracts.md](SAD/docs/architecture/domain-contracts.md)
- **Implementação Terraform**: [TERRAFORM-IMPLEMENTATION-REPORT.md](TERRAFORM-IMPLEMENTATION-REPORT.md)
- **Log de Progresso**: [/docs/logs/log-de-progresso.md](docs/logs/log-de-progresso.md)

### Agentes AI
- **Orchestrator Guide**: [/docs/prompts/orchestrator-guide.md](docs/prompts/orchestrator-guide.md)
- **Architect Guardian**: [/docs/agents/architect-guardian.md](docs/agents/architect-guardian.md)
- **Desenvolvedor**: [/docs/agents/desenvolvedor.md](docs/agents/desenvolvedor.md)
- **Arquiteto**: [/docs/agents/arquiteto.md](docs/agents/arquiteto.md)

### VALIDATION-REPORTs
- **platform-core**: [/domains/platform-core/docs/VALIDATION-REPORT.md](domains/platform-core/docs/VALIDATION-REPORT.md) (88.6%)
- **cicd-platform**: [/domains/cicd-platform/docs/VALIDATION-REPORT.md](domains/cicd-platform/docs/VALIDATION-REPORT.md) (86.4%)
- **data-services**: [/domains/data-services/docs/VALIDATION-REPORT.md](domains/data-services/docs/VALIDATION-REPORT.md) (92.3%)
- **observability**: [/domains/observability/docs/VALIDATION-REPORT.md](domains/observability/docs/VALIDATION-REPORT.md) (91.2%)

---

**Autor**: System Architect  
**Última Atualização**: 2026-01-05  
**Versão**: 1.0 (Consolidado)  
**Status**: ✅ ATIVO
