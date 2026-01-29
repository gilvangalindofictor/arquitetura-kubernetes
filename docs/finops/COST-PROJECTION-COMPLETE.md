# 💰 Projeção de Custos Completa - Plataforma Kubernetes AWS

**Data:** 2026-01-29
**Versão:** 2.1 (Incluindo Impacto Bitnami)
**Framework:** FinOps + TCO Analysis + Risk Assessment

---

## 🎯 Resumo Executivo

| Métrica | Valor Atual | Projeção Marco 3 | Observações |
|---------|-------------|------------------|-------------|
| **Custo Mensal (Atual Marco 2)** | **$685.70** | $737.10 | +7.5% ⬆️ |
| **Custo Anual (Atual)** | $8,228.40 | $8,845.20 | Marco 3 otimizado |
| **Custo com Economia Dev (8h/dia)** | $316.74/mês | $352.18/mês | -53.8% ⬇️ |
| **🔥 RISCO Licenciamento Bitnami** | **+$72,000/ano** | **$0 (Operators)** | **CRÍTICO** |
| **Economia Total Decisões** | $2,347/ano | $74,347/ano | **Com Operators** |

---

## 📊 Breakdown Completo por Marco

### Marco 0: Baseline & State Management

| Componente | Especificação | Custo/Mês | Custo/Ano |
|------------|---------------|-----------|-----------|
| S3 Terraform State | 10MB storage | $0.05 | $0.60 |
| DynamoDB Lock Table | On-demand | $0.02 | $0.24 |
| **TOTAL Marco 0** | | **$0.07** | **$0.84** |

**Status:** ✅ Completo (2026-01-23)

---

### Marco 1: Infraestrutura Base EKS

| Componente | Especificação | Quantidade | Custo/Mês | Custo/Ano |
|------------|---------------|------------|-----------|-----------|
| **EKS Control Plane** | Managed Kubernetes | 1 cluster | $73.00 | $876.00 |
| **EC2 Nodes - System** | t3.medium (2 vCPU, 4GB) | 2 nodes | $60.74 | $728.88 |
| **EC2 Nodes - Workloads** | t3.medium | 3 nodes | $91.11 | $1,093.32 |
| **EC2 Nodes - Critical** | t3.medium | 2 nodes | $60.74 | $728.88 |
| **EBS Volumes (Root)** | gp3 50GB por node | 7 nodes | $28.00 | $336.00 |
| **NAT Gateways** | 2 AZs (reaproveitados) | 2 NAT GW | $65.70 | $788.40 |
| **Data Transfer NAT** | ~500GB/mês egress | | $22.50 | $270.00 |
| **TOTAL Marco 1** | | | **$401.79** | **$4,821.48** |

**Status:** ✅ Completo (2026-01-25)
**Economia Reaproveitamento VPC:** $788.40/ano (2 NAT GW não criados)

---

### Marco 2: Platform Services

| Fase | Componente | Custo/Mês | Custo/Ano | Status |
|------|------------|-----------|-----------|--------|
| **Fase 1** | ALB Controller | $0.00 | $0.00 | ✅ Completo |
| **Fase 2** | Cert-Manager | $0.00 | $0.00 | ✅ Completo |
| **Fase 3** | Prometheus Stack | $2.56 | $30.72 | ✅ Completo |
| **Fase 4** | Loki + Fluent Bit | $19.70 | $236.40 | ✅ Completo |
| **Fase 5** | Network Policies | $0.00 | $0.00 | ✅ Completo |
| **Fase 6** | Cluster Autoscaler | $0.00 | $0.00 | ✅ Completo |
| **Fase 7** | Test Applications | $32.40 | $388.80 | ✅ Completo |
| **Fase 8** | OpenTelemetry (Traces) | $19.70 | $236.40 | ✅ Completo |
| **TOTAL Marco 2** | | **$74.36** | **$892.32** | |

**Status:** ✅ Completo (2026-01-29)
**Economia vs CloudWatch:** $363.60/ano (Loki vs CloudWatch Logs)

---

### Marco 3: Data Services & Workloads (PLANEJADO)

#### Fase 1: Sem Domínio (Implementação Imediata)

**Data Services:**

