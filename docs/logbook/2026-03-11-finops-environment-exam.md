# FinOps Environment Exam - 2026-03-11

**Executor:** Orquestrador DevOps
**Protocol:** executor-terraform.md
**Tipo:** Exame completo do ambiente (cluster + custos + automacao)
**Cluster:** k8s-platform-prod (EKS 1.34.2)

---

## Objetivo

Exame completo do ambiente de staging em 2026-03-11 para avaliar estado do cluster, consumo de recursos, custos MTD, e eficacia da automacao FinOps apos 1 mes de operacao.

---

## 1. Estado do Cluster

| Metrica | Valor Atual | Valor Anterior (Mar 6) | Delta |
|---------|-------------|------------------------|-------|
| Nodes Ready | 13 | 9 | +4 (+44%) |
| Pods Total | 234 | 209 | +25 (+12%) |
| EKS Version | 1.34.2 | 1.34.2 | -- |

### Node Groups

| Node Group | Instance Type | Desired | Max | Anterior (Mar 6) | Delta |
|------------|---------------|---------|-----|-------------------|-------|
| system | t3.medium | 4 | 4 | 3 | +1 (AT MAX) |
| workloads | t3.large | 6 | 6 | 4 | +2 (AT MAX) |
| critical | t3.xlarge | 3 | 4 | 2 | +1 |

**ALERTA P0:** system e workloads estao no limite maximo. Nenhuma margem para scale-up.

### Top Namespaces por Pod Count

| Namespace | Pods |
|-----------|------|
| kube-system | 78 |
| staging-observability-monitoring | 67 |
| velero | 14 |
| linkerd-cni | 13 |
| staging-platform-gitlab | 11 |
| staging-platform-argocd | 11 |

---

## 2. Consumo de Recursos (kubectl top nodes)

| Node | CPU | CPU% | MEM | MEM% | Obs |
|------|-----|------|-----|------|-----|
| ip-10-0-130-167 | 298m | 7% | 4630Mi | 31% | |
| ip-10-0-131-138 | 210m | 10% | 1621Mi | 22% | |
| ip-10-0-133-163 | 151m | 7% | 1267Mi | 17% | |
| ip-10-0-138-0 | 340m | 17% | 2839Mi | 40% | Scale-up recente (6h33m) |
| ip-10-0-139-187 | 222m | 5% | 705Mi | 4% | Scale-up recente (5min) |
| ip-10-0-140-208 | 96m | 4% | 1251Mi | 38% | Scale-up recente (6h33m) |
| ip-10-0-142-118 | 213m | 11% | 2899Mi | **88%** | **P1: Risco OOMKill** |
| ip-10-0-148-204 | 365m | 9% | 4366Mi | 29% | |
| ip-10-0-152-132 | 172m | 8% | 3648Mi | 51% | |
| ip-10-0-152-97 | 143m | 7% | 1418Mi | 43% | |
| ip-10-0-155-56 | 149m | 7% | 2006Mi | 28% | |
| ip-10-0-156-132 | 132m | 6% | 1344Mi | 19% | |
| ip-10-0-159-150 | 92m | 4% | 1362Mi | 41% | |

### Analise de Consumo

- **CPU medio:** ~7-8% — extremamente subutilizado
- **MEM media:** ~32% — moderada, mas com outlier critico
- **Node 142-118 a 88% MEM** (t3.medium 4GiB) — risco de OOMKill iminente
- 3 nodes recem-escalados (ip-10-0-139-187, ip-10-0-138-0, ip-10-0-140-208) indicam scale-up recente pelo cluster autoscaler

**Paradoxo:** CPU muito baixa (~7%) mas autoscaler escalou para 13 nodes. Causa provavel: requests de memoria inflados nos pods forcando scheduling em novos nodes apesar de CPU ociosa.

---

## 3. Pods Nao-Running

| Pod | Status | Age | Namespace |
|-----|--------|-----|-----------|
| linkerd-cni-gpmzf | Pending | 3h12m | linkerd-cni |
| linkerd-cni-sw76h | Pending | 3h10m | linkerd-cni |
| loki-canary-hthxm | Pending | 6h33m | staging-observability-monitoring |
| loki-canary-mfg2f | Pending | 18h | staging-observability-monitoring |

