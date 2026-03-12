# Relatorio FinOps — Status Financeiro Atualizado

**Data:** 2026-03-11
**Cluster:** k8s-platform-prod (EKS 1.34)
**Periodo de Referencia:** Jan/2026 — Mar/2026
**Fonte Dados:** AWS Cost Explorer API (dados reais coletados 2026-03-11)
**Status Geral:** CRITICO — Forecast Mar +51% acima do budget | 13 nodes ativos | Weekend savings comprometido

---

## 1. Resumo Executivo

| Metrica | Valor |
|---------|-------|
| **Custo Fevereiro 2026 REAL** | **$914.41 = R$ 5.487** |
| **Budget Marco 3 Aprovado** | $807/mes (R$ 4.841) |
| **Mar/2026 MTD REAL (10 dias)** | **$426.72** |
| **Mar/2026 Daily rate (dias 2-10)** | **$37.57/dia** |
| **Forecast Marco 2026 (calculado)** | **$1,217/mes = R$ 7.300** |
| **Status Marco vs Budget** | **ACIMA em $410 (+51%)** — ERA +22% NO RELATORIO ANTERIOR |
| **Forecast anterior (2026-03-10)** | $986/mes |
| **Degradacao vs forecast anterior** | **+$231 (+23% pior)** |
| **Reducao vs Baseline** | -21% (vs -40% em Fev) — REGRESSAO |
| **Savings Realizados (acumulado)** | **R$ 57.461/ano** |
| **Meta Original** | R$ 62.000/ano |
| **Realizacao vs Meta** | **92.7%** |

**ALERTA CRITICO:** O forecast de Marco subiu de $986 (relatorio 03-10) para $1,217 (+23%). Causa principal: cluster escalou de 9 para 13 nodes e custos de weekend nao estao atingindo o minimo esperado.

**Causa raiz do desvio:**
- Cluster autoscaler atingiu maximo em TODOS os node groups (system=4/4, workloads=6/6, critical=3/4)
- 13 nodes ativos vs 9 no periodo anterior (+44% de compute)
- 234 pods vs ~209 anteriormente (+12%)
- Weekend costs $38-39/dia vs esperado $15-18/dia (Lambda STOP executa mas cluster re-escala)

---

## 2. Savings Totais Realizados — Estado 2026-03-11

### 2.1 Tabela Completa de Savings

| Otimizacao | Data | Economia Anual | Status |
|-----------|------|----------------|--------|
| EKS Upgrade 1.31 → 1.34 | 2026-02-10 | R$ 25.920 | ATIVO |
| ALBs deletados (nginx-test + echo-server) | 2026-02-11 | R$ 1.920 | ATIVO |
| NLBs deletados (RabbitMQ) | 2026-02-11 | R$ 384 | ATIVO |
| CloudWatch Logs retention | 2026-02-12 | R$ 54 | ATIVO |
| S3 Gateway Endpoint (NAT savings) | 2026-02-12 | R$ 900 | ATIVO |
| Orphan cleanup (EBS volumes + snapshots) | 2026-02-12 | R$ 2.221 | ATIVO |
| Orphan detector Lambda | 2026-02-12 | R$ 1.000 | ATIVO |
| EBS gp2 → gp3 (nodes + Prometheus) | 2026-02-13 | R$ 859 | ATIVO |
| Snapshot Cleanup Lambda | 2026-02-13 | R$ 216 | ATIVO |
| RDS Weekend Shutdown | 2026-02-18 | R$ 1.200 | ATIVO |
| Keycloak backup automation | 2026-02-18 | R$ 1.200 | ATIVO |
| SonarQube exporter | — | R$ 50 | ATIVO |
| FinOps FASE 2 — Automacao EventBridge | 2026-02-23 | R$ 12.800 | ATIVO — EFICACIA REDUZIDA |
| PDB Optimization — shutdown graceful | 2026-02-24 | R$ 4.405 | ATIVO |
| Snapshot DLM (3 policies: 30d/14d/7d) | 2026-02-27 | R$ 5.052 | ATIVO |
| Node Group Protection (custo confiabilidade) | 2026-02-27 | -R$ 720 | ATIVO |
| **TOTAL REALIZADOS** | | **R$ 57.461/ano** | **92.7% da meta** |
| CloudWatch Logs fix (5→3 log types) | 2026-03-10 | R$ 720-1.080 | APLICADO — AGUARDANDO VALIDACAO |
| **TOTAL POS-CLOUDWATCH FIX (estimado)** | | **R$ 58.181-58.541/ano** | **93.8-94.4%** |

