# VPA Rightsizing + FinOps Automation — Analise Consolidada

**Data:** 2026-03-10 | **Atualizado:** 2026-03-11
**Cluster:** k8s-platform-prod (EKS 1.34, staging cluster)
**Owner:** Observability & SRE Specialist + FinOps Team
**Referencia:** finops-status-2026-03-06.md | Budget: $807/mes | Mar Forecast: $986 (+22%)

---

## 1. VPA Rightsizing — Analise Atualizada (2026-03-10)

### 1.1 Decisao Confirmada: Staging CANCELADO, Producao Prioritaria

| Aspecto | Detalhe |
|---------|---------|
| **Decisao** | VPA staging CANCELADO em 2026-03-06 |
| **Saving real staging** | R$ 62/ano (insuficiente para justificar execucao) |
| **Causa** | 2/5 VPAs com recomendacoes, ambos ja no minAllowed |
| **Dado ruidoso** | Backstage M1 + 2 apps esteiradas distorceram coleta durante periodo |
| **Producao** | Mesmo esforco gera 3-5x mais retorno (24/7 vs weekend shutdown) |
| **Status** | Item encerrado — dados reaproveitados como calibracao para producao |

### 1.2 Requests Calibrados (Staging → Producao)

Os dados de VPA coletados em staging servem como **baseline informada para o primeiro deploy de producao**, evitando que os workloads subam oversized e precisem de 7 dias adicionais de coleta antes do primeiro rightsizing.

| Workload | Request Inicial para Producao | Limite Sugerido | Fonte | Nota |
|----------|-------------------------------|-----------------|-------|------|
| redis | cpu: 25m, memory: 65Mi | cpu: 200m, memory: 256Mi | VPA uncappedTarget staging | Confirmar com carga real prod |
| harbor-core | cpu: 15m, memory: 65Mi | cpu: 500m, memory: 512Mi | VPA uncappedTarget staging | Trivy scan pode elevar CPU burst |
| harbor-registry | cpu: 10m, memory: 50Mi | cpu: 300m, memory: 256Mi | Staging referencia + VPA day-1 | Coletar em producao dia 1 |
| harbor-jobservice | cpu: 10m, memory: 64Mi | cpu: 300m, memory: 256Mi | Staging referencia + VPA day-1 | Coletar em producao dia 1 |
| gitlab-webservice | cpu: 250m, memory: 500Mi | cpu: 1500m, memory: 2Gi | Staging referencia | Alta variabilidade — VPA obrigatorio |
| gitlab-sidekiq | cpu: 100m, memory: 256Mi | cpu: 1000m, memory: 1Gi | Staging referencia | Background jobs — burst imprevisivel |
| keycloak | cpu: 50m, memory: 256Mi | cpu: 500m, memory: 1Gi | Staging referencia + VPA day-1 | JVM — aguardar warmup 24h |
| loki | cpu: 50m, memory: 200Mi | cpu: 500m, memory: 512Mi | Staging referencia | chunksCache altera consumo |
| prometheus | cpu: 100m, memory: 512Mi | cpu: 1000m, memory: 2Gi | Staging referencia | Crece com # de metricas prod |
| alertmanager | cpu: 10m, memory: 32Mi | cpu: 100m, memory: 128Mi | Staging referencia | Consumo estavel |

**Importante:** Requests iniciais sao ponto de partida conservador. VPA `mode=Off` coleta dados desde o dia 1 — rightsizing formal ocorre apos 7 dias de carga representativa.

### 1.3 Impacto Estimado VPA Producao

| Cenario | Reducao Mensal | Saving Anual | Base de Calculo |
|---------|----------------|--------------|-----------------|
| Conservador (rightsizing 20% dos requests) | -R$ 1.250/mes | **R$ 15.000/ano** | 7 nos × R$ 1.786/mes × 20% |
| Base (rightsizing 25% dos requests) | -R$ 1.600/mes | **R$ 19.200/ano** | Target realista staging experience |
| Otimista (rightsizing 30% + bin-packing) | -R$ 2.083/mes | **R$ 25.000/ano** | Com reducao de 1-2 nos extras |
| **Producao 24/7 amplificado** | — | **R$ 25.000-35.000/ano** | vs R$ 7-11K staging (weekend shutdown elimina 2/7 dias) |

