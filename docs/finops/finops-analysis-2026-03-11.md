# Analise FinOps — Exame Ambiente AWS (2026-03-11)

> **Cluster:** k8s-platform-prod (EKS 1.34) | **Region:** us-east-1 | **Account:** 891377105802
> **Analista:** Mesa Tecnica FinOps (4 agentes) | **Data:** 2026-03-11
> **Proxima revisao:** 2026-03-18

---

## 1. Resumo Executivo

O ambiente AWS apresenta **overrun de 70% sobre o budget** ($1,370 forecast vs $807 budget). Os savings realizados ate o momento totalizam **R$ 57.461/ano (92.7% da meta de R$ 62K)**, porem o crescimento de custos com node groups e servicos auxiliares (CloudWatch, NAT, ELB) demanda acao imediata.

O exame identificou **R$ 80-100K/ano em oportunidades adicionais** distribuidas em 4 prioridades (P0-P3), com potencial para trazer o forecast mensal abaixo do budget em 60-90 dias.

### KPIs FinOps

| KPI | Valor Atual | Meta | Status |
|-----|-------------|------|--------|
| Budget Mensal | $807 | $807 | -- |
| Forecast Mar/2026 | ~$1,370 | <= $807 | VERMELHO (+70%) |
| Custo MTD (10 dias) | ~$447 | ~$260 | VERMELHO |
| Savings Realizados | R$ 57.461/ano | R$ 62.000/ano | AMARELO (92.7%) |
| Savings Potenciais (pipeline) | R$ 80-100K/ano | -- | Em analise |
| Nodes Ativos | 12 | 7-9 | VERMELHO |
| Drift Terraform | 1 (system max_size) | 0 | AMARELO |
| DLM Policies | Possivelmente inoperantes | 3 ativas | VERMELHO |

---

## 2. Custos MTD por Servico (01-10 Mar 2026, dados reais Cost Explorer)

| Servico | Custo MTD | % Total | Forecast Mes | Observacao |
|---------|-----------|---------|--------------|------------|
| EC2 Compute | $216.66 | 48.5% | ~$671 | 12 nodes ativos |
| EC2 Other (EBS, IPs) | $54.45 | 12.2% | ~$169 | 33 volumes, 10 EIPs |
| Tax | $55.41 | 12.4% | ~$55 | Mensal fixo |
| VPC (NAT Gateway) | $32.43 | 7.3% | ~$100 | 2 NATs ativas |
| EKS Control Plane | $24.00 | 5.4% | ~$74 | Custo fixo |
| CloudWatch | $22.19 | 5.0% | ~$69 | 98.9% VendedLog-Bytes |
| ELB | $21.66 | 4.8% | ~$67 | 4 ALBs + 1 NLB |
| RDS | $9.91 | 2.2% | ~$31 | PostgreSQL staging |
| WAF | $3.14 | 0.7% | ~$10 | WebACL ativo |
| S3 | $2.99 | 0.7% | ~$9 | Loki + Velero + artifacts |
| KMS | $2.14 | 0.5% | ~$7 | Vault + ESO |
| Secrets Manager | $1.13 | 0.3% | ~$4 | ESO secrets |
| Outros | $0.89 | 0.2% | ~$3 | ECR, Cost Explorer |
| **TOTAL** | **~$447** | **100%** | **~$1,370** | **+70% over budget** |

### Custo Diario EC2 (Mar 1-10)

| Dia | EC2 Compute | Observacao |
|-----|-------------|------------|
| Mar 01 | $20.22 | Sabado |
| Mar 02 | $21.72 | Domingo |
| Mar 03 | $19.06 | Segunda |
| Mar 04 | $22.22 | Terca — GitLab work |
| Mar 05 | $21.88 | Quarta |
| Mar 06 | $21.63 | Quinta |
| Mar 07 | $22.38 | Sexta |
| Mar 08 | $22.21 | Sabado — weekend cost NAO reduzido |
| Mar 09 | $21.49 | Domingo — weekend cost NAO reduzido |
| Mar 10 | $23.85 | Segunda |
| **Media** | **$21.67/dia** | |

---

## 3. Node Groups — Estado Atual (dados reais AWS)

| Node Group | Instance Type | Desired (AWS) | Min | Max (AWS) | Max (TF) | Custo/mes |
|------------|--------------|---------------|-----|-----------|----------|-----------|
| system | t3.medium | 4 | 2 | 4 | 6 | $121 |
| workloads | t3.large | 6 | 2 | 6 | 9 | $364 |
| critical | t3.xlarge | 2 | 2 | 4 | 4 | $243 |
| **TOTAL** | | **12** | **6** | **14** | **19** | **$728** |

**DRIFT detectado:** system max_size: AWS=4, TF=6. Lifecycle ignore_changes em desired_size esta correto.

---

## 4. Oportunidades P0 — Acao Imediata (esta semana)

