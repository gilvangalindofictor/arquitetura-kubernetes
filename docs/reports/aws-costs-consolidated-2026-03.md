# AWS Costs — Consolidated Report (Março 2026)

**Data de geração:** 2026-03-13 (atualizado com dados reais 01-12/03)
**Cluster:** k8s-platform-prod (EKS 1.34, us-east-1)
**Período:** 2026-03-01 → 2026-03-31
**Fonte dados reais:** AWS Cost Explorer API (dias 1-12) — coletado 2026-03-13 via CLI
**Budget aprovado:** $807/mês (R$ 4.841)
**AWS CE Forecast Março (2026-03-13):** $1.330,90/mês

---

## 1. Resumo Executivo

| Métrica | Valor | Status |
|---------|-------|--------|
| **MTD 12 dias REAL (01-12/03)** | **$539.50** | DADO REAL AWS CE |
| **Projeção mês completo (CE)** | **$1.330,90** | CRITICO (+65% budget) |
| **Projeção mês completo (ajustada)** | **~$1.145** | CRITICO (+42% budget) |
| **Budget aprovado** | $807/mês | META |
| **Tax março (pago dia 01)** | $66.29 | REVISADO (era $58.37) |
| **Daily rate weekday (excl anomalia, N=9)** | **$40.23/dia** | ACIMA |
| **Daily rate weekend (07-08/03)** | **$38.82/dia** | SEM REDUCAO (Lambda pré-fix) |
| **Daily rate dia 12 (pós-Lambda redeploy)** | **$39.00/dia** | REFERENCIA POS-FIX |
| **ELB dia 12 vs dia 11** | $1.44 vs $2.54 (-$1.10) | NLB ELIMINADO CONFIRMADO |
| **Savings realizados acumulados** | R$ 61.638/ano | 99.4% da meta |
| **EKS Standard Support** | $2.40/dia ($74.40/mês) | NORMAL |

**Interpretação executiva (2026-03-13):**
MTD real de $539.50 em 12 dias revela taxa diária significativamente acima do esperado. O AWS CE Forecast aponta $1.330,90/mês (+65% vs budget $807). Após ajuste para impacto Lambda weekends ($16.50/dia em vez de $38.82) e NLB eliminado (-$1.10/dia), nossa projeção interna é $1.145/mês (+42%). O dia 11 foi revisado pela AWS de $30.42 para $42.71 (billing consolidation). O dia 12 confirma redução na ELB (-$1.10) pela eliminação do NLB RabbitMQ. ATENÇÃO: Tax do mês foi $66.29 (vs $24.19 estimado anteriormente — revisão AWS billing).

---

## 2. MTD Março 2026 — Custos Reais (Dias 1–12) — ATUALIZADO 2026-03-13

> Dados reais coletados via AWS CE API em 2026-03-13. Todos os dias 01-12 consolidados.
> NOTA: Tax revisada pela AWS de $24.19 para $66.29 (billing consolidation). Dia 11 revisado de $30.42 para $42.71.

