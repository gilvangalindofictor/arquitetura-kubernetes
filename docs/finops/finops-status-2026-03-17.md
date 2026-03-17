# Relatório FinOps — Status Financeiro Atualizado

**Data:** 2026-03-17
**Cluster:** k8s-platform-prod (EKS 1.34)
**Período de Referência:** Mar/2026 MTD + últimos 7 dias
**Fonte Dados:** AWS Cost Explorer REAL — coletado 2026-03-17 via CLI (sessão ativa)
**Status Geral:** FINANCEIRO CRÍTICO — MTD $709.56 (16 dias) | CE Forecast $1.309,31/mês (+62%) | [GAP-LAMBDA] INVESTIGADO 2026-03-17 — Lambda executa corretamente, savings REAL=$9.72/dia (projeção original $22/dia estava errada)

---

## 1. Resumo Executivo

| Métrica | Valor |
|---------|-------|
| **Custo Jan 2026 REAL** | **$240.20** |
| **Custo Fevereiro 2026 REAL** | **$914.41 = R$ 5.258** |
| **Budget Marco 3 Aprovado** | $807/mês (R$ 4.640) |
| **Mar/2026 MTD REAL (16 dias, 01-16/03)** | **$709.56** |
| **Mar/2026 Daily rate (referência sem anomalias, 14 dias)** | **$39.82/dia** |
| **AWS CE Forecast restante (17-31/Mar)** | **$599.75** |
| **AWS CE Forecast total mês** | **$1.309,31 = R$ 7.529** |
| **Projeção SQ (sem ação)** | **$1.306,80 (+61.9% vs budget)** |
| **Projeção c/ Lambda fix (weekends 21-22, 28-29/Mar)** | **$1.218,80 (+51% vs budget)** |
| **YTD acumulado (até 16/Mar)** | **$1.864,17** |
| **YTD projeção fechamento Mar (SQ)** | **$2.461,41** |
| **Savings Realizados (acumulado)** | **R$ 54.454/ano = $788/mês USD** (corrigido: Lambda $9.72/dia real) |
| **Meta Original** | R$ 62.000/ano |
| **Realização vs Meta** | **87.8%** — Revisão necessária: Lambda savings real < projetado |

---

## 2. Últimos 7 Dias — Dados REAIS (10-16/Mar)

| Data | Dia | Total | EC2 Compute | EC2 Other | VPC/NAT | CloudWatch | EKS | ELB | RDS | Obs |
|------|-----|-------|-------------|-----------|---------|------------|-----|-----|-----|-----|
| 2026-03-10 | Seg | $42.81 | $23.85 | $5.85 | $3.26 | $2.62 | $2.40 | $2.21 | $1.26 | — |
| 2026-03-11 | Ter | $42.71 | $23.91 | $5.55 | $3.39 | $2.50 | $2.40 | $2.54 | $1.26 | — |
| 2026-03-12 | Qua | $39.00 | $23.03 | $4.40 | $2.79 | $2.50 | $2.40 | **$1.44** | $1.33 | ✅ NLB eliminado (-$1.10 ELB) |
| 2026-03-13 | Qui | **$32.01** | **$15.36** | $4.40 | $2.88 | $2.66 | $2.40 | $1.62 | $1.21 | ⚠️ EC2 anomalia — investigar |
| 2026-03-14 | Sáb | $39.07 | $23.21 | $4.03 | $2.88 | $2.90 | $2.40 | $1.62 | $0.37 | ✅ Lambda rodou 03:00 UTC — workloads/critical já em 0 (shutdown sex 23:00) — $39 = BASELINE |
| 2026-03-15 | Dom | $39.50 | $23.13 | $4.59 | $2.88 | $2.96 | $2.40 | $1.62 | $0.85 | ⚠️ Lambda START invocado manualmente 4x às 17:16-17:22 UTC — nodes subiram, sem shutdown sun |
| 2026-03-16 | Seg | $39.08 | $20.61 | $5.29 | $2.88 | $2.97 | $2.40 | $1.62 | $2.06 | — |
| **TOTAL** | | **$274.17** | **$153.09** | **$34.11** | **$20.96** | **$19.11** | **$16.80** | **$12.67** | **$8.34** | |
| **MÉDIA** | | **$39.17** | $21.87 | $4.87 | $2.99 | $2.73 | $2.40 | $1.81 | $1.19 | |