> **Nota FinOps Automation (R$ 12.800):** Savings real possivelmente MENOR que estimado.
> Weekend costs Mar 8-9 mostram $38-39/dia (esperado $15-18/dia com nodes no minimo).
> Root cause: cluster autoscaler re-escala nodes apos Lambda STOP por demanda de pods.
> Recomendacao: revisar eficacia real da automacao e ajustar savings estimado se necessario.

### 2.2 Reconciliacao com Documentos Anteriores

| Documento | Total | Diferenca |
|-----------|-------|-----------|
| finops-status-2026-03-06.md | R$ 56.546 | referencia |
| finops-status-2026-03-10.md (revisado) | R$ 57.461 | +R$ 915 vs 03-06 |
| finops-status-2026-03-11.md (este) | R$ 57.461 | sem mudanca vs 03-10 |
| CloudWatch fix (pendente validacao) | +R$ 720-1.080 | aplicado 2026-03-10, validacao em andamento |

---

## 3. Custos MTD Marco 2026 — Dados REAIS Cost Explorer

### 3.1 Custo Diario (2026-03-01 a 2026-03-10)

| Data | Dia | Custo | Observacao |
|------|-----|-------|------------|
| 2026-03-01 | Sabado | $87.55 | Inclui Tax mensal (~$52) |
| 2026-03-02 | Domingo | $39.99 | Weekend — cluster ativo |
| 2026-03-03 | Segunda | $37.28 | Dia util |
| 2026-03-04 | Terca | $40.10 | Dia util — GitLab work |
| 2026-03-05 | Quarta | $39.42 | Dia util |
| 2026-03-06 | Quinta | $40.17 | Dia util |
| 2026-03-07 | Sexta | $38.74 | Dia util |
| 2026-03-08 | Sabado | $38.43 | Weekend — custo NAO reduzido |
| 2026-03-09 | Domingo | $39.04 | Weekend — custo NAO reduzido |
| 2026-03-10 | Segunda | $26.01 | Parcial (dados incompletos) |
| **MTD TOTAL** | | **$426.72** | **10 dias** |

### 3.2 Comparativo vs Relatorio Anterior (mesmos dias)

| Periodo | Relatorio 03-10 | Relatorio 03-11 (real) | Delta |
|---------|-----------------|------------------------|-------|
| Mar 01 | $59.65 | $87.55 | +$27.90 (tax difference) |
| Mar 02 | $39.69 | $39.99 | +$0.30 |
| Mar 03 | $37.03 | $37.28 | +$0.25 |
| Mar 04 | $39.83 | $40.10 | +$0.27 |
| Mar 05 | $22.82 (parcial) | $39.42 (completo) | +$16.60 (dia completo) |
| Mar 06-10 | ~$150-190 (est.) | $182.39 (real) | Agora com dados reais |
| **MTD** | **~$350-400 (est.)** | **$426.72 (real)** | **+$27-77 acima da estimativa** |

### 3.3 Breakdown por Servico MTD (10 dias)

| Servico | Custo MTD | % Total | Projecao Mensal |
|---------|-----------|---------|-----------------|
| EC2 Compute | $206.89 | 48.5% | ~$641 |
| EC2 Other (EBS, IPs) | $52.02 | 12.2% | ~$161 |
| Tax | $51.84 | 12.1% | ~$52 (mensal fixo) |
| VPC (NAT Gateway) | $31.29 | 7.3% | ~$97 |
| EKS | $23.30 | 5.5% | ~$72 |
| CloudWatch | $21.36 | 5.0% | ~$66 |
| ELB | $20.98 | 4.9% | ~$65 |
| RDS | $9.36 | 2.2% | ~$29 |
| WAF | $3.14 | 0.7% | ~$10 |
| S3 | $2.99 | 0.7% | ~$9 |
| KMS | $2.14 | 0.5% | ~$7 |
| Secrets Manager | $1.13 | 0.3% | ~$4 |
| Cost Explorer | $0.27 | 0.1% | ~$1 |
| ECR | $0.02 | 0.0% | ~$0 |
| **TOTAL** | **$426.72** | **100%** | **~$1,217** |

### 3.4 Forecast Marco 2026

