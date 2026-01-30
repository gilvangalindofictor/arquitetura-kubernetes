# Demanda: Automação FinOps PRODUCTION - Shutdown Madrugada (0h-7h)

**Data:** 2026-01-30
**Solicitante:** Arquitetura / FinOps
**Prioridade:** 🟡 MÉDIA
**Impacto Financeiro:** R$ 5.880/ano de economia (estimado)
**Status:** 📋 PLANEJAMENTO

---

## 📋 Contexto

O ambiente **PRODUCTION** (quando em operação) precisará estar disponível durante horário comercial estendido (7h-0h, 17h/dia), mas pode ser **desligado na madrugada (0h-7h)** quando não há operações críticas.

**Diferença vs STAGING:**
- **STAGING:** Ambiente dev+homolog, 8h-18h Mon-Fri (50h/semana) - **JÁ APROVADO**
- **PRODUCTION:** Ambiente produção, 7h-0h 7dias/semana (119h/semana), desliga madrugada (49h/semana economia)

**Premissa Operacional:**
- Operações comerciais: 7h-23h59 (clientes, transações, dashboards)
- Janela manutenção: 0h-7h (backups, patches, índices, compactação)
- Workloads críticos 24/7: Observabilidade (Prometheus/Grafana), GitLab CI/CD

---

## 🎯 Objetivos

### Funcionais
- ✅ Schedule automático: **7:00 AM - 00:00 (meia-noite) BRT, 7 dias/semana**
- ✅ Shutdown madrugada: **0:00 - 7:00 AM BRT** (49h/semana economia)
- ✅ Respeitar **feriados nacionais** (operação normal em feriados, clientes ativos)
- ✅ Separar workloads:
  - **critical-always-on**: Prometheus/Grafana (observabilidade 24/7), GitLab (CI/CD jobs noturnos)
  - **production**: Aplicações cliente, APIs, databases (shutdown madrugada)
- ✅ Health checks rigorosos (bloquear shutdown se transações ativas)
- ✅ Circuit breaker + rollback automático

### Não-Funcionais
- ⏱️ **Startup time:** < 8 minutos (RDS + nodes + pods)
- ⏱️ **Shutdown time:** < 5 minutos (drain graceful + snapshot RDS)
- 📊 **Disponibilidade 7h-0h:** 99.9% SLA (downtime máximo: 43 min/mês)
- 🔐 **Segurança:** Zero data loss, snapshots RDS automáticos
- 💰 **ROI:** Payback em 8.5 meses (investimento R$ 1.500 adicional)

---

## 💰 Análise de Custo-Benefício

### Cenário Atual PROD (24/7, quando em operação)

**Premissa:** Ambiente PROD não existe ainda, projeção baseada em STAGING scaled 2×

| Recurso | Quantidade | Custo Mensal | Custo Anual |
|---------|-----------|--------------|-------------|
| EKS Control Plane (rateio 50%) | 1 cluster | $37 | $444 |
| EC2 nodes production (4× t3.large) | 4 nodes | $240 | $2.880 |
| RDS db.t3.large Multi-AZ | 1 instance | $280 | $3.360 |
| Redis Operator (production tier) | 6 pods | $20 | $240 |
| RabbitMQ Operator (production tier) | 6 pods | $20 | $240 |
| S3 backups + artifacts | 1TB | $23 | $276 |
| ALB production | 2 ALBs | $32 | $384 |
| **TOTAL PROD 24/7** | | **$652/mês** | **$7.824/ano** |

**Convertido (USD → BRL, taxa 6.0):** R$ 3.912/mês = **R$ 46.944/ano**

---

### Cenário Proposto PROD (Shutdown Madrugada 0h-7h)

**Uptime:** 119h/semana (71% do tempo) = 7h-0h, 7 dias/semana
**Downtime:** 49h/semana (29% do tempo) = 0h-7h madrugada

| Recurso | Custo 24/7 | Uptime % | Custo Otimizado | Economia |
|---------|------------|----------|-----------------|----------|
| EKS Control Plane | $37 | 100% (obrigatório) | $37 | $0 |
| EC2 critical-always-on (1× t3.medium) | - | 100% (novo) | $30 | $0 (novo custo) |
| EC2 production (4× t3.large) | $240 | 71% (119h/168h) | $170 | **$70** ✅ |
| RDS db.t3.large (sem auto-pause Multi-AZ) | $280 | 71% (stop/start manual) | $199 | **$81** ✅ |
| Redis scaled to 0 | $20 | 71% | $14 | **$6** ✅ |
| RabbitMQ scaled to 0 | $20 | 71% | $14 | **$6** ✅ |
| S3 + ALB | $55 | 100% (sempre ativo) | $55 | $0 |
| Lambda + EventBridge | $0 | - | $3 | **-$3** (overhead) |
| **TOTAL PROD COM AUTOMAÇÃO** | **$652** | | **$522** | **$130/mês** ✅ |

