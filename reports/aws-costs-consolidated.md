# Relatório Consolidado de Custos AWS

**Período analisado:** 2026-02-01 → 2026-02-18 (18 dias com dados)
**Conta:** 891377105802 (k8s-platform-prod)
**Gerado em:** 2026-02-19
**Fonte:** AWS Cost Explorer API (`ce:GetCostAndUsage`)

---

## Visão Geral

| Métrica                       | Valor                        |
| ----------------------------- | ---------------------------- |
| **Total MTD (18 dias)**       | **$596.89 USD**              |
| **Média diária**              | **$33.16 USD**               |
| **AWS Forecast (mês)**        | **$745.62 USD**              |
| **Projeção linear (28d)**     | **$928.48 USD**              |
| **Projeção anual (forecast)** | **$8,947.44 USD**            |
| **Dia de pico**               | 2026-02-01 ($108.19)         |
| **Dia de menor custo**        | 2026-02-18 ($11.52)          |
| **Tendência**                 | ✅ Queda -73% (Sem 1 → Sem 3) |

---

## Custos Diários por Serviço (Detalhado)

| Data             |         EKS | EC2 Compute |  EC2 Other |        Tax |    ALB/ELB |        VPC |        RDS | CloudWatch |       KMS |        S3 | Secrets Mgr |   **Total** |
| ---------------- | ----------: | ----------: | ---------: | ---------: | ---------: | ---------: | ---------: | ---------: | --------: | --------: | ----------: | ----------: |
| 2026-02-01       |      $14.40 |      $14.23 |      $4.27 |     $72.55 |      $1.08 |      $0.84 |      $0.41 |          - |     $0.18 |     $0.20 |       $0.03 | **$108.19** |
| 2026-02-02       |      $14.40 |      $15.46 |      $5.03 |          - |      $2.00 |      $1.09 |      $1.20 |          - |     $0.18 |     $0.21 |       $0.04 |  **$39.63** |
| 2026-02-03       |      $14.40 |      $18.95 |      $5.33 |          - |      $3.33 |      $1.79 |      $2.14 |      $0.71 |     $0.21 |     $0.21 |       $0.09 |  **$47.17** |
| 2026-02-04       |      $14.40 |      $19.49 |      $5.79 |          - |      $2.36 |      $1.40 |      $1.97 |      $1.41 |     $0.22 |     $0.20 |       $0.09 |  **$47.35** |
| 2026-02-05       |      $14.40 |      $12.85 |      $5.33 |          - |      $3.24 |      $1.81 |      $1.14 |      $1.72 |     $0.25 |     $0.20 |       $0.09 |  **$41.06** |
| 2026-02-06       |      $14.40 |      $10.15 |      $5.40 |          - |      $3.24 |      $2.17 |      $1.29 |      $1.32 |     $0.23 |     $0.20 |       $0.10 |  **$38.53** |
| 2026-02-07       |      $14.40 |       $0.25 |      $3.63 |          - |      $3.24 |      $2.76 |      $0.41 |      $0.50 |     $0.25 |     $0.20 |       $0.10 |  **$25.74** |
| 2026-02-08       |      $14.40 |       $0.25 |      $3.63 |          - |      $3.24 |      $2.76 |      $0.41 |      $0.50 |     $0.25 |     $0.20 |       $0.10 |  **$25.74** |
| 2026-02-09       |      $14.40 |       $9.91 |      $5.58 |          - |      $4.23 |      $3.16 |      $1.30 |      $1.34 |     $0.25 |     $0.21 |       $0.11 |  **$40.59** |
| 2026-02-10       |       $9.52 |      $10.99 |      $5.15 |          - |      $4.43 |      $3.50 |      $1.30 |      $1.36 |     $0.25 |     $0.22 |       $0.11 |  **$36.97** |
| 2026-02-11       |       $2.40 |       $8.53 |      $4.29 |          - |      $2.32 |      $3.32 |      $1.29 |      $1.34 |     $0.25 |     $0.21 |       $0.11 |  **$24.13** |
| 2026-02-12       |       $2.40 |      $10.04 |      $4.42 |          - |      $2.81 |      $3.53 |      $1.29 |      $1.48 |     $0.25 |     $0.20 |       $0.11 |  **$26.61** |
| 2026-02-13       |       $2.40 |      $13.05 |      $3.97 |          - |      $3.15 |      $3.66 |      $1.30 |      $1.70 |     $0.25 |     $0.20 |       $0.12 |  **$29.87** |
| 2026-02-14       |       $2.40 |       $0.25 |      $2.56 |          - |      $2.16 |      $3.24 |      $0.41 |      $0.53 |     $0.25 |     $0.20 |       $0.11 |  **$12.11** |
| 2026-02-15       |       $2.40 |       $0.25 |      $2.56 |          - |      $2.16 |      $3.24 |      $0.41 |      $0.53 |     $0.25 |     $0.20 |       $0.11 |  **$12.11** |
| 2026-02-16       |       $2.40 |       $2.96 |      $3.04 |          - |      $2.16 |      $3.25 |      $0.68 |      $0.76 |     $0.25 |     $0.20 |       $0.11 |  **$15.83** |
| 2026-02-17       |       $2.40 |       $1.28 |      $2.90 |          - |      $2.16 |      $3.24 |      $0.51 |      $0.65 |     $0.25 |     $0.20 |       $0.11 |  **$13.72** |
| 2026-02-18       |       $1.60 |       $2.75 |      $2.04 |          - |      $1.44 |      $1.98 |      $0.58 |      $0.69 |     $0.15 |     $0.21 |       $0.08 |  **$11.52** |
| **TOTAL MTD**    | **$157.52** | **$151.63** | **$74.91** | **$72.55** | **$48.76** | **$46.72** | **$18.05** | **$16.52** | **$4.16** | **$3.67** |   **$1.73** | **$596.89** |
| **Projeção 28d** |     $245.03 |     $235.87 |    $116.53 |    $112.86 |     $75.85 |     $72.68 |     $28.07 |     $25.70 |     $6.47 |     $5.71 |       $2.69 |     $928.48 |

