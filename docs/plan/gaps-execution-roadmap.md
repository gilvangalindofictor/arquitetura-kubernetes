# 🗺️ Roadmap de Execução — Gaps Críticos para Staging Eficiente

**Versão:** 2.0 (Corrigido após auditoria)
**Data:** 2026-02-09
**Status:** ✅ Atualizado com Dados Reais

---

## ⚠️ ATUALIZAÇÃO IMPORTANTE

Este documento foi **atualizado após auditoria de código Terraform**. Descobrimos que **43% do esforço estimado não é necessário** porque componentes já estão implementados.

**Mudanças principais:**
- Timeline: 16 semanas → **9 semanas** (-44%)
- Esforço: 156h → **89h** (-43%)
- Custo: R$ 31.200 → **R$ 17.800** (-43%)
- GAP 5 (CI/CD): ArgoCD, Harbor, GitLab, Keycloak **JÁ DEPLOYADOS**

---

## 📋 Visão Executiva

Este documento complementa o [Critical Gaps Distribution](critical-gaps-distribution.md) com:
- Roadmap visual de execução semana-a-semana **(CORRIGIDO: 9 semanas)**
- Matriz de responsabilidades RACI
- Grafo de dependências críticas
- Milestones de validação
- Estratégia de paralelização
- **Componentes já implementados** (ArgoCD, Harbor, GitLab, Keycloak, Observability)

---

## 📅 Roadmap Semanal Detalhado

### Semana 3-4: Marco 2 Sprint 2 (Observabilidade Baseline) ✅ CORRIGIDO

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 3-4: Observabilidade/SRE (9h - REDUZIDO DE 12h)         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GAP 1: Observabilidade/SRE (9h)                               │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ ✅ Prometheus + ServiceMonitors          │ JÁ COMPLETO  │   │
│  │ ✅ Grafana + dashboards baseline         │ JÁ COMPLETO  │   │
│  │ ✅ Loki + Tempo integrados               │ JÁ COMPLETO  │   │
│  │ 📋 Definir 5 SLIs críticos               │ 2h │ Dia 1   │   │
│  │ 📋 Validar 10 alertas críticos           │ 3h │ Dia 1-2 │   │
│  │ 📋 Dashboards específicos (workloads)    │ 4h │ Dia 2-3 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • ✅ Stack observabilidade operacional (JÁ COMPLETO)          │
│  • 📋 SLIs/SLOs documentados para staging                      │
│  • 📋 10 alertas críticos validados                            │
│  • 📋 Dashboards específicos por workload                      │
│                                                                 │
│  🎉 ECONOMIA: -3h (-25%) - Stack já operacional                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** SRE Specialist (9h - reduzido de 12h)
**Bloqueantes:** Nenhum (✅ Prometheus/Grafana/Loki/Tempo JÁ INSTALADOS)
**Componentes já existentes:** 28 ServiceMonitors, Alertmanager, dashboards baseline

---

### Semana 5-6: Marco 2 Sprint 3 (Backup/DR + Hardening)

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 5-6: Backup/DR Completo + Validação                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GAP 3: Backup/DR Specialist (14h)                             │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Instalar Velero + S3 backend          │ 4h │ Dia 1-2 │   │
│  │ 📋 Configurar backup schedules           │ 2h │ Dia 2   │   │
│  │ 📋 DR Runbook documentado                │ 3h │ Dia 3   │   │
│  │ 📋 Definir RTO/RPO targets               │ 1h │ Dia 3   │   │
│  │ 📋 DR Drill: RDS restore                 │ 2h │ Dia 4   │   │
│  │ 📋 DR Drill: K8s namespace restore       │ 2h │ Dia 5   │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • Velero backup diário de namespaces críticos                 │
│  • RTO: 1h, RPO: 24h validados                                 │
│  • DR drill completo documentado                               │
│                                                                 │
│  CHECKPOINT 1: ✅ Marco 2 Completo                              │
│  Gate: Observabilidade + Backup validados antes Marco 3        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** Backup/DR Specialist (14h)
**Bloqueantes:** S3 buckets criados, IRSA configurado

---

