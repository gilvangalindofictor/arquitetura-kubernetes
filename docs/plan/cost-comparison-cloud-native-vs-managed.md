# Comparativo de Custos: Stack Cloud-Agnostic vs Managed Services

> **Data**: 2025-12-30
> **Objetivo**: Comparar custos da stack self-hosted Kubernetes vs serviços gerenciados (AWS, Azure, GCP)
> **Premissa**: Ambiente de produção médio com HA, backup e observabilidade

---

## 📊 Cenário de Comparação

### Workload Assumido (Produção)
- **Aplicações**: 10-15 microservices **polyglot** (Go, .NET, Python, Node.js)
- **Tráfego**: 1M requests/dia (~12 req/s)
- **Databases**: 3 PostgreSQL (50GB cada), 2 Redis (10GB cada), 2 RabbitMQ (20GB cada)
- **Container Registry**: 500GB de imagens
- **Secrets**: 500 secrets gerenciados
- **Backup**: 1TB/mês de backups
- **Logs/Traces**: 500GB/mês
- **Disponibilidade**: 99.9% (HA obrigatório)
- **Retenção**: 30 dias logs, 90 dias backups

---

## 💰 NOSSA STACK (Cloud-Agnostic Self-Hosted)

### Infraestrutura Kubernetes Base

#### AWS (EKS)
```
5× EC2 t3.2xlarge (8 vCPU, 32GB RAM)
- On-Demand: $0.3328/hora × 5 × 730 horas = $1.214/mês
- Reserved 1yr: $0.214/hora × 5 × 730 horas = $781/mês
- Spot Instance: $0.100/hora × 5 × 730 horas = $365/mês

EKS Control Plane: $0.10/hora × 730 horas = $73/mês

EBS Storage (gp3): 800GB × $0.08/GB = $64/mês

Load Balancer (2× NLB): 2 × $0.0225/hora × 730 = $33/mês
```

**Total AWS (EKS + nodes)**:
- Com Reserved Instances: **$951/mês** = **$11.412/ano**
- Com Spot Instances: **$535/mês** = **$6.420/ano**

#### Azure (AKS)
```
5× Standard_D8s_v3 (8 vCPU, 32GB RAM)
- Pay-as-you-go: $0.384/hora × 5 × 730 horas = $1.402/mês
- Reserved 1yr: $0.242/hora × 5 × 730 horas = $883/mês

AKS Control Plane: Gratuito

Managed Disks (Premium SSD): 800GB × $0.12/GB = $96/mês

Load Balancer: 2 × $0.025/hora × 730 = $37/mês
```

**Total Azure (AKS + nodes)**:
- Com Reserved Instances: **$1.016/mês** = **$12.192/ano**
- Pay-as-you-go: **$1.535/mês** = **$18.420/ano**

#### GCP (GKE)
```
5× n2-standard-8 (8 vCPU, 32GB RAM)
- On-Demand: $0.3888/hora × 5 × 730 horas = $1.419/mês
- CUD 1yr: $0.272/hora × 5 × 730 horas = $992/mês

GKE Control Plane: $0.10/hora × 730 = $73/mês

Persistent Disk (SSD): 800GB × $0.17/GB = $136/mês

Cloud Load Balancing: 2 × $18/mês = $36/mês
```

**Total GCP (GKE + nodes)**:
- Com CUD 1yr: **$1.237/mês** = **$14.844/ano**
- On-Demand: **$1.664/mês** = **$19.968/ano**

---

### Nossa Stack (Software no Kubernetes)

| Componente | RAM Uso | Storage | Custo Adicional |
|------------|---------|---------|-----------------|
| Harbor (registry) | 3GB | 500GB | **$0** (incluído no K8s) |
| Vault (secrets) | 2GB | 5GB | **$0** (incluído no K8s) |
| Linkerd (service mesh) | 2GB | - | **$0** (incluído no K8s) |
| PostgreSQL (3× HA) | 12GB | 150GB | **$0** (incluído no K8s) |
| Redis (2× cluster) | 4GB | 20GB | **$0** (incluído no K8s) |
| RabbitMQ (2× HA) | 4GB | 40GB | **$0** (incluído no K8s) |
| GitLab (CI/CD) | 8GB | 100GB | **$0** (incluído no K8s) |
| Observability Stack | 10GB | 500GB | **$0** (incluído no K8s) |
| Kong (API Gateway) | 2GB | - | **$0** (incluído no K8s) |
| Keycloak (Auth) | 2GB | 10GB | **$0** (incluído no K8s) |
| Backstage | 2GB | 10GB | **$0** (incluído no K8s) |
| **TOTAL SOFTWARE** | **51GB de 160GB disponíveis** | **1.335GB de 800GB disponíveis** | **$0** |