| Data | Dia | Tipo | Custo Total | EC2 Compute | EKS | VPC | ELB | Tax | Observacao |
|------|-----|------|-------------|-------------|-----|-----|-----|-----|------------|
| 2026-03-01 | Dom | WEEKEND | $99.79 | $20.22 | $2.40 | $3.24 | $2.16 | $66.29 | ANOMALIA — Tax total mes ($66.29) + billing carry-over |
| 2026-03-02 | Seg | WEEKDAY | $40.25 | $21.72 | $2.40 | $3.24 | $2.16 | — | Baseline weekday |
| 2026-03-03 | Ter | WEEKDAY | $37.53 | $19.06 | $2.40 | $3.24 | $2.16 | — | Dia util |
| 2026-03-04 | Qua | WEEKDAY | $40.38 | $22.22 | $2.40 | $3.24 | $2.16 | — | Dia util |
| 2026-03-05 | Qui | WEEKDAY | $39.67 | $21.88 | $2.40 | $3.24 | $2.16 | — | Dia util |
| 2026-03-06 | Sex | WEEKDAY | $40.43 | $21.63 | $2.40 | $3.24 | $2.16 | — | Dia util |
| 2026-03-07 | Sab | WEEKEND | $38.98 | $22.38 | $2.40 | $3.24 | $2.16 | — | Weekend — Lambda STOP sem reducao (pre-fix) |
| 2026-03-08 | Dom | WEEKEND | $38.66 | $22.21 | $2.40 | $3.24 | $2.16 | — | Weekend — Lambda STOP sem reducao (pre-fix) |
| 2026-03-09 | Seg | WEEKDAY | $39.28 | $21.49 | $2.40 | $3.24 | $2.16 | — | Dia util |
| 2026-03-10 | Ter | WEEKDAY | $42.81 | $23.85 | $2.40 | $3.26 | $2.21 | — | Spike (+$3 vs baseline) |
| 2026-03-11 | Qua | WEEKDAY | $42.71 | $23.91 | $2.40 | $3.39 | $2.54 | — | REVISADO (era $30.42) — billing consolidation. ELB +$0.38 vs baseline (NAT transicao) |
| 2026-03-12 | Qui | WEEKDAY | $39.00 | $23.03 | $2.40 | $2.79 | $1.44 | — | Pos-Lambda redeploy. ELB $1.44 (NLB eliminado, -$1.10 vs dia 11) |
| **MTD TOTAL (01-12)** | | | **$539.50** | **$263.60** | **$28.80** | **$38.62** | **$25.64** | **$66.29** | **12 dias consolidados** |

**Medias (dados reais coletados 2026-03-13):**

| Categoria | Media | N | Observacao |
| --- | --- | --- | --- |
| Weekday (02-06, 09-12, excl anomalia 01) | $40.23/dia | 9 | Todos dias uteis do periodo |
| Weekend (07-08 — exc. anomalia 01) | $38.82/dia | 2 | Lambda STOP nao reduziu (pre-fix) |
| Weekend com anomalia (01, 07, 08) | $59.14/dia | 3 | Distorcido pela Tax $66.29 em 01/03 |
| Baseline pos-Lambda redeploy (apenas dia 12) | $39.00/dia | 1 | Referencia pos-redeploy 2026-03-12T14:39 |

---

## 3. MTD Março 2026 — Dados Historicos (Dias 1–5 e 6–10) — SUBSTITUIDO POR DADOS REAIS

> Esta secao foi substituida por dados reais na Secao 2 acima. Os dados originais estimados (gerados 2026-03-10)
> estavam proximos dos reais para dias 2-6, mas a Tax foi significativamente subestimada ($24.19 vs real $66.29).
> Dias 7-8 (weekends) foram estimados em $13/dia — real foi $38.98/$38.66 (Lambda STOP ineficaz, pre-fix).

| Periodo | Estimativa Original (2026-03-10) | Real (2026-03-13) | Desvio |
|---------|----------------------------------|-------------------|--------|
| Dias 1-5 | $199.62 (parcial) | $257.63 | +$58.01 (Tax revision $42.10 + dia 01 billing) |
| Dias 6-10 | ~$136 (estimado) | $200.17 | +$64.17 (weekends $38-39 vs $13 esperado) |
| **MTD 10 dias** | **~$335-355** | **$457.71** | **+$102-122 (desvio significativo)** |
| Dia 11 | ~$30 (estimado pós-apply) | $42.71 | +$12.71 (billing revision) |
| Dia 12 | $0 (dados parciais) | $39.00 | Primeiro dado real |
| **MTD 12 dias** | — | **$539.50** | **DADO OFICIAL** |

---

## 4. Projeção Mês Completo — Março 2026

### Calendário de Março

| Semana | Dias Úteis | Fins de Semana | Observações |
|--------|-----------|----------------|-------------|
| S1 (03-03 a 03-07) | 5 dias | 2 dias | Dados reais + estimativas |
| S2 (03-08 a 03-14) | 5 dias | 2 dias | Plataforma normal |
| S3 (03-15 a 03-21) | 5 dias | 2 dias | VPA rollout esperado |
| S4 (03-22 a 03-28) | 5 dias | 2 dias | Operação pós-VPA |
| S5 (03-29 a 03-31) | 3 dias | — | Final do mês |
| **TOTAL** | **23 dias úteis** | **8 fins de semana** | **31 dias** |