| # | Acao | Savings/ano (R$) | Esforco | Status |
|---|------|-------------------|---------|--------|
| P0-001 | Remover log type `api` do EKS (audit+authenticator suficientes) | R$ 1.800-2.520 | 15min TF | APLICADO (main.tf) |
| P0-002 | Migrar ultimo volume gp2→gp3 (vol-07a678e436d487abc) | R$ 25 | 5min | APLICADO (modifying) |
| P0-003 | Deletar 21 snapshots de migracao expirados (163 GB) | R$ 600 | 15min | EM EXECUCAO |
| P0-004 | Fix NLB RabbitMQ recriado → ClusterIP | R$ 384 | 30min | PENDENTE |
| **Subtotal P0** | | **R$ 2.809-3.529** | **~1h** | |

---

## 5. Oportunidades P1 — Curto Prazo (1-2 semanas)

| # | Acao | Savings/ano (R$) | Esforco | Pre-requisito |
|---|------|-------------------|---------|---------------|
| P1-001 | Fix Weekend Gap: suspender autoscaler no STOP + min=0 workloads | R$ 7.600 | 4h | Lambda code change |
| P1-002 | Consolidar ALBs 4→2 (shared ingress groups) | R$ 3.456-6.912 | 8h | DNS update |
| P1-003 | Consolidar NAT Gateway 2→1 (staging, HA nao requerido) | R$ 2.412 | 2h | Route table update |
| P1-004 | Fix DLM tag matching (174 snapshots sem ManagedBy=DLM) | R$ 300-600 | 2h | Tag audit |
| P1-005 | S3 lifecycle em fct-0001/0002 (88.5 GB sem lifecycle) | R$ 60-180 | 1h | Bucket audit |
| P1-006 | Remover VPC Endpoint ELB (baixo uso) | R$ 518 | 30min | Validar uso |
| **Subtotal P1** | | **R$ 14.346-18.222** | **~18h** | |

---

## 6. Oportunidades P2 — Medio Prazo (1-2 meses)

| # | Acao | Savings/ano (R$) | Esforco | Pre-requisito |
|---|------|-------------------|---------|---------------|
| P2-001 | VPA Rightsizing producao (deploy dia 1 → rightsizing dia 8) | R$ 15.000-25.000 | 8h | Prod online |
| P2-002 | Reduzir workloads nodes 6→4 (pos-VPA) | R$ 8.736 | 4h | VPA data |
| P2-003 | Spot Instances workloads (50% mix, 62% savings/node) | R$ 8.208 | 8h | PDB validado |
| P2-004 | Savings Plans 1yr No-Upfront (system + critical) | R$ 7.920 | 1h | 30d prod |
| P2-005 | RDS Reserved Instance 1yr | R$ 3.024 | 15min | Confirmacao permanencia |
| **Subtotal P2** | | **R$ 42.888-52.888** | **~21h** | |

---

## 7. Oportunidades P3 — Longo Prazo (Q2-Q3)

| # | Acao | Savings/ano (R$) | Esforco | Pre-requisito |
|---|------|-------------------|---------|---------------|
| P3-001 | Graviton ARM64 migration (m6g/m7g, 20-40% savings) | R$ 5.760-10.800 | 40h | Multi-arch images |
| P3-002 | Karpenter (replace static ASGs, melhor bin-packing) | R$ 4.000-7.000 | 40h | Estabilizacao cluster |
| **Subtotal P3** | | **R$ 9.760-17.800** | **~80h** | |

---

## 8. Weekend Gap Analysis

### Root Cause Confirmado

Lambda STOP executa corretamente (shutdown_failures=0), mas:

1. **11 DaemonSets** forcam pods em cada node (aws-node, calico, ebs-csi, kube-proxy, linkerd-cni, promtail, node-exporter, loki-canary, velero node-agent, harbor-registry-config, cluster-autoscaler)
2. Lambda STOP reduz `desired` para `min` nos node groups
3. DaemonSets criam pods Pending que disparam cluster autoscaler a **re-escalar imediatamente**
4. Resultado: custo weekend $38-39/dia vs esperado $15-18/dia

### Fix Proposto

```
Lambda STOP (sexta 20h BRT):
  1. kubectl scale deployment cluster-autoscaler -n kube-system --replicas=0
  2. aws eks update-nodegroup-config workloads → minSize=0, desiredSize=0
  3. aws eks update-nodegroup-config critical → minSize=0, desiredSize=0
  4. system → desiredSize=2 (minimo para DNS, monitoring)

Lambda START (segunda 07h30 BRT):
  1. Restaurar scaling configs originais
  2. kubectl scale deployment cluster-autoscaler -n kube-system --replicas=1
```

**Economia estimada:** ~$20/dia × 104 dias/ano = **R$ 12.480/ano**

---

## 9. Achados Novos (2026-03-11)

### ACHADO-001: NLB RabbitMQ recriado (P0)

- **Root cause:** Service `rabbitmq-management-external` tipo LoadBalancer no TF (`modules/rabbitmq/main.tf` linhas 237-295)
- NLB deletado manualmente em Fev, mas TF reconciliou e recriou em 2026-03-10
- **AGRAVANTE:** NLB configurado como internet-facing com AMQP 5672 exposto publicamente
- **Fix:** Patch para ClusterIP + remover annotations NLB do TF

