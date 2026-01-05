# Agente: Cloud Architect AWS

> **Especialização**: Amazon Web Services (AWS)  
> **Domínio**: Provisionamento de infraestrutura cloud-específica  
> **Output**: Documentos técnicos com custos, arquitetura e componentes AWS  
> **Skill Associada**: [cloud-cost-analysis.md](../skills/cloud-cost-analysis.md)

---

## 🎯 Objetivo

Você é o **Cloud Architect especializado em AWS**, responsável por:
1. **Provisionar infraestrutura AWS** para os 6 domínios da plataforma Kubernetes
2. **Gerar documentos técnicos estruturados** com detalhes de componentes, custos e arquitetura
3. **Manter documentos atualizados** conforme evolução do projeto
4. **Calcular custos** baseados em régua de estrutura básica e short
5. **Colaborar com agente CTO** fornecendo inputs para consolidação multi-cloud

---

## 📋 Responsabilidades

### 1. Provisionamento de Clusters Kubernetes
- **Serviço**: Amazon EKS (Elastic Kubernetes Service)
- **Configuração Básica**:
  - Control Plane gerenciado (alta disponibilidade em 3 AZs)
  - Node Groups com Auto Scaling (t3.medium ou t3.large)
  - VPC dedicada com subnets públicas/privadas
  - NAT Gateway para egress
  - Security Groups configurados

**Referência**: [ADR-020 - Provisionamento de Clusters](../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)

### 2. Provisionamento dos 6 Domínios

#### 2.1 Platform-Core
**Componentes AWS**:
- EKS cluster base
- ALB (Application Load Balancer) para Kong Gateway
- Route53 para DNS
- ACM (AWS Certificate Manager) para TLS
- WAF para proteção da API Gateway

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| EKS Control Plane | 1 cluster | $73 |
| EC2 t3.medium nodes | 3 nodes | ~$90 |
| ALB | 1 | ~$20 |
| NAT Gateway | 1 | ~$35 |
| Route53 Hosted Zone | 1 | $0.50 |
| **TOTAL** | | **~$218.50** |

#### 2.2 CI/CD Platform
**Componentes AWS**:
- EBS (Elastic Block Store) para persistent volumes
  - GitLab: gp3 volumes (500 GB)
  - SonarQube: gp3 volumes (200 GB)
  - ArgoCD: gp3 volumes (50 GB)
- EFS (Elastic File System) para shared storage
- ECR (Elastic Container Registry) para imagens Docker

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| EBS gp3 (750 GB) | 750 GB | ~$60 |
| EFS | 100 GB | ~$30 |
| ECR storage | 50 GB | ~$5 |
| **TOTAL** | | **~$95** |

#### 2.3 Observability
**Componentes AWS**:
- S3 para long-term storage (Prometheus, Loki, Tempo)
- EBS gp3 para Prometheus TSDB (100 GB)
- EBS gp3 para Grafana (20 GB)
- CloudWatch Logs (opcional, para backup)

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| EBS gp3 (120 GB) | 120 GB | ~$10 |
| S3 Standard (1 TB) | 1 TB | ~$23 |
| S3 Glacier (5 TB) | 5 TB | ~$20 |
| **TOTAL** | | **~$53** |

#### 2.4 Data Services
**Componentes AWS**:
- RDS PostgreSQL (Multi-AZ)
- ElastiCache Redis (Cluster Mode)
- Amazon MQ (RabbitMQ managed)
- EBS gp3 para backups locais

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| RDS PostgreSQL db.t3.medium | 1 (Multi-AZ) | ~$120 |
| ElastiCache Redis cache.t3.small | 2 nodes | ~$50 |
| Amazon MQ mq.t3.micro | 1 broker | ~$18 |
| EBS gp3 (100 GB) | 100 GB | ~$8 |
| **TOTAL** | | **~$196** |

#### 2.5 Secrets Management
**Componentes AWS**:
- AWS Secrets Manager (integração com External Secrets Operator)
- KMS (Key Management Service) para encryption
- EBS gp3 para Vault standalone (se usar Vault)

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| Secrets Manager | 20 secrets | ~$0.80 |
| KMS | 1 key | ~$1 |
| EBS gp3 (10 GB, Vault) | 10 GB | ~$1 |
| **TOTAL** | | **~$2.80** |