**Causa:** DaemonSets nao conseguem agendar em todos os nodes. Linkerd-cni e loki-canary sao DaemonSets que requerem 1 pod por node — provavelmente nodes com taints ou recursos insuficientes.

---

## 4. Custos MTD Marco 2026 (AWS Cost Explorer)

### Custo Diario

| Data | Custo | Obs |
|------|-------|-----|
| 2026-03-01 | $87.55 | Tax mensal incluso |
| 2026-03-02 | $39.99 | |
| 2026-03-03 | $37.28 | |
| 2026-03-04 | $40.10 | |
| 2026-03-05 | $39.42 | |
| 2026-03-06 | $40.17 | |
| 2026-03-07 | $38.74 | |
| 2026-03-08 | $38.43 | Sabado |
| 2026-03-09 | $39.04 | Domingo |
| 2026-03-10 | $26.01 | Parcial |
| **MTD Total** | **$426.72** | **10 dias** |

### Custo Medio e Forecast

- **Media diaria (excl tax):** ~$37.91/dia (dias 2-9)
- **Forecast Mar 2026:** ~$1,217/mes (31 dias x media + tax)
- **Budget mensal:** $807/mes
- **Desvio:** **+$410/mes (+51%)** — CRITICO

### Breakdown por Servico (MTD)

| Servico | Custo MTD | % Total |
|---------|-----------|---------|
| EC2 Compute | $206.89 | 48.5% |
| EC2 Other | $52.02 | 12.2% |
| Tax | $51.84 | 12.1% |
| VPC | $31.29 | 7.3% |
| EKS | $23.30 | 5.5% |
| CloudWatch | $21.36 | 5.0% |
| ELB | $20.98 | 4.9% |
| RDS | $9.36 | 2.2% |
| WAF | $3.14 | 0.7% |
| S3 | $2.99 | 0.7% |
| KMS | $2.14 | 0.5% |
| Secrets Manager | $1.13 | 0.3% |

**EC2 (Compute + Other) = 60.7%** do custo total — reflete diretamente os 13 nodes ativos.

---

## 5. FinOps Automation — Validacao 1o. Mes

### Lambda START

- **Status:** OPERACIONAL
- **Ultima execucao:** 2026-03-11T10:30:10
- **Configuracao de escala:** system=2, workloads=3, critical=2 (7 nodes total)

### Lambda STOP

- **Status:** OPERACIONAL
- **Ultima execucao:** 2026-03-10T23:00:12
- **EXCLUDED_NODE_GROUPS:** system, critical (conforme ADR-094)
- **RDS Stop:** k8s-platform-prod-postgresql

### Circuit Breaker

- **Estado:** CLOSED (saudavel)
- **Startup failures:** 0
- **Shutdown failures:** 0

### EventBridge Rules (5/5 ENABLED)

| Rule | Schedule | Funcao |
|------|----------|--------|
| finops-startup-staging | cron(30 10 ? * MON-FRI *) | Ligar cluster dias uteis 10:30 UTC |
| finops-shutdown-staging | cron(0 23 ? * MON-FRI *) | Desligar cluster dias uteis 23:00 UTC |
| finops-weekend-shutdown-staging | cron(0 3 ? * SAT *) | Desligar sabado 03:00 UTC |
| finops-snapshot-cleanup-staging-schedule | cron(0 3 ? * MON *) | Cleanup snapshots segunda |
| weekly-finops-report-staging-schedule | cron(0 12 ? * MON *) | Report semanal segunda |

### Eficacia da Automacao

**ACHADO P0 — Savings de weekend abaixo do esperado:**
- Custo sabado (Mar 8): $38.43
- Custo domingo (Mar 9): $39.04
- **Esperado em weekend:** $15-18/dia (com nodes desligados)
- **Realizado:** $38-39/dia — praticamente igual a dia util
- **Causa provavel:** EXCLUDED_NODE_GROUPS (system, critical) mantem 5+ nodes ativos no weekend, ou autoscaler re-escala workloads group antes do horario de shutdown

---

## 6. CloudWatch — Validacao Pos-Fix

