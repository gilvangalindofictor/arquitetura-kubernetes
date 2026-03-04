# Projeto Kubernetes - Plataforma Corporativa de Engenharia

**Last Updated:** 2026-03-04
**Status:** Current
**Owner:** Platform Team
**Version:** 4.0 (Marco 4 Complete + CI/CD Enhancement + INFRA Upgrades)

> **🎯 PROJETO ATIVO:** AWS EKS GitLab Quickstart — Enterprise Assessment 4.0/5.0 (Advanced+)
> **📋 VISÃO FUTURA:** Plataforma Cloud-Agnostic Completa (Fases 2-4)
> **Metodologia**: AI-First (adaptado do projeto iPaaS)
> **Status Atual**: Marco 4 ✅ COMPLETO | Marco 5 em planejamento (Production Readiness 10%)
> **Última Atualização**: 2026-03-04

---

## 🎯 Hierarquia de Projetos

### 🟢 Projeto Ativo: AWS EKS GitLab — Marco 4 ✅ COMPLETO

**Status:** Marco 4 ✅ 100% COMPLETO | Marco 5 🚧 em planejamento (10%)
**Documento:** [aws-eks-gitlab-quickstart-REAL.md](docs/plan/quickstart/aws-eks-gitlab-quickstart-REAL.md)
**Enterprise Assessment:** 4.0/5.0 (Advanced+) — 85% production-ready
**Custo:** ~$716/mês líquido (staging) | FinOps Savings: R$ 62.425/ano

**Objetivo:** Plataforma Kubernetes enterprise-grade na AWS com GitLab CI/CD, mTLS, WAF, DR e observabilidade completa.

**Escopo — Marcos Completos:**

- ✅ Marco 0: Baseline Terraform (backend S3 + DynamoDB)
- ✅ Marco 1: Cluster EKS 1.34 Standard Support (17 namespaces DEC-074)
- ✅ Marco 2: Platform Services — ALB, cert-manager, Prometheus stack, Loki, Autoscaler
- ✅ Marco 3: Workloads — RDS PostgreSQL 16.4, Vault HA, Harbor, Keycloak OIDC 6 clients
- ✅ Marco 4: CI/CD Platform — GitLab v18.9.1, ArgoCD, SonarQube, 8/8 GAPs
  - CI/CD Enhancement: CICD-001→005 (SAST/DAST, Quality Gate, Secret Rotation, Immutable Tags, Argo Rollouts)
  - iPaaS Public: GAP-010 AWS WAF v2 | GAP-011 Linkerd mTLS 18/18 proxies | GAP-012 Velero DR Phase 1
  - INFRA: GitLab v17.7→v18.9.1 (INFRA-001) | PostgreSQL 14.8→16.4 (INFRA-002)
  - Security: Kyverno ENFORCE 80/80 PASS | ESO 16/16 SecretSynced | 8/8 vulnerabilities fixed
- 🚧 Marco 5: Production Readiness (planejamento — 8 gates, 2 em contagem)

**Por que este é o projeto principal:**

- ✅ Resultado tangível e operacional rápido
- ✅ Validação prática de decisões arquiteturais
- ✅ Fundações corretas para evolução futura
- ✅ Custos controlados e otimizados
- ✅ 75-80% dos componentes já cloud-agnostic (ADR-023)

#### 🔄 Arquitetura do GitLab: Instância Compartilhada com Migração Progressiva de Recursos

**Decisão Estratégica**: GitLab será deployado como **instância única compartilhada entre ambientes**, com migração progressiva dos recursos de backend.

##### Momento A - Fase Inicial (Validação)

```text
GitLab CE (namespace: cicd-gitlab)
├── Aplicação GitLab (webservice, sidekiq, gitaly)
├── GitLab Runners (configurados para múltiplos ambientes)
└── Dependências Backend (Staging):
    ├── PostgreSQL RDS: staging-gitlab-db (db.t3.small Multi-AZ)
    ├── Redis: staging-redis (single instance)
    ├── RabbitMQ: staging-rabbitmq (single instance)
    └── Object Storage: S3 bucket staging-gitlab-artifacts
```

##### Momento B - Fase Produção (Após Validação)

```text
GitLab CE (namespace: cicd-gitlab)
├── Aplicação GitLab (MESMA instância, sem downtime)
├── GitLab Runners (MESMOS runners, reconfigurados)
└── Dependências Backend (Produção):
    ├── PostgreSQL RDS: prod-gitlab-db (db.t3.medium Multi-AZ) ✅ MIGRADO
    ├── Redis: prod-redis HA (master-replica + sentinel) ✅ MIGRADO
    ├── RabbitMQ: prod-rabbitmq (cluster mode) ✅ MIGRADO
    └── Object Storage: S3 bucket prod-gitlab-artifacts ✅ MIGRADO
```

##### Benefícios desta abordagem

- ✅ **Economia de custos**: Uma única instância do GitLab (reduz uso de recursos computacionais)
- ✅ **Gestão simplificada**: Apenas um GitLab para administrar (usuários, permissões, configurações)
- ✅ **Migração sem downtime**: Troca de backend via configuração, sem reinstalação
- ✅ **Validação segura**: Iniciar com recursos staging (menor custo) e escalar para produção conforme necessário
- ✅ **Isolamento lógico**: Branches, repositórios e runners podem ser organizados por ambiente

##### Estratégia de Migração (Momento A → Momento B)

1. **Backup completo** do GitLab (repositories, DB, uploads) → S3
2. **Deploy recursos de produção** (RDS prod, Redis HA, RabbitMQ cluster)
3. **Atualizar configuração GitLab** (Helm values) apontando para novos backends
4. **Migrar dados** via ferramentas nativas (pg_dump/restore, redis-cli, rabbitmqctl)
5. **Rollout GitLab** com nova configuração (zero downtime via rolling update)
6. **Validação** e smoke tests
7. **Descomissionar recursos staging** (opcional, pode manter para testes)

**Referência**: Ver [Quickstart README](docs/plan/quickstart/README.md) para detalhes sobre recursos de staging e produção.