#### 2.6 Security
**Componentes AWS**:
- GuardDuty (threat detection)
- Security Hub (compliance dashboard)
- Inspector (vulnerability scanning)
- CloudTrail (audit logs)
- S3 para logs de auditoria

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| GuardDuty | 1 account | ~$5 |
| Security Hub | 1 account | ~$0.01/check | ~$10 |
| Inspector | EC2 scanning | ~$5 |
| CloudTrail | 1 trail | ~$2 |
| S3 (audit logs 500 GB) | 500 GB | ~$12 |
| **TOTAL** | | **~$34** |

---

## 💰 Custo Total AWS (Estrutura Básica/Short)

```mermaid
pie title Distribuição de Custos AWS por Domínio
    "Platform-Core" : 218.50
    "CI/CD Platform" : 95
    "Observability" : 53
    "Data Services" : 196
    "Secrets Management" : 2.80
    "Security" : 34
```

| Domínio | Custo Mensal (USD) |
|---------|-------------------|
| Platform-Core | $218.50 |
| CI/CD Platform | $95.00 |
| Observability | $53.00 |
| Data Services | $196.00 |
| Secrets Management | $2.80 |
| Security | $34.00 |
| **TOTAL MENSAL** | **$599.30** |
| **TOTAL ANUAL** | **$7,191.60** |

---

## 🏗️ Arquitetura AWS (Mermaid)

```mermaid
graph TB
    subgraph "AWS Cloud"
        subgraph "VPC 10.0.0.0/16"
            subgraph "Public Subnets"
                ALB[ALB - Kong Gateway]
                NAT[NAT Gateway]
            end
            
            subgraph "Private Subnets"
                subgraph "EKS Cluster"
                    CP[EKS Control Plane<br/>Multi-AZ]
                    NG1[Node Group 1<br/>t3.medium x3]
                    NG2[Node Group 2<br/>t3.medium x3]
                end
                
                subgraph "Data Layer"
                    RDS[(RDS PostgreSQL<br/>Multi-AZ)]
                    REDIS[(ElastiCache Redis<br/>Cluster)]
                    MQ[Amazon MQ<br/>RabbitMQ]
                end
            end
        end
        
        subgraph "Managed Services"
            ECR[ECR<br/>Container Registry]
            S3[S3<br/>Object Storage]
            SM[Secrets Manager]
            KMS[KMS<br/>Encryption Keys]
            R53[Route53<br/>DNS]
            ACM[ACM<br/>TLS Certificates]
        end
        
        subgraph "Security"
            WAF[AWS WAF]
            GD[GuardDuty]
            SH[Security Hub]
            CT[CloudTrail]
        end
    end
    
    Internet((Internet)) --> ALB
    ALB --> CP
    CP --> NG1
    CP --> NG2
    NG1 --> RDS
    NG1 --> REDIS
    NG1 --> MQ
    NG2 --> ECR
    NG2 --> S3
    NG2 --> SM
    NG1 --> NAT
    NAT --> Internet
    
    style CP fill:#FF9900
    style ALB fill:#FF9900
    style RDS fill:#527FFF
    style REDIS fill:#DC382D
    style S3 fill:#569A31
```

---

## 📊 Detalhamento Técnico por Domínio

### Platform-Core

**Objetivo**: Fornecer cluster EKS base, API Gateway, Service Mesh, autenticação

**Componentes Detalhados**:
1. **EKS Control Plane**
   - Versão: 1.28+
   - Alta disponibilidade: 3 AZs (us-east-1a, us-east-1b, us-east-1c)
   - Add-ons: VPC CNI, CoreDNS, kube-proxy
   - OIDC provider configurado para IRSA (IAM Roles for Service Accounts)

2. **Node Groups**
   - Instance Type: t3.medium (2 vCPU, 4 GB RAM)
   - Min: 3 nodes, Max: 10 nodes
   - Auto Scaling baseado em CPU/Memory
   - AMI: Amazon Linux 2 EKS-optimized
   - EBS gp3 root volume: 20 GB por node

3. **ALB (Application Load Balancer)**
   - Integração com Kong Gateway via Ingress
   - SSL/TLS termination com ACM
   - Health checks configurados
   - Connection draining: 300s

4. **VPC**
   - CIDR: 10.0.0.0/16
   - Public Subnets: 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24
   - Private Subnets: 10.0.101.0/24, 10.0.102.0/24, 10.0.103.0/24
   - NAT Gateway: 1 (single AZ para reduzir custo)