- **EKS log types ativos:** api, audit, authenticator (3/3 conforme plano)
- **Removidos:** controllerManager, scheduler
- **Custo MTD CloudWatch:** $21.36 (10 dias)
- **Projecao mensal:** ~$66/mes
- **Custo Fev 2026:** ~$34/mes

**ACHADO P1 — Custo CloudWatch quase dobrou (+94%):**
- Apesar de reduzir log types de 5 para 3
- Causa provavel: 13 nodes (vs 9 em Fev) gerando ~44% mais metricas de Container Insights
- Custo de metricas escala linearmente com node count

---

## 7. Matriz de Achados e Riscos

| Sev | ID | Achado | Impacto Estimado | Acao Requerida |
|-----|----|--------|------------------|----------------|
| P0 | F-001 | 13 nodes (all groups at/near max) | +$400+/mes vs 9 nodes | Investigar causa do scale-up; avaliar reducao de max |
| P0 | F-002 | Forecast Mar ~$1,217 vs $807 budget (+51%) | +$410/mes desvio | VPA urgente + bin-packing review |
| P0 | F-003 | Weekend costs $38-39/dia (vs $15-18 esperado) | ~$80-96/mes perdidos | Revisar EXCLUDED_NODE_GROUPS + scheduling |
| P1 | F-004 | CloudWatch $66/mes projetado (era $34) | +$32/mes (+94%) | Verificar Container Insights; correlacao com node count |
| P1 | F-005 | Node 142-118 a 88% MEM | Risco OOMKill | Identificar pods; considerar drain + rebalance |
| P2 | F-006 | 4 pods Pending (linkerd-cni + loki-canary) | DaemonSets incompletos | Verificar taints/tolerations nos nodes novos |

---

## 8. Acoes Recomendadas (Priorizadas)

### P0 — Imediato

1. **Investigar scale-up para 13 nodes** — Identificar quais pods/requests estao forcando o autoscaler. Hipotese: memory requests inflados + bin-packing ineficiente.
2. **Avaliar reducao de max node group** — workloads max=6 para 4, system max=4 para 3, para forcar bin-packing e reduzir custo.
3. **VPA urgente** — Aplicar VPA para top consumers de memoria e reduzir requests, permitindo consolidacao em menos nodes.
4. **Revisar eficacia de weekend shutdown** — Entender por que custo de fim de semana nao cai. Verificar se nodes excluded estao gerando custo significativo.

### P1 — Esta Semana

5. **Investigar CloudWatch** — Verificar se Container Insights esta ativo e quantas custom metrics estao sendo geradas por node.
6. **Resolver node 142-118 (88% MEM)** — Listar pods nesse node, identificar top consumers, avaliar drain.
7. **Resolver linkerd-cni Pending pods** — Verificar se nodes novos tem tolerations corretas para DaemonSet.

### P2 — Proximo Sprint

8. **Resolver loki-canary Pending** — Avaliar se DaemonSet tem resources requests compativeis com nodes disponiveis.

---

## 9. Comparativo com Baseline

| Metrica | Fev 2026 | Mar 2026 (projecao) | Delta | Sentido |
|---------|----------|---------------------|-------|---------|
| Nodes | 9 | 13 | +44% | Pior |
| Pods | 209 | 234 | +12% | Neutro |
| Custo mensal | ~$807 | ~$1,217 | +51% | Pior |
| CloudWatch | $34/mes | $66/mes | +94% | Pior |
| Weekend savings | $15-18/dia | $38-39/dia | ~0% | Pior |
| FinOps Lambda | Operacional | Operacional | -- | Estavel |
| Circuit Breaker | N/A | CLOSED | -- | Bom |

**Conclusao:** O ambiente esta operacionalmente saudavel (234 pods, 0 CrashLoop) mas financeiramente deteriorado. O crescimento de 9 para 13 nodes e o principal driver de custo. A automacao FinOps funciona corretamente mas nao compensa o aumento de consumo. Acao imediata necessaria em VPA e bin-packing para reverter a tendencia.

---

## Metadados

- **Data do exame:** 2026-03-11
- **Ferramentas:** kubectl top nodes, kubectl get pods, aws ce get-cost-and-usage, aws lambda list-functions, aws events list-rules
- **Referencia anterior:** MEMORY.md (savings baseline Fev 2026)