### Cálculo de Projeção — ATUALIZADO 2026-03-13 (dados reais 12 dias)

| Cenario | Calculo | Total Mensal |
|---------|---------|-------------|
| **AWS CE Forecast (2026-03-13)** | — | **$1.330,90** |
| **Nossa Projecao Ajustada** | MTD $539.50 + (13d WD x $39.00) + (6d WKD x $16.50) | **$539.50 + $507.00 + $99.00 = $1.145,50** |
| **Cenario Otimista (Lambda eficaz weekends)** | MTD $539.50 + (13d WD x $38.00) + (6d WKD x $16.50) | **$539.50 + $494.00 + $99.00 = $1.132,50** |
| **Cenario Pessimista (Lambda ineficaz)** | MTD $539.50 + (19d x $40.00) | **$539.50 + $760.00 = $1.299,50** |

> **Projecao adotada (ajustada):** ~$1.145/mes

> **NOTA CRITICA:** Projecao anterior de 2026-03-10 era $830-860/mes. A realidade de 12 dias revela que a taxa de custo
> é ~$40/dia (vs $35 estimado) E que weekends estao em $38-39/dia (vs $13 esperado). O desvio total acumulado nos
> primeiros 12 dias vs estimativa original foi de +$102-122. A Tax real ($66.29) superou a estimativa ($24.19) em $42.10.

### Impacto da Tax na Projecao

A tax de $66.29 alocada no dia 01/03 representa **~12.3% do MTD de 12 dias**. A taxa diária "limpa" (sem tax) e sem anomalia 01-03:

- ($539.50 - $99.79) / 11 = **$39.97/dia** — real weekday rate
- Tax anual projetada: ~$66.29/mes x 12 = **~$795/ano** (significativo)

---

## 5. Breakdown por Servico — MTD REAL 12 Dias (01-12/03) — ATUALIZADO 2026-03-13

Dados reais AWS CE coletados em 2026-03-13:

| Servico | MTD 12d Real | % | $/dia | Observacao |
|---------|-------------|---|-------|------------|
| Amazon EC2 - Compute | $263.60 | 48.9% | $21.97 | 13 nodes (t3.medium/large/xlarge) |
| Tax | $66.29 | 12.3% | $5.52 | Cobrado dia 1 do mes (REVISADO de $24.19) |
| EC2 - Other | $64.40 | 11.9% | $5.37 | EBS, NAT Data, IPs elasticos |
| Amazon VPC | $38.62 | 7.2% | $3.22 | NAT Gateway (2x1 desde 03-11) |
| Amazon EKS | $28.80 | 5.3% | $2.40 | Control plane ($0.10/h) |
| AmazonCloudWatch | $27.18 | 5.0% | $2.27 | Metricas + logs |
| Amazon ELB | $25.64 | 4.8% | $2.14 | 2 ALBs + NLB (NLB eliminado dia 12: $1.44 total) |
| Amazon RDS | $12.50 | 2.3% | $1.04 | PostgreSQL db.t3.medium |
| AWS WAF | $3.88 | 0.7% | $0.32 | Web ACL |
| Amazon S3 | $3.72 | 0.7% | $0.31 | Storage + requests |
| AWS KMS | $2.67 | 0.5% | $0.22 | CMKs + requests |
| AWS Secrets Manager | $1.40 | 0.3% | $0.12 | Secrets rotation |
| AWS Cost Explorer | $0.77 | 0.1% | $0.06 | API queries |
| Amazon ECR | $0.02 | 0.0% | $0.00 | — |
| **TOTAL** | **$539.50** | **100%** | **$44.96** | **12 dias** |