### Semana 7-8: Marco 3 Sprint 4 (Foundation)

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 7-8: CI/CD Baseline + Performance Foundation            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GAP 5: CI/CD/DevEx Specialist (16h) — TRILHA A                │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Deploy ArgoCD + ApplicationSets       │ 6h │ Dia 1-3 │   │
│  │ 📋 Deploy Harbor + robot accounts        │ 4h │ Dia 3-4 │   │
│  │ 📋 GitLab pipelines otimizados           │ 4h │ Dia 4-5 │   │
│  │ 📋 Smoke tests pós-deploy                │ 2h │ Dia 5   │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  GAP 2: Performance/Capacity Specialist (12h) — TRILHA B       │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Configurar HPA (GitLab, ArgoCD)       │ 4h │ Dia 1-2 │   │
│  │ 📋 Configurar VPA (recommend mode)       │ 2h │ Dia 2   │   │
│  │ 📋 Baseline performance metrics          │ 3h │ Dia 3-4 │   │
│  │ 📋 Capacity dashboard Grafana            │ 3h │ Dia 4-5 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • ArgoCD operacional com OIDC ready                           │
│  • Harbor registry com scanning habilitado                     │
│  • Pipelines GitLab < 5min build time                          │
│  • HPA configurado com métricas custom                         │
│  • Baseline de performance estabelecido                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** DevEx Specialist (16h) + Performance Specialist (12h)
**Paralelização:** Trilha A e B independentes (executar em paralelo)
**Bloqueantes:** Marco 2 validado (Checkpoint 1)

---

### Semana 9-10: Marco 3 Sprint 5 (Data Services Operators)

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 9-10: Backup Intermediário + Observabilidade Workloads  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GAP 3: Backup/DR Specialist (10h) — TRILHA A                  │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Velero schedules Redis/RabbitMQ PVCs  │ 3h │ Dia 1-2 │   │
│  │ 📋 CloudNativePG backup S3 (futuro)      │ 3h │ Dia 2-3 │   │
│  │ 📋 Automated restore testing (CronJob)   │ 4h │ Dia 3-5 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  GAP 1: Observabilidade/SRE Specialist (10h) — TRILHA B        │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Dashboards específicos (GitLab/ArgoCD)│ 4h │ Dia 1-2 │   │
│  │ 📋 SLOs tracking (Sloth)                 │ 3h │ Dia 3-4 │   │
│  │ 📋 Alertas específicos operadores        │ 3h │ Dia 4-5 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • Backups automatizados todos stateful workloads              │
│  • Restore testing semanal com relatório                       │
│  • Dashboards operacionais para cada workload                  │
│  • SLOs automatizados com error budget tracking                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** Backup Specialist (10h) + SRE Specialist (10h)
**Paralelização:** Trilha A e B independentes
**Bloqueantes:** Redis/RabbitMQ Operators deployed

---

### Semana 11-12: Marco 3 Sprint 6 (Validação & Hardening)

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 11-12: Performance Testing + Chaos Engineering          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GAP 2: Performance/Capacity Specialist (14h) — TRILHA A       │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Load testing K6 (GitLab/ArgoCD/Harbor)│ 6h │ Dia 1-3 │   │
│  │ 📋 Benchmarking contínuo                 │ 3h │ Dia 3-4 │   │
│  │ 📋 Capacity planning (6 meses projeção)  │ 3h │ Dia 4-5 │   │
│  │ 📋 Tuning (JVM, DB connections)          │ 2h │ Dia 5   │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  GAP 6: Chaos Engineering/Resilience (12h) — TRILHA B          │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Chaos experiments básicos (pod kill) │ 4h │ Dia 1-2 │   │
│  │ 📋 Validação HA Redis (Sentinel failover)│ 3h │ Dia 3   │   │
│  │ 📋 Validação HA RabbitMQ (quorum queue) │ 3h │ Dia 4   │   │
│  │ 📋 Game day (node drain simulation)      │ 2h │ Dia 5   │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • K6 scripts executando em CI                                 │
│  • Capacity report com projeção de 6 meses                     │
│  • Tuning documentado com before/after metrics                 │
│  • Chaos experiments automatizados (LitmusChaos)               │
│  • HA validada na prática (não apenas teoria)                  │
│  • Game day runbook documentado                                │
│                                                                 │
│  CHECKPOINT 2: ✅ Marco 3 Completo                              │
│  Gate: Staging production-ready, pode promover para prod       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** Performance Specialist (14h) + Resilience Specialist (12h)
**Paralelização:** Trilha A e B independentes
**Bloqueantes:** Workloads estáveis, observabilidade completa

---

