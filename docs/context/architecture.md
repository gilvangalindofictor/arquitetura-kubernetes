# 🏗️ Arquitetura da Plataforma Kubernetes AWS

**Última Atualização:** 2026-01-29
**Versão:** 2.1 (Marco 2 Fase 8 Planejada)
**Status:** 🟡 Em Expansão (Fase 8 Pendente)

---

## 📊 Visão Geral

Plataforma Kubernetes completa na AWS, estruturada em marcos evolutivos, com foco em observabilidade, segurança e custos otimizados.

### Marcos de Evolução

```
Marco 0: Baseline & State Management  →  Marco 1: EKS Cluster  →  Marco 2: Platform Services  →  Marco 3: Workloads (Próximo)
```

---

## 🎯 Marco 0: Baseline Terraform

**Status:** ✅ Completo

### Componentes
- **VPC Existente:** `vpc-0b1396a59c417c1f0` (10.0.0.0/16, 2 AZs: us-east-1a, us-east-1b)
- **Backend S3:** `terraform-state-marco0-891377105802`
- **DynamoDB Lock:** `terraform-state-lock`
- **Engenharia Reversa:** Scripts para importar recursos AWS existentes

### Decisões Arquiteturais
- Reaproveitamento de VPC existente (economia $96/mês em NAT Gateways)
- Multi-AZ com 2 zonas (suficiente para DevOps tools, não critical workloads)
- State management centralizado em S3 com versioning

---

## ⚙️ Marco 1: Infraestrutura Base EKS

**Status:** ✅ Completo

### Cluster EKS
- **Nome:** k8s-platform-prod
- **Versão:** 1.31.x
- **Região:** us-east-1
- **OIDC Provider:** Habilitado para IRSA

### Node Groups (7 nodes total)

| Node Group | Tipo | Quantidade | vCPU | RAM | Disco | Workload |
|------------|------|------------|------|-----|-------|----------|
| system | t3.medium | 2 | 4 | 8GB | 50GB | Platform services críticos |
| workloads | t3.medium | 3 | 12 | 24GB | 50GB | Aplicações usuário |
| critical | t3.medium | 2 | 8 | 16GB | 50GB | Serviços high-availability |

**Taints e Labels:**
- `system`: `node-type=system:NoSchedule` + label `node-type=system`
- `workloads`: label `node-type=workloads` (sem taint, general purpose)
- `critical`: `node-type=critical:NoSchedule` + label `node-type=critical`

### Add-ons EKS (4 total)
1. **vpc-cni** - Networking plugin (ENI-based pod IPs)
2. **kube-proxy** - Network proxy
3. **coredns** - DNS resolution
4. **ebs-csi-driver** - Persistent volumes (IRSA configurado)

### IAM & IRSA
- **OIDC Provider:** `EC913B145BF356481CBE823532F09150`
- **Padrão IRSA:** Todos platform services usam IAM Roles (sem Access Keys)
- **Roles criados:** 4 (EBS CSI, ALB Controller, Loki S3, Cluster Autoscaler)

---

## 🛠️ Marco 2: Platform Services

**Status:** 🟡 Fase 8 Planejada (7/8 Fases Completas)

### Fase 1: AWS Load Balancer Controller
- **Versão:** v1.11.0
- **Namespace:** kube-system
- **IRSA Role:** AWSLoadBalancerControllerRole-k8s-platform-prod
- **Função:** Provisiona ALBs para Kubernetes Ingresses
- **WAF/Shield:** Desabilitados (economia)
- **Custo:** $0 (usa nodes existentes)

### Fase 2: Cert-Manager
- **Versão:** v1.16.3
- **Namespace:** cert-manager
- **CRDs:** 6 instalados (Certificate, Issuer, ClusterIssuer, etc.)
- **Função:** Gerenciamento automático de certificados TLS
- **ClusterIssuers:** 3 criados (letsencrypt-staging, letsencrypt-prod, selfsigned)
- **Custo:** $0 (usa nodes existentes)

### Fase 3: Monitoring (Kube-Prometheus-Stack)
- **Versão:** v69.4.0 (Helm chart)
- **Namespace:** monitoring
- **Componentes:** Prometheus, Grafana, Alertmanager, Node Exporter, Kube State Metrics
- **Pods:** 13 Running
- **Dashboards:** 30+ pré-configurados
- **PVCs:** 3 volumes (27Gi total)
  - Prometheus: 20Gi (gp3)
  - Grafana: 5Gi (gp3)
  - Alertmanager: 2Gi (gp3)
- **Secrets:** Grafana admin password no AWS Secrets Manager
- **Custo:** $2.56/mês (EBS + Secrets Manager)

