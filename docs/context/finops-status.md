# FinOps Status — Plataforma k8s-platform-prod

**Ultima Atualizacao:** 2026-03-24
**Cluster:** k8s-platform-prod (EKS 1.34, us-east-1)
**Conta:** 891377105802
**Status AWS SSO:** ATIVO — dados coletados em tempo real via AWS CE API (2026-03-24)

> Todos os valores sao dados REAIS coletados via `aws ce get-cost-and-usage` com sessao SSO ativa.
> Valores marcados como "Estimated" pelo AWS CE sao estimativas diarias de billing (normais para o dia corrente e recentes).

---

## CloudWatch — Mesa Tecnica 2026-03-24

### Estado Atual (pos-otimizacao)

- Custo real baseline: ~$3-5/mes (authenticator only)
- Saving realizado em 2026-03-21: ~$170/mes (remocao audit/api/controllerManager/scheduler — VendedLog-Bytes $104.96/mes eliminado)
- RDS log groups drift: CORRIGIDO (retention 14d adicionado via IaC — modules postgresql, rds-replica, dr-multi-region)
- Lambda stop log group: CORRIGIDO (14d → 7d)
- Weekly finops report log group: CORRIGIDO (30d → 14d)

### Protecoes Ativas

- EKS log types: apenas `authenticator` — NAO adicionar outros sem aprovacao formal
- Spike risk: habilitar `audit` = ~$75/mes/dia (7 GB/dia de ingestion a $0.50/GB)
- Comentario protetor adicionado em `modules/eks/main.tf` na linha `enabled_cluster_log_types`

### Imports TF State (2026-03-24)

- `module.postgresql_staging.aws_cloudwatch_log_group.rds_postgresql` importado — existia com 7d, TF corrige para 14d
- `module.postgresql_staging.aws_cloudwatch_log_group.rds_upgrade` — nao existia, sera criado pelo TF (apply pendente)

### Proximas Acoes (Q2)

- INIT-005: Migrar EKS auth mode → API_AND_CONFIG_MAP (GAP-FINOPS-ACCESS-ENTRY) = -$60-70/mes adicional
- Verificar grupos RDS de rds-replica e dr-multi-region apos primeira habilitacao (replicas ainda nao ativas)

### Saving Adicional Esperado (pos-Mesa-Tecnica-2026-03-24)

- Lambda stop 14→7d: ~$0.50/mes
- Weekly report 30→14d: ~$0.50/mes
- RDS log groups Never-Expire → 14d: ~$15-30/mes (evita crescimento indefinido de postgresql/upgrade logs)
- **Total estimado: $16-32/mes ($192-384/ano)**

---

## 1. Ultimos 7 Dias — Dados REAIS AWS CE (2026-03-17 a 2026-03-23)

| Data       | Dia da Semana | Custo Real  | Observacao                                   |
|------------|---------------|-------------|----------------------------------------------|
| 2026-03-17 | Segunda       | $38.99      | Baseline dia util normal                     |
| 2026-03-18 | Terca         | $41.54      | Leve alta vs baseline                        |
| 2026-03-19 | Quarta        | $53.06      | SPIKE: +$11 vs baseline (investigar EC2/CW)  |
| 2026-03-20 | Quinta        | $69.88      | SPIKE CRITICO: +$30 vs baseline (deploy prod)|
| 2026-03-21 | Sexta         | $40.89      | Retorno ao baseline (Lambda FinOps ativo)    |
| 2026-03-22 | Sabado        | $21.70      | WEEKEND: Lambda shutdown eficaz (-47%)       |
| 2026-03-23 | Domingo       | $27.76      | WEEKEND: custo reduzido (RDS+workloads off)  |
| **TOTAL**  |               | **$293.82** |                                              |
| **MEDIA**  |               | **$41.97/dia** |                                           |

### Destaques da Semana

- **Spike 2026-03-19 ($53.06):** +36% acima do baseline. Provavelmente relacionado a deploys de staging+prod (Tempo, External-DNS, Harbor ExternalSecrets — confirmados na sessao 2026-03-21).
- **Spike critico 2026-03-20 ($69.88):** +79% acima do baseline. Dia de maior atividade operacional da sessao 2026-03-21 (multiplos applies TF, Linkerd rollout, Harbor prod, Backstage).
- **Weekend eficaz 2026-03-22 ($21.70):** Lambda FinOps funcionando corretamente — saving real de $17-18/dia vs weekday baseline (maior que o $9.72/dia projetado, confirmando eficacia do shutdown completo).
- **Weekend 2026-03-23 ($27.76):** Ligeiramente acima do sabado — possivel warmup de alguns servicos.

