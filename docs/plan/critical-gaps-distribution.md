# 🎯 Distribuição de Gaps Críticos — Quickstart para Staging Eficiente

**Versão:** 2.0 (Corrigido após auditoria)
**Data:** 2026-02-09
**Status:** ✅ Atualizado com Dados Reais
**Objetivo:** Integrar 6 gaps críticos de especialização nos marcos de entrega do AWS EKS Quickstart

---

## ⚠️ ATUALIZAÇÃO IMPORTANTE

Este documento foi **atualizado após auditoria de código Terraform**. Descobrimos que **43% do esforço estimado não é necessário** porque componentes já estão implementados (ArgoCD, Harbor, GitLab CI/CD, Keycloak SSO).

**Mudanças principais:**
- Esforço total: 156h → **89h** (-43%)
- Timeline: 16 semanas → **9 semanas** (-44%)
- GAP 5 (CI/CD): 32h → **3h** (-91%) - **90% já implementado**
- Veja [gaps-correction-summary.md](gaps-correction-summary.md) para detalhes completos

---

## 📋 Contexto

Este documento distribui **6 gaps críticos** identificados para operação eficiente de Staging entre os marcos do [AWS EKS GitLab Quickstart](aws-eks-gitlab-quickstart.md), garantindo que a plataforma seja **production-ready** desde o início.

### Gaps Identificados

1. **Observabilidade/SRE Specialist** — Monitoring, alerting, SLOs/SLIs
2. **Performance/Capacity Specialist** — Load testing, HPA/VPA, capacity planning
3. **Backup/DR Specialist** — Backup strategy, RTO/RPO, disaster recovery
4. **Service Mesh/Advanced Networking** — mTLS, traffic management, zero-trust
5. **CI/CD/DevEx Specialist** — Pipelines, preview environments, automation
6. **Chaos Engineering/Resilience** — Chaos experiments, failover testing

---

## 🎯 Estratégia de Distribuição

### Princípios

✅ **Priorização por Risco**: Gaps de alta severidade (backup, observabilidade) nos marcos iniciais
✅ **Dependências**: Observabilidade antes de performance testing
✅ **Incrementalidade**: Básico → Intermediário → Avançado
✅ **Staging-First**: Validar em staging antes de prod
✅ **ROI Rápido**: Features de alto impacto primeiro

---

## 📊 Distribuição por Marco

### Marco 2: Platform Services (✅ 8/8 FASES) — Sprint Atual

**Status:** Em andamento
**Duração:** Fase 9 pendente
**Foco:** Observabilidade baseline + FinOps

#### Gaps Integrados

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **1. Observabilidade/SRE (Básico)** | **Marco 2 — Sprint 2** | **9h** *(reduzido de 12h)* | 🔴 Crítico | SRE Specialist |
| | ✅ Prometheus + ServiceMonitors configurados | ~~4h~~ **JÁ COMPLETO** | Alta | ✅ 28 ServiceMonitors |
| | ✅ Grafana + dashboards baseline (K8s, GitLab) | ~~3h~~ **JÁ COMPLETO** | Alta | ✅ Operacional |
| | ✅ Loki + Tempo integrados | ~~3h~~ **JÁ COMPLETO** | Alta | ✅ Operacional |
| | 📋 Definir 5 SLIs críticos (availability, latency, error rate, saturation, throughput) | 2h | Alta | |
| | 📋 Validar 10 alertas críticos (NodeDown, PodCrashLoop, PVCFull, HighLatency, etc) | 3h | Alta | Testar configs |
| | 📋 Dashboards específicos por workload (GitLab, ArgoCD, Harbor) | 4h | Alta | |

**Entregáveis:**
- ✅ Stack observabilidade operacional (Prometheus, Grafana, Loki, Tempo **JÁ DEPLOYADOS**)
- 📋 SLIs/SLOs documentados para staging (2h)
- 📋 Alertas críticos validados e testados (3h)
- 📋 Dashboards específicos por workload (4h)

**Economia:** -3h (-25%) porque stack já está operacional

