# Plano de Execução AWS - Índice Geral

**Versão:** 1.1
**Data:** 2026-01-20
**Baseado em:** [AWS EKS GitLab Quickstart](../quickstart/aws-eks-gitlab-quickstart.md)
**Metodologia:** CLI-First (Terraform/AWS CLI) + Helm/kubectl + Console AWS como referência

> ⚠️ **Abordagem CLI-First:** Todos os documentos foram atualizados para oferecer:
> 1. **Terraform** (IaC recomendado) para provisionamento reproduzível
> 2. **AWS CLI** para execução via terminal
> 3. **Console AWS** apenas como referência visual
>
> 📊 Veja a [Análise CLI-First](00-analise-cli-first.md) para detalhes das melhorias.

---

## 📊 Estado Atual da Implementação (2026-01-29)

> **NOTA:** Este documento representa o **plano base original** (épicos A-I). A implementação real evoluiu para um roadmap de 8 semanas com mudanças estratégicas.

### Marco 2: Platform Services - ✅ COMPLETO

**Fases Deployadas (100%):**
- ✅ Fase 1: AWS Load Balancer Controller (v1.11.0)
- ✅ Fase 2: Cert-Manager (v1.16.3)
- ✅ Fase 3: Kube-Prometheus-Stack (13 pods, 3 PVCs)
- ✅ Fase 4: Loki + Fluent Bit (15 pods, S3 backend)
- ✅ Fase 5: Network Policies (11 políticas, Calico)
- ✅ Fase 6: Cluster Autoscaler (IRSA configurado)
- ✅ Fase 7: Test Applications (4 pods, 2 ALBs)

**Fase Planejada:**
- 📝 Fase 8: OpenTelemetry Tempo + Collector (ADR-020 aprovado)

**Custo Atual:** $666/mês | **Projetado com Fase 8:** $685.70/mês

### Marco 3: Workloads - 📝 PLANEJADO (8 Semanas)

**Mudança Estratégica (ADR-021):** Implementação em 2 fases
- **Fase 1 (Semanas 1-8):** Sem domínio, LoadBalancer (NLB) para databases, ALB DNS HTTP para workloads
- **Fase 2 (Futuro):** TLS/HTTPS + Keycloak SSO após registro de domínio

**Mudança Estratégica (ADR-023):** Migration from Bitnami Charts to Kubernetes Operators
- **Motivação:** Evitar licenciamento Bitnami Tanzu Standard ($72,000/ano) + HA superior + cloud-agnostic
- **Redis:** Spotahome Redis Operator (RedisFailover CRD, Sentinel-based HA)
- **RabbitMQ:** RabbitMQ Cluster Operator oficial (RabbitmqCluster CRD, Quorum Queues)
- **Economia:** $72,900/ano vs alternativa Bitnami Tanzu Standard
- **Impacto:** Sprint 1 +4h (88h→92h), Épico C +4h (20h→24h)

**Sequência Atualizada:**
1. Semanas 1-2: OpenTelemetry Tempo + Collector (Fase 8)
2. Semanas 3-5: Data Services (PostgreSQL RDS, Redis, RabbitMQ)
3. Semanas 6-8: Workloads (GitLab, ArgoCD, Harbor)

**Custo Projetado Marco 3:** $737.10/mês (com otimizações Reserved Instances -$165.20/mês)

### Documentação Atualizada

| Documento | Status |
|-----------|--------|
| [architecture.md](../../context/architecture.md) | ✅ Atualizado (Fase 8, Marco 3 estratégia) |
| [decisions.md](../../context/decisions.md) | ✅ Atualizado (ADR-020, ADR-021) |
| [costs.md](../../context/costs.md) | ✅ Atualizado (Fase 8 $19.70/mês, Marco 3 breakdown) |
| [00-diario-de-bordo.md](00-diario-de-bordo.md) | ✅ Atualizado (Versão 1.11 - Mudança estratégica) |
| [04-observability-stack.md](04-observability-stack.md) | ✅ Atualizado (Fases 1-7 completas, Fase 8 planejada) |
| **Plano Executivo 8 Semanas** | ✅ [~/.claude/plans/wild-wiggling-treasure.md](~/.claude/plans/wild-wiggling-treasure.md) |

---

## Visão Geral (Plano Base Original)

Este conjunto de documentos transforma o **AWS EKS GitLab Quickstart** em um **guia de execução passo a passo** extremamente detalhado, permitindo que qualquer pessoa com acesso ao console AWS consiga executar a implementação.

### Escopo

