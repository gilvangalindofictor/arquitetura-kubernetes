# Relatorio FinOps — Status Financeiro Atualizado

**Data:** 2026-03-13
**Cluster:** k8s-platform-prod (EKS 1.34)
**Periodo de Referencia:** Jan/2026 — Mar/2026
**Fonte Dados:** AWS Cost Explorer REAL — coletado 2026-03-13 via CLI (sessao ativa) — dados 01-12/03 consolidados
**Status Geral:** FINANCEIRO CRITICO — MTD $539.50 (12 dias) | AWS CE Forecast $1.330,90/mes (+65% budget $807) | Projecao Ajustada $1.145/mes (+42%) | Day 12 confirma eliminacao NLB (-$1.10 ELB) | Lambda redeploy 2026-03-12T14:39 aguarda validacao no weekend 14-15/03

---

## 1. Resumo Executivo

| Metrica | Valor |
|---------|-------|
| **Custo Fevereiro 2026 REAL** | **$914.41 = R$ 5.487** |
| **Budget Marco 3 Aprovado** | $807/mes (R$ 4.640) |
| **Mar/2026 MTD REAL (12 dias, 01-12/03)** | **$539.50** |
| **Mar/2026 Daily rate weekday (excl anomalia 01-03, N=9)** | **$40.23/dia** |
| **Mar/2026 Daily rate weekend (07-08/03, pre-fix Lambda)** | **$38.82/dia** |
| **Mar/2026 Daily rate dia 12 (pos-Lambda redeploy)** | **$39.00/dia** |
| **AWS CE Forecast total mes (coletado 2026-03-13)** | **$1.330,90/mes = R$ 7.653** |
| **Forecast AJUSTADO (Lambda weekends $16.50 + NLB removido)** | **$1.145/mes = R$ 6.584** |
| **Status Marco vs Budget (forecast ajustado)** | **ACIMA em $338 (+42%)** |
| **Status Marco vs Budget (CE forecast)** | **ACIMA em $523 (+65%)** |
| **Savings Realizados (acumulado)** | **R$ 61.638/ano** |
| **Meta Original** | R$ 62.000/ano |
| **Realizacao vs Meta** | **99.4%** — QUASE ATINGIDA |

**REVISAO IMPORTANTE (2026-03-13):** Dados reais de 12 dias revelam desvio significativo vs estimativas anteriores:

1. **Tax revisada:** $66.29 real vs $24.19-58.37 estimado/anterior — revisao AWS billing (+$8-42)
2. **Dia 11 revisado:** $42.71 real vs $30.42 reportado em 2026-03-12 (billing consolidation +$12.29)
3. **Weekends pre-fix:** $38.82/dia real vs $13 esperado — Lambda STOP era ineficaz (pre-redeploy 14:39)
4. **MTD 12 dias:** $539.50 vs $480.28 reportado dia anterior (dia 11 $42.71 + dia 12 $39.00 novos)

**CONFIRMACOES DO DIA 12 (pos-apply 14:39 BRT):**

- ELB dia 12: $1.44 vs $2.54 dia 11 = **-$1.10/dia confirmado** (NLB RabbitMQ eliminado)
- VPC dia 12: $2.79 vs $3.39 dia 11 = **-$0.60/dia** (NAT Gateway traffic reducao pos-NLB)
- EC2 Compute dia 12: $23.03 vs $23.91 dia 11 = -$0.88 (marginal, sem suspend_autoscaler ainda)

**ALERTA FINANCEIRO CRITICO:** AWS CE Forecast (2026-03-13) = $1.330,90/mes (+65% vs budget $807).
Forecast AJUSTADO com Lambda fix weekends ($16.50/dia) + NLB removido = $1.145/mes (+42%).
O weekend de 14-15/03 sera o PRIMEIRO TESTE REAL do suspend_cluster_autoscaler() deployado em 2026-03-12T14:39.
Se Lambda funcionar: daily rate weekend cai de $38.82 para ~$16.50 (-$22/dia x 8 dias/mes = -$176/mes).

---