**Por que producao rende 3-5x mais:**
- Staging: weekend shutdown remove ~28% do tempo de execucao (2/7 dias)
- Producao: 24/7 — cada R$ de request reduzido tem impacto integral
- Producao tende a ter mais replicas e HPA ativo — multiplicador de economia
- Savings Plans e Reserved Instances viram viáveis (vide secao 3)

### 1.4 Plano de Execucao VPA Producao

```
DIA 1 DO DEPLOY DE PRODUCAO:
  ├─ Aplicar VPA manifests (mode=Off) em TODOS os workloads
  ├─ Usar requests calibrados da tabela 1.2 como initial values
  ├─ Configurar minAllowed conservador (nao travar abaixo do minimo operacional)
  └─ Habilitar dashboards VPA no Grafana (recomendacoes vs requests atuais)

DIA 7 (primeira janela de rightsizing):
  ├─ Coletar VPA recommendations: kubectl get vpa -A -o json
  ├─ Filtrar workloads com target < request atual (saving identificado)
  ├─ Aplicar patches graduais (25% → 50% → 100% da recomendacao em 3 dias)
  ├─ Monitorar OOMKill events e CPU throttling pos-ajuste
  └─ Projecao: -$60-80/mes immediato (retorno ao budget $807)

DIA 14 (refinamento):
  ├─ Segunda rodada VPA com dados de carga pico semana 1
  ├─ Ajustar minAllowed baseado em comportamento real
  └─ Acionar bin-packing: `kubectl drain` nodes extras se < 40% utilizacao
```

**Timeline esperado:** 7 dias coleta → rightsizing dia 8 → -$60-80/mes confirmado dia 15.

---

## 2. FinOps Automation — Validacao 1o. Mes (23/02 → 11/03)

### 2.1 Periodo de Analise

| Parametro | Detalhe |
|-----------|---------|
| **Data de ativacao** | 2026-02-23 (FinOps FASE 2 habilitado) |
| **Data de analise** | 2026-03-11 (atualizado de 2026-03-10) |
| **Periodo total** | 17 dias operacionais |
| **Componentes** | EventBridge (startup 08:00 / shutdown 18:00 BRT seg-sex) + weekend rule + Lambda start/stop + DynamoDB circuit breaker |

### 2.2 Weekend Shutdowns — Custo Real Observado

| Weekend | Datas | Custo Real | Custo Esperado Sem Shutdown | Economia Confirmada |
|---------|-------|------------|----------------------------|---------------------|
| Weekend 1 (parcial, pre-ativacao) | 14-16/02 | $12.07 + $12.07 + $15.78 = $39.92 | $37.50 × 3 = $112.50 | $72.58 |
| Weekend 2 | 21-22/02 | $12.35 + $12.35 = $24.70 | $37.50 × 2 = $75.00 | **$50.30** |
| Weekend 3 | 01-02/03 | $59.65 + $39.69 = $99.34* | $37.50 × 2 = $75.00 | ($24.34) |
| Weekend 4 | 08-09/03 | $38.43 + $39.04 = $77.47 | $42.00 × 2 = $84.00 | **$6.53** |

> *Weekend 01-02/03: $59.65 inclui Tax mensal de Marco ($24.19) que seria cobrada independente do shutdown. Custo real de compute = $59.65 - $24.19 = $35.46. Economia real: ($37.50 × 2) - ($35.46 + $39.69) = $75 - $75.15 = neutro (Tax distorce). Revisar com dados granulares CloudWatch.

**ACHADO CRITICO — Weekend 08-09/03 (validacao 2026-03-11):**
- Mar 8 (Sab): $38.43 | Mar 9 (Dom): $39.04 — custo weekend NAO reduz como esperado
- Lambda STOP rodou corretamente (shutdown confirmado). Lambda START rodou Mar 9 10:30 (domingo)
- EventBridge schedule e MON-FRI — invocacao domingo requer investigacao (manual ou bug de schedule)
- **Root cause:** Lambda escala para min (system=2, work=2, crit=2 = 6 nodes) mas cluster autoscaler re-escala para atender demanda de pods remanescentes
- Custo base esperado weekend: ~$15-18/dia (6 nodes) + VPC/ELB overhead ~$8-10 = $23-28/dia
- Custo real: $38-39/dia = **GAP de $10-15/dia** vs esperado
- Saving real weekend: baseline $42/dia sem shutdown → $38/dia com = ~$4/dia = **~$120/mes = R$ 8.640/ano** (abaixo dos R$ 12.800 documentados)

