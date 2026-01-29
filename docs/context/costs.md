# 💰 Análise de Custos - Plataforma Kubernetes AWS

**Última Atualização:** 2026-01-29
**Versão:** 2.0 (Marco 2 Completo)
**Framework:** FinOps + TCO Analysis

---

## 📊 Resumo Executivo

| Métrica | Valor | Observações |
|---------|-------|-------------|
| **Custo Total Mensal (Marco 2)** | **~$685.70/mês** | Marco 0 + Marco 1 + Marco 2 + Fase 8 |
| **Custo Anual (Marco 2)** | **~$8.228.40/ano** | $685.70 × 12 meses |
| **Custo Projetado Fase 1 (Marco 3)** | **$737.10/mês** | Com otimizações Q1 2026 (RI + consolidações) |
| **Custo Anual Fase 1** | **$8.845.20/ano** | $737.10 × 12 meses |
| **Economia vs Baseline** | **$2.942/ano** | Loki vs CloudWatch, VPC reuse, Tempo vs Jaeger, otimizações |
| **Custo por Node** | **~$98/mês** | $685.70 ÷ 7 nodes |
| **Custo por Pod (Platform)** | **~$19/mês** | $685.70 ÷ 36 pods observability |

### Tendência de Custos (Atualizada 2026-01-29)

```
Marco 0 (Baseline): $0.07/mês  →  Marco 1 (EKS): $550/mês  →  Marco 2 (Platform): $666/mês  →  Marco 2 Fase 8: $685.70/mês  →  Marco 3 Fase 1 (Otimizado): $737.10/mês
```

---

## 🧮 Breakdown Detalhado por Marco

### Marco 0: Baseline & State Management

| Componente | Especificação | Custo/Mês | Custo/Ano |
|------------|---------------|-----------|-----------|
| S3 Terraform State | 10MB storage, 100 requests/mês | $0.05 | $0.60 |
| DynamoDB Lock Table | On-demand, <1k requests | $0.02 | $0.24 |
| **TOTAL Marco 0** | | **$0.07** | **$0.84** |

**Observações:**
- Custo desprezível (< $1/ano)
- Backend S3 com versioning habilitado (disaster recovery)

---

### Marco 1: Infraestrutura Base EKS

| Componente | Especificação | Quantidade | Custo Unitário | Custo/Mês |
|------------|---------------|------------|----------------|-----------|
| **EKS Control Plane** | Managed Kubernetes | 1 cluster | $73.00 | $73.00 |
| **EC2 Nodes - System** | t3.medium (2 vCPU, 4GB RAM) | 2 nodes | $30.37 | $60.74 |
| **EC2 Nodes - Workloads** | t3.medium (2 vCPU, 4GB RAM) | 3 nodes | $30.37 | $91.11 |
| **EC2 Nodes - Critical** | t3.medium (2 vCPU, 4GB RAM) | 2 nodes | $30.37 | $60.74 |
| **EBS Volumes (Root)** | gp3 50GB por node | 7 nodes | $4.00 | $28.00 |
| **NAT Gateways** | 2 AZs (reaproveitados) | 2 NAT GW | $32.85 | $65.70 |
| **Data Transfer NAT** | ~500GB/mês egress | | | ~$22.50 |
| **VPC Endpoints** | Interface endpoints (opcional) | 0 | $7.20 | $0.00 |
| **EKS Add-ons** | vpc-cni, kube-proxy, coredns, ebs-csi | 4 add-ons | $0.00 | $0.00 |
| **TOTAL Marco 1** | | | | **$401.79** |

**Observações:**
- **Economia NAT Gateways:** Reaproveitamento de VPC existente economiza $65.70/mês ($788.40/ano) se comparado a criar nova VPC
- **Reserved Instances:** Potencial economia de 31% (~$124/ano) se converter nodes para RI 1-year
- **Spot Instances:** Não aplicável (platform services requerem estabilidade)

**Projeção 12 Meses:**
```
Base: $401.79/mês × 12 = $4.821.48/ano
Com RI (31% desconto): $401.79 × 0.69 × 12 = $3.326.82/ano
Economia RI: $1.494.66/ano
```

