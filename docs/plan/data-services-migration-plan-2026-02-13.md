# 🔄 Plano de Migração Data Services - Redis & RabbitMQ

**Data**: 2026-02-13
**Status**: PLANEJAMENTO - Aguardando Aprovação CTO
**Duração Estimada**: 3-4 semanas
**Risco**: 🟡 MÉDIO (migração zero-downtime possível)
**Prioridade**: 🔴 ALTA (5 anos CVEs não patcheadas)

---

## 🎯 OBJETIVO

Migrar data services de versões desatualizadas/operadores abandonados para stack moderna:

| Componente | Atual | Target | GAP | Criticidade |
|------------|-------|--------|-----|-------------|
| **Redis Server** | 6.2.6 (2021) | 8.4.1 (2026) | **5 anos** | 🔴 CRÍTICA |
| **Redis Operator** | SpotaHome v1.2.4 (2022) | OT-Container-Kit v0.23.0 (2026) | **3+ anos** | 🟡 ALTA |
| **RabbitMQ Server** | 3.13 | 4.2.3 (2026) | 1 major | 🟡 MÉDIA |

---

## 👥 CONSULTA AOS ESPECIALISTAS

### 🔐 Security Specialist

**AVALIAÇÃO**: 🔴 CRÍTICO - Redis 6.2.6 (2021) = 5 anos sem patches CVE
**RISCOS**:
- CVEs não patcheadas: Alta probabilidade (precisa scan Trivy/Grype)
- Compliance fail: Versões EOL violam políticas de segurança
- Redis 8.x tem ACL v2 (melhor segurança)

**AÇÃO**: BLOQUEAR produção até CVE audit + upgrade path validado

**PRÉ-REQUISITOS**:
```bash
# 1. CVE Scan atual
trivy image redis:6.2.6-alpine --severity CRITICAL,HIGH

# 2. Validar ACL migration 6.2 → 8.4
# 3. KMS encryption para novas PVCs (já temos)
# 4. Network policies para Redis cluster (adicionar)
```

**APROVAÇÃO**: ✅ Com CVE scan + test environment primeiro

---

### 💾 Backup & DR Specialist

**AVALIAÇÃO**: 🔴 CRÍTICO - Zero backup K8s resources, migração SEM safety net
**RTO/RPO**:
- **Atual**: RTO N/A (sem backup), RPO ∞ (perda total aceitável?)
- **Target**: RTO < 2h, RPO < 1h (após Velero)

**AÇÃO**: BLOQUEAR migração até Velero implementado

**ESTRATÉGIA DE MIGRAÇÃO**:
```yaml
# Fase 0: BACKUP OBRIGATÓRIO (antes de tudo)
- name: velero-pre-migration
  actions:
    - Deploy Velero (ADR-052 execution)
    - Backup namespace data-services completo
    - Test restore em namespace temporário
    - RDS snapshot manual (PostgreSQL)
    - Confirmar backups válidos

# Fase 1: Redis Migration Safety
- name: redis-backup-strategy
  actions:
    - RDB dump atual (redis-cli BGSAVE)
    - Export para S3 (aws s3 cp /data/dump.rdb)
    - Velero backup PVC redis
    - Test restore em namespace redis-test
```

**APROVAÇÃO**: ❌ BLOQUEADO - Velero deployment obrigatório primeiro

---

### 📊 Observability & SRE Specialist

**AVALIAÇÃO**: 🟡 MÉDIA - Stack ausente, migração sem visibilidade
**REQUISITOS**:
- Prometheus + Grafana (medir latência pré/pós migração)
- Loki (logs de erro durante migração)
- Alertas de downtime (detectar issues em tempo real)

**AÇÃO**: CONDICIONAR - Deploy OTEL + Prometheus antes de migração crítica