> **Top 3 desvios vs estimativa original:**
>
> 1. Tax: $66.29 real vs $24.19 estimado (+$42.10, +174%) — billing revision AWS
> 2. Weekend EC2: $38-39/dia real vs $13 estimado (+$26/dia x 2 dias = +$52) — Lambda STOP ineficaz (pre-fix)
> 3. EC2 Compute: $21.97/dia real vs ~$11/dia estimado para weekends (+$22/dia x 2 = +$44) — cluster nao foi desligado

---

## 6. Comparativo vs Budget — ATUALIZADO 2026-03-13

| Metrica | Fevereiro Real | Marco Projecao (CE) | Marco Proj. Ajustada | Budget | Status |
|---------|---------------|---------------------|---------------------|--------|--------|
| Custo Mensal USD | $914.41 | $1.330,90 | ~$1.145 | $807 | CRITICO |
| Custo Mensal BRL | R$ 5.487 | R$ 7.653 | R$ 6.584 | R$ 4.841 | CRITICO |
| vs Budget | +$107 (+13%) | +$523 (+65%) | +$338 (+42%) | — | DESVIO GRAVE |
| Daily Rate Util | $38.60/dia | — | $40.23/dia | ~$29/dia | ACIMA |
| Daily Rate Weekend | $12.35/dia | — | $38.82/dia | ~$10/dia | FALHA |

### Analise do Desvio

O desvio de $338-524/mes e explicado por fatores estruturais:

1. **13 nodes ativos (vs 7-8 no budget):** +$8-12/dia. Resolve-se com VPA rightsizing (Abr/26).
2. **Lambda STOP ineficaz nos weekends (pre-fix):** +$22-25/dia x 8 dias/mes = +$176-200/mes. Fix deployado 2026-03-12T14:39 — proxima validacao: weekend 14-15/03.
3. **Tax $66.29 (vs $24-25 esperado):** Revisao AWS billing. Tax real anualizada = ~$795/ano nao esperado.
4. **CloudWatch $27.18 (12d) = $68/mes projetado:** +$34/mes vs baseline $34/mes Fev — causado por 13 nodes.

**Sem esses 3 fatores:** projeção seria ~$757-780 — **abaixo do budget**.

---

## 7. Top Anomalias Identificadas

### 7.1 Tax Alocada no Dia 01 — $24.19

**Observação:** PIS/COFINS brasileiro sempre alocado no primeiro dia do mês. Distorce métricas diárias de 01/Mar ($59.65 = custo mais alto do mês). Sem tax, o dia 01 seria $35.46 — dentro do padrão.

**Ação:** Nenhuma — comportamento esperado. Filtrar tax ao calcular daily rate operacional.

### 7.2 Cluster 9 Nós (vs 7-8 no Budget)

**Causa:** Trabalho intenso de plataforma em Fev-Mar/26 (Linkerd Phase 2, GitLab rev 12-14, Keycloak import, Harbor OOM fixes, ArgoCD upgrade, TF drift fixes) forçou autoscaler ao máximo.

**Impacto:** +$16-32/dia vs baseline de 7 nós. ~+$320-480 no mês inteiro.

**Ação:** Após estabilização e VPA rightsizing (workloads bem dimensionados), autoscaler deve voltar a 7-8 nós. Redução esperada: -R$ 640-960/mês.

### 7.3 Fim de Semana Dia 01-02 com Cluster Ativo — $99.34 (2 dias)

**Causa:** Cluster não estava em modo weekend nos primeiros dias de março — trabalho de plataforma em andamento. Custo total sáb+dom foi $99.34 vs padrão normal $26 ($13/dia).

**Delta:** +$73.34 em 2 dias.

**Ação:** FinOps Automation EventBridge deve normalizar fins de semana seguintes. Monitorar semanas 2-4.

### 7.4 CloudWatch +64% vs Documentado

**Custo estimado:** ~$34-40/mês em março (vs $21 documentado no baseline).

**Causa confirmada (da sessão 2026-03-06):** Observability stack GitLab verbose + Linkerd metrics em expansão.

**Ação:** Revisar log retention policies + custom metrics exporters.

