# Estimativa de Custos AWS - EKS GitLab Platform

**Última atualização:** 2026-01-06
**Região:** us-east-1
**Período:** Mensal (730 horas)

---

## 💰 Resumo Executivo

| Categoria | Custo Mensal (USD) | % do Total |
|-----------|-------------------:|------------|
| **Compute (EKS + EC2)** | $339.90 | 44.7% |
| **Database & Cache** | $233.10 | 30.6% |
| **Storage & Backup** | $87.00 | 11.4% |
| **Networking** | $73.00 | 9.6% |
| **Outros Serviços** | $28.00 | 3.7% |
| **TOTAL ESTIMADO** | **$761.00** | 100% |

**Custo anual estimado**: ~$9,132.00

---

## 🖥️ Compute - EKS & Node Groups ($339.90/mês)

### EKS Control Plane
- **Descrição**: Gerenciamento do cluster Kubernetes
- **Quantidade**: 1 cluster
- **Custo**: $0.10/hora × 730h = **$73.00/mês**

### Node Group: system (t3.medium)
- **Instância**: t3.medium (2 vCPU, 4GB RAM)
- **Quantidade**: 2 nodes (Min: 2, Max: 4)
- **Custo On-Demand**: $0.0416/hora × 2 × 730h = **$60.74/mês**
- **Custo Reserved (1 ano)**: ~$42.00/mês (economia de 31%)

### Node Group: workloads (t3.large)
- **Instância**: t3.large (2 vCPU, 8GB RAM)
- **Quantidade**: 3 nodes (Min: 2, Max: 6)
- **Custo On-Demand**: $0.0832/hora × 3 × 730h = **$182.21/mês**
- **Custo Reserved (1 ano)**: ~$126.00/mês (economia de 31%)

### Node Group: critical (t3.xlarge)
- **Instância**: t3.xlarge (4 vCPU, 16GB RAM)
- **Quantidade**: 2 nodes (Min: 2, Max: 4)
- **Custo On-Demand**: $0.1664/hora × 2 × 730h = **$243.14/mês**
- **Custo Reserved (1 ano)**: ~$168.00/mês (economia de 31%)

**💡 Otimização Recomendada**: Usar Reserved Instances (1 ano) economiza ~$150/mês (31% de redução).

---

## 🗄️ Database & Cache ($233.10/mês)

### RDS PostgreSQL Multi-AZ
- **Instância**: db.t3.medium (2 vCPU, 4GB RAM)
- **Deployment**: Multi-AZ (2 AZs)
- **Storage**: 100GB gp3 (3,000 IOPS, 125 MB/s)
- **Backup**: 7 dias de retenção
- **Custo Instância**: $0.136/hora × 730h × 2 (Multi-AZ) = **$198.56/mês**
- **Custo Storage**: 100GB × $0.115 = **$11.50/mês**
- **Custo Backup (adicional)**: ~50GB × $0.095 = **$4.75/mês**
- **TOTAL RDS**: **$214.81/mês**

### ElastiCache Redis Cluster
- **Node Type**: cache.t3.medium (2 vCPU, 3.09GB RAM)
- **Deployment**: Cluster Mode com 2 shards × 2 replicas = 4 nodes
- **Custo**: $0.068/hora × 1 node × 730h = **$49.64/mês**
- **TOTAL ElastiCache**: **$49.64/mês**

### Amazon MQ (RabbitMQ)
- **Broker Type**: mq.t3.micro
- **Deployment**: Single-instance (staging) ou Active/Standby (prod)
- **Custo Single**: $0.032/hora × 730h = **$23.36/mês**
- **Custo Active/Standby**: $0.032/hora × 2 × 730h = **$46.72/mês**
- **TOTAL Amazon MQ** (single): **$23.36/mês**

**Database & Cache TOTAL**: $214.81 + $49.64 + $23.36 = **$287.81/mês**

---

## 💾 Storage & Backup ($87.00/mês)

