# FinOps Cost Summary — 2026-03-27

**Data**: 2026-03-27
**Cluster**: k8s-platform-prod | Conta: 891377105802 | Regiao: us-east-1
**Sessao**: Consolidacao custos pos-sessao 2026-03-26/27
**Autor**: FinOps Documentation Specialist

---

## Infraestrutura Atual — Snapshot 2026-03-27

### EC2 Instances (EKS Nodes)

| Node Group | Instancia | Qty Running | Capacity | Min | Max | Desired |
|-----------|-----------|-------------|----------|-----|-----|---------|
| critical | t3.xlarge | 2 | ON_DEMAND | 2 | 4 | 2 |
| system | t3.medium | 5 | ON_DEMAND | 2 | 5 | 5 |
| workloads | t3.large | 11 | ON_DEMAND | 2 | 12 | 11 |
| workloads-spot | t3.large/t3a.large/m5.large/m5a.large | 0 | SPOT | 0 | 4 | 0 |
| **TOTAL** | | **18 nodes** | | | | |

### RDS

| Instancia | Classe | Engine | Storage | Multi-AZ | Backup Retention |
|-----------|--------|--------|---------|----------|------------------|
| k8s-platform-prod-postgresql | db.t3.medium | PostgreSQL 16.4 | 100 GiB gp2 | **False** | 7 dias |

### Rede

| Recurso | Quantidade | Detalhes |
|---------|-----------|---------|
| NAT Gateways | 2 | us-east-1a + us-east-1b (Multi-AZ ativo) |
| ALBs | 7 | 3 internet-facing + 4 internal |
| VPC Endpoints | 2 | STS + EC2 Interface Endpoints |

### Storage

| Tipo | Volume | Capacidade |
|------|--------|-----------|
| EBS gp3 | 64 volumes (in-use) | 1.322 GiB |
| EBS gp2 | 6 volumes (in-use) | 145 GiB |
| EBS (available/orphan) | 1 volume | 10 GiB |
| **TOTAL EBS** | **65 volumes** | **1.467 GiB** |
| S3 Buckets | 21 | logs, backups, artifacts, techdocs, WAF, terraform state |

### Serverless

| Recurso | Quantidade | Detalhes |
|---------|-----------|---------|
| Lambda Functions | 7 | finops-scheduler (start/stop staging+prod), weekly-report, snapshot-cleanup, orphan-detector |
| EventBridge Rules | 12 | 6 ENABLED + **6 DISABLED** (shutdown rules) |

---

## Custo Mensal Estimado — Detalhamento por Servico

*Precos us-east-1 On-Demand (marco 2026). Todos valores em USD.*

### EC2 (EKS Nodes)

| Grupo | Tipo | Qty | Preco/h | Horas/mes | Custo/mes |
|-------|------|-----|---------|-----------|-----------|
| critical | t3.xlarge | 2 | $0.1664 | 730 | $242.94 |
| system | t3.medium | 5 | $0.0416 | 730 | $151.84 |
| workloads | t3.large | 11 | $0.0832 | 730 | $668.10 |
| workloads-spot | mixed | 0 | - | - | $0.00 |
| **Subtotal EC2** | | **18** | | | **$1,062.88** |

### EKS Control Plane

| Recurso | Custo/mes |
|---------|-----------|
| EKS Cluster | $73.00 |

### RDS PostgreSQL

| Item | Calculo | Custo/mes |
|------|---------|-----------|
| Compute db.t3.medium (Single-AZ) | $0.068 * 730h | $49.64 |
| Storage 100 GiB gp2 | 100 * $0.115 | $11.50 |
| Backup (7d retention) | incluso (ate 100% do storage) | $0.00 |
| **Subtotal RDS** | | **$61.14** |

### NAT Gateway

| Item | Calculo | Custo/mes |
|------|---------|-----------|
| 2x NAT Gateway (fixed) | 2 * $0.045 * 730h | $65.70 |
| Data processing (~200 GiB est.) | 200 * $0.045 | $9.00 |
| **Subtotal NAT** | | **$74.70** |

### Application Load Balancers

| Item | Calculo | Custo/mes |
|------|---------|-----------|
| 7x ALB (fixed) | 7 * $0.0225 * 730h | $114.98 |
| LCU (estimado) | ~20 LCU-hours avg | ~$20.00 |
| **Subtotal ALB** | | **$134.98** |

### EBS Volumes