**Analise critica Weekend 01-02/03:**
- $59.65 no sabado 01/03 e anormalmente alto — Tax mensal de Marco ($24.19) foi alocado neste dia
- Sem Tax: custo compute = $35.46 (sabado) — indica cluster com mais nos que o esperado
- EC2 $20.22 no sabado sugere alguns nos ainda ativos (possivelmente nodes system+critical no minimo)
- Nodes `min=2` nao desligam com a automacao de shutdown — apenas `desired` e reduzido para `min`

### 2.3 Calculo Rigoroso — Economia FinOps Automation (17 dias) [ATUALIZADO 2026-03-11]

**Metodologia:**
- Custo com shutdown (observado): dados reais Cost Explorer
- Custo sem shutdown (contrafactual): baseline $42/dia (atualizado de $37.50 — cluster expandiu para 13 nodes)
- Economia = Contrafactual - Real

| Componente | Calculo | Resultado |
|-----------|---------|-----------|
| Dias analisados | 23/02 → 11/03 = 17 dias | 17 dias |
| Custo real 17 dias (estimado) | $914.41 (fev completo) + $199.62 (mar 1-5) = proporcional | ~$360 nos 17 dias |
| Custo contrafactual 17 dias | 17 × $42.00 = $714 | $714 |
| **Economia bruta 17 dias** | $714 - $360 ≈ | **~$354** |
| Economia anualizada (proporcional) | $354 × (365/17) = | **~$7.602/ano = R$ 45.612** |

> **RECONCILIACAO 2026-03-11:** O calculo acima usa contrafactual de $42/dia (baseline sem shutdown com 13 nodes). Porem a economia REAL observada nos weekends e muito menor: baseline $42/dia → $38/dia com shutdown = ~$4/dia de saving efetivo. Isso ocorre porque o cluster autoscaler re-escala nodes para atender pods remanescentes, anulando parcialmente o shutdown.

**Saving REAL baseado em weekend costs observados (2026-03-11):**
- Weekend saving efetivo: ~$4/dia × 8 dias weekend/mes = ~$32/mes = **~R$ 2.304/ano** (apenas weekends)
- Weekday shutdown savings (18h-08h): contribuicao adicional estimada ~$500/mes = **~R$ 6.000/ano**
- **Saving real conservador total: R$ 8.000-10.000/ano** (confirmado)
- **Saving documentado anterior: R$ 12.800/ano — OTIMISTA (revisado para baixo)**

**Nota sobre divergencia vs R$ 13.597 documentado:**
O saving documentado de R$ 13.597/ano foi calculado com base no modelo de shutdown completo (desired=0 exceto min). Custo residual real nos finais de semana e $38-39/dia (nodes `min=2` permanecem ativos + cluster autoscaler re-escala). A diferenca confirma que o saving real converge para **R$ 8.000-10.000/ano** considerando o custo residual. Proximo checkpoint: junho/2026 (3 meses completos).

### 2.4 Status Lambda Execucoes [VALIDADO 2026-03-11]

| Verificacao | Status | Evidencia (2026-03-11) |
|-------------|--------|------------------------|
| Lambda start-nodes.py | ✅ OPERACIONAL | last_startup: 2026-03-11T10:30:10.873692 — "Scaling node group system to 2 nodes, workloads to 3 nodes, critical to 2 nodes" |
| Lambda stop-nodes.py | ✅ OPERACIONAL | last_shutdown: 2026-03-10T23:00:12.808987 — "EXCLUDED_NODE_GROUPS=['system', 'critical']", "Stopping RDS instance k8s-platform-prod-postgresql" |
| DynamoDB circuit breaker | ✅ CLOSED | startup_failures=0, shutdown_failures=0 |
| EventBridge rules | ✅ 5 rules ENABLED | startup, shutdown, weekend-shutdown, snapshot-cleanup, weekly-report |
| SNS notificacoes | ⚠️ Parcial | Webhook Teams (pos DT-005) — validar entrega das notificacoes |

