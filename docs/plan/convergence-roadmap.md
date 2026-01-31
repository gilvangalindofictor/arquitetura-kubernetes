# 🛣️ Roadmap de Convergência: AWS EKS → Plataforma Cloud-Agnostic

**Versão:** 1.0
**Data:** 2026-01-30
**Status:** 🎯 Ativo - Definição da Estratégia Dual

---

## 📋 Visão Geral

Este documento estabelece a **hierarquia de prioridades** e o **roadmap de convergência** entre dois escopos do projeto:

1. **Projeto Ativo (Fase 1):** AWS EKS GitLab Quickstart - Implementação prática e operacional
2. **Visão de Longo Prazo (Fase 2+):** Plataforma Kubernetes Cloud-Agnostic completa

---

## 🎯 Definição de Prioridades

### Projeto Ativo: AWS EKS GitLab Quickstart

**Status:** 🟢 **PROJETO PRINCIPAL ATIVO**

**Documento Base:** [aws-eks-gitlab-quickstart.md](quickstart/aws-eks-gitlab-quickstart.md)

**Escopo:**
- ✅ Plataforma Kubernetes operacional na AWS
- ✅ GitLab CI/CD completo (Helm hybrid)
- ✅ Observability Stack (OpenTelemetry, Prometheus, Grafana, Loki, Tempo)
- ✅ Data Services via Operators (PostgreSQL RDS, Redis Operator, RabbitMQ Operator)
- ✅ Security baseline (Network Policies, WAF, RBAC)
- ✅ 2 Ambientes (Staging scheduled + Prod 24/7)

**Objetivo:** Entregar plataforma funcional para desenvolvimento interno em **8 semanas**

**Custo:** R$ 3.624/mês (USD $604) - otimizado com automação FinOps

**Benefícios:**
- ✅ Resultado tangível e operacional rápido
- ✅ Custos controlados e otimizados
- ✅ Fundações arquiteturais corretas para evolução
- ✅ Validação prática de decisões técnicas

---

### Visão de Longo Prazo: Plataforma Cloud-Agnostic

**Status:** 📋 **VISÃO ESTRATÉGICA (Fase 2+)**

**Documento Base:** [README.md](../../README.md) + [SAD](../../SAD/docs/sad.md)

**Escopo:**
- 📋 6 Domínios especializados independentes
- 📋 Multi-cloud ready (AWS, Azure, GCP, on-premise)
- 📋 Zero dependências de cloud providers
- 📋 Service Mesh completo (Istio/Linkerd)
- 📋 Secrets Management avançado (Vault)
- 📋 Developer Portal (Backstage)
- 📋 Security avançado (Kyverno, Falco, Trivy)

**Objetivo:** Plataforma corporativa de engenharia completa **cloud-agnostic**

**Timeline:** 12-18 meses (após validação Fase 1)

**Benefícios:**
- ✅ Portabilidade total entre clouds
- ✅ Independência de vendor lock-in
- ✅ Escalabilidade multi-domínio
- ✅ Maturidade Platform Engineering

---

## 🔄 Estratégia de Convergência

### Princípios de Design

1. **AWS-First, Cloud-Agnostic by Design**
   - Implementar primeiro na AWS (rápido, prático)
   - Usar sempre padrões Kubernetes nativos
   - Evitar recursos AWS-specific quando possível
   - Documentar dependências AWS claramente

2. **Evolução Incremental**
   - Cada marco AWS já contempla portabilidade
   - Refatoração mínima para migração futura
   - Módulos Terraform parametrizados

3. **Validação Contínua**
   - Testar decisões técnicas na prática
   - Ajustar visão estratégica com aprendizados
   - ADRs evoluem com experiência real

---

## 📊 Mapeamento de Convergência

### Marco 0: Baseline ✅ COMPLETO

| Componente | AWS Atual | Cloud-Agnostic | Gap | Esforço |
|------------|-----------|---------------|-----|---------|
| **VPC/Networking** | AWS VPC (10.0.0.0/16) | Qualquer VPC/VNet | Terraform providers | Baixo |
| **State Backend** | S3 + DynamoDB | S3/GCS/Azure Blob | Backend remoto | Baixo |
| **IAM** | AWS IAM Roles | RBAC K8s nativo | Abstração | Médio |

**Portabilidade:** 🟡 60% (VPC é AWS-specific, mas padrões CIDR reutilizáveis)

---

### Marco 1: EKS Cluster ✅ COMPLETO