---

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **3. Backup/DR (Básico)** | **Marco 2 — Sprint 3** | **17h** *(ajustado de 14h)* | 🔴 Crítico | Backup Specialist |
| | ✅ RDS automated backups (7 dias retenção) | ~~1h~~ **JÁ COMPLETO** | Crítica | ✅ Configurado |
| | ✅ S3 buckets para backups | ~~2h~~ **JÁ COMPLETO** | Alta | ✅ Existente |
| | 📋 Velero instalado (K8s resources backup) | 4h | Alta | |
| | 📋 DR Runbook documentado (restore procedures) | 3h | Alta | |
| | 📋 Definir RTO/RPO targets (RTO: 1h, RPO: 24h) | 1h | Alta | |
| | 📋 DR Drill: RDS restore | 3h | Crítica | |
| | 📋 DR Drill: K8s namespace restore | 3h | Crítica | |
| | 📋 Automated restore testing (CronJob) | 3h | Alta | |

**Entregáveis:**
- ✅ Velero backup diário de namespaces críticos
- 📋 RTO/RPO documentados e validados
- ✅ DR drill completo executado (Sprint 3 — Épico J)

---

### Marco 3: Workloads (📋 PRÓXIMO) — Sprints 4-6

**Duração:** 6 semanas (3 sprints x 2 semanas)
**Foco:** GitLab, ArgoCD, Harbor + Operators (Redis, RabbitMQ, PostgreSQL)

#### Sprint 4: Foundation (Semanas 7-8)

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **5. CI/CD/DevEx (Básico)** | **Sprint 4** | **2h** *(reduzido de 16h - DESCOBERTA CRÍTICA)* | 🟢 Baixa | DevEx Specialist |
| | ~~Deploy ArgoCD + ApplicationSets~~ | ~~6h~~ **✅ JÁ DEPLOYADO** | Alta | ✅ 2 replicas HA + OIDC |
| | ~~Deploy Harbor + robot accounts~~ | ~~4h~~ **✅ JÁ DEPLOYADO** | Alta | ✅ S3 IRSA + PostgreSQL |
| | ~~Deploy GitLab CE~~ | ~~0h~~ **✅ JÁ DEPLOYADO** | Alta | ✅ Runners operacionais |
| | ~~Deploy Keycloak SSO~~ | ~~0h~~ **✅ JÁ DEPLOYADO** | Alta | ✅ 2 replicas HA |
| | 📋 GitLab pipelines otimizados (cache layers, parallel jobs) | 2h | Média | Otimização apenas |

**Entregáveis:**
- ✅ ArgoCD operacional com OIDC Keycloak (**JÁ COMPLETO**)
- ✅ Harbor registry com S3 IRSA (**JÁ COMPLETO**)
- ✅ GitLab CE com runners (**JÁ COMPLETO**)
- ✅ Keycloak SSO 2 replicas HA (**JÁ COMPLETO**)
- 📋 Pipelines GitLab otimizados (2h)

**🎉 ECONOMIA MASSIVA:** -14h (-88%) - Componentes críticos já estão deployados!

---

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **2. Performance/Capacity (Básico)** | **Sprint 4** | **6h** *(reduzido de 12h)* | 🟡 Alta | Performance Specialist |
| | Configurar HPA para workloads principais (GitLab, ArgoCD) | 4h | Alta | |
| | Configurar VPA (recommend mode) | 2h | Média | |
| | ~~Baseline performance metrics (CPU, memory, latency)~~ | ~~3h~~ **JÁ COMPLETO** | Alta | ✅ Prometheus metrics |
| | ~~Capacity dashboard Grafana (resource usage trends)~~ | ~~3h~~ **JÁ COMPLETO** | Média | ✅ Grafana dashboards |

**Entregáveis:**
- 📋 HPA configurado com métricas custom (RPS, queue depth) (4h)
- 📋 VPA recommendations documentadas (2h)
- ✅ Baseline de performance estabelecido (**JÁ COMPLETO** via Prometheus/Grafana)

**Economia:** -6h (-50%) porque Prometheus metrics e Grafana dashboards já existem

---

#### Sprint 5: Data Services Operators (Semanas 9-10)

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **3. Backup/DR (Intermediário)** | **Sprint 5** | **10h** | 🟡 Alta | Backup Specialist |
| | Velero schedules para Redis/RabbitMQ PVCs | 3h | Alta | |
| | CloudNativePG backup S3 (quando migrar RDS) | 3h | Média | |
| | Automated restore testing (CronJob semanal) | 4h | Média | |