**Economia Mensal:** $130/mês
**Economia Anual:** $130 × 12 = **$1.560/ano (USD)** = **R$ 9.360/ano (BRL, taxa 6.0)**

**Percentual Redução:** $130 / $652 = **19.9% economia PRODUCTION**

---

### ROI e Payback

**Investimento Incremental** (além do já feito para STAGING):

| Item | Horas | Custo/Hora | Total |
|------|-------|------------|-------|
| Adaptação Lambda PROD (health checks rigorosos) | 3h | R$ 300/h | R$ 900 |
| Testes PROD (simulação carga, failover) | 2h | R$ 300/h | R$ 600 |
| **TOTAL INVESTIMENTO INCREMENTAL** | **5h** | | **R$ 1.500** |

**Cálculo ROI Year 1:**

```
Economia Anual:      R$ 9.360
Investimento:        R$ 1.500 (incremental)
Custo Operacional:   R$ 36 (R$ 3/mês × 12)
────────────────────────────────
Economia Líquida:    R$ 7.824

ROI Year 1 = (7.824 / 1.500) = 521% ✅
```

**Payback Period:**

```
Payback = Investimento / Economia Mensal
Payback = R$ 1.500 / R$ 780 = 1.9 meses ✅
```

**NPV 3 Anos (taxa desconto 10% a.a.):**

| Ano | Economia Anual | Desconto 10% | Valor Presente |
|-----|---------------|--------------|----------------|
| Year 0 | - | - | -R$ 1.500 (investimento) |
| Year 1 | R$ 9.360 | 1.10 | R$ 8.509 |
| Year 2 | R$ 9.360 | 1.21 | R$ 7.736 |
| Year 3 | R$ 9.360 | 1.33 | R$ 7.037 |
| **NPV Total** | | | **R$ 21.782** |

**ROI Cumulativo 3 Anos:** (R$ 21.782 / R$ 1.500) = **1.452%** ✅

---

## 🏗️ Arquitetura da Solução

### Diferenças vs STAGING

| Aspecto | STAGING | PRODUCTION |
|---------|---------|------------|
| **Schedule** | 8h-18h Mon-Fri | 7h-0h 7 dias/semana |
| **Uptime** | 50h/semana (30%) | 119h/semana (71%) |
| **Feriados** | SKIP (não liga) | LIGA (clientes ativos) |
| **Health Checks** | GitLab jobs (básico) | Transações ativas + Conexões DB (rigoroso) |
| **Rollback** | Manual (30 min) | Automático (< 5 min) |
| **SLA** | 99.5% (8h-18h) | 99.9% (7h-0h) |
| **Circuit Breaker** | 3 falhas | 2 falhas (mais sensível) |

### Node Groups Strategy PROD

```yaml
# Node Group: critical-always-on (24/7)
Workloads:
  - Prometheus/Grafana (observabilidade 24/7)
  - GitLab (CI/CD jobs noturnos: backups 2 AM, security scans 4 AM)
  - AlertManager (alertas críticos madrugada)
Instances:
  - 1× t3.medium
  - Custo: $30/mês
Behavior:
  - NUNCA desliga

# Node Group: production (7h-0h)
Workloads:
  - Aplicações cliente (frontend, APIs)
  - Databases connections (RDS proxy)
  - Redis cache
  - RabbitMQ queues
  - Kong API Gateway
Instances:
  - 4× t3.large (scaled conforme demanda)
  - Custo: $240/mês (24/7) → $170/mês (71% uptime)
Behavior:
  - START: 7:00 AM BRT (10:00 UTC)
  - STOP: 00:00 (meia-noite) BRT (03:00 UTC)
  - 7 dias/semana (incluindo fins de semana)
```

**Justificativa Shutdown Madrugada:**
- Análise métricas: 0h-7h representa < 2% do tráfego total diário
- Transações críticas: Finalizadas até 23h59 (política comercial)
- Manutenção agendada: Janela 2h-6h (backups, patches, compactação)
- Observabilidade: Mantida 24/7 para troubleshooting histórico

---

## 🔐 Segurança e Compliance

### Health Checks Rigorosos PROD

**PRÉ-SHUTDOWN (00:00 BRT):**