| Componente | AWS Atual | Cloud-Agnostic | Gap | Esforço |
|------------|-----------|---------------|-----|---------|
| **Cluster** | Amazon EKS 1.31 | AKS, GKE, kubeadm | Terraform provider | Baixo |
| **Node Groups** | EC2 Auto Scaling Groups | VM Scale Sets, MIGs | Provider-specific | Baixo |
| **Networking** | AWS VPC CNI | Calico, Cilium | CNI plugin | Médio |
| **Storage** | EBS CSI Driver | Cloud CSI Drivers | CSI padrão | Baixo |
| **IRSA** | IAM Roles for Service Accounts | Workload Identity, Pod Identity | Abstração | Médio |

**Portabilidade:** 🟡 70% (Kubernetes API é agnóstico, apenas provisioning é cloud-specific)

---

### Marco 2: Platform Services ✅ 8/8 FASES

| Componente | AWS Atual | Cloud-Agnostic | Gap | Esforço |
|------------|-----------|---------------|-----|---------|
| **ALB Controller** | AWS-specific | NGINX/Traefik Ingress | Migrar Ingress | Médio |
| **Cert-Manager** | ✅ Agnóstico (ACME) | ✅ Reutilizável | Nenhum | Zero |
| **Prometheus Stack** | ✅ Agnóstico | ✅ Reutilizável | Nenhum | Zero |
| **Loki** | S3 backend | GCS/Azure Blob | Storage backend | Baixo |
| **Tempo** | S3 backend | GCS/Azure Blob | Storage backend | Baixo |
| **Network Policies** | ✅ Calico agnóstico | ✅ Reutilizável | Nenhum | Zero |
| **Cluster Autoscaler** | AWS-specific | Karpenter multi-cloud | Abstração | Médio |
| **FinOps Automation** | EventBridge + Lambda | CloudScheduler, Azure Functions | Reimplementar | Alto |

**Portabilidade:** 🟢 80% (Maioria dos componentes já agnósticos!)

---

### Marco 3: Workloads (PRÓXIMO)

| Componente | AWS Planejado | Cloud-Agnostic | Gap | Esforço |
|------------|--------------|---------------|-----|---------|
| **PostgreSQL** | RDS Single-AZ | ✅ CloudNativePG Operator | Migrar para Operator | Médio |
| **Redis** | ✅ Spotahome Redis Operator | ✅ Agnóstico | Nenhum | Zero |
| **RabbitMQ** | ✅ RabbitMQ Cluster Operator | ✅ Agnóstico | Nenhum | Zero |
| **GitLab** | ✅ Helm chart oficial | ✅ Agnóstico | Nenhum | Zero |
| **ArgoCD** | ✅ Helm chart oficial | ✅ Agnóstico | Nenhum | Zero |
| **Harbor** | ✅ Helm chart oficial | ✅ Agnóstico | Nenhum | Zero |
| **Load Balancer (DBs)** | AWS NLB | MetalLB, Cloud LB | Abstração | Médio |

**Portabilidade:** 🟢 85% (ADR-023 já escolheu Operators cloud-agnostic!)

---

## 🎯 Marcos de Migração Cloud-Agnostic

### Fase 1: AWS EKS Quickstart (8 semanas) - ✅ EM ANDAMENTO

**Objetivo:** Plataforma operacional AWS

**Entregas:**
- ✅ Marco 0: Baseline Terraform
- ✅ Marco 1: Cluster EKS
- ✅ Marco 2: Platform Services (8 fases)
- 📋 Marco 3: Workloads (GitLab, ArgoCD, Harbor)

**Portabilidade:** 75-80%

**Próximo:** Finalizar Marco 3 (8 semanas)

---

### Fase 2: Abstração AWS → Multi-Cloud (12 semanas) - 📋 PLANEJADA

**Objetivo:** Remover dependências AWS-specific

**Épicos:**

1. **Épico A: Ingress Unificado (3 semanas)**
   - Migrar ALB Controller → NGINX Ingress Controller
   - Manter ALB via annotations apenas
   - Testar ExternalDNS multi-cloud

2. **Épico B: Storage Agnóstico (2 semanas)**
   - Abstração S3 → S3-compatible (MinIO, Rook-Ceph)
   - Loki/Tempo backends configuráveis
   - Validar performance

3. **Épico C: Autoscaling Multi-Cloud (3 semanas)**
   - Migrar Cluster Autoscaler → Karpenter
   - Configurar provisioners multi-cloud
   - Testar Spot/Preemptible instances

4. **Épico D: Observability Backends (2 semanas)**
   - Parametrizar backends de storage (S3/GCS/Azure Blob)
   - Testar Loki/Tempo em GCS
   - Validar custos

5. **Épico E: RDS → CloudNativePG (2 semanas)**
   - Migrar PostgreSQL RDS → CloudNativePG Operator
   - Configurar backups S3/GCS
   - Validar performance vs RDS

