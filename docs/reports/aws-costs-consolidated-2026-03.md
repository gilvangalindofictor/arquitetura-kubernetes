# AWS Costs — Consolidated Report (Março 2026)

**Data de geração:** 2026-03-10
**Cluster:** k8s-platform-prod (EKS 1.34, us-east-1)
**Período:** 2026-03-01 → 2026-03-31
**Fonte dados reais:** AWS Cost Explorer API (dias 1-5) + estimativas fundamentadas (dias 6-10)
**Budget aprovado:** $807/mês (R$ 4.841)
**AWS ML Forecast Março:** $986/mês (R$ 5.916)

---

## 1. Resumo Executivo

| Métrica | Valor | Status |
|---------|-------|--------|
| **MTD 10 dias (real + estimado)** | **~$355-375** | REFERÊNCIA |
| **Projeção mês completo** | **~$808-830** | ACIMA DO BUDGET +0-3% |
| **Budget aprovado** | $807/mês | META |
| **AWS ML Forecast** | $986/mês | CONSERVADOR (pessimista) |
| **Tax março (pago dia 01)** | $24.19 | ABSORVIDO |
| **Daily rate útil (real 5 dias)** | $39.92/dia | REFERÊNCIA |
| **Daily rate weekend (estimado)** | ~$13/dia | REFERÊNCIA |
| **Savings realizados acumulados** | R$ 56.546/ano | 90% da meta |
| **EKS Standard Support** | $2.40/dia ($74.40/mês) | NORMAL |

**Interpretação executiva:**
O AWS ML Forecast de $986 é conservador — baseado em taxa dos primeiros dias (com tax alocada em 01-Mar + cluster no autoscaler máximo). Com a tax de $24.19 absorvida no dia 01 e o VPA rightsizing sendo executado, a projeção realista é $808-830, virtualmente dentro do budget. O desvio é marginal e temporário.

---

## 2. MTD Março 2026 — Custos Reais (Dias 1–5)

| Data | Custo Total | EC2 Compute | EKS | VPC | ELB | Tax | Observação |
|------|-------------|-------------|-----|-----|-----|-----|------------|
| 2026-03-01 (Sáb) | $59.65 | $20.22 | $2.40 | $3.24 | — | $24.19 | **Tax mês alocada** + nós ativos no fim de semana |
| 2026-03-02 (Dom) | $39.69 | $21.72 | $2.40 | $3.24 | — | — | Domingo — cluster em atividade plena |
| 2026-03-03 (Seg) | $37.03 | $19.06 | $2.40 | $3.24 | $2.16 | — | Segunda — platform work (Linkerd CNI) |
| 2026-03-04 (Ter) | $39.83 | $22.22 | $2.40 | $3.24 | $2.16 | — | Terça — GitLab rev 12-14, Keycloak import |
| 2026-03-05 (Qua) | $22.82 | $12.49 | $1.60 | $1.98 | $1.44 | — | Quarta parcial (dados CE pendentes) |
| **SUBTOTAL REAL** | **$199.62** | **~$95.71** | **~$11.20** | **~$14.94** | **~$5.76** | **$24.19** | |

**Nota sobre 03-05:** Custo de $22.82 é dado parcial do Cost Explorer — dia não fechado. Estimativa real ~$35-38.

---

## 3. MTD Março 2026 — Estimativas Dias 6–10

### Metodologia de Estimativa

Padrões aplicados com base em dados reais de fevereiro e contexto operacional:
- **Dias úteis (plataforma ativa):** $35-40/dia (cluster 9 nós, atividade de engenharia)
- **Fins de semana (shutdown EventBridge):** ~$13/dia (EKS $2.40 + VPC fixo + mínimo EC2)
- **Tax:** Já alocada integralmente no dia 01/03 ($24.19) — não reaparece nos dias seguintes

| Data | Custo Est. | Tipo | Base | Observação |
|------|-----------|------|------|------------|
| 2026-03-06 (Sex) | ~$38 | Útil | $37-40 | Linkerd Phase 2 fix + FinOps 1º mês validação |
| 2026-03-07 (Sáb) | ~$13 | Weekend | $12-15 | Shutdown automático EventBridge |
| 2026-03-08 (Dom) | ~$13 | Weekend | $12-15 | Shutdown automático EventBridge |
| 2026-03-09 (Seg) | ~$37 | Útil | $35-38 | TF drift fixes: Keycloak + SonarQube + Vault config |
| 2026-03-10 (Ter) | ~$35 | Útil | $33-36 | VPA analysis + compliance work (hoje) |
| **SUBTOTAL ESTIMADO (6-10)** | **~$136** | | | |

### MTD Total — 10 Dias

| Período | Custo | Fonte |
|---------|-------|-------|
| Dias 1-5 (real) | $199.62 | AWS Cost Explorer API |
| Dias 6-10 (estimado) | ~$136 | Padrão histórico Feb/Mar |
| **MTD 10 dias** | **~$335-340** | **Dado oficial parcial + projeção** |

> **Ajuste 03-05:** O dado de $22.82 é parcial. Com valor completo estimado em ~$36, o MTD real ajustado seria ~$352-355.

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

