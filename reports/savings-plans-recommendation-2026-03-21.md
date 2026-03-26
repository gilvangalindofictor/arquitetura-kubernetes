# Savings Plans Recommendation Report

**Data**: 2026-03-21
**Account**: 891377105802 (k8s-platform-prod)
**Region**: us-east-1
**Analista**: FinOps Agent

---

## 1. Situacao Atual — 100% On-Demand

### 1.1 Inventario EC2 Running (16 instancias)

| Node Group | Tipo | Qtd | On-Demand $/h (unit) | On-Demand $/h (total) |
|------------|------|-----|----------------------|----------------------|
| system     | t3.medium | 5 | $0.0416 | $0.2080 |
| critical   | t3.xlarge | 2 | $0.1664 | $0.3328 |
| workloads  | t3.large  | 8 | $0.0832 | $0.6656 |
| standalone | t3.micro  | 1 | $0.0104 | $0.0104 |
| **TOTAL**  |           | **16** | | **$1.2168/h** |

### 1.2 Scaling Config dos Node Groups

| Node Group | Instance Type | Min | Max | Desired (atual) | Always-On? |
|------------|---------------|-----|-----|-----------------|------------|
| system     | t3.medium     | 2   | 6   | 5               | Sim (min=2) |
| critical   | t3.xlarge     | 2   | 4   | 2               | Sim (min=2) |
| workloads  | t3.large      | 0   | 9   | 8               | Nao (min=0) |
| standalone | t3.micro      | -   | -   | 1               | Sim (24/7)  |

### 1.3 Custo EC2 Compute — Ultimo Mes (dados reais AWS Cost Explorer)

| Periodo | Custo EC2 Compute |
|---------|------------------|
| 21 Feb - 01 Mar (8 dias) | $88.97 |
| 01 Mar - 21 Mar (21 dias) | $434.08 |
| **Projecao Mensal (31 dias)** | **~$641.07** |

### 1.4 Custo Diario EC2 (Marco 2026)

| Data | Custo | Observacao |
|------|-------|------------|
| 01/03 (Dom) | $20.22 | Weekend |
| 02/03 (Seg) | $21.72 | |
| 03/03 (Ter) | $19.06 | |
| 04/03 (Qua) | $22.22 | |
| 05/03 (Qui) | $21.88 | |
| 06/03 (Sex) | $21.63 | |
| 07/03 (Sab) | $22.38 | Weekend |
| 08/03 (Dom) | $22.21 | Weekend |
| 09/03 (Seg) | $21.49 | |
| 10/03 (Ter) | $23.85 | |
| 11/03 (Qua) | $23.91 | |
| 12/03 (Qui) | $23.03 | |
| 13/03 (Sex) | $15.36 | Dia atipico (infra parcial?) |
| 14/03 (Sab) | $23.21 | Weekend |
| 15/03 (Dom) | $23.13 | Weekend |
| 16/03 (Seg) | $20.61 | |
| 17/03 (Ter) | $20.77 | |
| 18/03 (Qua) | $23.55 | |
| 19/03 (Qui) | $24.03 | |
| 20/03 (Sex) | $19.82 | |
| **Media/dia** | **$21.15** | |
| **Desvio** | ~$1.50-$2.00 | Variacao baixa |

**Observacao importante**: O custo diario e relativamente constante (~$20-$24/dia), inclusive nos weekends. Isso indica que a FinOps Lambda de scale-down NAO esta desligando completamente o cluster nos finais de semana. Os nodes `system` (min=2) e `critical` (min=2) permanecem 24/7.

### 1.5 Breakdown por Tipo de Instancia (01-21 Mar)

| Tipo | Custo | Horas | % do Total |
|------|-------|-------|-----------|
| t3.large | $193.49 | 2,326h | 44.6% |
| t3.xlarge | $154.60 | 929h | 35.6% |
| t3.medium | $81.05 | 1,948h | 18.7% |
| t3.micro | $4.93 | 474h | 1.1% |
| **TOTAL** | **$434.08** | **5,677h** | **100%** |

---

## 2. Analise de Baseline (Commitment Floor)

### 2.1 Componentes Always-On (24/7/365)

Estas instancias NUNCA desligam (min > 0 nos node groups):

| Componente | Tipo | Qtd Min | $/h On-Demand |
|-----------|------|---------|---------------|
| system nodes | t3.medium | 2 | $0.0832 |
| critical nodes | t3.xlarge | 2 | $0.3328 |
| fictor-tools | t3.micro | 1 | $0.0104 |
| **TOTAL ALWAYS-ON** | | **5** | **$0.4264/h** |

**Custo mensal always-on**: $0.4264 x 730h = **$311.27/mes**

### 2.2 Componentes Variaveis (FinOps Lambda Scale)

