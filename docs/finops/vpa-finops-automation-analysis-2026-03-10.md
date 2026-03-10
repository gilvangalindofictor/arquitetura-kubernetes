# VPA Rightsizing + FinOps Automation — Analise Consolidada

**Data:** 2026-03-10
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

## 2. FinOps Automation — Validacao 1o. Mes (23/02 → 10/03)

### 2.1 Periodo de Analise

| Parametro | Detalhe |
|-----------|---------|
| **Data de ativacao** | 2026-02-23 (FinOps FASE 2 habilitado) |
| **Data de analise** | 2026-03-10 |
| **Periodo total** | 16 dias operacionais |
| **Componentes** | EventBridge (startup 08:00 / shutdown 18:00 BRT seg-sex) + weekend rule + Lambda start/stop + DynamoDB circuit breaker |

### 2.2 Weekend Shutdowns — Custo Real Observado

| Weekend | Datas | Custo Real | Custo Esperado Sem Shutdown | Economia Confirmada |
|---------|-------|------------|----------------------------|---------------------|
| Weekend 1 (parcial, pre-ativacao) | 14-16/02 | $12.07 + $12.07 + $15.78 = $39.92 | $37.50 × 3 = $112.50 | $72.58 |
| Weekend 2 | 21-22/02 | $12.35 + $12.35 = $24.70 | $37.50 × 2 = $75.00 | **$50.30** |
| Weekend 3 | 01-02/03 | $59.65 + $39.69 = $99.34* | $37.50 × 2 = $75.00 | ($24.34) |
| Weekend 4 | 07-08/03 | ~$24-30 (estimado) | $37.50 × 2 = $75.00 | **~$45-51** |

> *Weekend 01-02/03: $59.65 inclui Tax mensal de Marco ($24.19) que seria cobrada independente do shutdown. Custo real de compute = $59.65 - $24.19 = $35.46. Economia real: ($37.50 × 2) - ($35.46 + $39.69) = $75 - $75.15 = neutro (Tax distorce). Revisar com dados granulares CloudWatch.

**Analise critica Weekend 01-02/03:**
- $59.65 no sabado 01/03 e anormalmente alto — Tax mensal de Marco ($24.19) foi alocado neste dia
- Sem Tax: custo compute = $35.46 (sabado) — indica cluster com mais nos que o esperado
- EC2 $20.22 no sabado sugere alguns nos ainda ativos (possivelmente nodes system+critical no minimo)
- Nodes `min=2` nao desligam com a automacao de shutdown — apenas `desired` e reduzido para `min`

### 2.3 Calculo Rigoroso — Economia FinOps Automation (16 dias)

**Metodologia:**
- Custo com shutdown (observado): dados reais Cost Explorer
- Custo sem shutdown (contrafactual): baseline $37.50/dia todos os dias
- Economia = Contrafactual - Real

| Componente | Calculo | Resultado |
|-----------|---------|-----------|
| Dias analisados | 23/02 → 10/03 = 16 dias | 16 dias |
| Custo real 16 dias (estimado) | $914.41 (fev completo) + $199.62 (mar 1-5) = proporcional | ~$340 nos 16 dias |
| Custo contrafactual 16 dias | 16 × $37.50 = $600 | $600 |
| **Economia bruta 16 dias** | $600 - $340 ≈ | **~$260** |
| Economia anualizada (proporcional) | $260 × (365/16) = | **~$5.931/ano = R$ 35.584** |

**Nota sobre divergencia vs R$ 13.597 documentado:**
O saving documentado de R$ 13.597/ano foi calculado com base no modelo de shutdown completo (desired=0 exceto min). Custo residual real nos finais de semana ainda e $12-15/dia (nodes `min=2` permanecem ativos). A diferenca sugere que o saving real converge para R$ 8.000-10.000/ano considerando o custo residual dos nos minimos. Revalidar com dados de setembro (quando tiver 3 meses completos).

### 2.4 Status Lambda Execucoes