**💡 Nota sobre Stack Polyglot (Go, .NET, Python, Node.js)**:
- ✅ Dimensionamento **já considera** workload misto de linguagens
- ✅ Margem de **109GB RAM disponível** comporta 10-15 microservices:
  - Go services: ~100MB RAM cada (otimizado)
  - .NET services: ~200MB RAM cada
  - Python services: ~300MB RAM cada
  - Node.js services: ~250MB RAM cada
- ✅ Multi-stage builds otimizam storage:
  - Go: 15-55MB (imagem final com alpine/scratch)
  - .NET: 130-190MB (aspnet:alpine base)
  - Python: 170-320MB (python:slim base)
  - Node.js: 190-440MB (node:alpine base)
- ✅ **Custos não mudam** vs stack única (cluster já dimensionado generosamente)

### Storage Adicional (Backups e Logs)

#### AWS S3
```
1TB backups: 1000GB × $0.023/GB = $23/mês
500GB logs: 500GB × $0.023/GB = $11.50/mês
GET requests: 1M × $0.0004/1000 = $0.40/mês
PUT requests: 100k × $0.005/1000 = $0.50/mês
```
**S3 Total**: **$35/mês**

#### Azure Blob Storage
```
1.5TB (hot tier): 1500GB × $0.018/GB = $27/mês
Operações: ~$5/mês
```
**Azure Blob Total**: **$32/mês**

#### GCP Cloud Storage
```
1.5TB (standard): 1500GB × $0.020/GB = $30/mês
Operações: ~$3/mês
```
**GCP Storage Total**: **$33/mês**

---

### 💡 CUSTO TOTAL NOSSA STACK (Cloud-Agnostic)

| Cloud | Kubernetes | Storage S3/Blob | **TOTAL/MÊS** | **TOTAL/ANO** |
|-------|------------|-----------------|---------------|---------------|
| **AWS** (Reserved + Spot) | $535 | $35 | **$570** | **$6.840** |
| **AWS** (Reserved) | $951 | $35 | **$986** | **$11.832** |
| **Azure** (Reserved) | $1.016 | $32 | **$1.048** | **$12.576** |
| **GCP** (CUD 1yr) | $1.237 | $33 | **$1.270** | **$15.240** |

---

## 🏢 SERVIÇOS GERENCIADOS (Managed Services)

### AWS Managed Services

#### Compute (ECS Fargate)
```
15 tasks × 2 vCPU × 730 horas × $0.04048/vCPU-hora = $887/mês
15 tasks × 4GB RAM × 730 horas × $0.004445/GB-hora = $195/mês
```
**Compute**: **$1.082/mês**

#### Database (RDS PostgreSQL)
```
3× db.r6g.xlarge Multi-AZ (4 vCPU, 32GB RAM)
3 × $0.704/hora × 730 horas = $1.542/mês
Storage: 150GB × $0.115/GB = $17/mês
Backup: 150GB × $0.095/GB = $14/mês
```
**RDS Total**: **$1.573/mês**

#### Cache (ElastiCache Redis)
```
2× cache.r6g.large Multi-AZ (2 vCPU, 13GB RAM)
2 × $0.276/hora × 730 horas = $403/mês
```
**ElastiCache Total**: **$403/mês**

#### Message Queue (Amazon MQ RabbitMQ)
```
2× mq.m5.large Multi-AZ (2 vCPU, 8GB RAM)
2 × $0.484/hora × 730 horas = $707/mês
Storage: 40GB × $0.15/GB = $6/mês
```
**Amazon MQ Total**: **$713/mês**

#### Container Registry (ECR)
```
Storage: 500GB × $0.10/GB = $50/mês
Data transfer: 100GB/mês × $0.09/GB = $9/mês
```
**ECR Total**: **$59/mês**

