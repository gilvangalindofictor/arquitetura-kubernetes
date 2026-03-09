# Relatorio FinOps — Status Financeiro Atualizado

**Data:** 2026-03-06
**Cluster:** k8s-platform-prod (EKS 1.34)
**Periodo de Referencia:** Jan/2026 — Mar/2026
**Fonte Dados Reais:** AWS Cost Explorer API (aws ce get-cost-and-usage, conta 891377105802)
**Status Geral:** ATENCAO — Acima do budget em Mar/26 | 90% do roadmap realizado

---

## 1. Resumo Executivo

| Metrica | Valor |
|---------|-------|
| **Custo Baseline (Jan/Fev 2026 — antes otimizacoes)** | R$ 9.179/mes ($1.530/mes) |
| **Custo Fevereiro 2026 REAL** | **$914.41 = R$ 5.487** |
| **Budget Marco 3 Aprovado** | $807/mes (R$ 4.841) |
| **Status Fevereiro vs Budget** | ACIMA em $107 (+13%) |
| **Forecast Marco 2026 (AWS ML)** | **$986/mes = R$ 5.916** |
| **Status Marco vs Budget** | ACIMA em $179 (+22%) |
| **Reducao vs Baseline** | -40% (real) |
| **Savings Realizados (acumulado)** | **R$ 56.546/ano** |
| **Savings Projetados (pós-VPA)** | +R$ 15.000-17.000/ano |
| **Total Projetado (roadmap completo)** | **R$ 87-89K/ano** |
| **Meta Original** | R$ 62K/ano |
| **Realizacao vs Meta** | **143%** |

**Razoes para desvio vs budget (ver secao 7):**
- Cluster autoscaler at max durante trabalho de plataforma (Linkerd Phase 2, GitLab, Keycloak)
- 9 nos ativos vs 7-8 esperados (workloads=4, system=3, critical=2)
- VPA rightsizing nao executado ainda (dados disponiveis, execucao pendente)

---

## 2. Custo Baseline — Antes das Otimizacoes (Jan/Fev 2026)

Dados reais do AWS Cost Explorer (28/Jan/2026 — 10/Fev/2026, com EKS Extended Support ativo):

| Componente | USD/mes | BRL/mes (R$6.0) | % Total |
|------------|---------|-----------------|---------|
| EKS Control Plane (Extended Support 1.31) | $433.00 | R$ 2.598 | 28.3% |
| EC2 Compute (10 nodes) | $607.49 | R$ 3.645 | 39.7% |
| EC2 Other (EBS, IPs, snapshots) | $126.00 | R$ 756 | 8.2% |
| VPC (NAT Gateway + Endpoints) | $78.00 | R$ 468 | 5.1% |
| ALB/NLB (10 units) | $74.00 | R$ 444 | 4.8% |
| RDS PostgreSQL | $29.00 | R$ 174 | 1.9% |
| CloudWatch (logs + metrics) | $21.00 | R$ 126 | 1.4% |
| Secrets Manager (17+ secrets) | $21.24 | R$ 127 | 1.4% |
| KMS | $5.80 | R$ 35 | 0.4% |
| S3 (Loki, Tempo, GitLab) | $25.80 | R$ 155 | 1.7% |
| Observability (kube stack) | $32.00 | R$ 192 | 2.1% |
| Data Services (Redis, RabbitMQ) | $48.50 | R$ 291 | 3.2% |
| Tax + Outros | $148.45 | R$ 891 | 9.7% |
| **TOTAL BASELINE** | **$1.530** | **R$ 9.179** | **100%** |

---

## 3. Dados Reais AWS Cost Explorer — Fevereiro 2026 (Mes Completo)

**Total Real Fevereiro 2026: $914.41 (R$ 5.487)**

### 3.1 Custos Diarios Fevereiro (Real)