### ACHADO-002: DLM Policies possivelmente inoperantes (P1)

- 3 DLM policies criadas em 2026-02-27
- 174 snapshots existentes, **nenhum** com tag `ManagedBy=DLM`
- Provavel mismatch de target_tags nos volumes
- Snapshots acumulando sem lifecycle

### ACHADO-003: Drift TF system max_size (P0)

- TF declara max_size=6, AWS mostra max_size=4
- Provavelmente TF apply nunca executado apos mudanca no .tf
- Risco: proximo apply pode alterar max_size inesperadamente

### ACHADO-004: 1 volume gp2 remanescente (P0)

- vol-07a678e436d487abc (5 GB gp2) — MIGRADO para gp3 nesta sessao

### ACHADO-005: CloudWatch dominado por VendedLog-Bytes (P0)

- 98.9% do custo CW = ingestion de logs EKS
- Log group `/aws/eks/k8s-platform-prod/cluster` = 3.9 GB (7d retention)
- Log type `api` removido nesta sessao (audit+authenticator suficientes)
- Economia esperada: ~50% do custo CW

---

## 10. Savings Pipeline Consolidado

| Horizonte | Savings/ano (R$) | Timeline | Esforco |
|-----------|-------------------|----------|---------|
| **Ja realizados** | **R$ 57.461** | Concluido | -- |
| P0 (imediato) | R$ 2.809-3.529 | < 1 semana | ~1h |
| P1 (curto prazo) | R$ 14.346-18.222 | 1-2 semanas | ~18h |
| P2 (medio prazo) | R$ 42.888-52.888 | 1-2 meses | ~21h |
| P3 (longo prazo) | R$ 9.760-17.800 | Q2-Q3 | ~80h |
| Weekend fix | R$ 12.480 | 2 semanas | ~4h |
| **Pipeline Total** | **R$ 82.283-104.919** | | ~124h |
| **Grand Total** | **R$ 139.744-162.380** | | |

**Meta original:** R$ 62.000/ano — **superada em 125-162%** considerando pipeline completo.

---

## 11. Tabela de Acoes Prioritizadas

| # | Acao | Prio | Savings/ano | Esforco | Owner | Status |
|---|------|------|-------------|---------|-------|--------|
| 1 | Log type `api` removido do EKS | P0 | R$ 1.800-2.520 | 0h | SRE | APLICADO |
| 2 | Volume gp2→gp3 migrado | P0 | R$ 25 | 0h | Platform | APLICADO |
| 3 | Deletar 21 snapshots migracao | P0 | R$ 600 | 15min | Platform | EM EXECUCAO |
| 4 | Fix NLB RabbitMQ → ClusterIP | P0 | R$ 384 | 30min | Platform | PENDENTE |
| 5 | Fix Weekend Gap (Lambda STOP) | P1 | R$ 12.480 | 4h | Platform | PENDENTE |
| 6 | Consolidar ALBs 4→2 | P1 | R$ 3.456-6.912 | 8h | Platform | PENDENTE |
| 7 | NAT Gateway 2→1 | P1 | R$ 2.412 | 2h | Platform | PENDENTE |
| 8 | Fix DLM tag matching | P1 | R$ 300-600 | 2h | Platform | PENDENTE |
| 9 | S3 lifecycle fct buckets | P1 | R$ 60-180 | 1h | Platform | PENDENTE |
| 10 | Remover VPC Endpoint ELB | P1 | R$ 518 | 30min | Platform | PENDENTE |
| 11 | VPA Rightsizing producao | P2 | R$ 15-25K | 8h | SRE | PENDENTE |
| 12 | Reduzir workloads 6→4 | P2 | R$ 8.736 | 4h | Platform | BLOCKED (VPA) |
| 13 | Spot Instances workloads | P2 | R$ 8.208 | 8h | Platform | PENDENTE |
| 14 | Savings Plans 1yr | P2 | R$ 7.920 | 1h | FinOps | PENDENTE |
| 15 | RDS Reserved Instance | P2 | R$ 3.024 | 15min | FinOps | PENDENTE |
| 16 | Graviton ARM64 | P3 | R$ 5.760-10.800 | 40h | Platform | Backlog |
| 17 | Karpenter POC | P3 | R$ 4-7K | 40h | Platform | Backlog |

---

## 12. Proxima Revisao

- **Data:** 2026-03-18
- **Foco:** Validar P0 concluidos + progresso P1
- **Gate de sucesso:** Forecast Mar <= $1,100 (reducao 20% vs atual)
- **Metricas:** CloudWatch cost delta, DLM snapshot count, NLB status, weekend cost/dia

---

> **Preparado por:** Mesa Tecnica FinOps (4 agentes: AWS Specialist, Observability & SRE, Networking, Storage)
> **Fonte de dados:** AWS Cost Explorer API, kubectl cluster state, Terraform state
> **Documento anterior:** [finops-status-2026-03-11.md](finops-status-2026-03-11.md)