---

## Resumo por Serviço

| Serviço                 |   Total MTD |  % Total |  Média/Dia | Projeção Mensal (28d) | Projeção Anual | Status                  |
| ----------------------- | ----------: | -------: | ---------: | --------------------: | -------------: | ----------------------- |
| EKS Control Plane       |     $157.52 |    26.4% |      $8.75 |               $245.03 |      $2,940.34 | ✅ Esperado              |
| EC2 Compute (Nodes)     |     $151.63 |    25.4% |      $8.42 |               $235.87 |      $2,830.38 | ✅ Shutdown efetivo      |
| EC2 Other (EBS/NAT/IPs) |      $74.91 |    12.6% |      $4.16 |               $116.53 |      $1,398.31 | ✅ NAT fixo              |
| Tax                     |      $72.55 |    12.2% |      $4.03 |               $112.86 |      $1,354.27 | - Imposto               |
| ALB/ELB                 |      $48.76 |     8.2% |      $2.71 |                $75.85 |        $910.24 | ⚠️ Verificar ALBs ativos |
| VPC (Endpoints+NAT)     |      $46.72 |     7.8% |      $2.60 |                $72.68 |        $872.18 | ⚠️ +149% vs doc          |
| RDS PostgreSQL          |      $18.05 |     3.0% |      $1.00 |                $28.07 |        $336.87 | ✅ Shutdown efetivo      |
| CloudWatch              |      $16.52 |     2.8% |      $0.92 |                $25.70 |        $308.41 | ⚠️ +150% vs doc          |
| KMS                     |       $4.16 |     0.7% |      $0.23 |                 $6.47 |         $77.61 | ✅ 3 keys ativas         |
| S3                      |       $3.67 |     0.6% |      $0.20 |                 $5.71 |         $68.50 | ✅ Estável               |
| Secrets Manager         |       $1.73 |     0.3% |      $0.10 |                 $2.69 |         $32.27 | ✅ Esperado              |
| Cost Explorer           |       $0.34 |     0.1% |      $0.02 |                 $0.53 |          $6.35 | ✅ API queries           |
| ECS/ECR/DynamoDB/Outros |       $0.32 |     0.1% |      $0.02 |                 $0.50 |          $5.94 | ✅ Negligível            |
| **TOTAL**               | **$596.88** | **100%** | **$33.16** |           **$928.47** | **$11,141.64** |                         |