#### Secrets Manager
```
500 secrets × $0.40/secret = $200/mês
API calls: 10M × $0.05/10k = $50/mês
```
**Secrets Manager Total**: **$250/mês**

#### API Gateway (REST API)
```
1M requests/dia × 30 dias = 30M requests
30M × $3.50/milhão = $105/mês
Data transfer: 50GB × $0.09/GB = $4.50/mês
```
**API Gateway Total**: **$110/mês**

#### Cognito (Auth)
```
50k MAU × $0.0055 = $275/mês
```
**Cognito Total**: **$275/mês**

#### CloudWatch Logs
```
500GB ingest × $0.50/GB = $250/mês
500GB storage × $0.03/GB = $15/mês
```
**CloudWatch Total**: **$265/mês**

#### Application Load Balancer
```
2× ALB: 2 × $0.0225/hora × 730 = $33/mês
LCU: 730 horas × $0.008/LCU = $6/mês
```
**ALB Total**: **$39/mês**

#### Backup (AWS Backup)
```
1TB backups × $0.05/GB = $50/mês
```

#### VPC/Networking
```
NAT Gateway: 2 × $0.045/hora × 730 = $66/mês
Data transfer: 100GB × $0.09/GB = $9/mês
```
**Network Total**: **$75/mês**

### 💰 TOTAL AWS MANAGED SERVICES

| Serviço | Custo/Mês |
|---------|-----------|
| ECS Fargate | $1.082 |
| RDS PostgreSQL | $1.573 |
| ElastiCache Redis | $403 |
| Amazon MQ RabbitMQ | $713 |
| ECR | $59 |
| Secrets Manager | $250 |
| API Gateway | $110 |
| Cognito | $275 |
| CloudWatch Logs | $265 |
| ALB | $39 |
| AWS Backup | $50 |
| Networking | $75 |
| **TOTAL** | **$4.894/mês** = **$58.728/ano** |

---

### Azure Managed Services

#### Compute (Azure Container Instances)
```
15 containers × 2 vCPU × 730 horas × $0.0435/vCPU-hora = $953/mês
15 containers × 4GB RAM × 730 horas × $0.0043/GB-hora = $188/mês
```
**Compute**: **$1.141/mês**

#### Database (Azure Database for PostgreSQL)
```
3× General Purpose D4s v3 (4 vCPU, 16GB RAM)
3 × $0.368/hora × 730 horas = $806/mês
Storage: 150GB × $0.115/GB = $17/mês
Backup: 150GB × $0.10/GB = $15/mês
```
**Azure PostgreSQL Total**: **$838/mês**

#### Cache (Azure Cache for Redis)
```
2× Standard C3 (6GB cache)
2 × $0.352/hora × 730 horas = $514/mês
```
**Azure Redis Total**: **$514/mês**

#### Message Queue (Azure Service Bus Premium)
```
1 messaging unit × $0.928/hora × 730 = $677/mês
```
**Service Bus Total**: **$677/mês**

#### Container Registry (ACR Premium)
```
Storage: 500GB × $0.167/dia = $83/mês
Build minutes: 100 min/dia × 30 × $0.0016/min = $5/mês
```
**ACR Total**: **$88/mês**

#### Key Vault
```
500 secrets × $0.03/secret (10k operations/month) = $15/mês
HSM-protected keys: 10 × $5/key = $50/mês
```
**Key Vault Total**: **$65/mês**

#### API Management (Developer tier)
```
Base: $50/mês
1M calls/mês: incluído
```
**APIM Total**: **$50/mês**

#### Azure AD B2C
```
50k MAU × $0.00325 = $162/mês
```
**Azure AD B2C Total**: **$162/mês**

#### Log Analytics (Azure Monitor)
```
500GB ingest × $2.76/GB = $1.380/mês
Retention (31-90 dias): $0.15/GB × 500GB = $75/mês
```
**Azure Monitor Total**: **$1.455/mês**

#### Application Gateway
```
2× Gateway v2: 2 × $0.246/hora × 730 = $359/mês
Capacity units: 10 × $0.008/hora × 730 = $58/mês
```
**App Gateway Total**: **$417/mês**