| Componente | Especificação | Custo/Mês | Custo/Ano | Observações |
|------------|---------------|-----------|-----------|-------------|
| **PostgreSQL RDS** | db.t3.medium, Single-AZ | $50.00 | $600.00 | 3 databases (GitLab, Keycloak, Harbor) |
| **Redis Operator** | Spotahome Operator | **$0.00** | **$0.00** | ✅ 3 pods (1 master + 2 replicas) |
| **RabbitMQ Operator** | Cluster Operator | **$0.00** | **$0.00** | ✅ 3 nodes cluster |
| **NLB PostgreSQL** | LoadBalancer | $16.20 | $194.40 | Acesso externo (DBeaver, PgAdmin) |
| **NLB Redis** | LoadBalancer | $16.20 | $194.40 | Acesso externo (Redis CLI) |
| **S3 Buckets** | gitlab-artifacts + harbor-images | $15.00 | $180.00 | 700GB total |
| **SUBTOTAL Data Services** | | **$97.40** | **$1,168.80** | |

**Workloads:**

| Componente | Especificação | Custo/Mês | Custo/Ano | Observações |
|------------|---------------|-----------|-----------|-------------|
| **GitLab CE** | ALB DNS HTTP (sem domínio) | $81.20 | $974.40 | Inclui RDS share + Redis + S3 + ALB |
| **ArgoCD** | ALB DNS HTTP | $16.20 | $194.40 | GitOps platform |
| **Harbor** | ALB DNS HTTP + S3 backend | $21.80 | $261.60 | Container registry + Trivy scan |
| **SUBTOTAL Workloads** | | **$119.20** | **$1,430.40** | |

**TOTAL Marco 3 Fase 1 (Sem Otimizações):** $216.60/mês ($2,599.20/ano)

#### Otimizações Q1 2026

| Otimização | Economia/Mês | Economia/Ano | Esforço | Status |
|------------|--------------|--------------|---------|--------|
| Reserved Instances EC2 (1 ano) | -$124.00 | -$1,488.00 | 1h | ⏳ Planejado |
| Consolidar ALBs (IngressGroup) | -$16.20 | -$194.40 | 2h | ⏳ Planejado |
| PostgreSQL RDS Shared | -$25.00 | -$300.00 | 4h | ✅ Contemplado |
| **TOTAL Economia Q1** | **-$165.20** | **-$1,982.40** | **7h** | |

**TOTAL Marco 3 Fase 1 OTIMIZADO:** $51.40/mês ($616.80/ano)

---

## 💸 Consolidação Total de Custos

### Cenário 1: Marco 2 Atual (Baseline)

| Marco | Componentes | Custo/Mês | Custo/Ano | % Total |
|-------|-------------|-----------|-----------|---------|
| Marco 0 | State Management | $0.07 | $0.84 | 0.01% |
| Marco 1 | EKS + Nodes + Networking | $401.79 | $4,821.48 | 58.6% |
| Marco 2 | Platform Services | $74.36 | $892.32 | 10.8% |
| Marco 2 Fase 8 | OpenTelemetry Traces | $19.70 | $236.40 | 2.9% |
| **TOTAL ATUAL** | | **$685.70** | **$8,228.40** | **100%** |

### Cenário 2: Marco 3 Fase 1 Otimizado (Operators)

| Marco | Componentes | Custo/Mês | Custo/Ano | % Total |
|-------|-------------|-----------|-----------|---------|
| Marco 0+1+2 | Baseline atual | $685.70 | $8,228.40 | 93.0% |
| Marco 3 Data Services | PostgreSQL RDS + Operators + NLBs + S3 | $97.40 | $1,168.80 | 13.2% |
| Marco 3 Workloads | GitLab + ArgoCD + Harbor | $119.20 | $1,430.40 | 16.2% |
| **SUBTOTAL Sem Otimizações** | | **$902.30** | **$10,827.60** | **122.4%** |
| Otimizações Q1 2026 | RI + ALB consolidation + RDS shared | -$165.20 | -$1,982.40 | -22.4% |
| **TOTAL OTIMIZADO** | | **$737.10** | **$8,845.20** | **100%** |

**Crescimento vs Marco 2:** +$51.40/mês (+7.5%)
**Custo por Node:** $105.30/mês (7 nodes)
**Custo por Workload:** $39.77/mês (GitLab + ArgoCD + Harbor + Platform)

### 🔥 Cenário 3: Marco 3 com Bitnami + Tanzu Standard (EVITAR)

| Marco | Componentes | Custo/Mês | Custo/Ano | % Total |
|-------|-------------|-----------|-----------|---------|
| Marco 0+1+2+3 | Baseline otimizado | $737.10 | $8,845.20 | 10.9% |
| **Licenciamento Tanzu Standard** | Bitnami charts (Redis + RabbitMQ) | **$6,000.00** | **$72,000.00** | **89.1%** |
| **TOTAL COM TANZU** | | **$6,737.10** | **$80,845.20** | **100%** |