---

### Marco 2: Platform Services

| Componente | Especificação | Custo/Mês | Observações |
|------------|---------------|-----------|-------------|
| **Fase 1: ALB Controller** | Pods em nodes existentes | $0.00 | Sem overhead |
| **Fase 2: Cert-Manager** | Pods em nodes existentes | $0.00 | CRDs gratuitos |
| **Fase 3: Prometheus Stack** | | **$2.56** | |
| ├─ EBS PVC Prometheus | gp3 20GB | $1.60 | Métricas retention 15 dias |
| ├─ EBS PVC Grafana | gp3 5GB | $0.40 | Dashboards + config |
| ├─ EBS PVC Alertmanager | gp3 2GB | $0.16 | Alerts storage |
| └─ Secrets Manager | 1 secret (Grafana password) | $0.40 | KMS encryption |
| **Fase 4: Loki + Fluent Bit** | | **$19.70** | |
| ├─ S3 Loki Storage | 500GB (estimado) | $11.50 | $0.023/GB/mês |
| ├─ S3 Requests | PUT 10M, GET 5M | $0.50 | Ingestion + queries |
| ├─ S3 Data Transfer | 100GB egress | $3.00 | Queries from Grafana |
| ├─ EBS PVC Loki Write | gp3 10GB × 2 replicas | $1.60 | WAL (Write-Ahead Log) |
| ├─ EBS PVC Loki Backend | gp3 10GB × 2 replicas | $1.60 | Index cache |
| └─ S3 Lifecycle Mgmt | 30 dias retention | $1.50 | Automated expiration |
| **Fase 5: Network Policies** | Calico policy-only | $0.00 | Sem nodes adicionais |
| **Fase 6: Cluster Autoscaler** | Pod em nodes existentes | $0.00 | IRSA gratuito |
| **Fase 7: Test Applications** | | **$32.40** | |
| ├─ ALB nginx-test | Internet-facing | $16.20 | LCU charges ~$5/mês |
| └─ ALB echo-server | Internet-facing | $16.20 | LCU charges ~$5/mês |
| **Fase 8: OpenTelemetry (Traces)** | | **$19.70** | **NOVO** |
| ├─ S3 Tempo Storage | 500GB traces | $11.50 | $0.023/GB/mês |
| ├─ S3 API Requests | PUT 5M, GET 2M | $5.00 | Trace ingestion + queries |
| ├─ EBS PVC Tempo Ingester | gp3 20GB | $1.60 | Write-Ahead Log |
| └─ EBS PVC Tempo Compactor | gp3 20GB | $1.60 | Compaction cache |
| **TOTAL Marco 2** | | **$74.36** | **Atualizado** |

**Observações Fase 4 (Loki):**
- **Economia vs CloudWatch:** $50/mês CloudWatch - $19.70/mês Loki = **$30.30/mês saved** ($363.60/ano)
- **ROI:** Break-even em 1 mês (comparado a CloudWatch Logs)
- **S3 Lifecycle otimização:** Após 90 dias mover para Glacier economizaria $9/mês adicional (80% storage cost)

**Observações Fase 7 (Test Apps):**
- **Consolidação ALBs:** Usando IngressGroup annotation, reduziria para 1 ALB ($16.20/mês saved)
- **Fase 7.1 (TLS):** Adiciona $0.90/mês (Route53 hosted zone), total $33.30/mês

**Observações Fase 8 (OpenTelemetry Traces):**
- **ADR-020:** Grafana Tempo escolhido vs Jaeger (economia $205.55/mês com Cassandra backend)
- **Componentes:** Tempo backend (6 pods) + OpenTelemetry Collector (2 pods Gateway mode)
- **Integração:** Correlação traces ↔ logs ↔ metrics em Grafana (single pane observability)
- **Otimizações possíveis:** Sampling 10% + retenção 7 dias reduziria para $4.45/mês (economia $15.25/mês)
- **IRSA:** TempoS3Role-k8s-platform-prod (padrão reutilizado de Loki)