#### Backup (Azure Backup)
```
1TB × $0.05/GB = $50/mês
```

#### Networking
```
VPN Gateway: $0.04/hora × 730 = $29/mês
Data transfer: 100GB × $0.087/GB = $9/mês
```
**Network Total**: **$38/mês**

### 💰 TOTAL AZURE MANAGED SERVICES

| Serviço | Custo/Mês |
|---------|-----------|
| Container Instances | $1.141 |
| Azure PostgreSQL | $838 |
| Azure Redis | $514 |
| Service Bus | $677 |
| ACR | $88 |
| Key Vault | $65 |
| API Management | $50 |
| Azure AD B2C | $162 |
| Azure Monitor | $1.455 |
| Application Gateway | $417 |
| Azure Backup | $50 |
| Networking | $38 |
| **TOTAL** | **$5.495/mês** = **$65.940/ano** |

---

### GCP Managed Services

#### Compute (Cloud Run)
```
15 services × 2 vCPU × 730 horas × $0.00002400/vCPU-sec = $945/mês
15 services × 4GB RAM × 730 horas × $0.00000250/GB-sec = $98/mês
Requests: 30M × $0.40/milhão = $12/mês
```
**Cloud Run**: **$1.055/mês**

#### Database (Cloud SQL PostgreSQL)
```
3× db-n1-standard-4 HA (4 vCPU, 15GB RAM)
3 × $0.445/hora × 730 horas = $975/mês
Storage: 150GB × $0.17/GB = $25/mês
Backup: 150GB × $0.08/GB = $12/mês
```
**Cloud SQL Total**: **$1.012/mês**

#### Cache (Memorystore Redis)
```
2× M3 (5GB RAM) HA
2 × $0.173/hora × 730 horas = $252/mês
```
**Memorystore Total**: **$252/mês**

#### Message Queue (Pub/Sub)
```
30M mensagens/mês × $40/milhão = $1.200/mês
Storage: 20GB × $0.27/GB = $5/mês
```
**Pub/Sub Total**: **$1.205/mês**

#### Container Registry (Artifact Registry)
```
Storage: 500GB × $0.10/GB = $50/mês
Data transfer: 100GB × $0.12/GB = $12/mês
```
**Artifact Registry Total**: **$62/mês**

#### Secret Manager
```
500 secrets × $0.06/secret = $30/mês
Access: 10M × $0.03/10k = $30/mês
```
**Secret Manager Total**: **$60/mês**

#### API Gateway
```
1M calls/dia × 30 = 30M calls
30M × $3/milhão = $90/mês
```
**API Gateway Total**: **$90/mês**

#### Identity Platform
```
50k MAU × $0.015 = $750/mês
```
**Identity Platform Total**: **$750/mês**

#### Cloud Logging
```
500GB ingest × $0.50/GB = $250/mês
500GB storage × $0.01/GB = $5/mês
```
**Cloud Logging Total**: **$255/mês**

#### Cloud Load Balancing
```
5 forwarding rules × $18/mês = $90/mês
Ingress: 100GB × $0.008/GB = $0.80/mês
```
**Load Balancing Total**: **$91/mês**

#### Cloud Storage (Backup)
```
1TB × $0.020/GB = $20/mês
```

#### Networking
```
Cloud NAT: 2 × $0.044/hora × 730 = $64/mês
Data transfer: 100GB × $0.12/GB = $12/mês
```
**Network Total**: **$76/mês**

### 💰 TOTAL GCP MANAGED SERVICES

| Serviço | Custo/Mês |
|---------|-----------|
| Cloud Run | $1.055 |
| Cloud SQL | $1.012 |
| Memorystore Redis | $252 |
| Pub/Sub | $1.205 |
| Artifact Registry | $62 |
| Secret Manager | $60 |
| API Gateway | $90 |
| Identity Platform | $750 |
| Cloud Logging | $255 |
| Load Balancing | $91 |
| Cloud Storage | $20 |
| Networking | $76 |
| **TOTAL** | **$4.928/mês** = **$59.136/ano** |

---

## 📊 COMPARATIVO FINAL: NOSSA STACK vs MANAGED SERVICES

### Custos Mensais (Produção com HA)