| Metrica | Valor | Calculo |
|---------|-------|---------|
| Daily rate (dias 2-10, excl tax day 1) | $37.57/dia | ($426.72 - $52 tax) / 9 dias = $374.72 / 9 |
| Dias restantes (11-31) | 21 dias | |
| Custo projetado restante | $788.97 | 21 × $37.57 |
| Tax (mensal) | ~$52 | Cobrado no dia 1 |
| **Forecast total Marco** | **~$1,217** | $426.72 + (21 × $37.57) |
| **Em reais** | **R$ 7.300** | @ R$ 6.00/USD |
| **vs Budget ($807)** | **+$410 (+51%)** | CRITICO |
| **vs Forecast anterior ($986)** | **+$231 (+23%)** | DEGRADACAO SIGNIFICATIVA |

---

## 4. Node Groups — Estado 2026-03-11

### 4.1 Capacidade Atual

| Node Group | Instance Type | Min | Desired | Max | Status |
|------------|--------------|-----|---------|-----|--------|
| system | t3.medium | 2 | 4 | 4 | AT MAX |
| workloads | t3.large | 2 | 6 | 6 | AT MAX |
| critical | t3.xlarge | 2 | 3 | 4 | NEAR MAX (75%) |
| **TOTAL** | | **6** | **13** | **14** | **93% da capacidade maxima** |

### 4.2 Comparativo vs Periodos Anteriores

| Periodo | Nodes | Pods | Custo EC2/dia |
|---------|-------|------|---------------|
| Jan 2026 (baseline) | ~8-10 | ~180 | ~$35-40 |
| Fev 2026 (otimizado) | 7-9 | ~209 | ~$25-30 |
| Mar 06 (relatorio anterior) | 9 | ~209 | ~$30-35 |
| **Mar 11 (atual)** | **13** | **234** | **~$37-40** |

### 4.3 Impacto Financeiro do Crescimento de Nodes

| Calculo | Valor |
|---------|-------|
| Nodes adicionais vs Mar 06 | +4 nodes |
| Custo adicional estimado | +$400/mes (~R$ 2.400) |
| Impacto anual | +R$ 28.800/ano se mantido |

### 4.4 FinOps Automation — Escala Diaria

| Momento | Nodes | Responsavel |
|---------|-------|-------------|
| Lambda START (08:00 BRT) | 7 (system=2, workloads=3, critical=2) | Lambda |
| Horario comercial (escala) | 13 (system=4, workloads=6, critical=3) | Cluster Autoscaler |
| Lambda STOP (18:00 BRT) | Min config (system=2, workloads=2, critical=2) = 6 | Lambda |
| Weekend (esperado) | 6 nodes | Lambda STOP |
| Weekend (REAL) | ~10-13 nodes | Autoscaler re-escala |

---

## 5. FinOps Automation — 1o. Mes VALIDADO

### 5.1 Status Operacional (2026-03-11)

| Componente | Status | Detalhe |
|-----------|--------|---------|
| Lambda START | OPERACIONAL | last_startup: 2026-03-11T10:30:10 |
| Lambda STOP | OPERACIONAL | last_shutdown: 2026-03-10T23:00:12 |
| Circuit breaker | CLOSED | startup_failures=0, shutdown_failures=0 |
| EventBridge | 3 rules ENABLED | startup Mon-Fri, shutdown Mon-Fri, weekend shutdown Sat |
| ADR-094 compliance | CONFIRMADO | system+critical EXCLUIDOS do shutdown (logs validados) |
| Teams notifications | ATIVO | Pos DT-005 |

### 5.2 ACHADO CRITICO — Weekend Costs

| Metrica | Esperado | Real | Gap |
|---------|----------|------|-----|
| Weekend cost/dia | $15-18 (6 nodes base) | $38-39 | **+$20-24/dia (+130%)** |
| Mar 08 (Sabado) | $15-18 | $38.43 | Lambda STOP executou mas custo nao caiu |
| Mar 09 (Domingo) | $15-18 | $39.04 | Idem |
| Weekend savings esperado | ~$40-48/weekend | ~$0-5/weekend | **SAVINGS COMPROMETIDO** |

**Root cause provavel:**
1. Lambda STOP reduz desired para minimo nos node groups workloads
2. Cluster autoscaler re-escala nodes por demanda de pods que permanecem schedulados
3. Pods com requests altos forcam autoscaler a manter nodes
4. RDS pode continuar ativo nos weekends (a confirmar)