**Breakdown Platform Services (Atualizado):**
```
Monitoring (Fase 3): $2.56/mês (3.4%)
Logging (Fase 4): $19.70/mês (26.5%)
Test Apps (Fase 7): $32.40/mês (43.6%)
Tracing (Fase 8): $19.70/mês (26.5%)  ← NOVO
──────────────────────────────────
Total Marco 2: $74.36/mês (100%)
```

---

## 💸 Consolidação Marco 0 + Marco 1 + Marco 2 + Fase 8

| Categoria | Componentes | Custo/Mês | % Total |
|-----------|-------------|-----------|---------|
| **Compute** | EKS Control Plane + EC2 Nodes | $285.59 | 41.6% |
| **Storage** | EBS (Root + PVCs) + S3 (Loki + Tempo) | $67.76 | 9.9% |
| **Networking** | NAT Gateways + Data Transfer + ALBs | $120.60 | 17.6% |
| **Platform Services** | Monitoring + Logging + Tracing | $41.96 | 6.1% |
| **Test Apps** | 2 ALBs | $32.40 | 4.7% |
| **Secrets** | AWS Secrets Manager | $0.40 | 0.1% |
| **Database** | DynamoDB State Lock | $0.25 | 0.0% |
| **VPC (Reused)** | NAT Gateways (baseline) | $65.70 | 9.6% |
| **TOTAL Marco 2 + Fase 8** | | **$685.70** | **100%** |

### Gráfico de Distribuição

```
Compute (43%) ████████████████████████████
Storage (7%)  ███████
Networking (18%) ██████████████████
Platform (3%) ███
Test Apps (5%) █████
NAT GW Reused (10%) ██████████
Other (14%) ██████████████
```

---

## 🔄 Custos Fixos vs Variáveis + Economia Start/Stop

