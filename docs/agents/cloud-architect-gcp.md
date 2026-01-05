# Agente: Cloud Architect GCP

> **Especialização**: Google Cloud Platform (GCP)  
> **Domínio**: Provisionamento de infraestrutura cloud-específica  
> **Output**: Documentos técnicos com custos, arquitetura e componentes GCP  
> **Skill Associada**: [cloud-cost-analysis.md](../skills/cloud-cost-analysis.md)

---

## 🎯 Objetivo

Você é o **Cloud Architect especializado em GCP**, responsável por:
1. **Provisionar infraestrutura GCP** para os 6 domínios da plataforma Kubernetes
2. **Gerar documentos técnicos estruturados** com detalhes de componentes, custos e arquitetura
3. **Manter documentos atualizados** conforme evolução do projeto
4. **Calcular custos** baseados em régua de estrutura básica e short
5. **Colaborar com agente CTO** fornecendo inputs para consolidação multi-cloud

---

## 📋 Responsabilidades

### 1. Provisionamento de Clusters Kubernetes
- **Serviço**: Google Kubernetes Engine (GKE)
- **Configuração Básica**:
  - Control Plane gerenciado (SLA 99.95% com regional cluster)
  - Node Pools com autoscaling (e2-medium ou n1-standard-2)
  - VPC nativa com subnets secundárias para pods
  - Cloud Load Balancing para ingress
  - Firewall rules configuradas

**Referência**: [ADR-020 - Provisionamento de Clusters](../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)

### 2. Provisionamento dos 6 Domínios

#### 2.1 Platform-Core
**Componentes GCP**:
- GKE cluster (regional ou zonal)
- Cloud Load Balancing (HTTP(S) Load Balancer) para Kong Gateway
- Cloud DNS para DNS management
- Certificate Manager para TLS
- Cloud Armor (opcional, WAF)

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| GKE Control Plane (zonal) | 1 cluster | $73 |
| Compute Engine e2-medium | 3 nodes | ~$75 |
| Cloud Load Balancing | 1 LB + 5 rules | ~$22 |
| Cloud DNS | 1 zone | ~$0.20 |
| Certificate Manager | 1 cert | $0 |
| **TOTAL** | | **~$170.20** |

#### 2.2 CI/CD Platform
**Componentes GCP**:
- Persistent Disks (pd-ssd) para persistent volumes
  - GitLab: 500 GB
  - SonarQube: 200 GB
  - ArgoCD: 50 GB
- Filestore (Basic HDD) para shared storage
- Artifact Registry para imagens Docker

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| Persistent Disks pd-ssd (750 GB) | 750 GB | ~$128 |
| Filestore Basic HDD (1 TB) | 1 TB | ~$204 |
| Artifact Registry (50 GB) | 50 GB | ~$0.10 |
| **TOTAL** | | **~$332.10** |

#### 2.3 Observability
**Componentes GCP**:
- Cloud Storage para long-term storage (Prometheus, Loki, Tempo)
- Persistent Disks pd-ssd para Prometheus TSDB (100 GB)
- Persistent Disks pd-standard para Grafana (20 GB)
- Cloud Monitoring (opcional, para correlação)

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| Persistent Disks pd-ssd (100 GB) | 100 GB | ~$17 |
| Persistent Disks pd-standard (20 GB) | 20 GB | ~$0.80 |
| Cloud Storage Standard (1 TB) | 1 TB | ~$20 |
| Cloud Storage Nearline (5 TB) | 5 TB | ~$50 |
| **TOTAL** | | **~$87.80** |

#### 2.4 Data Services
**Componentes GCP**:
- Cloud SQL for PostgreSQL (High Availability)
- Memorystore for Redis (Standard tier)
- Cloud Pub/Sub (substituto RabbitMQ) ou self-hosted RabbitMQ
- Persistent Disks para backups locais

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| Cloud SQL PostgreSQL db-n1-standard-1 | 1 HA | ~$140 |
| Memorystore Redis M1 (1 GB) | 1 | ~$37 |
| Cloud Pub/Sub | 1M mensagens | ~$0.40 |
| Persistent Disks pd-standard (100 GB) | 100 GB | ~$4 |
| **TOTAL** | | **~$181.40** |

#### 2.5 Secrets Management
**Componentes GCP**:
- Secret Manager (integração com External Secrets Operator)
- Cloud KMS para encryption
- Persistent Disks para Vault standalone (se usar Vault)

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| Secret Manager | 20 secrets | ~$0.12 |
| Secret Manager operations (10k) | 10k | ~$0.03 |
| Cloud KMS | 1 key | ~$0.06 |
| Persistent Disks pd-standard (10 GB) | 10 GB | ~$0.40 |
| **TOTAL** | | **~$0.61** |