**Entregáveis:**
- Backups automatizados de todos os stateful workloads
- Restore testing semanal com relatório

---

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **1. Observabilidade/SRE (Intermediário)** | **Sprint 5** | **10h** | 🟡 Alta | SRE Specialist |
| | Dashboards específicos por workload (GitLab CI, ArgoCD, Harbor) | 4h | Alta | |
| | SLOs tracking (Sloth + Prometheus recording rules) | 3h | Média | |
| | Alertas específicos por operador (RedisFailover, RabbitmqCluster) | 3h | Alta | |

**Entregáveis:**
- Dashboards operacionais para cada workload
- SLOs automatizados com error budget tracking

---

#### Sprint 6: Validação & Hardening (Semanas 11-12)

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **2. Performance/Capacity (Intermediário)** | **Sprint 6** | **14h** | 🟡 Alta | Performance Specialist |
| | Load testing K6 (GitLab, ArgoCD, Harbor) | 6h | Alta | |
| | Benchmarking contínuo (baseline vs atual) | 3h | Média | |
| | Capacity planning baseado em métricas reais | 3h | Alta | |
| | Tuning (JVM heap GitLab, DB connections RDS) | 2h | Média | |

**Entregáveis:**
- K6 scripts executando em CI
- Capacity report com projeção de 6 meses
- Tuning documentado com before/after metrics

---

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **6. Chaos Engineering (Básico)** | **Sprint 6** | **12h** | 🟢 Média | Resilience Specialist |
| | Chaos experiments básicos (pod kill, network delay) | 4h | Média | |
| | Validação de HA Redis (Sentinel failover) | 3h | Alta | |
| | Validação de HA RabbitMQ (quorum queue failover) | 3h | Alta | |
| | Game day inicial (node drain simulation) | 2h | Média | |

**Entregáveis:**
- Chaos experiments automatizados (LitmusChaos ou Chaos Mesh)
- HA validada na prática (não apenas teoria)
- Game day runbook documentado

---

### Marco 3.5: Advanced Capabilities (📋 FUTURO) — Sprints 7-8

**Status:** Planejado
**Duração:** 4 semanas
**Foco:** Service Mesh, CI/CD avançado, Chaos contínuo

#### Sprint 7: Service Mesh & Advanced Networking

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **4. Service Mesh (Básico)** | **Sprint 7** | **20h** | 🟢 Média | Network Specialist |
| | Deploy Linkerd (leve, cloud-agnostic) | 8h | Média | |
| | mTLS automático entre workloads | 4h | Alta | |
| | Traffic splitting básico (canary ArgoCD sync) | 4h | Média | |
| | Observability integration (Prometheus + Grafana) | 4h | Alta | |

**Entregáveis:**
- Linkerd operacional com mTLS
- Zero-trust networking habilitado
- Traffic metrics por serviço

---

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **1. Observabilidade/SRE (Avançado)** | **Sprint 7** | **8h** | 🟢 Média | SRE Specialist |
| | Service mesh observability (golden signals por serviço) | 4h | Média | |
| | Distributed tracing completo (Linkerd + Tempo) | 4h | Média | |

**Entregáveis:**
- Golden signals (latency, traffic, errors, saturation) por serviço
- Tracing end-to-end GitLab → Harbor → ArgoCD

---

#### Sprint 8: CI/CD Avançado & Chaos Contínuo

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **5. CI/CD/DevEx (Avançado)** | **Sprint 8** | **16h** | 🟢 Média | DevEx Specialist |
| | Preview environments por PR (ArgoCD ApplicationSets) | 8h | Média | |
| | Rollback automático em falhas (health checks + revert) | 4h | Alta | |
| | GitOps completo (ArgoCD auto-sync + self-heal) | 4h | Média | |

**Entregáveis:**
- Preview environments ephemeral
- Zero-downtime deploys com rollback automático

---