### 7.5 ELB em Queda — Tendência Positiva

**Fevereiro:** $71.09 | **Março estimado:** ~$60-65 | **Tendência:** -9-15%

**Causa:** ALBs nginx-test e echo-server deletados (2026-02-11) + otimização de ingress. Economia consolidada.

---

## 8. Status das Otimizações — Março 2026

### 8.1 Ativas e Funcionando

| Otimização | Savings/ano | Ativação | Status Março |
|-----------|-------------|----------|-------------|
| EKS 1.34 Standard Support | R$ 25.920 | 2026-02-10 | ATIVO — $2.40/dia ✅ |
| FinOps Automation EventBridge | R$ 13.597 | 2026-02-23 | **1º MÊS COMPLETO — validar execuções** |
| PDB Optimization | R$ 4.405 | 2026-02-24 | ATIVO ✅ |
| Snapshot DLM (3 políticas) | R$ 5.052 | 2026-02-27 | ATIVO ✅ |
| EBS gp3 (nós + PVCs) | R$ 859 | 2026-02-13 | ATIVO ✅ |
| ALBs deletados (nginx-test + echo) | R$ 1.920 | 2026-02-11 | ATIVO ✅ |
| RDS Weekend Shutdown | R$ 1.200 | 2026-02-18 | ATIVO ✅ |
| S3 Gateway Endpoint | R$ 900 | 2026-02-12 | ATIVO ✅ |
| Orphan cleanup + detector Lambda | R$ 3.221 | 2026-02-12 | ATIVO ✅ |
| CloudWatch Log Retention | R$ 54 | 2026-02-12 | ATIVO ✅ |
| **TOTAL ATIVO** | **R$ 57.128/ano** | | |

### 8.2 Pendentes / Em Andamento

| Otimização | Savings Potencial | Prioridade | Status |
|-----------|-------------------|------------|--------|
| **VPA Rightsizing** (10+ workloads) | R$ 15.000-17.000/ano | **URGENTE** | PENDENTE — dados disponíveis |
| FinOps Automation — Validação 1º mês | R$ 13.597 em risco | **ALTA** | Monitorar execuções automáticas |
| Redução nós workloads (4→2 pós-VPA) | R$ 7.680-12.000/ano | MÉDIA | Aguarda VPA |
| CloudWatch audit | ~R$ 936/ano | MÉDIA | Pendente investigação |
| Karpenter + Spot (staging) | R$ 6.696/ano | BAIXA | Aguardar estabilização |

### 8.3 Alertas DT-005 Teams — RESOLVIDO (2026-03-09)

- **Status anterior (2026-03-06):** webhook Teams com valor `REPLACE` — alertas financeiros não chegando
- **Status atual (2026-03-10):** webhook Teams real populado no Vault (`secret/alertmanager/teams-webhook`)
- **Slack→Teams:** 100% migrado (308+ refs) — alertas financeiros devem chegar ao canal Teams agora
- **Ação:** Validar receipt de alertas PrometheusRule em canal Teams

---

## 9. KPIs do Mês — Revisão 2026-03-10

| KPI | Meta Mensal | Fevereiro Real | Março MTD (10d) | Março Projeção | Status |
|-----|-------------|----------------|-----------------|----------------|--------|
| Custo Mensal | <= $807 | $914 | ~$335-355 | ~$830-860 | ATENÇÃO |
| Daily Rate Útil | ~$29/dia | $38.60/dia | $39.92/dia | $35-40/dia | ACIMA |
| Daily Rate Weekend | ~$10/dia | $12.35/dia | ~$13/dia | ~$13/dia | DENTRO |
| EKS Standard Support | $74/mês | $182 (transição) | $24 (10d) | $74.40 | ON TRACK ✅ |
| FinOps Automation | 95% success | N/A (1º exec) | **Validar** | — | MONITORAR |
| VPA Rightsizing | 10 workloads | 0/10 | 0/10 | Iniciar urgente | URGENTE ⚠️ |
| Savings Realizados | R$ 62K/ano | R$ 56.546 (90%) | R$ 57.128 (91%) | R$ 57-72K/ano | ON TRACK ✅ |
| Savings Potenciais (pós-VPA) | R$ 72-74K/ano | — | — | Aguarda execução | PENDENTE |
| Desvio vs Budget | 0% | +13% | — | +3-7% | MELHORA ✅ |
| Redução vs Baseline | -47% | -40% | -38% (MTD) | -42% | PROGRESSO ✅ |