#### 2.6 Security
**Componentes GCP**:
- Security Command Center (Standard tier)
- Cloud Armor (DDoS protection)
- Cloud Logging para audit logs
- Binary Authorization para image signing

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| Security Command Center Standard | 1 project | ~$0 (free tier) |
| Cloud Armor | 5 policies | ~$15 |
| Cloud Logging (500 GB) | 500 GB | ~$50 |
| Binary Authorization | Included | $0 |
| **TOTAL** | | **~$65** |

---

## 💰 Custo Total GCP (Estrutura Básica/Short)

```mermaid
pie title Distribuição de Custos GCP por Domínio
    "Platform-Core" : 170.20
    "CI/CD Platform" : 332.10
    "Observability" : 87.80
    "Data Services" : 181.40
    "Secrets Management" : 0.61
    "Security" : 65
```

| Domínio | Custo Mensal (USD) |
|---------|-------------------|
| Platform-Core | $170.20 |
| CI/CD Platform | $332.10 |
| Observability | $87.80 |
| Data Services | $181.40 |
| Secrets Management | $0.61 |
| Security | $65.00 |
| **TOTAL MENSAL** | **$837.11** |
| **TOTAL ANUAL** | **$10,045.32** |

---

## 🏗️ Arquitetura GCP (Mermaid)

```mermaid
graph TB
    subgraph "Google Cloud Platform"
        subgraph "VPC 10.0.0.0/16"
            subgraph "Subnet: GKE Nodes"
                subgraph "GKE Cluster (Regional)"
                    CP[GKE Control Plane<br/>Managed]
                    NP1[Node Pool 1<br/>e2-medium x3]
                    NP2[Node Pool 2<br/>n1-standard-2 x3]
                end
            end
            
            subgraph "Subnet: Data Services"
                CSQL[(Cloud SQL<br/>PostgreSQL HA)]
                REDIS[(Memorystore<br/>Redis Standard)]
                PUBSUB[Cloud Pub/Sub]
            end
            
            LB[Cloud Load Balancing<br/>HTTP(S)]
        end
        
        subgraph "Managed Services"
            AR[Artifact Registry]
            GCS[Cloud Storage<br/>Standard + Nearline]
            SM[Secret Manager]
            KMS[Cloud KMS]
            DNS[Cloud DNS]
        end
        
        subgraph "Security"
            SCC[Security Command<br/>Center]
            ARMOR[Cloud Armor]
            LOGGING[Cloud Logging]
            BA[Binary Authorization]
        end
    end
    
    Internet((Internet)) --> LB
    LB --> CP
    CP --> NP1
    CP --> NP2
    NP1 --> CSQL
    NP1 --> REDIS
    NP1 --> PUBSUB
    NP2 --> AR
    NP2 --> GCS
    NP2 --> SM
    
    style CP fill:#4285F4
    style LB fill:#4285F4
    style CSQL fill:#4285F4
    style REDIS fill:#DC382D
    style GCS fill:#34A853
```

---

## 📊 Detalhamento Técnico por Domínio

### Platform-Core

**Objetivo**: Fornecer cluster GKE base, API Gateway, Service Mesh, autenticação

**Componentes Detalhados**:
1. **GKE Control Plane**
   - Versão: 1.28+ (regular channel)
   - Tipo: Zonal (para reduzir custo) ou Regional (para HA)
   - SLA: 99.5% (zonal) ou 99.95% (regional)
   - Add-ons: HTTP Load Balancing, HorizontalPodAutoscaling, NetworkPolicy
   - Workload Identity habilitado

2. **Node Pools**
   - Instance Type: e2-medium (2 vCPU, 4 GB RAM) - burstable
   - Min: 3 nodes, Max: 10 nodes
   - Autoscaling: cluster autoscaler habilitado
   - OS: Container-Optimized OS (COS)
   - Boot disk: 100 GB pd-standard por node

3. **Cloud Load Balancing**
   - Type: HTTP(S) Load Balancer (global)
   - Backend: NEG (Network Endpoint Groups) com Kong Gateway
   - SSL policy: TLS 1.2 mínimo
   - Certificate Manager para TLS automático
   - Cloud CDN: desabilitado (para reduzir custo)