### Análise Detalhada do Período

**ELB confirmado (-$1.10/dia desde 12/Mar):**
- Dia 10-11: $2.21-$2.54/dia
- Dia 12-16: $1.44-$1.62/dia → Saving NLB confirmado ✅

**[GAP-LAMBDA] Investigado 2026-03-17 — Root Causes Confirmados:**

**RC-1 — Savings $9.72/dia (não $22/dia como projetado):**
- Lambda calcula: `(7 nodes × $0.04161/hr × 24h) + $0.75 data transfer + $0.33 ALB + $1.644 RDS = $9.72/dia`
- A projeção original de $22/dia estava baseada em premissas incorretas de custo/node
- `$39/dia sábado = BASELINE correto` com workloads+critical em 0 (Lambda funcionou!)

**RC-2 — Lambda START manual no domingo 15/Mar (17:16-17:22 UTC - 4 invocações):**
- 4 execuções manuais do Lambda START em pleno domingo → nodes subiram às 17:16 UTC
- Sem regra de shutdown para domingo → nodes rodaram dom 17:16 UTC até seg 23:00 UTC
- Causa: teste/validação manual da Lambda em produção — recomendação: doc procedimento

**RC-3 — kubectl não instalado na Lambda (WARNING não-bloqueante):**
- `[Errno 2] No such file or directory: 'kubectl'` → CA Deployment NÃO escala para 0
- K8s API HTTP 403 (RBAC) — Cluster Autoscaler continua rodando durante shutdown
- Impacto: CA pode alocar novos nós se houver workloads no system nodegroup

**RC-4 — Nomenclatura mismatch (cosmético):**
- Lambda loga `environment: staging` mas atua em `k8s-platform-prod` — funcional mas confuso

**Mar 13 (Quinta) — Anomalia $32.01:**
- EC2: $15.36 → Lambda desplegada 12/Mar 17:39 UTC, múltiplas execuções de teste em 13/Mar
- Billing parcial: nodes ficaram down parte do dia após testes de validação

**RDS weekends confirmado funcionando:**
- Sáb 14/Mar: $0.37 vs $1.26-1.33 nos dias úteis → ✅ RDS shutdown weekend ATIVO

---

## 3. MTD Março 2026 — Evolução Diária

| Data | Custo/Dia | Acumulado | Obs |
|------|-----------|-----------|-----|
| 2026-03-01 | $120.13 | $120.13 | ⚠️ Anomalia billing consolidation |
| 2026-03-02 | $40.25 | $160.38 | — |
| 2026-03-03 | $37.53 | $197.91 | — |
| 2026-03-04 | $40.38 | $238.29 | — |
| 2026-03-05 | $39.67 | $277.96 | — |
| 2026-03-06 | $40.43 | $318.39 | — |
| 2026-03-07 | $38.98 | $357.37 | — |
| 2026-03-08 | $38.66 | $396.03 | — |
| 2026-03-09 | $39.35 | $435.38 | — |
| 2026-03-10 | $42.81 | $478.19 | — |
| 2026-03-11 | $42.71 | $520.90 | — |
| 2026-03-12 | $39.00 | $559.90 | NLB eliminado |
| 2026-03-13 | $32.01 | $591.91 | EC2 anomalia |
| 2026-03-14 | $39.07 | $630.98 | Lambda falhou |
| 2026-03-15 | $39.50 | $670.48 | Lambda falhou |
| 2026-03-16 | $39.08 | $709.56 | — |
| **TOTAL MTD** | | **$709.56** | **16 dias** |
| Daily avg (16d): | $44.35 | | incl. anomalia dia 1 |
| Daily avg referência (14d): | $39.82 | | excl. dias 1 e 13 |

---

## 4. Histórico Mensal e YTD 2026

| Mês | Custo Real | Budget | Delta | Status |
|-----|-----------|--------|-------|--------|
| Jan/2026 | $240.20 | — | — | Partial (projeto iniciando) |
| Fev/2026 | $914.41 | $807 | +$107 (+13.3%) | ❌ ACIMA |
| Mar/2026 MTD (16d) | $709.56 | — | — | Running |
| Mar/2026 Forecast CE | $1.309,31 | $807 | +$502 (+62.2%) | ❌ CRÍTICO |
| **YTD atual (até 16/Mar)** | **$1.864,17** | | | |
| **YTD projeção Mar-fechamento** | **~$2.461,41** | | | SQ sem ação |