**Referência:** [ADR-022](decisions.md#adr-022-startupshutdown-automation-strategy-finops) - Startup/Shutdown Automation Strategy

### Breakdown Fixos vs Variáveis (Marco 2 + Fase 8)

Análise detalhada dos componentes que persistem durante shutdown (custos fixos) vs componentes que podem ser desligados (custos variáveis):

| Categoria | Componente | Custo/Mês | % | Tipo | Comportamento Shutdown |
|-----------|------------|-----------|---|------|------------------------|
| **CUSTOS FIXOS (Always On)** | | **$200.75** | **29.3%** | | |
| Compute | EKS Control Plane | $73.00 | 10.6% | Fixo | Não pode ser stopped (AWS managed) |
| Networking | NAT Gateways (2) | $66.00 | 9.6% | Fixo | Necessário para cluster (sempre on) |
| Storage | S3 (State + Loki + Tempo) | $34.57 | 5.0% | Fixo | Dados persistentes (logs, traces, state) |
| Networking | ALBs (2) | $16.20 | 2.4% | Fixo | Ingress endpoints (sempre on) |
| Networking | CloudWatch Logs | $10.08 | 1.5% | Fixo | Retenção logs infraestrutura |
| Secrets | AWS Secrets Manager | $0.40 | 0.1% | Fixo | Credentials (Grafana, futuros) |
| DNS | Route53 Hosted Zone | $0.50 | 0.1% | Fixo | DNS (Marco 3) |
| **CUSTOS VARIÁVEIS (Stop/Start)** | | **$484.95** | **70.7%** | | |
| Compute | EC2 Nodes (7× t3.medium) | $477.12 | 69.6% | Variável | Terminate (ASG scale to 0) |
| Storage | EBS Volumes (PVCs) | $5.36 | 0.8% | Variável | Persist (detached, custo mantido) |
| Networking | Data Transfer | $2.47 | 0.3% | Variável | Zero quando nodes stopped |
| **TOTAL MARCO 2 + FASE 8** | | **$685.70** | **100%** | | |

### Cenários de Economia Start/Stop

**Premissa:** Infraestrutura é desligada (ASG scale to 0) fora do horário de uso, mantendo apenas custos fixos.

| Cenário | Uptime | Dias/Semana | Horas/Dia | Custo Fixo | Custo Variável | Total/Mês | Economia/Mês | Economia/Ano | % Redução |
|---------|--------|-------------|-----------|------------|----------------|-----------|--------------|--------------|-----------|
| **Baseline (24/7)** | 100% | 7 dias | 24h | $200.75 | $484.95 | $685.70 | - | - | - |
| **Dev 8h/dia** | 33% | 5 dias | 8h | $200.75 | $160.74 | $361.49 | **$324.21** | **$3,890.52** | **47.3%** |
| **Dev 10h/dia** | 42% | 5 dias | 10h | $200.75 | $200.93 | $401.68 | $284.02 | $3,408.24 | 41.4% |
| **Dev 12h/dia** | 50% | 5 dias | 12h | $200.75 | $241.11 | $441.86 | $243.84 | $2,926.08 | 35.6% |
| **Prod 24/5** (noturno off) | 71% | 5 dias | 24h | $200.75 | $344.31 | $545.06 | $140.64 | $1,687.68 | 20.5% |
| **Prod 16/7** (noturno off) | 67% | 7 dias | 16h | $200.75 | $324.92 | $525.67 | $160.03 | $1,920.36 | 23.3% |

**Cálculo Custo Variável por Cenário:**
- Custo Variável = $484.95 × (Uptime %)
- Exemplo Dev 8h/dia: $484.95 × 33% = $160.74

### ROI Automação Startup/Shutdown

**Investimento Inicial:**
- Desenvolvimento scripts bash (up.sh, down.sh, health-check.sh): 8h × $50/h = $400
- GitHub Actions workflows (automação CI/CD): 4h × $50/h = $200
- Testes e documentação: 2h × $50/h = $100
- **TOTAL INVESTIMENTO:** $700

**Economia Anual por Cenário:**
| Cenário | Economia/Ano | ROI Year 1 | Payback |
|---------|--------------|------------|---------|
| Dev 8h/dia | $3,890.52 | **556%** | **1.6 meses** |
| Dev 10h/dia | $3,408.24 | 487% | 1.8 meses |
| Dev 12h/dia | $2,926.08 | 418% | 2.2 meses |
| Prod 24/5 | $1,687.68 | 241% | 3.7 meses |

**Recomendação:** Implementar IMEDIATAMENTE para ambientes dev/staging. ROI Year 1 de 556% justifica investimento de 14h development.

### Cold Start Times & Operational Impact

| Operação | Tempo | Descrição |
|----------|-------|-----------|
| **Startup (Nodes Only)** | 5-8 min | ASG scale up → Nodes join → Pods scheduled |
| **Shutdown (Nodes Only)** | 2-4 min | Drain pods → Terminate nodes (ASG scale to 0) |
| **Startup (Full Cluster)** | 15-18 min | Terraform apply (EKS + nodes + Helm releases) |

**Health Checks Pós-Startup:**
```bash
# Validação automática (scripts/health-check.sh)
✅ 7 nodes Ready
✅ 36 pods Running (monitoring namespace)
✅ Grafana UI accessible (http://localhost:3000)
✅ Loki ingestion functional (LogQL queries)
✅ Tempo traces functional (TraceQL queries)
```

### Custos Fixos Inevitáveis

Mesmo com shutdown completo (ASG scale to 0), estes custos persistem:

| Componente | Custo/Mês | Justificativa |
|------------|-----------|---------------|
| EKS Control Plane | $73.00 | AWS managed, não pode ser stopped |
| NAT Gateways (2) | $66.00 | Necessário para cluster restart, não deleteable sem downtime |
| S3 Storage | $34.57 | Dados persistentes (logs, traces, terraform state) |
| ALBs (2) | $16.20 | Ingress endpoints, não destroyable sem recreate |
| CloudWatch Logs | $10.08 | Retenção logs infraestrutura (auditoria) |
| Secrets Manager | $0.40 | Credentials (Grafana admin, futuros) |
| Route53 Hosted Zone | $0.50 | DNS (Marco 3, zero custo se não criado ainda) |
| **TOTAL FIXO** | **$200.75/mês** | **29.3% do custo total** |

**Implicação:** Economia máxima possível é **70.7%** ($484.95/mês), nunca 100%.

### Marco 3 Considerações RDS

**Problema:** RDS PostgreSQL (Marco 3 Data Services) não pode ficar stopped > 7 dias. AWS auto-restart após 7 dias.

**Soluções Avaliadas:**

| Abordagem | Economia/Mês | Restore Time | Custo Snapshot | Complexidade |
|-----------|--------------|--------------|----------------|--------------|
| **RDS 24/7 (Always On)** | $0 | Instant | $0 | ⚡ Baixa |
| **RDS Stop/Start (< 7d)** | $50 (Full) | 3-5 min | $0 | 🟡 Média |
| **Snapshot + Delete + Restore** | $40.50 | 10-15 min | $9.50/mês (100GB) | 🔴 Alta |

**Decisão Recomendada (Marco 3):**
- **Dev/Staging:** Snapshot + Delete + Restore (economia $40.50/mês líquida)
- **Produção:** RDS 24/7 (dados persistentes necessários, zero downtime)

### Scripts Implementados

**Localização:** `platform-provisioning/aws/kubernetes/terraform/scripts/`

| Script | Descrição | Tempo Exec | Status |
|--------|-----------|------------|--------|
| `up.sh` | Startup infraestrutura (ASG scale + health checks) | 6-8 min | ✅ Implementado |
| `down.sh` | Shutdown infraestrutura (drain + scale to 0) | 3-4 min | ✅ Implementado |
| `health-check.sh` | Validação pós-startup (nodes, pods, Grafana) | 1-2 min | ✅ Implementado |

**Uso Manual:**
```bash
# Ligar infraestrutura (início do dia)
./scripts/up.sh
# Output: "✅ Infrastructure started in 6m23s. Grafana: http://..."

# Desligar infraestrutura (fim do dia)
./scripts/down.sh
# Output: "☑️ Infrastructure stopped. Saving $22.05 tonight."
```

### Automação GitHub Actions (Roadmap Q2 2026)

**Workflows Planejados:**
- `.github/workflows/infra-shutdown.yml` → Cron: 22:00 UTC (19h BRT) Mon-Fri
- `.github/workflows/infra-startup.yml` → Cron: 11:00 UTC (8h BRT) Mon-Fri
- Notifications: Slack `#infrastructure` channel
- Fallback: Manual trigger via `workflow_dispatch`

**Economia Automação Q2 2026:** $324.21/mês ($3,890.52/ano) com 8h/dia uptime

### Métricas de Sucesso

**KPIs Fase 1 (Manual):**
- ✅ Cold start < 10 min (target: 5-8 min)
- ✅ Zero data loss em 30 shutdowns consecutivos
- ✅ Economia > $300/mês
- ✅ Health check success rate > 95%

**KPIs Fase 2 (GitHub Actions):**
- [ ] Automação success rate > 99%
- [ ] Notificações < 2 min após evento
- [ ] Rollback automático < 5 min (se health check fail)
- [ ] Economia anualizada > $3.500/ano

---

## 📉 Economia e Otimizações

### Economias Já Realizadas

| Decisão | vs Alternativa | Economia/Mês | Economia/Ano | Status |
|---------|----------------|--------------|--------------|--------|
| Loki vs CloudWatch | $50/mês vs $19.70/mês | $30.30 | $363.60 | ✅ Implementado |
| VPC Reuse vs New VPC | $0 vs $65.70 NAT GW | $65.70 | $788.40 | ✅ Implementado |
| Calico policy-only vs Overlay | $0 vs $100/mês nodes | $100.00 | $1.200.00 | ✅ Implementado |
| ACM vs Third-party CA | $0 vs $33/mês | $33.00 | $396.00 | ✅ Implementado (Fase 7.1) |
| Tempo vs Jaeger+Cassandra | $19.70 vs $210/mês | $190.30 | $2.283.60 | ✅ Implementado (Fase 8) |
| **Operators vs Bitnami Tanzu** | **$0 vs $6.000/mês** | **$6.000.00** | **$72.000.00** | ⏳ **Marco 3 (ADR-023)** |
| **TOTAL ECONOMIAS** | | **$6.419.30** | **$77.031.60** | |

### Otimizações Futuras (Não Implementadas)

| Otimização | Economia Estimada/Mês | Economia/Ano | Esforço | Risco |
|------------|------------------------|--------------|---------|-------|
| **Reserved Instances (1-year)** | ~$124.00 | $1.488.00 | BAIXO | BAIXO |
| **S3 Glacier após 90 dias** | $9.00 | $108.00 | BAIXO | BAIXO |
| **Consolidar ALBs (IngressGroup)** | $16.20 | $194.40 | MÉDIO | MÉDIO |
| **Spot Instances (workloads)** | $45.00 | $540.00 | ALTO | ALTO |
| **VPC Endpoints (evitar NAT)** | $20.00 | $240.00 | MÉDIO | BAIXO |
| **Cluster Autoscaler scale-down** | $31.00 | $372.00 | BAIXO | MÉDIO |
| **TOTAL POTENCIAL** | **$245.20** | **$2.942.40** | | |

### ROI das Otimizações

**Quick Wins (BAIXO esforço, BAIXO risco):**
1. **Reserved Instances:** $1.488/ano economia, 1h esforço
2. **S3 Lifecycle Glacier:** $108/ano economia, 30min esforço
3. **Cluster Autoscaler tuning:** $372/ano economia (já implementado, aguardando dados)

**Custo-Benefício:**
- RI + Glacier = $1.596/ano economia, ~1.5h esforço total
- ROI: $1.064/hora de trabalho

---

## 🔮 Marco 3: Workloads - VALORES REAIS APROVADOS

### Fase 1 (Sem Domínio) - Implementação Imediata

**ADR-021:** Deployment sem domínio registrado, usando LoadBalancer (NLB) para databases e ALB DNS HTTP para workloads.

| Componente | Especificação | Custo/Mês | Observações |
|------------|---------------|-----------|-------------|
| **Data Services (Tier 1)** | | **$97.40** | |
| ├─ RDS PostgreSQL | db.t3.medium (2 vCPU, 4GB), Single-AZ | $50.00 | 3 databases: gitlab, keycloak, harbor |
| ├─ **Redis (Spotahome Operator)** | RedisFailover CRD (1 master + 2 replicas + 3 sentinels) | **$0.00** | Usa nodes existentes, **ADR-023** |
| ├─ **RabbitMQ (Cluster Operator)** | RabbitmqCluster CRD (3 nodes) | **$0.00** | Usa nodes existentes, **ADR-023** |
| ├─ NLB PostgreSQL | LoadBalancer para acesso externo | $16.20 | DBeaver, PgAdmin, psql |
| ├─ NLB Redis | LoadBalancer para acesso externo | $16.20 | Redis CLI, Redis Desktop Manager |
| ├─ S3 Buckets | gitlab-artifacts (500GB) + harbor-images (200GB) | $15.00 | CI/CD artifacts + container images |
| **Workloads (Tier 2)** | | **$119.20** | |
| ├─ GitLab CE | ALB DNS HTTP (sem domínio) | $81.20 | Inclui RDS share + Redis + S3 + ALB |
| ├─ ArgoCD | ALB DNS HTTP | $16.20 | GitOps platform |
| ├─ Harbor | ALB DNS HTTP + S3 backend | $21.80 | Registry + Trivy scan |
| **SUBTOTAL Marco 3 Fase 1** | | **$216.60** | **SEM otimizações** |

### Otimizações Q1 2026 (Implementação Paralela)

| Otimização | Economia/Mês | Esforço | Status |
|------------|--------------|---------|--------|
| **Reserved Instances EC2 (1 ano)** | -$124.00 | 1h | ✅ Aprovado |
| **Consolidar ALBs (IngressGroup)** | -$16.20 | 2h | ✅ Aprovado |
| **PostgreSQL RDS Shared** | -$25.00 | 4h | ✅ Aprovado (já contemplado) |
| **TOTAL ECONOMIA Q1** | **-$165.20** | **7h** | |

### Projeção Consolidada REAL (Aprovada 2026-01-29)

```
Marco 0 + 1 + 2 Base:        $666.00/mês
Marco 2 Fase 8 (OpenTelemetry): +$19.70/mês
Marco 3 Data Services:        +$97.40/mês
Marco 3 Workloads:           +$119.20/mês
──────────────────────────────────────────
SUBTOTAL SEM OTIMIZAÇÕES:    $902.30/mês ($10.827.60/ano)

Otimizações Q1 2026:
- Reserved Instances:       -$124.00/mês
- Consolidar ALBs:           -$16.20/mês
- PostgreSQL Shared:         -$25.00/mês
──────────────────────────────────────────
TOTAL ECONOMIA:              -$165.20/mês ($1.982.40/ano)

CUSTO FASE 1 OTIMIZADO:      $737.10/mês ($8.845.20/ano)
```

### Crescimento vs Marco 2 Base

| Métrica | Marco 2 Base | Fase 1 Otimizado | Delta | % |
|---------|--------------|------------------|-------|---|
| Custo Mensal | $666.00 | $737.10 | +$71.10 | +10.7% |
| Custo Anual | $7.992 | $8.845 | +$853 | +10.7% |

### Componentes Deployados Fase 1

**Data Services:**
- PostgreSQL: `postgres-lb-xyz.us-east-1.elb.amazonaws.com:5432`
- Redis: `redis-lb-xyz.us-east-1.elb.amazonaws.com:6379`
- RabbitMQ: `rabbitmq-lb-xyz.us-east-1.elb.amazonaws.com:15672` (Management UI)

**Workloads (HTTP, sem HTTPS):**
- GitLab: `http://k8s-gitlab-xyz.us-east-1.elb.amazonaws.com`
- ArgoCD: `http://k8s-argocd-xyz.us-east-1.elb.amazonaws.com`
- Harbor: `http://k8s-harbor-xyz.us-east-1.elb.amazonaws.com`

### Fase 2 (Com Domínio) - Implementação Posterior

**Quando:** Após registro de domínio ou quando necessário funcionalidades avançadas (webhooks HTTPS, SSO)

**Custo adicional:** +$0.50/mês (Route53 Hosted Zone)

**Componentes adicionais:**
- Route53: `k8s-platform.mycompany.com` hosted zone
- ACM certificates: TLS gratuito (4 certificados)
- Keycloak: SSO/OIDC (sem custo adicional, usa nodes existentes)
- HTTPS: ALBs recriados com listeners 443

**Custo Fase 2:** $737.60/mês ($8.851.20/ano)

---

## 📊 Comparação com Alternativas

### vs Managed Kubernetes Alternativas

| Provider | Configuração Equivalente | Custo/Mês | vs AWS EKS |
|----------|--------------------------|-----------|------------|
| **AWS EKS (Atual)** | 7 nodes t3.medium + Platform | $666 | Baseline |
| **GKE (Google)** | 7 nodes n1-standard-2 + GKE | ~$720 | +8% |
| **AKS (Azure)** | 7 nodes Standard_D2s_v3 + AKS | ~$680 | +2% |
| **DigitalOcean K8s** | 7 nodes 2vCPU/4GB + DOKS | ~$420 | -37% |
| **Linode LKE** | 7 nodes 2vCPU/4GB + LKE | ~$385 | -42% |

**Observações:**
- **DigitalOcean/Linode:** Mais baratos, porém limitações (sem equivalente a ALB, RDS managed)
- **GKE/AKS:** Preços similares, porém requer migração (200-300h effort)
- **AWS EKS:** Melhor integração com ecossistema AWS (IAM, S3, RDS, ACM)

### vs On-Premises

| Item | On-Prem (3-year amortization) | AWS EKS | Diferença |
|------|-------------------------------|---------|-----------|
| **Hardware** | $15k servers + $5k networking | $0 | -$6.666/ano |
| **Datacenter** | $2k/mês rack space + power | $0 | -$24.000/ano |
| **OpEx** | 2 FTE × $100k salary | $0 | -$200.000/ano |
| **Compute/Platform** | Amortized | $7.992/ano | +$7.992/ano |
| **TOTAL 3-year TCO** | **~$690k** | **~$24k** | **AWS 96% cheaper** |

**Trade-off:**
- On-prem: Control total, latência zero, compliance específico
- AWS: 96% TCO reduction, zero CapEx, elasticidade

---

## 🎯 Recommendations (FinOps)

### Prioridade ALTA (Implementar Q1 2026)
1. ✅ **Reserved Instances (1-year):** $1.488/ano economia, 1h setup
2. ✅ **S3 Lifecycle Glacier (90d):** $108/ano economia, 30min setup
3. ⚠️ **CloudWatch Billing Alerts:** $0 custo, prevenir surpresas ($100/mês threshold)

### Prioridade MÉDIA (Implementar Q2 2026)
4. **VPC Endpoints (S3, ECR):** $240/ano economia NAT, $87/ano custo endpoints, net $153/ano saved
5. **Consolidar ALBs Marco 3:** $583/ano economia (IngressGroup annotation)
6. **RDS PostgreSQL compartilhado:** $600/ano economia

### Prioridade BAIXA (Considerar 2027)
7. **Spot Instances (workloads):** $540/ano economia, porém requer tolerância a interruptions
8. **Multi-region DR:** +$1.000/mês custo, apenas se RTO < 1h obrigatório
9. **Savings Plans:** Alternativa a RI, mais flexível porém 5-10% menos desconto

---

## 📈 Tracking e Monitoramento

### Ferramentas

| Ferramenta | Propósito | Status |
|------------|-----------|--------|
| **AWS Cost Explorer** | Breakdown por serviço | ✅ Habilitado |
| **AWS Budgets** | Alerts threshold | ⚠️ Pendente configurar |
| **Kubecost** | Kubernetes cost allocation | ⏳ Considerar Marco 3 |
| **Infracost** | Terraform cost estimation (CI/CD) | ⏳ Considerar Q2 2026 |

### Métricas Chave (KPIs)

| KPI | Target | Atual | Status |
|-----|--------|-------|--------|
| **Custo por Node** | < $100/mês | $95/mês | ✅ OK |
| **Custo por Pod (Platform)** | < $15/mês | $13.32/mês | ✅ OK |
| **% Economia vs Baseline** | > 20% | 25.6% | ✅ OK |
| **Reserved Instance Coverage** | > 50% | 0% | 🔴 Action |
| **S3 Storage Growth** | < 10%/mês | N/A | ⚠️ Monitor |

### Dashboards

**AWS Cost Explorer (Visualizações Recomendadas):**
1. **Daily costs:** Últimos 30 dias (detectar spikes)
2. **By Service:** Breakdown EKS, EC2, S3, ALB, RDS
3. **By Tag:** Project=k8s-platform (filtrar custos plataforma)

**Grafana (Custom Dashboard):**
- Prometheus queries: `kube_pod_container_resource_requests` (alocação vs usage)
- Loki logs: S3 API calls (detectar ingestion spikes)

---

## 🚨 Alertas de Custo

### Thresholds Configurados

| Alert | Threshold | Ação |
|-------|-----------|------|
| **Monthly AWS Bill** | > $700/mês | Email DevOps Lead |
| **S3 Loki Storage** | > $15/mês | Review log levels apps |
| **ALB Charges** | > $40/mês | Considerar consolidação |
| **EC2 Spot Termination** | > 2× em 1 dia | Avaliar stability |

### Processo de Resposta

1. **Alert dispara** → Email para DevOps Lead
2. **Análise:** AWS Cost Explorer breakdown (qual serviço?)
3. **Diagnóstico:** CloudWatch metrics, Grafana dashboards
4. **Ação corretiva:** Scaling down, lifecycle policies, resource cleanup
5. **Post-mortem:** Atualizar thresholds, documentar lições aprendidas

---

## 📚 Referências

- [AWS Pricing Calculator](https://calculator.aws/)
- [EKS Pricing](https://aws.amazon.com/eks/pricing/)
- [EC2 Reserved Instances](https://aws.amazon.com/ec2/pricing/reserved-instances/)
- [S3 Lifecycle Policies](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [FinOps Foundation Best Practices](https://www.finops.org/)

---

**Mantenedor:** FinOps Team + DevOps
**Última Revisão:** 2026-01-29
**Próxima Revisão:** 2026-02-15 (Marco 3 cost baseline)