| Data | Custo | Observacao |
|------|-------|------------|
| 2026-02-01 | $147.43 | Tax mes + burst deploy + EKS Extended $14.40/dia |
| 2026-02-02 | $40.60 | EKS Extended |
| 2026-02-03 | $47.80 | EKS Extended |
| 2026-02-04 | $47.26 | EKS Extended |
| 2026-02-05 | $40.94 | EKS Extended |
| 2026-02-06 | $38.44 | EKS Extended |
| 2026-02-07 | $25.71 | Sabado — shutdown efetivo |
| 2026-02-08 | $25.71 | Domingo — shutdown efetivo |
| 2026-02-09 | $40.49 | Retorno semana |
| **2026-02-10** | $36.88 | **EKS Upgrade concluido — EKS cai de $14.40 para $2.40/dia** |
| 2026-02-11 | $24.04 | ALBs deletados |
| 2026-02-12 | $26.51 | Orphan cleanup + Quick Wins |
| 2026-02-13 | $29.75 | EBS gp3 + Snapshot Lambda |
| 2026-02-14 | $12.07 | Sexta — shutdown |
| 2026-02-15 | $12.07 | Sabado — custo minimo |
| 2026-02-16 | $15.78 | Domingo — parcial |
| 2026-02-17 | $13.68 | Semana, cluster light |
| 2026-02-18 | $24.85 | Reinicio atividade |
| 2026-02-19 | $27.59 | Normal |
| 2026-02-20 | $24.83 | Normal |
| 2026-02-21 | $12.35 | Sabado — shutdown |
| 2026-02-22 | $12.35 | Domingo — shutdown |
| 2026-02-23 | $25.28 | FinOps FASE 2 habilitado |
| 2026-02-24 | $24.41 | PDB Optimization |
| 2026-02-25 | $31.55 | Trabalho GitLab + Keycloak |
| 2026-02-26 | $32.01 | CI/CD Enhancement + Kyverno |
| 2026-02-27 | $37.64 | Snapshot DLM + Linkerd Phase 2 |
| 2026-02-28 | $36.41 | GitLab cleanup + docs |
| **TOTAL FEV** | **$914.41** | |

### 3.2 Breakdown por Servico — Fevereiro 2026 (Real AWS)

| Servico | USD Real | % | vs Baseline | Observacao |
|---------|----------|---|-------------|------------|
| EKS Control Plane | $182.32 | 19.9% | -58% | Extended Feb 1-9 + Standard Feb 10-28 |
| EC2 Compute | $269.29 | 29.5% | -56% | Weekend shutdown efetivo |
| EC2 Other (EBS/NAT/IPs) | $119.15 | 13.0% | -5% | EBS volumes + NAT fixo |
| Amazon VPC | $80.42 | 8.8% | +3% | NAT + Endpoints ($80 vs $78 esperado) |
| Elastic Load Balancing | $71.09 | 7.8% | -4% | ALBs deletados a partir de Feb 11 |
| AmazonCloudWatch | $34.47 | 3.8% | +64% | Observability stack GitLab verbose |
| RDS PostgreSQL | $29.02 | 3.2% | 0% | Weekend shutdown efetivo |
| AWS KMS | $6.73 | 0.7% | +16% | 3 keys ativas |
| Amazon S3 | $6.01 | 0.7% | -77% | Reducao vs projecao inicial |
| AWS WAF | $0.79 | 0.1% | NOVO | WAF ativado (nao estava no baseline) |
| AWS Secrets Manager | $3.05 | 0.3% | -86% | Reducao significativa |
| Tax | $111.10 | 12.2% | - | PIS/COFINS (alocado dia 1) |
| Outros (ECR, ECS, DynamoDB, etc.) | $1.00 | 0.1% | - | Negligivel |
| **TOTAL FEVEREIRO** | **$914.41** | **100%** | **-40% vs baseline** | |

**Analise da queda EKS Feb:**
- Feb 01-09 (9 dias): $14.40/dia = $129.60 (Extended Support)
- Feb 10-28 (19 dias): $2.40/dia = $45.60 (Standard Support, pos-upgrade)
- Total Feb: $175.20 de EKS puro + $7.12 de ajustes = $182.32

---