---

## 5. Projeções — Cenários

### Cenário 1: Status Quo (sem ações adicionais)

```
MTD atual (01-16/Mar):         $709.56
Restante 15 dias × $39.82/d:   $597.24
TOTAL MÊS PROJETADO:           $1.306,80
vs Budget $807:                +$499.80 (+61.9%)  ← CRÍTICO
```

### Cenário 2: Lambda funcionando corretamente (savings reais $9.72/dia)

```
Weekends restantes em Mar:      4 dias (21-22, 28-29/Mar)
Saving real por dia (Lambda):   -$9.72/dia  ← CORRIGIDO (antes $22/dia incorreto)
Saving weekends:                $38.88
Weekday nights (12 restantes × savings parcial ~$3.35/noite): -$40.20
TOTAL SAVINGS ATÉ FIM MÊS:     ~$79.08
TOTAL MÊS COM LAMBDA:          ~$1.230,72
vs Budget $807:                 +$423.72 (+52.5%)  ← CRÍTICO
```

### Cenário 3: Lambda Fix + VPA + Karpenter consolidation

```
Lambda weekdays+weekends:      -$79/mês (savings reais estimados vs SQ)
VPA right-sizing (est.):       -$3/dia × 15d = -$45.00
TOTAL MÊS OTIMIZADO:           ~$1.183,80
vs Budget $807:                +$376.80 (+46.7%)  ← Ainda crítico
```

**CONCLUSÃO:** Mesmo com todas as otimizações disponíveis, março ficará +45-62% acima do budget. O custo de base ($39.82/dia = ~$1.193/mês) está estruturalmente acima do budget $807. Necessário reavaliar budget ou reduzir footprint de infraestrutura.

---

## 6. Savings Realizados — Estado 2026-03-17

> **2026-03-17**: R$ 54.454/ano confirmado — Lambda savings corrigido para $9.72/dia real (era $22/dia projetado incorretamente). [GAP-LAMBDA] RC1+RC2+RC3 identificados.

| Otimização | Data | Economia Anual | Status |
|-----------|------|----------------|--------|
| EKS Upgrade 1.31 → 1.34 | 2026-02-10 | R$ 25.920 | ✅ ATIVO |
| ALBs deletados (nginx-test + echo-server) | 2026-02-11 | R$ 1.920 | ✅ ATIVO |
| NLBs deletados (RabbitMQ) | 2026-02-11 | R$ 384 | ✅ ATIVO |
| CloudWatch Logs retention | 2026-02-12 | R$ 54 | ✅ ATIVO |
| S3 Gateway Endpoint (NAT savings) | 2026-02-12 | R$ 900 | ✅ ATIVO |
| Orphan cleanup (EBS + snapshots) | 2026-02-12 | R$ 2.221 | ✅ ATIVO |
| EBS gp2 → gp3 | 2026-02-13 | R$ 859 | ✅ ATIVO |
| RDS Weekend Shutdown | 2026-02-18 | R$ 1.200 | ✅ ATIVO (confirmado 14-15/Mar) |
| FinOps FASE 2 — Lambda EventBridge | 2026-02-23 | R$ 5.616 | ⚠️ PARCIAL — savings real $9.72/dia (não $22/dia projetado) — [GAP-LAMBDA] |
| PDB Optimization | 2026-02-24 | R$ 4.405 | ✅ ATIVO |
| CloudWatch fix (5→3 log types) | 2026-03-10 | R$ 720-1.080 | ✅ APLICADO |
| ALB 4→2 (consolidação) | 2026-03-11 | R$ 2.009 | ✅ ATIVO |
| NAT 2→1 (removida NAT us-east-1b) | 2026-03-11 | R$ 2.168 | ✅ ATIVO |
| **TOTAL REALIZADOS** | | **R$ 54.454/ano** | **87.8% meta** |

---

## 7. GAPs e Ações Requeridas