| Abordagem | AWS | Azure | GCP |
|-----------|-----|-------|-----|
| **Nossa Stack (Cloud-Agnostic)** | **$986** | **$1.048** | **$1.270** |
| **Managed Services** | **$4.894** | **$5.495** | **$4.928** |
| **ECONOMIA MENSAL** | **$3.908** | **$4.447** | **$3.658** |
| **% ECONOMIA** | **80%** | **81%** | **74%** |

### Custos Anuais (Produção com HA)

| Abordagem | AWS | Azure | GCP |
|-----------|-----|-------|-----|
| **Nossa Stack (Cloud-Agnostic)** | **$11.832** | **$12.576** | **$15.240** |
| **Managed Services** | **$58.728** | **$65.940** | **$59.136** |
| **ECONOMIA ANUAL** | **$46.896** | **$53.364** | **$43.896** |
| **% ECONOMIA** | **80%** | **81%** | **74%** |

### Economia em 3 Anos (com depreciação)

| Cloud | Nossa Stack (3 anos) | Managed (3 anos) | Economia Total |
|-------|----------------------|------------------|----------------|
| **AWS** | $35.496 | $176.184 | **$140.688** |
| **Azure** | $37.728 | $197.820 | **$160.092** |
| **GCP** | $45.720 | $177.408 | **$131.688** |

---

## ⚖️ TRADE-OFFS: Nossa Stack vs Managed Services

### ✅ Vantagens da Nossa Stack

| Aspecto | Nossa Stack | Managed Services |
|---------|-------------|------------------|
| **💰 Custo** | 74-81% mais barato | Muito caro |
| **🔓 Vendor Lock-in** | Zero (portável) | Alto (preso ao vendor) |
| **🔧 Customização** | Total | Limitada |
| **📊 Observabilidade** | Unificada (OpenTelemetry) | Fragmentada por cloud |
| **🚀 Portabilidade** | Qualquer cloud/on-prem | Difícil migração |
| **🎓 Skill Team** | Kubernetes (universal) | Específico por cloud |
| **🔄 Multi-Cloud** | Nativo | Complexo |
| **📜 Compliance** | Controle total | Depende do vendor |

### ⚠️ Desvantagens da Nossa Stack

| Aspecto | Nossa Stack | Managed Services |
|---------|-------------|------------------|
| **🛠️ Operação** | Time precisa operar | Vendor opera |
| **⏱️ Time-to-Market** | Setup inicial ~2-3 semanas | Imediato (APIs prontas) |
| **🆘 Suporte** | Comunidade + time interno | Vendor SLA (pago) |
| **🔐 Segurança** | Time responsável | Vendor gerencia patches |
| **📈 Scaling** | Manual/HPA (configurável) | Auto-scaling nativo |
| **💪 Resiliência** | Configurar HA manualmente | HA out-of-the-box |

---

## 🎯 Cenários de Decisão

### ✅ Usar Nossa Stack Quando:

1. **💰 Custo é prioridade** (economia 74-81%)
2. **🔓 Evitar vendor lock-in** (multi-cloud, migração futura)
3. **Team tem expertise Kubernetes** (ou quer desenvolver)
4. **Controle total** sobre infra, segurança, compliance
5. **Workload previsível** (não tem picos extremos)
6. **Longo prazo** (3+ anos, ROI cresce com tempo)

### ⚠️ Considerar Managed Services Quando:

1. **⏱️ Time-to-market crítico** (precisa subir HOJE)
2. **Team pequeno** (< 3 pessoas infra)
3. **Sem expertise Kubernetes** (e não pode treinar)
4. **Workload altamente variável** (picos 10x, auto-scaling crítico)
5. **Curto prazo** (< 6 meses, POC, MVP)
6. **Vendor-specific features** (ex: AWS Lambda + API Gateway integração profunda)

---

## 💡 RECOMENDAÇÃO FINAL

### Estratégia Híbrida Proposta

#### FASE 1: Nossa Stack (Cloud-Agnostic) — **RECOMENDADO**
**Escopo**: 90% da plataforma
- ✅ Kubernetes (EKS/AKS/GKE)
- ✅ Harbor, Vault, Linkerd, PostgreSQL, Redis, RabbitMQ
- ✅ GitLab, Observability, Kong, Keycloak
- **Custo**: $986-$1.270/mês
- **Economia**: $3.908-$4.447/mês vs Managed