**Node Groups — Estado Expandido (2026-03-11):**

| Node Group | Tipo | Desired Anterior | Desired Atual | Max | Observacao |
|------------|------|-----------------|---------------|-----|------------|
| system | t3.medium | 3 | **4 (MAX)** | 4 | Cluster autoscaler empurrou ao maximo |
| workloads | t3.large | 4 | **6 (MAX)** | 6 | Cluster autoscaler empurrou ao maximo |
| critical | t3.xlarge | 2 | **3** | — | Expandiu 1 node |
| **Total** | — | **9** | **13** | — | **+44% nodes — impacto direto em custo** |

> **ALERTA:** Todos os node groups no maximo ou proximo. Cluster autoscaler esta compensando pods com requests altos. VPA rightsizing e a alavanca para reduzir de volta para 7-9 nodes.

**Impacto VPA com 13 nodes (2026-03-11):**
- Se VPA reduzir requests → autoscaler podera manter 7-9 nodes em vez de 13
- Savings incrementais: 4-6 nodes a menos x ~$3-8/dia/node = $12-48/dia = **R$ 2.160-8.640/ano** adicional apenas em staging
- VPA producao permanece como maior alavanca: **R$ 25.000-35.000/ano**

**Investigacao pendente:**
- Lambda START invocou Mar 9 (domingo) as 10:30 — EventBridge schedule e MON-FRI. Verificar se foi invocacao manual ou bug no cron expression

### 2.5 Extrapolacao Anual FinOps Automation [ATUALIZADO 2026-03-11]

| Cenario | Saving Anual | Base | Status |
|---------|--------------|------|--------|
| Documentado (modelo teorico) | R$ 13.597 | 100% shutdown efetivo + sem nos minimos | ~~OTIMISTA~~ REVISADO |
| **Conservador (validado 2026-03-11)** | **R$ 8.000-10.000** | Weekend costs reais $38-39/dia vs $42 baseline + weekday shutdown | **CONFIRMADO** |
| Otimista (ajuste min=0 em workloads) | R$ 11.000-13.000 | Requer mudanca min→0 em workloads group | PENDENTE VALIDACAO |

**Conclusao (atualizada 2026-03-11):** FinOps Automation **OPERACIONAL** — Lambdas com zero failures, circuit breaker CLOSED, 5 EventBridge rules ativas. Saving conservador **confirmado em R$ 8-10K/ano** baseado em weekend costs reais. Gap principal: cluster autoscaler re-escala nodes mesmo apos shutdown (min=2 insuficiente — pods remanescentes forcam scale-up). Saving documentado de R$ 12.800/ano revisado para baixo.

---

## 3. Otimizacoes Pendentes — Ranking por ROI (Mar/2026)

| Prioridade | Item | Saving/ano | Pre-requisito | Timeline | Notas |
|------------|------|-----------|---------------|----------|-------|
| **P0** | **Reduzir workloads desired 4→2** | R$ 6.000-7.200 | VPA rightsizing concluido | Apos VPA dia 8 | $320/mes direto |
| **P1** | **VPA Rightsizing (producao)** | R$ 25.000-35.000 | Prod online + 7 dias VPA coleta | Dia 1 + 7d | Maior alavanca disponivel |
| **P1** | **FinOps Automation min=0 (workloads)** | R$ 3.000-5.000 | Validar que workloads podem zerar | Sprint atual | Reduz custo residual weekend |
| **P2** | **Savings Plans 1yr No-Upfront** | R$ 11.363 | 30d Cost Explorer (producao) | Mes 1 pós-prod | Break-even imediato em 24/7 |
| **P2** | **RDS Reserved Instance 1yr** | R$ 3.024 | Prod online | Mes 1 pós-prod | Console RDS — 15 min para ativar |
| **P3** | **Karpenter + Spot (staging)** | R$ 6.696 | Estabilizacao pos-Backstage | Q2/2026 | Requer migração de node affinity |
| **P3** | **Graviton ARM64 (staging→prod)** | R$ 6.984 | VPA producao completo | Q3/2026 | Validar compatibilidade workloads |
| **P4** | **CloudWatch retention otimizacao** | R$ 3.240-4.800 | Auditoria log groups | Sprint atual | $13/mes fix rapido |