**Impacto Tanzu:** +814% de aumento vs Marco 3 otimizado ❌
**Custo por Node:** $962.44/mês (7 nodes) - **INACEITÁVEL**

---

## 📈 Comparativo: Todas as Alternativas

### Tabela Completa de Cenários

| Cenário | Infra AWS | Licenciamento | Total/Ano | vs Baseline | Decisão |
|---------|-----------|---------------|-----------|-------------|---------|
| **Marco 2 Atual** | $8,228 | $0 | **$8,228** | - | ✅ Baseline |
| **Marco 3 Operators (Otimizado)** | $8,845 | **$0** | **$8,845** | +7.5% | ✅ **RECOMENDADO** |
| **Marco 3 Bitnami + Tanzu** | $8,845 | **$72,000** | **$80,845** | +882% | ❌ **EVITAR** |
| **Marco 3 AWS Managed (RDS + ElastiCache + MQ)** | $11,640 | $0 | **$11,640** | +41% | ⚠️ Alternativa |

**Decisão:** Marco 3 com **Operators** - Melhor custo-benefício ($8,845/ano, +7.5% vs baseline)

---

## 💰 Economia Total Acumulada (Decisões Estratégicas)

### Economias Realizadas (Marco 0-2)

| Decisão | vs Alternativa | Economia/Ano | Status | ADR/DEC |
|---------|----------------|--------------|--------|---------|
| VPC Reaproveitamento | vs Criar nova VPC | $1,152 | ✅ Implementado | DEC-010 |
| Loki vs CloudWatch | vs CloudWatch Logs | $364 | ✅ Implementado | ADR-005 |
| Calico policy-only | vs Overlay network | $1,200 | ✅ Implementado | ADR-006 |
| Cluster Autoscaler | vs Nodes fixos | $372 | ✅ Implementado | ADR-007 |
| ACM vs Third-party CA | vs DigiCert/GlobalSign | $396 | ✅ Implementado | ADR-008 |
| Tempo vs Jaeger | vs Jaeger + Cassandra | $2,467 | ✅ Implementado | ADR-020 |
| **SUBTOTAL Economias Marco 0-2** | | **$5,951/ano** | | |

### Economias Planejadas (Marco 3)

| Decisão | vs Alternativa | Economia/Ano | Status | ADR/DEC |
|---------|----------------|--------------|--------|---------|
| **Operators vs Bitnami Tanzu** | vs Tanzu Standard | **$72,000** | ⏳ Planejado | **CRÍTICO** |
| Reserved Instances EC2 | vs On-Demand | $1,488 | ⏳ Planejado | Q1 2026 |
| Consolidar ALBs | vs Múltiplos ALBs | $194 | ⏳ Planejado | Q1 2026 |
| PostgreSQL RDS Shared | vs 3 RDS instances | $300 | ✅ Contemplado | ADR-021 |
| S3 Lifecycle Glacier | vs Standard storage | $108 | ⏳ Planejado | Q2 2026 |
| **SUBTOTAL Economias Marco 3** | | **$74,090/ano** | | |

**ECONOMIA TOTAL ACUMULADA:** $5,951 + $74,090 = **$80,041/ano**

---

## 🔄 Economia Start/Stop Automation (ADR-022)

### Breakdown Custos Fixos vs Variáveis

| Categoria | Componente | Custo/Mês | % | Tipo |
|-----------|------------|-----------|---|------|
| **CUSTOS FIXOS (Always On)** | | **$200.75** | **29.3%** | |
| Compute | EKS Control Plane | $73.00 | 10.6% | Fixo |
| Networking | NAT Gateways (2) | $66.00 | 9.6% | Fixo |
| Storage | S3 (State + Loki + Tempo) | $34.57 | 5.0% | Fixo |
| Networking | ALBs (2 Marco 2 + 3 Marco 3) | $32.40 | 4.7% | Fixo |
| DNS | Route53 Hosted Zone | $0.50 | 0.1% | Fixo |
| Secrets | AWS Secrets Manager | $0.40 | 0.1% | Fixo |
| | | | | |
| **CUSTOS VARIÁVEIS (Stop/Start)** | | **$484.95** | **70.7%** | |
| Compute | EC2 Nodes (7× t3.medium) | $477.12 | 69.6% | Variável |
| Storage | EBS Volumes (PVCs) | $5.36 | 0.8% | Variável (parcial) |
| Networking | Data Transfer | $2.47 | 0.3% | Variável |

### Cenários de Economia (Dev 8h/dia útil)