### Fase 4: Logging (Loki + Fluent Bit)
- **Loki Versão:** Chart v5.42.0 (SimpleScalable mode)
- **Fluent Bit Versão:** Chart v0.43.0
- **Namespace:** monitoring
- **Pods:** 15 total (8 Loki + 7 Fluent Bit DaemonSet)
- **Backend:** S3 bucket `k8s-platform-loki-891377105802`
- **Retenção:** 30 dias (S3), 7 dias (in-memory cache)
- **IRSA:** Role LokiS3Role-k8s-platform-prod
- **Integração:** Grafana datasource pré-configurado
- **Custo:** $19.70/mês (S3 500GB ~$11.50 + EBS 40Gi ~$3.20 + requests ~$5)

### Fase 5: Network Policies
- **CNI:** Calico policy-only mode (overlay AWS VPC CNI)
- **Políticas:** 11 aplicadas
  - 3 default-deny (por namespace: kube-system, monitoring, cert-manager)
  - 3 allow-dns (todos pods → CoreDNS UDP/53)
  - 3 allow-api-server (todos pods → API Server TCP/443)
  - 1 allow-prometheus-scraping (Prometheus → targets variados)
  - 1 allow-fluent-bit-to-loki (Fluent Bit → Loki Gateway TCP/3100)
- **Zero Trust:** Default deny, explicit allow
- **Custo:** $0 (Calico policy-only não requer nodes adicionais)

### Fase 6: Cluster Autoscaler
- **Versão:** Chart v9.43.2
- **Namespace:** kube-system
- **IRSA Role:** ClusterAutoscalerRole-k8s-platform-prod
- **Configuração:** Scale-down habilitado (5 min unneeded), min=max (desabilitado auto-scale por enquanto)
- **ServiceMonitor:** Integrado Prometheus
- **Custo:** $0 (usa nodes existentes)

### Fase 7: Test Applications
- **Namespace:** test-apps
- **Apps:** 2 (nginx-test, echo-server)
- **Pods:** 4 (2 réplicas cada)
- **Ingresses:** 2 (ALB internet-facing HTTP-only)
- **ALBs Ativos:** 2
  - nginx-test: k8s-testapps-nginxtes-bf6521357f
  - echo-server: k8s-testapps-echoserv-d5229efc2b
- **ServiceMonitors:** 2 (integração Prometheus)
- **Network Policy:** 1 (allow ALB Controller + monitoring)
- **TLS:** Desabilitado (aguardando domínio registrado)
- **Custo:** $32.40/mês (2 ALBs × $16.20)

### Fase 8: Distributed Tracing (OpenTelemetry + Tempo)
**Status:** 📝 Planejada (ADR-020 aprovado)

**Componentes:**
- **Grafana Tempo:** Backend de traces distribuídos
  - **Versão:** Chart v1.10.x (SimpleScalable mode)
  - **Namespace:** monitoring
  - **Pods:** 6 total
    - 2 × distributor (recebe traces do OTel Collector)
    - 2 × ingester (processa + escreve S3)
    - 1 × querier (queries via Grafana)
    - 1 × compactor (compactação S3)
  - **Storage:** S3 bucket `k8s-platform-tempo-891377105802`
  - **Retenção:** 30 dias (S3)
  - **IRSA:** Role TempoS3Role-k8s-platform-prod

- **OpenTelemetry Collector:** Gateway de ingestão
  - **Versão:** Chart v0.108.x
  - **Pods:** 2 (Gateway mode, alta disponibilidade)
  - **Receivers:** OTLP gRPC (4317), OTLP HTTP (4318)
  - **Exporters:** Tempo (traces), Prometheus (metrics), Loki (logs)
  - **Função:** Coleta traces de aplicações, processa, envia para backends

**Integração:**
- Grafana datasource Tempo configurado
- Correlação traces ↔ logs (derived fields: trace_id → Loki query)
- Correlação metrics ↔ traces (exemplars: Prometheus → Tempo)
- Grafana Explore: TraceQL queries

**Network Policies:**
- 4 novas políticas (total Marco 2: 15)
  - allow-otel-collector-ingress (apps → collector:4317/4318)
  - allow-otel-to-tempo (collector → tempo-distributor:3100)
  - allow-grafana-to-tempo (grafana → tempo-query-frontend:3100)
  - allow-tempo-to-s3 (tempo → S3 via IRSA, egress policy)

**Decisão Arquitetural (ADR-020):**
- **Tempo escolhido vs Jaeger:** Economia $205.55/mês ($2,467/ano)
  - Tempo S3 backend: $19.70/mês (S3 $11.50 + API $5.00 + EBS $3.20)
  - Jaeger Cassandra: $210/mês (Cassandra $150 + Collector $30 + EBS $30)