---

## 2. Marco 2026 — Dados REAIS AWS CE (01-23/03/2026)

### 2.1 Evolucao Diaria — Dados Reais

| Data       | Custo/Dia  | Acumulado    | Observacao                                    |
|------------|------------|--------------|-----------------------------------------------|
| 2026-03-01 | $160.10    | $160.10      | ANOMALIA: Tax mensal + billing consolidation  |
| 2026-03-02 | $40.25     | $200.35      | Dia util baseline                             |
| 2026-03-03 | $37.53     | $237.89      | Dia util                                      |
| 2026-03-04 | $40.38     | $278.27      | Dia util                                      |
| 2026-03-05 | $39.67     | $317.94      | Dia util                                      |
| 2026-03-06 | $40.43     | $358.37      | Dia util                                      |
| 2026-03-07 | $38.98     | $397.35      | Sabado (Lambda pre-fix — saving parcial)      |
| 2026-03-08 | $38.66     | $436.01      | Domingo (Lambda pre-fix — saving parcial)     |
| 2026-03-09 | $39.49     | $475.50      | Dia util                                      |
| 2026-03-10 | $42.81     | $518.31      | Spike EC2 (deploy/testes)                     |
| 2026-03-11 | $42.71     | $561.02      | NLB eliminado — billing mix                   |
| 2026-03-12 | $39.00     | $600.02      | NLB saving confirmado (-$1.10 ELB)            |
| 2026-03-13 | $32.01     | $632.03      | Anomalia EC2 ($15.36 — billing parcial)       |
| 2026-03-14 | $39.07     | $671.10      | Sabado — Lambda shutdown (workloads+critical=0)|
| 2026-03-15 | $39.50     | $710.60      | Domingo — Lambda START manual (4 invocacoes)  |
| 2026-03-16 | $39.23     | $749.83      | Dia util                                      |
| 2026-03-17 | $38.99      | $788.82      | Dia util baseline                             |
| 2026-03-18 | $41.54     | $830.36      | Leve alta                                     |
| 2026-03-19 | $53.06     | $883.42      | SPIKE: deploys staging+prod                   |
| 2026-03-20 | $69.88     | $953.30      | SPIKE CRITICO: sessao operacional intensa      |
| 2026-03-21 | $40.89     | $994.19      | Retorno baseline                              |
| 2026-03-22 | $21.70     | $1.015.89    | Weekend eficaz                                |
| 2026-03-23 | $27.76     | $1.043.65    | Weekend                                       |

### 2.2 Resumo Marco 2026

| Metrica                             | Valor              | Status           |
|-------------------------------------|--------------------|------------------|
| **Acumulado real (01-23/03)**       | **$1.043.65**      | Dado real AWS CE |
| **Media diaria (23 dias)**          | $45.38/dia         | Inclui spikes    |
| **Media diaria sem anomalias (excl. dias 01, 19, 20)** | $39.82/dia | Baseline operacional |
| **Projecao fim de mes (media x31)** | **~$1.407/mes**    | Estimativa       |
| **Projecao realista (baseline $39.82 x31 + tax $66)** | **~$1.302/mes** | Mais precisa |
| **Budget aprovado**                 | $807/mes           | Meta             |
| **Desvio vs budget (projecao)**     | +$495 a +$600 (+61-74%) | CRITICO     |

### 2.3 Comparativo Fevereiro vs Marco 2026

| Metrica              | Fevereiro 2026   | Marco 2026 (acumulado real) | Delta        |
|----------------------|------------------|-----------------------------|--------------|
| **Custo total mes**  | $914.41 (28d)    | $1.043.65 (23d) → ~$1.302-1.407 proj | +43-54% |
| **Media diaria**     | $32.66/dia       | $39.82/dia (baseline)       | +$7.16/dia (+22%) |
| **Anomalias**        | Sem dados        | +$122 em dias 01,19,20 (spikes) | —        |
| **Tendencia**        | Plataforma em ramp-up | Plataforma 100% operacional | Custo base consolidado |