| Cenário | Uptime | Custo Fixo | Custo Variável | Total/Mês | Economia/Mês | Economia/Ano |
|---------|--------|------------|----------------|-----------|--------------|--------------|
| **Baseline 24/7** | 100% | $200.75 | $484.95 | $685.70 | - | - |
| **Dev 8h/dia** | 24% | $200.75 | $116.03 | $316.78 | **$368.92** | **$4,427** |
| **Dev 10h/dia** | 30% | $200.75 | $145.49 | $346.24 | $339.46 | $4,073 |
| **Prod 24/5** | 71% | $200.75 | $344.31 | $545.06 | $140.64 | $1,688 |

**ROI Automação:**
- Investimento: $500 (5h desenvolvimento scripts)
- Economia Ano 1 (Dev 8h/dia): $4,427
- **ROI:** 886% (payback < 3 semanas)

---

## 📊 Projeção Multi-Ambiente (Roadmap Futuro)

### Fase Atual: Ambiente Único (Dev/Staging/Prod compartilhado)

| Ambiente | Custo/Mês | Uptime | Economia Start/Stop |
|----------|-----------|--------|---------------------|
| **Único (Dev)** | $316.78 | 8h/dia | $368.92/mês |

### Fase 2: Multi-Ambiente (Produção separada)

| Ambiente | Custo/Mês | Uptime | Economia Start/Stop |
|----------|-----------|--------|---------------------|
| **Dev** | $316.78 | 8h/dia | $368.92/mês |
| **Staging** | $316.78 | 10h/dia | $339.46/mês |
| **Produção** | $737.10 | 24/7 | $0 |
| **TOTAL** | **$1,370.66** | | **$708.38/mês** |

**Custo Anual Multi-Ambiente:** $16,448/ano
**Economia vs 3 ambientes 24/7:** $8,500/ano (34% redução)

---

## 🎯 Recomendações de Otimização

### Prioridade CRÍTICA (Implementar Q1 2026)

| Otimização | Economia/Ano | Esforço | Payback | Status |
|------------|--------------|---------|---------|--------|
| **Migrar para Operators (vs Bitnami Tanzu)** | **$72,000** | 30h | **13 dias** | ⏳ PLANEJADO |
| Reserved Instances EC2 (1 ano) | $1,488 | 1h | Imediato | ⏳ PLANEJADO |
| Start/Stop Automation Dev 8h/dia | $4,427 | 5h | 3 semanas | ✅ IMPLEMENTADO |

**TOTAL ECONOMIA CRÍTICA:** $77,915/ano

### Prioridade ALTA (Implementar Q2 2026)

| Otimização | Economia/Ano | Esforço | Status |
|------------|--------------|---------|--------|
| S3 Lifecycle Glacier (90 dias) | $108 | 0.5h | ⏳ Planejado |
| Consolidar ALBs (IngressGroup) | $194 | 2h | ⏳ Planejado |
| VPC Endpoints (S3, ECR) | $153 | 3h | ⏳ Considerar |

**TOTAL ECONOMIA ALTA:** $455/ano

### Prioridade MÉDIA (Considerar 2027)

| Otimização | Economia/Ano | Esforço | Risco | Status |
|------------|--------------|---------|-------|--------|
| Spot Instances (workloads) | $540 | 8h | MÉDIO | ⏳ Avaliar |
| Savings Plans (3 anos) | $2,400 | 2h | BAIXO | ⏳ Considerar |
| Karpenter (vs Cluster Autoscaler) | $600 | 20h | ALTO | ⏳ 2027 |

**TOTAL ECONOMIA MÉDIA:** $3,540/ano

---

## 🚨 Riscos Financeiros

### Risco 1: Licenciamento Bitnami → Tanzu Standard

**Probabilidade:** ALTA (se não agir)
**Impacto:** CRÍTICO (+$72k/ano)
**Severidade:** 🔴 CRÍTICO

**Mitigação:** Migrar para Operators IMEDIATAMENTE (Marco 3)
**Status:** ⏳ Aguardando aprovação stakeholders

### Risco 2: Variação Cambial (USD/BRL)

**Probabilidade:** MÉDIA
**Impacto:** MÉDIO (±10-15% custos)
**Severidade:** 🟡 MÉDIO

**Mitigação:**
- AWS Budgets com alertas ($800/mês threshold)
- Hedge cambial (se necessário)
- Revisão mensal de custos

### Risco 3: Custos S3 Excedem Estimativa

**Probabilidade:** MÉDIA
**Impacto:** BAIXO (+$10-20/mês)
**Severidade:** 🟢 BAIXO

**Mitigação:**
- S3 Lifecycle policies (30 dias retention, 90 dias Glacier)
- CloudWatch billing alerts
- Log level tuning (INFO em prod, não DEBUG)

### Risco 4: AWS Price Increases