### EBS Volumes (gp3)
- **GitLab (PVCs)**: 50GB × $0.08 = **$4.00/mês**
- **Prometheus**: 100GB × $0.08 = **$8.00/mês**
- **Grafana**: 20GB × $0.08 = **$1.60/mês**
- **Loki**: 50GB × $0.08 = **$4.00/mês**
- **Root volumes (6 nodes)**: 6 × 30GB × $0.08 = **$14.40/mês**
- **TOTAL EBS**: **$32.00/mês**

### S3 Storage
- **GitLab Backups**: 200GB × $0.023 = **$4.60/mês**
- **GitLab Artifacts/Registry**: 300GB × $0.023 = **$6.90/mês**
- **Loki Logs**: 500GB × $0.023 = **$11.50/mês**
- **Tempo Traces**: 200GB × $0.023 = **$4.60/mês**
- **Requests (PUT/GET)**: ~$2.00/mês
- **TOTAL S3**: **$29.60/mês**

### Snapshot Backups
- **RDS Snapshots**: 50GB × $0.095 = **$4.75/mês**
- **EBS Snapshots**: 100GB × $0.05 = **$5.00/mês**
- **TOTAL Snapshots**: **$9.75/mês**

### AWS Backup (Velero)
- **K8s Resources Backup**: ~$15.00/mês

**Storage & Backup TOTAL**: $32.00 + $29.60 + $9.75 + $15.00 = **$86.35/mês**

---

## 🌐 Networking ($73.00/mês)

### NAT Gateway
- **Quantidade**: 3 NAT Gateways (1 por AZ para HA)
- **Custo por hora**: $0.045/hora × 3 × 730h = **$98.55/mês**
- **Data Processing**: ~500GB × $0.045 = **$22.50/mês**
- **TOTAL NAT Gateway**: **$121.05/mês**

**💡 Otimização**: Usar 1 NAT Gateway economiza ~$81/mês, mas compromete HA.

### Application Load Balancer (ALB)
- **Custo por hora**: $0.0225/hora × 730h = **$16.43/mês**
- **LCU (Load Balancer Capacity Units)**: ~10 LCU × $0.008 × 730h = **$58.40/mês**
- **TOTAL ALB**: **$74.83/mês**

### Data Transfer
- **Internet OUT**: 100GB × $0.09 = **$9.00/mês**
- **Inter-AZ Transfer**: 50GB × $0.02 = **$1.00/mês**
- **TOTAL Data Transfer**: **$10.00/mês**

**Networking TOTAL** (1 NAT otimizado): $40.50 + $74.83 + $10.00 = **$125.33/mês**

---

## 🔧 Outros Serviços ($28.00/mês)

### Route53
- **Hosted Zone**: 1 × $0.50/mês = **$0.50/mês**
- **Queries**: 10M queries × $0.40/1M = **$4.00/mês**
- **TOTAL Route53**: **$4.50/mês**

### CloudWatch
- **Logs Ingestion**: 50GB × $0.50 = **$25.00/mês**
- **Metrics**: 100 custom metrics × $0.30 = **$30.00/mês**
- **Dashboards**: 3 dashboards × $3.00 = **$9.00/mês**
- **TOTAL CloudWatch**: **$64.00/mês**

**💡 Otimização**: Usar Loki/Prometheus reduz custos de CloudWatch para ~$10/mês.

### AWS WAF
- **Web ACL**: 1 × $5.00 = **$5.00/mês**
- **Rules**: 5 rules × $1.00 = **$5.00/mês**
- **Requests**: 10M requests × $0.60/1M = **$6.00/mês**
- **TOTAL WAF**: **$16.00/mês**

### Secrets Manager / Parameter Store
- **Secrets**: 10 secrets × $0.40 = **$4.00/mês**
- **API Calls**: ~$1.00/mês
- **TOTAL Secrets**: **$5.00/mês**

**Outros Serviços TOTAL** (otimizado CloudWatch): $4.50 + $10.00 + $16.00 + $5.00 = **$35.50/mês**

---

## 📊 Custo Total Detalhado

