# ADR-059: Multi-Marco Infrastructure Split Strategy

**Data:** 2026-02-12
**Status:** ✅ **ACEITO**
**Contexto:** Análise de conformidade Terraform vs AWS revelou 20 gaps de drift
**Decisor:** DevOps Team + Platform Team

---

## 📋 Contexto

Durante análise abrangente de conformidade Terraform vs AWS real state (2026-02-12), identificamos que **staging environment consome infraestrutura criada em Marco 1** via Terraform data sources, causando aparente "drift" quando na verdade reflete **arquitetura intencional de separação de responsabilidades**.

### Gaps Identificados (Aparentes)

| Gap ID | Recurso | Terraform Staging | AWS Real | Root Cause |
|--------|---------|-------------------|----------|------------|
| T2 | EKS Node Groups | NOT managed (data source) | 3 grupos ativos | Marco 1 externo |
| T4 | VPC Endpoints STS+EC2 | NOT managed | 2 endpoints ativos | Marco 0/1 externo |
| T9 | EKS Cluster | Data source only | Cluster operacional 1.34 | Marco 1 externo |
| T10 | EKS Addons | NOT managed | 4 addons ativos | Marco 1 externo |
| T13 | NAT Gateways | NOT managed | 2 NGW (us-east-1a/b) | Marco 0 externo |
| T16 | KMS Keys (EKS) | Data source only | Key ativa | Marco 1 externo |

**Total:** 10/20 gaps (50%) são resultado de **Multi-Marco architecture**, não drift real.

---

## ⚠️ Problema Identificado

### 1. Documentação Insuficiente

**Problema:**
Não há documento consolidado explicando **quem gerencia o quê** entre Marco 0, Marco 1 e Marco 3 (staging).

**Impacto:**
- Análises de drift incorretas
- Tentativas de "corrigir" código que está correto
- Confusão sobre onde aplicar mudanças
- Duplicação de esforço (investigar "problemas" inexistentes)

### 2. Ambiguidade de Ownership

**Problema:**
Sem ownership matrix, não está claro se um recurso ausente do Terraform staging é:
- ❌ Drift real (recurso criado manualmente, precisa import)
- ✅ Arquitetura intencional (recurso gerenciado em outro Marco)

**Exemplo:**
```hcl
# staging/main.tf
data "aws_eks_cluster" "cluster" {
  name = local.cluster_name  # ← Consome cluster de Marco 1
}
```

**Pergunta não documentada:** Por que staging não cria o cluster?

### 3. Decisões Arquiteturais Implícitas

**Problema:**
Estratégia de **shared cluster** (prod + staging no mesmo EKS) nunca foi formalizada em ADR.

**Impacto:**
- Risco de refactoring desnecessário
- Impossibilidade de validar se arquitetura atual é intencional ou acidental

---

## 🎯 Decisão

Formalizar **Multi-Marco Infrastructure Split Strategy** com ownership explícito:

### Marco 0: VPC Foundation (Deprecated/Legacy)

**Responsabilidade:** Rede base compartilhada

**Recursos Gerenciados:**
- ✅ VPC (`vpc-0b1396a59c417c1f0`)
- ✅ Subnets (4: 2 public + 2 private)
- ✅ Route Tables
- ✅ Internet Gateway
- ✅ NAT Gateways (2: us-east-1a, us-east-1b) - **$66/mês**
- ✅ S3 Gateway Endpoint (vpce-0a7ef345dce0bea69)

**Terraform State:** `marco0/terraform.tfstate`

**Status:** LEGACY - criado manualmente ou via TF antigo, mantido como-is

---

### Marco 1: EKS Cluster Foundation

**Responsabilidade:** Cluster Kubernetes compartilhado (prod + staging)

**Recursos Gerenciados:**
- ✅ EKS Cluster (`k8s-platform-prod`, version 1.34)
- ✅ EKS Node Groups (3):
  - `system`: t3.medium, 2-4 nodes, 30GB gp3
  - `workloads`: t3.large, 2-7 nodes, 50GB gp3 (desired: 4)
  - `critical`: t3.xlarge, 2-4 nodes, 100GB gp3