## 4. Dados Reais AWS — Marco 2026 (MTD + Forecast)

### 4.1 Custos Diarios Marco 2026 (Real)

| Data | Custo Total | EC2 Compute | EKS | VPC | ELB | Tax | Observacao |
|------|-------------|-------------|-----|-----|-----|-----|------------|
| 2026-03-01 | $59.65 | $20.22 | $2.40 | $3.24 | - | $24.19 | Tax mes + sabado com nos ativos |
| 2026-03-02 | $39.69 | $21.72 | $2.40 | $3.24 | - | - | Domingo — cluster em atividade |
| 2026-03-03 | $37.03 | $19.06 | $2.40 | $3.24 | $2.16 | - | Segunda — platform work |
| 2026-03-04 | $39.83 | $22.22 | $2.40 | $3.24 | $2.16 | - | Terca — GitLab rev 12-14 |
| 2026-03-05 | $22.82 | $12.49 | $1.60 | $1.98 | $1.44 | - | Quarta parcial |
| **MTD (5 dias)** | **$199.62** | | | | | | |

**AWS ML Forecast Marco 2026: $986/mes (R$ 5.916)**

### 4.2 Estado Atual dos Node Groups (2026-03-06)

| Node Group | Min | Desired | Max | Custo/dia est. |
|------------|-----|---------|-----|----------------|
| workloads (t3.large) | 2 | **4** | 6 | ~$16/dia |
| system (t3.medium) | 2 | **3** | 4 | ~$7/dia |
| critical (t3.xlarge) | 2 | **2** | 4 | ~$8/dia |
| **TOTAL** | **6** | **9** | **14** | **~$31/dia** |

**Observacao:** Cluster em 9 nos (vs 7-8 esperados) devido ao trabalho intenso de plataforma (Linkerd Phase 2, GitLab rev 12-14, Keycloak import, Kyverno, etc.) que forcou autoscaler ao maximo.

---

## 5. Otimizacoes Implementadas — Cronologia e Impacto Real

### 5.1 Quick Wins — Fevereiro 2026

| Data | Otimizacao | Economia Anual | Status |
|------|-----------|----------------|--------|
| 2026-02-10 | **EKS Upgrade 1.31 → 1.34** | **R$ 25.920** | ATIVO ✅ |
| 2026-02-11 | ALBs deletados (nginx-test + echo-server) | R$ 1.920 | ATIVO ✅ |
| 2026-02-11 | NLBs deletados (RabbitMQ, 2 units) | R$ 384 | ATIVO ✅ |
| 2026-02-12 | CloudWatch Logs retention policies | R$ 54 | ATIVO ✅ |
| 2026-02-12 | S3 Gateway Endpoint (NAT savings) | R$ 900 | ATIVO ✅ |
| 2026-02-12 | Orphan cleanup (EBS volumes + snapshots) | R$ 2.221 | ATIVO ✅ |
| 2026-02-12 | Orphan detector Lambda | R$ 1.000 | ATIVO ✅ |
| 2026-02-13 | EBS gp2 → gp3 (node disks + PVCs) | R$ 830 | ATIVO ✅ |
| 2026-02-13 | EBS gp2 → gp3 Prometheus | R$ 29 | ATIVO ✅ |
| 2026-02-13 | Snapshot Cleanup Lambda | R$ 216 | ATIVO ✅ |
| 2026-02-18 | RDS Weekend Shutdown | R$ 1.200 | ATIVO ✅ |
| 2026-02-18 | Keycloak backup automation | R$ 1.200 | ATIVO ✅ |
| - | SonarQube exporter (vs deploy externo) | R$ 50 | ATIVO ✅ |
| **SUBTOTAL QUICK WINS** | | **R$ 35.924** | |

### 5.2 Medium Wins — Fevereiro 2026