| Aspecto | Descrição |
|---------|-----------|
| **Ambientes** | Staging (scheduled 8h-18h) + Prod (24/7) |
| **Duração** | 3 Sprints (6 semanas) |
| **Esforço** | 266 person-hours (92h + 84h + 90h) |
| **Custo Mensal** | ~R$ 3.624 (USD $604) |
| **Região AWS** | us-east-1 (N. Virginia) |

### Princípios

- **CLI-First**: Terraform/AWS CLI para reprodutibilidade e automação (Console apenas como referência)
- **Cloud-Agnostic onde possível**: Redis e RabbitMQ via **Kubernetes Operators**, não serviços gerenciados (ADR-023: economia de $72,900/ano vs Bitnami Tanzu Standard)
- **Security by Design**: Network Policies, RBAC, WAF, least-privilege desde o dia 1
- **Testes e Validação**: Scripts de validação automatizados em cada fase
- **FinOps integrado**: Budgets, alertas, automação start/stop

---

## Mapa dos Documentos

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SPRINT 1 (92h) - Semanas 1-2                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │
│  │ 01-INFRAESTRUTURA   │  │ 02-GITLAB           │  │ 03-DATA-SERVICES    │ │
│  │ BASE AWS            │  │ HELM DEPLOY         │  │ OPERATORS           │ │
│  │                     │  │                     │  │                     │ │
│  │ Épico A (20h)       │  │ Épico B (48h)       │  │ Épico C (24h)       │ │
│  │ • VPC Multi-AZ      │──▶ • GitLab CE Helm   │──▶ • RDS PostgreSQL   │ │
│  │ • EKS Cluster       │  │ • Runners           │  │ • Redis Operator    │ │
│  │ • Node Groups       │  │ • Route53 + ALB     │  │ • RabbitMQ Operator │ │
│  │ • IAM/IRSA          │  │ • S3 Backups        │  │ • ADR-023 (FinOps)  │ │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        SPRINT 2 (84h) - Semanas 3-4                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                    04-OBSERVABILITY STACK                              │ │
│  │                                                                        │ │
│  │  Épico D (34h)          Épico E (28h)           Épico F (22h)         │ │
│  │  ┌──────────────┐       ┌──────────────┐        ┌──────────────┐      │ │
│  │  │ OTEL         │       │ Logs         │        │ Visualization│      │ │
│  │  │ Collector    │──────▶│ Loki         │───────▶│ Grafana      │      │ │
│  │  │ Prometheus   │       │ Tempo        │        │ Alertmanager │      │ │
│  │  └──────────────┘       └──────────────┘        └──────────────┘      │ │
│  │                                                                        │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        SPRINT 3 (90h) - Semanas 5-6                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │
│  │ 05-SECURITY         │  │ 06-BACKUP           │  │ 07-FINOPS           │ │
│  │ HARDENING           │  │ DISASTER RECOVERY   │  │ AUTOMAÇÃO           │ │
│  │                     │  │                     │  │                     │ │
│  │ Épico G (30h)       │  │ Épico H (24h)       │  │ Transversal         │ │
│  │ • Network Policies  │  │ • Velero            │  │ • Budgets           │ │
│  │ • WAF/IP Allowlist  │  │ • S3 Backups        │  │ • Cost Explorer     │ │
│  │ • RBAC              │  │ • Épico J (10h)     │  │ • Start/Stop Auto   │ │
│  │ • cert-manager      │  │ • DR Drill          │  │ • Alertas           │ │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                    08-VALIDAÇÃO E CHECKLIST                            │ │
│  │                                                                        │ │
│  │  Épico I (26h)                                                        │ │
│  │  • Smoke Tests              • Definition of Done por Sprint           │ │
│  │  • Testes End-to-End        • Critérios de "Pronto para Produção"     │ │
│  │  • Knowledge Transfer       • Checklists de Validação                 │ │
│  │                                                                        │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Documentos Detalhados

### Documento de Análise (CLI-First)

| # | Documento | Descrição |
|---|-----------|-----------|
| 00 | [Análise CLI-First](00-analise-cli-first.md) | Avaliação dos documentos vs critérios CLI-first, Security by Design e Automação |

### Sprint 1 - Preparação e GitLab Mínimo (92h)

| # | Documento | Épico | Horas | Conteúdo Principal |
|---|-----------|-------|-------|-------------------|
| 01 | [Infraestrutura Base AWS](01-infraestrutura-base-aws.md) | A | 20h | VPC, EKS, Node Groups, IAM, Storage (**CLI/Terraform**) |
| 02 | [GitLab Helm Deploy](02-gitlab-helm-deploy.md) | B | 48h | GitLab CE, Runners, Route53, ALB, S3 |
| 03 | [Data Services Operators](03-data-services-helm.md) | C | 24h | RDS PostgreSQL, **Redis Operator** (Spotahome), **RabbitMQ Operator** (Cluster Operator) - **ADR-023**: Economia $72,900/ano vs Bitnami Tanzu |