**Probabilidade:** BAIXA
**Impacto:** BAIXO (+2-5%/ano)
**Severidade:** 🟢 BAIXO

**Mitigação:**
- AWS Price List API monitoring
- Reserved Instances (lock pricing 1-3 anos)
- Diversificação cloud (contingency GCP/Azure)

---

## 📚 Documentos Relacionados

### FinOps

- [costs.md](costs.md) - Breakdown detalhado custos Marco 2
- [BITNAMI-LICENSING-IMPACT-ANALYSIS.md](BITNAMI-LICENSING-IMPACT-ANALYSIS.md) - Análise crítica Bitnami
- [EXECUTIVE-SUMMARY.md](EXECUTIVE-SUMMARY.md) - Resumo executivo start/stop
- [STARTUP-SHUTDOWN-STRATEGY.md](STARTUP-SHUTDOWN-STRATEGY.md) - Estratégia automação

### Decisões Técnicas

- [decisions.md](../context/decisions.md) - ADRs consolidados
- ADR-020: OpenTelemetry Tracing Strategy (Tempo vs Jaeger)
- ADR-021: No-Domain Phase 1 Strategy
- ADR-022: Startup/Shutdown Automation Strategy

### Arquitetura

- [architecture.md](../context/architecture.md) - Arquitetura completa
- [aws-eks-gitlab-quickstart.md](../plan/quickstart/aws-eks-gitlab-quickstart.md) - Plano quickstart Marco 3

---

## 🗓️ Timeline e Milestones

### 2026-01-29 (HOJE)

- ✅ Marco 2 Fase 8 completo (OpenTelemetry)
- ✅ Análise impacto Bitnami concluída
- ⏳ Aguardando aprovação migração Operators

### 2026-02 (Q1 2026)

- [ ] Marco 3 Fase 1 deploy (Operators + Workloads)
- [ ] Reserved Instances EC2 (1 ano)
- [ ] Consolidar ALBs
- [ ] Start/Stop automation GitHub Actions

### 2026-03 - 2026-06 (Q2 2026)

- [ ] S3 Lifecycle Glacier policies
- [ ] VPC Endpoints (S3, ECR)
- [ ] Marco 3 Fase 2 (Com domínio + TLS + SSO)
- [ ] Multi-ambiente (Staging separado)

### 2026-07 - 2026-12 (H2 2026)

- [ ] Spot Instances para dev/staging
- [ ] Savings Plans (avaliar vs RI)
- [ ] Kubecost deployment (cost allocation)
- [ ] Infracost CI/CD integration

### 2027+

- [ ] Karpenter (substituir Cluster Autoscaler)
- [ ] Multi-region DR (se necessário)
- [ ] Reserved Instances 3 anos (após validação 1 ano)

---

## 📞 Contato e Aprovações

**Mantenedores:**
- FinOps Team: finops@empresa.com
- DevOps Lead: devops-lead@empresa.com
- Cloud Architect AWS: cloud-architect@empresa.com

**Aprovações Requeridas:**

- [ ] **CFO:** ___________________ Data: ___/___/___ (Aprovação economia $72k/ano Operators)
- [ ] **CTO:** ___________________ Data: ___/___/___ (Aprovação técnica Marco 3 Operators)
- [ ] **DevOps Lead:** ___________________ Data: ___/___/___ (Compromisso execução 30h)

---

## 🎉 Conclusão

### Resumo Executivo Final

**Custos Atuais:**
- Marco 2 completo: $8,228/ano ($685.70/mês)
- Com economia dev 8h/dia: $3,801/ano ($316.78/mês)

**Projeção Marco 3:**
- Com Operators: $8,845/ano ($737.10/mês) - **RECOMENDADO**
- Com Bitnami Tanzu: $80,845/ano ($6,737.10/mês) - **EVITAR**

**Economia Total:**
- Decisões estratégicas: $80,041/ano
- Start/Stop automation: $4,427/ano (dev 8h/dia)
- **TOTAL:** $84,468/ano economia vs baseline sem otimizações

**Próxima Ação Crítica:**

> **APROVAR migração para Operators (Marco 3) IMEDIATAMENTE**
>
> Evitar custo de $72,000/ano (Tanzu Standard) com investimento de apenas $3,000 (30h).
>
> **ROI: 2,400% Ano 1. Payback: 2 semanas.**

---

**Documento preparado por:** FinOps Specialist + Cloud Architect AWS
**Data:** 2026-01-29
**Versão:** 2.1
**Classificação:** Interno - Confidencial
**Próxima Revisão:** 2026-02-15 (Pós Marco 3 deployment)