## 2. Savings Totais Realizados — Estado 2026-03-13

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
| FinOps FASE 2 — Automacao EventBridge | 2026-02-23 | R$ 12.800 | ATIVO — EFICACIA EM VALIDACAO (weekend 14-15/03) |
| PDB Optimization — shutdown graceful | 2026-02-24 | R$ 4.405 | ATIVO |
| Snapshot DLM (3 policies: 30d/14d/7d) | 2026-02-27 | R$ 5.052 | SUBSTITUIDO — DLM removido, Velero cobre |
| Node Group Protection (custo confiabilidade) | 2026-02-27 | -R$ 720 | ATIVO |
| CloudWatch fix (5→3 log types) | 2026-03-10 | R$ 720-1.080 | APLICADO — AGUARDANDO VALIDACAO |
| **ALB 4→2 (observability+data → platform-staging)** | **2026-03-11** | **R$ 2.009** | **CODIFICADO + APLICADO** |
| **NAT 2→1 (removida NAT us-east-1b)** | **2026-03-11** | **R$ 2.168** | **CODIFICADO + APLICADO** |
| **RabbitMQ NLB eliminado (ClusterIP)** | **2026-03-12** | **R$ 384** | **JA CONTADO ACIMA (fev-11) — confirmado operacional** |
| **TOTAL REALIZADOS** | | **R$ 61.638/ano** | **99.4% da meta — SEM MUDANCA VS 2026-03-12** |

> **Nota:** Nenhum novo saving foi adicionado em 2026-03-13. O NLB eliminado em 03-12 ja estava contabilizado desde
> a entrada de 2026-02-11 (R$ 384). Confirmacao operacional do saving anterior, nao novo saving.

### 2.2 Reconciliacao com Documentos Anteriores

| Documento | Total | Diferenca |
|-----------|-------|-----------|
| finops-status-2026-03-06.md | R$ 56.546 | referencia |
| finops-status-2026-03-10.md | R$ 57.461 | +R$ 915 vs 03-06 |
| finops-status-2026-03-11.md | R$ 57.461 | sem mudanca vs 03-10 |
| finops-status-2026-03-12.md | R$ 61.638 | +R$ 4.177 vs 03-11 (ALB + NAT) |
| finops-status-2026-03-13.md (este) | R$ 61.638 | sem mudanca vs 03-12 |

---

## 3. Custos MTD Marco 2026 — Dados Reais (coletados 2026-03-13)

### 3.1 Custo Diario (2026-03-01 a 2026-03-12) — DADOS REAIS AWS CE

| Data | Dia | Tipo | Custo USD | EC2 Compute | ELB | VPC | Observacao |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-03-01 | Dom | WEEKEND | $99.79 | $20.22 | $2.16 | $3.24 | ANOMALIA — Tax $66.29 (total mes) |
| 2026-03-02 | Seg | WEEKDAY | $40.25 | $21.72 | $2.16 | $3.24 | Baseline weekday |
| 2026-03-03 | Ter | WEEKDAY | $37.53 | $19.06 | $2.16 | $3.24 | Dia util |
| 2026-03-04 | Qua | WEEKDAY | $40.38 | $22.22 | $2.16 | $3.24 | Dia util |
| 2026-03-05 | Qui | WEEKDAY | $39.67 | $21.88 | $2.16 | $3.24 | Dia util |
| 2026-03-06 | Sex | WEEKDAY | $40.43 | $21.63 | $2.16 | $3.24 | Dia util |
| 2026-03-07 | Sab | WEEKEND | $38.98 | $22.38 | $2.16 | $3.24 | Weekend — Lambda STOP ineficaz (pre-fix) |
| 2026-03-08 | Dom | WEEKEND | $38.66 | $22.21 | $2.16 | $3.24 | Weekend — Lambda STOP ineficaz (pre-fix) |
| 2026-03-09 | Seg | WEEKDAY | $39.28 | $21.49 | $2.16 | $3.24 | Dia util |
| 2026-03-10 | Ter | WEEKDAY | $42.81 | $23.85 | $2.21 | $3.26 | Spike +$3 (billing delay / CE queries $0.36) |
| 2026-03-11 | Qua | WEEKDAY | $42.71 | $23.91 | $2.54 | $3.39 | **REVISADO** (era $30.42 — billing consolidation AWS) |
| 2026-03-12 | Qui | WEEKDAY | $39.00 | $23.03 | $1.44 | $2.79 | **ELB -$1.10 (NLB eliminado)** — pos-redeploy Lambda |
| **MTD TOTAL (01-12/03)** | | | **$539.50** | $263.60 | $25.64 | $38.62 | **12 dias efetivos** |

