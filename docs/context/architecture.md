# 🏗️ Arquitetura da Plataforma Kubernetes AWS

**Última Atualização:** 2026-01-29
**Versão:** 2.0 (Marco 2 Completo)
**Status:** ✅ Produção

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

**Status:** ✅ Completo (7/7 Fases)

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

### IAM IRSA Pattern (4 implementações)
1. **EBS CSI Driver:** AmazonEBSCSIDriverRole
2. **ALB Controller:** AWSLoadBalancerControllerRole
3. **Loki:** LokiS3Role (acesso bucket logs)
4. **Cluster Autoscaler:** ClusterAutoscalerRole (modify ASGs)

### Network Isolation
- **Default Deny:** 3 namespaces com políticas default-deny-all
- **Explicit Allow:** 11 políticas específicas
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

### Traces (Futuro)
- **Proposta:** Jaeger ou Tempo (integração Grafana)
- **Status:** Não implementado (Marco 3)

---

## 💰 Custos Consolidados

### Marco 0 + Marco 1 + Marco 2

| Categoria | Componente | Custo/Mês |
|-----------|------------|-----------|
| **Compute** | EKS Control Plane | $73.00 |
| | EC2 Nodes (7 × t3.medium) | ~$477.00 |
| **Storage** | EBS gp3 (67Gi total) | $5.36 |
| | S3 Terraform State | $0.07 |
| | S3 Loki Logs (500GB) | $11.50 |
| **Networking** | ALBs (2 test-apps) | $32.40 |
| | NAT Gateways (2) | ~$66.00 (reaproveitado Marco 0) |
| **Secrets** | AWS Secrets Manager (1 secret) | $0.40 |
| **Database** | DynamoDB Lock Table | $0.25 |
| **TOTAL Marco 0+1+2** | | **~$666/mês** |

**Economia vs Baseline:**
- Loki vs CloudWatch: $423/ano saved
- VPC reaproveitada: $1.152/ano saved
- Total Economia: ~$1.575/ano

---

## 🚀 Marco 3: Workloads (Próximo)

### Prioridades

**Priority HIGH:**
1. **GitLab CE** - CI/CD Platform
   - Helm chart + RDS PostgreSQL + Redis + S3 artifacts
   - TLS obrigatório (gitlab.domain.com)
   - Estimate: 8-12h, +$150-200/mês

2. **Keycloak** - Identity & SSO
   - OIDC integration com GitLab
   - TLS obrigatório (auth.domain.com)
   - Estimate: 4-6h, +$50-80/mês

**Priority MEDIUM:**
3. **ArgoCD** - GitOps
   - Sync com GitLab repos
   - TLS obrigatório (argocd.domain.com)
   - Estimate: 3-4h, ~$0 (usa nodes existentes)

4. **Harbor** - Container Registry
   - S3 backend, Trivy scanning
   - TLS obrigatório (registry.domain.com)
   - Estimate: 6-8h, +$40-60/mês

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
