# FinOps: Estratégia de Startup/Shutdown - Análise de Economia de Custos

**Data:** 2026-01-29
**Versão:** 1.0
**Autor:** FinOps Specialist + Cloud Architect
**Contexto:** Marco 2 Completo (Fase 8), Projeção Marco 3

---

## 📊 Executive Summary

| Métrica | Valor |
|---------|-------|
| **Custo Base Marco 2** | $685.70/mês (24/7) |
| **Economia Dev (8h/dia útil)** | **$368.96/mês (53.8%)** |
| **Economia Prod (10h/dia útil)** | **$333.52/mês (48.6%)** |
| **Economia Prod Ext (12h/dia útil)** | **$298.09/mês (43.5%)** |
| **ROI Automação** | Payback < 1 mês |

**Recomendação Estratégica:**
✅ **Start/Stop é ALTAMENTE RECOMENDADO** para todos cenários. Economia anual de $3.576 a $4.428 (43-54% do budget).

---

## 🧮 1. Breakdown: Custos Fixos vs Variáveis

### 1.1 Custos FIXOS (Não podem ser desligados)

| Componente | Detalhes | Custo/Mês | Custo/Ano | Motivo Fixo |
|------------|----------|-----------|-----------|-------------|
| **EKS Control Plane** | Managed K8s | $73.00 | $876.00 | Serviço gerenciado 24/7 |
| **S3 Storage** | Loki (500GB) + Tempo (500GB) | $23.00 | $276.00 | Storage retention |
| **S3 Requests** | PUT/GET APIs | $5.50 | $66.00 | Background jobs |
| **DynamoDB State Lock** | Terraform backend | $0.25 | $3.00 | State management |
| **NAT Gateways** | 2 AZs (baseline) | $65.70 | $788.40 | Network egress |
| **Route53** | Hosted zone | $0.50 | $6.00 | DNS resolution |
| **Secrets Manager** | 1 secret | $0.40 | $4.80 | Grafana password |
| **ALBs Inativos** | Sem tráfego quando nodes off | $32.40 | $388.80 | Hour charges (LCU=0) |
| **SUBTOTAL FIXO** | | **$200.75** | **$2.409.00** | **29.3% do custo total** |

**Observação:**
- NAT Gateways: Cobram por hora mesmo sem tráfego ($32.85/mês cada)
- ALBs: Cobram $16.20/mês por hora + LCU (quando nodes off, LCU vai pra 0 mas hour charge persiste)
- S3 Storage: Cobrado por GB armazenado, independente de acesso

---

### 1.2 Custos VARIÁVEIS (Podem ser desligados)

| Componente | Especificação | Qtd | Custo Unitário | Custo/Mês (24/7) | Custo/Ano |
|------------|---------------|-----|----------------|------------------|-----------|
| **EC2 Nodes - System** | t3.medium | 2 | $30.37 | $60.74 | $728.88 |
| **EC2 Nodes - Workloads** | t3.medium | 3 | $30.37 | $91.11 | $1.093.32 |
| **EC2 Nodes - Critical** | t3.medium | 2 | $30.37 | $60.74 | $728.88 |
| **EBS Volumes (Root)** | gp3 50GB | 7 nodes | $4.00 | $28.00 | $336.00 |
| **EBS PVCs Platform** | Prometheus, Grafana, Loki, Tempo | - | - | $8.96 | $107.52 |
| **Data Transfer NAT** | ~500GB/mês egress | - | $0.045/GB | $22.50 | $270.00 |
| **ALB LCU Charges** | Active traffic | 2 ALBs | $5.00 | $10.00 | $120.00 |
| **SUBTOTAL VARIÁVEL** | | | | **$282.05** | **$3.384.60** |
| | | | | | |
| **Data Transfer (Reduzido)** | ~100GB quando off | - | $0.045/GB | $4.50 | $54.00 |
| **EBS quando nodes off** | Storage persiste | - | - | $36.96 | $443.52 |
| **SUBTOTAL quando OFF** | | | | **$41.46** | **$497.52** |

**Economia potencial MÁXIMA (nodes off):** $282.05 - $41.46 = **$240.59/mês**

---

### 1.3 Breakdown por Categoria (Marco 2 Base: $685.70/mês)