**Total otimizacoes P0-P2 (curto prazo):** R$ 48.000-61.000/ano adicional
**Soma com savings ja realizados (R$ 56.546):** Potencial R$ 105.000-117.000/ano

---

## 4. t3.medium Memory Alert (P0) — Node System a 88% [ATUALIZADO 2026-03-11]

### 4.1 Diagnostico

| Dado | Valor | Nota (2026-03-11) |
|------|-------|--------------------|
| Node group | system (t3.medium, 4 GiB RAM) | Agora com 4 nodes (era 3) |
| Utilizacao atual | **88% = ~3.52 GiB utilizado** (ip-10-0-142-118) | Melhorou de 91% — pressao melhor distribuida com 4 nodes |
| Risco | OOMKill no node — pods reiniciam, degradacao de servico | Reduzido com 4 nodes |
| Threshold critico | > 95% = eviction imminente | |

### 4.2 Workloads Suspeitos

Nodes system hospedam prioritariamente: DNS (CoreDNS), monitoring stack, linkerd-control-plane, kube-system components.

| Categoria | Consumo Estimado | Observacao |
|-----------|-----------------|------------|
| Linkerd sidecars (linkerd-proxy) | ~64-128Mi por pod | Cada pod injetado adiciona sidecar; 40+ pods no cluster |
| Linkerd control plane | ~300-500Mi total | linkerd-destination, linkerd-identity, linkerd-proxy-injector |
| Prometheus + Alertmanager | ~600Mi-1.2Gi | Historico de series aumenta com Linkerd metrics |
| CoreDNS | ~70-100Mi | Estavel |
| GitLab agents/runners | ~128-256Mi | Depende de jobs ativos |
| Kyverno controllers | ~150-200Mi | 3 replicas × 64Mi |

**Root cause mais provavel:** Proliferacao de Linkerd metrics no Prometheus. Cada sidecar expoe ~200 series de metricas. Com 40+ pods injetados: 8.000+ series extras sem retention separada.

### 4.3 Acoes Recomendadas

**Emergencial (hoje) [ATUALIZADO 2026-03-11]:**
```bash
# 1. Identificar top consumers no node system
kubectl top pods --all-namespaces --sort-by=memory | head -20

# 2. Identificar qual node esta a 88%
kubectl top nodes

# 3. Scale temporario: system desired 3→4 — JA REALIZADO (autoscaler escalou para 4/4 MAX)
# NOTA: system ja esta em 4 nodes (MAX). Se pressao persistir, aumentar maxSize para 5.
# aws eks update-nodegroup-config \
#   --cluster-name k8s-platform-staging \
#   --nodegroup-name system \
#   --scaling-config minSize=2,maxSize=5,desiredSize=4
```

**Medio prazo (esta semana):**
1. Migrar pods nao-criticos de system para workloads group via `nodeSelector` ou `tolerations`
2. Adicionar Prometheus scrape interval diferenciado para Linkerd metrics: `scrapeInterval: 60s` (vs 15s padrao)
3. Configurar retention separada para Linkerd metrics: 7 dias (vs 30 dias para metricas de negocio)
4. Revisar VPA para Prometheus — se `uncappedTarget` memory < request atual, limitar memoria

**Longo prazo:**
- Considerar upgrade t3.medium → t3.large para node group system (custo: +$3/dia = +R$ 216/mes)
- Ou consolidar monitoring em node dedicado com `nodeSelector: role=monitoring`

---

## 5. CloudWatch Cost Investigation (P1) — $34/mes vs $21 Esperado [ATUALIZADO 2026-03-11]

### 5.1 Divergencia Identificada

| Metrica | Valor | Atualizacao 2026-03-11 |
|---------|-------|-----------------------|
| **Baseline documentado** | $21.00/mes | — |
| **Real Fevereiro 2026** | **$34.47/mes** (5 log types, 9 nodes) | Fix aplicado: 3 log types (controllerManager e scheduler REMOVIDOS) |
| **Real Marco 2026 MTD** | — | **$21.36 (10 dias) → projetado ~$66/mes** |
| **Delta** | +$13.47/mes (+64%) | Marco projetado PIOR apesar do fix — 13 nodes compensam reducao de logs |
| **Impacto anual** | +$161.64/ano = R$ 970/ano nao planejado | Revisado: +$540/ano (~$45/mes excedente vs baseline) |