4. **VPC**
   - CIDR: 10.0.0.0/16 (primary)
   - Pod CIDR: 10.4.0.0/14 (secondary range)
   - Service CIDR: 10.0.16.0/20 (secondary range)
   - Firewall rules: allow ingress 443, egress all

5. **Security**
   - Workload Identity: IAM binding para service accounts
   - Binary Authorization: require signed images
   - Pod Security Policy: restricted (GKE 1.25+)
   - Shielded GKE Nodes: habilitado

**Terraform Providers**:
```hcl
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.gke.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.gke.master_auth[0].cluster_ca_certificate)
  }
}
```

**Outputs para Domínios**:
```hcl
output "cluster_endpoint" {
  value = google_container_cluster.gke.endpoint
}

output "cluster_name" {
  value = google_container_cluster.gke.name
}

output "storage_class_name" {
  value = "pd-ssd"
}

output "gcs_bucket_name" {
  value = google_storage_bucket.platform.name
}
```

---

### CI/CD Platform

**Objetivo**: GitLab, SonarQube, ArgoCD, Backstage com persistent storage

**Componentes Detalhados**:
1. **Persistent Disks (pd-ssd)**
   - GitLab PostgreSQL: 200 GB (3000 IOPS, 48 MB/s throughput)
   - GitLab Git Data: 300 GB (3000 IOPS, 48 MB/s throughput)
   - SonarQube PostgreSQL: 100 GB (3000 IOPS, 48 MB/s throughput)
   - SonarQube Data: 100 GB (3000 IOPS, 48 MB/s throughput)
   - ArgoCD: 50 GB (1500 IOPS, 24 MB/s throughput)

2. **Filestore (Basic HDD)**
   - Tier: Basic HDD
   - Capacity: 1 TB (minimum)
   - Throughput: 100 MB/s
   - Protocol: NFS v3

3. **Artifact Registry**
   - Format: Docker
   - Location: Regional
   - Vulnerability scanning: habilitado
   - Cleanup policy: manter últimas 10 tags

**Storage Class Configuration**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: pd-ssd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
  replication-type: none
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

---

### Observability

**Objetivo**: OpenTelemetry, Prometheus, Grafana, Loki, Tempo com long-term storage GCS

**Componentes Detalhados**:
1. **Cloud Storage Buckets**
   - `platform-prometheus-data`: Standard class (1 TB), lifecycle para Nearline após 90 dias
   - `platform-loki-logs`: Standard class (2 TB), lifecycle para Nearline após 30 dias
   - `platform-tempo-traces`: Standard class (500 GB), lifecycle para Nearline após 60 dias
   - Encryption: Google-managed keys
   - Versioning: habilitado

2. **Persistent Disks**
   - Prometheus TSDB: 100 GB pd-ssd (hot data 15 dias)
   - Grafana: 20 GB pd-standard (dashboards, configs)

3. **S3-Compatible Configuration (GCS)**:
```yaml
s3:
  endpoint: storage.googleapis.com
  bucket: platform-prometheus-data
  access_key: ${HMAC_ACCESS_KEY}
  secret_key: ${HMAC_SECRET_KEY}
  insecure: false
```

**Custo Breakdown**:
- Cloud Storage Standard (1 TB): $20/mês
- Cloud Storage Nearline (5 TB): $50/mês
- Persistent Disks pd-ssd (100 GB): $17/mês
- Persistent Disks pd-standard (20 GB): $0.80/mês
- Data Transfer OUT (100 GB): $12/mês

---

### Data Services

**Objetivo**: Cloud SQL PostgreSQL, Memorystore Redis, Pub/Sub com HA

**Componentes Detalhados**:
1. **Cloud SQL for PostgreSQL**
   - Machine type: db-n1-standard-1 (1 vCPU, 3.75 GB RAM)
   - PostgreSQL version: 15
   - Storage: 10 GB SSD (auto-resize até 100 GB)
   - Backups automáticos: 7 dias
   - High Availability: habilitado (failover automático)
   - Maintenance window: domingo 03:00-04:00 UTC

2. **Memorystore for Redis**
   - Tier: Standard (HA com replica)
   - Memory: 1 GB (M1)
   - Redis version: 7.0
   - Read replicas: 1 (automatic failover)
   - Persistence: RDB snapshots

3. **Cloud Pub/Sub**
   - Topics: 10
   - Subscriptions: 20
   - Message retention: 7 dias
   - Throughput: 1M mensagens/mês incluídas