| Data | Otimizacao | Economia Anual | Status |
|------|-----------|----------------|--------|
| 2026-02-23 | **FinOps FASE 2 — Automacao EventBridge** | **R$ 13.597** | ATIVO ✅ |
| 2026-02-24 | **PDB Optimization** — shutdown graceful | R$ 4.405 | ATIVO ✅ |
| 2026-02-27 | **Snapshot DLM** (3 policies: 30d/14d/7d) | R$ 5.052 | ATIVO ✅ |
| 2026-02-27 | Node Group Protection (custo de confiabilidade) | -R$ 720 | ATIVO ✅ |
| **SUBTOTAL MEDIUM WINS** | | **R$ 22.334** | |

### 5.3 Total Realizados

| Categoria | Economia Anual |
|-----------|----------------|
| Quick Wins | R$ 35.924 |
| Medium Wins | R$ 22.334 |
| **TOTAL REALIZADOS** | **R$ 56.546/ano** |
| Meta original | R$ 62.856/ano |
| % da meta | **90%** |

---

## 6. Analise de Budget — Fevereiro vs Marco 2026

| Metrica | Fevereiro (Real) | Marco (Forecast) | Budget Aprovado |
|---------|-----------------|-----------------|-----------------|
| Custo USD | $914.41 | $986 | $807 |
| Custo BRL (R$6.0) | R$ 5.487 | R$ 5.916 | R$ 4.841 |
| vs Budget | +$107 (+13%) | +$179 (+22%) | - |
| Status | ACIMA | ACIMA | META |

### Causas do Desvio

1. **Cluster autoscaler at max:** Trabalho intenso de plataforma em Feb-Mar/26 forcou escalonamento de 7 para 9 nos. Cada no adicional = +$5-16/dia.

2. **Cluster em expansao:** Backstage M1 + 2 apps sendo esteiradas adicionam carga ao cluster durante periodo de coleta VPA, tornando as recommendations ruidosas.

3. **Trabalho de plataforma nao recorrente:** Linkerd Phase 2, GitLab rev 12-14, Keycloak import (11 recursos), Harbor OOM fixes, ArgoCD upgrade — tudo demandou compute extra temporario.

4. **Node Group Protection adicional:** +$720/ano (+$60/mes) para manter system+critical no minimo 2 nos cada.

5. **CloudWatch acima do esperado:** $34.47 real em Feb vs $21 documentado. GitLab observability e Linkerd metrics em expansao.

### Decisao Estrategica — VPA Staging (2026-03-06)

VPA rightsizing em staging **ADIADO** — prioridade redirecionada para producao.

Razoes:
- Dados reais mostram 2/5 VPAs com recomendacoes, ambos ja no minAllowed (saving real: R$ 62/ano)
- Cluster instavel: Backstage M1 + 2 apps esteiradas adicionando carga durante coleta
- Producao sera implementada em breve — mesmo esforco gera 3-5x mais retorno la
- o t3.medium a 91% de memoria e risco operacional, nao de rightsizing

Ver estrategia completa na secao 8.

---

## 7. Alertas e Riscos Financeiros

| Prioridade | Item | Impacto | Acao |
|------------|------|---------|------|
| P0 | **Forecast Marco acima do budget** | +$179/mes vs budget | Aceitar temporariamente — cluster em expansao (Backstage + prod) |
| P0 | **t3.medium a 91% de memoria** | Risco OOMKill no node system | Investigar qual pod esta consumindo + migrar para workloads node |
| P1 | **CloudWatch +64% vs documentado** | $34/mes vs $21 esperado | Revisar log retention e custom metrics |
| P1 | **Fin Automation — validar 1o. mes** | R$ 13.597/ano em risco se falhar | Confirmar execucoes automaticas sem falhas |
| P2 | **DT-005 Teams Webhook** | Alertas financeiros nao chegam ao Teams | Pendente URL webhook Teams — decisao 2026-03-06: Teams substituiu Slack |

---

## 8. Estrategia de Savings — Decisao 2026-03-06

### 8.1 VPA Staging — FECHADO SEM EXECUCAO

**Decisao:** Nao executar rightsizing em staging. Item encerrado.

**Justificativa:**