| Categoria | Componentes | Custo/Mês | Variável? | % Total |
|-----------|-------------|-----------|-----------|---------|
| **Compute (Nodes)** | 7 EC2 t3.medium | $212.59 | ✅ SIM | 31.0% |
| **Compute (Control)** | EKS Control Plane | $73.00 | ❌ NÃO | 10.6% |
| **Storage (EBS)** | Root volumes + PVCs | $36.96 | ⚠️ PARCIAL | 5.4% |
| **Storage (S3)** | Loki + Tempo + Requests | $28.50 | ❌ NÃO | 4.2% |
| **Networking (NAT)** | 2 NAT GWs + Data Transfer | $88.20 | ⚠️ PARCIAL | 12.9% |
| **Networking (ALB)** | 2 ALBs test apps | $42.40 | ⚠️ PARCIAL | 6.2% |
| **Platform Services** | Secrets, DynamoDB, Route53 | $1.15 | ❌ NÃO | 0.2% |
| **Outros** | Reserved/misc | $202.90 | ❌ NÃO | 29.6% |
| **TOTAL MARCO 2** | | **$685.70** | | **100%** |

**Legenda:**
- ✅ **Variável SIM:** Economia total quando desligado
- ❌ **Fixo NÃO:** Sempre cobra mesmo desligado
- ⚠️ **Parcial:** EBS persiste (storage), NAT reduz data transfer, ALB elimina LCU

---

## 💰 2. Cálculo de Economia por Cenário

### 2.1 Premissas

| Parâmetro | Valor | Fonte |
|-----------|-------|-------|
| **Horas/mês (24/7)** | 730h | Padrão billing AWS |
| **Dias úteis/mês** | 21.7 dias | Média anual (260 dias ÷ 12 meses) |
| **Uptime Dev (8h/dia)** | 173h/mês (24%) | 21.7 dias × 8h |
| **Uptime Prod (10h/dia)** | 217h/mês (30%) | 21.7 dias × 10h |
| **Uptime Prod Ext (12h/dia)** | 260h/mês (36%) | 21.7 dias × 12h |
| **Cold Start Time** | ~5min | EKS node ready + pods running |
| **RDS Stop Limit** | 7 dias | AWS limitation |

---

### 2.2 Cenário 1: Desenvolvimento (8h/dia útil)

**Horário:** Segunda-Sexta 08:00-18:00 BRT (11:00-21:00 UTC)
**Uptime:** 173h/mês (24% do tempo)

#### Custos Variáveis (podem ser reduzidos)

| Componente | Custo 24/7 | Custo 8h/dia | Economia |
|------------|------------|--------------|----------|
| **EC2 Nodes (7 nodes)** | $212.59 | $50.45 | $162.14 |
| **Data Transfer NAT** | $22.50 | $5.34 | $17.16 |
| **ALB LCU Charges** | $10.00 | $2.37 | $7.63 |
| **SUBTOTAL ECONOMIA** | | | **$186.93** |

#### Custos que NÃO mudam (fixos ou parciais)

| Componente | Custo/Mês | Motivo |
|------------|-----------|--------|
| **EBS Volumes + PVCs** | $36.96 | Storage persiste mesmo node off |
| **Custos Fixos Base** | $200.75 | EKS, S3, NAT hour charge, ALB hour charge |
| **Background Transfer** | $4.50 | CloudWatch logs, health checks |
| **SUBTOTAL FIXO** | **$242.21** | |

#### Total Cenário Desenvolvimento

| Métrica | Valor |
|---------|-------|
| **Custo Base 24/7** | $685.70/mês |
| **Custo com Start/Stop 8h** | $316.74/mês |
| **Economia Absoluta** | **$368.96/mês** |
| **Economia Percentual** | **53.8%** |
| **Economia Anual** | **$4.427.52/ano** |

---

### 2.3 Cenário 2: Produção (10h/dia útil - 8h-18h)

**Horário:** Segunda-Sexta 08:00-18:00 BRT (11:00-21:00 UTC)
**Uptime:** 217h/mês (30% do tempo)

#### Custos Variáveis

| Componente | Custo 24/7 | Custo 10h/dia | Economia |
|------------|------------|---------------|----------|
| **EC2 Nodes (7 nodes)** | $212.59 | $63.19 | $149.40 |
| **Data Transfer NAT** | $22.50 | $6.68 | $15.82 |
| **ALB LCU Charges** | $10.00 | $2.97 | $7.03 |
| **SUBTOTAL ECONOMIA** | | | **$172.25** |