- ✅ EKS Addons (4):
  - `aws-ebs-csi-driver` (v1.37.0)
  - `coredns` (v1.34.x)
  - `kube-proxy` (v1.31.2 → **PRECISA upgrade para v1.34.x**)
  - `vpc-cni` (v1.19.0)
- ✅ IRSA OIDC Provider (`arn:aws:iam::891377105802:oidc-provider/oidc.eks.us-east-1...`)
- ✅ KMS Key (EKS secrets encryption): `alias/k8s-platform-prod-eks-secrets`
- ✅ VPC Endpoints (Interface):
  - STS (IRSA authentication)
  - EC2 (node registration)
- ✅ Security Groups (cluster + nodes base)

**Terraform State:** `marco1/terraform.tfstate`

**Cost:** ~$450/mês (EKS control plane $73 + nodes $377)

**Pattern:** **Shared Cluster Strategy**
- Cluster único para prod + staging
- Isolamento via namespaces + RBAC + NetworkPolicies
- Cost efficiency: 1 control plane vs 2 ($73/mês savings)

---

### Marco 3 Staging: Workloads & Data Services

**Responsabilidade:** Workloads de aplicação (staging environment)

**Recursos Gerenciados:**
- ✅ PostgreSQL RDS (staging):
  - Instance: db.t3.medium, 100GB storage
  - Databases: gitlab, harbor, keycloak
  - Multi-AZ: false (cost-optimized)
- ✅ Redis Operator (SpotaHome):
  - Replicas: 1 (no Sentinel)
  - PVC: 5Gi gp3
  - Namespace: data-services
- ✅ RabbitMQ Cluster Operator:
  - Replicas: 1 (no quorum)
  - PVC: 5Gi gp3
  - Namespace: data-services
- ✅ Vault HA (KMS auto-unseal):
  - Replicas: 3 (production-ready)
  - KMS Key: `alias/vault-unseal-k8s-platform-prod` (**managed in Marco 3**)
  - PVC: 3×10Gi gp3
  - Namespace: vault-system
- ✅ External Secrets Operator:
  - Replicas: 1
  - Namespace: external-secrets-system
- ✅ Harbor Registry:
  - S3 backend (IRSA)
  - PostgreSQL external (shared RDS)
  - Namespace: harbor-system
- ✅ GitLab CE:
  - Replicas: 1 webservice
  - PostgreSQL external (shared RDS)
  - Redis external (operator)
  - S3 artifacts (IRSA)
  - Namespace: gitlab-staging
- ✅ Keycloak SSO:
  - Replicas: 1 (target 2 pending CPU)
  - PostgreSQL external (shared RDS)
  - Namespace: keycloak
- ✅ Observability Stack:
  - Kube-Prometheus-Stack (Prometheus + Grafana + Alertmanager)
  - Loki (distributed mode)
  - Tempo (distributed tracing)
  - OpenTelemetry Collector
  - Namespace: monitoring
- ✅ FinOps Automation:
  - Lambda functions (start/stop scheduler)
  - EventBridge rules (weekday 8h-18h BRT)
  - Savings: R$ 1.200/ano

**Terraform State:** `environments/staging/terraform.tfstate`

**Cost:** ~$175/mês (RDS $30 + workloads $145)

**Pattern:** **Consume Marco 1 via Data Sources**

```hcl
# staging/main.tf - CORRETO (não é drift)
data "aws_eks_cluster" "cluster" {
  name = local.cluster_name  # Consome Marco 1
}

data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}
```

---

## 📊 Resource Ownership Matrix