**Entregas:**
- ✅ 90%+ componentes agnósticos
- ✅ Terraform multi-cloud ready
- ✅ Documentação de portabilidade

**Custo:** R$ 4.200/mês (leve aumento por abstrações)

---

### Fase 3: Validação Multi-Cloud (8 semanas) - 📋 FUTURA

**Objetivo:** Provar portabilidade em 2ª cloud

**Épicos:**

1. **Épico F: Deploy Staging em GCP/Azure (4 semanas)**
   - Provisionar GKE ou AKS
   - Deploy completo da plataforma
   - Validar funcionalidades

2. **Épico G: Testes de Portabilidade (2 semanas)**
   - Smoke tests multi-cloud
   - Performance benchmarks
   - Disaster recovery cross-cloud

3. **Épico H: Refinamento e Documentação (2 semanas)**
   - Runbooks multi-cloud
   - Troubleshooting guides
   - Cost comparison

**Entregas:**
- ✅ Plataforma rodando em 2 clouds
- ✅ 95%+ portabilidade validada
- ✅ Runbooks multi-cloud

**Custo:** R$ 6.000/mês (2 clouds staging)

---

### Fase 4: Platform Engineering Completo (12 semanas) - 📋 FUTURA

**Objetivo:** 6 Domínios completos cloud-agnostic

**Épicos:**

1. **Épico I: Service Mesh (Linkerd) (4 semanas)**
   - Deploy Linkerd (leve, cloud-agnostic)
   - mTLS automático
   - Traffic management

2. **Épico J: Secrets Management (Vault) (3 semanas)**
   - HashiCorp Vault HA
   - Dynamic secrets
   - Integração CI/CD

3. **Épico K: Developer Portal (Backstage) (3 semanas)**
   - Backstage Spotify
   - Service catalog
   - Self-service templates

4. **Épico L: Security Avançado (2 semanas)**
   - Kyverno policies
   - Falco runtime security
   - Trivy scan automation

**Entregas:**
- ✅ 6 Domínios operacionais
- ✅ 100% cloud-agnostic
- ✅ Platform Engineering maduro

**Custo:** R$ 8.500/mês (plataforma completa)

---

## 📐 Decisões Arquiteturais Convergentes

### ADRs que Já Garantem Portabilidade

| ADR | Decisão | Cloud-Agnostic? | Motivo |
|-----|---------|----------------|--------|
| **ADR-020** | Tempo vs Jaeger | ✅ Sim | Grafana-native, S3-compatible |
| **ADR-021** | No-Domain Phase 1 | ⚠️ Parcial | LoadBalancer é cloud-specific |
| **ADR-023** | Operators vs Bitnami | ✅ Sim | Kubernetes Operators nativos |
| **ADR-024** | FinOps Multi-Ambiente | ❌ Não | EventBridge + Lambda (AWS-only) |

### Mudanças Necessárias para Portabilidade Total

1. **ADR-021 Fase 2:** Migrar LoadBalancer → Ingress HTTPS (agnóstico)
2. **ADR-024 Refactor:** FinOps via CronJobs Kubernetes (agnóstico)
3. **Novo ADR-025:** Ingress Controller Strategy (NGINX vs Cloud-Specific)
4. **Novo ADR-026:** Storage Backend Strategy (S3-compatible)

---

## 💰 Comparativo de Custos

### Fase 1: AWS EKS (Atual)

| Ambiente | Custo Mensal | Custo Anual |
|----------|-------------|-------------|
| Staging (scheduled) | R$ 672 | R$ 8.064 |
| Prod (24/7) | R$ 2.802 | R$ 33.624 |
| Observability | R$ 150 | R$ 1.800 |
| **TOTAL** | **R$ 3.624** | **R$ 43.488** |

**Economia FinOps:** -R$ 12.787/ano

---

### Fase 2: Abstração Multi-Cloud (Projetado)

| Ambiente | Custo Mensal | Custo Anual |
|----------|-------------|-------------|
| Staging (scheduled) | R$ 720 (+7%) | R$ 8.640 |
| Prod (24/7) | R$ 3.180 (+13%) | R$ 38.160 |
| Observability | R$ 300 (+100%) | R$ 3.600 |
| **TOTAL** | **R$ 4.200** | **R$ 50.400** |

**Aumento:** +R$ 576/mês (+16%) para abstrações

**Justificativa:** MinIO/Rook-Ceph, Karpenter, overhead de abstrações

---

### Fase 4: Multi-Cloud Produção (Projetado)

| Cloud | Ambiente | Custo Mensal | Custo Anual |
|-------|----------|-------------|-------------|
| AWS | Prod (24/7) | R$ 3.600 | R$ 43.200 |
| Azure | Staging (scheduled) | R$ 800 | R$ 9.600 |
| Observability | Compartilhada | R$ 500 | R$ 6.000 |
| **TOTAL** | | **R$ 4.900** | **R$ 58.800** |