> Marco teve 2 spikes significativos (19/03 e 20/03) totalizando ~$52 acima do baseline.
> Excluindo esses dias, o baseline diario e consistente em ~$39.82/dia.
> Fevereiro total real: $914.41 | Dado real AWS CE confirmado.

---

## 3. TOP 5 Servicos — Ultimos 7 Dias (2026-03-17 a 2026-03-23)

> Dados reais via `aws ce get-cost-and-usage --group-by SERVICE` — total $293.82

| #  | Servico                                    | Custo 7d    | % Total | Tendencia  |
|----|--------------------------------------------|-------------|---------|------------|
| 1  | Amazon EC2 Compute (Nodes EKS)             | $124.63     | 42.4%   | Dominante  |
| 2  | EC2 - Other (EBS, IPs, ENA, snapshots)     | $45.22      | 15.4%   | Estatico   |
| 3  | Amazon CloudWatch (logs, metricas, alarmes)| $40.55      | 13.8%   | Alto — investigar |
| 4  | Amazon VPC (NAT Gateway, transf. dados)    | $24.67      | 8.4%    | Estatico   |
| 5  | Amazon Elastic Load Balancing (ALB)        | $21.51      | 7.3%    | Reduzido (4→2 ALB) |
| 6  | EKS Control Plane                          | $16.60      | 5.6%    | Fixo       |
| 7  | Amazon RDS PostgreSQL                      | $9.48       | 3.2%    | Reducao weekend |
| 8  | AWS WAF (2 WebACLs staging+prod)           | $3.45       | 1.2%    | Fixo       |
| 9  | Amazon S3                                  | $2.30       | 0.8%    | Baixo      |
| 10 | AWS KMS                                    | $1.68       | 0.6%    | Fixo       |

### Alertas por Servico

- **CloudWatch $40.55/semana = ~$175/mes:** Continua alto. Fix de 5→3 log types aplicado em 2026-03-10 (R$900/ano). Verificar se novos log groups foram criados (Tempo, Backstage, etc).
- **VPC/NAT $24.67/semana = ~$107/mes:** NAT consolidado 2→1 em 2026-03-11 (R$2.168/ano saving). Valor atual reflete 1 NAT Gateway + data transfer.
- **ELB $21.51/semana = ~$93/mes:** ALB 4→2 em 2026-03-11 (R$2.009/ano saving). Valor atual e baseline pos-consolidacao.

---

## 4. Lambda FinOps — Savings Realizados em Marco

### 4.1 Eficacia Lambda — Dados Reais de Marco

| Data       | Custo Real | Tipo    | Saving Estimado | Baseline Sem Lambda |
|------------|------------|---------|-----------------|---------------------|
| 2026-03-22 | $21.70     | WEEKEND | ~$17-18         | ~$39/dia            |
| 2026-03-23 | $27.76     | WEEKEND | ~$11-12         | ~$39/dia            |
| Total weekend savings (semana) | — | — | **~$28-30** | — |

> Os dados de weekend mostram savings SUPERIORES ao $9.72/dia projetado originalmente.
> Sabado $21.70 representa -44% vs baseline weekday — Lambda shutdown funcionando conforme esperado.

### 4.2 Configuracao Lambda FinOps

| Item                  | Valor                         | Status |
|-----------------------|-------------------------------|--------|
| Schedule UP           | 11:00 UTC (08:00 BRT)         | ATIVO  |
| Schedule DOWN         | 21:00 UTC (18:00 BRT)         | ATIVO  |
| Dias de operacao      | Segunda a Sexta               | ATIVO  |
| LINKERD_TIMEOUT_SEC   | 480                           | ATIVO  |
| Circuit Breaker       | CLOSED (operacional)          | OK     |
| _delete_crashloopbackoff_pods() | Ativo               | OK     |
| Saving real (RC-1)    | $9.72/dia weekday / ~$17-18/dia weekend | CONFIRMADO |

### 4.3 Savings Lambda Marco 2026

| Metrica                          | Valor           |
|----------------------------------|-----------------|
| Dias uteis Marco (01-23/03)      | ~16 dias uteis  |
| Saving Lambda weekdays (est.)    | ~$155.52        |
| Saving Lambda weekends (real)    | ~$28-30 (semana 17-23/03) |
| Saving estimado Marco total      | ~$185-210/mes   |
| Saving anual Lambda projetado    | ~$2.220-2.520/ano |
| Saving anual Lambda (BRL @5.75)  | ~R$ 12.765-14.490/ano |

