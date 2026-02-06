# project_brief.md

> **Responsabilidade**: Usuário (AI nunca modifica automaticamente)
> **Quando atualizar**: Quando requisitos/objetivos mudam
> **Prioridade de leitura**: 1 (sempre ler primeiro)

---

## Visão Geral

**Nome do Projeto**: Plataforma Kubernetes Corporativa

**Objetivo Principal**: Estabelecer uma plataforma corporativa de engenharia robusta e escalável usando Kubernetes como base de articulação tecnológica do departamento, fornecendo esteira CI/CD completa, observabilidade full-stack, serviços de dados gerenciados (HA, backup, alarmes), governança via Backstage, e segurança desde o início.

**Estado Atual**: Desenvolvimento ativo - Marco 3 em andamento (67% completo)

---

## Contexto de Negócio

**Problema que Resolve**:
Atualmente a organização não possui uma plataforma centralizada para desenvolvimento, deployment e operação de aplicações. Times trabalham de forma descentralizada, sem padrões, observabilidade unificada, ou governança clara. Este projeto estabelece essa plataforma base.

**Stakeholders**:
- CTO: Visão estratégica e aprovações arquiteturais
- Arquiteto: Decisões técnicas e design da plataforma
- Equipe DevOps: Implementação e operação
- Desenvolvedores: Usuários finais da plataforma

**Restrições/Constraints**:
- **Prazo**: Marco 0-3 em 8 semanas (MVP)
- **Orçamento**: ~$700/mês para ambiente staging
- **Técnicas**:
  - Kubernetes obrigatório como orquestrador (ADR-021)
  - Cloud-agnostic obrigatório (sem recursos nativos de cloud provider)
  - Infrastructure as Code (Terraform + Helm)
  - Governança via SAD (System Architecture Document) congelado v1.2
- **Regulatórias**: Rastreabilidade total (hooks, logs, commits estruturados)

---

## Escopo

### In Scope (O que SERÁ feito)
- [x] Backend Terraform (S3 + DynamoDB) para state remoto
- [x] Cluster EKS operacional (7 nodes, 4 add-ons)
- [x] Platform Services (8 fases): observability stack, security, networking
- [x] Workloads: GitLab, Harbor, Keycloak, Vault, PostgreSQL, Redis, RabbitMQ
- [ ] Esteira CI/CD completa (GitLab, SonarQube, ArgoCD, Backstage)
- [ ] Observabilidade full-stack (OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Kiali)
- [ ] Serviços de dados com HA e backup
- [ ] Segurança: Kong, Service Mesh (Linkerd), Kyverno, Falco, Trivy
- [ ] Governança via Backstage (catálogo + templates)

### Out of Scope (O que NÃO será feito, pelo menos agora)
- Desenvolvimento de aplicações de negócio (plataforma é para times usarem)
- Migração de aplicações existentes (primeiro estabelecer plataforma)
- Multi-cloud deployment simultâneo (MVP é AWS-only, mas mantendo cloud-agnostic design)
- Implementação dos 6 domínios isolados (visão futura, 12-18 meses pós-MVP)

---

## Requisitos Não-Funcionais

**Performance**:
- API Gateway deve responder em < 200ms p95
- GitLab pipeline start em < 30s
- Prometheus scrape interval: 15s

**Disponibilidade**:
- SLA target: 99.5% (staging), 99.9% (produção futura)
- RTO: < 1h
- RPO: < 15min (backups automáticos)

**Segurança**:
- Autenticação centralizada via Keycloak (OAuth 2.0 / OIDC)
- Secrets via Vault + External Secrets Operator
- Network Policies obrigatórias
- Service Mesh mTLS entre serviços
- RBAC granular por namespace
- Zero secrets hardcoded no código

**Escalabilidade**:
- Horizontal: HPA para workloads stateless
- Cluster Autoscaler habilitado
- Vertical: VPA considerado para otimização

**Observabilidade**:
- Logs agregados no Loki
- Métricas no Prometheus
- Traces no Tempo
- Dashboards Grafana para todos os componentes
- Alertmanager para alertas críticos

---

## Marcos e Entregas

