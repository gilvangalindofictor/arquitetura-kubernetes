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

### Semana 5-6: Marco 3 Sprint 4 (Backup/DR + CI/CD Optimization) ✅ CORRIGIDO

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 5-6: Backup/DR + CI/CD (10h - REDUZIDO DE 30h)          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GAP 3: Backup/DR Specialist (8h)                              │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ ✅ RDS automated backups                 │ JÁ COMPLETO  │   │
│  │ ✅ S3 buckets para backups               │ JÁ COMPLETO  │   │
│  │ 📋 Instalar Velero + S3 backend          │ 4h │ Dia 1-2 │   │
│  │ 📋 DR Runbook documentado                │ 3h │ Dia 2-3 │   │
│  │ 📋 Definir RTO/RPO targets               │ 1h │ Dia 3   │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  GAP 5: CI/CD/DevEx (2h)                                       │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ ✅ ArgoCD + ApplicationSets              │ JÁ DEPLOYADO │   │
│  │ ✅ Harbor + robot accounts               │ JÁ DEPLOYADO │   │
│  │ ✅ GitLab CE + runners                   │ JÁ DEPLOYADO │   │
│  │ ✅ Keycloak SSO                          │ JÁ DEPLOYADO │   │
│  │ 📋 Pipeline optimization (cache, parallel)│ 2h │ Dia 3  │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • ✅ ArgoCD, Harbor, GitLab, Keycloak operacionais (COMPLETO) │
│  • 📋 Velero instalado com S3 backend                          │
│  • 📋 RTO/RPO documentados                                     │
│  • 📋 Pipelines otimizados                                     │
│                                                                 │
│  🎉 ECONOMIA MASSIVA: -20h (-67%) - CI/CD já deployado!        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** Backup Specialist (8h) + DevEx Specialist (2h)
**Bloqueantes:** ✅ S3 buckets criados, ✅ IRSA configurado
**Componentes já existentes:** ArgoCD 2 replicas HA, Harbor S3 IRSA, GitLab runners, Keycloak 2 replicas

---

### Semana 7-8: Marco 3 Sprint 5 (Performance + Backup Testing) ✅ CORRIGIDO

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 7-8: Performance + Backup Testing (13h - REDUZIDO)      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GAP 2: Performance/Capacity Specialist (10h) — TRILHA A       │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ ✅ Metrics Server                        │ JÁ COMPLETO  │   │
│  │ ✅ Prometheus metrics                    │ JÁ COMPLETO  │   │
│  │ ✅ Grafana dashboards baseline           │ JÁ COMPLETO  │   │
│  │ 📋 Instalar VPA (recommend mode)         │ 2h │ Dia 1   │   │
│  │ 📋 Configurar HPA (GitLab, ArgoCD)       │ 4h │ Dia 1-2 │   │
│  │ 📋 Baseline metrics review               │ 1h │ Dia 2   │   │
│  │ 📋 Dashboards workload-specific          │ 3h │ Dia 3   │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  GAP 3: Backup/DR Specialist (3h) — TRILHA B                   │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Automated restore testing (CronJob)   │ 3h │ Dia 1-2 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • ✅ Prometheus metrics coletando tudo (JÁ COMPLETO)          │
│  • 📋 VPA instalado                                            │
│  • 📋 HPA configurado para 3+ workloads                        │
│  • 📋 Dashboards específicos por workload                      │
│  • 📋 Restore testing automatizado                             │
│                                                                 │
│  🎉 ECONOMIA: -15h (-54%) - Metrics/dashboards já existem      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** Performance Specialist (10h) + Backup Specialist (3h)
**Paralelização:** Trilha A e B independentes
**Bloqueantes:** ✅ Prometheus operacional, ✅ Velero instalado
**Componentes já existentes:** Metrics Server, Prometheus, Grafana, FinOps capacity mgmt

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