### Semana 13-14: Marco 3.5 Sprint 7 (Service Mesh)

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 13-14: Service Mesh + Observabilidade Avançada          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GAP 4: Service Mesh/Network Specialist (20h) — TRILHA A       │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Deploy Linkerd (cloud-agnostic)       │ 8h │ Dia 1-4 │   │
│  │ 📋 mTLS automático entre workloads       │ 4h │ Dia 4-5 │   │
│  │ 📋 Traffic splitting básico (canary)     │ 4h │ Dia 6-7 │   │
│  │ 📋 Observability integration (Prom+Graf) │ 4h │ Dia 7-8 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  GAP 1: Observabilidade/SRE Specialist (8h) — TRILHA B         │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Service mesh observability (golden)   │ 4h │ Dia 5-6 │   │
│  │ 📋 Distributed tracing completo          │ 4h │ Dia 7-8 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • Linkerd operacional com mTLS                                │
│  • Zero-trust networking habilitado                            │
│  • Traffic metrics por serviço                                 │
│  • Golden signals (latency, traffic, errors, saturation)       │
│  • Tracing end-to-end GitLab → Harbor → ArgoCD                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** Network Specialist (20h) + SRE Specialist (8h)
**Bloqueantes:** Network Policies básicas, observabilidade intermediária
**Paralelização:** Trilha B depende de Trilha A (deploy Linkerd primeiro)

---

### Semana 15-16: Marco 3.5 Sprint 8 (CI/CD Avançado)

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 15-16: CI/CD Avançado + Chaos Contínuo                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GAP 5: CI/CD/DevEx Specialist (16h) — TRILHA A                │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Preview envs por PR (ApplicationSets) │ 8h │ Dia 1-4 │   │
│  │ 📋 Rollback automático (health checks)   │ 4h │ Dia 4-6 │   │
│  │ 📋 GitOps completo (auto-sync+self-heal) │ 4h │ Dia 6-8 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  GAP 6: Chaos Engineering/Resilience (12h) — TRILHA B          │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Chaos experiments avançados (disk)    │ 4h │ Dia 1-2 │   │
│  │ 📋 Scheduled chaos (1x/semana staging)   │ 2h │ Dia 3   │   │
│  │ 📋 Chaos dashboard Grafana               │ 3h │ Dia 4-5 │   │
│  │ 📋 Game day trimestral (multi-failure)   │ 3h │ Dia 6-8 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • Preview environments ephemeral                              │
│  • Zero-downtime deploys com rollback automático              │
│  • Chaos contínuo automatizado                                 │
│  • Confidence score de resiliência                             │
│                                                                 │
│  CHECKPOINT 3: ✅ Marco 3.5 Completo                            │
│  Gate: Platform Engineering maturo, ready para multi-cloud     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** DevEx Specialist (16h) + Resilience Specialist (12h)
**Paralelização:** Trilha A e B independentes
**Bloqueantes:** ArgoCD estável, service mesh operacional

---

## 🔀 Grafo de Dependências

```
┌───────────────────────────────────────────────────────────────────┐
│                    DEPENDÊNCIAS CRÍTICAS                          │
└───────────────────────────────────────────────────────────────────┘

  MARCO 2 (Baseline)
  ┌─────────────────────┐
  │ 1. Observabilidade  │ ◄──── Pré-requisito para tudo
  │    (SRE Specialist) │
  └──────────┬──────────┘
             │
             ├──────────────┬───────────────┬────────────────┐
             ▼              ▼               ▼                ▼
  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │ 2. Performance│  │ 3. Backup/DR │  │ 5. CI/CD     │  │ 6. Chaos Eng │
  │    Specialist │  │   Specialist │  │   Specialist │  │   Specialist │
  └──────┬───────┘  └──────────────┘  └──────┬───────┘  └──────┬───────┘
         │                                     │                 │
         │                                     │                 │
         └─────────────┬───────────────────────┴─────────────────┘
                       ▼
           ┌─────────────────────┐
           │ 4. Service Mesh     │ ◄──── Depende de todos acima
           │    Specialist       │
           └─────────────────────┘

LEGENDA:
  ─────►  Dependência forte (bloqueante)
  ─ ─ ►  Dependência fraca (recomendado)
```

---

## 📊 Matriz RACI

### Marco 2: Platform Services

| Tarefa | SRE | Backup | Perf | Network | DevEx | Chaos | PM |
|--------|-----|--------|------|---------|-------|-------|-----|
| **Definir SLIs/SLOs** | R,A | C | C | I | I | I | I |
| **Configurar alertas** | R,A | C | I | I | I | I | I |
| **Instalar Velero** | C | R,A | I | I | I | I | I |
| **DR Drill execution** | C | R,A | I | I | I | I | A |
| **RTO/RPO definition** | C | R,A | I | I | I | I | A |