**Aumento:** +R$ 1.276/mês (+35%) vs Fase 1

**Benefício:** Redundância geográfica, portabilidade validada, DR cross-cloud

---

## ✅ Critérios de Sucesso por Fase

### Fase 1: AWS EKS (8 semanas)

- ✅ GitLab operacional com runners
- ✅ Observabilidade completa (métricas + logs + traces)
- ✅ 2 Ambientes (staging + prod)
- ✅ FinOps automation funcionando
- ✅ Custos < R$ 4.000/mês

---

### Fase 2: Abstração Multi-Cloud (12 semanas)

- ✅ 90%+ componentes agnósticos
- ✅ Terraform multi-cloud ready
- ✅ RDS migrado para CloudNativePG
- ✅ Ingress NGINX funcionando
- ✅ Custos < R$ 4.500/mês

---

### Fase 3: Validação Multi-Cloud (8 semanas)

- ✅ Plataforma rodando em 2 clouds
- ✅ Smoke tests cross-cloud passando
- ✅ DR cross-cloud validado
- ✅ Runbooks multi-cloud completos

---

### Fase 4: Platform Engineering (12 semanas)

- ✅ 6 Domínios operacionais
- ✅ Service Mesh implantado
- ✅ Vault operacional
- ✅ Backstage funcional
- ✅ 100% cloud-agnostic validado

---

## 📋 Roadmap Visual

```
┌─────────────────────────────────────────────────────────────────────┐
│                        TIMELINE COMPLETA                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  2026-01 ──────────────▶ 2026-03 ──────────────▶ 2026-08           │
│    │                       │                       │                │
│    │                       │                       │                │
│  ┌─▼─────────────────┐  ┌─▼─────────────────┐  ┌─▼──────────────┐  │
│  │  FASE 1           │  │  FASE 2           │  │  FASE 3        │  │
│  │  AWS EKS          │  │  Abstração        │  │  Validação     │  │
│  │  Quickstart       │  │  Multi-Cloud      │  │  Multi-Cloud   │  │
│  │                   │  │                   │  │                │  │
│  │  8 semanas        │  │  12 semanas       │  │  8 semanas     │  │
│  │  Marco 0-3        │  │  Épicos A-E       │  │  Épicos F-H    │  │
│  │  R$ 3.624/mês     │  │  R$ 4.200/mês     │  │  R$ 6.000/mês  │  │
│  │  ✅ 75% agnóstico │  │  ✅ 90% agnóstico │  │  ✅ 95% valid. │  │
│  └───────────────────┘  └───────────────────┘  └────────────────┘  │
│                                                                     │
│                                                                     │
│  2026-08 ──────────────────────────────────────▶ 2027-01           │
│    │                                               │                │
│    │                                               │                │
│  ┌─▼───────────────────────────────────────────────▼──────────────┐│
│  │  FASE 4                                                         ││
│  │  Platform Engineering Completo                                  ││
│  │                                                                 ││
│  │  12 semanas                                                     ││
│  │  Épicos I-L                                                     ││
│  │  R$ 8.500/mês                                                   ││
│  │  ✅ 100% cloud-agnostic | 6 Domínios completos                 ││
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Próximos Passos Imediatos

### Semana Atual (2026-01-30)

1. ✅ Deploy FinOps Automation (Fase 9 Marco 2)
2. 📝 Deploy OpenTelemetry Tempo (Fase 8 Marco 2)
3. 🧪 Validação completa Marco 2

### Próximas 2 Semanas

1. Iniciar Marco 3 Sprint 1
2. Deploy Redis Operator (Spotahome)
3. Deploy RabbitMQ Cluster Operator

### Mês Seguinte

1. Finalizar Marco 3 (GitLab, ArgoCD, Harbor)
2. Validação end-to-end completa
3. Iniciar planejamento Fase 2 (Abstração Multi-Cloud)

---

## 📚 Referências

- [AWS EKS GitLab Quickstart](quickstart/aws-eks-gitlab-quickstart.md) - Projeto Ativo
- [Evolution Strategy](quickstart/evolution-strategy.md) - Roadmap de Evolução
- [Architecture](../context/architecture.md) - Estado Atual Implementação
- [Decisions](../context/decisions.md) - ADRs Técnicas
- [README](../../README.md) - Visão de Longo Prazo

---

**Última Atualização:** 2026-01-30
**Autor:** DevOps Team
**Versão:** 1.0
**Próxima Revisão:** 2026-03-01 (Após Marco 3)