---

### 📋 Visão de Longo Prazo (Fases 2-4): Plataforma Cloud-Agnostic

**Status:** ESTRATÉGIA FUTURA
**Documento:** [Roadmap de Convergência](docs/plan/convergence-roadmap.md)
**Timeline:** 12-18 meses (após Marco 3)
**Custo Projetado:** R$ 8.500/mês (plataforma completa)

**Objetivo:** Evoluir plataforma AWS para arquitetura 100% cloud-agnostic com 6 domínios especializados.

**Fases de Convergência:**

- 📋 Fase 2 (12 semanas): Abstração Multi-Cloud (NGINX Ingress, Karpenter, CloudNativePG)
- 📋 Fase 3 (8 semanas): Validação em 2ª cloud (GCP/Azure staging)
- 📋 Fase 4 (12 semanas): Platform Engineering Completo (Service Mesh, Vault, Backstage)

### Arquitetura em Duas Camadas (v1.3)

**⚠️ ATUALIZAÇÃO v1.3**: A arquitetura é organizada em **duas camadas complementares**:

#### Camada 1: Domínios Técnicos (Infraestrutura de Plataforma)

**6 Domínios Especializados:**

1. **platform-core**: Fundação (Kong, Keycloak, Service Mesh, cert-manager)
2. **cicd-platform**: Esteira CI/CD (GitLab, SonarQube, ArgoCD, Backstage)
3. **observability**: Monitoramento full-stack (OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Kiali)
4. **data-services**: DBaaS, CacheaaS, MQaaS (PostgreSQL, Redis, RabbitMQ com HA e backup)
5. **secrets-management**: Cofre centralizado (Vault)
6. **security**: Policies, runtime, compliance (OPA/Kyverno, Falco, Trivy)

**Referência**: [ADR-002: Estrutura de Domínios Técnicos](docs/adr/adr-002-estrutura-de-dominios.md)

#### Camada 2: Domínios Corporativos (Aplicações de Negócio)

**5 Domínios Organizados por Produtos/Linhas de Negócio (Domain-Driven Design):**

1. **PLATFORM**: Infraestrutura compartilhada (herda Camada 1)
2. **INTEGRATION**: iPaaS - 9 microserviços para integrações SaaS (BFF REST/gRPC/SOAP, MS Core-Comm, Jobs, Notifications, Validation, Peers, Orchestrator)
3. **DATA**: ETL Hatch (151 extractors + API GraphQL + Web UI), ETL VemSoft, Data Platform (catálogo, qualidade, governança)
4. **OPERATIONS**: Process Management, Fulfillment, Operational Monitoring
5. **SHARED-SERVICES**: Files (BucketConnector, Generators), Notification (Email/Slack/Teams), Calendar, RPA Platform

**Referências**:
- [ADR-047: Estrutura Corporativa de Domínios de Negócio](docs/adr/adr-047-estrutura-corporativa-dominios.md)
- [ADR-048: Naming Conventions Determinísticas](docs/adr/adr-048-naming-conventions-deterministicas.md)
- [ADR-049: Governança e RBAC](docs/adr/adr-049-governanca-rbac-dominios-corporativos.md)

**Diferenciação**:
- **Camada 1**: Infraestrutura técnica, mudanças raras, ownership Platform Team
- **Camada 2**: Aplicações de negócio, mudanças frequentes, ownership por domínio (Integration Team, Data Team, etc)

**Características:**

- ✅ **Orquestrador: Kubernetes** - Escolhido vs Docker Swarm, Nomad, ECS, Cloud Run
- ✅ **Cloud-Agnostic OBRIGATÓRIO** - Meta final, iniciando com AWS
- ✅ **Escalabilidade Multi-Domínio** - Cada domínio evolui independentemente
- ✅ **Governança Centralizada** - ADRs obrigatórios
- ✅ **Rastreabilidade Total** - Hooks, logs, commits estruturados
- ✅ **Isolamento** - Namespaces, RBAC, Network Policies, Service Mesh por domínio

---

## 🔄 Estratégia de Convergência

### Princípio: AWS-First, Cloud-Agnostic by Design

**Implementamos primeiro na AWS (rápido, prático) mas projetamos para portabilidade:**

1. **Fundações Corretas Desde o Início**
   - Uso prioritário de Helm Charts oficiais (agnósticos)
   - Kubernetes Operators em vez de serviços gerenciados (ADR-023)
   - Network Policies com Calico (portável)
   - Terraform modularizado

2. **Portabilidade Atual (Fase 1)**
   - ✅ 75-80% dos componentes já cloud-agnostic
   - ⚠️ Dependências AWS: ALB Controller, RDS, EventBridge/Lambda (FinOps)
   - ✅ Decisões de design permitem migração incremental

3. **Roadmap de Evolução**
   - Ver [Roadmap de Convergência](docs/plan/convergence-roadmap.md) completo
   - Migração planejada para NGINX Ingress, CloudNativePG, Karpenter
   - Validação multi-cloud em Fase 3

**Documentação de Convergência:**

- 📘 [Convergence Roadmap](docs/plan/convergence-roadmap.md) - Estratégia completa de evolução AWS → Multi-Cloud
- 📘 [AWS EKS Quickstart](docs/plan/quickstart/aws-eks-gitlab-quickstart.md) - Projeto ativo detalhado
- 📘 [Evolution Strategy](docs/plan/quickstart/evolution-strategy.md) - Fases de maturidade
- 📘 [Architecture](docs/context/architecture.md) - Estado atual da implementação
- 📘 [Decisions](docs/context/decisions.md) - ADRs técnicas aplicadas

---

## 🗂️ Estrutura do Projeto