#### Custos Fixos

| Componente | Custo/Mês |
|------------|-----------|
| **EBS Volumes + PVCs** | $36.96 |
| **Custos Fixos Base** | $200.75 |
| **Background Transfer** | $5.00 |
| **SUBTOTAL FIXO** | **$242.71** |

#### Total Cenário Produção 10h

| Métrica | Valor |
|---------|-------|
| **Custo Base 24/7** | $685.70/mês |
| **Custo com Start/Stop 10h** | $352.18/mês |
| **Economia Absoluta** | **$333.52/mês** |
| **Economia Percentual** | **48.6%** |
| **Economia Anual** | **$4.002.24/ano** |

---

### 2.4 Cenário 3: Produção Estendida (12h/dia útil)

**Horário:** Segunda-Sexta 07:00-19:00 BRT (10:00-22:00 UTC)
**Uptime:** 260h/mês (36% do tempo)

#### Custos Variáveis

| Componente | Custo 24/7 | Custo 12h/dia | Economia |
|------------|------------|---------------|----------|
| **EC2 Nodes (7 nodes)** | $212.59 | $75.83 | $136.76 |
| **Data Transfer NAT** | $22.50 | $8.03 | $14.47 |
| **ALB LCU Charges** | $10.00 | $3.57 | $6.43 |
| **SUBTOTAL ECONOMIA** | | | **$157.66** |

#### Custos Fixos

| Componente | Custo/Mês |
|------------|-----------|
| **EBS Volumes + PVCs** | $36.96 |
| **Custos Fixos Base** | $200.75 |
| **Background Transfer** | $5.50 |
| **SUBTOTAL FIXO** | **$243.21** |

#### Total Cenário Produção 12h

| Métrica | Valor |
|---------|-------|
| **Custo Base 24/7** | $685.70/mês |
| **Custo com Start/Stop 12h** | $387.61/mês |
| **Economia Absoluta** | **$298.09/mês** |
| **Economia Percentual** | **43.5%** |
| **Economia Anual** | **$3.577.08/ano** |

---

## 📈 3. Comparação de Cenários

### 3.1 Tabela Resumo

| Cenário | Uptime/Mês | Uptime % | Custo/Mês | Economia/Mês | Economia/Ano | ROI Automação |
|---------|------------|----------|-----------|--------------|--------------|---------------|
| **24/7 Baseline** | 730h | 100% | $685.70 | - | - | - |
| **Dev: 8h/dia** | 173h | 24% | $316.74 | $368.96 (54%) | $4.427.52 | < 1 mês |
| **Prod: 10h/dia** | 217h | 30% | $352.18 | $333.52 (49%) | $4.002.24 | < 1 mês |
| **Prod Ext: 12h/dia** | 260h | 36% | $387.61 | $298.09 (43%) | $3.577.08 | < 1 mês |
| **Sempre Ligado** | 730h | 100% | $685.70 | $0.00 (0%) | $0.00 | N/A |

### 3.2 Gráfico de Economia

```
                  ECONOMIA ANUAL POR CENÁRIO

$5.000 ┤
       │  ████████████ Dev 8h/dia: $4.427.52/ano (54%)
$4.500 ┤  ████████████
       │  ████████████
$4.000 ┤  ████████████  ██████████ Prod 10h: $4.002.24/ano (49%)
       │  ████████████  ██████████
$3.500 ┤  ████████████  ██████████  ████████ Prod 12h: $3.577.08/ano (43%)
       │  ████████████  ██████████  ████████
$3.000 ┤  ████████████  ██████████  ████████
       │  ████████████  ██████████  ████████
$2.500 ┤  ████████████  ██████████  ████████
       └──────────────────────────────────────────────
          Dev 8h      Prod 10h    Prod 12h
```

---

## 🔮 4. Projeção Marco 3 (Com RDS PostgreSQL)

### 4.1 Componentes Adicionais Marco 3 Fase 1