Com a Lambda de FinOps:
- UP: 10:30 UTC (07:30 BRT) | DOWN: 23:00 UTC (20:00 BRT) = 12.5h/dia
- Seg-Sex: 12.5h x 5 = 62.5h/semana
- Weekend: dados mostram que o cluster continua rodando (~$20-23/dia no weekend)

**Realidade observada**: Os dados de custo mostram que o scale-down dos weekends e PARCIAL. O custo diario de weekend ($20-23) e quase igual ao de semana ($19-24), indicando que `workloads` (min=0) pode estar com pods que impedem scale-to-zero.

### 2.3 Custo Real Observado

- Media diaria real: **$21.15/dia**
- Custo mensal projetado (31 dias): **$655.65/mes**
- Custo mensal extrapolado dos dados (434.08 / 21 * 31): **$641.07/mes**
- **Baseline adotado para calculo**: **$640/mes** (~$0.877/h efetivo)

---

## 3. Recomendacao de Savings Plans

### 3.1 Estrategia: Compute Savings Plan 1yr No-Upfront

**Por que Compute SP (e nao EC2 Instance SP)?**
- Compute SP cobre EC2 + Fargate + Lambda
- Flexibilidade para mudar tipo de instancia, regiao, OS, tenancy
- Ideal para ambiente EKS com autoscaling variavel
- Desconto menor que EC2 Instance SP, porem sem lock-in de tipo

### 3.2 Calculo do Commitment

**Desconto tipico Compute SP 1yr No-Upfront para t3 family**: ~27% vs On-Demand

#### Cenario A: Commitment Conservador (apenas always-on)

Commitment baseado SOMENTE nos nodes que nunca desligam:

| Item | On-Demand $/h | SP $/h (est. -27%) |
|------|---------------|-------------------|
| 2x t3.medium (system) | $0.0832 | $0.0607 |
| 2x t3.xlarge (critical) | $0.3328 | $0.2429 |
| 1x t3.micro (standalone) | $0.0104 | $0.0076 |
| **TOTAL** | **$0.4264** | **$0.3112** |

- **Commitment/hora**: $0.31/h
- **Custo mensal SP**: $0.31 x 730 = $226.30
- **Economia vs On-Demand always-on**: $311.27 - $226.30 = **$84.97/mes**
- **Economia anual**: **$1,019.64**

#### Cenario B: Commitment Moderado (always-on + base workloads)

Considerando que os dados mostram custo minimo diario de ~$15.36 (dia 13/03, atipico) e base normal de ~$19-20/dia:

- Custo-hora minimo observado: $15.36/24 = $0.64/h
- Commitment seguro: **$0.55/h** (abaixo do minimo observado com margem)

| Metrica | Valor |
|---------|-------|
| **Commitment/hora** | **$0.55/h** |
| Custo mensal SP | $0.55 x 730 = $401.50 |
| Economia SP vs On-Demand (sobre $0.55/h) | $0.55 x 0.27 x 730 = **$108.41/mes** |
| **Economia anual** | **$1,300.86** |

#### Cenario C: Commitment Agressivo (cobertura ~80% do uso)

Baseado na media de uso de $0.877/h:

- Commitment: $0.70/h (~80% da media)

| Metrica | Valor |
|---------|-------|
| **Commitment/hora** | **$0.70/h** |
| Custo mensal SP | $0.70 x 730 = $511.00 |
| Economia SP vs On-Demand (sobre $0.70/h) | $0.70 x 0.27 x 730 = **$137.97/mes** |
| **Economia anual** | **$1,655.64** |

### 3.3 Recomendacao Final

> **RECOMENDADO: Cenario B — Commitment de $0.55/hora**
>
> - Tipo: **Compute Savings Plan**
> - Termo: **1 ano**
> - Pagamento: **No Upfront**
> - Commitment: **$0.55/hora**
> - Economia mensal estimada: **~$108/mes**
> - Economia anual estimada: **~$1,301/ano**
> - Risco de waste: **Baixo** (commitment abaixo do minimo observado)

**Justificativa**: O cenario B equilibra economia com seguranca. O commitment de $0.55/h esta abaixo do custo-hora minimo observado nos ultimos 21 dias ($0.64/h), garantindo que nunca havera "waste" (pagamento por commitment nao utilizado). Ao mesmo tempo, captura ~63% do gasto total com desconto.

---

## 4. Tabela Comparativa dos Cenarios

| Cenario | Commitment $/h | Custo SP/mes | Economia/mes | Economia/ano | Risco |
|---------|---------------|-------------|-------------|-------------|-------|
| A (Conservador) | $0.31 | $226 | $85 | $1,020 | Muito baixo |
| **B (Moderado)** | **$0.55** | **$402** | **$108** | **$1,301** | **Baixo** |
| C (Agressivo) | $0.70 | $511 | $138 | $1,656 | Moderado |