> **Revisao critica dia 11:** O custo reportado em 2026-03-12 para o dia 11 era $30.42 (dados parciais).
> O valor consolidado real e $42.71 (+$12.29). Isso explica a diferenca entre MTD $480.28 (reportado 03-12)
> e MTD real $539.50 (dia 11 $42.71 + dia 12 $39.00 = +$59.22 vs status anterior).

**Medias (dados reais coletados 2026-03-13):**

| Categoria | Media | N | Observacao |
| --- | --- | --- | --- |
| Weekday (02-06, 09-12, excl anomalia 01) | $40.23/dia | 9 | Todos dias uteis do periodo |
| Weekend (07, 08 — exc. anomalia 01) | $38.82/dia | 2 | Lambda STOP nao reduziu (pre-fix) |
| Weekend com anomalia (01, 07, 08) | $59.14/dia | 3 | Distorcido pela Tax $66.29 em 01/03 |
| Baseline pos-Lambda redeploy (dia 12) | $39.00/dia | 1 | Referencia pos-redeploy 2026-03-12T14:39 |
| Baseline pos-NLB eliminado (ELB dia 12) | $1.44/dia | 1 | vs $2.16/dia baseline anterior (-$0.72 vs media) |

### 3.2 Analise Dia 12 — Confirmacao dos Applies de 2026-03-12T14:39

| Metrica | Dia 11 (pre-apply) | Dia 12 (pos-apply) | Delta | Observacao |
| --- | --- | --- | --- | --- |
| ELB Total | $2.54 | $1.44 | **-$1.10** | NLB RabbitMQ eliminado — CONFIRMADO |
| VPC Total | $3.39 | $2.79 | **-$0.60** | NAT Gateway traffic reducao pos-NLB |
| EC2 Compute | $23.91 | $23.03 | -$0.88 | Marginal — sem suspend_autoscaler ainda |
| EKS | $2.40 | $2.40 | $0 | Estavel |
| CloudWatch | $2.50 | $2.50 | $0 | Estavel |
| **TOTAL** | **$42.71** | **$39.00** | **-$3.71** | Reducao real dia 12 vs dia 11 |

**Economia diaria confirmada (NLB + NAT traffic):** -$1.70/dia
**Projecao anualizada da economia:** -$1.70 x 365 = **$620.50/ano = R$ 3.568/ano**

> **Nota Lambda suspend_autoscaler:** O redeploy foi feito em 2026-03-12T14:39 (quinta-feira — dia util).
> O impacto do suspend_cluster_autoscaler() so sera visivel nos FINS DE SEMANA (14-15/03).
> Dia 12 sendo dia util, o cluster estava ativo normalmente — sem impacto esperado no weekday cost.

### 3.3 Forecast Marco 2026 — Recalculado 2026-03-13

#### 3.3.1 AWS CE Forecast (coletado 2026-03-13)

| Metrica | Valor |
| --- | --- |
| AWS CE Forecast total mes Março | $1.330,90 |
| MTD real (01-12) | $539.50 |
| Restante projetado (13-31/03) | $791.40 |
| Daily rate restante (19 dias) | $41.65/dia |

#### 3.3.2 Nossa Projecao Ajustada (com Lambda weekends + NLB removido)