```
Kubernetes/
├── docs/                     # Governança central
│   ├── context/              # Missão e escopo
│   ├── adr/                  # ADRs de governança
│   ├── plan/                 # Plano de execução
│   ├── skills/               # Skills para IA
│   ├── agents/               # Agentes especializados
│   ├── prompts/              # Prompts operacionais
│   ├── mcp/                  # MCP tools
│   └── logs/                 # Log de progresso
│
├── SAD/                      # Decisões Arquiteturais Sistêmicas
│   └── docs/
│       ├── sad.md            # v1.2 🔒 FROZEN (Freeze #3)
│       ├── adrs/             # ADRs sistêmicos (13 ADRs)
│       └── architecture/     # Regras de herança e contratos
│
├── ai-contexts/              # Contextos para agentes AI
│   └── copilot-context.md
│
├── platform-provisioning/    # 🆕 Provisionamento de Clusters (CLOUD-SPECIFIC)
│   ├── azure/                # 🔄 AKS (recomendado - $615/mês)
│   │   └── kubernetes/       # Terraform azurerm, VNet, storage
│   ├── aws/                  # ⏸️ EKS (planejado - $599/mês)
│   └── gcp/                  # ⏸️ GKE (planejado - $837/mês)
│
└── domains/                  # Domínios independentes (CLOUD-AGNOSTIC)
    ├── observability/        # ✅ Métricas, logs, traces (OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Kiali)
    ├── platform-core/        # 🔄 Fundação (Kong, Keycloak, Service Mesh, cert-manager)
    ├── cicd-platform/        # 🔄 🎯 CI/CD (GitLab, SonarQube, ArgoCD, Backstage)
    ├── data-services/        # 🔄 DBaaS (PostgreSQL, Redis, RabbitMQ, Velero)
    ├── secrets-management/   # 🔄 Cofre (Vault)
    └── security/             # 🔄 Policies (OPA/Kyverno, Falco, Trivy)
```

---

## 🎯 Domínios

### 1. ✅ observability (Integrado)
**Responsabilidade**: Coleta, armazenamento e visualização de métricas, logs e traces

**Stack**:
- OpenTelemetry Collector (coletor central)
- Prometheus (métricas) + Alertmanager
- Grafana (visualização)
- Loki (logs)
- Tempo (traces)
- Kiali (service mesh observability)

**Status**: Estrutura migrada do projeto Observabilidade

---

### 2. 🔄 platform-core (Fundação)
**Responsabilidade**: Infraestrutura base (gateway, autenticação, service mesh, certificados)

**Stack**:
- Kong (API Gateway)
- Keycloak (Autenticação e Autorização centralizada)
- Istio ou Linkerd (Service Mesh com sidecar isolation)
- cert-manager (Certificados TLS automatizados)
- NGINX (Ingress Controller)

**Status**: Aguardando FASE 2

---

### 3. 🔄 🎯 cicd-platform (Esteira CI/CD) — **Primeiro Objetivo**
**Responsabilidade**: CI/CD completo e governança de aplicações via Backstage

**Stack**:
- GitLab (Git self-hosted + CI pipelines)
- SonarQube (Qualidade de código)
- ArgoCD (Continuous Deployment)
- Backstage Spotify (Developer Portal + Catálogo + Governança)
- **Stacks Suportadas**: Go, .NET, Python, Node.js (polyglot)

**Workflow**:
1. Backstage cria repositório no GitLab
2. GitLab CI executa build + SonarQube scan
3. ArgoCD faz deploy no Kubernetes
4. Vault injeta secrets no processo

**Status**: Aguardando FASE 2

---

### 4. 🔄 data-services (Serviços de Dados)
**Responsabilidade**: Databases, cache, mensageria gerenciados (DBaaS, CacheaaS, MQaaS)

**Stack**:
- PostgreSQL (HA com replicação + backup automatizado)
- Redis (cluster mode para cache e sessões)
- RabbitMQ (cluster HA para mensageria)
- Velero (backup/restore automatizado)
- Prometheus Exporters (observabilidade)
- Alertmanager (alarmística)

**Status**: Aguardando FASE 3

---

### 5. 🔄 secrets-management (Cofre de Senhas)
**Responsabilidade**: Cofre centralizado integrado com CI/CD

**Stack**:
- HashiCorp Vault ou External Secrets Operator
- Integração automática com CI/CD (injeção de secrets)
- Rotação automática de credenciais
- Auditoria de acessos

**Decisão Pendente**: Mesa técnica sobre armazenar secrets na imagem vs external

**Status**: Aguardando FASE 3

---

### 6. 🔄 security (Segurança e Compliance)
**Responsabilidade**: Policies, runtime security, compliance, vulnerability scanning

**Stack**:
- OPA ou Kyverno (policy engine)
- Falco (runtime security)
- Trivy (scan de vulnerabilidades integrado ao CI/CD)
- RBAC centralizado por namespace
- Network Policies rigorosas
- Pod Security Standards

**Status**: Aguardando FASE 4

---

## 📚 Documentação Principal

### Governança e Contexto
- [Context Generator](docs/context/context-generator.md) - Missão, escopo e restrições
- [Copilot Context](ai-contexts/copilot-context.md) - Contexto completo para IA
- [Execution Plan](docs/plan/execution-plan.md) - Plano de 6 fases

### ADRs (Architecture Decision Records)
- [ADR-001: Setup, Governança e Método](docs/adr/adr-001-setup-e-governanca.md)
- [ADR-002: Estrutura de Domínios](docs/adr/adr-002-estrutura-de-dominios.md)

### Prompts Especializados
- [Orchestrator Guide](docs/prompts/orchestrator-guide.md) - Setup completo
- [Develop Feature](docs/prompts/develop-feature.md) - Desenvolver features
- [Bugfix](docs/prompts/bugfix.md) - Corrigir bugs
- [Refactoring](docs/prompts/refactoring.md) - Refatorar infraestrutura
- [Domain Creation](docs/prompts/domain-creation.md) - Criar novos domínios
- [Automatic Audit](docs/prompts/automatic-audit.md) - Auditar consistência

### Scripts AWS - Marco 0

Esta seção consolida a documentação dos scripts presentes em `platform-provisioning/aws/scripts` (Marco 0).

Contém scripts para engenharia reversa e expansão incremental da VPC existente.

## 📋 Índice