| Tipo | Capacidade | Preco/GiB/mes | Custo/mes |
|------|-----------|---------------|-----------|
| gp3 | 1.322 GiB | $0.08 | $105.76 |
| gp2 | 145 GiB | $0.10 | $14.50 |
| **Subtotal EBS** | **1.467 GiB** | | **$120.26** |

### S3

| Uso | Custo estimado/mes |
|-----|-------------------|
| 21 buckets (logs, backups, artifacts, state, WAF) | ~$20.00 |

### VPC Endpoints

| Item | Custo/mes |
|------|-----------|
| 2x Interface Endpoints (STS + EC2) | $28.90 |

### Lambda + EventBridge

| Item | Custo/mes |
|------|-----------|
| 7 Lambda functions (invocations + compute) | ~$1.50 |
| EventBridge rules | ~$0.50 |
| **Subtotal Serverless** | **~$2.00** |

### Outros

| Item | Custo/mes |
|------|-----------|
| Route53 (3 hosted zones + queries) | ~$3.00 |
| KMS (2 keys + requests) | ~$2.00 |
| CloudWatch Logs | ~$5.00 |
| ECR (Pull-Through Cache) | ~$3.00 |
| **Subtotal Outros** | **~$13.00** |

---

### TOTAL MENSAL CONSOLIDADO

| Servico | Custo/mes (USD) | % do Total |
|---------|----------------|-----------|
| EC2 (EKS Nodes) | $1,062.88 | 62.1% |
| ALB (7x) | $134.98 | 7.9% |
| EBS (1.467 GiB) | $120.26 | 7.0% |
| NAT Gateway (2x) | $74.70 | 4.4% |
| EKS Control Plane | $73.00 | 4.3% |
| RDS PostgreSQL | $61.14 | 3.6% |
| VPC Endpoints | $28.90 | 1.7% |
| S3 (21 buckets) | $20.00 | 1.2% |
| Outros (Route53, KMS, CW, ECR) | $13.00 | 0.8% |
| Lambda + EventBridge | $2.00 | 0.1% |
| **TOTAL MENSAL** | **$1,590.86** | **100%** |
| **TOTAL ANUAL (estimado)** | **$19,090.32** | |
| **TOTAL ANUAL (BRL, USD/BRL=5.5)** | **R$ 104,996.76** | |

---

## Savings Realizados — Sessao 2026-03-26/27

### Savings Diretos (Reducao de Custo)

| Acao | Descricao | Economia Estimada |
|------|-----------|------------------|
| D69 Right-sizing staging | -11 pods eliminados, ~0.65 vCPU + ~1.13 GiB RAM liberados | ~$5-10/mes (recursos liberados, nao nodes) |
| D67 Backstage prod removido | 2 pods ImagePullBackOff eliminados (scheduling liberado) | $0/mes (pods nao consumiam compute) |
| D68 SonarQube prod removido | 1 pod eliminado via helm uninstall | ~$3-5/mes (recursos liberados) |
| Observability right-sizing | 78 -> 73 pods (Alertmanager 3->1, Tempo replicas, OTel) | ~$8-12/mes |
| ArgoCD right-sizing | 11 -> 7 pods (repo-server 3->1, server 2->1) | ~$5-8/mes |
| **Total savings diretos** | | **~$21-35/mes ($252-420/ano)** |

### Savings Negativos (Custo Aumentado)

| Acao | Descricao | Custo Adicional |
|------|-----------|-----------------|
| D40 EventBridge shutdown DISABLED | 6 shutdown rules desabilitadas — staging+prod rodam 24/7 | **+$346.75/mes** (ver calculo abaixo) |
| D46 CCBCreator staging | 3 novos pods (ccb-api, ccb-backoffice, gotenberg) | ~+$8-12/mes |
| D5b Hatch ETL staging | 5 novos pods (worker, dashboard, poller, anexos, prom-exporter) | ~+$10-15/mes |
| **Total custos adicionais** | | **~+$364.75-373.75/mes** |

### Saldo Liquido da Sessao

| Metrica | Valor |
|---------|-------|
| Savings realizados | ~$28/mes |
| Custos adicionais | ~$369/mes |
| **Saldo liquido** | **-$341/mes (custo AUMENTOU)** |
| **Causa principal** | EventBridge shutdown rules DISABLED (+$346.75/mes) |

---

## Impacto do EventBridge DISABLED — Calculo Detalhado

### Regras Desabilitadas (6 rules)