| Componente | Custo 24/7 | Variável? | Observações |
|------------|-----------|-----------|-------------|
| **RDS PostgreSQL** | $50.00/mês | ⚠️ LIMITADO | Stop máximo 7 dias, depois reinicia auto |
| **Redis (pods)** | $0.00 | ✅ SIM | Segue nodes (3 pods) |
| **RabbitMQ (pods)** | $0.00 | ✅ SIM | Segue nodes (3 nodes cluster) |
| **NLB PostgreSQL** | $16.20/mês | ⚠️ PARCIAL | Hour charge persiste, NLCU vai pra 0 |
| **NLB Redis** | $16.20/mês | ⚠️ PARCIAL | Hour charge persiste, NLCU vai pra 0 |
| **S3 Buckets** | $15.00/mês | ❌ NÃO | gitlab-artifacts + harbor-images |
| **GitLab ALB** | $81.20/mês | ⚠️ PARCIAL | $16.20 hour + $65 LCU (LCU vai pra 0) |
| **ArgoCD ALB** | $16.20/mês | ⚠️ PARCIAL | Hour charge apenas |
| **Harbor ALB** | $21.80/mês | ⚠️ PARCIAL | Hour + S3 backend |
| **TOTAL Marco 3 Adicional** | $216.60/mês | | |

### 4.2 Economia Marco 3 - Cenário Desenvolvimento (8h/dia)

#### Custos Variáveis Adicionais

| Componente | Custo 24/7 | Custo 8h/dia | Economia |
|------------|------------|--------------|----------|
| **RDS PostgreSQL** | $50.00 | $11.85 | $38.15 |
| **Redis/RabbitMQ (pods)** | $0.00 | $0.00 | $0.00 |
| **NLB NLCU Charges** | $10.00 | $2.37 | $7.63 |
| **ALB LCU Charges** | $75.00 | $17.80 | $57.20 |
| **SUBTOTAL ECONOMIA** | | | **$102.98** |

#### Custos Fixos Adicionais

| Componente | Custo/Mês |
|------------|-----------|
| **S3 Buckets** | $15.00 |
| **NLB Hour Charges** | $32.40 |
| **ALB Hour Charges** | $48.60 |
| **SUBTOTAL FIXO** | **$96.00** |

#### Total Marco 3 Desenvolvimento

| Métrica | Valor |
|---------|-------|
| **Marco 2 Base** | $316.74/mês (8h/dia) |
| **Marco 3 Adicional** | +$198.17/mês |
| **TOTAL Marco 3 Dev** | **$514.91/mês** |
| **vs 24/7 Marco 3** | $902.30/mês (sem otimizações) |
| **Economia Marco 3** | **$387.39/mês (42.9%)** |
| **Economia Anual** | **$4.648.68/ano** |

### 4.3 Economia Marco 3 - Cenário Produção (10h/dia)

| Métrica | Valor |
|---------|-------|
| **Marco 2 Base** | $352.18/mês (10h/dia) |
| **Marco 3 Adicional** | +$216.15/mês |
| **TOTAL Marco 3 Prod** | **$568.33/mês** |
| **vs 24/7 Marco 3** | $902.30/mês |
| **Economia Marco 3** | **$333.97/mês (37.0%)** |
| **Economia Anual** | **$4.007.64/ano** |

---

## ⚠️ 5. Limitações e Considerações

### 5.1 RDS Stop Limitation

**Problema:**
AWS RDS pode ser stopped por até **7 dias consecutivos**. Após isso, reinicia automaticamente.

**Impacto:**
- Dev/Homolog: Se parar sexta 18h, reinicia na segunda seguinte (3 dias ok)
- Produção: Idem, sem impacto
- **Long Weekends:** Feriados > 7 dias = RDS reinicia sozinho

**Mitigação:**
1. **Snapshot + Restore:** Deletar RDS sexta, restaurar de snapshot segunda (economia total)
2. **Lambda Automático:** Re-stop RDS no dia 6 (reset contador de 7 dias)
3. **Aceitar Reinício:** Deixar reiniciar, parar novamente no próximo ciclo

**Recomendação:**
Para Dev, usar **opção 1** (snapshot sexta → restore segunda). Economia adicional: **$38.15/mês** ($457.80/ano).

### 5.2 Cold Start Time

**Tempo estimado:**
- EKS nodes: 2-3min (boot + join cluster)
- Pods platform: 1-2min (Prometheus, Grafana, Loki)
- Pods workloads: 2-4min (GitLab, ArgoCD, Harbor)
- **TOTAL:** ~5-7min até ambiente fully operational