- [Visão Geral](#visão-geral)
- [Pré-requisitos](#pré-requisitos)
- [Scripts Disponíveis](#scripts-disponíveis)
- [Workflow Recomendado](#workflow-recomendado)
- [Segurança](#segurança)

## Visão Geral

Este diretório contém scripts para o **Marco 0** do projeto, que estabelece a baseline da infraestrutura AWS usando engenharia reversa da VPC existente.

### Objetivos do Marco 0

1. ✅ Documentar estado atual da VPC como código Terraform
2. ✅ Permitir evolução incremental sem downtime
3. ✅ Viabilizar testes locais antes de aplicar na AWS
4. ✅ Expandir de 2 AZs (us-east-1a, us-east-1b) para 3 AZs (+ us-east-1c)

## Pré-requisitos

### Ferramentas Necessárias

```bash
# Verificar instalações
aws --version       # AWS CLI v2.33.4+
terraform --version # Terraform v1.14.3+
jq --version       # jq 1.7+
```

### Credenciais AWS

```bash
# Configurar credenciais
aws configure

# Validar
aws sts get-caller-identity
```

### Permissões AWS Necessárias

- `ec2:Describe*` (leitura de VPC, subnets, NAT, IGW, route tables)
- `ec2:CreateSubnet` (criação de subnets - apenas script incremental)
- `ec2:CreateNatGateway` (criação de NAT - opcional)
- `ec2:AllocateAddress` (alocação de EIP - opcional)
- `ec2:CreateRouteTable` (criação de route tables)
- `ec2:CreateTags` (tagging de recursos)

## Scripts Disponíveis

### 1. Engenharia Reversa (`00-marco0-reverse-engineer-vpc.sh`)

**Propósito:** Extrair configuração atual da VPC e gerar Terraform equivalente.

**Uso:**

```bash
cd platform-provisioning/aws/scripts
./00-marco0-reverse-engineer-vpc.sh
```

**Output:**

```
vpc-reverse-engineered/
├── terraform/              # Código Terraform modular
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── vpc/
│       ├── subnets/
│       ├── nat-gateways/
│       ├── internet-gateway/
│       └── route-tables/
└── docs/                   # JSONs brutos + documentação
    ├── vpc-raw.json
    ├── subnets-raw.json
    ├── nat-gateways-raw.json
    ├── igw-raw.json
    ├── route-tables-raw.json
    ├── README.md
    └── SUMMARY.md
```

**Validação:**

```bash
cd vpc-reverse-engineered/terraform
terraform init
terraform plan  # DEVE mostrar "No changes" (equivalência)
```

**⚠️ IMPORTANTE:** Este script é **READ-ONLY** - não modifica nada na AWS.

---

### 2. Incremental - Adicionar us-east-1c (`01-marco0-incremental-add-region.sh`)

**Propósito:** Adicionar 3ª Availability Zone sem impactar recursos existentes.

**Uso:**

```bash
cd platform-provisioning/aws/scripts
./01-marco0-incremental-add-region.sh
```

**Output:**

```
marco0-incremental-1c/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── subnets-1c/
│       ├── nat-gateway-1c/
│       └── route-tables-1c/
├── Makefile
├── README.md
└── SUMMARY.md
```

**Validação e Deploy:**

```bash
cd marco0-incremental-1c

# Inicializar
make init

# Visualizar mudanças (dry-run)
make plan

# Opção 1: Aplicar SEM NAT dedicado (economia; recomendado)
make apply-no-nat

# Opção 2: Aplicar COM NAT dedicado (HA total; +$32/mês)
make apply-with-nat

# Validar recursos criados
make validate
```

**Recursos Criados:**

| Recurso        | CIDR         | Propósito                |
| -------------- | ------------ | ------------------------ |
| eks-public-1c  | 10.0.42.0/24 | ALB, Ingress Controllers |
| eks-private-1c | 10.0.54.0/24 | EKS Worker Nodes         |
| eks-db-1c      | 10.0.55.0/24 | RDS, ElastiCache         |

**Custo:**

- SEM NAT dedicado: **$0/mês** (usa NAT existente)
- COM NAT dedicado: **+$32/mês** (~R$ 192/mês)

---

## Workflow Recomendado

### Fase 1: Engenharia Reversa (WSL - Seguro)

```bash
# 1. Executar script de engenharia reversa
./00-marco0-reverse-engineer-vpc.sh

# 2. Validar Terraform gerado
cd vpc-reverse-engineered/terraform
terraform init
terraform plan  # Revisar equivalência

# 3. Estudar documentação
cat ../docs/SUMMARY.md
cat ../docs/README.md
```

**✅ Esta fase é 100% segura** - apenas leitura da AWS.

---

## Segurança

### ✅ O que é SEGURO fazer no WSL

- ✅ Executar `00-marco0-reverse-engineer-vpc.sh` (read-only)
- ✅ Executar `01-marco0-incremental-add-region.sh` (gera código)
- ✅ `terraform init` (inicializa providers)
- ✅ `terraform plan` (visualiza mudanças planejadas)
- ✅ `terraform validate` (valida sintaxe)
- ✅ Comandos AWS CLI read-only (`describe-*`, `list-*`)

### ❌ O que NÃO fazer no WSL (sem supervisão)

- ❌ `terraform apply` (cria/modifica recursos - risco de duplicação)
- ❌ `make apply-*` (executa terraform apply)
- ❌ Comandos AWS CLI de modificação (`create-*`, `delete-*`, `modify-*`)

---

## Próximos Passos (relacionados ao Marco 0)

## Terraform: Engenharia Reversa da VPC (Marco 0) ✅

### 📋 Visão Geral

Marco 0 estabelece a baseline da infraestrutura AWS usando engenharia reversa da VPC existente, criando um backend Terraform profissional e módulos reutilizáveis.

**Status:** ✅ COMPLETO (2026-01-24)

**Infraestrutura Analisada:**
- VPC: `vpc-0b1396a59c417c1f0` (10.0.0.0/16)
- Subnets: 4 (2 públicas, 2 privadas) em us-east-1a e us-east-1b
- NAT Gateways: 2 (um por AZ)
- Internet Gateway: 1
- Route Tables: 4 (2 públicas, 2 privadas)
- Security Groups: Mapeados
- Account ID: 891377105802

---

### 🏗️ Arquitetura do Backend Terraform

```
┌─────────────────────────────────────────┐
│   S3 Bucket (State Storage)             │
│   terraform-state-marco0-891377105802   │
│   ├─ Versioning: ON                     │
│   ├─ Encryption: AES256                 │
│   ├─ Public Access: BLOCKED             │
│   └─ State: marco0/terraform.tfstate    │
└──────────────┬──────────────────────────┘
               │
               │ State Read/Write
               ▼
┌─────────────────────────────────────────┐
│   DynamoDB Table (State Locking)        │
│   terraform-state-lock                  │
│   ├─ Key: LockID (String)               │
│   ├─ Billing: PAY_PER_REQUEST           │
│   └─ Status: ACTIVE                     │
└─────────────────────────────────────────┘
```

**Custo Estimado:** ~$0.01/mês (praticamente gratuito)

---

### 📂 Estrutura de Diretórios

```
platform-provisioning/aws/kubernetes/
│
├── terraform-backend/                    # Bootstrap do backend
│   ├── create-tf-backend.sh              # ✅ Cria S3 + DynamoDB
│   └── README.md
│
├── terraform/
│   ├── modules/                          # ✅ Módulos reutilizáveis
│   │   ├── vpc/
│   │   ├── subnets/
│   │   ├── nat-gateways/
│   │   ├── internet-gateway/
│   │   ├── route-tables/
│   │   ├── security-groups/
│   │   └── kms/
│   │
│   └── envs/
│       └── marco0/                       # ✅ Ambiente de validação
│           ├── main.tf                   # Orquestra módulos
│           ├── backend.tf                # S3 + DynamoDB config
│           ├── variables.tf              # Variáveis do ambiente
│           ├── outputs.tf                # Outputs importantes
│           ├── terraform.tfvars.example  # Template de valores
│           ├── init-terraform.sh         # ✅ Script de inicialização
│           └── plan-terraform.sh         # ✅ Script de planejamento
│
└── scripts/
    └── setup-terraform-backend.sh

docs/plan/aws-execution/
├── COMANDOS-EXECUTADOS-MARCO0.md         # ✅ Guia completo (20+ páginas)
├── diario-marco0-2026-01-23.md           # ✅ Diário de bordo
└── vpc-reverse-output/                   # JSONs da engenharia reversa
    ├── vpc.json
    ├── subnets.json
    ├── nat-gateways.json
    ├── route-tables.json
    ├── igw.json
    └── security-groups.json
```

---

### 🚀 Guia de Uso

#### 1. Bootstrap do Backend (Executar UMA VEZ)

```bash
cd platform-provisioning/aws/kubernetes/terraform-backend/

# Criar bucket S3 e tabela DynamoDB
./create-tf-backend.sh \
  --bucket terraform-state-marco0-891377105802 \
  --region us-east-1 \
  --yes
```

**O que faz:**
- ✅ Cria bucket S3 com versionamento + criptografia AES256
- ✅ Bloqueia acesso público ao bucket
- ✅ Cria tabela DynamoDB para locking (PAY_PER_REQUEST)
- ✅ Aguarda recursos ficarem prontos

**Output esperado:**
```
[STEP] Creating S3 bucket (if not exists)
  Bucket created: terraform-state-marco0-891377105802
[STEP] Enabling versioning and encryption
[STEP] Blocking public access
[STEP] Creating DynamoDB table for state locking
  Table created: terraform-state-lock
  Waiting for table to become ACTIVE...
  Table is now ACTIVE
[DONE] Backend prepared.
```

---

#### 2. Inicializar Terraform

```bash
cd platform-provisioning/aws/kubernetes/terraform/envs/marco0/

# Opção A: Script automatizado (recomendado)
./init-terraform.sh

# Opção B: Manual
terraform init
```

**O que faz:**
- Carrega credenciais AWS automaticamente
- Verifica identidade (aws sts get-caller-identity)
- Conecta ao backend S3
- Instala providers
- Inicializa módulos

---

#### 3. Validar Configuração

```bash
# Opção A: Script automatizado
./plan-terraform.sh

# Opção B: Manual
terraform plan
```

**Comportamento Esperado:**
- **Plan mostra "will create"** (recursos não foram importados)
- **DECISÃO ARQUITETURAL:** Código serve como blueprint para novos ambientes
- Para gerenciar infra existente, seria necessário importar cada recurso:
  ```bash
  terraform import module.vpc.aws_vpc.vpc vpc-0b1396a59c417c1f0
  terraform import 'module.subnets.aws_subnet.subnets["public-1a"]' subnet-xxx
  # ... (tedioso, 1 comando por recurso)
  ```

---

### 🛠️ Scripts Disponíveis

#### create-tf-backend.sh
**Correções aplicadas:**
- ✅ Fix para us-east-1 (não usa LocationConstraint)
- ✅ Verificação de recursos existentes
- ✅ Aguarda tabela DynamoDB ficar ACTIVE

#### init-terraform.sh (Novo)
**Funcionalidades:**
- Carrega credenciais do cache AWS CLI (`~/.aws/login/cache/*.json`)
- Suporta credenciais SSO/STS temporárias
- Verifica identidade antes de executar
- Executa terraform init

#### plan-terraform.sh (Novo)
**Funcionalidades:**
- Carrega credenciais automaticamente
- Executa terraform plan
- Suporta argumentos: `./plan-terraform.sh -out=tfplan`

---

### 📖 Documentação Detalhada

**Guia Completo (20+ páginas):**
[docs/plan/aws-execution/COMANDOS-EXECUTADOS-MARCO0.md](docs/plan/aws-execution/COMANDOS-EXECUTADOS-MARCO0.md)

**Conteúdo:**
- ✅ Todos os comandos AWS CLI explicados em detalhes
- ✅ Parâmetros de cada comando (o que faz, por que é importante)
- ✅ Diagrams de funcionamento do backend S3/DynamoDB
- ✅ Análise de custos detalhada ($0.01/mês)
- ✅ Troubleshooting completo com soluções
- ✅ Tipos de credenciais AWS (IAM vs STS vs SSO)
- ✅ Lock mechanism explicado
- ✅ Problemas encontrados e correções aplicadas

**Diário de Bordo:**
[docs/plan/aws-execution/diario-marco0-2026-01-23.md](docs/plan/aws-execution/diario-marco0-2026-01-23.md)

---

### ⚠️ Problemas Comuns e Soluções

#### 1. InvalidLocationConstraint (us-east-1)
**Erro:**
```
InvalidLocationConstraint: The specified location-constraint is not valid
```

**Causa:** us-east-1 não aceita `LocationConstraint`

**Solução:** Script corrigido com condicional para us-east-1

---

#### 2. No valid credential sources found
**Erro:**
```
Error: No valid credential sources found
```

**Solução:**
```bash
# Exportar credenciais manualmente
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."  # Obrigatório para STS (ASIA...)

# Ou usar scripts automatizados
./init-terraform.sh
```

---

#### 3. State Lock Timeout
**Erro:**
```
Error acquiring the state lock
Lock Info: ID: xxxxx-xxxx-xxxx
```

**Solução:**
```bash
# Verificar quem está com lock
aws dynamodb get-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"terraform-state-marco0-891377105802/marco0/terraform.tfstate-md5"}}'

# Force unlock (CUIDADO! Só use se tiver certeza que nenhum processo está rodando)
terraform force-unlock <LOCK_ID>
```

---

### 📊 Recursos AWS Criados

| Recurso        | Nome                                | Configuração                       | Custo/Mês   |
| -------------- | ----------------------------------- | ---------------------------------- | ----------- |
| S3 Bucket      | terraform-state-marco0-891377105802 | Versioning + AES256 + Public Block | ~$0.00002   |
| DynamoDB Table | terraform-state-lock                | LockID (String), PAY_PER_REQUEST   | ~$0.0000125 |
| **TOTAL**      |                                     |                                    | **~$0.01**  |

---

### ✅ Validações Executadas

- ✅ Bucket S3 criado com versionamento
- ✅ Criptografia AES256 habilitada
- ✅ Public access bloqueado
- ✅ Tabela DynamoDB criada e ACTIVE
- ✅ Terraform init com backend remoto funcional
- ✅ State file criado no S3
- ✅ Lock mechanism testado (force-unlock executado)
- ✅ Scripts corrigidos e funcionais
- ✅ Documentação completa (20+ páginas)

---

### 🎯 Próximos Passos

#### Opção 1: Importar Infraestrutura Existente
```bash
# Importar recursos para gerenciá-los via Terraform
terraform import module.vpc.aws_vpc.vpc vpc-0b1396a59c417c1f0
# ... (repetir para todos os recursos)
```

#### Opção 2: Usar como Blueprint (Recomendado)
```bash
# Criar novo ambiente usando os módulos
cp -r envs/marco0 envs/staging
# Ajustar terraform.tfvars e criar nova infraestrutura
```

#### Opção 3: Adicionar Módulo EKS
```bash
# Criar módulos para EKS cluster
modules/eks-cluster/
modules/eks-node-groups/
```

---

### 📝 Commits Relacionados

1. **420b043** - feat: add Marco 0 VPC reverse engineering and Terraform infrastructure
2. **d5e4c95** - docs: update Marco 0 diary with commit and governance consolidation
3. **df4c1ea** - feat: bootstrap Terraform backend and configure Marco 0 environment
4. **4c8fba7** - docs: add comprehensive Marco 0 documentation and fix scripts

1. ✅ Atualizar EKS Node Groups para usar 3 AZs
2. ✅ Adicionar us-east-1c aos DB Subnet Groups (RDS, ElastiCache)
3. ✅ Testar distribuição de pods em 3 AZs
4. ✅ Documentar no [diário de bordo](docs/plan/aws-execution/00-diario-de-bordo.md)
5. ⏳ Seguir para Sprint 1: Networking Foundation

- [Log de Progresso](docs/logs/log-de-progresso.md) - Histórico completo

---

## 🚀 Como Começar

### Para IA/Copilot
1. Ler [Copilot Context](ai-contexts/copilot-context.md)
2. Consultar [ADR-001](docs/adr/adr-001-setup-e-governanca.md) e [ADR-002](docs/adr/adr-002-estrutura-de-dominios.md)
3. Verificar [Execution Plan](docs/plan/execution-plan.md) para próximos passos
4. Sempre usar [Orchestrator Guide](docs/prompts/orchestrator-guide.md) como referência

### Para Humanos
1. Ler este README
2. Consultar [Context Generator](docs/context/context-generator.md)
3. Revisar [ADRs](docs/adr/)
4. Seguir [Execution Plan](docs/plan/execution-plan.md)

---

## 📊 Status Atual

### Fases
- ✅ **FASE 0**: Setup do Sistema (100%)
- ⏳ **FASE 1**: Concepção do SAD (0%)
- ⏳ **FASE 2**: Criação dos Domínios (0%)
- ⏳ **FASE 3**: Execução por Domínio (0%)
- ⏳ **FASE 4**: Integração e Validação (0%)
- ⏳ **FASE 5**: Documentação e Handover (0%)

### Progresso Geral
**16.7%** (FASE 0 concluída)

---

## 🎯 Próximos Passos

1. **Iniciar FASE 1**: Concepção do SAD
2. Criar `/SAD/docs/sad.md` com decisões sistêmicas
3. Criar ADRs sistêmicos (003-008)
4. Definir regras de herança (`/SAD/docs/architecture/inheritance-rules.md`)
5. Definir contratos entre domínios (`/SAD/docs/architecture/domain-contracts.md`)
6. **SAD FREEZE** 🔒

### Lacunas Identificadas na Mesa Técnica (DevOps/DevSecOps/SRE)
Após mesa técnica com especialistas, foram identificadas as seguintes lacunas críticas (considerando marco zero sem legado):

1. **Compliance Regulatória**: Adicionar auditoria automática, data residency e zero-trust networking para GDPR/HIPAA.
2. **Testes de Carga e Performance**: Incluir na FASE 4, com ferramentas como K6 ou Locust para validar escalabilidade.
3. **Disaster Recovery**: Procedures para backup cross-region e failover automático (Velero + multi-region).
4. **Multi-Cloud Deployment**: Estratégia para portabilidade e alta disponibilidade entre clouds.
5. **FinOps (Gestão de Custos)**: Estratégia dedicada para orçamento, monitoramento e otimização de custos.
6. **Multi-Tenancy para Equipes**: Isolamento por equipe dentro de domínios (namespaces, quotas).
7. **Escalabilidade Vertical**: Estratégia para vertical scaling (CPU/memory limits, HPA vertical).
8. **Integração com Ferramentas Externas**: Integração com Jira (tickets), Slack (notificações), etc.
9. **Treinamento de Equipes**: Capacitação em Kubernetes, IaC, observabilidade.
10. **Governança de Mudanças**: Processo para mudanças manuais ou emergenciais.

### ADRs Sugeridos
- **ADR-007**: Service Mesh (Linkerd recomendado por custo e simplicidade).
- **ADR-013**: Disaster Recovery (Velero + multi-region backup).
- **ADR-014**: Compliance Regulatória (auditoria e zero-trust).
- **ADR-015**: Multi-Tenancy (isolamento por equipe).
- **ADR-016**: Escalabilidade Vertical.
- **ADR-017**: Integrações Externas (Jira, Slack).
- **ADR-018**: Treinamento e Capacitação.

---

## 🛠️ Stack Tecnológica

### Core
- **Orquestração**: Kubernetes (EKS/GKE/AKS/on-prem)
- **IaC**: Terraform (módulos multi-cloud)
- **CD**: Helm, Kustomize, ArgoCD/Flux
- **Containers**: Docker, containerd

### Domínios
Ver seção [Domínios](#-domínios) acima

---

## 📝 Regras de Ouro

1. **Consultar ADRs** antes de qualquer mudança
2. **Nunca agir sem contexto** validado
3. **Decisões exigem rastreabilidade** (ADR + commit + log)
4. **SAD é a fonte suprema** após FASE 1
5. **Isolamento de domínios** é obrigatório

### Frase de Controle Global
> **Se uma ação não puder ser rastreada em documentos, logs ou commits, ela NÃO deve ser executada.**

---

## 🤖 Metodologia AI-First

Este projeto foi desenvolvido usando a metodologia **AI-First** do projeto iPaaS:
- Governança rigorosa com ADRs obrigatórios
- Hooks pre/post para todas as ações
- Agentes especializados (Gestor, Arquiteto, Architect Guardian, SRE)
- Prompts operacionais para cada tipo de tarefa
- Rastreabilidade total (logs, commits estruturados)

---

## 🧾 Scripts AWS — Marco 1

### Scripts de Gerenciamento do Cluster EKS - Marco 1

Scripts para ligar/desligar o cluster EKS e gerenciar custos da infraestrutura AWS.

## 📋 Scripts Disponíveis

### 1. `status-cluster.sh` - Verificar Status e Custos

Verifica o status atual do cluster e calcula custos estimados.

```bash
./status-cluster.sh
```

**Saída:**
- Status do cluster (ACTIVE, DESLIGADO, etc.)
- Informações dos node groups
- Total de nodes
- Custos estimados (hora/dia/mês)
- Status do kubectl

### 2. `shutdown-cluster.sh` - Desligar Cluster

Destrói completamente o cluster EKS para economia de custos.

```bash
./shutdown-cluster.sh
```

**O que destrói:**
- ✅ Cluster EKS k8s-platform-prod
- ✅ 7 nodes EC2 (2 system + 3 workloads + 2 critical)
- ✅ 4 add-ons (CoreDNS, VPC CNI, Kube-proxy, EBS CSI Driver)
- ✅ Security Groups e KMS Key

**O que NÃO destrói:**
- ❌ VPC fictor-vpc e subnets
- ❌ NAT Gateways (2) e Internet Gateway
- ❌ IAM Roles

**Economia:** ~$0.76/hora (~$547/mês)

**Tempo:** ~3-5 minutos

**Backup:** Cria backup automático do state em `~/.terraform-backups/marco1/`

### 3. `startup-cluster.sh` - Ligar Cluster

Recria o cluster EKS via Terraform (100% conformidade IaC).

```bash
./startup-cluster.sh
```

**O que cria:**
- ✅ Cluster EKS k8s-platform-prod (Kubernetes 1.31)
- ✅ 7 nodes EC2 (2 system + 3 workloads + 2 critical)
- ✅ 4 add-ons (CoreDNS, VPC CNI, Kube-proxy, EBS CSI Driver)
- ✅ Security Groups e KMS Key
- ✅ Configura kubectl automaticamente

**Tempo:** ~15 minutos

**Custo:** ~$0.76/hora (~$547/mês) enquanto ligado

## 💰 Gestão de Custos

### Custos Estimados (com cluster ligado)

| Recurso          | Custo/hora | Custo/dia  | Custo/mês   |
| ---------------- | ---------- | ---------- | ----------- |
| Cluster EKS      | $0.10      | $2.40      | $73.00      |
| Nodes EC2 (7)    | $0.66      | $15.84     | $475.20     |
| NAT Gateways (2) | $0.09      | $2.16      | $65.70      |
| **TOTAL**        | **$0.85**  | **$20.40** | **$613.90** |

### Custos Estimados (com cluster desligado)

| Recurso          | Custo/hora | Custo/dia | Custo/mês  |
| ---------------- | ---------- | --------- | ---------- |
| NAT Gateways (2) | $0.09      | $2.16     | $65.70     |
| **TOTAL**        | **$0.09**  | **$2.16** | **$65.70** |

**Economia com shutdown:** ~$0.76/hora (~$18.24/dia, ~$548.20/mês)

### Estratégia Recomendada

1. **Desenvolvimento Ativo (dias úteis):**
  - Ligar cluster pela manhã: `./startup-cluster.sh`
  - Desligar cluster à noite: `./shutdown-cluster.sh`
  - Economia: ~50% (~$300/mês)

2. **Desenvolvimento Intermitente:**
  - Ligar apenas quando necessário
  - Desligar após uso
  - Economia: ~70-80% (~$400-450/mês)

3. **Produção 24/7:**
  - Manter cluster ligado
  - Implementar Auto Scaling para otimizar custos
  - Considerar Reserved Instances ou Savings Plans

## 🔧 Uso Diário Recomendado

### Início do Dia de Trabalho

```bash
# 1. Verificar status atual
./status-cluster.sh

# 2. Se desligado, ligar cluster
./startup-cluster.sh

# 3. Aguardar ~15 minutos
# 4. Cluster estará pronto para uso
```

### Fim do Dia de Trabalho

```bash
# 1. Salvar todo trabalho importante
# 2. Fazer commit de código no Git
# 3. Desligar cluster
./shutdown-cluster.sh

# 4. Aguardar ~3-5 minutos
# 5. Confirmar destruição
./status-cluster.sh
```

## 🔐 Pré-requisitos

### AWS CLI e Credenciais

```bash
# Verificar se credenciais estão válidas
aws sts get-caller-identity --profile k8s-platform-prod

# Se expirado, fazer login novamente
aws sso login --profile k8s-platform-prod
```

### Terraform

```bash
# Terraform deve estar instalado
terraform version

# Deve mostrar: Terraform v1.14.3 ou superior
```

### kubectl (opcional, mas recomendado)

```bash
# kubectl deve estar instalado para validações
kubectl version --client

# Deve mostrar: Client Version: v1.34.1 ou superior
```

## 📊 Logs e Troubleshooting

### Localização dos Logs

- **Shutdown:** `/tmp/terraform-shutdown-YYYYMMDD_HHMMSS.log`
- **Startup:** `/tmp/terraform-startup-YYYYMMDD_HHMMSS.log`
- **Backups State:** `~/.terraform-backups/marco1/terraform.tfstate.backup.YYYYMMDD_HHMMSS`

### Problemas Comuns

#### 1. Erro: "Lock already exists"

```bash
# Identificar Lock ID no erro
# Desbloquear manualmente
cd ../
terraform force-unlock <LOCK_ID>
```

#### 2. Erro: "Credenciais expiradas"

```bash
# Renovar credenciais AWS
aws sso login --profile k8s-platform-prod
```

#### 3. Erro: "Timeout during shutdown"

```bash
# Verificar recursos manualmente no Console AWS
# Ou tentar novamente
./shutdown-cluster.sh
```

#### 4. Erro: "kubectl não conecta"

```bash
# Reconfigurar kubectl
aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod --profile k8s-platform-prod
```

## 🎯 Conformidade IaC

Todos os scripts seguem 100% conformidade com Infrastructure as Code:

- ✅ Usa exclusivamente Terraform para criar/destruir recursos
- ✅ State gerenciado remotamente no S3 com locking DynamoDB
- ✅ Backups automáticos do state antes de operações destrutivas
- ✅ Logs completos de todas as operações
- ✅ Idempotente: pode executar múltiplas vezes com segurança

## 📝 Notas Importantes

1. **NAT Gateways** continuam gerando custos (~$65/mês) mesmo com cluster desligado
  - Para economia total, seria necessário destruir a VPC também
  - Não recomendado pois perde a infraestrutura de rede

2. **IAM Roles** não geram custos, são mantidos entre shutdowns/startups

3. **Terraform State** é mantido no S3, garantindo rastreabilidade completa

4. **Tempo de startup** pode variar:
  - Mínimo: 12-13 minutos (cluster + nodes + add-ons)
  - Máximo: 18-20 minutos (se houver contenção de recursos AWS)

5. **Dados persistentes**: Qualquer dado armazenado em PVCs será perdido no shutdown
  - Fazer backup de dados importantes antes de desligar

## 🚀 Próximos Passos

Para otimização adicional de custos:

1. Implementar Spot Instances para node groups não-críticos
2. Configurar Cluster Autoscaler para dimensionamento automático
3. Implementar Karpenter para otimização avançada de nodes
4. Configurar AWS Instance Scheduler para automação de start/stop
5. Considerar Reserved Instances para workloads 24/7

## 📖 Referências

- [AWS EKS Pricing](https://aws.amazon.com/eks/pricing/)
- [EC2 On-Demand Pricing](https://aws.amazon.com/ec2/pricing/on-demand/)
- [NAT Gateway Pricing](https://aws.amazon.com/vpc/pricing/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)


## 📞 Suporte

Para questões sobre:
- **Governança e Método**: Consultar [ADR-001](docs/adr/adr-001-setup-e-governanca.md)
- **Estrutura de Domínios**: Consultar [ADR-002](docs/adr/adr-002-estrutura-de-dominios.md)
- **Próximas Ações**: Consultar [Execution Plan](docs/plan/execution-plan.md)
- **Contexto Completo**: Consultar [Copilot Context](ai-contexts/copilot-context.md)

---

## 📜 Licença

*(Definir conforme necessário)*

---

**Projeto iniciado em**: 2025-12-30
**Metodologia**: AI-First (iPaaS)
**Mantenedor**: gilvangalindo

## 🧩 Scripts — Plataforma Completa (envs/scripts)

Este diretório contém scripts para gerenciar o ciclo completo da plataforma Kubernetes (Marco 1 + Marco 2).

Principais scripts:

- `status-full-platform.sh`: status completo (EKS, ALB Controller, Cert-Manager, ClusterIssuers, custos)
- `startup-full-platform.sh`: liga cluster + platform services (~20 min)
- `shutdown-full-platform.sh`: desliga cluster mantendo states (~6 min)

Use os scripts em `envs/scripts/` para o workflow diário (ligar/desligar plataforma completa). Use os scripts em `marco1/scripts/` apenas para operações específicas do cluster EKS.