---

### Marco 3 Sprint 4: Foundation

| Tarefa | SRE | Backup | Perf | Network | DevEx | Chaos | PM |
|--------|-----|--------|------|---------|-------|-------|-----|
| **Deploy ArgoCD** | C | I | I | C | R,A | I | I |
| **Deploy Harbor** | C | I | I | C | R,A | I | I |
| **Otimizar pipelines** | I | I | I | I | R,A | I | I |
| **Configurar HPA** | C | I | R,A | I | C | I | I |
| **Configurar VPA** | C | I | R,A | I | I | I | I |
| **Baseline metrics** | C | I | R,A | I | I | I | I |

---

### Marco 3 Sprint 5: Data Services

| Tarefa | SRE | Backup | Perf | Network | DevEx | Chaos | PM |
|--------|-----|--------|------|---------|-------|-------|-----|
| **Velero PVC schedules** | C | R,A | I | I | I | I | I |
| **Automated restore test** | C | R,A | I | I | I | I | I |
| **Dashboards workloads** | R,A | I | C | I | C | I | I |
| **SLO tracking** | R,A | I | C | I | I | I | I |
| **Alertas operadores** | R,A | I | I | I | C | I | I |

---

### Marco 3 Sprint 6: Validação

| Tarefa | SRE | Backup | Perf | Network | DevEx | Chaos | PM |
|--------|-----|--------|------|---------|-------|-------|-----|
| **Load testing K6** | C | I | R,A | I | C | I | I |
| **Capacity planning** | C | I | R,A | I | I | I | A |
| **Tuning (JVM, DB)** | C | I | R,A | I | C | I | I |
| **Chaos pod kill** | C | I | I | I | I | R,A | I |
| **HA validation** | C | C | C | C | I | R,A | I |
| **Game day** | C | C | C | C | C | R,A | A |

---

### Marco 3.5 Sprint 7: Service Mesh

| Tarefa | SRE | Backup | Perf | Network | DevEx | Chaos | PM |
|--------|-----|--------|------|---------|-------|-------|-----|
| **Deploy Linkerd** | C | I | I | R,A | C | I | I |
| **mTLS config** | C | I | I | R,A | I | I | I |
| **Traffic splitting** | C | I | C | R,A | C | I | I |
| **Golden signals** | R,A | I | C | C | I | I | I |
| **Distributed tracing** | R,A | I | I | C | I | I | I |

---

### Marco 3.5 Sprint 8: CI/CD Avançado

| Tarefa | SRE | Backup | Perf | Network | DevEx | Chaos | PM |
|--------|-----|--------|------|---------|-------|-------|-----|
| **Preview envs PR** | C | I | I | C | R,A | I | I |
| **Rollback automático** | C | I | I | I | R,A | I | I |
| **GitOps completo** | C | I | I | I | R,A | I | A |
| **Chaos avançado** | C | I | I | I | I | R,A | I |
| **Scheduled chaos** | C | I | I | I | C | R,A | I |
| **Game day trimestral** | C | C | C | C | C | R,A | A |

**LEGENDA RACI:**
- **R** (Responsible): Executa a tarefa
- **A** (Accountable): Responsável final, aprova
- **C** (Consulted): Consultado (input necessário)
- **I** (Informed): Informado (mantido atualizado)

---

## 🎯 Milestones de Validação

### Milestone 1: Observabilidade Baseline ✅

**Data Target:** Fim Semana 4
**Responsável:** SRE Specialist

**Critérios de Aceitação:**
- [ ] 5 SLIs definidos e documentados:
  - [ ] Availability (uptime %)
  - [ ] Latency (p50, p95, p99)
  - [ ] Error Rate (4xx, 5xx)
  - [ ] Saturation (CPU, memory, disk)
  - [ ] Throughput (requests/sec)
- [ ] 10 alertas críticos funcionando:
  - [ ] NodeDown
  - [ ] PodCrashLooping
  - [ ] PVCUsage > 80%
  - [ ] HighMemoryUsage > 90%
  - [ ] HighCPUUsage > 85%
  - [ ] HighLatencyP95 > 1s
  - [ ] HighErrorRate > 5%
  - [ ] PrometheusTargetDown
  - [ ] AlertmanagerDown
  - [ ] KubeletDown
- [ ] Grafana com 5 dashboards operacionais
- [ ] Loki + Tempo integrados e recebendo dados