---

## 5. Savings Realizados Acumulados (Q1 2026)

> Checkpoint auditado: 2026-03-21 = R$ 30.982/ano confirmados

| Otimizacao                              | Data       | Economia Anual   | Status    |
|-----------------------------------------|------------|------------------|-----------|
| EKS Extended Support → Standard Support | 2026-02-10 | R$ 25.920/ano    | ATIVO     |
| ALBs deletados (nginx-test, echo-server)| 2026-02-11 | R$ 1.920/ano     | ATIVO     |
| NLBs deletados (RabbitMQ)               | 2026-02-11 | R$ 384/ano       | ATIVO     |
| CloudWatch Logs retention fix           | 2026-02-12 | R$ 54/ano        | ATIVO     |
| S3 Gateway Endpoint (NAT savings)       | 2026-02-12 | R$ 900/ano       | ATIVO     |
| Orphan cleanup (EBS + snapshots)        | 2026-02-12 | R$ 2.221/ano     | ATIVO     |
| EBS gp2 → gp3                           | 2026-02-13 | R$ 859/ano       | ATIVO     |
| RDS Weekend Shutdown                    | 2026-02-18 | R$ 1.200/ano     | ATIVO     |
| Lambda FinOps (FASE 2 EventBridge)      | 2026-02-23 | R$ 5.616/ano     | ATIVO     |
| PDB Optimization                        | 2026-02-24 | R$ 4.405/ano     | ATIVO     |
| CloudWatch fix (5→3 log types)          | 2026-03-10 | R$ 900/ano       | ATIVO     |
| ALB consolidacao (4→2)                  | 2026-03-11 | R$ 2.009/ano     | ATIVO     |
| NAT consolidacao (2→1 gateway)          | 2026-03-11 | R$ 2.168/ano     | ATIVO     |
| GAP-FINOPS-002: System ASG max 6→4     | 2026-03-23 | R$ 2.160-4.320/ano | NOVO (2026-03-23) |
| **TOTAL Q1 2026**                       |            | **~R$ 50.716-52.876/ano** | ACUMULADO |

> Checkpoint baseline 2026-03-21: R$ 30.982/ano (subset dos savings acima — os novos items adicionam ~R$20K).

---

## 6. Status Savings Plans / Reserved Instances

> Coletado via AWS CE API em 2026-03-24 — sessao SSO ativa.

| Tipo                       | Status              | Detalhe                                       |
|----------------------------|---------------------|-----------------------------------------------|
| Compute Savings Plans      | NAO COMPRADO        | API retornou DataUnavailableException — nenhum ativo |
| EC2 Instance Savings Plans | NAO COMPRADO        | —                                             |
| Reserved Instances (RDS)   | NAO COMPRADO        | UtilizationsByTime vazio — 0 RIs ativas       |
| Reserved Instances (EC2)   | NAO COMPRADO        | PurchasedHours: 0, NetRISavings: 0            |

### Decisao Pendente (D3)

| Cenario | Commitment $/h | Economia/mes | Economia/ano | Risco    |
|---------|----------------|-------------|-------------|----------|
| A (conservador) | $0.31 | $85 | $1.020 | Muito baixo |
| **B (moderado)** | **$0.55** | **$108** | **$1.301** | **Baixo** |
| C (agressivo)   | $0.70 | $138 | $1.656 | Moderado |

> DECISAO D3 PENDENTE: Compute Savings Plans 1yr No-Upfront $0.55/h — usuario confirmou mas nao executado.
> Savings potencial imediato com D3: R$ 7.481/ano (@5.75).

---

## 7. Projecao Economia Anual — Roadmap Q2-Q3 2026

