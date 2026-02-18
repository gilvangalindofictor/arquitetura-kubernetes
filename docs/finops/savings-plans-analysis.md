# Análise: Compute Savings Plans + RDS Reserved Instances — Staging vs Produção

**Data:** 2026-02-18
**Cluster:** k8s-platform-prod (staging)
**Autor:** FinOps Team
**Status:** ⚠️ FINDING CRÍTICO — Recomendação diverge do savings-calculator.md

---

## 🔑 Sumário Executivo

A análise quantitativa usando dados reais do AWS Cost Explorer (Feb 2026) revelou que
**Compute Savings Plans e RDS Reserved Instances NÃO são viáveis para o cluster de staging
enquanto o Lambda de weekend shutdown estiver ativo**.

O motivo: SP/RI cobram por hora comprometida 24/7. O weekend shutdown reduz a utilização EC2
para ~$0.25/dia nos fins de semana. Qualquer compromisso SP/RI acima de $0.02/hr gera prejuízo.

---

## 📊 Dados Reais (AWS Cost Explorer — Semana Normal Feb 9–15)

### EC2 Compute Costs

| Dia | Data | EC2 Compute (USD) |
|-----|------|-------------------|
| Segunda | Feb 09 | $9.91 |
| Terça | Feb 10 | $10.99 |
| Quarta | Feb 11 | $8.53 |
| Quinta | Feb 12 | $10.04 |
| Sexta | Feb 13 | $13.05 |
| **Sábado** | Feb 14 | **$0.25** ← shutdown |
| **Domingo** | Feb 15 | **$0.25** ← shutdown |
| **Total semana** | | **$53.02** |

### RDS PostgreSQL Costs

| Período | Custo Diário |
|---------|-------------|
| Dias úteis (running) | ~$1.29/dia |
| Fim de semana (stopped) | ~$0.41/dia (storage apenas) |

### Projeção Mensal Real

| Serviço | Mensal (estimado) | Anual | Vs. Calculadora (24/7) |
|---------|-------------------|-------|------------------------|
| EC2 Compute | $233/mês | $2,796/ano | -54% |
| RDS Compute | $31.66/mês | $380/ano | -74% |

> **Nota:** A calculadora original assumia utilização 24/7. O weekend shutdown reduz
> significativamente a utilização real.

---

## ❌ Por Que SP/RI NÃO Funcionam com Weekend Shutdown

### Mechanics Savings Plans

Um Compute Savings Plan compromete $X/hr **cobrado 24/7 independente do uso**.
- Durante a semana ativa (10h/dia): SP gera desconto de 26%
- Nas 14h noturnas (apenas system nodes): SP gera 70% de desperdício
- No fim de semana ($0.0104/hr apenas): SP gera >95% de desperdício

### Simulação por Nível de Commitment (semana típica)

| Commitment | SP/semana | OD restante | Total c/ SP | Total sem SP | Economia |
|-----------|-----------|-------------|-------------|--------------|----------|
| $0.02/hr | $3.36 | $40.02 | $43.38 | $43.76 | **+$0.38/sem** ✅ |
| $0.05/hr | $8.40 | $35.16 | $43.56 | $43.76 | **+$0.21/sem** ✅ |
| **$0.10/hr** | $16.80 | $30.68 | $47.48 | $43.76 | **-$3.72/sem ❌** |
| $0.15/hr | $25.20 | $27.30 | $52.50 | $43.76 | -$8.74/sem ❌ |
| $0.20/hr | $33.60 | $23.93 | $57.53 | $43.76 | -$13.76/sem ❌ |
| $0.30/hr | $50.40 | $17.17 | $67.57 | $43.76 | -$23.81/sem ❌ |

**Máximo savings viáveis com SP (commitment $0.02/hr):** $0.38/sem → **R$ 119/ano**
(vs. R$ 5.616/ano projetado na calculadora — 97% abaixo)

### Por Que a Calculadora Estava Errada

A `savings-calculator.md` foi escrita assumindo utilização 24/7 ($607.49/mês EC2).
A realidade do cluster staging com weekend shutdown é $233/mês EC2 (-62%).

O Weekend Shutdown Lambda **já captura o saving**. SP/RI tentaria capturar o mesmo
saving de uma maneira diferente — mas são **estratégias mutuamente exclusivas**:

```
Comparação para EC2 (staging):
  Opção A (atual): Weekend Shutdown → salva $374/mês vs 24/7 → R$ 26.928/ano
  Opção B: Remover shutdown + Compute SP 26% off → salva $157.95/mês → R$ 11.372/ano

  Opção A é 2.4x MELHOR que Opção B para staging.
```

---

## ✅ Quando SP/RI SÃO Viáveis

### 1. Cluster de Produção (futuro deployment)

Se o cluster de produção rodar 24/7 (sem weekend shutdown):
- EC2 Compute estimate: $607/mês (baseline)
- Compute SP 1yr no-upfront (26% off): **$157.82/mês → $1.894/ano → R$ 11.363/ano**
- RDS RI 1yr no-upfront (35% off): **$42/mês → $504/ano → R$ 3.024/ano**
- **Total SP+RI produção: R$ 14.387/ano (ROI 2.398%)**