| Fator | Detalhe |
|-------|---------|
| Dados insuficientes | 2/5 VPAs com recomendacao, ambos no minAllowed (saving real: R$ 62/ano) |
| Dados ruidosos | Backstage M1 + 2 apps esteiradas distorcem coleta durante periodo ativo |
| Custo de oportunidade | Mesmo esforco em producao rende 3-5x mais retorno |
| Gargalo real | t3.medium a 91% MEM e problema de scheduling, nao de rightsizing |
| Producao a caminho | Staging deixara de ser o principal centro de custo em breve |

**Uso dos dados coletados:** Os dados de VPA de staging serao usados como **referencia para os requests iniciais de producao**, evitando que producao suba oversized e precise de 7 dias para corrigir.

| Workload | Request Inicial Recomendado (producao) | Fonte |
|----------|---------------------------------------|-------|
| redis | cpu: 25m, memory: 65Mi | VPA uncappedTarget staging |
| harbor-core | cpu: 15m, memory: 65Mi | VPA uncappedTarget staging |
| Demais | Usar staging como referencia + VPA day-1 | Coletar em producao |

---

### 8.2 Producao — Estrategia FinOps desde o Dia 1

**Principio:** Producao roda 24/7. As alavancas que nao funcionavam em staging (Savings Plans, Reserved Instances) tornam-se obrigatorias em producao.

#### Dia 1 do Deploy de Producao

- Implantar VPA `mode=Off` em **TODOS** os workloads desde o primeiro deploy
- Usar requests iniciais calibrados pelos dados de staging (tabela acima)
- Nao aguardar problemas para agir — partir de uma baseline ja informada

#### Apos 7 dias (coleta VPA)

- Executar rightsizing com dados de carga real de producao
- Savings estimados: **R$ 25.000-35.000/ano** (cluster 24/7, maior que staging)

#### Apos 30 dias (dados Cost Explorer)

Comprar na mesma janela — sem protelacao:

| Compromisso | Saving Anual | Acao |
|-------------|-------------|------|
| Compute Savings Plans 1yr No-Upfront | R$ 11.363 | `aws ce get-savings-plans-purchase-recommendation` para validar commitment |
| RDS Reserved Instance 1yr No-Upfront | R$ 3.024 | Comprar via console RDS |
| **Total imediato** | **R$ 14.387** | Payback < 1 mes |

**Nota:** SP e RI sao inviáveis em staging (weekend shutdown elimina utilização base necessaria para o commitment ser lucrativo). Em producao 24/7, o break-even e imediato.

---

### 8.3 Savings Restantes em Staging (contexto)

| Iniciativa | Saving/ano | Prioridade | Decisao |
|-----------|-----------|------------|---------|
| VPA Rightsizing staging | R$ 7-11K | — | **CANCELADO** — ROI insuficiente vs prod |
| Karpenter + Spot (staging) | R$ 6.696 | P3 | Aguardar estabilizacao pos-Backstage |
| Graviton ARM64 (staging) | R$ 6.984 | P3 | Aguardar VPA producao concluido |

---

## 9. ROI das Otimizacoes Implementadas

| Categoria | Investimento Eng | Savings Anuais | ROI |
|-----------|-----------------|----------------|-----|
| EKS Upgrade (4h × R$300) | R$ 1.200 | R$ 25.920 | 2.060% |
| Quick Wins (13h × R$300) | R$ 3.900 | R$ 8.033 | 206% |
| FinOps Automation (20h × R$300) | R$ 6.000 | R$ 13.597 | 227% |
| PDB Optimization (8h × R$300) | R$ 2.400 | R$ 4.405 | 183% |
| Snapshot DLM (4h × R$300) | R$ 1.200 | R$ 5.052 | 421% |
| **TOTAL REALIZADOS** | **R$ 14.700** | **R$ 57.007** | **388%** |

Payback medio: **3,1 meses**.

---

## 10. Historico de Custos — Linha do Tempo (Dados Reais)