**Definition of Done Sprint 1:**
- [ ] VPC com 3 AZs operacional
- [ ] EKS cluster acessível via kubectl
- [ ] GitLab UI via HTTPS funcional
- [ ] Pipeline básico rodando
- [ ] Redis e RabbitMQ operacionais

---

### Sprint 2 - Observability Baseline (84h)

| # | Documento | Épicos | Horas | Conteúdo Principal | Status |
|---|-----------|--------|-------|-------------------|--------|
| 04 | [Observability Stack](04-observability-stack.md) | D, E, F | 84h | OTEL, Prometheus, Loki, Tempo, Grafana | 🟡 75% |

**Definition of Done Sprint 2:**
- [x] Métricas de todos os pods no Prometheus ✅ (Fase 3: Prometheus Stack)
- [ ] Logs centralizados no Loki ⏳ (Fase 4: Código pronto, aguardando deploy)
- [ ] Traces no Tempo ⏳ (Pendente)
- [x] Dashboards baseline no Grafana ✅ (Fase 3: 30+ dashboards)
- [x] Alertas críticos configurados ✅ (Fase 3: Alertmanager)

**Status Atual (2026-01-28):**
- ✅ **Fase 3 (Prometheus Stack):** COMPLETO - 13 pods monitoring, 30+ dashboards
- 📝 **Fase 4 (Loki + Fluent Bit):** CÓDIGO IMPLEMENTADO - Aguardando deploy
- ⏳ **Fase 5 (Tempo):** PENDENTE

---

### Sprint 3 - Hardening, Network & Smoke Tests (90h)

| # | Documento | Épicos | Horas | Conteúdo Principal |
|---|-----------|--------|-------|-------------------|
| 05 | [Security Hardening](05-security-hardening.md) | G | 30h | Network Policies, WAF, RBAC, cert-manager (**CLI/Terraform**) |
| 06 | [Backup e DR](06-backup-disaster-recovery.md) | H, J | 34h | Velero, AWS Backup, DR Drill |
| 07 | [FinOps e Automação](07-finops-automacao.md) | - | - | Budgets, Alertas, Start/Stop |
| 08 | [Validação e Checklist](08-validacao-checklist.md) | I | 26h | Smoke Tests, DoD, Handoff |

**Definition of Done Sprint 3:**
- [ ] Network Policies deny-all aplicadas
- [ ] WAF + IP allowlist configurados
- [ ] Backup restaurado com sucesso
- [ ] DR Drill executado (RTO < 1h)
- [ ] Knowledge transfer realizado

---

## Pré-requisitos

### Acessos Necessários

| Recurso | Nível de Acesso | Para Quê |
|---------|-----------------|----------|
| **Console AWS** | Administrator ou PowerUser | Criar todos os recursos |
| **AWS CLI** | Credenciais configuradas | Operações via terminal |
| **kubectl** | Instalado localmente | Gerenciar cluster EKS |
| **Helm 3.x** | Instalado localmente | Deploy de charts |
| **Domínio DNS** | Acesso ao registrador | Configurar nameservers Route53 |

### Conhecimentos Recomendados

| Área | Nível | Observação |
|------|-------|------------|
| AWS Console | Básico | Navegação, criação de recursos |
| Kubernetes | Básico | Conceitos de pods, deployments, services |
| Helm | Básico | Instalar/atualizar charts |
| Git | Básico | Clone, commit, push |
| Linux/Bash | Básico | Comandos básicos de terminal |

---