**AWS ML Forecast:** **$745.62/mês** ($8,947.44/ano) — leva em conta a tendência de queda

---

## Tendência Diária

```
Fev 01: $108.19 ████████████████████████████████████████████ (deploy burst + Tax)
Fev 02: $ 39.64 ████████████████
Fev 03: $ 47.17 ███████████████████
Fev 04: $ 47.36 ███████████████████
Fev 05: $ 41.06 ████████████████
Fev 06: $ 38.53 ███████████████
Fev 07: $ 25.74 ██████████           ← sábado (shutdown)
Fev 08: $ 25.74 ██████████           ← domingo (shutdown)
Fev 09: $ 40.59 ████████████████
Fev 10: $ 36.97 ██████████████       ← Sprint 2 FinOps Wave
Fev 11: $ 24.13 █████████            ← ALBs deletados
Fev 12: $ 26.61 ██████████
Fev 13: $ 29.87 ████████████
Fev 14: $ 12.11 █████                ← sexta → shutdown weekend
Fev 15: $ 12.11 █████                ← sábado
Fev 16: $ 15.83 ██████               ← domingo
Fev 17: $ 13.72 █████
Fev 18: $ 11.52 ████                 ← custo mínimo atingido
```

### Análise Semanal

| Semana    | Período     | Custo Total |  Média/Dia | Eventos                                        |
| --------- | ----------- | ----------: | ---------: | ---------------------------------------------- |
| Semana 1  | Fev 01-07   |     $347.69 |     $49.67 | Deploy Marco 3, 7 nodes ativos, ALBs GitLab    |
| Semana 2  | Fev 08-13   |     $183.01 |     $30.50 | Sprint 2 FinOps, ALBs deletados, EBS migration |
| Semana 3  | Fev 14-18   |      $65.29 |     $13.06 | Custo estabilizado pós-otimizações             |
| **Total** | **18 dias** | **$596.88** | **$33.16** | **Redução -73% (Sem 1→Sem 3)**                 |

---

## Comparação Janeiro vs Fevereiro 2026

| Serviço             | Jan 2026 (full) | Fev MTD (18d) | Fev Forecast | Delta Jan→Fev | Motivo                                       |
| ------------------- | --------------: | ------------: | -----------: | ------------- | -------------------------------------------- |
| EKS Control Plane   |          $52.86 |       $157.52 |      $245.04 | +363%         | Jan cluster parcialmente desligado           |
| EC2 Compute         |          $55.86 |       $151.63 |      $235.87 | +322%         | Fev com 7 nodes ativos (scaling progressivo) |
| EC2 Other (EBS/NAT) |          $76.77 |        $74.91 |      $116.56 | +52%          | NAT fixo + EBS volumes adicionais            |
| ELB                 |           $3.24 |        $48.76 |       $75.85 | +2241%        | GitLab ALBs + IngressGroup (Fev)             |
| VPC                 |          $12.68 |        $46.72 |       $72.68 | +473%         | 3 VPC Endpoints adicionados (STS, EC2, KMS)  |
| RDS                 |           $2.50 |        $18.05 |       $28.08 | +1023%        | PostgreSQL RDS ativo full (Marco 3)          |
| CloudWatch          |           $0.32 |        $16.52 |       $25.70 | +7931%        | Logs + custom metrics observability          |
| S3                  |           $5.53 |         $3.67 |        $5.71 | +3%           | Estável                                      |
| Tax                 |          $29.18 |        $72.55 |      $112.86 | +287%         | Proporcional ao aumento de serviços          |
| **TOTAL**           |     **$240.20** |   **$596.88** |  **$745.62** | **+210%**     | Plataforma expandida (Marco 3)               |