**Impacto:**
- Desenvolvimento: Aceitável (devs chegam 08:00, plataforma ready 08:07)
- Produção: Considerar pre-warm 07:50 (ready às 08:00)

**Mitigação:**
- EventBridge rule: Start 15min antes (07:45 BRT = 10:45 UTC)
- Health checks: ALB target health antes de roteamento

### 5.3 Data Persistence

**Componentes que PERSISTEM quando nodes off:**

| Componente | Storage | Custo/Mês | Segurança |
|------------|---------|-----------|-----------|
| **EBS Root Volumes** | 7 × 50GB | $28.00 | ✅ Preservado |
| **EBS PVCs** | Prometheus, Grafana, Loki WAL | $8.96 | ✅ Preservado |
| **S3 Loki/Tempo** | 500GB + 500GB | $23.00 | ✅ Preservado |
| **S3 GitLab** | Artifacts + Images | $15.00 | ✅ Preservado |
| **RDS (stopped)** | 100GB gp3 | $11.50 | ✅ Preservado |

**Confirmação:** Nenhum dado é perdido no shutdown. Apenas compute é liberado.

### 5.4 Network Connectivity

**Durante Shutdown:**
- ALBs: HTTP returns **503 Service Unavailable** (sem targets healthy)
- DNS: Route53 continua resolvendo (mas ALB sem backends)
- VPN: Se acesso interno, tudo offline (esperado)

**Workaround:**
- Página manutenção: S3 Static Website com redirect Route53 (custo: $0.50/mês)

---

## 🚀 6. ROI da Automação

### 6.1 Investimento Inicial

| Atividade | Horas | Custo* | Descrição |
|-----------|-------|--------|-----------|
| **Lambda Functions** | 2h | $200 | Stop/Start nodes + RDS |
| **EventBridge Rules** | 1h | $100 | Cron schedules |
| **IAM Policies** | 0.5h | $50 | Permissions Lambda |
| **Testing** | 1h | $100 | Validação ciclos |
| **Documentation** | 0.5h | $50 | Runbooks |
| **TOTAL ESFORÇO** | **5h** | **$500** | |

*Assumindo $100/hora DevOps Engineer

### 6.2 Payback Period

| Cenário | Economia/Mês | Payback | ROI 12 meses |
|---------|--------------|---------|--------------|
| **Dev 8h/dia** | $368.96 | < 2 semanas | $4.427.52 (886% ROI) |
| **Prod 10h/dia** | $333.52 | < 2 semanas | $4.002.24 (800% ROI) |
| **Prod 12h/dia** | $298.09 | < 2 semanas | $3.577.08 (715% ROI) |

**Análise:**
Investimento de $500 (5h) retorna em **< 2 semanas** em QUALQUER cenário.

### 6.3 Custo Operacional Contínuo

| Item | Frequência | Custo/Ano |
|------|------------|-----------|
| **Lambda Executions** | 2×/dia × 260 dias | $0.00 (Free Tier) |
| **EventBridge Rules** | 2 rules | $0.00 (Free Tier) |
| **CloudWatch Logs** | 1GB/ano | $0.50 |
| **Manutenção** | 1h/trimestre | $400 |
| **TOTAL OPEX** | | **$400.50/ano** |

**Net Savings:** $4.427.52 - $400.50 = **$4.027.02/ano** (Dev 8h/dia)

---

## 🎯 7. Estratégia FinOps Recomendada

### 7.1 Decisão por Ambiente

| Ambiente | Recomendação | Uptime | Economia/Ano | Justificativa |
|----------|--------------|--------|--------------|---------------|
| **Development** | ✅ **START/STOP 8h** | 24% | $4.427.52 | ROI altíssimo, uso real 8h/dia |
| **Homolog/Staging** | ✅ **START/STOP 8h** | 24% | $4.427.52 | Testes apenas horário comercial |
| **Production** | ⚠️ **AVALIAR** | 100% ou 30% | $0 ou $4.002 | Depende SLA (ver abaixo) |

### 7.2 Produção: Quando vale Start/Stop?

**VALE A PENA se:**
- ✅ SLA permite downtime noturno (ex: B2B, horário comercial)
- ✅ Clientes concentrados em 1 timezone (Brasil)
- ✅ Não há jobs batch noturnos críticos
- ✅ Cold start de 5min é aceitável