**Bloqueantes para Milestone 2:** Este milestone é OBRIGATÓRIO antes de avançar

---

### Milestone 2: Backup/DR Validado ✅

**Data Target:** Fim Semana 6
**Responsável:** Backup/DR Specialist

**Critérios de Aceitação:**
- [ ] Velero instalado e backup diário configurado
- [ ] RTO documentado: 1 hora (medido)
- [ ] RPO documentado: 24 horas (medido)
- [ ] DR Drill executado:
  - [ ] Cenário 1: RDS restore < 30min
  - [ ] Cenário 2: Namespace K8s restore < 15min
  - [ ] Cenário 3: GitLab funcional pós-restore
- [ ] DR Runbook completo documentado

**Bloqueantes para Milestone 3:** Este milestone é OBRIGATÓRIO antes de Marco 3

**GATE CHECKPOINT 1:** ✅ Sem Milestone 1+2, não avançar para Marco 3

---

### Milestone 3: CI/CD + Performance Foundation ✅

**Data Target:** Fim Semana 8
**Responsáveis:** DevEx Specialist + Performance Specialist

**Critérios de Aceitação:**
- [ ] ArgoCD operacional com ApplicationSets
- [ ] Harbor registry com scanning habilitado
- [ ] GitLab pipelines < 5min build time
- [ ] HPA configurado para 3+ workloads
- [ ] VPA recommendations documentadas
- [ ] Baseline performance estabelecido

**Bloqueantes para Milestone 4:** Workloads estáveis

---

### Milestone 4: Observabilidade Intermediária ✅

**Data Target:** Fim Semana 10
**Responsável:** SRE Specialist

**Critérios de Aceitação:**
- [ ] Dashboards específicos por workload (GitLab, ArgoCD, Harbor)
- [ ] SLO tracking automatizado com error budget
- [ ] Alertas específicos por operador (Redis, RabbitMQ)

**Bloqueantes para Milestone 5:** Nenhum (pode paralelizar)

---

### Milestone 5: Performance Testing + Chaos Validation ✅

**Data Target:** Fim Semana 12
**Responsáveis:** Performance Specialist + Resilience Specialist

**Critérios de Aceitação:**
- [ ] K6 scripts em CI executando
- [ ] Capacity report 6 meses projetado
- [ ] Tuning aplicado (JVM, DB connections)
- [ ] Chaos experiments validando HA:
  - [ ] Redis Sentinel failover < 30s
  - [ ] RabbitMQ quorum queue failover < 10s
  - [ ] Pod kill sem downtime
- [ ] Game day executado e documentado

**GATE CHECKPOINT 2:** ✅ Staging production-ready, pode promover para prod

---

### Milestone 6: Service Mesh Operacional ✅

**Data Target:** Fim Semana 14
**Responsáveis:** Network Specialist + SRE Specialist

**Critérios de Aceitação:**
- [ ] Linkerd com mTLS operacional
- [ ] Zero-trust networking habilitado
- [ ] Golden signals por serviço
- [ ] Distributed tracing end-to-end

**Bloqueantes para Milestone 7:** Service mesh estável

---

### Milestone 7: Platform Engineering Maturo ✅

**Data Target:** Fim Semana 16
**Responsáveis:** DevEx Specialist + Resilience Specialist

**Critérios de Aceitação:**
- [ ] Preview environments por PR
- [ ] Rollback automático em falhas
- [ ] GitOps completo (auto-sync + self-heal)
- [ ] Chaos contínuo scheduled
- [ ] Confidence score resiliência > 90%

**GATE CHECKPOINT 3:** ✅ Ready para multi-cloud

---

## 🚀 Estratégia de Paralelização

### Semana 3-4: Marco 2 Sprint 2

**Sequencial:** Observabilidade é pré-requisito para tudo

```
SRE Specialist (única trilha) → Milestone 1
```

---

### Semana 5-6: Marco 2 Sprint 3

**Sequencial:** Backup/DR independente

```
Backup Specialist (única trilha) → Milestone 2
```

---

### Semana 7-8: Marco 3 Sprint 4

**Paralelo:** CI/CD e Performance independentes

```
Trilha A: DevEx Specialist     → ArgoCD + Harbor + Pipelines
Trilha B: Performance Specialist → HPA + VPA + Baseline

Economia: 28h → 16h (42% redução)
```

---

### Semana 9-10: Marco 3 Sprint 5

**Paralelo:** Backup e Observabilidade independentes