---

## Análise de Padrão Dia da Semana

| Dia                       |                                    Custo Médio | Observação                         |
| ------------------------- | ---------------------------------------------: | ---------------------------------- |
| Segunda-Quinta (workdays) | $30-47 (Sem 1), $24-30 (Sem 2), $12-16 (Sem 3) | Nodes ativos, workloads running    |
| Sexta                     |               $38.53 (Fev 06), $12.11 (Fev 14) | Shutdown FinOps 20h BRT            |
| Sábado                    |               $25.74 (Fev 07), $12.11 (Fev 15) | Custos fixos apenas (EKS+NAT+VPCE) |
| Domingo                   |               $25.74 (Fev 08), $15.83 (Fev 16) | Custos fixos apenas                |

**Custo fixo diário (infraestrutura always-on):** ~$11-12/dia
- EKS Control Plane: ~$2.40/dia (pós Fev 11) ou ~$14.40/dia (com Extended Support)
- VPC Endpoints+NAT: ~$3.24/dia
- EBS Volumes: ~$2.50/dia
- ALB hour charges: ~$2.16/dia

---

## Detalhamento EC2 Compute (Padrão Shutdown)

| Data                | EC2 Compute | Observação                                   |
| ------------------- | ----------: | -------------------------------------------- |
| Fev 01-06 (seg-sex) |  $10-19/dia | Nodes ativos (7× t3.medium/t3.xlarge)        |
| Fev 07-08 (sáb-dom) |   $0.25/dia | ✅ Shutdown efetivo (ASG scale to 0)          |
| Fev 09-13 (seg-sex) |   $8-13/dia | Nodes ativos (menos que Sem 1 — otimizações) |
| Fev 14-15 (sex-sáb) |   $0.25/dia | ✅ Shutdown efetivo                           |
| Fev 16-17 (dom-seg) |    $1-3/dia | Startup parcial ou mínimo                    |
| Fev 18 (ter)        |   $2.75/dia | Dia parcial                                  |

**Economia observada shutdown:** EC2 cai de ~$15/dia para ~$0.25/dia nos weekends = **~$14.75/dia economizado**

---

## Detalhamento EKS (Mudança de Pricing)

| Período   |    EKS/Dia | Observação                            |
| --------- | ---------: | ------------------------------------- |
| Fev 01-09 | $14.40/dia | EKS Extended Support ativo ($0.60/hr) |
| Fev 10    |  $9.52/dia | Transição de pricing                  |
| Fev 11-17 |  $2.40/dia | EKS Standard Support ($0.10/hr)       |
| Fev 18    |  $1.60/dia | Dia parcial                           |

**Impacto:** Mudança de Extended Support → Standard Support reduziu EKS de $14.40 para $2.40/dia = **-$12/dia = -$360/mês**

---

## Forecast — Estimativa até Fim do Mês

### Cenário 1: AWS ML Forecast

| Métrica              | Valor       |
| -------------------- | ----------- |
| **Total Fev 2026**   | **$745.62** |
| Restante (10 dias)   | ~$148.74    |
| Custo médio restante | ~$14.87/dia |

### Cenário 2: Projeção Linear (média 18 dias)

| Métrica              | Valor       |
| -------------------- | ----------- |
| **Total Fev 2026**   | **$928.47** |
| Restante (10 dias)   | ~$331.59    |
| Custo médio restante | ~$33.16/dia |

### Cenário 3: Projeção Semana 3 (custo estabilizado)

| Métrica              | Valor                             |
| -------------------- | --------------------------------- |
| **Total Fev 2026**   | **$727.48**                       |
| Restante (10 dias)   | ~$130.60                          |
| Custo médio restante | ~$13.06/dia                       |
| Melhor cenário       | Baseado no padrão pós-otimizações |