**Acao recomendada:**
- Investigar quais pods estao schedulados nos weekends e se podem ser scaled down
- Considerar adicionar HPA com minReplicas=0 para workloads nao-criticos no weekend
- Verificar se RDS weekend shutdown esta efetivo
- Reavaliar savings real da automacao (R$ 12.800 pode ser R$ 6.000-8.000)

---

## 6. CloudWatch Fix — Aplicado e Monitorando

| Item | Antes | Depois | Status |
|------|-------|--------|--------|
| EKS log types | 5 (api, audit, authenticator, controllerManager, scheduler) | 3 (api, audit, authenticator) | APLICADO |
| CloudWatch MTD (10d) | — | $21.36 | Coletado |
| Projecao mensal | $34/mes (Fev) | ~$66/mes | SUBIU +94% |
| Saving esperado | R$ 720-1.080/ano | A VALIDAR | Pode ser anulado pelo aumento de nodes |

**ALERTA:** CloudWatch subiu de $34/mes (Fev) para projetado $66/mes (Mar) APESAR do fix de log types.
Causa: 13 nodes geram significativamente mais metricas e logs que 9 nodes.
O fix de log types economiza ~$10-15/mes, mas o crescimento de 9→13 nodes adicionou ~$30-40/mes em metricas.

---

## 7. DT-005 — Slack → Teams (COMPLETO — sem mudancas)

**Status:** CONCLUIDO em 2026-03-09 — sem alteracoes desde relatorio anterior.

---

## 8. VPA Rightsizing — Status PENDENTE

**Sem mudancas desde 2026-03-10.** VPA para producao permanece como proxima alavanca principal.

**URGENCIA AUMENTADA:** Com forecast de $1,217/mes (+51% budget), VPA rightsizing se torna CRITICO
para reduzir requests de pods e potencialmente permitir reducao de nodes de 13 para 9-10.

**Economia projetada (producao, pos-deploy):**
- R$ 25.000-35.000/ano (cluster 24/7)
- Reducao potencial de 13 para 9-10 nodes: -$90-120/mes

---

## 9. Pods Nao-Running (2026-03-11)

| Pod | Namespace | Status | Duracao | Impacto |
|-----|-----------|--------|---------|---------|
| linkerd-cni (2 pods) | linkerd-cni | Pending | 3h12m, 3h10m | Mesh injection degradado em 2 nodes |
| loki-canary (2 pods) | staging-observability-monitoring | Pending | 6h33m, 18h | Monitoramento Loki degradado |

**Total:** 4 pods Pending / 234 total = 1.7% nao-saudavel

---

## 10. Alertas e Riscos Financeiros

| Prio | Item | Impacto | Acao Recomendada |
|------|------|---------|-----------------|
| **P0** | **13 NODES ATIVOS — todos os groups at/near max** | +$400/mes vs 9 nodes (+R$ 28.800/ano) | Investigar quais workloads escalaram; VPA urgente |
| **P0** | **Forecast Mar $1,217 vs budget $807 (+51%)** | +$410/mes = +R$ 4.920/ano | ESCALAR para gestao — desvio significativo |
| **P0** | **Weekend costs $38-39/dia (deveria ser $15-18)** | Savings Automation parcialmente ineficaz | Investigar pods weekend; HPA com minReplicas=0 |
| **P1** | **CloudWatch $66/mes projetado (era $34/mes Fev)** | +$32/mes (+94%) apesar do fix de log types | Causado por 13 nodes — resolver nodes resolve CW |
| **P1** | **Node system ip-10-0-142-118 a 88% MEM** | Risco OOMKill em pods system | Monitorar; escalar system group se necessario |
| **P2** | **FinOps Automation savings superestimado** | R$ 12.800 pode ser R$ 6-8K real | Recalcular com dados weekend reais |

### Evolucao de Alertas vs Relatorio Anterior

| Alerta | Status 03-10 | Status 03-11 | Tendencia |
|--------|-------------|-------------|-----------|
| Forecast acima budget | +22% ($986) | +51% ($1,217) | PIORANDO |
| FinOps Automation | Nao validada | VALIDADA — mas eficacia reduzida | PARCIAL |
| CloudWatch | $34/mes | $66/mes projetado | PIORANDO |
| VPA Rightsizing | Pendente | Pendente — URGENCIA AUMENTADA | IGUAL |
| Node count | 9 nodes | 13 nodes | PIORANDO |
| Weekend costs | Nao monitorado | $38-39/dia (NOVO achado) | NOVO |

