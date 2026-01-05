# ADR 002 — Estrutura de Domínios Multi-Kubernetes

## Data
2025-12-30

## Status
Aprovado ✅

## Contexto
O projeto Kubernetes atua como **plataforma corporativa de engenharia**, gerenciando 6 domínios especializados: platform-core (fundação), cicd-platform (esteira DevOps), observability (monitoramento), data-services (databases/cache/mensageria), secrets-management (cofre), security (policies/runtime).

Cada domínio possui responsabilidades específicas e deve evoluir de forma independente, mantendo isolamento rigoroso e contratos explícitos.

## Problema
Como organizar 6 domínios especializados de plataforma corporativa garantindo:
- Isolamento e autonomia
- Integração via contratos explícitos
- Padrões compartilhados (IaC, observabilidade, segurança)
- Rastreabilidade e governança
- Facilidade de manutenção e evolução independente

## Decisões

### 1. Estrutura de Domínios em `/domains`

Cada domínio terá estrutura padronizada:

```
/domains/{domain-name}/
├── docs/               # Documentação do domínio
│   ├── context/
│   │   └── domain-context.md
│   ├── adr/            # ADRs específicos do domínio
│   ├── plan/
│   │   └── execution-plan.md
│   ├── runbooks/       # Runbooks operacionais
│   └── logs/
│       └── log-de-progresso.md
├── infra/              # Infraestrutura como Código
│   ├── terraform/      # Módulos Terraform
│   ├── helm/           # Helm charts
│   └── configs/        # Configs adicionais
├── local-dev/          # Ambiente local Docker
│   ├── docker-compose.yml
│   └── README.md
└── contexts/           # Contextos para AI
    └── copilot-context.md
```

### 2. Domínios da Plataforma Corporativa

#### 1. platform-core
**Responsabilidade**: Infraestrutura base (gateway, autenticação, service mesh, certificados)
**Stack**: Kong (API Gateway), Keycloak (auth), Istio ou Linkerd (service mesh), cert-manager, NGINX
**Namespaces**: `platform-core`, `kong-system`, `keycloak`, `istio-system`
**Contratos**: Fornece autenticação, roteamento e isolamento para todos os domínios
**Status**: Planejado (FASE 2)

#### 2. cicd-platform
**Responsabilidade**: Esteira CI/CD completa e governança de aplicações
**Stack**: GitLab (Git + CI), SonarQube (qualidade), ArgoCD (CD), Backstage Spotify (Developer Portal)
**Namespaces**: `cicd`, `gitlab`, `sonarqube`, `argocd`, `backstage`
**Contratos**: 
- Backstage cria repos no GitLab
- GitLab CI executa build + SonarQube scan
- ArgoCD faz deploy no Kubernetes
- Integração com secrets-management para injeção de credenciais
**Status**: Planejado (FASE 2) — **Primeiro Objetivo**

#### 3. observability
**Responsabilidade**: Coleta, armazenamento e visualização de métricas, logs e traces
**Stack**: OpenTelemetry Collector (central), Prometheus, Grafana, Loki, Tempo, Kiali
**Namespaces**: `observability`, `monitoring`, `logging`, `tracing`
**Contratos**: 
- Todos os domínios enviam métricas/logs/traces para OpenTelemetry Collector
- Fornece dashboards Grafana e Kiali para consumo
- Exporta alertas via Alertmanager
**Status**: Migrado do projeto Observabilidade existente ✅

#### 4. data-services
**Responsabilidade**: Databases, cache, mensageria gerenciados (DBaaS, CacheaaS, MQaaS)
**Stack**: PostgreSQL (HA + replicação), Redis (cluster), RabbitMQ (HA), Velero (backup), Prometheus Exporters, Alertmanager
**Namespaces**: `data-services`, `postgres`, `redis`, `rabbitmq`
**Contratos**:
- Fornece PostgreSQL databases sob demanda (via Operator)
- Fornece Redis clusters para cache/sessões
- Fornece RabbitMQ queues/exchanges
- Backup automatizado via Velero
- Métricas enviadas para observability
**Status**: Planejado (FASE 3)

#### 5. secrets-management
**Responsabilidade**: Cofre centralizado de secrets integrado com CI/CD
**Stack**: HashiCorp Vault ou External Secrets Operator, rotação automática, auditoria de acesso
**Namespaces**: `secrets`, `vault-system`
**Contratos**:
- cicd-platform injeta secrets automaticamente em pipelines
- Aplicações consomem via CSI driver ou init containers
- Rotação automática de credenciais
- Auditoria de acessos
**Status**: Planejado (FASE 3)
**Decisão Pendente**: Mesa técnica sobre armazenar secrets na imagem vs external