```
Trilha A: Backup Specialist → Velero schedules + restore testing
Trilha B: SRE Specialist    → Dashboards + SLO tracking

Economia: 20h → 10h (50% redução)
```

---

### Semana 11-12: Marco 3 Sprint 6

**Paralelo:** Performance e Chaos independentes

```
Trilha A: Performance Specialist  → K6 + Capacity + Tuning
Trilha B: Resilience Specialist   → Chaos + HA validation + Game day

Economia: 26h → 14h (46% redução)
```

---

### Semana 13-14: Marco 3.5 Sprint 7

**Sequencial parcial:** Service mesh precisa estar deployed antes observability

```
Trilha A (Dia 1-4): Network Specialist → Linkerd + mTLS
Trilha B (Dia 5-8): SRE Specialist     → Golden signals + Tracing

Bloqueante: Trilha B depende de Trilha A
Economia: 28h → 20h (29% redução)
```

---

### Semana 15-16: Marco 3.5 Sprint 8

**Paralelo:** CI/CD e Chaos independentes

```
Trilha A: DevEx Specialist      → Preview envs + Rollback + GitOps
Trilha B: Resilience Specialist → Chaos avançado + Scheduled chaos

Economia: 28h → 16h (43% redução)
```

---

## 📊 Consolidação de Economia

### Sem Paralelização

| Marco | Sprints | Esforço Total | Duração (1 eng) |
|-------|---------|---------------|-----------------|
| Marco 2 | 2-3 | 26h | 3,25 dias |
| Marco 3 | 4-6 | 74h | 9,25 dias |
| Marco 3.5 | 7-8 | 56h | 7 dias |
| **TOTAL** | **6** | **156h** | **19,5 dias** |

---

### Com Paralelização (2 engenheiros)

| Marco | Sprints | Esforço Paralelo | Duração (2 eng) | Economia |
|-------|---------|------------------|-----------------|----------|
| Marco 2 | 2-3 | 26h | 3,25 dias | 0% |
| Marco 3 | 4-6 | 40h | 5 dias | -46% |
| Marco 3.5 | 7-8 | 36h | 4,5 dias | -36% |
| **TOTAL** | **6** | **102h** | **12,75 dias** | **-35%** |

**ROI Paralelização:**
- Economia: 54 person-hours (-35%)
- Redução calendar time: 6,75 dias (-35%)
- Custo adicional: R$ 10.800 (2º engenheiro)
- Time-to-market: 12,75 dias vs 19,5 dias

---

## 🎯 Próximos Passos Imediatos

### Esta Semana (Semana Atual)

**Ação 1:** Finalizar Marco 2 Fase 9 (FinOps automation)
**Responsável:** Orquestrador
**Esforço:** 2h

**Ação 2:** Deploy Tempo (Marco 2 Fase 8 pendente)
**Responsável:** SRE Specialist
**Esforço:** 3h

---

### Próximas 2 Semanas (Semana 3-4)

**Ação 3:** Executar Gap 1 (Observabilidade baseline)
**Responsável:** SRE Specialist
**Esforço:** 12h
**Milestone:** Milestone 1

**Tarefas:**
1. Definir 5 SLIs críticos para staging
2. Validar 10 alertas críticos Alertmanager
3. Criar 5 dashboards baseline Grafana
4. Documentar SLOs targets

---

### Semana 5-6

**Ação 4:** Executar Gap 3 (Backup/DR)
**Responsável:** Backup/DR Specialist
**Esforço:** 14h
**Milestone:** Milestone 2

**Tarefas:**
1. Instalar Velero com S3 backend
2. Configurar backup schedules
3. Documentar RTO/RPO targets
4. Executar DR drill completo
5. Criar DR Runbook

**GATE:** Validar Checkpoint 1 antes de Marco 3

---

## 📚 Referências

- [Critical Gaps Distribution](critical-gaps-distribution.md) — Distribuição detalhada por gap
- [AWS EKS GitLab Quickstart](aws-eks-gitlab-quickstart.md) — Plano base 3 sprints
- [Convergence Roadmap](../convergence-roadmap.md) — Visão longo prazo
- [Marco 2 Diary](../../diary/marco2-diary.md) — Progresso atual
- [ADR-024: FinOps](../../context/decisions.md#adr-024) — Automação custo

---

**Status:** 📋 Roadmap de execução aprovado
**Próxima Ação:** Finalizar Marco 2 Fase 9 + Iniciar Gap 1 (SLIs/SLOs)
**Responsável:** Orquestrador + SRE Specialist
**Última Atualização:** 2026-02-09
