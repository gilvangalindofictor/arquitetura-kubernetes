# Projeto Kubernetes - Plataforma Corporativa de Engenharia

> **Metodologia**: AI-First (adaptado do projeto iPaaS)
> **Fase Atual**: 2 (Implementação de Domínios) 🔄
> **Status SAD**: v1.2 🔒 CONGELADO (Freeze #3 - 2026-01-05)
> **Última Atualização**: 2026-01-05
> **Primeiro Objetivo**: Esteira CI/CD completa (GitLab + SonarQube + ArgoCD + Backstage)
> **Orquestrador**: Kubernetes (ADR-021) - escolhido por cloud-agnostic + ecossistema maduro
> **Cloud Recomendada**: Azure (CTO) - $7,381.44/ano (on-demand), $4,428.86/ano (RI 3-year)

> 📘 **CONTEXTO CONSOLIDADO**: Ver [PROJECT-CONTEXT.md](PROJECT-CONTEXT.md) para documentação completa e atualizada

---

## 📋 Visão Geral

**Projeto Kubernetes** é uma **plataforma corporativa de engenharia robusta e escalável** usando Kubernetes como base de articulação tecnológica do departamento, gerenciando **6 domínios especializados**:

1. **platform-core**: Fundação (Kong, Keycloak, Service Mesh, cert-manager)
2. **cicd-platform**: Esteira CI/CD (GitLab, SonarQube, ArgoCD, Backstage) — **🎯 Primeiro Objetivo**
3. **observability**: Monitoramento full-stack (OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Kiali)
4. **data-services**: DBaaS, CacheaaS, MQaaS (PostgreSQL, Redis, RabbitMQ com HA e backup)
5. **secrets-management**: Cofre centralizado (Vault)
6. **security**: Policies, runtime, compliance (OPA/Kyverno, Falco, Trivy)

**Características**:
- ✅ **Orquestrador: Kubernetes** - Escolhido vs Docker Swarm, Nomad, ECS, Cloud Run (ADR-021)
- ✅ **Cloud-Agnostic OBRIGATÓRIO** - Sem recursos nativos de cloud
- ✅ **Escalabilidade Multi-Domínio** - Cada domínio evolui independentemente
- ✅ **Governança Centralizada** - SAD como fonte suprema, ADRs obrigatórios
- ✅ **Rastreabilidade Total** - Hooks, logs, commits estruturados
- ✅ **Isolamento** - Namespaces, RBAC, Network Policies, Service Mesh por domínio

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

**Status**: Aguardando FASE 2

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

Scripts para engenharia reversa e expansão incremental da VPC existente.

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

# Opção 1: Aplicar SEM NAT dedicado (economia, recomendado)
make apply-no-nat

# Opção 2: Aplicar COM NAT dedicado (HA total, +$32/mês)
make apply-with-nat

# Validar recursos criados
make validate
```

**Recursos Criados:**

| Recurso | CIDR | Propósito |
|---------|------|-----------|
| eks-public-1c | 10.0.42.0/24 | ALB, Ingress Controllers |
| eks-private-1c | 10.0.54.0/24 | EKS Worker Nodes |
| eks-db-1c | 10.0.55.0/24 | RDS, ElastiCache |

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