#### 6. security
**Responsabilidade**: Políticas, runtime security, RBAC, compliance, vulnerability scanning
**Stack**: OPA ou Kyverno (policies), Falco (runtime), Trivy (CI/CD scanning), RBAC centralizado, Network Policies
**Namespaces**: `security`, `policy-system`, `falco`
**Contratos**:
- cicd-platform integra Trivy no pipeline
- Falco monitora runtime em todos os namespaces
- OPA/Kyverno valida policies em todos os deploys
- Network Policies aplicadas por namespace
**Status**: Planejado (FASE 4)

### 3. Regras de Isolamento

**Isolamento Obrigatório:**
- Namespaces Kubernetes separados
- RBAC por domínio (ServiceAccounts, Roles)
- Network Policies para controle de tráfego
- Resource Quotas e Limits

**Comunicação Entre Domínios:**
- Apenas via contratos documentados (ver seção 2)
- Sem dependências diretas de código/infra
- APIs/interfaces explícitas quando necessário
- Exemplos de contratos:
  - cicd-platform ← secrets-management (injeção de secrets)
  - * → observability (métricas/logs/traces)
  - cicd-platform ← platform-core (autenticação via Keycloak)
  - data-services → observability (métricas de bancos)

### 4. Herança do SAD

Todos os domínios herdam decisões sistêmicas do SAD central:
- **Cloud-agnostic OBRIGATÓRIO**: Sem recursos nativos de cloud (AWS RDS, GCP Cloud SQL, etc.)
- **IaC Padrão**: Terraform (módulos reutilizáveis) + Helm (charts versionados)
- **Segurança Base**: RBAC, Network Policies, Pod Security Standards obrigatórios
- **Observabilidade Base**: Instrumentação OpenTelemetry, exporters Prometheus obrigatórios
- **Documentação Padrão**: Estrutura `/docs` com context, adr, plan, logs, runbooks
- **Backup**: Velero para stateful workloads
- **Governança AI**: Todos seguem metodologia AI-First (hooks, ADRs, rastreabilidade)

### 5. Criação de Novos Domínios

Para criar um novo domínio:
1. Validar necessidade (não pode ser absorvido por domínio existente)
2. Criar ADR sistêmico em `/SAD/docs/adrs/`
3. Definir contratos com outros domínios
4. Seguir estrutura padrão em `/domains/{nome}/`
5. Documentar contexto e plano
6. Validar com Architect Guardian
7. Commit: `[domain]: create {nome} domain`

### 6. Evolução de Domínios

Cada domínio evolui de forma independente:
- Plano próprio em `/domains/{domain}/docs/plan/`
- Logs próprios em `/domains/{domain}/docs/logs/`
- ADRs locais em `/domains/{domain}/docs/adr/`
- Mas sempre respeitando SAD central

## Alternativas Consideradas

### Alternativa 1: Monorepo Sem Domínios
**Rejeita**: Dificulta isolamento e cresceria de forma desordenada

### Alternativa 2: Repositórios Separados
**Rejeita**: Dificulta governança centralizada e padrões compartilhados

### Alternativa 3: Domínios como Git Submodules
**Rejeita**: Complexidade adicional de gerenciar submodules

## Consequências

### Positivas
- Isolamento claro entre domínios
- Autonomia para evoluir independentemente
- Facilita onboarding de novos domínios
- Reduz complexidade cognitiva (foco em um domínio por vez)
- Facilita testes isolados

### Negativas
- Estrutura pode parecer pesada inicialmente
- Requer disciplina para manter isolamento
- Potencial duplicação de código/infra entre domínios

### Riscos
- Domínios podem criar acoplamento não autorizado
- Mitigação: Architect Guardian valida contratos

## Métricas de Sucesso
- ✅ Domínios podem ser desenvolvidos/testados independentemente
- ✅ Mudanças em um domínio não quebram outros (contratos mantidos)
- ✅ Novos domínios podem ser adicionados sem refatoração da estrutura base
- ✅ Audit de isolamento passa sem violações (namespaces, RBAC, Network Policies)
- ✅ Backstage cataloga aplicações de todos os domínios
- ✅ CI/CD pipeline Python end-to-end funciona (cicd-platform)
- ✅ OpenTelemetry coleta dados de todos os domínios (observability)
- ✅ Data services fornecem PostgreSQL/Redis/RabbitMQ com HA + backup
- ✅ Secrets injetados automaticamente via cofre (secrets-management)
- ✅ Policies OPA/Kyverno validam deploys em todos os domínios (security)

## Aprovações
- [x] Usuário (gilvangalindo)
- [x] Architect Guardian
- [x] Copilot (executando)