---

## 11. KPIs Mensais — Revisao 2026-03-11

| KPI | Meta | Fevereiro Real | Marco Forecast | Marco MTD Real | Status |
|-----|------|----------------|----------------|----------------|--------|
| Custo Mensal | <= $807 | $914 | **$1,217** | $426.72 (10d) | CRITICO |
| EKS Standard Support | $73/mes | $182 (transicao) | ~$72 | $23.30 (10d) | OK |
| EC2 Compute | ~$450/mes | ~$550 | **~$641** | $206.89 (10d) | CRITICO |
| EC2 Weekend Shutdown | <$18/dia | $12-25/dia | **$38-39/dia** | Confirmado | FALHA |
| FinOps Automation | 95% sucesso | 100% (manual) | Lambdas OK | 0 failures | OK (execucao) |
| FinOps Automation | Savings real | — | R$ 12.800 est. | Eficacia reduzida | REVISAR |
| VPA Rightsizing | 10 workloads | 0/10 | 0/10 | 0/10 | PENDENTE |
| Savings Realizados | R$ 62K/ano | R$ 57.461 | R$ 57.461 | R$ 57.461 | 92.7% |
| Node Count | 7-9 | 9 | — | **13** | ACIMA |
| Pod Count | ~200 | ~209 | — | **234** | ACIMA |
| DT-005 Teams | COMPLETO | COMPLETO | COMPLETO | COMPLETO | OK |

---

## 12. Comparativo vs Targets

| Cenario | Custo Mensal | Custo Anual | Status vs Budget |
|---------|--------------|-------------|-----------------|
| Baseline (Jan/26) | R$ 9.179 | R$ 110.147 | REFERENCIA |
| Budget Marco 3 Aprovado | R$ 4.841 | R$ 58.092 | META |
| Fevereiro 2026 REAL | R$ 5.487 | R$ 65.844 | ACIMA +13% |
| Marco 2026 Forecast (03-10) | R$ 5.916 | R$ 70.992 | ACIMA +22% |
| **Marco 2026 Forecast (03-11)** | **R$ 7.300** | **R$ 87.600** | **ACIMA +51%** |
| Apos VPA Rightsizing (Abr/26) | R$ 3.600-4.800 | R$ 43-58K | PROXIMO/DENTRO BUDGET |
| Apos Karpenter + Spot (2026 H2) | R$ 2.400-3.600 | R$ 29-43K | ABAIXO DO BUDGET |

---

## 13. Proximos Passos

### Imediato (esta semana)

| Acao | Impacto | Prioridade |
|------|---------|------------|
| Investigar quais workloads escalaram de 209→234 pods | Identificar causa do crescimento | P0 |
| Investigar weekend costs (quais pods mantem nodes ativos) | Viabilizar savings weekend | P0 |
| Escalar alerta de budget para gestao (+51% acima) | Visibilidade e decisao | P0 |
| Resolver 4 pods Pending (linkerd-cni, loki-canary) | Saude do cluster | P1 |

### Curto Prazo (Mar-Abr 2026)

| Acao | Impacto | Responsavel |
|------|---------|-------------|
| VPA Rightsizing — URGENTE | Reduzir nodes de 13→9-10 | SRE + FinOps |
| HPA com minReplicas=0 para workloads nao-criticos | Reduzir weekend costs para $15-18/dia | SRE |
| Reavaliar savings real FinOps Automation | Ajustar de R$ 12.800 para valor real | FinOps |
| Savings Plans 1yr No-Upfront (apos 30d prod) | R$ 11.363/ano | FinOps |

### Medio Prazo (2026 H2)

| Acao | Impacto | Decisao |
|------|---------|---------|
| Karpenter + Spot Instances | R$ 6.696/ano | Aguardar estabilizacao |
| Graviton ARM64 | R$ 6.984/ano | Sequencial apos VPA |
| Savings Plans producao (1yr) | R$ 11.363/ano | Apos 30d producao ativa |

---

**Preparado em:** 2026-03-11
**Revisao programada:** 2026-03-18 (acompanhamento semanal dado severidade do desvio)
**Documento anterior:** [docs/finops/finops-status-2026-03-10.md](finops-status-2026-03-10.md)
**Owner:** FinOps Team + Platform Team