- **Padrão IRSA reutilizável:** Consistente com Loki S3 (mesmo padrão IAM)
- **Grafana-native:** Integração zero-config com Prometheus + Loki

**Benefícios:**
- Observabilidade completa: **Métricas (Prometheus) + Logs (Loki) + Traces (Tempo)**
- Troubleshooting distribuído: rastrear requests entre microserviços
- Performance profiling: identificar latências por span
- Root cause analysis: correlacionar erros com traces + logs

**Custo:** $19.70/mês (S3 500GB + API requests + EBS 40Gi)

---

## 📐 Diagrama de Rede

```
Internet
    ↓
[ALB] (Application Load Balancer - Fase 7)
    ↓
[Kubernetes Ingress] (test-apps namespace)
    ↓
[Services] (nginx-test, echo-server)
    ↓
[Pods] (4 total, nodes workloads)
    ↓
[VPC CNI] (AWS ENI-based networking)
    ↓
[Private Subnets] (10.0.0.0/16)
    ↓
[NAT Gateway] → Internet (egress only)
```

---

## 🔐 Segurança

### IAM IRSA Pattern (5 implementações)
1. **EBS CSI Driver:** AmazonEBSCSIDriverRole
2. **ALB Controller:** AWSLoadBalancerControllerRole
3. **Loki:** LokiS3Role (acesso bucket logs)
4. **Tempo:** TempoS3Role (acesso bucket traces) - *Fase 8 planejada*
5. **Cluster Autoscaler:** ClusterAutoscalerRole (modify ASGs)

### Network Isolation
- **Default Deny:** 3 namespaces com políticas default-deny-all
- **Explicit Allow:** 15 políticas específicas (11 deployed + 4 Fase 8 planejadas)
- **Calico:** Policy engine sem overhead de overlay network

### Secrets Management
- **AWS Secrets Manager:** Grafana admin password (KMS encrypted)
- **Kubernetes Secrets:** Service account tokens (automático)

---

## 📊 Observabilidade

### Métricas (Prometheus)
- **Targets:** 50+ (nodes, pods, services, kube-state-metrics)
- **Retention:** 15 dias (PVC 20Gi)
- **Dashboards:** 30+ no Grafana
- **Alerting:** Alertmanager (rules básicas configuradas)

### Logs (Loki)
- **Ingestão:** 7 Fluent Bit agents (1 por node)
- **Storage:** S3 (30 dias), in-memory cache (7 dias)
- **Query:** Grafana Explore (LogQL)
- **Parsers:** JSON, multiline (stack traces)

### Traces (Tempo - Fase 8 Planejada)
- **Backend:** Grafana Tempo SimpleScalable mode (6 pods)
- **Collector:** OpenTelemetry Collector Gateway (2 pods)
- **Storage:** S3 bucket `k8s-platform-tempo-891377105802` (30 dias retenção)
- **Query:** Grafana Explore (TraceQL)
- **Protocolos:** OTLP gRPC (4317), OTLP HTTP (4318)
- **Correlação:** Traces → Logs (via trace_id), Metrics → Traces (via exemplars)
- **Decisão:** ADR-020 (Tempo vs Jaeger, economia $205.55/mês)

---

## 💰 Custos Consolidados

### Marco 0 + Marco 1 + Marco 2

| Categoria | Componente | Custo/Mês |
|-----------|------------|-----------|
| **Compute** | EKS Control Plane | $73.00 |
| | EC2 Nodes (7 × t3.medium) | ~$477.00 |
| **Storage** | EBS gp3 (107Gi total) | $8.56 |
| | S3 Terraform State | $0.07 |
| | S3 Loki Logs (500GB) | $11.50 |
| | S3 Tempo Traces (500GB) - *Fase 8* | $11.50 |
| **Networking** | ALBs (2 test-apps) | $32.40 |
| | NAT Gateways (2) | ~$66.00 (reaproveitado Marco 0) |
| **Secrets** | AWS Secrets Manager (1 secret) | $0.40 |
| **Database** | DynamoDB Lock Table | $0.25 |
| **API Requests** | S3 API (Tempo PUT/GET) - *Fase 8* | $5.00 |
| **TOTAL Marco 0+1+2 (7 Fases)** | | **~$666/mês** |
| **TOTAL Marco 0+1+2 (8 Fases)** | | **~$685.70/mês** |