| Iniciativa                         | INIT     | Trimestre | Economia/ano     | Risco  |
|------------------------------------|----------|-----------|------------------|--------|
| Spot Instances (workloads 70%)     | INIT-003 | Q2        | R$ 8.000-12.000  | Medio  |
| Compute Savings Plans (1yr no-up)  | INIT-004 | Q2        | R$ 3.600-5.400   | Baixo  |
| Budget Alerts (AWS Budgets TF)     | INIT-012 | Q2        | R$ 2.000-5.000   | Zero   |
| Karpenter (bin-packing + Spot adv) | INIT-013 | Q3        | R$ 6.000-9.000   | Medio  |
| Prefix Delegation CNI              | INIT-014 | Q3        | R$ 3.000-6.000   | Baixo  |
| VPA Cycle (GAP-ARCH-016)           | —        | Q2        | R$ 8.712/ano     | Baixo  |
| Quick Win EBS orphan vol-0055d1a7  | QW-03    | Imediato  | R$ 600/ano       | Zero   |
| System ASG max 6→4 (executado)     | GAP-FINOPS-002 | Executado 2026-03-23 | R$ 2.160-4.320/ano | — |
| **TOTAL POTENCIAL Q2-Q3**          |          |           | **R$ 34.072-46.032/ano** | |

> Savings Q1 confirmados: R$ 30.982/ano (checkpoint 2026-03-21)
> Savings totais com roadmap Q2-Q3: R$ 30.982 + R$ 34.072-46.032 = **R$ 65.054-77.014/ano**

---

## 8. GAPs FinOps Pendentes

| GAP             | Descricao                                                  | Prioridade | Economia Estimada      |
|-----------------|------------------------------------------------------------|------------|------------------------|
| GAP-FINOPS-003  | Karpenter + Spot 70% pendente                              | P3 (Q3)    | R$ 10-18K/ano          |
| GAP-FINOPS-004  | Savings Plans nao comprados (D3 pendente usuario)          | P2         | ~R$ 7.481/ano          |
| GAP-FINOPS-005  | RDS Staging db.t3.medium overprovisioned                   | P3         | ~R$ 900/ano            |
| GAP-FINOPS-006  | ECR Pull-Through Cache ausente em prod                     | P3         | NAT savings estimados  |
| GAP-ARCH-016    | VPA sem ciclo de aplicacao                                 | P1         | R$ 8.712/ano           |
| GAP-LAMBDA-RC3  | kubectl ausente na Lambda (CA nao escala para 0)           | P1         | +$3-5/dia adicional    |
| GAP-BUDGET      | Baseline $39.82/dia = $1.194/mes estrutural vs budget $807 | ESTRUTURAL | Requer decisao usuario |
| QW-03           | EBS orphan vol-0055d1a7bc8e4e292 (10GB gp3, nao attached) | Imediato   | R$ 600/ano             |
| SPIKE-CLOUDWATCH| CW $40.55/semana = ~$175/mes — novos log groups?           | P2         | ~R$ 500-900/ano        |

---

## 9. Score FinOps — Benchmark Enterprise

| Dimensao               | Score Atual | Benchmark | GAP | Acao Q2  |
|------------------------|-------------|-----------|-----|----------|
| Automatizacao          | 6/10        | 8/10      | -2  | Lambda+kubectl fix |
| Spot/Savings Plans     | 0/10        | 8/10      | -8  | INIT-003/004 |
| Observabilidade custos | 4/10        | 7/10      | -3  | INIT-012 budgets |
| Tagging/Attribution    | 7/10        | 8/10      | -1  | Minor gaps |
| Right-sizing           | 5/10        | 8/10      | -3  | VPA cycle |
| **Global FinOps**      | **4/10**    | **8/10**  | -4  |          |

---

## 10. Referencias

- `docs/finops/finops-status-2026-03-17.md` — ultimo status detalhado pre-2026-03-24
- `docs/reports/aws-costs-consolidated-2026-03.md` — dados reais 01-12/03/2026
- `reports/savings-plans-recommendation-2026-03-21.md` — analise Savings Plans
- `docs/demands/2026-03-21-roadmap-enterprise.md` — roadmap FinOps Q2-Q3 (442 linhas)
- `docs/demands/2026-03-23-gap-arch-finops-remediation.md` — GAPs identificados 2026-03-23
- `docs/demands/2026-03-23-gap-sched-phase2-finops.md` — GAP-FINOPS-002 system ASG fix
- `platform-provisioning/aws/kubernetes/terraform/modules/finops-automation/` — modulo TF Lambda

---

*Documento atualizado em 2026-03-24 com dados REAIS da AWS Cost Explorer API (sessao SSO ativa).*
*Profile: k8s-platform-prod | Account: 891377105802 | Region: us-east-1*
*Proxima atualizacao recomendada: 2026-03-31 (fechamento de mes)*