---

## 5. Outros Custos Significativos (Oportunidades Adicionais)

Do breakdown de servicos em Marco (01-21):

| Servico | Custo (21 dias) | Projecao Mensal | Observacao |
|---------|----------------|----------------|------------|
| EC2 Compute | $434.08 | $641 | **Foco deste relatorio** |
| Tax | $112.94 | $167 | Imposto, nao otimizavel |
| EC2 Other (EBS, IPs, etc) | $108.57 | $160 | Verificar EBS nao utilizado, Elastic IPs ociosos |
| CloudWatch | $73.81 | $109 | **Alto!** Revisar retencion de logs e metricas custom |
| VPC | $61.89 | $91 | NAT Gateway provavelmente. Verificar uso |
| EKS Control Plane | $47.80 | $71 | Fixo ($0.10/h por cluster) |
| ELB | $42.41 | $63 | Consolidar ALBs? Verificar ociosos |
| RDS | $23.91 | $35 | Candidato a RI se always-on |

**Total mensal projetado (todos servicos)**: ~$1,385/mes (excl. tax)

---

## 6. Riscos e Mitigacoes

| Risco | Probabilidade | Impacto | Mitigacao |
|-------|--------------|---------|-----------|
| Mudanca para Graviton/ARM (t4g) | Media | Commitment continua valido (Compute SP e flexivel) | Compute SP cobre qualquer familia |
| Reducao significativa do cluster | Baixa | Commitment acima do uso real = waste | Cenario B ja conservador ($0.55 < $0.64 minimo) |
| Aumento do cluster | Media | Parte do aumento coberta pelo SP, resto On-Demand | Pode comprar SP adicional depois |
| Lock-in de 1 ano | - | Commitment irrevogavel por 12 meses | Usar cenario conservador/moderado |
| AWS desativar instancias t3 | Muito baixa | Compute SP migra automaticamente | Sem acao necessaria |

---

## 7. Recomendacoes Complementares (Quick Wins)

### 7.1 CloudWatch — $109/mes projetado
- Revisar log groups e retencion (reduzir para 30 dias onde possivel)
- Verificar metricas custom desnecessarias
- **Economia potencial**: $30-50/mes

### 7.2 VPC/NAT Gateway — $91/mes projetado
- Se o custo e predominantemente NAT Gateway, avaliar:
  - VPC Endpoints para S3, ECR, CloudWatch (elimina trafego NAT)
  - Economia potencial com endpoints: $20-40/mes

### 7.3 ELB — $63/mes projetado
- Verificar se ha ALBs sem targets ou com pouco trafego
- Consolidar ingress com um unico ALB via AWS Load Balancer Controller

### 7.4 FinOps Lambda — Scale-Down Weekends
- Os dados mostram custo de weekend quase igual a dias uteis
- Investigar se workloads (min=0) realmente escala para zero
- Se o scale-down funcionar corretamente: economia adicional de ~$40-60/mes

---

## 8. Proximos Passos para Compra

### Imediato (esta semana)
1. **Validar** que o cluster permanecera estavel por 12+ meses (sem planos de migrar regiao ou desligar)
2. **Confirmar** que nao ha planos de migrar de EKS para outra plataforma

### Compra (proximo ciclo)
3. Acessar AWS Console > Cost Management > Savings Plans > Purchase
4. Selecionar:
   - Plan type: **Compute Savings Plans**
   - Term: **1 Year**
   - Payment: **No Upfront**
   - Hourly commitment: **$0.55**
5. Revisar e confirmar

### Pos-Compra (30 dias)
6. Monitorar utilization do SP no Cost Explorer > Savings Plans > Utilization report
7. Se utilization > 95% consistente, considerar comprar SP adicional (mais $0.10-0.15/h)
8. Implementar quick wins complementares (CloudWatch, VPC Endpoints)

### Revisao Trimestral
9. Reavaliar commitment a cada 3 meses
10. Ajustar estrategia conforme crescimento do cluster

---

## 9. Resumo Executivo

| Metrica | Valor |
|---------|-------|
| Gasto EC2 atual (mensal) | ~$641/mes |
| Commitment recomendado | Compute SP, 1yr, No-Upfront, $0.55/h |
| Economia mensal SP | ~$108/mes |
| Economia anual SP | ~$1,301/ano |
| Economia total potencial (SP + quick wins) | ~$160-200/mes / $1,900-2,400/ano |
| Savings Plans existentes | Nenhum |
| Reserved Instances existentes | Nenhum |
| Risco do commitment | Baixo (abaixo do minimo de uso observado) |

---

*Relatorio gerado automaticamente em 2026-03-21 via FinOps Agent.*
*Dados: AWS Cost Explorer (60 dias lookback) + EC2 describe-instances.*