**Economia vs Baseline:**
- Loki vs CloudWatch: $423/ano saved
- VPC reaproveitada: $1.152/ano saved
- Tempo vs Jaeger: $2.467/ano saved (Fase 8)
- Total Economia: ~$4.042/ano

---

## 🚀 Marco 3: Workloads (Próximo)

**Status:** 📝 Planejado (8 semanas, ADR-021 aprovado)
**Estratégia:** 2 Fases - Fase 1 sem domínio (LoadBalancer), Fase 2 com TLS/SSO

### Fase 1: Deployment Sem Domínio (Semanas 1-8)

**ADR-021:** Implementação inicial sem domínio registrado para uso operacional interno

**Tier 1: Data Services (Semanas 3-5)**
1. **PostgreSQL RDS** - Database centralizado
   - Instance: db.t3.medium Single-AZ (economia $50/mês vs Multi-AZ)
   - Databases: gitlab, keycloak, harbor (shared)
   - Acesso: LoadBalancer (NLB) + endpoint interno ClusterIP
   - Clientes externos: DBeaver, PgAdmin, psql
   - Custo: $50/mês (RDS) + $16.20/mês (NLB) = $66.20/mês

2. **Redis** - Cache & Sessions
   - Helm: bitnami/redis (1 master + 2 replicas)
   - Acesso: LoadBalancer (NLB) + endpoint interno ClusterIP
   - Clientes externos: Redis CLI, Redis Desktop Manager
   - Custo: $0 (nodes existentes) + $16.20/mês (NLB) = $16.20/mês

3. **RabbitMQ** - Message Queue
   - Operator: bitnami/rabbitmq-cluster-operator (3 nodes)
   - Acesso: LoadBalancer (NLB) para Management UI (15672)
   - Custo: $0 (nodes existentes) + $16.20/mês (NLB) = $16.20/mês

4. **S3 Buckets** - Object Storage
   - k8s-platform-gitlab-artifacts-891377105802 (CI/CD artifacts)
   - k8s-platform-harbor-images-891377105802 (container images)
   - Custo: $15/mês (700GB total estimado)

**Tier 2: Workloads (Semanas 6-8)**

5. **GitLab CE** - CI/CD Platform
   - Acesso: ALB DNS HTTP (ex: k8s-gitlab-xyz.us-east-1.elb.amazonaws.com)
   - Dependências: PostgreSQL, Redis, S3
   - Funcionalidades: Git push/pull ✅, CI/CD pipelines ✅, Interface Web ✅
   - Limitações: Webhooks HTTPS externos ❌, SSO ❌
   - Custo: $81.20/mês (inclui RDS $50 + Redis $15 + ALB $16.20)

6. **ArgoCD** - GitOps
   - Acesso: ALB DNS HTTP (ex: k8s-argocd-xyz.us-east-1.elb.amazonaws.com)
   - Funcionalidades: Sync GitLab repos ✅, Auto-deploy ✅
   - Custo: $16.20/mês (ALB)

7. **Harbor** - Container Registry
   - Acesso: ALB DNS HTTP (ex: k8s-harbor-xyz.us-east-1.elb.amazonaws.com)
   - Backend: S3 + PostgreSQL shared + Trivy scanning
   - Funcionalidades: Push/pull images ✅, Scan vulnerabilities ✅
   - Limitações: Docker login menos seguro sem HTTPS
   - Custo: $21.80/mês (S3 $4.60 + ALB $16.20 + shared RDS $0)

**Custo Total Fase 1:** $902.30/mês (baseline) → **$737.10/mês (otimizado com Reserved Instances)**

### Fase 2: TLS/SSO (Futuro)

**Quando:** Após registro de domínio ou quando necessário webhooks HTTPS externos

**Mudanças:**
- Registrar domínio (Route53 ~$12/ano)
- Habilitar `enable_tls = true` no terraform.tfvars
- Deploy Keycloak + configurar OIDC para todos workloads
- Migração transparente (ALBs recriados com listeners HTTPS)

**Custo Adicional:** +$0.50/mês (Route53 Hosted Zone)

### Otimizações Q1 2026 (Incluídas no Custo Otimizado)
- Reserved Instances EC2 (1 ano, 7 nodes): -$124/mês
- Consolidar ALBs via IngressGroup (4→1): -$16.20/mês
- PostgreSQL RDS Shared (3 databases): -$25/mês
- **Total Economia:** -$165.20/mês

---

## 📚 Referências

- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kube-Prometheus-Stack Docs](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Calico Network Policies](https://docs.tigera.io/calico/latest/network-policy/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

---

**Mantenedor:** DevOps Team
**Última Revisão:** 2026-01-29
**Próxima Revisão:** Marco 3 Planning