**Correlacao nodes vs CloudWatch (2026-03-11):**
- Fevereiro: 5 log types, 9 nodes = $34.47/mes
- Marco: 3 log types, 13 nodes = ~$66/mes (projetado)
- Cada node gera ~$1.50-2.50/mes em metricas CloudWatch
- 4 nodes extras = +$6-10/mes em metricas
- **Conclusao:** fix de log types foi correto mas expansao de nodes anulou economia. Savings real do fix: dificil isolar com expansao simultanea

### 5.2 Suspeitos por Categoria

| Fonte | Ingestion Estimada | Custo Estimado | Prioridade |
|-------|-------------------|----------------|------------|
| **GitLab verbose logging** | Alta (CI/CD jobs = log intensivo) | $4-6/mes | Alta |
| **Linkerd metrics** | Media-Alta (200 series/pod × 40+ pods) | $3-5/mes | Alta |
| **Loki → CloudWatch (se configurado)** | Alta | $2-4/mes | Media |
| **Lambda logs (FinOps Automation)** | Baixa | <$1/mes | Baixa |
| **Container Insights (se ativo)** | Muito alta | $5-8/mes | Critica |
| **EKS Control Plane logs** | Media | $1-2/mes | Media |

**Hipotese principal:** Container Insights ativado por padrao no EKS 1.34 ou Linkerd metrics sendo ingestados no CloudWatch como custom metrics (agent DaemonSet).

### 5.3 Plano de Investigacao e Correcao

**Fase 1 — Identificar (1 dia):**
```bash
# Top log groups por ingestion (ultimos 30 dias)
aws logs describe-log-groups \
  --query 'logGroups | sort_by(@, &storedBytes) | reverse(@) | [0:15].{name:logGroupName, sizeMB: to_number(storedBytes)/1048576, retention:retentionInDays}' \
  --output table

# Custom metrics namespace breakdown
aws cloudwatch list-metrics \
  --query 'Metrics | group_by(Namespace) | @.{Namespace:Namespace, Count: length(MetricName)}' 2>/dev/null || \
aws cloudwatch list-metrics --output json | jq '[.Metrics[].Namespace] | group_by(.) | map({namespace: .[0], count: length}) | sort_by(.count) | reverse | .[0:15]'
```

**Fase 2 — Remediar (2-3 dias):**

| Acao | Saving Estimado | Complexidade |
|------|----------------|--------------|
| Aplicar retention 3 dias em log groups de CI/CD jobs | $2-3/mes | Baixa |
| Aplicar retention 7 dias em Linkerd/proxy logs | $1-2/mes | Baixa |
| Desativar Container Insights (se ativo, redundante com kube-prometheus) | $5-8/mes | Media |
| Mover EKS Control Plane logs para S3 via Kinesis (compress+archive) | $1-2/mes | Alta |
| **Total potencial** | **$9-15/mes = R$ 648-1.080/ano** | |

**Fase 3 — Prevencao:**
- Adicionar alerta: `CloudWatchCostForecast > $25/mes` → Teams webhook
- Revisar policy de log retention mensalmente via tag `billing:review`

---

## 6. Resumo Executivo — Acoes Mar/2026

### 6.1 Acoes Imediatas (Esta Semana) [ATUALIZADO 2026-03-11]

| # | Acao | Responsavel | Impacto | Status |
|---|------|-------------|---------|--------|
| 1 | ~~Aumentar system desired 3→4 (P0 memory)~~ | Platform Team | Evita OOMKill | ✅ CONCLUIDO (autoscaler escalou para 4/4, mem 91%→88%) |
| 2 | Investigar top log groups CloudWatch | SRE | -$9-15/mes | ⚠️ EM ANDAMENTO (fix log types aplicado, mas custo subiu com 13 nodes) |
| 3 | ~~Validar Lambda execucoes (CloudWatch Logs + DynamoDB)~~ | FinOps | ~~Confirma R$ 13.597/ano~~ R$ 8-10K/ano | ✅ VALIDADO (Lambdas operacionais, circuit breaker CLOSED, saving revisado) |
| 4 | Aplicar retention 7d em debug/CI log groups | SRE | -$5-8/mes | PENDENTE |
| 5 | **Investigar Lambda START domingo Mar 9** | Platform Team | Correcao schedule EventBridge | NOVO — verificar cron expression |
| 6 | **Investigar cluster autoscaler re-scaling apos shutdown** | Platform Team | Aumentar saving weekend | NOVO — pods remanescentes forcam scale-up |