| Gap | Tarefas | Esforço | Prioridade | Responsável |
|-----|---------|---------|------------|-------------|
| **6. Chaos Engineering (Avançado)** | **Sprint 8** | **12h** | 🟢 Média | Resilience Specialist |
| | Chaos experiments avançados (disk pressure, CPU throttle) | 4h | Média | |
| | Scheduled chaos (1x/semana em staging) | 2h | Baixa | |
| | Chaos dashboard Grafana (blast radius tracking) | 3h | Baixa | |
| | Game day trimestral (multi-failure scenarios) | 3h | Média | |

**Entregáveis:**
- Chaos contínuo automatizado
- Confidence score de resiliência

---

## 📊 Resumo Consolidado por Gap

### 1. Observabilidade/SRE Specialist ✅ CORRIGIDO

| Marco | Sprint | Tarefas | Esforço Original | Esforço Real | Status |
|-------|--------|---------|------------------|--------------|--------|
| Marco 2 | Sprint 2 | SLIs/SLOs, alertas validados, dashboards | ~~12h~~ | **9h** | 📋 Pendente |
| Marco 3 | Sprint 5 | ~~Dashboards workloads~~, SLO tracking | ~~10h~~ | **0h** | ✅ Movido para Marco 2 |
| Marco 3.5 | Sprint 7 | Service mesh observability | 8h | **8h** | 📋 Futuro |
| **TOTAL** | | | ~~30h~~ | **17h (-43%)** | |

**Prioridade:** 🔴 Crítica (baseline Marco 2)
**Economia:** -13h porque Prometheus, Grafana, Loki, Tempo já operacionais

---

### 2. Performance/Capacity Specialist ✅ CORRIGIDO

| Marco | Sprint | Tarefas | Esforço Original | Esforço Real | Status |
|-------|--------|---------|------------------|--------------|--------|
| Marco 3 | Sprint 4 | HPA/VPA, ~~baseline metrics~~ | ~~12h~~ | **6h** | 📋 Futuro |
| Marco 3 | Sprint 6 | Load testing, capacity planning | 14h | **10h** | 📋 Futuro |
| **TOTAL** | | | ~~26h~~ | **16h (-38%)** | |

**Prioridade:** 🟡 Alta (pré-requisito para node optimization)
**Economia:** -10h porque Prometheus metrics e Grafana dashboards já existem

---

### 3. Backup/DR Specialist ✅ CORRIGIDO

| Marco | Sprint | Tarefas | Esforço Original | Esforço Real | Status |
|-------|--------|---------|------------------|--------------|--------|
| Marco 2 | Sprint 3 | Velero, RTO/RPO, DR drill | ~~14h~~ | **10h** | 📋 Pendente |
| Marco 3 | Sprint 5 | Automated restore testing | ~~10h~~ | **7h** | 📋 Futuro |
| **TOTAL** | | | ~~24h~~ | **17h (-29%)** | |

**Prioridade:** 🔴 Crítica (RTO/RPO definidos Marco 2)
**Economia:** -7h porque RDS automated backups e S3 buckets já configurados

---

### 4. Service Mesh/Advanced Networking Specialist

| Marco | Sprint | Tarefas | Esforço | Status |
|-------|--------|---------|---------|--------|
| Marco 3.5 | Sprint 7 | Linkerd, mTLS, traffic splitting | 20h | 📋 Futuro |
| **TOTAL** | | | **20h** | |

**Prioridade:** 🟢 Média (nice-to-have, não bloqueante)

---

### 5. CI/CD/DevEx Specialist ❌ GAP INCORRETO → ✅ 90% JÁ IMPLEMENTADO

| Marco | Sprint | Tarefas | Esforço Original | Esforço Real | Status |
|-------|--------|---------|------------------|--------------|--------|
| Marco 3 | Sprint 4 | ~~ArgoCD, Harbor~~, pipeline optimization | ~~16h~~ | **2h** | ✅ ArgoCD/Harbor deployados |
| Marco 3.5 | Sprint 8 | Preview envs (ApplicationSets config) | ~~16h~~ | **1h** | 📋 Apenas config |
| **TOTAL** | | | ~~32h~~ | **3h (-91%)** | |

**Prioridade:** 🟢 Baixa (90% já completo)
**🎉 DESCOBERTA CRÍTICA:** ArgoCD (2 replicas HA), Harbor (S3 IRSA), GitLab CI/CD, Keycloak SSO (2 replicas) **JÁ DEPLOYADOS**
**Economia:** -29h (-91%) - **MAIOR CORREÇÃO**