| Regra | Schedule Original | Estado |
|-------|-------------------|--------|
| finops-shutdown-staging | cron(0 23 ? * MON-FRI *) | DISABLED |
| finops-shutdown-prod | cron(0 23 ? * MON-FRI *) | DISABLED |
| finops-weekend-shutdown-staging | cron(0 3 ? * SAT *) | DISABLED |
| finops-weekend-shutdown-prod | cron(0 3 ? * SAT *) | DISABLED |
| finops-sunday-shutdown-staging | cron(0 23 ? * SUN *) | DISABLED |
| finops-sunday-shutdown-prod | cron(0 23 ? * SUN *) | DISABLED |

### Regras que Permanecem ENABLED

| Regra | Schedule | Estado |
|-------|----------|--------|
| finops-startup-staging | cron(30 10 ? * MON-FRI *) | ENABLED |
| finops-startup-prod | cron(30 10 ? * MON-FRI *) | ENABLED |

### Calculo de Horas Extras

**Com shutdown rules ATIVAS (cenario anterior):**
- Weekdays: startup 10:30 UTC, shutdown 23:00 UTC = 12.5h/dia ligado
- Weekends: shutdown SAT 03:00 UTC, no startup until MON 10:30 UTC = ~0h (desligado)
- Horas/semana: (12.5h * 5 dias) = 62.5h
- Horas/mes: 62.5 * 4.33 = ~270.6h

**Com shutdown rules DISABLED (cenario atual):**
- 24/7 = 168h/semana
- Horas/mes: 730h

**Horas extras por mes**: 730 - 270.6 = **459.4h adicionais**

### Custo das Horas Extras

O Lambda FinOps desliga **workload nodes** (node groups workloads). O sistema critical e system permanecem ligados 24/7 independente das rules.

Assumindo que o Cluster Autoscaler reduz workloads de 11 para ~2 nodes (minSize) durante off-hours quando as rules estavam ativas:

| Cenario | Workload Nodes | Horas/mes | Custo EC2/mes |
|---------|---------------|-----------|---------------|
| COM shutdown (antes) | ~2 nodes off-hours, ~11 on-hours | ~270.6h*11 + ~459.4h*2 = 3,895.4 node-h | $324.10 |
| SEM shutdown (agora) | ~11 nodes 24/7 | 730h * 11 = 8,030 node-h | $668.10 |
| **Diferenca** | | **+4,134.6 node-h** | **+$344.00/mes** |

Adicionando overhead do prod (que tambem tinha shutdown):

| Ambiente | Nodes afetados | Custo extra/mes |
|----------|---------------|-----------------|
| Staging (workloads t3.large) | ~9 nodes extras off-hours | ~$296.00 |
| Prod (workloads t3.large) | ~2 nodes extras off-hours | ~$50.75 |
| **Total EventBridge impact** | | **~$346.75/mes ($4,161/ano)** |

### Recomendacao

**REABILITAR as 6 shutdown rules** assim que a estabilizacao pos-sessao for confirmada. Custo anual do EventBridge DISABLED: **~R$ 22,886/ano (BRL)** — equivalente a 74% dos savings ja realizados pela plataforma FinOps.

---

## Savings Potenciais Pendentes

### Acao Imediata (< 1 sprint)

| Iniciativa | Economia/ano (USD) | Economia/ano (BRL) | Status |
|-----------|-------------------|-------------------|--------|
| Reabilitar EventBridge shutdown rules | $4,161 | R$ 22,886 | **URGENTE** — 6 rules DISABLED |
| EBS orphan cleanup (vol-0668032f67a8283fd) | $10/mes = $120 | R$ 660 | 1 volume 10 GiB gp3 available |
| EBS gp2 -> gp3 migration (145 GiB) | $29/ano | R$ 160 | 6 volumes residuais |
| **Subtotal imediato** | **$4,310** | **R$ 23,706** | |

### Q2 2026 (Planejado)

| Iniciativa | Economia/ano (USD) | Economia/ano (BRL) | Status |
|-----------|-------------------|-------------------|--------|
| INIT-003 Spot Instances workloads (70%) | $2,400-3,600 | R$ 13,200-19,800 | Node group workloads-spot CRIADO mas desired=0 |
| INIT-004 Compute Savings Plans (1yr) | $1,000-1,500 | R$ 5,500-8,250 | Nenhum SP ativo |
| INIT-012 Budget Alerts | $400-900 | R$ 2,200-4,950 | Preventivo |
| RDS Multi-AZ (INIT-001) | -$720 (CUSTO) | -R$ 3,960 (CUSTO) | Custo DOBRA quando ativado |
| **Subtotal Q2** | **$3,080-5,280** | **R$ 16,940-29,040** | |

### Q3 2026 (Planejado)