```
BASELINE (Abr/26 projecao sem acao):    R$ 9.179/mes = R$ 110.147/ano

Jan/26 Cluster deploy (EKS 1.31):       ~R$ 1.380 (parcial, 4 dias)
Fev/26 REAL (mes completo):             R$ 5.487 = $914.41
  - Pico: R$ 884 (Feb 01, tax + extended)
  - Minimo: R$ 72.42 (Feb 14-15, shutdown weekend)
  - Tendencia: -73% da semana 1 para semana 3

Mar/26 FORECAST (AWS ML):               $986 = R$ 5.916
  - MTD 5 dias: R$ 1.198 = $199.62
  - Daily rate: ~$35-40/dia (cluster em max autoscaler)

Pos-VPA Rightsizing (Abr/26 estimativa): $850-900/mes = R$ 5.100-5.400
  - Com 7 nos (vs 9 atuais): -$60-80/mes
  - Meta: retornar ao budget $807

Roadmap completo (2027 projecao):
  - Karpenter + Spot: adicional -R$ 558/mes
  - Graviton: adicional -R$ 582/mes
  - Meta: $600-700/mes
```

---

## 11. Comparativo vs Targets

| Cenario | Custo Mensal | Custo Anual | Status vs Budget |
|---------|--------------|-------------|-----------------|
| Baseline (Jan/26) | R$ 9.179 | R$ 110.147 | REFERENCIA |
| Budget Marco 3 Aprovado | R$ 4.841 | R$ 58.092 | META |
| **Fevereiro 2026 REAL** | **R$ 5.487** | **R$ 65.844** | **ACIMA +13%** |
| **Marco 2026 Forecast** | **R$ 5.916** | **R$ 70.992** | **ACIMA +22%** |
| Apos VPA Rightsizing (Abr/26 est.) | R$ 5.100-5.400 | R$ 61-65K | PROXIMO DO BUDGET |
| Apos Karpenter + Spot (2026 H2) | R$ 3.600-4.200 | R$ 43-50K | ABAIXO DO BUDGET |

---

## 12. KPIs Mensais (Revisao 2026-03-06)

| KPI | Meta | Fevereiro Real | Marco Forecast | Status |
|-----|------|----------------|----------------|--------|
| Custo Mensal | <= $807 | $914 | $986 | ATENCAO |
| EKS Standard Support | $73/mes | $182 (transicao) | $69 (on track) | OK MAR |
| EC2 Weekend Shutdown | <$1/dia | $12-25/dia weekend | Variavel | MONITORAR |
| FinOps Automation | 95% success | 100% (5/5 manual) | Validacao em curso | MONITORAR |
| VPA Rightsizing | 10 workloads | 0/10 | 0/10 | URGENTE |
| Kyverno Compliance | 100% | 100% | 100% | OK |
| Savings Realizados | R$ 62K/ano | R$ 56.546 | R$ 56.546 | 90% |

---

## 13. Acoes Prioritarias — Marco 2026

| # | Acao | Impacto | Urgencia |
|---|------|---------|---------|
| 1 | **Executar VPA Rightsizing** (10 workloads com data) | -R$ 15-17K/ano, -$60-80/mes | CRITICO |
| 2 | **Verificar FinOps Automation** (1o. mes execucoes automaticas) | R$ 13.597/ano em risco | ALTA |
| 3 | **Reduzir nos workloads de 4 para 2** apos VPA | -$320/mes (2x t3.large) | MEDIA |
| 4 | **Investigar CloudWatch $34/mes** (vs $21 documentado) | -$13/mes potencial | MEDIA |
| 5 | **DT-005 Webhooks Teams** | Alertas financeiros ao Teams (decisao 2026-03-06: Teams substituiu Slack) | BAIXA |

---

**Preparado em:** 2026-03-06
**Dados reais extraidos de:** AWS Cost Explorer API (aws ce get-cost-and-usage)
**Proximo review:** 2026-03-10 (pos VPA rightsizing + validacao FinOps 1o. mes)
**Owner:** FinOps Team + Platform Team
**Referencia base:** [docs/finops/executive-summary-finops.md](executive-summary-finops.md) (historico 2026-02-10)