**Cenário mais provável:** AWS Forecast ($745.62) — leva em conta a tendência decrescente e é consistente com o custo estabilizado da Semana 3.

---

## Cenário: Shutdown de Fins de Semana (Projeção 19–28 Fev)

Aplicando shutdown parcial nos finais de semana (custo reduzido a $12.11/dia) e mantendo a média histórica de dias úteis (~$31.77/dia) para os dias úteis, a projeção para 19–28 Fev é a seguinte:

- **Soma projetada (19–28 Fev):** **$258.72 USD**
- **Projeção total Fev (1–28) com shutdown:** **$855.61 USD**
- **Economia estimada vs projeção sem shutdown:** **$74.01 USD**

Daily projection (19–28 Feb):

| Data       | Projeção (USD) |
| ---------- | -------------: |
| 2026-02-19 |         $31.77 |
| 2026-02-20 |         $31.77 |
| 2026-02-21 |         $12.11 |
| 2026-02-22 |         $12.11 |
| 2026-02-23 |         $31.77 |
| 2026-02-24 |         $31.77 |
| 2026-02-25 |         $31.77 |
| 2026-02-26 |         $31.77 |
| 2026-02-27 |         $31.77 |
| 2026-02-28 |         $12.11 |

CSV com a projeção diária: [reports/aws-costs-projection-shutdown.csv](reports/aws-costs-projection-shutdown.csv)


## Alertas e Observações

### ⚠️ Items que Requerem Atenção

1. **VPC Endpoints ($72/mês projetado vs $28.90 documentado)** — O custo VPC inclui NAT Gateway + 3 VPC Interface Endpoints. Custo acima do documentado em +149%. Considerar: VPCE KMS foi adicionado em fev, atualizar documentação.

2. **CloudWatch ($25/mês projetado vs ~$10 documentado)** — Aumento de +150%. Verificar log retention policies e custom metrics. Ação: revisar CloudWatch Logs Insights usage e data ingestion.

3. **EKS Extended Support depreciation** — Custo EKS caiu de $14.40/dia para $2.40/dia a partir de 10-Fev. Confirmar que esta mudança é permanente e reflete no forecast.

4. **Tax ($72.55 lançado dia 01)** — Todo o imposto do mês lançado no primeiro dia. Custo "real" do dia 01 sem tax: $35.64.

### ✅ Items Positivos

1. **Economia shutdown confirmada** — EC2 cai de ~$15/dia para $0.25/dia nos weekends
2. **Tendência de queda -73%** — Custo estabilizado em ~$13/dia na Semana 3
3. **Forecast alinhado** — AWS Forecast $745.62 vs documentado $752.80 (-0.95%)
4. **FinOps Sprint 2 efetivo** — ALBs deletados visíveis no custo a partir de Fev 11

---

## Ações Recomendadas

1. **Investigar CloudWatch Logs** — $25/mês projetado é +150% do esperado. Verificar retention policies e data ingestion volume.
2. **Atualizar documentação VPC** — Incluir VPCE KMS no custo documentado ($72/mês total VPC vs $28.90).
3. **Confirmar EKS pricing** — Validar transição Extended → Standard Support como permanente.
4. **Criar AWS Budget** — Threshold $750/mês com alerta 80% ($600) e 100% ($750).
5. **Monitorar Semana 4 (19-28 Fev)** — Confirmar estabilização ~$13/dia.

---

## Arquivos de Referência

| Arquivo                         | Descrição                   |
| ------------------------------- | --------------------------- |
| `reports/aws-costs.json`        | Raw JSON — MTD por serviço  |
| `reports/aws-costs-daily.csv`   | CSV custos diários          |
| `docs/context/costs.md`         | Análise FinOps completa     |
| `docs/context/current_state.md` | Estado atual (seção FinOps) |

---

Relatório gerado via AWS Cost Explorer API em 2026-02-19.