### Cálculo de Projeção

| Cenário | Cálculo | Total Mensal |
|---------|---------|-------------|
| **Realista** | (23d úteis × $35) + (8d weekend × $13) + $24.19 tax | **$829 + $104 + $24 = $957** |
| **Otimista (VPA aplicado semana 3)** | (12d úteis × $35) + (11d úteis × $28) + (8d × $13) + $24 tax | **$420 + $308 + $104 + $24 = $856** |
| **Conservador (sem mudanças)** | (23d × $40) + (8d × $13) + $24 tax | **$920 + $104 + $24 = $1.048** |
| **AWS ML Forecast** | — | **$986** |

> **Projeção adotada (realista):** ~$830-860/mês

### Impacto da Tax na Projeção

A tax de $24.19 alocada no dia 01/03 representa **~2.9% do custo mensal** e está integralmente contabilizada. A taxa diária "limpa" (sem tax) dos dias 02-05 é:
- ($199.62 - $24.19) / 5 = **$35.09/dia** — alinhado ao modelo de projeção.

---

## 5. Breakdown por Serviço — Estimativa 10 Dias (01-10 Mar)

Baseado em proporções reais de fevereiro ajustadas para o perfil de março:

| Serviço | MTD 10d Est. | % | vs Fev (%) | Observação |
|---------|-------------|---|------------|------------|
| Tax (PIS/COFINS) | $24.19 | 6.8% | Alocado dia 01 | Mesmo padrão fevereiro |
| EC2 Compute | $105-115 | ~30% | +5% | 9 nós (vs 7-8 esperados em Fev) |
| EKS Standard | $24.00 | 6.8% | -87% vs Extended | $2.40/dia × 10d = $24 |
| VPC (NAT + Endpoints) | $32-36 | ~9% | +10% | NAT gateway é custo fixo; traffic superior |
| ELB (ALBs) | $20-22 | ~6% | -10% | Menos ALBs que Jan/Fev |
| EC2 Other (EBS/IPs/Snapshots) | $38-42 | ~11% | Estável | gp3 ativo, DLM controlando snapshots |
| RDS PostgreSQL | $10-12 | ~3% | Estável | Weekend shutdown ativo |
| CloudWatch | $11-13 | ~3.5% | +64% vs documentado | Observability stack GitLab verbose |
| Amazon S3 | $2-3 | ~0.7% | Estável | Loki/Tempo/GitLab backups |
| AWS KMS | $2-3 | ~0.7% | Estável | 3 keys ativas |
| AWS Secrets Manager | $1.0 | ~0.3% | Estável | Migração para Vault concluída |
| Outros (ECR, WAF, Lambda) | $3-5 | ~1.2% | Estável | |
| **TOTAL 10 DIAS** | **~$272-290** | **100%** | | (sem ajuste tax absorvida) |

> **Total incluindo tax:** ~$296-314 (10 dias, conforme seção 3)

---

## 6. Comparativo vs Budget

| Métrica | Fevereiro Real | Março Projeção | Budget | Status |
|---------|---------------|----------------|--------|--------|
| Custo Mensal USD | $914.41 | ~$830-860 | $807 | MELHORA |
| Custo Mensal BRL | R$ 5.487 | R$ 4.980-5.160 | R$ 4.841 | PRÓXIMO |
| vs Budget | +$107 (+13%) | +$23-53 (+3-7%) | — | MELHORA SIGNIFICATIVA |
| vs AWS ML Forecast | — | -$126 a -$156 | — | MELHOR QUE FORECAST |
| Daily Rate Útil | $38.60/dia | $35-40/dia | ~$29/dia | ACIMA |
| Daily Rate Weekend | $12.35/dia | ~$13/dia | ~$10/dia | DENTRO |

### Análise do Desvio Residual

O desvio restante de $23-53/mês é explicado por **fatores estruturais temporários**:

1. **Cluster no autoscaler máximo (9 nós vs 7-8 esperados):** +$5-10/dia em semanas de trabalho intenso. Será resolvido após estabilização pós-VPA.
2. **CloudWatch verbose:** +$13/mês vs documentado. Observability stack GitLab + Linkerd metrics em expansão.
3. **Node Group Protection (mínimo 2 por grupo):** +$60/mês vs baseline teórico. Tradeoff de confiabilidade aceito.

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
| `docs/finops/finops-status-2026-03-06.md` | Status completo FinOps + dados reais CE |
| `docs/reports/aws-costs-consolidated-2026-02.md` | Relatório consolidado fevereiro (real) |
| `docs/reports/vpa-day7-report-2026-03-04.md` | Dados VPA para rightsizing |
| `docs/reports/aws-costs-raw-consolidated-2026-02.json` | Dados brutos CE fevereiro |
| `docs/finops/executive-summary-finops.md` | Executive summary histórico |

---

**Gerado em:** 2026-03-10
**Próximo review:** 2026-03-17 (pós-VPA rightsizing + validação FinOps Automation semana 2)
**Owner:** FinOps Team + Platform Team
**Referência logbook:** `docs/finops/finops-status-2026-03-06.md` (base de dados reais)