| Marco              | Descrição                                                 | Data Alvo | Status            |
| ------------------ | --------------------------------------------------------- | --------- | ----------------- |
| Marco 0            | Backend Terraform (S3 + DynamoDB)                         | ✅ 2 dias  | ✅ Completo        |
| Marco 1            | Cluster EKS (7 nodes, 4 add-ons)                          | ✅ 1 dia   | ✅ Completo        |
| Marco 2            | Platform Services (8 fases)                               | ✅ 3 dias  | ✅ Completo        |
| Marco 3 Fase 1a/1b | PostgreSQL, Redis, RabbitMQ, GitLab, Vault, ESO, Harbor   | ✅ 5 dias  | ✅ Completo        |
| Marco 3 Fase 1c    | PostgreSQL SG Fix (ADR-040), Vault HA Migration (ADR-041) | ✅ < 1h    | ✅ Completo        |
| Marco 3 Fase 1d    | FinOps Automation Staging (ADR-024)                       | ✅ 3 dias  | ✅ Completo        |
| Marco 3 Fase 1e    | VPC Endpoints (ADR-046, Vault recovery)                   | ✅ 2h32min | ✅ Completo        |
| Marco 4            | GitLab + SonarQube + ArgoCD + Backstage                   | 🚧         | 🚧 Em planejamento |
| Marco 5            | Observability completa + Service Mesh                     | ⏸️         | ⏸️ Pendente        |
| Marco 6            | Multi-environment + Convergência cloud-agnostic           | ⏸️         | ⏸️ Pendente        |

**Legenda**: ✅ Completo | 🚧 Em andamento | ⏸️ Pendente

**Total Marcos 0-3**: ~14 dias de trabalho efetivo

---

## Critérios de Sucesso

**Técnicos**:
- [x] Cluster EKS operacional com 7 nodes
- [x] GitLab, Harbor operacionais
- [x] Observability stack (Prometheus, Grafana, Loki) funcional
- [x] Vault + ESO para secrets management
- [x] PostgreSQL, Redis, RabbitMQ operacionais
- [ ] Pipeline CI/CD completa (build + scan + deploy)
- [ ] Cobertura de testes > 80% para IaC (Terratest)
- [ ] Zero vulnerabilidades HIGH/CRITICAL (security audit)
- [ ] Documentação 100% atualizada (ADRs, logbooks)

**Negócio**:
- [ ] Redução de 50% no tempo de setup de novo projeto (via Backstage templates)
- [ ] 100% de rastreabilidade de mudanças (via hooks Git)
- [ ] Custo staging < $800/mês
- [ ] Satisfação dos desenvolvedores > 4/5 (pesquisa pós-MVP)

---

## Referências

- **Documentação Técnica**:
  - [PROJECT-CONTEXT.md](PROJECT-CONTEXT.md) - Contexto consolidado
  - [README.md](README.md) - Documentação principal
  - [ARCHITECTURE-DIAGRAMS.md](ARCHITECTURE-DIAGRAMS.md)
  - [docs/context/architecture.md](docs/context/architecture.md)
  - [docs/context/decisions.md](docs/context/decisions.md)
  - [SAD v1.2](SAD/docs/sad.md) - CONGELADO (Freeze #3)

- **Repositório**: [Contexto local]

- **Planejamento**:
  - [Quickstart AWS EKS GitLab](docs/plan/quickstart/aws-eks-gitlab-quickstart.md)
  - [Convergence Roadmap](docs/plan/convergence-roadmap.md)
  - [Execution Plan](docs/plan/execution-plan.md)

- **ADRs Críticos**:
  - ADR-021: Kubernetes como orquestrador
  - ADR-024: FinOps automation strategy
  - ADR-026: Multi-environment structure
  - ADR-040: PostgreSQL security groups
  - ADR-041: Vault HA migration
  - ADR-046: VPC endpoints strategy

---

## Notas

### Hierarquia de Projetos

Este projeto tem duas camadas:

1. **🟢 PROJETO ATIVO (Atual)**: AWS EKS MVP
   - Implementação prática para AWS
   - Timeline: 8 semanas
   - Usa alguns serviços AWS nativos (RDS, Secrets Manager temporário)
   - 75-80% já cloud-agnostic (fundações corretas)

2. **🎨 VISÃO CORE (Futuro)**: Plataforma Cloud-Agnostic
   - 6 domínios isolados e reutilizáveis
   - 100% Kubernetes operators (sem recursos nativos cloud)
   - Portável entre AWS, GCP, Azure, on-premises
   - Timeline: 12-18 meses pós-MVP

**Estratégia**: AWS-First, Cloud-Agnostic by Design

### Governança

- **SAD v1.2**: CONGELADO (Freeze #3) - Não modificar
- **ADRs**: Obrigatórios para decisões arquiteturais
- **Rastreabilidade**: Hooks Git obrigatórios
- **AI-First**: Desenvolvimento assistido por AI com aprendizagem contínua

---

_Última atualização: 2026-02-06_
_Este documento é mantido pelo usuário. AI sugere mudanças mas não modifica automaticamente._