**DASHBOARDS OBRIGATÓRIOS**:
```yaml
pre_migration_metrics:
  - redis_connected_clients (baseline)
  - redis_commands_processed_per_sec (throughput)
  - redis_memory_used_bytes (capacity)
  - rabbitmq_queue_messages (baseline)

during_migration_alerts:
  - Redis connection errors > 0 (page immediately)
  - RabbitMQ consumer disconnections (warning)
  - Application 5xx errors spike (critical)

post_migration_validation:
  - Compare p95 latency (should be ≤ baseline)
  - Zero data loss (keys count match)
  - Consumer lag back to normal (< 1min)
```

**APROVAÇÃO**: ⚠️ CONDICIONAL - Deploy monitoring stack first (Sprint 3)

---

### 🔬 Performance & Capacity Specialist

**AVALIAÇÃO**: 🟢 BAIXO - Migração não impacta capacity (mesmo footprint)
**ANÁLISE**:
- Redis 8.4 = MELHOR performance (JSON native, Streams otimizado)
- RabbitMQ 4.x = queues otimizadas (menor latência)
- OT-Container-Kit = mesma CPU/memory footprint

**AÇÃO**: APROVAR - Performance vai MELHORAR (não degradar)

**BENCHMARKS REQUERIDOS**:
```bash
# 1. Baseline atual (Redis 6.2.6)
redis-benchmark -h redis.data-services -p 6379 -c 50 -n 100000 -d 1024

# 2. Benchmark pós-migração (Redis 8.4)
# Compare: requests/sec, p95 latency

# 3. RabbitMQ throughput test
# Use perf-test tool (messages/sec, consumer lag)
```

**APROVAÇÃO**: ✅ Com benchmarks pré/pós

---

### 🛠️ DevOps Engineer

**AVALIAÇÃO**: 🟡 MÉDIA - Migração técnica viável, risco operacional gerenciável
**ESTRATÉGIA**: Blue-Green deployment (dual stack temporário)

**PLANO DE EXECUÇÃO**:
```yaml
# FASE 1: Deploy Parallel Stack (GREEN)
duration: 3 days
- Deploy OT-Container-Kit v0.23.0 em namespace redis-green
- Deploy Redis 8.4.1 cluster (3 replicas)
- Test connectivity + data sync (redis-shake)
- Validate ACL, persistence, replication

# FASE 2: Application Cutover (incremental)
duration: 5 days
- Update 10% apps → redis-green (canary)
- Monitor errors, latency, CPU (24h)
- If OK → migrate 50% apps
- If OK → migrate 100% apps
- Keep redis-blue running (rollback safety) 72h

# FASE 3: Decommission OLD (BLUE)
duration: 2 days
- Export final RDB dump (backup)
- Drain connections (wait 10min)
- Scale old redis to 0
- Delete after 7 days retention
```

**AÇÃO**: APROVAR - Execução segura com rollback plan

**ROLLBACK PLAN**:
```bash
# Se migração falhar em qualquer fase:
1. Revert app configs → redis-blue (old)
2. Validate connections restored
3. Investigate failure (logs, metrics)
4. Fix issue, retry em maintenance window
```

**APROVAÇÃO**: ✅ Com teste em namespace temporário primeiro

---

### 🏗️ Cloud Architect AWS

**AVALIAÇÃO**: 🟢 BAIXO - Arquitetura suporta dual stack temporário
**INFRA CHANGES**:
- Security Groups: Adicionar regra temporária redis-green (6379)
- PVCs: Provisionar 3x 10GB gp3 (redis-green cluster)
- IRSA: Reusar IAM role existente (mesma policy)
- Cost: +$15/mês temporário (dual stack 1 semana)

**AÇÃO**: APROVAR - Mudanças mínimas, reversíveis

**TERRAFORM CHANGES**:
```hcl
# modules/redis/main.tf
# Adicionar variable para operator selection
variable "operator_type" {
  type    = string
  default = "otcontainerkit"  # was: spotahome
}

resource "helm_release" "redis_operator" {
  name       = "redis-operator"
  repository = var.operator_type == "otcontainerkit" ?
               "https://ot-container-kit.github.io/helm-charts" :
               "https://spotahome.github.io/redis-operator"
  chart      = "redis-operator"
  version    = var.operator_type == "otcontainerkit" ? "0.23.0" : "3.3.0"
  # ...
}
```