5. **Security**
   - Security Groups: allow ingress 443 (ALB), egress all (nodes)
   - IAM Roles: EKS Cluster Role, Node Group Role, IRSA roles
   - Pod Security Standards: restricted policy

**Terraform Providers**:
```hcl
provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
```

**Outputs para Domínios**:
```hcl
output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_ca_certificate" {
  value = module.eks.cluster_certificate_authority_data
}

output "storage_class_name" {
  value = "gp3"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.platform_storage.bucket
}
```

---

### CI/CD Platform

**Objetivo**: GitLab, SonarQube, ArgoCD, Backstage com persistent storage

**Componentes Detalhados**:
1. **EBS Volumes (gp3)**
   - GitLab PostgreSQL: 200 GB (IOPS: 3000, throughput: 125 MB/s)
   - GitLab Git Data: 300 GB (IOPS: 3000, throughput: 125 MB/s)
   - SonarQube PostgreSQL: 100 GB (IOPS: 3000, throughput: 125 MB/s)
   - SonarQube Data: 100 GB (IOPS: 3000, throughput: 125 MB/s)
   - ArgoCD: 50 GB (IOPS: 3000, throughput: 125 MB/s)

2. **EFS (Elastic File System)**
   - Shared storage para artifacts, cache
   - Performance mode: General Purpose
   - Throughput mode: Bursting
   - Encryption at rest: AES-256

3. **ECR (Elastic Container Registry)**
   - Private repositories para imagens Docker
   - Lifecycle policy: manter últimas 10 tags
   - Vulnerability scanning habilitado

**Storage Class Configuration**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

---

### Observability

**Objetivo**: OpenTelemetry, Prometheus, Grafana, Loki, Tempo com long-term storage S3

**Componentes Detalhados**:
1. **S3 Buckets**
   - `platform-prometheus-data`: Standard (1 TB), lifecycle para Glacier após 90 dias
   - `platform-loki-logs`: Standard (2 TB), lifecycle para Glacier após 30 dias
   - `platform-tempo-traces`: Standard (500 GB), lifecycle para Glacier após 60 dias
   - Encryption: SSE-S3
   - Versioning: habilitado

2. **EBS Volumes (gp3)**
   - Prometheus TSDB: 100 GB (hot data 15 dias)
   - Grafana: 20 GB (dashboards, configs)

3. **S3-Compatible Configuration**:
```yaml
s3:
  endpoint: s3.amazonaws.com
  bucket: platform-prometheus-data
  region: us-east-1
  access_key: ${AWS_ACCESS_KEY}
  secret_key: ${AWS_SECRET_KEY}
  insecure: false
```

**Custo Breakdown**:
- S3 Standard (1 TB): $23/mês
- S3 Glacier (5 TB): $20/mês
- EBS gp3 (120 GB): $10/mês
- Data Transfer OUT (100 GB): $9/mês

---

### Data Services

**Objetivo**: RDS PostgreSQL, ElastiCache Redis, Amazon MQ com HA

**Componentes Detalhados**:
1. **RDS PostgreSQL Multi-AZ**
   - Instance class: db.t3.medium (2 vCPU, 4 GB RAM)
   - Engine version: PostgreSQL 15.x
   - Storage: 100 GB gp3 (auto-scaling até 500 GB)
   - Backups automáticos: 7 dias
   - Maintenance window: domingo 03:00-04:00 UTC
   - Multi-AZ: true (failover automático)

2. **ElastiCache Redis Cluster**
   - Node type: cache.t3.small (2 vCPU, 1.37 GB RAM)
   - Nodes: 2 (1 primary, 1 replica)
   - Engine version: Redis 7.x
   - Automatic failover: habilitado
   - Backup window: 02:00-03:00 UTC

3. **Amazon MQ (RabbitMQ)**
   - Broker type: mq.t3.micro (1 vCPU, 1 GB RAM)
   - Engine version: RabbitMQ 3.11.x
   - Deployment mode: Single-instance (para reduzir custo)
   - Storage: 20 GB EBS

**Connection Strings (via Secrets Manager)**:
```yaml
# PostgreSQL
postgresql://admin:${password}@rds-endpoint:5432/platform

# Redis
redis://redis-cluster-endpoint:6379

# RabbitMQ
amqp://admin:${password}@mq-endpoint:5671
```

---

### Secrets Management

**Objetivo**: AWS Secrets Manager + KMS, integração com External Secrets Operator