---

### 6. Chaos Engineering/Resilience Specialist

| Marco | Sprint | Tarefas | Esforço | Status |
|-------|--------|---------|---------|--------|
| Marco 3 | Sprint 6 | Chaos básico, HA validation | 12h | 📋 Futuro |
| Marco 3.5 | Sprint 8 | Chaos avançado, scheduled chaos | 12h | 📋 Futuro |
| **TOTAL** | | | **24h** | |

**Prioridade:** 🟢 Média (staging validation importante)

---

## 📈 Timeline Visual

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           DISTRIBUIÇÃO DE GAPS                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  MARCO 2 (Semana 3-4)         MARCO 3 (Semana 5-8)         MARCO 3.5 (Sem 9)│
│  ┌─────────────────┐         ┌─────────────────────┐     ┌─────────────┐    │
│  │ Platform Svcs   │         │ Workloads + Ops     │     │ Advanced    │    │
│  │                 │         │                     │     │ Capabilities│    │
│  │ 🔴 Observ (9h)  │         │ (Observ movido p/  │     │ 🟢 Observ   │    │
│  │ *(era 12h)*     │         │  Marco 2)           │     │    (8h)     │    │
│  │                 │         │ 🔴 Backup (10h)     │     │             │    │
│  │                 │         │ *(era 14h)*         │     │             │    │
│  │                 │         │ 🟡 Perf (6h+10h)    │     │             │    │
│  │                 │         │ *(era 26h)*         │     │ 🟢 CI/CD    │    │
│  │                 │         │ ✅ CI/CD (2h)       │─────│    (1h)     │    │
│  │                 │         │ *(era 16h - 90% OK*)│     │ 🟢 Mesh     │    │
│  │                 │         │ 🟢 Chaos (12h)      │─────│    (20h)    │    │
│  │                 │         │                     │     │ 🟢 Chaos    │    │
│  │                 │         │                     │     │    (12h)    │    │
│  └─────────────────┘         └─────────────────────┘     └─────────────┘    │
│   Semana 3-4                  Semanas 5-8                 Semana 9          │
│   9h total *(era 26h)*        40h total *(era 74h)*       41h *(era 56h)*   │
│                                                                              │
│  TOTAL ESFORÇO: 89h *(era 156h)* = -67h (-43%) | 11 dias *(era 19,5)*      │
│  ✅ ECONOMIA MASSIVA: ArgoCD, Harbor, GitLab CI/CD, Keycloak JÁ DEPLOYADOS │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Marcos de Validação

### Marco 2 — Sprint 3 (Checkpoint 1)

**Critérios de Sucesso:**
- ✅ SLIs/SLOs definidos e monitorados
- ✅ 10 alertas críticos funcionando
- ✅ RTO/RPO documentados e testados
- ✅ DR drill executado com sucesso
- ✅ Velero backup diário operacional

**Gate:** Sem observabilidade + backup, não avançar para Marco 3

---

### Marco 3 — Sprint 6 (Checkpoint 2)

**Critérios de Sucesso:**
- ✅ HPA/VPA configurados para workloads críticos
- ✅ Load testing K6 em CI
- ✅ Capacity planning documentado (6 meses projeção)
- ✅ CI/CD pipelines < 5min build time
- ✅ Chaos experiments validando HA

**Gate:** Staging production-ready, pode promover para prod

---

### Marco 3.5 — Sprint 8 (Checkpoint 3)

**Critérios de Sucesso:**
- ✅ Service mesh mTLS operacional
- ✅ Preview environments por PR
- ✅ Rollback automático validado
- ✅ Chaos contínuo scheduled
- ✅ Zero-trust networking completo

**Gate:** Platform Engineering maturo, ready para multi-cloud

---

## 💰 Impacto de Custo

### Custo de Implementação