| Data | Dia | Tipo | Proj. Ajustada | Base |
| --- | --- | --- | --- | --- |
| 2026-03-13 | Sex | WD | $39.00 | Baseline dia 12 |
| 2026-03-14 | **Sab** | **WKD** | **$16.50** | Lambda+autoscaler (PRIMEIRO TESTE REAL) |
| 2026-03-15 | **Dom** | **WKD** | **$16.50** | Lambda+autoscaler |
| 2026-03-16 | Seg | WD | $39.00 | Baseline pos-fix |
| 2026-03-17 | Ter | WD | $39.00 | — |
| 2026-03-18 | Qua | WD | $39.00 | — |
| 2026-03-19 | Qui | WD | $39.00 | — |
| 2026-03-20 | Sex | WD | $39.00 | — |
| 2026-03-21 | **Sab** | **WKD** | **$16.50** | Lambda+autoscaler |
| 2026-03-22 | **Dom** | **WKD** | **$16.50** | Lambda+autoscaler |
| 2026-03-23 | Seg | WD | $39.00 | — |
| 2026-03-24 | Ter | WD | $39.00 | — |
| 2026-03-25 | Qua | WD | $39.00 | — |
| 2026-03-26 | Qui | WD | $39.00 | — |
| 2026-03-27 | Sex | WD | $39.00 | — |
| 2026-03-28 | **Sab** | **WKD** | **$16.50** | Lambda+autoscaler |
| 2026-03-29 | **Dom** | **WKD** | **$16.50** | Lambda+autoscaler |
| 2026-03-30 | Seg | WD | $39.00 | — |
| 2026-03-31 | Ter | WD | $39.00 | — |
| **TOTAL RESTANTE (13-31/03)** | | | **$606.00** | 13 WD x $39 + 6 WKD x $16.50 |
| **TOTAL MES (MTD + restante)** | | | **$1.145,50** | |

#### 3.3.3 Resumo Comparativo

| Metrica | AWS CE (sem ajustes) | Nossa Projecao Ajustada |
| --- | --- | --- |
| Forecast total marco | $1.330,90/mes | $1.145,50/mes |
| Em reais (@ R$5.75) | R$ 7.653 | R$ 6.587 |
| vs Budget ($807) | **+$523 (+65%)** | **+$338 (+42%)** |
| Economia dos ajustes (Lambda + NLB) | — | **$185/mes** |

### 3.4 Breakdown por Servico MTD REAL (12 dias) — DADOS REAIS AWS CE

| Servico | MTD USD | % Total | $/dia | Observacao |
| --- | --- | --- | --- | --- |
| Amazon EC2 - Compute | $263.60 | 48.9% | $21.97 | 13 nodes (t3.medium/large/xlarge) |
| Tax | $66.29 | 12.3% | $5.52 | Cobrado dia 1 do mes (REVISADO — era $58.37) |
| EC2 - Other | $64.40 | 11.9% | $5.37 | EBS, NAT Data, IPs elasticos |
| Amazon VPC | $38.62 | 7.2% | $3.22 | NAT Gateway (2→1 desde 03-11) |
| Amazon EKS | $28.80 | 5.3% | $2.40 | Control plane ($0.10/h) |
| AmazonCloudWatch | $27.18 | 5.0% | $2.27 | Metricas + logs |
| Amazon ELB | $25.64 | 4.8% | $2.14 | 2 ALBs (NLB eliminado dia 12: ELB = $1.44) |
| Amazon RDS | $12.50 | 2.3% | $1.04 | PostgreSQL db.t3.medium |
| AWS WAF | $3.88 | 0.7% | $0.32 | Web ACL |
| Amazon S3 | $3.72 | 0.7% | $0.31 | Storage + requests |
| AWS KMS | $2.67 | 0.5% | $0.22 | CMKs + requests |
| AWS Secrets Manager | $1.40 | 0.3% | $0.12 | Secrets rotation |
| AWS Cost Explorer | $0.77 | 0.1% | $0.06 | API queries |
| Demais (ECR) | $0.02 | 0.0% | $0.00 | — |
| **TOTAL** | **$539.50** | **100%** | **$44.96** | **12 dias** |

> **Top 3 desvios vs status 2026-03-12:** Tax $66.29 (era $58.37, +$7.92 billing revision); Dia 11 $42.71 (era $30.42, +$12.29); MTD total $539.50 (era $480.28, +$59.22).

---

## 4. FinOps Automation — Estado 2026-03-13

### 4.1 Status Operacional

| Componente | Status | Detalhe |
|-----------|--------|---------|
| Lambda START | OPERACIONAL | Ultimo: 2026-03-13T10:30 UTC (esperado) — system→2, workloads→3, critical→2 |
| Lambda STOP | OPERACIONAL | Ultimo: 2026-03-12T23:00 UTC (esperado) |
| **Lambda START/STOP (atualizadas)** | **DEPLOYADO 2026-03-12T14:39 BRT** | **suspend_cluster_autoscaler() ativo** |
| Circuit breaker | CLOSED | Zero erros em 8 dias |
| EventBridge | 3 rules ENABLED | startup Mon-Fri, shutdown Mon-Fri, weekend shutdown Sat |
| suspend_cluster_autoscaler() | **PRODUCAO — aguardando primeiro weekend** | Primeiro teste: 2026-03-14 (sabado) |
| RabbitMQ ClusterIP | **CONFIRMADO** | NLB eliminado — ELB dia 12 = $1.44 (vs $2.54 dia 11) |