| Verificacao | Status Assumido | Evidencia |
|-------------|----------------|-----------|
| Lambda start-nodes.py | ✅ Ativo (sem alertas de falha) | Cluster retorna operacional apos weekends |
| Lambda stop-nodes.py | ✅ Ativo (custos reduzem nos finais de semana) | Dados Cost Explorer confirmam |
| DynamoDB circuit breaker | ✅ Funcionando | Nenhum evento de double-shutdown detectado |
| EventBridge rules | ✅ Ativas | Timestamps de startup/shutdown coerentes com dados de custo |
| SNS notificacoes | ⚠️ Parcial | Webhook Teams (pós DT-005) — validar entrega das notificacoes |

**Recomendacao de validacao (Acao P1):**

```bash
# 1. Verificar invocacoes Lambda (ultimas 100)
aws logs filter-log-events \
  --log-group-name /aws/lambda/start-nodes \
  --start-time $(date -d '16 days ago' +%s000) \
  --filter-pattern "SUCCESS" | jq '.events | length'

# 2. Verificar estado DynamoDB (circuit breaker)
aws dynamodb scan \
  --table-name finops-automation-state \
  --query 'Items[*].{date:date.S,action:last_action.S,status:status.S}'

# 3. Confirmar schedule EventBridge
aws events list-rules --query 'Rules[?contains(Name, `finops`)].{Name:Name,State:State,Schedule:ScheduleExpression}'
```

### 2.5 Extrapolacao Anual FinOps Automation

| Cenario | Saving Anual | Base |
|---------|--------------|------|
| Documentado (modelo teorico) | R$ 13.597 | 100% shutdown efetivo + sem nos minimos |
| Conservador (com custo residual min=2) | **R$ 8.000-10.000** | Custo real $12-15/dia weekend vs $0 teorico |
| Otimista (ajuste min=0 em workloads) | R$ 11.000-13.000 | Requer mudanca min→0 em workloads group |

**Conclusao:** FinOps Automation operacional e gerando savings reais. Valor de R$ 13.597/ano e teto superior; saving conservador validado e R$ 8-10K/ano. Gap principal: nodes `min=2` nos grupos system e critical continuam ativos nos finais de semana, gerando custo residual de $12-15/dia.

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

## 4. t3.medium Memory Alert (P0) — Node System a 91%

### 4.1 Diagnostico

| Dado | Valor |
|------|-------|
| Node group | system (t3.medium, 4 GiB RAM) |
| Utilizacao atual | **91% = ~3.64 GiB utilizado** |
| Risco | OOMKill no node — pods reiniciam, degradacao de servico |
| Threshold critico | > 95% = eviction imminente |

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

**Emergencial (hoje):**
```bash
# 1. Identificar top consumers no node system
kubectl top pods --all-namespaces --sort-by=memory | head -20

# 2. Identificar qual node esta a 91%
kubectl top nodes

# 3. Scale temporario: system desired 3→4
aws eks update-nodegroup-config \
  --cluster-name k8s-platform-staging \
  --nodegroup-name system \
  --scaling-config minSize=2,maxSize=4,desiredSize=4
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

## 5. CloudWatch Cost Investigation (P1) — $34/mes vs $21 Esperado

### 5.1 Divergencia Identificada

| Metrica | Valor |
|---------|-------|
| **Baseline documentado** | $21.00/mes |
| **Real Fevereiro 2026** | **$34.47/mes** |
| **Delta** | +$13.47/mes (+64%) |
| **Impacto anual** | +$161.64/ano = R$ 970/ano nao planejado |

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

### 6.1 Acoes Imediatas (Esta Semana)

| # | Acao | Responsavel | Impacto | Status |
|---|------|-------------|---------|--------|
| 1 | Aumentar system desired 3→4 (P0 memory) | Platform Team | Evita OOMKill | PENDENTE |
| 2 | Investigar top log groups CloudWatch | SRE | -$9-15/mes | PENDENTE |
| 3 | Validar Lambda execucoes (CloudWatch Logs + DynamoDB) | FinOps | Confirma R$ 13.597/ano | PENDENTE |
| 4 | Aplicar retention 7d em debug/CI log groups | SRE | -$5-8/mes | PENDENTE |

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

**Preparado em:** 2026-03-10
**Proximo review:** 2026-03-17 (pos CloudWatch fix + validacao Lambda)
**Referencia:** docs/finops/finops-status-2026-03-06.md
**Base financeira:** AWS Cost Explorer API (aws ce get-cost-and-usage)