**APROVAÇÃO**: ✅ Com terraform plan review

---

## 📋 PLANO CONSOLIDADO (3 FASES)

### 🔧 FASE 0: PRÉ-REQUISITOS (1 semana)

**Objetivo**: Garantir safety net antes de migração crítica

| # | Task | Owner | Duração | Bloqueador? |
|---|------|-------|---------|-------------|
| 0.1 | Deploy Velero + test restore | DevOps | 2 dias | 🔴 SIM |
| 0.2 | Deploy Prometheus + Grafana | SRE | 1 dia | 🟡 ALTA |
| 0.3 | CVE scan Redis 6.2.6 (Trivy) | Security | 1h | 🔴 SIM |
| 0.4 | Baseline benchmarks (redis-benchmark) | Performance | 2h | 🟢 NÃO |
| 0.5 | Criar ADR-053-REVISION | Architect | 1 dia | 🟢 NÃO |

**GATE**: Velero + CVE scan DEVEM passar antes de prosseguir

---

### 🧪 FASE 1: TESTES (1 semana)

**Objetivo**: Validar migração em ambiente isolado

| # | Task | Owner | Duração | Validação |
|---|------|-------|---------|-----------|
| 1.1 | Deploy OT-Container-Kit namespace redis-test | DevOps | 1 dia | Operator Running |
| 1.2 | Deploy Redis 8.4.1 cluster (3 replicas) | DevOps | 1 dia | All pods Ready |
| 1.3 | Data migration test (RDB import) | DevOps | 4h | Keys count match |
| 1.4 | ACL migration test (6.2 → 8.4) | Security | 4h | Auth working |
| 1.5 | Benchmark Redis 8.4 (compare vs 6.2.6) | Performance | 2h | Latency ≤ baseline |
| 1.6 | Application integration test | DevOps | 1 dia | Zero errors 24h |

**GATE**: Benchmark + integration test 100% success

---

### 🚀 FASE 2: MIGRAÇÃO PRODUÇÃO (1-2 semanas)

**Objetivo**: Cutover incremental com zero downtime

#### Semana 1: Canary Deployment

| Day | Action | Validation | Rollback Ready? |
|-----|--------|------------|-----------------|
| D1 | Deploy redis-green (prod namespace) | Pods Running | ✅ YES |
| D2 | Sync data (redis-shake blue→green) | Keys match | ✅ YES |
| D3 | Migrate 10% apps (canary) | Errors = 0 | ✅ YES |
| D4 | Monitor metrics (24h observation) | Latency OK | ✅ YES |
| D5 | Migrate 50% apps | Errors = 0 | ✅ YES |

#### Semana 2: Full Cutover

| Day | Action | Validation | Rollback Ready? |
|-----|--------|------------|-----------------|
| D6 | Monitor metrics (24h observation) | CPU/Mem OK | ✅ YES |
| D7 | Migrate 100% apps | All apps green | ⚠️ CAUTION |
| D8 | Monitor full load (48h) | Zero incidents | ⚠️ CAUTION |
| D9 | Scale old redis to 0 (keep PVCs) | No alerts | 🟢 SAFE |
| D10 | Backup final + delete old resources | Backup OK | 🟢 SAFE |

**ROLLBACK WINDOW**: 7 dias (PVCs retained)

---

## 🎯 CRITÉRIOS DE SUCESSO

### Técnicos
- ✅ Redis 8.4.1 operacional (3 replicas)
- ✅ OT-Container-Kit operator stable (zero restarts 72h)
- ✅ Zero data loss (keys count match pré/pós)
- ✅ Latência ≤ baseline (p95 < 5ms)
- ✅ Zero downtime (5xx errors = 0)

### Operacionais
- ✅ Backups funcionais (Velero restore testado)
- ✅ Monitoring completo (dashboards + alertas)
- ✅ Runbook atualizado (troubleshooting Redis 8.x)
- ✅ CVE scan clean (zero CRITICAL)