**NÃO VALE se:**
- ❌ SLA 24/7 obrigatório (B2C, global)
- ❌ Jobs noturnos (ETL, backups, CI/CD pipelines)
- ❌ Webhooks externos (GitHub, Slack) esperam resposta imediata
- ❌ Multi-region com failover (precisa standby always-on)

**Recomendação Produção:**
Se **B2B horário comercial** → Start/Stop 10h/dia economiza **$4.002/ano** (48.6%).
Se **B2C 24/7** → Sempre ligado, focar em outras otimizações (RI, Spot).

### 7.3 Hybrid Strategy (Recomendado)

```
┌─────────────────────────────────────────────────────────────┐
│               ESTRATÉGIA FINOPS RECOMENDADA                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  DEVELOPMENT (Dev/Test)                                      │
│  ├─ Start/Stop: 8h/dia útil (08:00-18:00 BRT)              │
│  ├─ Economia: $368.96/mês ($4.427/ano)                     │
│  └─ ROI: < 2 semanas                                        │
│                                                              │
│  STAGING (Homologação)                                       │
│  ├─ Start/Stop: 8h/dia útil (08:00-18:00 BRT)              │
│  ├─ Economia: $368.96/mês ($4.427/ano)                     │
│  └─ On-demand start para demos (webhook)                    │
│                                                              │
│  PRODUCTION                                                  │
│  ├─ Opção A (B2B): Start/Stop 10h/dia → $333/mês economia  │
│  ├─ Opção B (B2C): Always-on → Usar RI + Spot              │
│  └─ Decisão: Avaliar SLA + padrão de uso                   │
│                                                              │
│  OTIMIZAÇÕES COMPLEMENTARES (todos ambientes)                │
│  ├─ Reserved Instances: $124/mês economia                   │
│  ├─ S3 Lifecycle Glacier: $9/mês economia                   │
│  ├─ Consolidar ALBs: $16/mês economia                       │
│  └─ TOTAL ADICIONAL: $149/mês ($1.788/ano)                 │
│                                                              │
│  ECONOMIA TOTAL ANUAL (Dev + Staging + Otimizações)         │
│  └─ $8.855/ano + $1.788/ano = $10.643/ano                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 8. Implementation Checklist

### 8.1 Scripts Necessários

**Nota:** Os scripts mencionados no contexto (`scripts/startup-marco2-fase7.sh`, `scripts/shutdown-marco2-fase7.sh`) **não existem** no repositório.

**Criar:**

```bash
# /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/
├── startup-marco2.sh           # Start nodes + RDS
├── shutdown-marco2.sh          # Stop nodes + RDS + snapshot
├── startup-marco3.sh           # Marco 3 com workloads
├── shutdown-marco3.sh          # Marco 3 stop completo
└── restore-rds-snapshot.sh     # Restore RDS para dev
```

### 8.2 Lambda Functions

| Função | Trigger | Ação |
|--------|---------|------|
| `k8s-start-dev-morning` | EventBridge 08:00 BRT | Scale node groups 0→desired |
| `k8s-stop-dev-evening` | EventBridge 18:00 BRT | Scale node groups desired→0 + RDS stop |
| `k8s-rds-snapshot-friday` | EventBridge Sex 18:00 | Snapshot RDS + delete instance |
| `k8s-rds-restore-monday` | EventBridge Seg 07:45 | Restore RDS from latest snapshot |

### 8.3 EventBridge Cron Schedules

| Rule | Cron Expression (UTC) | Descrição |
|------|----------------------|-----------|
| `start-dev-morning` | `cron(0 11 ? * MON-FRI *)` | 08:00 BRT = 11:00 UTC |
| `stop-dev-evening` | `cron(0 21 ? * MON-FRI *)` | 18:00 BRT = 21:00 UTC |
| `snapshot-rds-friday` | `cron(0 21 ? * FRI *)` | Sexta 18:00 BRT |
| `restore-rds-monday` | `cron(45 10 ? * MON *)` | Segunda 07:45 BRT |

### 8.4 Tags para Automação

**Adicionar tag `Schedule` aos recursos:**

```bash
# Nodes Dev/Staging
aws eks tag-resource \
  --resource-arn arn:aws:eks:us-east-1:ACCOUNT:nodegroup/k8s-platform-cluster/system \
  --tags Schedule=office-hours,Environment=dev