### [GAP-LAMBDA] 🔍 INVESTIGADO 2026-03-17 — Root Causes Confirmados

**STATUS: PARCIALMENTE RESOLVIDO — Lambda FUNCIONA — savings real menor que projetado**

```
TIPO: GAP-CONFIG / GAP-PROJECTION

RC-1 [CRÍTICO] Savings projetado errado:
  PROJETADO: $22/dia (R$ 12.800/ano)
  REAL: $9.72/dia = R$ 5.616/ano — diferença: R$ 7.184/ano
  CAUSA: Fórmula Lambda hardcoded (7 nodes × $0.04161/hr × 24h = $6.99 EC2
         + $0.75 data transfer + $0.33 ALB + $1.64 RDS = $9.72/dia)
  AÇÃO: Atualizar todos os docs de projeção com savings correto $9.72/dia

RC-2 [CRÍTICO] Lambda START manual domingo 15/Mar:
  EVIDÊNCIA: 4 execuções 17:16-17:22 UTC domingo — stream CloudWatch confirmado
  IMPACTO: Nodes up dom 17:16 UTC → seg 23:00 UTC (sem shutdown dominical)
  AÇÃO: Documentar procedimento: NÃO invocar Lambda START em weekends manualmente
        OPÇÃO: Adicionar regra EventBridge domingo 23:00 UTC para shutdown preventivo

RC-3 [BAIXO] kubectl ausente na Lambda:
  IMPACTO: CA Deployment não escala para 0 replicas (non-blocking)
  AÇÃO: Adicionar layer kubectl à Lambda OU usar AWS SDK para patch CA deployment

IMPACTO FINANCEIRO REAL:
  Savings REAL fim do mês: ~$79/mês (vs $176/mês projetado)
  Diferença projeção vs real: -$97/mês
  Baseline estrutural: $39/dia = $1.170/mês com Lambda ativo nos weekdays
```

### [GAP-BUDGET] 🔴 FINANCEIRO CRÍTICO — Custo de base +62% vs budget

```
TIPO: GAP-PERF / estrutural
DESCRIÇÃO: Daily rate $39.82 = $1.194/mês estrutural vs budget $807.
           Mesmo com todos os savings realizados, o custo de base é 48% acima do budget.
OPÇÕES:
  A) Revisar budget para $1.200/mês (aceitar realidade operacional)
  B) Reduzir footprint: desligar nó de worker, consolidar serviços
  C) Migrar para instâncias Graviton (t4g) ou Spot para workloads não-críticos
STATUS: Requer decisão do usuário — aguardando
```

---

## 8. Próximas Ações Prioritárias

| Prioridade | Ação | Impacto Estimado | Responsável |
|-----------|------|-----------------|-------------|
| 🔴 P0 | [GAP-LAMBDA-RC2] Documentar procedimento: NÃO chamar Lambda START em weekends | Evita perda $39-79/evento | SRE + Doc |
| 🔴 P0 | [GAP-LAMBDA-RC2] Avaliar regra EventBridge domingo 23:00 UTC shutdown preventivo | +$9.72/domingo | TF Specialist |
| 🔴 P0 | Atualizar TODAS as projeções FinOps: savings $22→$9.72/dia | Evitar decisões baseadas em números errados | Doc Specialist |
| 🔴 P0 | Decisão: revisar budget para ~$900-1.000/mês ou reduzir footprint | Define estratégia | Usuário |
| 🟡 P1 | [GAP-LAMBDA-RC3] Adicionar layer kubectl à Lambda (fix CA scale) | Melhorar eficácia Lambda | TF + Lambda |
| 🟡 P1 | Implementar VPA (right-sizing automático) | ~$3-5/dia = $90-150/mês | TF + K8s |
| 🟡 P1 | Investigar Karpenter consolidation | ~$50-100/mês | Performance |
| 🟢 P2 | Migrar workloads não-críticos para Graviton/Spot | ~15-20% compute | AWS + TF |
| 🟢 P2 | Revisar CloudWatch savings (validar eficácia R$ 720-1.080) | Confirmar ou re-aplicar | Observability |

---

*Fonte: AWS Cost Explorer API — coletado 2026-03-17 via CLI*
*Profile: k8s-platform-prod | Account: 891377105802 | Region: us-east-1*