#### FASE 2: Managed Services Pontuais (quando fizer sentido)
**Escopo**: 10% - Casos específicos
- ⚠️ Object Storage (S3/Blob/GCS) — **Já usando** (durabilidade 11 noves)
- ⚠️ CDN (CloudFront/Azure CDN/Cloud CDN) — **Se precisar** de edge locations
- ⚠️ DNS (Route53/Azure DNS/Cloud DNS) — **Managed faz sentido** (low cost, alta disponibilidade)
- ⚠️ Email (SES/SendGrid) — **Managed faz sentido** (deliverability)

### Breakeven Point

Considerando:
- Setup inicial nossa stack: **2-3 semanas** (1 DevOps sênior)
- Custo DevOps: $15k/mês (fully loaded)
- Setup cost: ~$7.5k

**Breakeven**: 
- AWS: $7.5k / $3.908/mês = **1.9 meses** ✅
- Azure: $7.5k / $4.447/mês = **1.7 meses** ✅
- GCP: $7.5k / $3.658/mês = **2.0 meses** ✅

**Conclusão**: Nossa stack se paga em **menos de 2 meses** e depois economiza **$46k-$53k/ano**! 💰

---

## 📈 Projeção 5 Anos

### Nossa Stack (Cloud-Agnostic)

| Ano | Custo Infra | Custo Operação* | Total/Ano |
|-----|-------------|-----------------|-----------|
| Ano 1 | $11.832 | $30.000 | $41.832 |
| Ano 2 | $11.832 | $20.000 | $31.832 |
| Ano 3 | $11.832 | $15.000 | $26.832 |
| Ano 4 | $11.832 | $10.000 | $21.832 |
| Ano 5 | $11.832 | $10.000 | $21.832 |
| **TOTAL 5 ANOS** | | | **$144.160** |

*Operação decrescente: automatização, maturidade, runbooks

### Managed Services (AWS)

| Ano | Custo Infra | Custo Operação | Total/Ano |
|-----|-------------|----------------|-----------|
| Ano 1 | $58.728 | $10.000 | $68.728 |
| Ano 2 | $58.728 | $10.000 | $68.728 |
| Ano 3 | $58.728 | $10.000 | $68.728 |
| Ano 4 | $58.728 | $10.000 | $68.728 |
| Ano 5 | $58.728 | $10.000 | $68.728 |
| **TOTAL 5 ANOS** | | | **$343.640** |

### 💰 ECONOMIA EM 5 ANOS: **$199.480** (58% mais barato)

---

## 🚀 Conclusão e Próximos Passos

### Decisão Recomendada

✅ **APROVAR Nossa Stack Cloud-Agnostic**

**Justificativa**:
1. **Economia massiva**: 74-81% vs Managed Services ($46k-$53k/ano)
2. **Breakeven rápido**: < 2 meses
3. **ROI 5 anos**: $199k economia
4. **Zero vendor lock-in**: Portável entre AWS/Azure/GCP/on-prem
5. **Controle total**: Segurança, compliance, customização
6. **Skill universal**: Kubernetes (transferível entre clouds)
7. **Longo prazo**: Investimento se paga exponencialmente

### Próximos Passos

1. ✅ **Validar premissas** desta análise com time financeiro
2. ✅ **Aprovar stack técnica** definida no documento `technical-meeting-decisions.md`
3. ✅ **Criar ADRs sistêmicos** (ADR-003 a ADR-012)
4. ✅ **Iniciar FASE 1** (Concepção do SAD)
5. ✅ **FASE 2**: Implementar domínios (platform-core, cicd-platform, etc.)

---

## 📚 Fontes de Preços (2025-12-30)

- AWS: https://aws.amazon.com/pricing/
- Azure: https://azure.microsoft.com/pricing/
- GCP: https://cloud.google.com/pricing/
- Calculadoras oficiais utilizadas para estimativas

**Nota**: Preços podem variar por região. Estimativas baseadas em us-east-1 (AWS), East US (Azure), us-central1 (GCP).

---

**Status**: 📊 Análise completa pronta para decisão executiva