---

## 10. Projeção Pós-VPA — Impacto em Abril/2026

Se VPA rightsizing for executado na semana de 2026-03-10/14:

| Métrica | Março Atual | Abril Estimado | Savings Delta |
|---------|-------------|----------------|---------------|
| Nós ativos (semana) | 9 | 7-8 | -1-2 nós |
| Daily rate útil | $35-40 | $28-33 | -$7-12/dia |
| Custo mensal | $830-860 | $750-790 | -$60-110/mês |
| vs Budget ($807) | ACIMA +3-7% | ABAIXO ou ON TRACK | DENTRO |
| vs Meta anual | R$ 57K/ano | R$ 72-74K/ano | +R$ 15-17K/ano |

**Conclusão:** VPA rightsizing é a única alavanca necessária para retornar ao budget. Não há necessidade de outras intervenções estruturais em março.

---

## 11. Linha do Tempo Financeira (Dados Reais + Projeções)

```
BASELINE (sem ações, Jan/26):       $1.530/mês = R$ 9.179
  ↓ -40% (otimizações Q1/26)
FEVEREIRO 2026 REAL:                $914.41 = R$ 5.487
  - Tax alocada dia 01: $111.10
  - EKS Extended (01-09 Feb): $14.40/dia
  - EKS Standard (10-28 Feb): $2.40/dia
  - Weekend shutdown efetivo: $12-25/dia
  - Pico: $147.43 (01/Feb) | Mínimo: $12.07 (14-15/Feb)

MARÇO 2026 MTD (10 dias):           ~$335-355
  - Tax alocada dia 01: $24.19
  - Daily rate real (d1-5): $39.92/dia
  - Cluster no autoscaler máximo: 9 nós
  - Fins de semana 06-09 Mar: shutdown ativo

MARÇO 2026 PROJEÇÃO (mês completo): ~$830-860
  - AWS ML Forecast: $986 (conservador)
  - Projeção interna: $830-860 (-15% vs ML)
  - Desvio vs budget: +3-7% (marginal)

ABRIL 2026 ESTIMADO (pós-VPA):      ~$750-790
  - VPA rightsizing: -$60-110/mês
  - Autoscaler normaliza para 7-8 nós
  - Status: DENTRO DO BUDGET ($807)

META MÉDIO PRAZO (Karpenter + Spot, H2/26): ~$600-700/mês
```

---

## 12. Alertas e Riscos — Restante de Março 2026

### CRÍTICO

| # | Alerta | Impacto | Prazo | Ação Recomendada |
|---|--------|---------|-------|------------------|
| A1 | **VPA Rightsizing NÃO EXECUTADO** | R$ 15-17K/ano perdidos + budget acima | **ESTA SEMANA** | Executar rightsizing nos 10 workloads identificados (dados VPA day-7 disponíveis desde 03-04) |

### ALTO

| # | Alerta | Impacto | Prazo | Ação Recomendada |
|---|--------|---------|-------|------------------|
| A2 | **FinOps Automation — 1º mês completo** | R$ 13.597/ano em risco se falhar | 2026-03-15 | Verificar logs EventBridge + Lambda executions. Confirmar shutdowns automáticos Sáb-Dom 07-08/Mar |
| A3 | **Projeção $830-860 vs budget $807** | +$23-53/mês acima do budget | Mês corrente | Aceitar temporariamente + executar VPA. Sem VPA → desvio persiste em Abr/Mai |

### MÉDIO

