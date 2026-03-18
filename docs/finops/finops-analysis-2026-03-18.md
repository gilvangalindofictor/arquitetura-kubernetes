# FinOps Analysis — Plataforma k8s-platform-prod

**Data:** 2026-03-18 | **Framework:** executor-terraform.md | **Fonte:** AWS Cost Explorer REAL (CLI 2026-03-17)
**Cluster:** k8s-platform-prod (891377105802 / us-east-1) | **Fase:** Desenvolvimento ativo — staging operacional, prod em 7 fases
**Compliance:** BACEN BCB 85/2021 | Circular 4.557/2021

---

## Executive Summary

O custo estrutural da plataforma é **$39.82/dia = ~$1.194/mês** (excluindo anomalia dia 1), representando **+48% acima do budget aprovado de $807/mês**. O FinOps Lambda está funcional mas entrega $9.72/dia de saving real (vs $22/dia projetado originalmente — erro de premissa corrigido). A plataforma está em fase de desenvolvimento ativo com todos os serviços de staging rodando simultaneamente (GitLab, Harbor, ArgoCD, Vault, Keycloak, Loki, Tempo, Prometheus, SonarQube, Backstage, Linkerd), o que explica o custo elevado. A otimização principal viável agora é Karpenter + Spot (economia estimada $140-180/mês) e redução de CloudWatch ($10-15/mês). A decisão de VPN é clara: **Cenário B (FortiGate site-to-site, ~$37/mês) é 7x mais barato** que AWS Client VPN ($263/mês). No horizonte de 12 meses pós go-live com plataforma estabilizada e otimizações aplicadas, o custo projetado cai para **$650-750/mês** — dentro ou próximo do budget original.

---

## 1. Diagnóstico do Custo Atual

### 1.1 Por que fins de semana = dias úteis (análise do padrão)

**Dados observados (fonte: AWS CE real):**

| Período | Custo/dia | Padrão |
|---------|-----------|--------|
| Dias úteis (seg-sex) | $37-43/dia | Variação ativa (Lambda shutdown noturno) |
| Fins de semana (sáb-dom) | $38-40/dia | Quase igual aos dias úteis |

**Root cause do padrão plano (3 fatores identificados):**

**Fator 1 — Custos fixos dominam (~75% do custo total)**

O breakdown por serviço revela que a maioria dos itens são custos quasi-fixos, não variáveis com o uso:

| Serviço | Custo/dia estimado | Tipo |
|---------|--------------------|------|
| EC2 Compute (nodes "system" + RDS baseline) | ~$15-17/dia | **Semi-fixo** — nodes system rodam 24/7 |
| EKS Control Plane | ~$2.40/dia | **Fixo** — $73/mês independente |
| CloudWatch | ~$2.50-3.00/dia | **Semi-fixo** — logs continuam gerando |
| VPC/NAT | ~$3.00/dia | **Fixo** — NAT Gateway tem custo por hora |
| ELB/ALBs | ~$1.60/dia | **Fixo** — ALBs cobrados por hora |
| KMS, Secrets Manager, S3 | ~$0.50/dia | **Fixo** |

**Total custos fixos estimados:** ~$25-27/dia (~$750-810/mês) — este valor **não varia com shutdown**.

**Fator 2 — Lambda economiza apenas nos nodes variáveis**

O Lambda shutdown para nodes `workloads` e `critical` (~7 nodes variáveis), mas os nodes `system` (3x t3.medium) permanecem rodando 24/7. O saving confirmado é de **$9.72/dia** (RC-1 confirmado em 2026-03-17):
- 7 nodes × $0.04161/hr × ~5.6h economia noturna + RDS stop + ALB redução
- Sábado com Lambda ativo mostrou baseline $39.07 — evidência: saving existe mas é pequeno relativo ao total

**Fator 3 — NAT Gateway cobra por hora (não por tráfego único)**

O custo de NAT inclui $0.045/hora por gateway (2 NAT GWs confirmados = $0.09/hora = $2.16/dia fixo) + data transfer. Mesmo sem workloads ativos, o NAT Gateway cobra a taxa horária — fins de semana não reduzem esse custo.

**Conclusão do padrão:** O custo de fim de semana ser igual ao dia útil é matematicamente correto. Com ~$27/dia de custos fixos e $9.72/dia de saving máximo possível via Lambda, a variação máxima teórica é apenas 24% — confirmado pelos dados reais (dias úteis $37-43, fins de semana $38-40).

---

### 1.2 Breakdown real + responsáveis pelo custo elevado

**Análise por serviço com responsável técnico:**