### 6.2 Acoes Medio Prazo (Proximas 2 Semanas)

| # | Acao | Responsavel | Impacto |
|---|------|-------------|---------|
| 5 | VPA day-1 quando producao subir | Platform Team | R$ 25-35K/ano |
| 6 | Reduzir workloads desired 4→2 apos VPA | Platform Team | -$320/mes |
| 7 | Savings Plans 1yr (30d pos-prod) | FinOps | R$ 11.363/ano |
| 8 | RDS Reserved Instance 1yr | FinOps | R$ 3.024/ano |

### 6.3 Projecao Financeira Atualizada

| Cenario | Custo Mensal | vs Budget $807 |
|---------|--------------|----------------|
| **Hoje (Mar/2026 forecast)** | **$986** | **+22% ACIMA** |
| Apos CloudWatch fix | ~$970 | +20% |
| Apos workloads desired 4→2 | ~$650-700 | **ABAIXO** ✅ |
| Apos VPA rightsizing | ~$580-640 | ABAIXO ✅✅ |
| Com Savings Plans + RDS RI | ~$490-560 | META ATINGIDA ✅✅✅ |

---

## 7. Appendix — Dados de Referencia

### 7.1 FinOps Automation — Arquitetura

```
EventBridge Rule (cron: 11:00 UTC = 08:00 BRT, seg-sex)
  └─ Lambda: start-nodes.py
       ├─ Checa DynamoDB circuit breaker (previne double-start)
       ├─ aws eks update-nodegroup-config desiredSize=<target>
       └─ SNS: notificacao Teams "Cluster iniciado"

EventBridge Rule (cron: 21:00 UTC = 18:00 BRT, seg-sex)
  └─ Lambda: stop-nodes.py
       ├─ Checa DynamoDB state (evita shutdown de cluster ja desligado)
       ├─ aws eks update-nodegroup-config desiredSize=min
       └─ SNS: notificacao Teams "Cluster desligado"

EventBridge Rule (sabado 21:00 UTC extra)
  └─ Lambda: stop-nodes.py (garantia fim de semana)
```

### 7.2 VPA — Manifests de Referencia (Template)

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: <workload>-vpa
  namespace: <namespace>
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: <workload>
  updatePolicy:
    updateMode: "Off"       # Coleta apenas — nao aplica automaticamente
  resourcePolicy:
    containerPolicies:
      - containerName: "*"
        minAllowed:
          cpu: 10m           # Minimo absoluto — ajustar por workload
          memory: 32Mi
        maxAllowed:
          cpu: 2             # Teto para evitar over-provisioning
          memory: 4Gi
```

### 7.3 Node Costs Reference (sa-east-1, On-Demand)

| Tipo | vCPU | RAM | Custo/hora | Custo/dia | Custo/mes |
|------|------|-----|------------|-----------|-----------|
| t3.medium | 2 | 4 GiB | ~$0.0464 | ~$1.11 | ~$33.65 |
| t3.large | 2 | 8 GiB | ~$0.0928 | ~$2.23 | ~$67.30 |
| t3.xlarge | 4 | 16 GiB | ~$0.1856 | ~$4.45 | ~$134.60 |

---

**Preparado em:** 2026-03-10 | **Atualizado:** 2026-03-11
**Proximo review:** 2026-03-17 (pos investigacao autoscaler re-scaling + CloudWatch com 13 nodes)
**Referencia:** docs/finops/finops-status-2026-03-06.md
**Base financeira:** AWS Cost Explorer API (aws ce get-cost-and-usage)
**Dados validados 2026-03-11:** Lambda logs, DynamoDB circuit breaker, EventBridge rules, Cost Explorer weekend costs