## Arquitetura Resumida

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS CLOUD (us-east-1)                          │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                           VPC (10.0.0.0/16)                            │ │
│  │                                                                        │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐    │ │
│  │  │ Public Subnet 1a │  │ Public Subnet 1b │  │ Public Subnet 1c │    │ │
│  │  │ NAT + ALB        │  │                  │  │                  │    │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘    │ │
│  │                                                                        │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐    │ │
│  │  │ Private Subnet   │  │ Private Subnet   │  │ Private Subnet   │    │ │
│  │  │ EKS Nodes        │  │ EKS Nodes        │  │ EKS Nodes        │    │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘    │ │
│  │                                                                        │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐    │ │
│  │  │ Data Subnet      │  │ Data Subnet      │  │ Data Subnet      │    │ │
│  │  │ RDS PostgreSQL   │  │ RDS PostgreSQL   │  │ RDS PostgreSQL   │    │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘    │ │
│  │                                                                        │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                         EKS CLUSTER                                    │ │
│  │                                                                        │ │
│  │  Node Groups:                                                          │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                   │ │
│  │  │ system      │  │ workloads   │  │ critical    │                   │ │
│  │  │ t3.medium   │  │ t3.large    │  │ t3.xlarge   │                   │ │
│  │  │ 2 nodes     │  │ 2-6 nodes   │  │ 2-4 nodes   │                   │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                   │ │
│  │                                                                        │ │
│  │  Namespaces:                                                           │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │ │
│  │  │ staging     │  │ prod        │  │ observa-    │  │ kube-system │  │ │
│  │  │ GitLab      │  │ GitLab      │  │ bility      │  │ AWS LB Ctrl │  │ │
│  │  │ Redis       │  │ Redis HA    │  │ Prometheus  │  │ EBS CSI     │  │ │
│  │  │ RabbitMQ    │  │ RabbitMQ    │  │ Grafana     │  │ cert-manager│  │ │
│  │  └─────────────┘  └─────────────┘  │ Loki/Tempo  │  └─────────────┘  │ │
│  │                                    └─────────────┘                    │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │ RDS         │  │ S3          │  │ Route53     │  │ WAF         │       │
│  │ PostgreSQL  │  │ Buckets     │  │ DNS         │  │ Firewall    │       │
│  │ Multi-AZ    │  │ Backups     │  │             │  │             │       │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Custos Consolidados

| Componente | Mensal (USD) | Mensal (BRL) | Anual (BRL) |
|------------|--------------|--------------|-------------|
| **Staging** (scheduled 50h/sem) | $112 | R$ 672 | R$ 8.064 |
| **Prod** (24/7) | $467 | R$ 2.802 | R$ 33.624 |
| **Observability** (compartilhado) | $25 | R$ 150 | R$ 1.800 |
| **TOTAL** | **$604** | **R$ 3.624** | **R$ 43.488** |

*Cotação: USD 1 = BRL 6,00 (jan/2026)*

---

## Como Usar Esta Documentação

### Ordem de Execução

```
1. Ler este índice completamente
2. Executar Doc 01 (Infraestrutura Base AWS)
3. Validar DoD do Doc 01 antes de prosseguir
4. Executar Doc 02 (GitLab Helm Deploy)
5. Executar Doc 03 (Data Services Helm)
6. Validar DoD Sprint 1
7. Executar Doc 04 (Observability Stack)
8. Validar DoD Sprint 2
9. Executar Docs 05, 06, 07 em paralelo se possível
10. Executar Doc 08 (Validação Final)
11. Validar DoD Sprint 3 e "Pronto para Produção"
```

### Convenções de Documentação

| Símbolo | Significado |
|---------|-------------|
| `Console AWS >` | Navegação no console |
| `kubectl ...` | Comando a executar |
| `values.yaml` | Arquivo de configuração |
| **IMPORTANTE** | Atenção especial necessária |
| `# Comentário` | Explicação do comando |

---

## Relacionamento com Outros Documentos

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DOCUMENTAÇÃO DO PROJETO                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    SAD v1.2 (Congelado)                              │   │
│  │                    Arquitetura Sistêmica                             │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                          │
│                                  ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AWS EKS GitLab Quickstart                         │   │
│  │                    (Estratégia de Alto Nível)                        │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                          │
│                                  ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │           >>> ESTE CONJUNTO DE DOCUMENTOS <<<                        │   │
│  │           Plano de Execução AWS (8 documentos)                       │   │
│  │           (Passo a Passo Detalhado no Console)                       │   │
│  └───────────────────────────────┬─────────────────────────────────────┘   │
│                                  │                                          │
│                                  ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Evolution Strategy                                │   │
│  │                    (Roadmap de Crescimento - 5 Fases)                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Suporte e Dúvidas

- **Documento de referência**: [aws-eks-gitlab-quickstart.md](../quickstart/aws-eks-gitlab-quickstart.md)
- **Evolução futura**: [evolution-strategy.md](../quickstart/evolution-strategy.md)
- **Estimativas de custo**: [cost-estimation.md](../cost-estimation.md)
- **ADRs sistêmicos**: [/SAD/docs/adrs/](../../../SAD/docs/adrs/)

---

**Última atualização:** 2026-01-19
**Próximo documento:** [01-infraestrutura-base-aws.md](01-infraestrutura-base-aws.md)