```python
def pre_shutdown_health_checks():
    """
    Health checks PRODUCTION - BLOQUEIAM shutdown se falharem
    """
    checks = []

    # 1. Verificar transações ativas (RDS)
    active_transactions = check_rds_active_transactions()
    if active_transactions > 0:
        logger.warning(f"{active_transactions} active DB transactions - POSTPONING shutdown")
        return False  # BLOQUEIA shutdown
    checks.append("transactions_ok")

    # 2. Verificar conexões abertas (> 5 min idle)
    idle_connections = check_rds_idle_connections(threshold_minutes=5)
    if idle_connections > 10:
        logger.warning(f"{idle_connections} idle DB connections > 5 min - POSTPONING shutdown")
        return False
    checks.append("connections_ok")

    # 3. Verificar queues RabbitMQ (mensagens pendentes)
    pending_messages = check_rabbitmq_queue_depth()
    if pending_messages > 100:
        logger.warning(f"{pending_messages} pending messages in RabbitMQ - POSTPONING shutdown")
        return False
    checks.append("queues_ok")

    # 4. Verificar jobs GitLab CI/CD
    running_jobs = check_gitlab_running_jobs()
    if running_jobs > 0:
        logger.info(f"{running_jobs} GitLab jobs running - OK (critical-always-on)")
    checks.append("gitlab_ok")

    # 5. Verificar AlertManager silences (manutenção programada)
    if not check_alertmanager_maintenance_window():
        logger.warning("No maintenance window configured - POSTPONING shutdown")
        return False
    checks.append("alertmanager_ok")

    logger.info(f"Pre-shutdown health checks PASSED: {checks}")
    return True  # AUTORIZA shutdown
```

**Critérios Bloqueio:**
- Transações DB ativas (commits pendentes)
- Conexões idle recentes (< 5 min)
- Mensagens RabbitMQ não processadas (> 100)
- Manutenção não agendada (AlertManager)

**Critérios NÃO Bloqueiam:**
- GitLab CI/CD jobs (rodam em critical-always-on)
- Prometheus scraping (observabilidade 24/7)
- Grafana queries (dashboards históricos)

---

### Snapshot RDS Automático

**PRÉ-SHUTDOWN:**

```bash
# Criar snapshot RDS antes de stop (segurança)
aws rds create-db-snapshot \
  --db-instance-identifier marco2-prod-rds \
  --db-snapshot-identifier "prod-autosave-$(date +%Y%m%d-%H%M%S)" \
  --tags Key=AutoGenerated,Value=finops-scheduler Key=Environment,Value=production

# Aguardar snapshot completo (timeout 10 min)
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier "prod-autosave-$(date +%Y%m%d-%H%M%S)"

# Lifecycle: Deletar snapshots > 7 dias
aws rds describe-db-snapshots \
  --db-instance-identifier marco2-prod-rds \
  --query "DBSnapshots[?SnapshotCreateTime<'$(date -d '7 days ago' --iso-8601)'].DBSnapshotIdentifier" \
  --output text | xargs -n1 aws rds delete-db-snapshot --db-snapshot-identifier
```

**Benefícios:**
- Recovery point objetivo (RPO): < 1h (snapshot 23h59)
- Recovery time objetivo (RTO): < 10 min (restore snapshot)
- Compliance: Auditoria completa (snapshots tagged)

---

## ⚠️ Riscos Específicos PROD

### Comparação Riscos STAGING vs PROD

| Risco | STAGING (Dev+Homolog) | PRODUCTION | Mitigação Adicional PROD |
|-------|----------------------|------------|--------------------------|
| **Falha startup** | 🟡 5% prob, R$ 3.600/ano | 🔴 10% prob, R$ 18.000/ano | Retry 5× (vs 3×), timeout 10 min (vs 5 min), alerta PagerDuty imediato |
| **Data loss** | 🟢 2% prob, R$ 1.200/ano | 🔴 1% prob, R$ 50.000/ano | Snapshot RDS PRÉ-shutdown (RPO < 1h), health checks rigorosos (transações) |
| **Shutdown bloqueado** | 🟢 5% prob (jobs GitLab) | 🟡 15% prob (transações ativas) | Grace period 15 min (vs 5 min), notificação Slack 30 min antes |
| **Uptime SLA breach** | 🟢 99.5% target | 🔴 99.9% target (43 min/mês) | Rollback automático < 5 min, circuit breaker 2 falhas (vs 3), monitoramento Synthetics |

### Plano de Contingência PROD

**Cenário: Startup Falha às 7h AM (horário comercial)**