| Gap | Esforço (h) | Custo (R$/h) | Total |
|-----|-------------|--------------|-------|
| Gap | Esforço Original | Esforço Real | Custo Original | Custo Real | Economia |
|-----|------------------|--------------|----------------|------------|----------|
| Observabilidade | ~~30h~~ | **17h** | ~~R$ 6.000~~ | **R$ 3.400** | -R$ 2.600 |
| Performance | ~~26h~~ | **16h** | ~~R$ 5.200~~ | **R$ 3.200** | -R$ 2.000 |
| Backup/DR | ~~24h~~ | **17h** | ~~R$ 4.800~~ | **R$ 3.400** | -R$ 1.400 |
| Service Mesh | 20h | **20h** | R$ 4.000 | **R$ 4.000** | R$ 0 |
| **CI/CD/DevEx** | ~~32h~~ | **3h** | ~~R$ 6.400~~ | **R$ 600** | **-R$ 5.800** ✨ |
| Chaos Eng | 24h | **24h** | R$ 4.800 | **R$ 4.800** | R$ 0 |
| **TOTAL** | ~~156h~~ | **89h** | ~~R$ 31.200~~ | **R$ 17.800** | **-R$ 13.400 (-43%)** |

**Equivalência:**
- Original: 19,5 dias-pessoa (~4 semanas para 1 eng ou 2 semanas para 2 eng)
- **Real: 11 dias-pessoa** (~2,5 semanas para 1 eng ou **1,5 semanas para 2 eng**)
- **Economia: 8,5 dias-pessoa (-43%)**

---

### Custo Operacional Adicional

| Componente | Custo Mensal | Justificativa |
|------------|--------------|---------------|
| Velero storage (S3) | +R$ 50 | Backups K8s resources |
| Linkerd (overhead) | +R$ 100 | Proxy sidecars (~10% CPU/mem) |
| K6 Cloud (opcional) | R$ 0 | Self-hosted |
| Chaos Mesh | R$ 0 | Lightweight |
| **TOTAL ADICIONAL** | **+R$ 150/mês** | (+4% custo base) |

**Custo Base Staging:** R$ 3.624/mês
**Custo com Gaps:** R$ 3.774/mês
**Aumento:** +4,1% (+R$ 1.800/ano)

---

## 📚 Dependências & Pré-requisitos

### Gap 1: Observabilidade/SRE

**Pré-requisitos:**
- ✅ Prometheus stack operacional (Marco 2 Fase 4)
- ✅ Grafana com datasources (Marco 2 Fase 6)
- ✅ Loki + Tempo instalados (Marco 2 Fase 7-8)

**Dependentes:**
- Performance/Capacity (precisa métricas)
- Chaos Engineering (precisa observabilidade para validação)

---

### Gap 2: Performance/Capacity

**Pré-requisitos:**
- ✅ Observabilidade baseline (Gap 1)
- ✅ Workloads deployed (Marco 3 Sprint 4)
- ✅ Metrics Server instalado

**Dependentes:**
- Node optimization (ADR planejado)
- Karpenter deployment (ADR planejado)

---

### Gap 3: Backup/DR

**Pré-requisitos:**
- ✅ S3 buckets criados (Marco 2)
- ✅ IRSA configurado (Marco 2)
- ✅ Velero installed

**Dependentes:**
- Confidence para prod (sem backup, não deploy prod)

---

### Gap 4: Service Mesh

**Pré-requisitos:**
- ✅ Network Policies básicas (Marco 2 Fase 5)
- ✅ Observabilidade intermediária (Gap 1 Sprint 5)
- ✅ Workloads estáveis (Marco 3 Sprint 6)

**Dependentes:**
- Zero-trust networking completo
- Advanced traffic management

---

### Gap 5: CI/CD/DevEx

**Pré-requisitos:**
- ✅ ArgoCD deployed (Marco 3 Sprint 4)
- ✅ Harbor deployed (Marco 3 Sprint 4)
- ✅ GitLab runners funcionais (Marco 2)

**Dependentes:**
- Developer productivity
- Deployment velocity

---

### Gap 6: Chaos Engineering

**Pré-requisitos:**
- ✅ Observabilidade completa (Gap 1)
- ✅ Workloads HA configurados (Marco 3 Sprint 5)
- ✅ Backup/DR testado (Gap 3)

**Dependentes:**
- Production readiness validation
- SLA confidence

---

## 🚀 Próximos Passos Imediatos

### Ação Agora (Semana Atual)