| Recurso | Marco 0 | Marco 1 | Marco 3 Staging | Justificativa |
|---------|---------|---------|-----------------|---------------|
| **Networking** |
| VPC | ✅ Gerencia | Data source | Data source | Shared foundation |
| Subnets | ✅ Gerencia | Data source | Data source | Shared foundation |
| NAT Gateways | ✅ Gerencia | Data source | Data source | Shared foundation, $66/mês |
| VPC Endpoints S3 | ✅ Gerencia | Data source | Data source | Cost optimization (NAT bypass) |
| VPC Endpoints STS | ❌ | ✅ Gerencia | Data source | IRSA authentication |
| VPC Endpoints EC2 | ❌ | ✅ Gerencia | Data source | Node registration |
| **Compute** |
| EKS Cluster | ❌ | ✅ Gerencia | Data source | Shared cluster strategy |
| EKS Node Groups | ❌ | ✅ Gerencia | Data source | Shared cluster strategy |
| EKS Addons | ❌ | ✅ Gerencia | Data source | Cluster-level config |
| **IAM** |
| OIDC Provider (IRSA) | ❌ | ✅ Gerencia | Data source | Cluster-level config |
| IRSA Roles (workload) | ❌ | ❌ | ✅ Gerencia | Workload-specific (Vault, Harbor, GitLab) |
| **Encryption** |
| KMS (EKS secrets) | ❌ | ✅ Gerencia | Data source | Cluster-level encryption |
| KMS (Vault unseal) | ❌ | ❌ | ✅ Gerencia | Workload-specific |
| **Data Services** |
| PostgreSQL RDS | ❌ | ❌ | ✅ Gerencia | Environment-specific |
| Redis Operator | ❌ | ❌ | ✅ Gerencia | Environment-specific |
| RabbitMQ Operator | ❌ | ❌ | ✅ Gerencia | Environment-specific |
| **Application Workloads** |
| Vault HA | ❌ | ❌ | ✅ Gerencia | Secrets management |
| External Secrets | ❌ | ❌ | ✅ Gerencia | Secrets sync |
| Harbor Registry | ❌ | ❌ | ✅ Gerencia | Container images |
| GitLab CE | ❌ | ❌ | ✅ Gerencia | CI/CD platform |
| Keycloak SSO | ❌ | ❌ | ✅ Gerencia | Authentication |
| Observability Stack | ❌ | ❌ | ✅ Gerencia | Monitoring/logging |

---

## 🔄 Consequências

### Positivas ✅

1. **Clareza de Ownership**
   - Documentação explícita de responsabilidades
   - Redução de confusão em análises de drift
   - Onboarding facilitado para novos engenheiros

2. **Cost Efficiency Validada**
   - Shared cluster: -$73/mês (1 control plane vs 2)
   - Shared NAT Gateways: -$66/mês (2 vs 4)
   - Total savings: ~$139/mês = **R$ 1.002/ano**

3. **Isolamento Adequado**
   - Namespaces: staging vs prod
   - RBAC: staging-admin ≠ prod-admin
   - NetworkPolicies: traffic isolation
   - Resource Quotas: prevent noisy neighbor

4. **Simplicidade Operacional**
   - 1 cluster para upgrade (não 2)
   - 1 addons set para manter (não 2)
   - 1 OIDC provider para integrar (não 2)

### Negativas ⚠️

1. **Drift Detection Complexo**
   - Terraform staging `plan` não pode validar Marco 1 resources
   - Precisa validar 3 states separadamente
   - Risco de drift silencioso em Marco 1

   **Mitigação:**
   ```bash
   # Validation script
   cd marco1/ && terraform plan  # Valida cluster foundation
   cd environments/staging/ && terraform plan  # Valida workloads
   ```

2. **Upgrade Coordination Required**
   - EKS cluster upgrade (Marco 1) afeta staging workloads (Marco 3)
   - Precisa coordenar testing: Marco 1 → Marco 3 validation
   - Rollback complexo (requer rollback de 2 states)

   **Mitigação:** Runbook de upgrade EKS documentado

3. **State File Dependency**
   - Marco 3 staging depende de `terraform_remote_state.marco1`
   - Se Marco 1 state corrompido → Marco 3 blocked

   **Mitigação:** S3 bucket versioning + DynamoDB locking habilitados