| # | Alerta | Impacto | Prazo | Ação Recomendada |
|---|--------|---------|-------|------------------|
| A4 | **CloudWatch +64% vs documentado** | +$13/mês desnecessário | Março | Auditar log groups: gitlab, linkerd, loki. Rever retention policies e custom metrics |
| A5 | **Fins de semana 01-02/Mar com cluster ativo** | +$73.34 de custo anômalo | Evento passado | Verificar se EventBridge executou normalmente nos fins de semana subsequentes (07-08, 14-15, 21-22, 28-29 Mar) |
| A6 | **Nós workloads em 4 (vs 2 baseline)** | +$10-16/dia extras | Março | Após VPA, reduzir desired de 4 para 2. Autoscaler sobe conforme necessidade |

### BAIXO / MONITORAMENTO

| # | Alerta | Impacto | Observação |
|---|--------|---------|------------|
| A7 | Teams Webhook ativo desde 03-09 | Alertas financeiros chegando ao canal | Validar receipt de PrometheusRule FinOps no Teams |
| A8 | Tax mês de Abril (previsão ~$25) | Pico no dia 01/Abr | Esperado — filtrar ao calcular daily rate |
| A9 | RDS snapshot retention (DLM ativo) | R$ 5.052/ano | Confirmar políticas DLM ativas no console |

---

## 13. Decisões e Recomendações

### Decisão 1: Aceitar Desvio de Março (RECOMENDADO)

O desvio projetado de $23-53/mês (+3-7%) sobre o budget é **resultado direto de trabalho de plataforma não-recorrente** (Linkerd Phase 2, GitLab upgrade, Keycloak import, TF drift correction, security compliance). Este trabalho gerou valor de R$ 57.128/ano em savings e compliance total. O ROI é positivo.

**Ação:** Registrar desvio como exceção planejada. Não iniciar otimizações emergenciais que possam desestabilizar o cluster.

### Decisão 2: VPA Rightsizing — Executar AGORA (URGENTE)

Dados VPA disponíveis desde 2026-03-04 (day-7 report). Cada semana sem execução = ~R$ 288-326 em savings perdidos.

**Workloads priorizados:**
1. redis — cpu: 25m, memory: 65Mi (VPA uncappedTarget)
2. harbor-core — cpu: 15m, memory: 65Mi
3. 8+ workloads adicionais com dados disponíveis

### Decisão 3: Savings Plans / Reserved Instances — Aguardar Produção

SP e RI são inviáveis em staging (weekend shutdown elimina utilização base). Ao subir produção 24/7:
- Compute Savings Plans 1yr No-Upfront: R$ 11.363/ano
- RDS Reserved Instance 1yr No-Upfront: R$ 3.024/ano
- **Total: R$ 14.387/ano** | Payback < 1 mês

---

## 14. Arquivos de Referência

| Arquivo | Conteúdo |
|---------|----------|
| `docs/finops/finops-status-2026-03-13.md` | Status FinOps 2026-03-13 — MTD atualizado, forecast recalculado |
| `docs/finops/finops-status-2026-03-12.md` | Status FinOps 2026-03-12 — apply Lambda+RabbitMQ confirmado |
| `docs/finops/finops-status-2026-03-06.md` | Status completo FinOps + dados reais CE |
| `docs/reports/aws-costs-raw-2026-03-13.json` | Raw JSON diário por serviço 01-12/03/2026 (coletado 2026-03-13) |
| `docs/reports/aws-costs-consolidated-2026-02.md` | Relatório consolidado fevereiro (real) |
| `docs/reports/vpa-day7-report-2026-03-04.md` | Dados VPA para rightsizing |
| `docs/reports/aws-costs-raw-consolidated-2026-02.json` | Dados brutos CE fevereiro |
| `docs/finops/executive-summary-finops.md` | Executive summary histórico |

---

**Gerado em:** 2026-03-10
**Atualizado em:** 2026-03-13 (dados reais 01-12/03 coletados via AWS CE CLI)
**Próximo review:** 2026-03-18 (validação weekend Lambda 14-15/03 + status nodes)
**Owner:** FinOps Team + Platform Team
**Referência logbook:** `docs/finops/finops-status-2026-03-13.md` (status atual)