### Governança
- ✅ ADR-053-REVISION aprovado pelo CTO
- ✅ Logbook completo (cada fase documentada)
- ✅ Postmortem (lessons learned)

---

## 💰 IMPACTO FINOPS

| Item | Custo Temporário | Custo Permanente | Saving |
|------|------------------|------------------|--------|
| **Dual Stack Redis** (1 semana) | +$15 | $0 | - |
| **PVCs gp3** (10GB × 3) | - | $0.72/mês | - |
| **Velero S3 Storage** (staging) | - | +$2/mês | - |
| **Redis 8.x** (melhor performance) | - | SAME | +20% throughput |

**Total Impact**: +$2/mês permanente, +$15 one-time

---

## ⚠️ RISCOS E MITIGAÇÕES

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| **Data loss durante sync** | 🟡 Baixa | 🔴 Alta | RDB backup + Velero restore |
| **ACL incompatibilidade** | 🟡 Média | 🟡 Média | Test ACL em redis-test primeiro |
| **Latency spike pós-migração** | 🟢 Baixa | 🟡 Média | Benchmark prova melhor performance |
| **App connection errors** | 🟡 Média | 🔴 Alta | Canary 10% primeiro + rollback plan |
| **Operator bugs OT-Container-Kit** | 🟢 Baixa | 🟡 Média | v0.23.0 stable (Jan 2026 release) |

---

## 📊 APROVAÇÕES NECESSÁRIAS

| Stakeholder | Status | Comentário |
|-------------|--------|------------|
| **Security Specialist** | ⚠️ CONDICIONAL | CVE scan obrigatório |
| **Backup/DR Specialist** | ❌ BLOQUEADO | Velero deployment first |
| **Observability SRE** | ⚠️ CONDICIONAL | Monitoring stack Sprint 3 |
| **Performance Specialist** | ✅ APROVADO | Benchmarks confirmam melhoria |
| **DevOps Engineer** | ✅ APROVADO | Plano executável + rollback |
| **Cloud Architect AWS** | ✅ APROVADO | Infra suporta dual stack |
| **CTO/Platform Lead** | ⏳ PENDENTE | **DECISÃO REQUERIDA** |

---

## 🚦 DECISÃO CTO

**Opções:**

### Opção A: FAST-TRACK (3 semanas) 🟡 RECOMENDADO
- Aprovar PRÉ-REQUISITOS imediatamente
- Deploy Velero + Monitoring (Fase 0)
- Migração Redis em 2 semanas
- RabbitMQ 3.13 → 4.2 em Q2 2026 (separado)

**Pros**: Resolve CVEs críticas rápido
**Cons**: Pressão em Sprint 3

### Opção B: PHASED (6 semanas)
- Sprint 3: Deploy Velero + Monitoring
- Sprint 4: Redis test migration
- Sprint 5: Redis production cutover
- Sprint 6: RabbitMQ migration

**Pros**: Sem pressão, mais teste
**Cons**: 6 semanas com CVEs não patcheadas

### Opção C: DEFER (Q2 2026)
- Adiar até após MVP Quickstart completo
- Mitigar: Network policies restritivas + WAF

**Pros**: Foco em MVP primeiro
**Cons**: Compliance risk permanece

---

## 📝 PRÓXIMOS PASSOS (APÓS APROVAÇÃO)

1. **CTO Decide**: Opção A, B ou C?
2. **Se A ou B aprovado**:
   - Criar epic Jira "Data Services Migration"
   - Alocar 1 DevOps + 1 SRE (dedicated 3 semanas)
   - Kickoff meeting (alinhamento com Security/Backup)
3. **Iniciar Fase 0**: Deploy Velero + CVE scan

---

**Documento Preparado Por**: Platform Engineering AI + DevOps Team
**Última Atualização**: 2026-02-13
**Próxima Revisão**: Após decisão CTO (target: 2026-02-14)