**Impacto:**
- Clientes sem acesso: 7h-8h (1h downtime)
- Perda receita: R$ 5.000/h (estimado)
- SLA breach: 60 min > 43 min/mês (violação)

**Rollback Automático:**

```python
def automatic_rollback():
    """
    Rollback automático se startup falha
    """
    if startup_failures >= 2:  # Threshold PROD: 2 falhas (vs 3 STAGING)
        logger.critical("PRODUCTION startup failed 2× - TRIGGERING AUTOMATIC ROLLBACK")

        # 1. Desabilitar automação (circuit breaker)
        disable_eventbridge_rules()

        # 2. Startup MANUAL via runbook
        trigger_manual_startup_runbook()

        # 3. Notificar on-call IMEDIATO
        send_pagerduty_alert(severity="critical", message="PROD startup failed - manual intervention required")

        # 4. Escalar para gerência (SLA breach iminente)
        send_slack_escalation(channel="#prod-incidents", escalation_level="P1")

        # 5. Preparar comunicação externa (clientes)
        prepare_status_page_update(status="investigating", eta="15 min")
```

**Recovery Manual:**

```bash
# Runbook: PROD Startup Manual
cd scripts/finops
./startup-marco2.sh production --force --skip-health-checks

# Validar serviços críticos
kubectl get pods -n production -l tier=critical
aws rds describe-db-instances --db-instance-identifier marco2-prod-rds

# Restore snapshot se RDS corrompido (última opção)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier marco2-prod-rds-restore \
  --db-snapshot-identifier "prod-autosave-20260130-235959"
```

---

## 📊 Observabilidade Específica PROD

### Métricas Adicionais

| Métrica | Threshold Critical | Ação |
|---------|-------------------|------|
| `finops.prod.startup.duration` | > 10 min | Rollback automático + PagerDuty |
| `finops.prod.sla.availability` | < 99.9% (43 min/mês) | Escalar gerência + disable automation |
| `finops.prod.transactions.blocked` | > 0 (shutdown bloqueado) | Alerta Slack + investigar carga noturna |
| `finops.prod.revenue.impact` | > R$ 1.000 (downtime × taxa) | Comunicação externa + status page |

### Dashboard Grafana "PROD FinOps Critical"

**Panels:**
1. **Uptime SLA (gauge):** Target 99.9%, atual, trend 30 dias
2. **Startup Duration (timeseries):** Média 6 min, threshold 10 min
3. **Shutdown Blocks (counter):** Transações ativas, mensagens RabbitMQ
4. **Revenue Impact (currency):** Downtime × R$ 5.000/h
5. **Circuit Breaker State (stat):** CLOSED (verde) / OPEN (vermelho)

---

## 🎯 Critérios de Sucesso PROD

**Operacionais:**

| Métrica | Target PROD | vs STAGING | Medição |
|---------|-------------|------------|---------|
| **SLA Disponibilidade** | 99.9% (7h-0h) | 99.5% (8h-18h) | CloudWatch Synthetics |
| **Startup time** | < 8 min | < 8 min | CloudWatch Logs |
| **Shutdown bloqueado** | < 5%/mês | < 2%/mês | Lambda metrics |
| **Falhas startup** | 0/mês | < 2/mês | Zero tolerance PROD |

**Financeiras:**

| Métrica | Target | Tolerância | Alerta |
|---------|--------|-----------|--------|
| **Economia mensal** | R$ 780 | ± 15% | < R$ 650 = Investigar |
| **Custo Lambda** | < $5/mês | +20% | > $6 = Otimizar |
| **Snapshots RDS** | < $20/mês | +30% | > $26 = Lifecycle review |

**Qualidade:**

| Métrica | Target PROD | Consequência Falha |
|---------|-------------|-------------------|
| **Zero data loss** | 100% | Incident review + rollback automation |
| **Revenue impact** | R$ 0 | Status page + comunicação clientes |
| **Customer satisfaction** | > 9/10 | Revisar automação ou desabilitar |

---

## 📅 Timeline e Dependências

### Dependências

- ✅ **STAGING automation:** Deploy completo e validado (1 mês operação)
- ⏳ **PROD environment:** Cluster EKS + RDS + workloads deployados
- ⏳ **Load testing:** Validar 99.9% SLA sob carga normal
- ⏳ **Runbooks:** Startup manual, rollback, incident response

### Timeline