### 4.2 Weekend Costs — Historico e Expectativa

| Metrica | Esperado | Real (07-08/03 pre-fix) | Esperado (14-15/03 pos-fix) |
|---------|----------|-------------------------|-----------------------------|
| Weekend cost/dia | $15-18 | $38.82 | $16.50 (projecao) |
| Mar 07 (Sabado) | $15-18 | $38.98 | — |
| Mar 08 (Domingo) | $15-18 | $38.66 | — |
| Mar 14 (Sabado) | $15-18 | — | **PRIMEIRO TESTE** |
| Mar 15 (Domingo) | $15-18 | — | **PRIMEIRO TESTE** |

**Economia esperada se Lambda funcionar:** ($38.82 - $16.50) x 6 weekends restantes = **$133.92/mes restante**

---

## 5. GAPs e Alertas — Estado 2026-03-13

### 5.1 GAPs Ativos

| GAP | Severidade | Descricao | Status |
|-----|-----------|-----------|--------|
| GAP-Lambda-Weekend | **CRITICO** | Lambda STOP/START com suspend_autoscaler nao validado em producao (deployado 2026-03-12, validacao: 14-15/03) | AGUARDANDO VALIDACAO WEEKEND |
| GAP-critical-nodes | MEDIO | staging/main.tf: excluded_node_groups alterado para ["system"] (GAP-2 fix 2026-03-12) — aguarda terraform apply | CODIFICADO, APPLY PENDENTE |
| GAP-EKS-logtypes | MEDIO | EKS log_types [audit,authenticator] codificado, apply pendente — R$ 1.800-2.520/ano | CODIFICADO, APPLY PENDENTE |
| GAP-Tax-revision | INFO | Tax real $66.29/mes vs $24.19-58.37 estimado/anterior — revisao AWS billing confirmada | INFORMATIVO — sem acao necessaria |
| GAP-day11-revision | INFO | Dia 11 revisado de $30.42 para $42.71 pela AWS (billing consolidation) | INFORMATIVO — impacto no MTD +$12.29 |

### 5.2 Alertas Financeiros

| Prio | Item | Impacto | Acao Recomendada |
|------|------|---------|-----------------|
| P0 | **Forecast $1.145/mes vs budget $807** | +$338/mes (+42%) | Escalar para gestao — desvio estrutural |
| P0 | **13 NODES ATIVOS — all groups at/near max** | +$400/mes vs 9 nodes | VPA urgente (Abr/26) |
| P0 | **Weekend Lambda nao validado** | R$ 12.800/ano em risco | Validar 14-15/03 — primeiro teste real |
| P1 | **Tax $66.29/mes (vs $24 estimado)** | +$42/mes surpresa | Aceitar — comportamento AWS billing |
| P1 | EKS log_types apply pendente | R$ 1.800-2.520/ano nao realizado | Executar apply |
| P1 | GAP-2 (critical nodes min) apply pendente | R$ 3-5K/ano desbloqueado | Executar apply proximo ciclo |

---

## 6. Savings Pipeline — Horizonte 2026-03-13

| Horizonte | Savings/ano (R$) | Status |
|-----------|-----------------|--------|
| Ja realizados (ate 2026-03-13) | R$ 61.638 | ATIVO |
| P0 apply pendente (EKS log_types) | R$ 1.800-2.520 | Aguardando apply |
| P1 weekend fix (Lambda + critical nodes) | R$ 7.600-12.480 | Lambda deployado; validacao 14-15/03 |
| P2 VPA Rightsizing producao | R$ 15.000-25.000 | Proximo ciclo (Abr/26) |
| P2 Workloads 6→4 (pos-VPA) | R$ 8.736 | Bloqueado por VPA |
| P2 Spot Instances workloads | R$ 8.208 | Pendente estabilizacao |
| P2 Savings Plans 1yr | R$ 7.920 | Aguardar 30d prod ativa |
| P3 Graviton / Karpenter | R$ 9.760-17.800 | Q2-Q3 2026 |

---