| Serviço | MTD 17 dias | Projetado/mês | Principal responsável | Otimizável agora? |
|---------|-------------|---------------|----------------------|-------------------|
| **EC2 Compute** | $362.79 | **~$661/mês** | Nodes system 24/7 + workloads on-demand | Sim (Spot/Karpenter) |
| **EC2-Other** (EBS, EIP, snapshots) | $86.52 | **~$158/mês** | PVCs dos serviços + snapshots DLM Velero | Parcialmente |
| **VPC/NAT** | $52.66 | **~$96/mês** | 2 NAT GWs ($65/mês base) + data transfer | Baixo (VPC Endpoints) |
| **CloudWatch** | $41.51 | **~$75/mês** | EKS audit logs + Kyverno webhooks + ESO syncs | Sim ($10-15/mês saving) |
| **EKS Control Plane** | $40.60 | **~$73/mês** | Fixo — 1 cluster | Não |
| **ELB** | $33.79 | **~$62/mês** | 4 ALBs ativos (2 internet-facing, 1 internal, 1 NLB) | Já otimizado (de 6 para 4) |
| **RDS** | $18.91 | **~$34/mês** | RDS PostgreSQL staging t3.micro (prod t3.medium Multi-AZ não incluso?) | Verificar |
| **WAF** | $5.47 | **~$10/mês** | 1 WebACL com 5 regras | Fixo |
| **S3** | $5.32 | **~$10/mês** | Velero backups + WAF logs + Lambda code | Pequeno |
| **KMS** | $3.76 | **~$7/mês** | CMKs para EKS, RDS, S3 | Verificar chaves órfãs |
| **AWS CE** | $2.06 | **~$4/mês** | Acesso à API de Cost Explorer | Fixo |
| **Secrets Manager** | $1.98 | **~$4/mês** | Segredos platform | Fixo |
| Tax | $90.72 | **~$166/mês** | — | — |
| **TOTAL** | **~$747** | **~$1.360/mês** | | |

**Nota RDS:** O valor de $34/mês para RDS é suspeito — é apenas o staging (t3.micro, Multi-AZ=false). O RDS de produção (db.t3.medium, Multi-AZ=true, declarado no TF) se estiver provisionado adicionaria ~$127-180/mês. Verificar com `aws rds describe-db-instances` se `k8s-platform-prod-postgresql-prod` existe.

---

## 2. Oportunidades Imediatas (Dev-Phase)

### Tabela Priorizada — Impacto × Esforço × Risco

| # | Serviço | Ação Específica | Economia/mês | Risco | Esforço | Status |
|---|---------|----------------|--------------|-------|---------|--------|
| **1** | EC2 Compute | Karpenter + Spot para node group `workloads` (ETL, Loki, Tempo, Grafana, GitLab Runner) | **$140-180/mês** | Médio | >4h (já em demanda 2026-03-17) | Planejado |
| **2** | CloudWatch | Reduzir EKS log types (5→3: remover scheduler+controllerManager) + retention 30→7d | **$10-15/mês** | Nenhum | <1h | A executar |
| **3** | VPC/NAT | VPC Endpoints para S3 + ECR (elimina data transfer NAT para esses destinos) | **$8-15/mês** | Nenhum | 1-4h | Pendente |
| **4** | EC2-Other | Auditoria de EBS volumes `available` (orphan volumes) — AWS Config Rule + lifecycle | **$5-10/mês** | Nenhum | 1-4h | Config Rule pendente |
| **5** | EC2 Compute | Prefix delegation VPC CNI (t3.medium: 17→110 pods/node) — evitar scale-out desnecessário | **$5-8/mês** | Baixo | 1-4h | Já em demanda 2026-03-17 |
| **6** | KMS | Inventariar CMKs — verificar chaves sem uso/sem uso há >90 dias ($1/chave/mês) | **$1-3/mês** | Nenhum | <1h | Fácil |
| **7** | FinOps Lambda | Adicionar regra EventBridge shutdown domingo 23:00 UTC (RC-2 confirmado 2026-03-17) | **$9.72/domingo** | Nenhum | <1h | Pendente — GAP-LAMBDA-RC2 |
| **8** | CloudWatch | Auditoria de Containers Insights (confirmar desabilitado) + RDS Enhanced Monitoring | **$5-8/mês** | Nenhum | <1h | Verificação pendente |

**Potencial total imediato:** ~$183-239/mês adicional de saving

---

### 2.1 EC2 Compute ($661/mês) — Análise Detalhada

**Por que o Lambda não resolve o problema:**
O FinOps Lambda salva $9.72/dia nos nodes variáveis. A oportunidade maior está em otimizar os **nodes que rodam 24/7**:

| Node Group | Tipo | Custo/mês (On-Demand) | Pode Spot? |
|------------|------|----------------------|------------|
| system (3 nodes) | t3.medium | ~$105/mês | Não (plataforma crítica) |
| workloads (4 nodes) | t3.large | ~$240/mês | Sim (ETL, observabilidade, runners) |
| Total nodes base | 7 nodes | ~$345/mês | — |

**Karpenter + Spot para workloads** (conforme demanda 2026-03-17-revisao-capacidade-karpenter.md):

| Cenário | Custo nodes/mês | Saving vs atual |
|---------|-----------------|-----------------|
| On-Demand puro (atual) | ~$345/mês | baseline |
| System On-Demand + Workloads Spot | ~$180/mês | **-$165/mês (-48%)** |
| + Karpenter bin-packing + consolidation | ~$140/mês | **-$205/mês (-59%)** |

**Risco operacional:** Spot pode ser interrompido com 2 min de aviso. Workloads candidatos a Spot (jobs ETL Hatch, Loki, Tempo, Grafana, GitLab Runner) são tolerantes à interrupção (jobs idempotentes, componentes stateless ou com PVC backup).

**Gate de sucesso:** Karpenter NodePool ativo + pelo menos 2 nodes Spot confirmados + zero downtime em workloads críticos.

---

### 2.2 CloudWatch ($75/mês) — O que está gerando custo

**Root cause confirmado (análise 2026-03-10, cloudwatch-cost-analysis-2026-03-10.md):**

A plataforma está gerando volume alto de logs/métricas via 5 fontes sobrepostas:

1. **EKS Control Plane Logs (5 tipos ativos):** Todos os tipos habilitados (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`). O `scheduler` e `controllerManager` têm baixo valor diagnóstico em steady-state — remover economiza 30-40% do volume. **Saving: $3-4/mês.**

2. **Kyverno admission webhooks:** ~50 webhooks/min × 60min × 24h × 30d = 2.16M eventos/mês gerando audit logs. Não é removível (compliance), mas pode ser filtrado no audit policy. **Saving potencial: $4-6/mês (médio prazo).**

3. **ESO sync loops:** 11 ExternalSecrets × 1 sync/min = 15.840 API calls/dia → audit logs. Reduzir `refreshInterval` de 1min para 5min pode reduzir 80% do volume ESO. **Saving: $1-2/mês.**

4. **Retention 30d:** Log group EKS em 30d de retenção — reduzir para 7d reduz storage. **Saving: $2-3/mês.**

5. **Container Insights (verificar):** Se ativo ($5-8/mês) — não confirmado via TF mas precisa de check na AWS.

**Ações imediatas sem risco:**
```
A1: Reduzir EKS log types 5→3 (remover scheduler+controllerManager) → $3-4/mês
A2: Retention EKS log group 30d→7d → $2-3/mês
A3: Confirmar Container Insights desabilitado → $0 se não ativo
A4: ESO refreshInterval 1min→5min → $1-2/mês
TOTAL: $6-9/mês (saving conservador sem risco operacional)
```

---

### 2.3 VPC/NAT ($96/mês) — VPC Endpoints

**Composição atual:**
- 2 NAT Gateways (us-east-1a + us-east-1b): $0.045/hora × 2 × 720h = **$64.80/mês fixo**
- Data transfer via NAT: **~$31/mês variável**

**Oportunidade — VPC Endpoints:**

| Serviço | Tipo de Endpoint | Custo do Endpoint | Saving NAT data transfer |
|---------|-----------------|-------------------|--------------------------|
| S3 | Gateway (gratuito) | $0 | Estima-se $5-8/mês (Velero backups, Loki, Tempo, Harbor registry) |
| ECR API | Interface ($0.01/GB) | ~$1-2/mês | $3-5/mês (Harbor pulls, pod starts) |
| ECR DKR | Interface ($0.01/GB) | ~$1-2/mês | $2-4/mês (imagens Docker) |
| Secrets Manager | Interface | ~$0.5/mês | $1-2/mês (ESO sync) |

**Nota:** S3 Gateway Endpoint já foi aplicado (2026-02-12, saving R$ 900/ano confirmado). Verificar se ECR VPC Endpoints foram adicionados.

**Saving líquido adicional (ECR + Secrets Manager endpoints):** ~$5-9/mês

**Risco:** Nenhum — endpoints privados apenas adicionam rotas privadas, não removem acesso público.

---

### 2.4 ELB ($62/mês) — Estado Atual

**ALBs ativos confirmados (2026-03-18):**

| ALB | Scheme | WAF | Custo estimado |
|-----|--------|-----|----------------|
| k8s-platformstaging-00e0ecf3b4 | internet-facing | Sim | ~$16/mês |
| k8s-gitlabstaging-da5a4e8c6d | internet-facing | Não | ~$16/mês |
| k8s-stagingp-keycloak-0dbafff841 | internet-facing | Não | ~$16/mês |
| k8s-backstagestaging-c827d564e5 | internal | N/A | ~$14/mês |

**Situação:** 4 ALBs é o mínimo técnico dado o estado atual (GitLab precisa de ALB separado por razões de routing + KAS WebSocket). O custo já foi otimizado em 2026-03-11 (de 6 para 4 ALBs, saving R$ 2.009/ano confirmado).

**IngressGroup já implementado?** Keycloak separado em ALB próprio pode indicar que o IngressGroup não foi usado. Se Keycloak for movido para o ALB platform-staging via `alb.ingress.kubernetes.io/group.name: shared-platform`, economiza ~$16/mês. **Risco:** Médio (requere testar routing sem quebrar sessões OIDC).

**Oportunidade restante:** Consolidar keycloak-staging no platform-staging via IngressGroup → **saving ~$16/mês**. Avaliar impacto em sessões OIDC antes.

---

### 2.5 EC2-Other ($158/mês) — EBS, EIPs, Snapshots

**Composição estimada:**

| Item | Custo estimado | Ação |
|------|---------------|------|
| EBS volumes (PVCs ativos) | ~$60-80/mês | Dimensionar via VPA antes de reduzir |
| EBS snapshots (DLM Velero) | ~$20-30/mês | Lifecycle 30d Velero OK; verificar snapshots manuais |
| EIPs (Elastic IPs alocados) | ~$5-10/mês | Auditar EIPs não associados ($0.005/hora cada) |
| Data transfer EC2 inter-AZ | ~$20-30/mês | Reduzir com affinity rules (pods no mesmo AZ que dados) |
| EBS IOPS (gp3 aprovisionados) | ~$10-15/mês | Verificar se IOPS acima de 3000 são necessários |

**Ação imediata:** `aws ec2 describe-addresses --filter "Name=association-id,Values=''"` — EIPs não associados cobram $3.65/mês cada.

---

### 2.6 KMS ($7/mês) — Inventário de Chaves

**Custo KMS:** $1/chave/mês (CMKs customer-managed) + $0.03/10.000 chamadas.

Com $7/mês, existem aproximadamente 5-7 CMKs ativas. Verificar:
- CMK para EKS secrets encryption (necessária)
- CMK para RDS (necessária)
- CMK para S3 Velero (necessária)
- CMKs de migração ou teste sem uso → deletar ($1/chave/mês cada)

**Ação:** `aws kms list-keys | jq '.Keys | length'` + verificar `LastUsedDate` via CloudTrail.

---

## 3. Roadmap de Otimização — Estabilização e Horizonte Temporal

### 3.1 Projeção de Custo em 3 Horizontes

```
PREMISSAS:
  - Taxa USD/BRL: R$ 5.80 (conservador)
  - Dev ativo (hoje): todos os serviços rodando, rebuilds frequentes, configurações over-provisioned
  - Pós Fase 7 (3-6 meses): ambiente prod estruturado, staging enxuto, workloads estáveis
  - 12 meses pós go-live: VPA enforcement, Spot otimizado, Reserved Instances, observabilidade lean
```

| Horizonte | Custo/mês (USD) | Custo/mês (BRL) | Budget atual | Delta |
|-----------|-----------------|-----------------|--------------|-------|
| **Março 2026 (dev ativo)** | **~$1.194/mês** | **~R$ 6.925** | $807 | +48% |
| **Pós Fase 7 — go-live prod (estimado Q3 2026)** | **~$870-1.000/mês** (c/ Karpenter+Spot+Savings Plans) | **~R$ 5.046-5.800** | $807 | +8-24% |
| **6 meses pós go-live (Q4 2026)** | **~$750-900/mês** | **~R$ 4.350-5.220** | $807 | -7% a +11% |
| **12 meses pós go-live (Q1 2027 — otimizado)** | **~$650-750/mês** | **~R$ 3.770-4.350** | $807 | -7% a -19% |

**Nota crítica sobre o budget:** O budget de $807/mês foi estabelecido antes do ambiente staging estar completamente operacional (17 namespaces, Linkerd mTLS, observabilidade full stack, etc). A revisão do budget para $900-1.000/mês durante a fase de desenvolvimento ativo é justificada e esperada — **não representa falha de FinOps, mas sim custo natural de uma plataforma enterprise em construção**.

---

### 3.2 Detalhamento das Otimizações por Horizonte

**Horizonte 1 — AGORA (dev-phase, impacto imediato):**

| Iniciativa | Saving/mês | Esforço | Gate |
|------------|-----------|---------|------|
| Karpenter + Spot workloads | $140-180 | >4h | Karpenter NodePool ativo + nodes Spot confirmados |
| CloudWatch A1+A2+A4 | $6-9 | <1h | `terraform plan` → 1 change, `apply` OK |
| VPC Endpoints ECR | $5-9 | 1-4h | NAT data transfer cai no CE |
| Lambda shutdown domingo | $10-15/mês | <1h | EventBridge rule domingo 23:00 UTC ativo |
| EIP orphan audit | $1-5 | <1h | Zero EIPs não associados |
| **Total estimado** | **$162-218/mês** | | |

**Horizonte 2 — Pós Fase 7 (go-live, 3-6 meses):**

| Iniciativa | Saving/mês | Timing |
|------------|-----------|--------|
| VPA enforcement (após 30d recomendações) | $50-80 | Após baseline estável |
| Savings Plans 1yr Compute (80% baseline) | $80-120 | Após VPA e rightsizing |
| Staging enxuto (só CI/CD essencial) | $100-150 | Quando prod assumir workloads |
| S3 Intelligent-Tiering (Harbor, Loki, Velero) | $5-10 | Imediato após Fase 7 |
| RDS Reserved Instance staging | $10-15 | Após confirmar que staging RDS é necessário 24/7 |
| CloudWatch lean (audit policy K8s) | $5-8 | 1 sprint após go-live |
| **Total estimado** | **$250-383/mês** | 3-6 meses pós go-live |

**Horizonte 3 — 12 meses pós go-live (fully optimized):**

| Iniciativa | Saving/mês | Timing |
|------------|-----------|--------|
| Graviton ARM64 (t4g + m7g para nodes system) | $30-50 | Q2/Q3 2027 |
| Karpenter consolidation máximo (bin-packing agressivo) | $20-40 | Após validação Spot 90d |
| CloudWatch → 100% Loki/Prometheus (desabilitar CW logs exceto compliance) | $20-30 | Após validação Loki |
| Reserved Instances RDS Multi-AZ (1yr no-upfront) | $25-40 | Após Multi-AZ validado e estável |
| **Total adicional** | **$95-160/mês** | 12 meses pós go-live |

---

### 3.3 Tabela de Evolução de Custos

```text
HOJE (Março 2026):
  Base sem otimizações:        ~$1.194/mês (dev ativo, 100% On-Demand)
  Com Karpenter + CW + Lambda: ~$980-1.030/mês  ← META IMEDIATA (saving ~$160-210/mês)

PÓS FASE 7 — GO-LIVE PROD (Q3 2026):
  Sem otimizações (base + delta prod):      ~$1.420-1.515/mês
  Com Karpenter+Spot + quick wins:          ~$1.210-1.320/mês
  Com staging enxuto + VPA:                 ~$990-1.080/mês
  Com Savings Plans 1yr Compute:            ~$870-1.000/mês  ← TARGET REALISTA

6 MESES PÓS GO-LIVE (Q4 2026):
  + Savings Plans consolidados:             ~$750-870/mês
  Target realista:             ~$650-750/mês  ← DENTRO DO BUDGET

12 MESES PÓS GO-LIVE (Q1 2027):
  + Graviton + Consolidation:  saving ~$50-90/mês adicional
  Target otimizado:            ~$460-580/mês
```

---

### 3.4 Delta Ambiente de Produção — Breakdown Detalhado

**Contexto:** Após a Fase 7 (go-live prod), o custo total inclui o baseline atual de staging (~$1.194/mês) mais o delta dos recursos exclusivos de produção. A estratégia de dados validada pela mesa técnica (2026-03-18) reduziu o delta de RDS de $136.99 para $124.18/mês.

| Item | Delta/mês | Observação |
| ---- | --------- | ---------- |
| **RDS Shared Multi-AZ** (db.t3.medium) | **+$124.18** | Estratégia híbrida mesa técnica: 1 instância shared, databases isolados. Saving de $12.81/mês vs 2 instâncias separadas |
| **ALB public prod** | +$16–20 | internet-facing com WAF + ACM; estimativa baseada nos ALBs staging atuais ($16/mês cada) |
| **ALB internal prod** | +$14–16 | internal scheme para ArgoCD, Grafana, Vault, SonarQube, Backstage |
| **VPN Gateway (Opção B — FortiGate site-to-site)** | +$37 | VGW $0.05/hr × 720h = $36.50/mês; sem custo por conexão individual |
| **EBS volumes prod** | +$20–40 | PVCs prod: Prometheus 30d retention (~50GB), Loki S3 backend (mínimo), Velero, Keycloak |
| **CloudWatch prod** | +$10–20 | EKS audit logs prod + Prometheus remote write (se ativo); reduzível com Loki migration |
| **Route53 + queries** | +$2–3 | Hosted zone $0.50/mês + queries DNS ~$1–2/mês (External-DNS automatizado) |
| **KMS + Secrets Manager prod** | +$3–5 | CMK prod (EKS, RDS, S3 prod) + segredos ESO prod |
| **Redis prod** | **+$0** | In-cluster (nodes existentes Karpenter); custo adicional ~$0 |
| **RabbitMQ prod VHost** | **+$0** | VHost isolado no cluster existente; sem recurso AWS adicional |
| **TOTAL DELTA PROD** | **~$226–315/mês** | Intervalo conservador vs otimizado |

**Nota Redis dedicado (obrigatório regulatório):**

Redis prod e staging são instâncias dedicadas por env — exigência de **BACEN BCB 85/2021** (segregação de dados de sessão) e **LGPD Art. 46** (medidas de segurança para dados pessoais). Ambas as instâncias rodam in-cluster via Redis Operator CRD nos nodes Karpenter existentes: **custo adicional AWS = $0**.

**Custo total estimado pós go-live (sem otimizações):**

```text
Base staging atual:    ~$1.194/mês
Delta prod:            ~$226-315/mês
Total bruto:           ~$1.420-1.515/mês
```

**Recomendação de revisão de budget:** Solicitar aprovação para **$1.000/mês até Fase 7 completa**, com compromisso de retorno a $807/mês ou abaixo quando a plataforma estiver em operação normal (Q3-Q4 2026).

---

## 4. Decisão VPN — Análise Financeira

### 4.1 Situação Atual

- **FortiNet:** Uso corporativo exclusivo para internet/home-office — sem tunnel AWS. FortiGate existe na empresa.
- **AWS Client VPN:** Não existe (`ClientVpnEndpoints: []` — confirmado 2026-03-18).
- **Acesso atual:** `windows-hosts.txt` com IPs dos ALBs + `kubectl port-forward` — insustentável para produção.
- **Serviços que precisam de VPN em prod:** ArgoCD, Grafana, Vault, SonarQube, Backstage, RabbitMQ (todos internal-only).

### 4.2 Comparativo Financeiro B vs C

| Item | Opção B: FortiGate Site-to-Site | Opção C: AWS Client VPN |
|------|--------------------------------|-------------------------|
| **Mecanismo** | FortiGate (já existe) ↔ AWS Virtual Private Gateway (VGW) | AWS Client VPN Endpoint + IAM Identity Center |
| **Custo AWS/mês** | VGW: ~$36.50/mês ($0.05/hr × 720h) | Endpoint: ~$73/mês + Associations 2 AZs: ~$146/mês + Connections: ~$0.05/hr/user |
| **Custo total base/mês** | **~$37/mês** | **~$219-263/mês** (sem conexões ativas) |
| **Custo adicional (infra FortiGate)** | $0 — FortiGate já existe | $0 — AWS-native |
| **Configuração** | 1 dia (FortiGate IKEv2 config + TF VGW) | 2-3 dias (PKI, ACM, TF module, SAML Keycloak) |
| **Ferramental engenheiros** | FortiClient (já instalado e conhecido) | AWS VPN Client (nova ferramenta) |
| **Autenticação** | Pre-shared key ou certificados (FortiGate nativo) | Certificate-auth ou SAML via IAM Identity Center |
| **Escalabilidade** | Limitada — site-to-site (todos que acessam o escritório entram) | Individual por engenheiro com MFA |
| **Auditoria** | FortiGate logs + VGW CloudWatch | CloudWatch VPN logs — mais granular |
| **BACEN compliance** | Satisfatório (acesso controlado por credenciais FortiNet) | Satisfatório (MFA por usuário) |
| **Dependência externa** | Requer FortiGate ativo/disponível | 100% AWS-native |

**Diferença de custo anual:**
```
Opção B: ~$37/mês × 12 = ~$444/ano
Opção C: ~$263/mês × 12 = ~$3.156/ano (sem conexões ativas)
Economia Opção B vs C: ~$2.712/ano (R$ 15.730/ano)
Fator: 7.1x mais barato
```

### 4.3 Recomendação FinOps Fundamentada

**Recomendação: Opção B (FortiGate site-to-site) para AGORA. Reavaliar Opção C quando escalar equipe.**

**Justificativa:**

1. **Custo:** Opção B é 7x mais barata. Numa fase de desenvolvimento ativo onde o custo já está 48% acima do budget, adicionar $263/mês de VPN quando $37/mês resolve o mesmo problema não é justificável.

2. **Velocidade:** FortiGate já está em produção. Configurar o tunnel IKEv2 no FortiGate + provisionar VGW via Terraform leva 1 dia. Opção C requer PKI, ACM, módulo TF client-vpn, e configuração SAML Keycloak (que ainda não tem URL pública).

3. **Dependência sequencial:** Opção C requer Keycloak com URL pública (`keycloak.prod.alvocard.com.br`) — isso é a **Fase 5** do plano de produção (blockeado pela delegação DNS externa). Opção B não tem essa dependência.

4. **Equipe pequena:** Para uma equipe pequena de engenheiros que já usa FortiClient diariamente, site-to-site é transparente — sem nova ferramenta ou novo fluxo de trabalho.

5. **Caminho de migração:** Opção B não impede Opção C no futuro. Quando a equipe escalar e MFA individual por usuário se tornar necessário (Entra ID federation completa), a Opção C pode ser adicionada sem remover o site-to-site.

**Quando reavaliar Opção C:**
- Equipe remota (sem acesso ao escritório com FortiGate) ultrapassar 5 pessoas
- CISO exigir MFA por usuário individual (não por escritório)
- Keycloak com URL pública estiver operacional (Fase 5 completa)

**Terraform — Opção B (VGW + Customer Gateway):**

```hcl
# modules/vpn-site-to-site/main.tf

resource "aws_vpn_gateway" "prod" {
  vpc_id          = var.vpc_id
  amazon_side_asn = 64512

  tags = {
    Name        = "prod-platform-vgw"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_customer_gateway" "fortinet" {
  bgp_asn    = 65000  # FortiGate ASN (configurar no FortiOS)
  ip_address = var.fortinet_public_ip  # IP público da sede
  type       = "ipsec.1"

  tags = {
    Name      = "fortinet-cgw"
    ManagedBy = "terraform"
  }
}

resource "aws_vpn_connection" "prod_to_fortinet" {
  vpn_gateway_id      = aws_vpn_gateway.prod.id
  customer_gateway_id = aws_customer_gateway.fortinet.id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = {
    Name        = "prod-platform-vpn-to-fortinet"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_vpn_gateway_route_propagation" "prod" {
  for_each       = toset(var.private_route_table_ids)
  vpn_gateway_id = aws_vpn_gateway.prod.id
  route_table_id = each.value
}

# Custo: $0.05/hora = ~$36.50/mês (VGW) — sem custo por conexão
```

---

## 5. Próximas Ações Priorizadas

### P0 — Imediato (< 1 semana, sem risco operacional)

| ID | Ação | Responsável | Gate | Saving |
|----|------|-------------|------|--------|
| **FIN-P0-01** | Adicionar EventBridge regra shutdown domingo 23:00 UTC (GAP-LAMBDA-RC2) | TF Specialist | EventBridge rule ativa; domingo seguinte custo cai $9.72 | $10-15/mês |
| **FIN-P0-02** | Reduzir EKS log types 5→3 (`scheduler` + `controllerManager` removidos) no TF | TF Specialist | `terraform plan` → 1 change, `terraform apply`, CE confirma redução CW | $3-4/mês |
| **FIN-P0-03** | Retention EKS log group `/aws/eks/k8s-platform-prod/cluster` 30d→7d | TF Specialist | `aws logs describe-log-groups` confirma 7d | $2-3/mês |
| **FIN-P0-04** | Confirmar Container Insights desabilitado (`aws eks list-addons`) | AWS Specialist | `amazon-cloudwatch-observability` não aparece na lista | $5-8/mês se ativo |
| **FIN-P0-05** | Auditar EIPs não associados e deletar | AWS Specialist | `aws ec2 describe-addresses` retorna 0 EIPs sem `association-id` | $1-5/mês |
| **FIN-P0-06** | Decisão: revisar budget para $1.000/mês durante fase dev ativa | Usuário/CTO | Budget aprovado formalmente | Clareza financeira |

### P1 — Curto prazo (1-2 semanas, esforço médio)

| ID | Ação | Responsável | Gate | Saving |
|----|------|-------------|------|--------|
| **FIN-P1-01** | Karpenter + Spot para node group `workloads` (conforme demanda 2026-03-17) | TF + AWS Specialist | NodePool Spot ativo; custo EC2 cai no CE | $140-180/mês |
| **FIN-P1-02** | Prefix delegation VPC CNI (t3.medium: 17→110 pods) + Terraform codificar | TF Specialist | `kubectl describe node` mostra `pods: 110` | Evita scale-out desnecessário ($5-8/mês) |
| **FIN-P1-03** | VPC Endpoints ECR API + ECR DKR (além do S3 já existente) | TF Specialist | NAT data transfer cai; Harbor pulls roteia via endpoint privado | $5-9/mês |
| **FIN-P1-04** | Provisionamento VPN Opção B (FortiGate site-to-site + VGW TF) | TF Specialist | Engenheiros acessam `argocd.prod.alvocard.com.br` via VPN | $0 adicional (vs $0 atual) |
| **FIN-P1-05** | Consolidar ALB keycloak-staging no platform-staging via IngressGroup | K8s/TF | 1 ALB a menos; `aws elbv2 describe-load-balancers` retorna 3 ALBs | $16/mês |
| **FIN-P1-06** | Inventariar CMKs KMS — deletar chaves sem uso há >90 dias | AWS Specialist | `aws kms list-keys` + `CloudTrail` → 0 chaves órfãs | $1-3/mês |

### P2 — Médio prazo (após go-live produção, 3-6 meses)

| ID | Ação | Responsável | Gate | Saving |
|----|------|-------------|------|--------|
| **FIN-P2-01** | VPA enforcement (após 30d recomendações coletadas) | TF + Performance | VPA modo `Auto`; sem OOMKills; CPU P95 < 80% | $50-80/mês |
| **FIN-P2-02** | Savings Plans 1yr Compute (após VPA + rightsizing estável) | FinOps + CTO | CE confirma commitment comprado; discount aplicado | $80-120/mês |
| **FIN-P2-03** | Staging enxuto: desligar serviços não-críticos (SonarQube, Backstage, Harbor staging) | Arquiteto | Prod assumiu workloads; staging só CI/CD + Vault + Keycloak | $100-150/mês |
| **FIN-P2-04** | S3 Intelligent-Tiering para Harbor images (>128KB, >30d sem acesso) | AWS Specialist | CE mostra S3 custo caindo | $3-5/mês |
| **FIN-P2-05** | RDS Reserved Instance (após confirmar Multi-AZ real e baseline 90d) | FinOps + CTO | Reservation comprada; CE confirma desconto -31% | $35-55/mês |
| **FIN-P2-06** | Graviton ARM64 (t4g nodes) — avaliar compatibilidade arm64 dos workloads | Performance + AWS | 20-40% saving vs x86 on-demand | $30-50/mês |

---

## Appendix — Gate de Sucesso desta Análise

- [x] Análise baseada nos dados reais AWS CE (fonte: finops-status-2026-03-17.md + cloudwatch-cost-analysis-2026-03-10.md)
- [x] Explica por que weekend = weekday cost — 3 fatores identificados (custos fixos dominam ~75%, Lambda salva apenas $9.72/dia nos nodes variáveis, NAT cobra por hora não por tráfego)
- [x] 8 oportunidades de redução imediata com economia estimada por item
- [x] Projeção de custo em 3 horizontes (dev ativo → pós go-live → 12 meses otimizado)
- [x] Recomendação VPN B vs C fundamentada em custo real ($37/mês vs $263/mês, 7.1x diferença, R$ 15.730/ano de economia escolhendo B)

---

## ✅ DECISÃO BUDGET — 2026-03-18

| Campo | Valor |
| --- | --- |
| **Budget anterior** | $807/mês |
| **Budget aprovado** | $1.000/mês |
| **Vigência** | Fase de desenvolvimento ativo (até Fase 7 completa) |
| **Justificativa** | Plataforma enterprise em build ativo — custos naturalmente superestimados; estabilização projetada para $650–750/mês em 12 meses pós go-live |
| **Data aprovação** | 2026-03-18 |

---

*Documento produzido pelo FinOps Specialist — framework executor-terraform.md*
*Fontes: AWS CE real (CLI 2026-03-17) | cloudwatch-cost-analysis-2026-03-10.md | finops-status-2026-03-17.md | 2026-03-17-revisao-capacidade-karpenter.md | 2026-03-18-setup-vpn-acesso-publico.md*
*Referência: 2026-03-18 | Próxima revisão: pós-implementação Karpenter (estimado 2026-03-25)*