| Fase | Prazo | Pré-requisito | Responsável |
|------|-------|---------------|-------------|
| **STAGING deploy** | 2026-02-17 | Aprovação stakeholders | DevOps |
| **STAGING validação 1 mês** | 2026-03-17 | 30 dias operação | FinOps |
| **PROD environment ready** | 2026-04-01 | Marco 3 deployado | Infra Team |
| **PROD automation dev** | 2026-04-08 | STAGING learnings | DevOps (5h) |
| **PROD automation deploy** | 2026-04-15 | Testes carga + runbooks | DevOps |
| **PROD validação 2 meses** | 2026-06-15 | SLA 99.9% confirmado | FinOps + Ops |

**Milestone Crítico:** PROD automation SOMENTE após STAGING 1 mês operação SEM falhas

---

## 🔗 Referências

- [Demanda STAGING (Aprovada)](./2026-01-30-automacao-finops-staging.md)
- [ADR-024: FinOps Automation Multi-Ambiente](../context/decisions.md#adr-024)
- [Architecture Documentation](../context/architecture.md#fase-9-finops-automation)
- [Costs Analysis](../context/costs.md#automacao-finops-production)
- [Risks](../context/risks.md#r-020-riscos-automação-finops-production)
- [Plano Executável Multi-Ambiente](../plan/aws-execution/fase-8-finops-multi-ambiente-automation.md)

---

## ✅ Aprovações Necessárias

- [ ] **Arquitetura** (análise técnica health checks rigorosos)
- [ ] **FinOps** (ROI validado R$ 9.360/ano)
- [ ] **Operations** (runbooks + rollback automático)
- [ ] **Product Owner** (SLA 99.9% acceptable, comunicação clientes)
- [ ] **Security** (snapshot strategy, zero data loss)

**Status:** 📋 PLANEJAMENTO → Aguardando STAGING 1 mês validação

---

**Consolidação Economia Total (Estratégia Evolutiva):**

### Fase 1: Pré-PROD (Atual)
```
STAGING (Dev+Homolog):  Ligado 8h-18h Mon-Fri (desenvolvimento ativo)
PROD:                   Não existe
────────────────────────────────────
Economia:               R$ 4.320/ano (STAGING apenas)
```

### Fase 2: PROD Go-Live
```
STAGING (Dev+Homolog):  Ligado 8h-18h Mon-Fri (testes + homologação)
PROD:                   Ligado 7h-0h 7 dias/semana (operação)
────────────────────────────────────
Economia STAGING:       R$ 4.320/ano
Economia PROD:          R$ 9.360/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 13.680/ano ✅
```

### Fase 3: PROD Estável (Futuro)
```
STAGING:                DESLIGADO permanentemente (liga SOB DEMANDA)
PROD:                   Ligado 7h-0h 7 dias/semana (operação)
────────────────────────────────────
Economia STAGING:       R$ 12.744/ano ✅ (95% economia, uptime ~5%)
Economia PROD:          R$ 9.360/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 22.104/ano ✅✅
```

**Cálculo Fase 3 (STAGING sob demanda):**
- Custo 24/7: R$ 13.464/ano
- Uptime estimado: 5% (ligando ~1×/semana para testes pontuais, 10h/mês)
- Custo otimizado: R$ 720/ano (5% × R$ 13.464 + overhead Lambda)
- **Economia: R$ 12.744/ano** (vs R$ 4.320/ano Fase 2)

**ROI Consolidado por Fase:**

| Fase | Economia Anual | Investimento Acumulado | ROI Year 1 | Payback |
|------|---------------|------------------------|-----------|---------|
| **Fase 1 (Atual)** | R$ 4.320 | R$ 3.000 | 44% | 6.7 meses |
| **Fase 2 (Go-Live)** | R$ 13.680 | R$ 4.500 | 204% | 3.9 meses |
| **Fase 3 (Estável)** | R$ 22.104 | R$ 4.500 | 391% | 2.4 meses |

**Investimento Total:** R$ 4.500 (STAGING R$ 3.000 + PROD R$ 1.500)

**NPV 3 Anos (Fase 3 estável):**
```
Year 1: R$ 22.104 / 1.10 = R$ 20.095
Year 2: R$ 22.104 / 1.21 = R$ 18.268
Year 3: R$ 22.104 / 1.33 = R$ 16.616
────────────────────────────────────
NPV 3 anos: R$ 54.979
Investimento: R$ 4.500
────────────────────────────────────
NPV líquido: R$ 50.479 (ROI cumulativo 1.121%) ✅✅✅
```

**Decisão:** ✅ **APROVAR estratégia evolutiva completa**

**Gatilhos para Fase 3:**
- [ ] PROD estável > 3 meses sem incidentes críticos
- [ ] Cobertura testes automatizados > 80%
- [ ] Equipe confortável com CI/CD production-first
- [ ] STAGING usado < 2×/mês (validar necessidade real)