# RDS Dev
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:us-east-1:ACCOUNT:db:gitlab-dev \
  --tags Key=Schedule,Value=office-hours
```

**Produção:**
```bash
# Tag Production nodes como always-on
aws eks tag-resource \
  --resource-arn arn:aws:eks:us-east-1:ACCOUNT:nodegroup/k8s-platform-cluster/system \
  --tags Schedule=always-on,Environment=production
```

---

## 📊 9. Monitoramento e Alertas

### 9.1 CloudWatch Dashboards

**Criar dashboard:** `FinOps-StartStop-Monitoring`

**Widgets:**
1. **Node Count Timeline** (grafo)
   - Métrica: `kube_node_info` (Prometheus)
   - Esperado: 7 nodes (08:00-18:00), 0 nodes (18:00-08:00)

2. **Cost Savings Gauge** (gauge)
   - Fórmula: `(1 - current_cost / baseline_cost) * 100`
   - Threshold: Verde > 40%, Amarelo 20-40%, Vermelho < 20%

3. **RDS Status** (stat)
   - Métrica: `aws_rds_database_status`
   - Estados: available, stopped, creating

4. **Lambda Execution Status** (log insights)
   - Query: `fields @timestamp, function_name, status | filter status != "success"`

### 9.2 Alertas Críticos

| Alerta | Condição | Ação |
|--------|----------|------|
| **Nodes não startaram** | `kube_node_info < 7` às 08:15 BRT | Teams + Email DevOps |
| **Nodes não pararam** | `kube_node_info > 0` às 18:15 BRT | Email FinOps Team |
| **RDS ainda running** | RDS status = "available" às 18:30 BRT | Teams alert |
| **Lambda failure** | Lambda errors > 0 | PagerDuty |

### 9.3 Métricas de Sucesso

| KPI | Target | Medição |
|-----|--------|---------|
| **Economia Real** | > 45%/mês | AWS Cost Explorer tag filter |
| **Uptime Conformance** | 95% adherence | EventBridge execution logs |
| **Cold Start Time** | < 7min | Prometheus timestamp diffs |
| **RDS Snapshot Success** | 100% | CloudWatch Logs Lambda |

---

## 🔄 10. Runbook Operacional

### 10.1 Manual Start (Emergency)

```bash
# 1. Start node groups
aws eks update-nodegroup-config \
  --cluster-name k8s-platform-cluster \
  --nodegroup-name system \
  --scaling-config minSize=2,desiredSize=2,maxSize=4

aws eks update-nodegroup-config \
  --cluster-name k8s-platform-cluster \
  --nodegroup-name workloads \
  --scaling-config minSize=2,desiredSize=3,maxSize=6

aws eks update-nodegroup-config \
  --cluster-name k8s-platform-cluster \
  --nodegroup-name critical \
  --scaling-config minSize=2,desiredSize=2,maxSize=4

# 2. Start RDS
aws rds start-db-instance --db-instance-identifier gitlab-dev

# 3. Verificar status
kubectl get nodes
aws rds describe-db-instances --db-instance-identifier gitlab-dev --query 'DBInstances[0].DBInstanceStatus'
```

### 10.2 Manual Stop (Emergency)

```bash
# 1. Stop nodes (scale to 0)
aws eks update-nodegroup-config \
  --cluster-name k8s-platform-cluster \
  --nodegroup-name system \
  --scaling-config minSize=0,desiredSize=0,maxSize=4

aws eks update-nodegroup-config \
  --cluster-name k8s-platform-cluster \
  --nodegroup-name workloads \
  --scaling-config minSize=0,desiredSize=0,maxSize=6

aws eks update-nodegroup-config \
  --cluster-name k8s-platform-cluster \
  --nodegroup-name critical \
  --scaling-config minSize=0,desiredSize=0,maxSize=4

# 2. Stop RDS
aws rds stop-db-instance --db-instance-identifier gitlab-dev