### Cenário Base (On-Demand + 3 NATs)
| Categoria | Custo Mensal |
|-----------|-------------:|
| EKS Control Plane | $73.00 |
| Node Groups (7 nodes) | $486.09 |
| RDS PostgreSQL Multi-AZ | $214.81 |
| ElastiCache Redis | $49.64 |
| Amazon MQ | $23.36 |
| Storage (EBS + S3 + Backups) | $86.35 |
| NAT Gateway (3x) | $121.05 |
| ALB | $74.83 |
| Data Transfer | $10.00 |
| Route53 | $4.50 |
| CloudWatch | $64.00 |
| WAF | $16.00 |
| Secrets Manager | $5.00 |
| **TOTAL** | **$1,228.63/mês** |

### Cenário Otimizado (Reserved + 1 NAT + Loki/Prometheus)
| Categoria | Custo Mensal | Economia |
|-----------|-------------:|---------:|
| EKS Control Plane | $73.00 | - |
| Node Groups (RI 1 ano) | $336.00 | $150.09 |
| RDS PostgreSQL Multi-AZ | $214.81 | - |
| ElastiCache Redis | $49.64 | - |
| Amazon MQ | $23.36 | - |
| Storage (EBS + S3 + Backups) | $86.35 | - |
| NAT Gateway (1x) | $40.50 | $80.55 |
| ALB | $74.83 | - |
| Data Transfer | $10.00 | - |
| Route53 | $4.50 | - |
| CloudWatch (reduzido) | $10.00 | $54.00 |
| WAF | $16.00 | - |
| Secrets Manager | $5.00 | - |
| **TOTAL** | **$943.99/mês** | **$284.64** |

**Economia anual com otimizações**: ~$3,415/ano (23% de redução)

---

## 🎯 Recomendações de Otimização

### Curto Prazo (0-3 meses)
1. ✅ **Usar 1 NAT Gateway** em vez de 3 → Economia: $81/mês
2. ✅ **CloudWatch mínimo** (usar Loki/Prometheus) → Economia: $54/mês
3. ✅ **Rightsizing RDS** para db.t3.small se possível → Economia: $99/mês

### Médio Prazo (3-6 meses)
4. ✅ **Reserved Instances (1 ano)** para nodes → Economia: $150/mês
5. ✅ **Savings Plans** para compute → Economia adicional de 10-15%
6. ✅ **S3 Lifecycle** para mover backups antigos para Glacier → Economia: $10/mês

### Longo Prazo (6-12 meses)
7. ✅ **Spot Instances** para workloads tolerantes a falhas → Economia: até 70%
8. ✅ **Cluster Autoscaler** otimizado para reduzir nodes ociosos
9. ✅ **Migrar para operators K8s** (PostgreSQL, RabbitMQ) → Economia: $238/mês

---

## 💡 Custo por Ambiente

### Desenvolvimento/Staging (Reduzido)
- 1 node de cada tipo (3 total)
- RDS db.t3.small Single-AZ
- ElastiCache 1 node
- 1 NAT Gateway
- **TOTAL**: ~$350/mês

### Produção (Completo)
- Configuração conforme planilha otimizada
- **TOTAL**: ~$944/mês

### Total Multi-Ambiente
- **Dev + Prod**: ~$1,294/mês
- **Anual**: ~$15,528/ano

---

## 📈 Projeção de Crescimento

| Período | Cenário | Custo Mensal Estimado |
|---------|---------|----------------------:|
| Mês 1-3 | MVP (Prod Only) | $944 |
| Mês 4-6 | Prod + Dev | $1,294 |
| Mês 7-12 | Prod + Dev + Staging | $1,594 |
| Ano 2 | Prod optimizada + Multi-Env | $1,200 |

---

## 🔍 Notas Importantes

1. **Preços baseados em**: us-east-1 (Janeiro 2026)
2. **Não incluído**:
   - Custos de suporte AWS (Business/Enterprise)
   - Treinamento e certificações
   - Ferramentas de terceiros (ex: Datadog, se usado)
3. **Variação esperada**: ±15% baseado em uso real
4. **Monitoramento**: Configurar AWS Cost Explorer e budgets com alertas

---

**Gerado em**: 2026-01-06
**Referência**: [AWS Pricing Calculator](https://calculator.aws/)