### Semana 8-9: Marco 3 Sprint 6 (Load Testing + DR Drill + Chaos) ✅ CORRIGIDO

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 8-9: Load Testing + DR Drill + Chaos (19h)              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GAP 2: Performance/Capacity Specialist (10h) — TRILHA A       │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Load testing K6 (GitLab/ArgoCD/Harbor)│ 6h │ Dia 1-3 │   │
│  │ 📋 Capacity planning (6 meses projeção)  │ 4h │ Dia 3-4 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  GAP 3: Backup/DR Specialist (6h) — TRILHA B                   │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 DR Drill: RDS restore                 │ 3h │ Dia 1-2 │   │
│  │ 📋 DR Drill: K8s namespace restore       │ 3h │ Dia 2-3 │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  GAP 6: Chaos Engineering/Resilience (3h) — TRILHA C           │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Instalar LitmusChaos                  │ 2h │ Dia 1   │   │
│  │ 📋 Chaos experiments básicos (pod kill)  │ 1h │ Dia 2   │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • 📋 K6 scripts executando em CI                              │
│  • 📋 Capacity report com projeção de 6 meses                  │
│  • 📋 DR drill completo (RTO < 1h, RPO < 24h)                  │
│  • 📋 LitmusChaos instalado                                    │
│  • 📋 Chaos experiments básicos validando HA                   │
│                                                                 │
│  CHECKPOINT 2: ✅ Marco 3 Completo                              │
│  Gate: Staging production-ready, pode promover para prod       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** Performance Specialist (10h) + Backup Specialist (6h) + Resilience Specialist (3h)
**Paralelização:** Trilhas A, B e C independentes
**Bloqueantes:** ✅ Workloads estáveis, ✅ Observabilidade completa, ✅ Velero operacional

---

### Semana 9+: Marco 3.5 Sprint 7-8 (Service Mesh + Chaos Avançado) - OPCIONAL

```
┌─────────────────────────────────────────────────────────────────┐
│ SEMANA 9+: Service Mesh + Chaos Avançado (45h) - OPCIONAL      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Sprint 7: Service Mesh (20h)                                  │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 📋 Deploy Linkerd (cloud-agnostic)       │ 8h │ Sem 9   │   │
│  │ 📋 mTLS automático entre workloads       │ 4h │ Sem 9   │   │
│  │ 📋 Traffic splitting básico (canary)     │ 4h │ Sem 9   │   │
│  │ 📋 Observability integration (Prom+Graf) │ 4h │ Sem 9   │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  Sprint 8: CI/CD + Chaos Avançado (25h)                        │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ ✅ ArgoCD ApplicationSets                │ JÁ PRONTO    │   │
│  │ ✅ Rollback automático                   │ JÁ EXISTS    │   │
│  │ 📋 Preview envs config (ApplicationSets) │ 1h │ Sem 10  │   │
│  │ 📋 Chaos: Validação HA Redis/RabbitMQ    │ 6h │ Sem 10  │   │
│  │ 📋 Chaos: Game day completo              │ 6h │ Sem 10  │   │
│  │ 📋 Chaos: Scheduled chaos (1x/semana)    │ 6h │ Sem 10  │   │
│  │ 📋 Chaos: Experiments avançados (disk)   │ 4h │ Sem 10  │   │
│  │ 📋 Chaos: Dashboard Grafana              │ 2h │ Sem 10  │   │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ENTREGAS:                                                      │
│  • Linkerd mTLS operacional                                    │
│  • Zero-trust networking completo                              │
│  • ✅ Preview envs (ApplicationSets config apenas - 1h)        │
│  • ✅ Rollback automático (já existe via ArgoCD)               │
│  • Chaos contínuo automatizado                                 │
│  • Confidence score resiliência > 90%                          │
│                                                                 │
│  CHECKPOINT 3: ✅ Marco 3.5 Completo                            │
│  Gate: Platform Engineering maturo, ready para multi-cloud     │
│                                                                 │
│  🎉 ECONOMIA: -15h (-25%) - ArgoCD/rollback já existem         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Responsáveis:** Network Specialist (20h) + DevEx Specialist (1h) + Resilience Specialist (24h)
**Paralelização:** Sprints 7 e 8 podem ser sequenciais ou paralelos
**Bloqueantes:** ✅ Network Policies básicas, ✅ Observabilidade completa, ✅ ArgoCD operacional
**Componentes já existentes:** ArgoCD ApplicationSets ready, health checks configurados

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