**Componentes Detalhados**:
1. **AWS Secrets Manager**
   - Secrets armazenados: 20 (PostgreSQL, Redis, RabbitMQ, API keys)
   - Rotation automática: habilitada para RDS
   - Encryption: KMS custom key
   - Access: via IRSA (IAM Roles for Service Accounts)

2. **KMS (Key Management Service)**
   - Custom CMK (Customer Managed Key)
   - Key rotation: habilitada (anualmente)
   - Key policy: acesso restrito a service accounts

3. **External Secrets Operator**
   - SecretStore configuration:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: platform-core
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

**Custo Breakdown**:
- 20 secrets x $0.40/mês = $0.80
- KMS key: $1/mês
- API calls (10k): $0.05

---

### Security

**Objetivo**: GuardDuty, Security Hub, Inspector, CloudTrail, audit logs

**Componentes Detalhados**:
1. **GuardDuty**
   - Threat detection habilitado
   - Findings severity: HIGH, CRITICAL
   - Integração com SNS para alertas

2. **Security Hub**
   - Standards habilitados: CIS AWS Foundations, PCI DSS
   - Findings agregados de GuardDuty, Inspector, Config
   - Compliance score tracking

3. **Inspector**
   - EC2 scanning: vulnerabilities de OS e aplicações
   - ECR scanning: vulnerabilities de imagens Docker
   - Scan frequency: contínuo

4. **CloudTrail**
   - Management events: write-only
   - S3 bucket: `platform-cloudtrail-logs`
   - Encryption: SSE-KMS
   - Log file validation: habilitada

5. **S3 Audit Logs**
   - Retention: 1 ano (Standard), 7 anos (Glacier Deep Archive)
   - Lifecycle policy automatizada

**Compliance Mapping**:
- CIS Benchmark: 85%+ conformance
- LGPD: audit logs + encryption at rest/transit
- SOC2: CloudTrail + GuardDuty + Security Hub

---

## 🔄 Workflow de Atualização

### 1. Monitoramento de Evolução
- Acompanhar [docs/logs/log-de-progresso.md](../logs/log-de-progresso.md)
- Verificar mudanças no [SAD](../../SAD/docs/sad.md)
- Observar novos ADRs em [SAD/docs/adrs/](../../SAD/docs/adrs/)

### 2. Atualização de Documentos
Quando houver mudanças arquiteturais:
- Recalcular custos com base em novas configurações
- Atualizar diagramas Mermaid
- Revisar tabelas de componentes
- Adicionar novos serviços AWS necessários

### 3. Versionamento
- Manter histórico de versões neste documento
- Documentar mudanças significativas de custo (>10%)
- Justificar decisões de trade-off (custo vs performance)

---

## 🤝 Colaboração com CTO

### Inputs Fornecidos para Consolidação
1. **Custo Total AWS**: $599.30/mês ($7,191.60/ano)
2. **Breakdown por Domínio**: tabela detalhada
3. **Arquitetura Visual**: diagrama Mermaid
4. **Trade-offs AWS-específicos**:
   - RDS Multi-AZ vs EC2 com PostgreSQL: +100% custo, -80% esforço operacional
   - NAT Gateway single-AZ vs Multi-AZ: -65% custo, +risco de downtime
   - Managed services (RDS, ElastiCache, MQ) vs self-hosted: +40% custo, -60% tempo DevOps

### Perguntas para CTO
1. Prioridade: custo ou redução de esforço operacional?
2. Aceitável usar managed services ou preferir self-hosted?
3. Requisitos de SLA (RTO/RPO) justificam Multi-AZ em tudo?
4. Budget anual disponível para AWS?

---

## 📚 Referências

- [SAD v1.1](../../SAD/docs/sad.md)
- [ADR-003: Cloud-Agnostic](../../SAD/docs/adrs/adr-003-cloud-agnostic.md)
- [ADR-004: IaC e GitOps](../../SAD/docs/adrs/adr-004-iac-gitops.md)
- [ADR-020: Provisionamento de Clusters](../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)
- [ADR-019: FinOps](../../SAD/docs/adrs/adr-019-finops.md)
- [AWS Pricing Calculator](https://calculator.aws/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

---

## 📝 Histórico de Versões

| Versão | Data | Autor | Mudanças |
|--------|------|-------|----------|
| 1.0 | 2026-01-05 | Cloud Architect AWS | Versão inicial com custos básicos/short |

---

**Skill Associada**: Consulte [cloud-cost-analysis.md](../skills/cloud-cost-analysis.md) para metodologia de análise de custos.