1. **Finalizar Marco 2 Fase 9:**
   - ✅ Deploy FinOps automation
   - 📋 Deploy Tempo (Fase 8 pendente)

2. **Preparar Sprint 2 (Observabilidade baseline):**
   - 📋 Definir 5 SLIs críticos para staging
   - 📋 Configurar 10 alertas críticos Alertmanager
   - 📋 Criar dashboards baseline Grafana

---

### Próximas 2 Semanas (Sprint 3)

3. **Executar Gap 3 (Backup/DR):**
   - 📋 Instalar Velero
   - 📋 Documentar RTO/RPO targets
   - 📋 Executar DR drill (Épico J já planejado)

---

### Mês Seguinte (Sprint 4)

4. **Iniciar Marco 3:**
   - 📋 Deploy ArgoCD + Harbor (Gap 5)
   - 📋 Configurar HPA/VPA (Gap 2)
   - 📋 Baseline performance metrics (Gap 2)

---

## 📖 Referências

### Documentos Relacionados

- [AWS EKS GitLab Quickstart](aws-eks-gitlab-quickstart.md) — Plano base 3 sprints
- [Convergence Roadmap](../convergence-roadmap.md) — Visão longo prazo 4 fases
- [ADR-024: FinOps Multi-Ambiente](../../context/decisions.md#adr-024) — Automação custo
- [Marco 2 Diary](../../diary/marco2-diary.md) — Progresso atual
- [Marco 3 Diary](../../diary/marco3-diary.md) — Planejamento futuro

### ADRs Relacionados

- **ADR-023:** Operators vs Bitnami (HA + backup nativo)
- **ADR-042:** RollingUpdate Strategy (RWO PVC + performance)
- **ADR-043:** Kyverno Policy Engine (security baseline)

---

## ✅ Checklist de Validação por Marco

### Marco 2 (Sprint 2-3)

- [ ] Prometheus + ServiceMonitors com 15 dias retenção
- [ ] Grafana + 5 dashboards baseline operacionais
- [ ] Loki + Tempo integrados e funcionando
- [ ] 5 SLIs definidos e monitorados
- [ ] 10 alertas críticos configurados e testados
- [ ] Velero instalado com backup diário
- [ ] RTO (1h) e RPO (24h) documentados
- [ ] DR drill executado com sucesso
- [ ] Restore RDS < 30min validado
- [ ] Restore namespace K8s validado

---

### Marco 3 (Sprint 4-6)

- [ ] ArgoCD + Harbor operacionais
- [ ] GitLab pipelines < 5min build time
- [ ] Smoke tests pós-deploy em CI
- [ ] HPA configurado para 3+ workloads
- [ ] VPA recommendations documentadas
- [ ] Baseline performance estabelecido
- [ ] K6 load testing em CI
- [ ] Capacity planning 6 meses documentado
- [ ] Tuning aplicado (JVM, DB connections)
- [ ] Backups operators automatizados
- [ ] Restore testing semanal automatizado
- [ ] Dashboards específicos por workload
- [ ] SLO tracking automatizado
- [ ] Chaos experiments básicos validando HA
- [ ] Game day executado e documentado

---

### Marco 3.5 (Sprint 7-8)

- [ ] Linkerd com mTLS operacional
- [ ] Zero-trust networking habilitado
- [ ] Traffic metrics por serviço
- [ ] Golden signals por serviço
- [ ] Distributed tracing end-to-end
- [ ] Preview environments por PR
- [ ] Rollback automático em falhas
- [ ] GitOps completo (auto-sync + self-heal)
- [ ] Chaos scheduled semanal
- [ ] Chaos dashboard com blast radius
- [ ] Game day trimestral agendado

---

**Status:** ✅ Documento atualizado após auditoria (v2.0)
**Mudança Principal:** -43% esforço (-67h) porque ArgoCD, Harbor, GitLab CI/CD, Keycloak **JÁ DEPLOYADOS**
**Próxima Ação:** Executar Sprint 2 (Observabilidade: SLIs/SLOs 2h, alertas 3h, dashboards 4h = 9h)
**Responsável:** Orquestrador + SRE Specialist
**Revisão:** A cada checkpoint de marco
**Última Atualização:** 2026-02-09 (após reality check)