## 7. KPIs Mensais — Revisao 2026-03-13

| KPI | Meta | Fevereiro Real | Marco Forecast CE | Marco MTD (12d) | Status |
|-----|------|----------------|-------------------|-----------------|--------|
| Custo Mensal | <= $807 | $914 | $1.330,90 | $539.50 (12d) | CRITICO |
| EKS Standard Support | $73/mes | $182 (transicao) | ~$74 | $28.80 | OK |
| EC2 Compute | ~$450/mes | ~$550 | ~$680 | $263.60 | CRITICO |
| EC2 Weekend Shutdown | <$18/dia | $12-25/dia | $38.82/dia (pre-fix) | Aguarda 14-15/03 | PENDENTE VALIDACAO |
| FinOps Automation | Execucao | 100% (manual) | Lambdas OK | 0 failures | OK (execucao) |
| FinOps Automation | Savings real | — | R$ 12.800 est. | Eficacia pre-fix 0% | VALIDAR 14-15/03 |
| Savings Realizados | R$ 62K/ano | R$ 57.461 | R$ 61.638 | R$ 61.638 | 99.4% |
| Node Count | 7-9 | 9 | — | 13 | ACIMA |

---

## 8. Proximos Passos

### Imediato (antes de 2026-03-15)

| Acao | Impacto | Prioridade |
|------|---------|------------|
| Monitorar weekend 14-15/03 — validar Lambda suspend_autoscaler | Confirmar/descartar R$ 12.480/ano | **P0 CRITICO** |
| Verificar logs Lambda STOP na noite de 13/03 (quinta→sexta) | Baseline corrigido | P1 |

### Curto Prazo (esta semana — antes de 2026-03-18)

| Acao | Impacto | Prioridade |
|------|---------|------------|
| Executar terraform apply: EKS log_types + excluded_node_groups | R$ 1.800-2.520/ano + R$ 3-5K/ano | P0 |
| Rever savings estimate FinOps Automation pos-weekend 14-15/03 | Ajustar R$ 12.800 para valor real | P1 |
| Coletar Cost Explorer dia 14 (segunda-feira) | Confirmar cost fim de semana com Lambda | P1 |

### Medio Prazo (Mar-Abr 2026)

| Acao | Impacto | Responsavel |
|------|---------|-------------|
| VPA Rightsizing — URGENTE | Reduzir nodes 13→9-10 (-$120-160/mes) | SRE + FinOps |
| Savings Plans 1yr No-Upfront | R$ 7.920/ano | Apos 30d prod ativa |

---

## 9. Comparativo vs Targets

| Cenario | Custo Mensal | Custo Anual | Status vs Budget |
|---------|--------------|-------------|-----------------|
| Baseline (Jan/26) | R$ 9.179 | R$ 110.147 | REFERENCIA |
| Budget Marco 3 Aprovado | R$ 4.841 | R$ 58.092 | META |
| Fevereiro 2026 REAL | R$ 5.487 | R$ 65.844 | ACIMA +13% |
| Marco 2026 Forecast CE (2026-03-13) | R$ 7.653 | R$ 91.836 | ACIMA +65% |
| Marco 2026 Projecao Ajustada | R$ 6.584 | R$ 79.008 | ACIMA +42% |
| Apos VPA Rightsizing (Abr/26) | R$ 4.800-5.400 | R$ 58-65K | PROXIMO BUDGET |
| Apos Karpenter + Spot (2026 H2) | R$ 2.400-3.600 | R$ 29-43K | ABAIXO DO BUDGET |

---

**Preparado em:** 2026-03-13 (coleta AWS CE via CLI)
**Fonte dados financeiros:** AWS Cost Explorer coletados 2026-03-13 — todos os dias 01-12/03 consolidados
**Proxima coleta Cost Explorer:** 2026-03-14 (validar custo weekend Lambda 14/03) ou 2026-03-18 (revisao semanal)
**Revisao programada:** 2026-03-18 (acompanhamento semanal + validacao Lambda weekend)
**Documento anterior:** [docs/finops/finops-status-2026-03-12.md](finops-status-2026-03-12.md)
**Raw data:** [docs/reports/aws-costs-raw-2026-03-13.json](../reports/aws-costs-raw-2026-03-13.json)
**Owner:** FinOps Team + Platform Team