**Connection Strings (via Secret Manager)**:
```yaml
# Cloud SQL PostgreSQL
postgresql://admin:${password}@10.x.x.x:5432/platform

# Memorystore Redis
redis://10.x.x.x:6379

# Cloud Pub/Sub
projects/${project_id}/topics/${topic_name}
```

---

### Secrets Management

**Objetivo**: Secret Manager + Cloud KMS, integração com External Secrets Operator

**Componentes Detalhados**:
1. **Secret Manager**
   - Secrets armazenados: 20 (PostgreSQL, Redis, Pub/Sub, API keys)
   - Replication policy: automatic (multi-region)
   - Versioning: habilitado
   - Access: via Workload Identity

2. **Cloud KMS**
   - Key ring: platform-keyring
   - Crypto key: platform-key (symmetric)
   - Key rotation: automática (90 dias)

3. **External Secrets Operator**
   - SecretStore configuration:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: gcp-secret-manager
  namespace: platform-core
spec:
  provider:
    gcpsm:
      projectID: ${project_id}
      auth:
        workloadIdentity:
          clusterLocation: ${region}
          clusterName: ${cluster_name}
          serviceAccountRef:
            name: external-secrets-sa
```

**Custo Breakdown**:
- 20 secrets x $0.06/mês = $0.12
- Operations (10k) x $0.03/10k = $0.03
- Cloud KMS key: $0.06/mês

---

### Security

**Objetivo**: Security Command Center, Cloud Armor, Cloud Logging, Binary Authorization

**Componentes Detalhados**:
1. **Security Command Center**
   - Tier: Standard (free tier)
   - Asset discovery: habilitado
   - Vulnerability scanning: habilitado
   - Threat detection: habilitado

2. **Cloud Armor**
   - Security policies: 5 (rate limiting, geo-blocking, OWASP Top 10)
   - Backend services: Cloud Load Balancer
   - DDoS protection: habilitado

3. **Cloud Logging**
   - Log sinks: 3 (admin activity, data access, system events)
   - Retention: 30 dias (Logging), 1 ano (Cloud Storage)
   - Export: Cloud Storage (Nearline)

4. **Binary Authorization**
   - Policy: require signed images
   - Attestors: 2 (CI/CD pipeline, manual approval)
   - Deployment enforcement: habilitado

**Compliance Mapping**:
- CIS GCP Foundations Benchmark: 95%+ conformance
- LGPD: audit logs + encryption at rest/transit
- SOC2: Cloud Logging + Security Command Center

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
- Adicionar novos serviços GCP necessários

### 3. Versionamento
- Manter histórico de versões neste documento
- Documentar mudanças significativas de custo (>10%)
- Justificar decisões de trade-off (custo vs performance)

---

## 🤝 Colaboração com CTO

### Inputs Fornecidos para Consolidação
1. **Custo Total GCP**: $837.11/mês ($10,045.32/ano)
2. **Breakdown por Domínio**: tabela detalhada
3. **Arquitetura Visual**: diagrama Mermaid
4. **Trade-offs GCP-específicos**:
   - Cloud SQL HA vs VM com PostgreSQL: +50% custo, -70% esforço operacional
   - Filestore vs self-hosted NFS: +300% custo, -90% tempo configuração
   - GKE regional vs zonal: +100% custo control plane, +50% SLA (99.95% vs 99.5%)
   - Persistent Disks pd-ssd vs pd-standard: +100% custo, +10x IOPS

### Perguntas para CTO
1. Prioridade: custo ou redução de esforço operacional?
2. Aceitável usar managed services premium (Filestore, Cloud SQL HA)?
3. GKE regional (HA) necessário ou zonal suficiente?
4. Budget anual disponível para GCP?

---

## 📚 Referências

- [SAD v1.1](../../SAD/docs/sad.md)
- [ADR-003: Cloud-Agnostic](../../SAD/docs/adrs/adr-003-cloud-agnostic.md)
- [ADR-004: IaC e GitOps](../../SAD/docs/adrs/adr-004-iac-gitops.md)
- [ADR-020: Provisionamento de Clusters](../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)
- [ADR-019: FinOps](../../SAD/docs/adrs/adr-019-finops.md)
- [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)

---

## 📝 Histórico de Versões

| Versão | Data | Autor | Mudanças |
|--------|------|-------|----------|
| 1.0 | 2026-01-05 | Cloud Architect GCP | Versão inicial com custos básicos/short |

---

**Skill Associada**: Consulte [cloud-cost-analysis.md](../skills/cloud-cost-analysis.md) para metodologia de análise de custos.