**Ação:** Ao fazer o deploy do cluster de produção, comprar SP/RI imediatamente.

### 2. Staging sem Shutdown (caso de uso 24/7)

Se o staging for promovido para operação contínua (ex: ambiente de demo):
- Remover Lambda de shutdown → compute sobe de $233/mês para $607/mês
- Comprar Compute SP → recupera $157/mês
- Net: pagaria $450/mês vs atual $233/mês → NÃO RECOMENDADO para staging

### 3. EC2 Savings Plans para Workloads Específicos

Qualquer workload **que rode 24/7 no cluster de staging** pode se beneficiar:
- Atualmente: apenas t3.micro non-EKS ($0.0104/hr, sempre-on)
- SP para esse host: savings mínimos (~R$ 50/yr) — não compensa overhead

---

## 📋 Impacto no Roadmap FinOps

### Atualizações à savings-calculator.md (Linha 8)

| Campo | Antes | Depois (Correto) |
|-------|-------|-----------------|
| Compute SP savings/mês | $78/mês | ~$1.65/mês (**staging**) |
| Economia anual | $936/ano (R$ 5.616) | ~$19/ano (R$ 119) — **staging** |
| Economia anual | N/A | R$ 14.387/ano — **produção** |
| Prazo | P1 (1 semana) | P3 (**produção apenas**, post-Marco 3) |

### Nova Priorização das Iniciativas Medium/Strategic

| Rank | Iniciativa | Saving | Viabilidade Atual |
|------|-----------|--------|-------------------|
| 1 | **RDS RI 1yr** | R$ 3.024/yr (produção) | P3: post-Marco 3 |
| 2 | **Compute SP 1yr** | R$ 11.363/yr (produção) | P3: post-Marco 3 |
| 3 | **Karpenter + Spot 70%** | R$ 10.200/yr | P2: staging cluster ok |
| 4 | **Graviton ARM64** | R$ 6.984/yr | P2: após rightsizing VPA |
| 5 | VPA Rightsizing | R$ 8.712/yr | Coleta 30d em progresso |

---

## 🎯 Recomendação Final

### Para Staging (Hoje)
1. ✅ **Manter Weekend Shutdown Lambda** — R$ 4.944/yr savings (já realizados)
2. ❌ **NÃO comprar Compute SP ou RDS RI para staging**
3. ⬛ **Próximo foco EC2**: Karpenter + Spot Instances (P2, R$ 10.200/yr)

### Para Produção (Marco 3+)
1. 🕐 **Assim que produção for deployed, comprar imediatamente:**
   - Compute Savings Plans 1yr No-Upfront: ~$157/mês (R$ 11.363/yr)
   - RDS Reserved Instance 1yr No-Upfront: ~$42/mês (R$ 3.024/yr)
   - **Commitment recomendado**: $0.40/hr Compute SP (cobre fleet de produção ~80%)

### Passos Concretos (Produção — Post Marco 3)

```bash
# 1. Validar utilização 30 dias (Cost Explorer)
aws ce get-savings-plans-purchase-recommendation \
  --savings-plans-type COMPUTE_SP \
  --term-in-years ONE_YEAR \
  --payment-option NO_UPFRONT \
  --lookback-period-in-days THIRTY_DAYS

# 2. Comprar Compute Savings Plan via Console
# AWS Console → Cost Management → Savings Plans → Purchase Savings Plans
# Type: Compute Savings Plans
# Term: 1 year
# Payment: No upfront
# Hourly commitment: $0.40/hr (validate with recommender)

# 3. RDS Reserved Instance via Console
# RDS Console → Reserved Instances → Purchase Reserved DB Instances
# DB Instance Class: db.t3.medium
# Duration: 1 year
# Offering Type: No Upfront
```

---

## 📈 Projeção Corrigida de Savings

### Staging (atual, 2026)

| Categoria | Savings Realizados | Savings Pendentes Viáveis |
|-----------|-------------------|---------------------------|
| EKS Upgrade 1.34 | R$ 25.920 ✅ | - |
| Weekend Shutdown | R$ 4.944 ✅ | - |
| EBS gp3 | R$ 816 ✅ | - |
| Orphan cleanup | R$ 3.106 ✅ | - |
| Compute SP | R$ 0 | R$ 119 (não recomendado) |
| RDS RI | R$ 0 | R$ 377 (marginal) |
| **Karpenter + Spot** | R$ 0 | **R$ 10.200** ← próximo P2 |
| **VPA Rightsizing** | pendente 30d | **R$ 8.712** |
| **Graviton** | R$ 0 | **R$ 6.984** ← pós VPA |

### Produção (post-Marco 3, estimativa)

| Categoria | Savings Estimados |
|-----------|------------------|
| Compute SP 1yr | R$ 11.363/yr |
| RDS RI 1yr | R$ 3.024/yr |
| Compute SP + RDS RI combinado | **R$ 14.387/yr** |

---

**Última Atualização:** 2026-02-18
**Owner:** FinOps Team
**Referências:**
- [savings-calculator.md](savings-calculator.md) — calculadora original (premissa 24/7)
- AWS Cost Explorer: cluster k8s-platform-prod, us-east-1
- Logbook [2026-02-18-p1-security-finops.md](../logbook/2026-02-18-p1-security-finops.md)