# 3. Verificar
kubectl get nodes  # Deve retornar "No resources found"
aws rds describe-db-instances --db-instance-identifier gitlab-dev --query 'DBInstances[0].DBInstanceStatus'  # stopped
```

### 10.3 Troubleshooting

| Problema | Causa Provável | Solução |
|----------|---------------|---------|
| **Nodes não sobem** | ASG max capacity atingido | Verificar ASG limits console |
| **Pods CrashLoopBackOff** | PVCs não montados | Check EBS CSI driver logs |
| **RDS connection timeout** | RDS ainda stopped | Wait 5min, check status |
| **Lambda timeout** | API throttling | Increase timeout 5min → 10min |

---

## 📚 11. Referências

### 11.1 Documentação AWS

- [EKS Node Group Scaling](https://docs.aws.amazon.com/eks/latest/userguide/update-managed-node-group.html)
- [RDS Stop Limitations](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_StopInstance.html)
- [Lambda + EventBridge](https://docs.aws.amazon.com/lambda/latest/dg/services-cloudwatchevents.html)
- [AWS Cost Optimization](https://aws.amazon.com/aws-cost-management/aws-cost-optimization/)

### 11.2 FinOps Foundation

- [FinOps Framework](https://www.finops.org/framework/)
- [Kubernetes Cost Optimization](https://www.finops.org/framework/capabilities/manage-commitment-based-discounts/)

### 11.3 Documentos Internos

- [/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/context/costs.md](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/context/costs.md)
- [/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/aws-execution/07-finops-automacao.md](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/aws-execution/07-finops-automacao.md)
- [/home/gilvangalindo/projects/Arquitetura/Kubernetes/SAD/docs/adrs/adr-019-finops.md](/home/gilvangalindo/projects/Arquitetura/Kubernetes/SAD/docs/adrs/adr-019-finops.md)

---

## ✅ 12. Conclusões e Recomendações Finais

### 12.1 Recomendação Estratégica

**IMPLEMENTAR START/STOP IMEDIATAMENTE para:**
- ✅ **Development:** 8h/dia útil → Economia $368.96/mês ($4.428/ano)
- ✅ **Staging:** 8h/dia útil → Economia $368.96/mês ($4.428/ano)

**AVALIAR CASO A CASO para:**
- ⚠️ **Production:** Se B2B horário comercial → 10h/dia economiza $333.52/mês ($4.002/ano)
- ⚠️ **Production:** Se B2C 24/7 → Manter sempre ligado, usar RI + Spot

### 12.2 Quick Wins (Implementação Imediata)

| Ação | Esforço | Economia/Ano | ROI |
|------|---------|--------------|-----|
| **Lambda Start/Stop Dev** | 5h | $4.428 | 886% |
| **Reserved Instances 1yr** | 1h | $1.488 | 1488% |
| **S3 Lifecycle Glacier** | 0.5h | $108 | 216% |
| **Consolidar ALBs** | 2h | $194 | 97% |
| **TOTAL Quick Wins** | **8.5h** | **$6.218/ano** | **732%** |

### 12.3 Roadmap de Implementação

**Fase 1 (Semana 1-2):**
1. Criar Lambda functions start/stop
2. Configurar EventBridge schedules
3. Testar ciclo completo Dev
4. Implementar alertas CloudWatch

**Fase 2 (Semana 3-4):**
5. Adicionar RDS snapshot/restore
6. Implementar S3 Lifecycle policies
7. Comprar Reserved Instances 1 ano
8. Dashboard Grafana FinOps

**Fase 3 (Mês 2):**
9. Consolidar ALBs (IngressGroup)
10. Avaliar Produção start/stop
11. Marco 3 automation (GitLab, Harbor)

**Economia Total Projetada Ano 1:**
- Start/Stop Dev+Staging: $8.856/ano
- Reserved Instances: $1.488/ano
- S3 Lifecycle: $108/ano
- ALB Consolidation: $194/ano
- **TOTAL:** **$10.646/ano** (78% do custo baseline)

### 12.4 Próximos Passos

- [ ] **Aprovar investimento:** 8.5h DevOps Engineer ($850)
- [ ] **Definir horários:** Confirmar 08:00-18:00 BRT ou ajustar
- [ ] **Criar Lambda functions:** Ver Doc 07 (FinOps Automação)
- [ ] **Testar em Dev:** 1 semana trial antes produção
- [ ] **Review mensal:** AWS Cost Explorer + KPIs

---

**Documento mantido por:** FinOps Team + Cloud Architect
**Última atualização:** 2026-01-29
**Próxima revisão:** 2026-02-15 (após 2 semanas de testes)