4. **Blast Radius Compartilhado**
   - Node failure pode afetar prod + staging simultaneously
   - Cluster-level issue (CNI, CoreDNS) afeta ambos

   **Mitigação:** Node groups separados + tolerations + taints

---

## 📝 Implicações para Gaps Identificados

### Gaps que SÃO drift real (precisam correção):

| Gap ID | Recurso | Ação |
|--------|---------|------|
| T1 | EKS module version default | ✅ CORRIGIDO: 1.28 → 1.34 |
| T3 | kube-proxy addon version | ⏳ PENDENTE: upgrade v1.31.2 → v1.34.x (Marco 1) |
| T5 | Orphan Security Groups | ⏳ PENDENTE: cleanup 10-15 SGs históricos |
| T7 | Storage class gp2 | ✅ CORRIGIDO: gp2 → gp3 (staging) |
| T8 | PostgreSQL comment | ✅ CORRIGIDO: comment atualizado |
| T14 | EBS volume count | ⏳ PENDENTE: validar PVC count |

### Gaps que NÃO são drift (arquitetura intencional):

| Gap ID | Recurso | Decisão |
|--------|---------|---------|
| T2 | EKS Node Groups | ✅ ACEITO: gerenciado em Marco 1 |
| T4 | VPC Endpoints STS+EC2 | ✅ ACEITO: gerenciado em Marco 0/1 |
| T6 | Workloads node scaling | ✅ ACEITO: gerenciado em Marco 1 |
| T9 | EKS Cluster | ✅ ACEITO: gerenciado em Marco 1 |
| T10 | EKS Addons | ✅ ACEITO: gerenciado em Marco 1 |
| T11 | Load Balancers | ✅ ACEITO: Kubernetes-managed (AWS LB Controller) |
| T13 | NAT Gateways | ✅ ACEITO: gerenciado em Marco 0 |
| T16 | KMS Keys (EKS) | ✅ ACEITO: gerenciado em Marco 1 |

---

## 🚀 Ações Imediatas

### 1. Documentação (Esta Semana)

- [x] ADR-059 criado (este documento)
- [ ] Atualizar `ARCHITECTURE.md` com ownership matrix
- [ ] Adicionar `docs/terraform/MULTI-MARCO-GUIDE.md` runbook

### 2. Código (Esta Semana)

- [x] T1: EKS module version default corrigido
- [x] T7: Storage class gp3 corrigido
- [x] T8: PostgreSQL comment corrigido
- [ ] T20: Doc metadata headers adicionados

### 3. Infraestrutura (Este Mês)

- [ ] T3: kube-proxy upgrade (Marco 1) - `aws eks update-addon`
- [ ] T5: Security Groups cleanup - `aws ec2 delete-security-group`
- [ ] T14: Validar EBS volume count - `kubectl get pvc -A`

### 4. Processos (Este Trimestre)

- [ ] Drift detection automation (cron terraform plan em 3 states)
- [ ] EKS upgrade runbook completo
- [ ] Multi-Marco dependency map (visual diagram)

---

## 🔗 Referências

- **Análise Original:** Terraform vs AWS Conformance Analysis (2026-02-12)
- **Logbook:** `docs/logbook/2026-02-12-terraform-conformance-implementation.md`
- **ADRs Relacionados:**
  - ADR-050: Shared Data Services (Prod/Staging)
  - ADR-022: FinOps Automation Strategy
  - ADR-046: Keycloak SSO Strategy
- **AWS Resources:**
  - EKS Cluster: `k8s-platform-prod` (1.34)
  - VPC: `vpc-0b1396a59c417c1f0`
  - Account: 891377105802

---

**Decisão Final:** ACEITAR arquitetura Multi-Marco como estratégia intencional. Documentar ownership matrix. Corrigir apenas drift real (T1, T3, T5, T7, T8, T14).

**Assinatura:** DevOps Team + Platform Team
**Data Aprovação:** 2026-02-12
**Próxima Revisão:** 2026-05-12 (3 meses)
