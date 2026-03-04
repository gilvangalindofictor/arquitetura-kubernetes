# 📘 Projeto Kubernetes - Contexto Consolidado

> **Última Atualização**: 2026-03-03
> **Projeto Ativo**: AWS EKS MVP (Marcos 0-4 ✅ 100% | Marco 5 planejamento | Enterprise Assessment 4.2/5.0)
> **Status SAD**: v1.3 🔒 CONGELADO (Freeze #4) — ✨ **NOVO:** Camada 2 (Domínios Corporativos)
> **Governança**: AI-First com rastreabilidade obrigatória
> **Orquestrador**: Kubernetes (ADR-021)
> **Custo AWS (Feb/2026)**: ~$800/mês staging | FinOps Savings: R$ 56.546/ano realizados
> **Recent Updates (2026-03-03)**: INFRA-001 GitLab v18.9.1 ✅ | GAP-011 Linkerd Deployed ✅ | INFRA-002 PostgreSQL 14→16 ✅ | 9 Breaking Changes Catalogued

---

## 🎯 CONTEXTO CRÍTICO: Hierarquia de Projetos

### IMPORTANTE: O que é "Projeto Ativo" vs "Visão Core"

**Quando pergunto "em que momento estamos?", estou falando do PROJETO ATIVO:**

#### 🟢 PROJETO ATIVO: AWS EKS MVP (Atual)

- **O quê**: Implementação prática e tipada para AWS
- **Por quê**: Necessidade específica de entregar plataforma funcional rapidamente
- **Status**: Marco 4 completo (100%), Marco 5 planejamento iniciado, Enterprise Assessment 4.2/5.0 (Advanced+)
- **Localização**: `/platform-provisioning/aws/kubernetes/`
- **Documentação**: [aws-eks-gitlab-quickstart-REAL.md](docs/plan/quickstart/aws-eks-gitlab-quickstart-REAL.md)
- **Características**:
  - ✅ Totalmente funcional em AWS
  - ✅ Terraform + Helm implementados
  - ✅ Marcos 0, 1, 2, 3, 4 completos (CI/CD end-to-end)
  - ✅ EKS v1.34 (control plane + nodes) — Standard Support
  - ✅ FinOps automation ativa (R$ 56.424/ano savings realizados)
  - ✅ CI/CD Platform completo: GitLab + ArgoCD + SonarQube + Keycloak SSO
  - ✅ Security: 8/8 vulnerabilities fixed, ESO 100% coverage
  - ✅ CI/CD Enhancement: 49 artefatos preparados (CICD-001 a 005)
  - ⚠️ Usa alguns serviços AWS nativos (RDS PostgreSQL, AWS Secrets Manager)
  - 📅 Timeline: 4 semanas Marco 0-4, Production Roadmap 14-19 semanas

#### 🎨 VISÃO CORE: Plataforma Cloud-Agnostic (Futuro)

- **O quê**: Stack de ferramentas para "esteirar" linha de produção em QUALQUER cloud
- **Por quê**: Objetivo arquitetural de longo prazo
- **Status**: Visão estratégica, implementação futura
- **Localização**: `/domains/` (estrutura definida, implementação pendente)
- **Documentação**: [SAD](SAD/docs/sad.md), ADRs sistêmicos
- **Características**:
  - 🎯 6 domínios isolados e reutilizáveis
  - 🎯 100% cloud-agnostic (Kubernetes operators, sem recursos nativos)
  - 🎯 Portável entre AWS, GCP, Azure, on-premises
  - 📅 Timeline: 12-18 meses pós-MVP

### Estratégia: AWS-First, Cloud-Agnostic by Design

```
┌─────────────────────────────────────────────────────────┐
│  VISÃO CORE (Long-term)                                 │
│  Stack instrumentada para qualquer cloud                │
│  • 6 domínios isolados                                  │
│  • 100% operators Kubernetes                            │
│  • Zero vendor lock-in                                  │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ Evolução Planejada (Fases 2-4)
                       ▼
┌─────────────────────────────────────────────────────────┐
│  PROJETO ATIVO (Current) ◄── ESTAMOS AQUI              │
│  AWS EKS MVP - Implementação prática                    │
│  • Marco 0: Backend Terraform ✅                        │
│  • Marco 1: Cluster EKS ✅                              │
│  • Marco 2: Platform Services ✅                        │
│  • Marco 3: Workloads ✅ (100% completo)               │
│  • Marco 4: CI/CD Pipeline ✅                            │
│  • Quickstart MVP: 90% (Nodes v1.34 ✅, GitLab v18.9.1 ✅, Linkerd ✅, OIDC ⏸️) │
│                                                          │
│  Pragmatismo: Usa AWS RDS, Secrets Manager              │
│  Fundações Corretas: 75-80% já cloud-agnostic           │
└─────────────────────────────────────────────────────────┘
```

### Quando Você Perguntar "Em Que Momento Estamos?"

**SEMPRE me refiro ao PROJETO ATIVO (AWS EKS MVP):**

- Marco atual: **Marco 5** (Production Readiness — Enterprise Assessment 4.2/5.0, Production Roadmap 10-14 semanas)
- Marco 4: **✅ 100% completo** (8/8 GAPs — CI/CD end-to-end funcional)
- CI/CD Enhancement: **49 artefatos preparados** (CICD-001 a CICD-005 — Security, Quality, Automation, Progressive Delivery)
- Progresso Geral: **75%** (Marcos 0-4 completos, Marco 5 em andamento — GitLab v18.9.1, Linkerd, PostgreSQL 16)
- Próximo: Deploy CI/CD Enhancement (Phase 1: SAST/DAST + Immutable Tags + Quality Gate, Phase 2: Secret Rotation, Phase 3: Argo Rollouts)

**NÃO me refiro:**

- ❌ Implementação dos 6 domínios isolados (futuro)
- ❌ Migração RDS → PostgreSQL Operator (Fase 2-4)
- ❌ Deploy em múltiplas clouds (futuro)

---

## 📋 Índice

1. [Hierarquia de Projetos](#-contexto-crítico-hierarquia-de-projetos) ⬆️ **VOCÊ ESTÁ AQUI**
2. [Visão Geral](#visão-geral)
3. [Status do Projeto Ativo](#status-do-projeto-ativo)
4. [Status dos Domínios](#status-dos-domínios) *(Visão Futura)*
5. [Arquitetura AI](#arquitetura-ai)
6. [Stack Tecnológica](#stack-tecnológica)
7. [Governança e Regras](#governança-e-regras)

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

## 📊 Status do Projeto Ativo

### AWS EKS MVP - Progresso Atual

| Marco              | Descrição                                                                     | Status     | Duração      | Custo/Mês     |
| ------------------ | ----------------------------------------------------------------------------- | ---------- | ------------ | ------------- |
| **Marco 0**        | Backend Terraform (S3 + DynamoDB)                                             | ✅ Completo | 2 dias       | ~$0.01        |
| **Marco 1**        | Cluster EKS (7 nodes, 4 add-ons)                                              | ✅ Completo | 1 dia        | $547          |
| **Marco 2**        | Platform Services (8 fases)                                                   | ✅ Completo | 3 dias       | +$66          |
| **Marco 3 F1a/1b** | Workloads + Secrets (PostgreSQL, Redis, RabbitMQ, GitLab, Vault, ESO, Harbor) | ✅ Completo | 5 dias       | +$58          |
| **Marco 3 F1c**    | PostgreSQL SG Fix (ADR-040)                                                   | ✅ Completo | 5min         | $0            |
| **Marco 3 F1c**    | Vault HA Migration (ADR-041)                                                  | ✅ Completo | 27min        | +$3/mês       |
| **Marco 3 F1d**    | FinOps Automation Staging (Lambda + EventBridge, ADR-024)                     | ✅ Completo | 3 dias       | +$0.50/mês    |
| **Marco 3 F1e**    | VPC Endpoints (STS + EC2, ADR-046, Vault recovery)                            | ✅ Completo | 2h32min      | +$28.90/mês   |
| **TOTAL**          |                                                                               |            | **~14 dias** | **~$700/mês** |

### Marco 3 - Detalhamento (Fase 1a/1b/1c)

| Componente                | Status        | Observações                                                                                                        |
| ------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------ |
| PostgreSQL RDS            | ✅ Completo    | db.t3.medium Single-AZ, 500GB, Harbor+Keycloak database bootstrap, SG least privilege (ADR-040)                    |
| Redis Operator            | ✅ Completo    | OT-Container-Kit v0.23.0, Redis 8.4.1-alpine, 1 replica staging (migrated from SpotaHome 2026-02-13)               |
| RabbitMQ Operator         | ✅ Completo    | Official operator, 1 replica staging, namespace data-services                                                      |
| GitLab CE Staging         | ✅ Completo    | Chart 9.9.1, App v18.9.1, 11 pods (Rev 36), IRSA S3 object storage, External PostgreSQL RDS + Redis                |
| Vault HA                  | ✅ Completo    | 3 replicas operational, KMS auto-unseal, 15h recovery 2026-02-06, VPC Endpoints fix (ADR-041, ADR-046)             |
| VPC Endpoints             | ✅ Completo    | STS + EC2 Interface Endpoints, Private DNS enabled, 10-40x latency improvement, $28.90/mês (ADR-046)               |
| External Secrets Operator | ✅ Operacional | ClusterSecretStore Vault backend, K8s auth configured, Keycloak secrets ready (ADR-032)                            |
| Harbor Registry           | ✅ Completo    | S3 IRSA storage, health OK, ServiceMonitor enabled, jobservice replicas=1 (ADR-039)                                |
| **Keycloak SSO**          | ⏳ Ready       | Chart 18.4.0, 2 replicas HA, PostgreSQL RDS backend, Vault+ESO pattern, deploy pending (R-029 RESOLVED 2026-02-06) |
| **Observability Stack**   | ✅ Completo    | Prometheus/Grafana/Alertmanager Running, 28 ServiceMonitors, tolerations ADR-041 aplicadas                         |
| **FinOps Automation**     | ✅ Completo    | EventBridge rules (startup 07:30, shutdown 20:00 BRT), Lambda functions operational, economia R$ 850/mês (ADR-024) |

### Marcos Completos

**Marco 2 - Platform Services (8/8 fases):**

1. ✅ AWS Load Balancer Controller (OIDC + IAM Role)
2. ✅ Cert-Manager (3 ClusterIssuers: Let's Encrypt prod/staging, self-signed)
3. ✅ Kube-Prometheus-Stack (Prometheus, Grafana, Alertmanager, 28+ dashboards)
4. ✅ Loki + Fluent Bit (Logging, economia $423/ano vs CloudWatch)
5. ✅ Network Policies (Calico policy-only, 11 políticas, microsegmentação)
6. ✅ Cluster Autoscaler (Auto-scaling nodes, economia ~$372/ano)
7. ✅ Test Applications (nginx + echo-server, validação end-to-end)
8. ✅ FinOps Automation (Lambda + EventBridge, economia $1.092/ano)

### Próximos Passos (Marco 3 - Fase 2)

**Todos os itens do Marco 3 estão ✅ COMPLETOS (2026-02-02 a 2026-02-06)**

1. ✅ **FinOps Automation Staging** (ADR-024, 2026-02-02 a 2026-02-05)
   - EventBridge rules: startup 07:30 BRT, shutdown 20:00 BRT (MON-FRI)
   - Lambda functions: finops-scheduler-start/stop-staging operational
   - Economia: R$ 850/mês (~40% redução), R$ 10.200/ano
   - Status: ENABLED e ativo

2. ✅ **PostgreSQL Security Group Fix** (ADR-040, 2026-02-05)
   - SG ingress: VPC CIDR → Private Subnet CIDRs (least privilege)
   - Bootstrap automation ativado

3. ✅ **Vault HA Completion + Recovery** (ADR-041, ADR-046, 2026-02-05/06)
   - 3 replicas operational (vault-0/1/2)
   - KMS auto-unseal ativo em todos os pods
   - Raft cluster validado + failover test OK
   - **Incident Recovery:** 15h downtime resolvido via VPC Endpoints (2026-02-06)
   - Root token: hvs.CxUPch... (secured in K8s secret)

4. ✅ **Redis Operator Migration** (ADR-053-REVISION, 2026-02-13)
   - SpotaHome v3.3.0 → OT-Container-Kit v0.23.0
   - Redis 6.2.6-alpine → 8.4.1-alpine (+20% throughput, 5 years CVE patches)
   - 45 minutes total (vs 4 weeks estimated)
   - Zero data loss (staging environment empty)

5. ✅ **Observability Stack** (2026-02-05)
   - Prometheus/Alertmanager: 2/2 Running
   - Grafana: 3/3 Running
   - 28 ServiceMonitors ativos, stack 100% operacional

6. ✅ **VPC Endpoints Critical Infrastructure** (ADR-046, 2026-02-06)
   - Interface Endpoints: STS (vpce-0c3a498a73742aa21), EC2 (vpce-0b52639b29be0559e)
   - Private DNS enabled (transparent migration)
   - Latency: 50-200ms → <5ms (10-40x improvement)
   - Cost: $28.90/mês vs $1,000+ incident avoided
   - **Trigger:** Vault recovery incident (EBS CSI Driver timeout via NAT Gateway)
   - **Result:** 100% PVC provisioning success rate, Vault operational

### Ações Futuras (Marco 4+)

1. **Harbor Robot Accounts Setup** ⚠️ **BLOQUEADO** (Harbor API auth issue)
   - Script create-robot-account.sh: 401 Unauthorized
   - Admin lockout detectado
   - **Ação:** Reset senha via PostgreSQL DB OU UI manual

2. **Multi-Environment Consolidation** (ADR-026)
   - Replicar stack Staging → Production (Terraform workspaces)
   - Timeline: 6-8 semanas
   - Custo Prod projetado: +$1.500/mês (HA 3 AZs)

3. **Cloud-Agnostic Evolution** (Fase 2)
   - Substituir AWS ALB → NGINX Ingress
   - Substituir RDS PostgreSQL → PostgreSQL Operator
   - Substituir Lambda/EventBridge → Kubernetes CronJob
   - Timeline: 12+ semanas
   - 20+ métricas Harbor disponíveis (health, projects, artifacts, HTTP)
   - Queries PromQL documentadas: [harbor-metrics-queries.md](docs/logbook/2026-02-05-harbor-metrics-queries.md)

7. **Marco 4 Gap Analysis** ✅ **COMPLETO** (2026-02-05, Sessão 4)
   - 8 gaps identificados (2 críticos, 3 médios, 3 baixos)
   - Decisão estratégica: OPÇÃO A (Keycloak + OIDC completo)
   - Roadmap 4 sprints: 13-17h, +$100/mês

8. ~~**GAP-001: Keycloak Deployment**~~ ✅ **REFACTORED** (2026-02-06)
   - Módulo Terraform refatorado: `modules/keycloak/`
   - Integrado no `environments/staging/main.tf`
   - Chart 18.4.0 (codecentric/keycloak), 2 replicas HA
   - PostgreSQL RDS backend: database `keycloak` bootstrapped
   - **Vault + ExternalSecrets pattern** (R-029 RESOLVED - refactored before deploy)
   - Admin password: random_password gerenciado via Terraform
   - DB credentials: ExternalSecret `keycloak-postgresql-credentials` (Vault KV v2)
   - **Status Terraform:** Código refatorado, aguarda `terraform apply`

9. **ArgoCD + SonarQube** 📝 **PLANEJADO** (Marco 4 - Sprint 2)
   - **ArgoCD:** Módulo scaffold criado (`modules/argocd/`), NOT IMPLEMENTED
     - Requer: integração OIDC Keycloak, AppProjects, RBAC
     - Estimativa: 2-3h para completar módulo + integração
   - **SonarQube:** Módulo scaffold criado (`modules/sonarqube/`), NOT IMPLEMENTED
     - Possui TODOs: bootstrap database, ExternalSecret
     - Estimativa: 2-3h para completar módulo + integração

---

## 📊 Status dos Domínios

| Domínio                   | Terraform    | VALIDATION     | Conformidade | Deploy Priority | Status      |
| ------------------------- | ------------ | -------------- | ------------ | --------------- | ----------- |
| **platform-core**         | ✅ 550 linhas | ✅ 500 linhas   | 88.6%        | #1 Fundação     | ✅ APROVADO  |
| **secrets-management**    | ⏳ ADR-002    | ⏳ Pendente     | N/A          | #2 Crítico      | ⚠️ BLOQUEADO |
| **observability**         | ✅ Refatorado | ✅ 3 validações | 91.2%        | #3 Medium       | ✅ APROVADO  |
| **cicd-platform**         | ✅ 650 linhas | ✅ 700 linhas   | 86.4%        | #4 Objetivo #1  | ✅ APROVADO  |
| **data-services**         | ✅ 450 linhas | ✅ 350 linhas   | 92.3%        | #5 Medium       | ✅ APROVADO  |
| **security**              | ⏳ ADR-002    | ⏳ Pendente     | N/A          | #6 Medium       | ⚠️ BLOQUEADO |
| **MÉDIA (implementados)** | -            | -              | **89.6%**    | -               | -           |

### Decisões Pendentes
1. ~~**secrets-management**: Vault vs External Secrets Operator~~ → ✅ **DECIDIDO:** Ambos (Vault HA storage + ESO sync, ADR-031/032)
2. ~~**security**: Kyverno vs OPA Gatekeeper~~ → ✅ **DECIDIDO:** Kyverno (ADR-043, simplicidade + YAML native)

### Conformidade por ADR (Domínios Implementados)

| ADR       | Título                | Conformidade Média |
| --------- | --------------------- | ------------------ |
| ADR-003   | Cloud-Agnostic        | 100% ✅             |
| ADR-004   | IaC/GitOps            | 100% ✅             |
| ADR-005   | Segurança             | 73.3% ⚠️            |
| ADR-006   | Observabilidade       | 96.7% ✅            |
| ADR-020   | Platform Provisioning | 100% ✅             |
| ADR-021   | Kubernetes            | 96.7% ✅            |
| **MÉDIA** |                       | **94.4%**          |

**Nota**: Gap comum ADR-005 (RBAC granular, Network Policies) é não-bloqueante, roadmap Sprint+1.

---

## 🏢 Status dos Domínios Corporativos (Camada 2)

**⚠️ NOVO (SAD v1.3 - 2026-02-09)**: Organização de aplicações por produtos/linhas de negócio (Domain-Driven Design)

### Diferenciação: Camada 1 vs Camada 2

| Aspecto         | Camada 1 (Domínios Técnicos) | Camada 2 (Domínios Corporativos)   |
| --------------- | ---------------------------- | ---------------------------------- |
| **Foco**        | Infraestrutura de plataforma | Aplicações de negócio              |
| **Status**      | ✅ Implementados (Marco 0-3)  | 📋 Planejamento (Marco 0)           |
| **Organização** | Por função técnica           | Por produto/linha de negócio (DDD) |
| **Referência**  | ADR-002                      | ADR-047, ADR-048, ADR-049          |

### 5 Domínios Corporativos

| Domínio             | Produtos                                             | Status Marco 0                   | Próximos Passos                 | Fase Implementação |
| ------------------- | ---------------------------------------------------- | -------------------------------- | ------------------------------- | ------------------ |
| **PLATFORM**        | Observability, CI/CD, Secrets, Security              | ✅ Herda Camada 1                 | Nenhum (já operacional)         | ✅ Marco 0-3        |
| **INTEGRATION**     | iPaaS (9 microserviços)                              | 📋 Dockerfiles existem            | Criar Helm charts, GitOps repos | Fase 1 (4 semanas) |
| **DATA**            | Hatch ETL (151 extractors), VemSoft ETL              | 📋 docker-compose existente       | Converter para K8s manifests    | Fase 2 (4 semanas) |
| **OPERATIONS**      | Process Management, Fulfillment                      | 📋 Planejado (futuro)             | Definir requisitos              | Fase 3 (6 semanas) |
| **SHARED-SERVICES** | Files (BucketConnector), Notification, Calendar, RPA | 📋 BucketConnector tem Helm chart | Deploy Files + Notification     | Fase 1 (4 semanas) |

### Documentação Criada (Marco 0)

✅ **ADRs Criados** (2026-02-09):
- **ADR-047**: Estrutura Corporativa de Domínios de Negócio
- **ADR-048**: Naming Conventions Determinísticas (regex-based)
- **ADR-049**: Governança e RBAC para Domínios Corporativos

✅ **Atualizações**:
- **ADR-002**: Atualizado para diferenciar Camada 1 (técnico) vs Camada 2 (corporativo)
- **SAD v1.3**: Adicionada seção "Camada 2: Domínios Corporativos"
- **README.md**: Adicionada arquitetura em duas camadas
- **PROJECT-CONTEXT.md**: Esta seção (status corporativo)

### Naming Conventions Definidas

**GitLab**:
```
Formato: ^(corporate-domains)/(platform|integration|data|operations|shared-services)/[a-z0-9-]+$
Exemplo: corporate-domains/integration/ipaas-bff-rest
```

**Kubernetes Namespaces**:
```
Formato: ^(staging|prod)-(integration|data|operations|shared)(-[a-z0-9-]+)?$
Exemplos:
  staging-integration-ipaas
  prod-data-hatch
  staging-shared-files
```

**Labels Obrigatórias**:
```yaml
domain: ^(platform|integration|data|operations|shared-services)$
owner: ^[a-z0-9-]+-team$
product: ^[a-z0-9-]+$
```

### RBAC Planejado

**GitLab Groups** (criar no Marco 0, mesmo sem membros):
- `platform-team` (você como Owner)
- `integration-team` (você como Owner)
- `data-team` (você como Owner)
- `operations-team` (você como Owner)
- `shared-services-team` (você como Owner)

**Princípio**: Cada time tem **Maintainer** no seu domínio, **Reporter** nos demais

### Timeline de Implementação

- ✅ **Marco 0 (Atual)**: ADRs criados, governança definida, naming conventions documentadas
- 📋 **Fase 1 (4 semanas)**: Deploy UTILS (Files, Notification) + INTEGRATION (iPaaS)
- 📋 **Fase 2 (4 semanas)**: Deploy DATA (Hatch ETL, VemSoft ETL) + CORE TECH (RPA)
- 📋 **Fase 3 (6 semanas)**: Deploy OPERATIONS (Process Management, Fulfillment)
- 📋 **Fase 4 (8 semanas)**: Backstage Software Catalog, GitOps completo (ArgoCD)

**Status Atual**: 📋 **Planejamento completo**, pronto para iniciar Fase 1

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
- **Linkerd** 1.16.11 - Service Mesh mTLS ✅ **DEPLOYED** (7/7 pods Running, 4 Grafana dashboards, 2026-03-03)
- **cert-manager** 1.13.3 - TLS Certificates (Let's Encrypt HTTP-01)
- **NGINX Ingress** 4.9.0 - Ingress Controller (2 réplicas, LoadBalancer)

**Contratos Providos**: Authentication (99.95% SLA), Gateway (99.9%), Service Mesh (99.9%), Certificates (99.9%), Ingress (99.9%)

### cicd-platform (Esteira DevOps)
- **GitLab CE** 9.9.1 - Git + CI (v18.9.1, 1 réplica webservice staging, External PostgreSQL RDS, External Redis, S3 object storage)
- **SonarQube** 10.3.0 - Code Quality (PostgreSQL, 20Gi storage)
- **Harbor** 1.14.0 - Registry (100Gi, Trivy scanning, Chartmuseum)
- **ArgoCD** v2.10.0 - GitOps (2 réplicas, Keycloak OIDC, ✅ PKCE active)
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
- **PostgreSQL RDS** 16.4 - AWS-managed ✅ **UPGRADED** (db.t3.medium Single-AZ staging, 14→16 completed 2026-03-03)
- **OT-Container-Kit Redis Operator** 0.23.0 - Redis 8.4.1 (migrated from SpotaHome 2026-02-13, ADR-053-REVISION)
- **RabbitMQ Cluster Operator** 2.19.0 - RabbitMQ 3.13-management (Official operator)
- **Velero** 1.15.0 - Backup/DR com IRSA (zero credenciais estáticas, 2026-02-25)

> **📋 Controle de Versões**: Atualizado 2026-02-13 (Redis migration). Consulte [VERSION-CONTROL.md](domains/data-services/docs/VERSION-CONTROL.md).

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
2. ✅ **Network Policies**: Implementado em audit mode (22 policies, 5 namespaces, 2026-02-24)
3. ✅ **Velero IRSA**: Completo - OIDC thumbprint + ARN format fix (2026-02-25)
4. **HPA/VPA**: Após 2 semanas de métricas (observar padrões)
5. **GitLab OIDC**: Integração com Keycloak (ArgoCD já implementado)

---

## 🚀 Próximos Passos

### Marco 3 (100% Completo ✅) — ATUALIZADO 2026-02-06
- [x] PostgreSQL RDS + Security Group least privilege (ADR-040)
- [x] Vault HA 3 replicas + KMS auto-unseal (ADR-041)
- [x] Redis Operator + RabbitMQ Operator + GitLab CE
- [x] Harbor Registry + Robot Accounts (UI workaround ADR-045)
- [x] External Secrets Operator + Vault backend integration
- [x] Observability Stack validação (28 ServiceMonitors)
- [x] **Keycloak SSO Platform** (2026-02-06) - Módulo implementado, aguarda deploy

### Marco 4 — CI/CD Pipeline Completo (EM ANDAMENTO 🚀)

**STATUS:** Sprint 1 QUASE COMPLETO - Keycloak implementado no código (aguarda `terraform apply`)
**DURAÇÃO ESTIMADA:** 4-8h restantes (SonarQube fix + GitLab CI/CD)
**CUSTO INCREMENTAL:** +$100/mês
**🎉 CONCLUÍDO (2026-02-20):** ArgoCD v2.10.0 upgrade com PKCE ativo

#### Sprint 1: Pre-Requisites — STATUS: 80% COMPLETO
- [x] **GAP-001:** Keycloak SSO Platform ✅ **CÓDIGO IMPLEMENTADO** (2026-02-06)
  - ✅ Módulo terraform/modules/keycloak/ criado e funcional
  - ✅ Integrado no environments/staging/main.tf
  - ✅ Bootstrap database keycloak no PostgreSQL RDS (via additional_databases)
  - ✅ AWS Secrets Manager pattern implementado
  - ✅ Admin password: random_password gerenciado via Terraform
  - ✅ Helm values configurados (2 replicas HA)
  - ⏳ **PRÓXIMA AÇÃO:** `terraform apply` para deploy no cluster
  - 📝 **PENDENTE:** Configurar OIDC clients (argocd, sonarqube, gitlab) após deploy
  - 📝 **PENDENTE:** Criar realm master + groups (argocd-admins, developers)

- [x] **GAP-002:** GitLab Components Fix ✅ RESOLVIDO (2026-02-13)
  - ✅ Gitaly: Running (PVC/scheduling fix via tolerations)
  - ✅ KAS: Running (K8s API auth resolved)
  - ✅ Sidekiq: Running (Redis/DB migration completed)
  - ✅ Webservice: Running (Redis authentication fixed)
  - ⚠️ Runner: DNS fix aplicado, aguarda authentication token (GitLab 17.x workflow - parte do GAP-005)

#### Sprint 2: Core CI/CD Components (4-6h)

- [x] **GAP-003:** ArgoCD Deploy ✅ COMPLETO (2026-02-06) | 🎉 UPGRADED (2026-02-20)
  - ✅ Deployed via Helm chart v5.51.6 (ArgoCD v2.9.3)
  - 🎉 **UPGRADED:** v2.9.3 → v2.10.0 (kubectl set image, 2026-02-20)
  - ✅ **PKCE Active:** Native support in v2.10.0+ (RFC 7636 compliant)
  - ✅ PostgreSQL RDS integration (external database)
  - ✅ OIDC Keycloak integration (realm platform)
  - ✅ RBAC configurado (argocd-admins group)
  - ✅ AppProjects criados (platform, applications)
  - ✅ HA: 2 replicas server/repo-server, 8 pods Running
  - 📝 Logbook: [2026-02-06-argocd-gitops-deployment.md](docs/logbook/2026-02-06-argocd-gitops-deployment.md)
  - 📝 Upgrade Log: [2026-02-20-argocd-upgrade-implementation.md](docs/logbook/2026-02-20-argocd-upgrade-implementation.md)

- [x] **GAP-004:** SonarQube Deploy ✅ COMPLETO (2026-02-06) | 🔴 BROKEN (2026-02-13)
  - ✅ Deployed SonarQube Community 10.3.0 (Helm chart)
  - ✅ PostgreSQL RDS integration
  - ✅ OIDC Keycloak attempted (Community edition limitation)
  - 🔴 **PROBLEMA ATUAL:** EBS volume deletado (vol-04fcd44f4ac758f9b não existe)
  - 🔴 **STATUS:** Pod stuck Init:0/2 (FailedAttachVolume)
  - 🚨 **AÇÃO URGENTE:** Recreate PVC + restore database (1-2h)
  - 📝 Logbook: [2026-02-06-sonarqube-deployment.md](docs/logbook/2026-02-06-sonarqube-deployment.md)

#### Sprint 3: Pipeline Integration (3h)
- [ ] **GAP-005:** GitLab CI/CD Integration (3h)
  - Configurar CI/CD variables (Harbor, SonarQube)
  - Criar .gitlab-ci.yml templates
  - Runner RBAC least-privilege
  - Validação pipeline end-to-end

#### Sprint 4: Hardening (4h) — OPCIONAL

- [ ] **GAP-006:** ApplicationSets GitOps Patterns (2h)
- [x] **GAP-007:** Tempo OTLP Integration ✅ COMPLETO (2026-02-10)
  - ✅ OTLP receivers gRPC:4317, HTTP:4318 ativos
  - ✅ Replication factor fix (RF=2 match replicas)
  - ✅ Trace generator operacional
  - ✅ Helm REV 6 estável
  - 📝 Logbook: [2026-02-10-gap007-tempo-otlp.md](docs/logbook/2026-02-10-gap007-tempo-otlp.md)

- [x] **GAP-011:** Linkerd Service Mesh ✅ COMPLETO (2026-03-03)
  - ✅ Deployed via terraform apply -target=module.linkerd
  - ✅ 7/7 pods Running (destination, identity, proxy-injector + viz: metrics-api, tap, tap-injector, web)
  - ✅ 4 Grafana dashboards deployed (top-line, service-mesh, deployment, namespace)
  - ✅ mTLS end-to-end — BACEN compliance ready

- [x] **INFRA-001:** GitLab Upgrade Chain v17.11.7→v18.9.1 ✅ COMPLETO (2026-03-03)
  - ✅ 9/9 upgrade steps executed (8.11.8→9.0.6→9.1.7→9.2.8→9.3.6→9.4.6→9.5.5→9.8.5→9.9.1)
  - ✅ 9 breaking changes discovered and catalogued
  - ✅ Root causes fixed permanently in values-staging-working.yaml
  - ✅ Rev 36 deployed, all 11 pods Running

- [x] **INFRA-002:** PostgreSQL 14→16 Upgrade ✅ COMPLETO (2026-03-03)
  - ✅ RDS major version upgrade (allow_major_version_upgrade = true)
  - ✅ GitLab chart image.tag set to "16.4" to match RDS
  - ✅ ADR-093 created documenting 5-phase upgrade strategy

- [ ] **GAP-008:** Monitoring & Dashboards Marco 4 (1h)

### Sprint+1: Remediação de Gaps
- [ ] RBAC Granular (4 domínios)
- [ ] Network Policies (6 domínios)
- [ ] Velero Credentials → Vault
- [ ] HPA/VPA (após 2 semanas métricas)

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
- **Domínios Implementados**: 5/6 (83%) - observability, platform-core, cicd-platform, data-services, security
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

### 🚨 ACHADOS CRÍTICOS EM STAGING (2026-02-13)

**✅ TERRAFORM = FONTE VERDADE. Staging matches Terraform 100%**

Auditoria revelou: **Staging está correto**, mas **Documentação Arquitetural foi atualizada para refletir estado real**.

LEITURA OBRIGATÓRIA para CTO e Architecture Team:

1. **[TERRAFORM-SOURCE-OF-TRUTH.md](domains/data-services/docs/TERRAFORM-SOURCE-OF-TRUTH.md)** - PostgreSQL=RDS✅ Redis=OT-Container-Kit✅ RabbitMQ=Official✅ Velero=Not impl✅
2. [STAGING-ANALYSIS-FINDINGS.md](domains/data-services/docs/STAGING-ANALYSIS-FINDINGS.md) - Sumário executivo STAGING
3. [STAGING-INVENTORY.md](domains/data-services/docs/STAGING-INVENTORY.md) - Reconciliação STAGING
4. [STAGING-BACKUP-STRATEGY.md](domains/data-services/docs/STAGING-BACKUP-STRATEGY.md) - Análise de gaps STAGING

**Verdade do Terraform (para STAGING):**
- ✅ PostgreSQL: AWS RDS 16.4 db.t3.medium (not Zalando Operator)
- ✅ Redis: OT-Container-Kit 0.23.0 with Redis 8.4.1 (migrated from SpotaHome 2026-02-13)
- ✅ RabbitMQ: Official 2.19.0 with 1 replica (confirmed)
- ✅ Velero: Not declared in Terraform (deliberate, zero implementation)

**AWS Profile (2026-02-13):**
- ✅ Profile renomeado: `k8s-platform-prod` → `k8s-platform-staging`
- ✅ Namespaces normalizados: `*-dev/*-hml/*-prd` → `*-staging`
- ✅ Documentação alinhada com ambiente staging

---

### VALIDATION-REPORTs
- **platform-core**: [/domains/platform-core/docs/VALIDATION-REPORT.md](domains/platform-core/docs/VALIDATION-REPORT.md) (88.6%)
- **cicd-platform**: [/domains/cicd-platform/docs/VALIDATION-REPORT.md](domains/cicd-platform/docs/VALIDATION-REPORT.md) (86.4%)
- **data-services**: [/domains/data-services/docs/VALIDATION-REPORT.md](domains/data-services/docs/VALIDATION-REPORT.md) (92.3%)
  - *⚠️ NOTA: Veja achados críticos acima*
- **observability**: [/domains/observability/docs/VALIDATION-REPORT.md](domains/observability/docs/VALIDATION-REPORT.md) (91.2%)

---

**Autor**: System Architect
**Última Atualização**: 2026-03-03
**Versão**: 1.2 (Session 2026-03-03: GitLab v18.9.1 + Linkerd + PostgreSQL 16)
**Status**: ✅ ATIVO