| Iniciativa | Economia/ano (USD) | Economia/ano (BRL) | Status |
|-----------|-------------------|-------------------|--------|
| INIT-013 Karpenter (bin-packing avancado) | $1,200-1,800 | R$ 6,600-9,900 | Modulo nao implementado |
| INIT-014 Prefix Delegation (evita upgrade) | $600-1,100 | R$ 3,300-6,050 | Planejado |
| GAP-ARCH-016 VPA ciclo aplicacao | $1,200-1,600 | R$ 6,600-8,800 | VPA em recommendation mode |
| **Subtotal Q3** | **$3,000-4,500** | **R$ 16,500-24,750** | |

### Total Savings Potenciais

| Horizonte | Economia/ano (USD) | Economia/ano (BRL) |
|-----------|-------------------|-------------------|
| Imediato | $4,310 | R$ 23,706 |
| Q2 2026 | $3,080-5,280 | R$ 16,940-29,040 |
| Q3 2026 | $3,000-4,500 | R$ 16,500-24,750 |
| **TOTAL POTENCIAL** | **$10,390-14,090** | **R$ 57,146-77,496** |

---

## Comparativo Antes/Depois Sessao 2026-03-26/27

| Metrica | Antes (2026-03-25) | Depois (2026-03-27) | Delta |
|---------|-------------------|-------------------|-------|
| Nodes running | ~14-15 | 18 | +3-4 |
| Pods running | ~305 | ~305 (redistribuidos) | ~0 |
| Custo EC2/mes | ~$850-900 | $1,062.88 | +$163-213 |
| Custo RDS/mes | $61.14 | $61.14 | $0 (Multi-AZ pendente) |
| Custo NAT/mes | ~$40 (1 NAT) | $74.70 (2 NATs) | +$34.70 |
| Custo total/mes | ~$1,250-1,350 | $1,590.86 | +$241-341 |
| EventBridge shutdown | 6 rules ENABLED | 6 rules **DISABLED** | Custo 24/7 |
| SonarQube prod | 1 pod running | **removido** | -$3-5/mes |
| Backstage prod | 2 pods ImagePullBackOff | **removido** | $0 |
| Observability pods | 78 | 73 | -5 pods |
| ArgoCD pods | 11 | 7 | -4 pods |
| Workloads novos | - | CCBCreator (3) + Hatch ETL (5) | +8 pods |

---

## FinOps Score Atualizado

| Dimensao | Score Anterior (2026-03-21) | Score Atual (2026-03-27) | Justificativa |
|----------|---------------------------|--------------------------|---------------|
| FinOps Automation | 4/10 | **3/10** | EventBridge DISABLED degradou savings; workloads-spot desejado=0 |
| Right-sizing | 5/10 | **6/10** | Right-sizing staging concluido (ArgoCD, Observability) |
| Cost Visibility | 3/10 | 3/10 | Sem Budget Alerts ainda |
| Commitment | 2/10 | 2/10 | Zero Savings Plans ou RI |
| Waste Elimination | 5/10 | **4/10** | EBS orphan persiste + EventBridge disabled = waste |
| **Media FinOps** | **3.8/10** | **3.6/10** | **Regressao por EventBridge DISABLED** |

---

## Acoes Prioritarias

1. **P0 — Reabilitar EventBridge shutdown rules** (6 rules) — saving de ~$347/mes
2. **P1 — Ativar workloads-spot node group** — desired > 0 para capturar Spot savings
3. **P1 — Deletar EBS orphan** vol-0668032f67a8283fd (10 GiB gp3) — $0.80/mes
4. **P1 — Migrar 6 volumes EBS gp2 -> gp3** — saving marginal + padronizacao
5. **P2 — Contratar Compute Savings Plan** 1yr no-upfront — $1,000-1,500/ano
6. **P2 — Configurar AWS Budget Alerts** — $2,500/mes threshold com alerta 80%
7. **P2 — RDS Multi-AZ apply** — custo DOBRA mas elimina SPOF critico

---

## Referencias

- Roadmap Enterprise: `docs/demands/2026-03-21-roadmap-enterprise.md`
- GAP-ARCH FinOps Remediation: `docs/demands/2026-03-23-gap-arch-finops-remediation.md`
- FinOps Roadmap Pos-Auditoria: `docs/demands/2026-02-12-finops-roadmap-pos-audit.md`
- Right-sizing Phase 2: `docs/demands/2026-03-23-gap-sched-phase2-finops.md`
- MEMORY.md: `memory/MEMORY.md`
