# Plano FinOps — Otimizações Imediatas (Stack Completa)

**Data:** 2026-03-18
**Cluster:** k8s-platform-prod (891377105802 / us-east-1 / EKS 1.34)
**Framework:** executor-terraform.md
**Fontes:** finops-analysis-2026-03-18.md | finops-status-2026-03-17.md | 2026-03-17-revisao-capacidade-karpenter.md
**Budget aprovado:** $1.000/mês (vigência: até Fase 7 completa)
**Custo baseline:** ~$1.194/mês (~$39.82/dia) — 100% On-Demand

---

## Resumo Executivo

O custo atual de $1.194/mês está **+19,4% acima do budget aprovado de $1.000/mês** e **+48% acima do budget original de $807/mês**. A plataforma opera em fase de desenvolvimento ativo com todos os serviços de staging simultâneos (GitLab, Harbor, ArgoCD, Vault, Keycloak, Loki, Tempo, Prometheus, SonarQube, Backstage, Linkerd). A EC2 representa a maior fatia de custo (~$661/mês — 100% On-Demand sem Spot ou Savings Plans).

Este plano endereça **5 oportunidades de otimização** com saving total projetado de **$162–218/mês**, reduzindo o custo para **$976–1.032/mês** — dentro do budget aprovado de $1.000/mês no cenário médio.

A oportunidade de maior impacto é **Karpenter + Spot Instances para o node group `workloads`** ($140–180/mês), seguida de ajustes de CloudWatch, VPC Endpoints ECR, Lambda Sunday shutdown e auditoria de EIPs.

**Total de saving projetado:** $162–218/mês ($1.944–2.616/ano)
**Esforço total estimado:** ~26–32 horas (2–3 semanas)
**Ponto de retorno ao budget ($807/mês):** Após Karpenter + VPA enforcement + staging enxuto (Q3-Q4 2026)

---

## Stack de Oportunidades — Tabela Priorizada

| # | Oportunidade | Saving/mês | Risco | Esforço | Prioridade | Status |
|---|-------------|-----------|-------|---------|-----------|--------|
| 1 | Karpenter + Spot (node group workloads) | $140–180 | Médio | 16–20h | **P1** | Planejado |
| 2 | Lambda Sunday shutdown (GAP-LAMBDA-RC2) | $10–15 | Nenhum | <1h | **P0** | TF pronto (RC2 no main.tf) |
| 3 | CloudWatch tuning (log types + retention + ESO) | $6–9 | Nenhum | 1–2h | **P0** | Parcialmente aplicado |
| 4 | VPC Endpoints para ECR API + ECR DKR | $5–9 | Nenhum | 2–4h | **P1** | Pendente |
| 5 | EIP orphan audit + KMS inventory | $2–8 | Nenhum | <1h | **P0** | Pendente |
| **TOTAL** | | **$163–221/mês** | | **~20–28h** | | |

**Nota:** Oportunidade de ALB consolidation (keycloak→platform-staging IngressGroup, ~$16/mês) não incluída neste plano por risco médio em sessões OIDC — avaliação separada.

---

## 1. Karpenter + Spot Instances — $140–180/mês

### Situação Atual

O node group `workloads` opera com **4x t3.large On-Demand** gerenciado pelo Cluster Autoscaler (CA). Custo estimado: ~$240/mês (4 × $0.0832/h × 720h). O CA tem limitações estruturais: sem suporte nativo a Spot, sem bin-packing otimizado, sem diversificação automática de instâncias. O colapso de capacidade de 2026-03-17 (CA réplicas=0, CPU 96-100%, pod limit ENI atingido) demonstrou a fragilidade do modelo atual.

**Node groups atuais (confirmado `platform-config.yaml` + TF state 2026-03-17):**

| Node Group | Instance Type | Qtd | Capacity Type | Custo On-Demand/mês |
|------------|--------------|-----|---------------|---------------------|
| system | t3.medium | 3 | ON_DEMAND | ~$105 |
| workloads | t3.large | 4 | ON_DEMAND | ~$240 |
| critical | t3.medium | 2–3 | ON_DEMAND | ~$70–105 |
| **Total** | | **9–10** | | **~$415–450/mês** |

Não há módulo Karpenter existente no repositório (`modules/` não contém karpenter — confirmado 2026-03-18).

### Plano de Implementação

**Estratégia:** Migração zero-downtime em 3 fases:
1. Instalar Karpenter no cluster (Helm via TF) sem remover CA
2. Criar NodePool Spot + EC2NodeClass para `workloads`
3. Drenar nodes CA do grupo `workloads` gradualmente; desabilitar CA para `workloads`

**System e critical node groups: ON-DEMAND — NAO ALTERAR.** Karpenter atua exclusivamente no node group `workloads`.

### Pré-requisitos

- [ ] AWS SSO ativo com permissões EKS + IAM + EC2
- [ ] EKS OIDC provider ARN disponível (já existe — `data.aws_iam_openid_connect_provider.eks` em staging/main.tf)
- [ ] Subnets privadas com IPs suficientes para Spot instances (verificar `aws ec2 describe-subnets`)
- [ ] SQS interruption queue permissão IAM (para Spot termination handling)
- [ ] Karpenter CRDs compatíveis com EKS 1.34 (Karpenter v0.37.x ou superior)
- [ ] Terraform provider `helm ~> 2.12` (já presente em staging/main.tf)

### Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| Interrupção Spot em workload ETL crítico | Média | Médio | Somente jobs idempotentes em Spot; usar `PodDisruptionBudget minAvailable=1` |
| Conflito CA + Karpenter durante coexistência | Alta | Médio | Labels exclusivos: CA gerencia `system/critical`, Karpenter gerencia `workloads` via `nodeSelector` |
| IAM IRSA incorreto — Karpenter não provisiona | Média | Alto | Usar IAM minimal declarado abaixo; testar com deployment dummy antes de migrar workloads |
| Spot unavailability no AZ (t3.large indisponível) | Baixa | Alto | Mix de 5 tipos de instância + fallback On-Demand no mesmo NodePool |
| TF drift pós-apply da migração | Alta | Médio | Rodar `terraform plan` após cada fase — gate obrigatório |

### Passos de Implementação

#### Fase 1 — Módulo Karpenter (Terraform)

**1.1 Criar módulo `modules/karpenter/`**

```hcl
# platform-provisioning/aws/kubernetes/terraform/modules/karpenter/main.tf

terraform {
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.0" }
    helm = { source = "hashicorp/helm", version = "~> 2.12" }
  }
}

# -----------------------------------------------------------------------------
# IAM Role para Karpenter Controller (IRSA)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "karpenter_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter" {
  name               = "karpenter-controller-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.karpenter_assume_role.json

  tags = merge(var.common_tags, {
    Name      = "karpenter-controller-${var.cluster_name}"
    Component = "karpenter"
  })
}

resource "aws_iam_role_policy" "karpenter" {
  name = "KarpenterControllerPolicy"
  role = aws_iam_role.karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceActions"
        Effect = "Allow"
        Resource = [
          "arn:aws:ec2:${var.aws_region}::image/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:spot-instances-request/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:launch-template/*",
        ]
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:DeleteLaunchTemplate",
          "ec2:TerminateInstances",
          "ec2:CreateTags",
        ]
      },
      {
        Sid      = "AllowScopedEC2InstanceActionsWithTags"
        Effect   = "Allow"
        Resource = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*"]
        Action   = ["ec2:TerminateInstances"]
        Condition = {
          StringLike = {
            "ec2:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Resource = [
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:fleet/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:volume/*",
          "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:network-interface/*",
          "arn:aws:ec2:${var.aws_region}::image/*",
        ]
        Action = ["ec2:CreateTags"]
      },
      {
        Sid    = "AllowScopedEC2ReadActions"
        Effect = "Allow"
        Resource = ["*"]
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
        ]
      },
      {
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Resource = aws_sqs_queue.interruption.arn
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
        ]
      },
      {
        Sid    = "AllowPassingInstanceRole"
        Effect = "Allow"
        Resource = ["arn:aws:iam::${var.aws_account_id}:role/${var.node_role_name}"]
        Action   = ["iam:PassRole"]
      },
      {
        Sid    = "AllowScopedInstanceProfileActions"
        Effect = "Allow"
        Resource = ["arn:aws:iam::${var.aws_account_id}:instance-profile/*"]
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
        ]
      },
      {
        Sid    = "AllowAPIServerEndpointDiscovery"
        Effect = "Allow"
        Resource = ["arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.cluster_name}"]
        Action   = ["eks:DescribeCluster"]
      },
      {
        Sid    = "AllowPricingReadActions"
        Effect = "Allow"
        Resource = ["*"]
        Action   = ["pricing:GetProducts"]
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# SQS Queue para Spot Interruption Handling
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "interruption" {
  name                      = "karpenter-interruption-${var.cluster_name}"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(var.common_tags, {
    Name    = "karpenter-interruption-${var.cluster_name}"
    Purpose = "karpenter-spot-interruption-handling"
  })
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2SpotInterruptionEvents"
        Effect = "Allow"
        Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.interruption.arn
      }
    ]
  })
}

# EventBridge rules → SQS para capturar eventos Spot
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "karpenter-spot-interruption-${var.cluster_name}"
  description = "Karpenter Spot interruption notices → SQS"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

# EventBridge para rebalancing e state change
resource "aws_cloudwatch_event_rule" "instance_rebalance" {
  name        = "karpenter-instance-rebalance-${var.cluster_name}"
  description = "Karpenter instance rebalance recommendations → SQS"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "instance_rebalance" {
  rule      = aws_cloudwatch_event_rule.instance_rebalance.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "karpenter-instance-state-change-${var.cluster_name}"
  description = "Karpenter EC2 instance state change → SQS"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

# -----------------------------------------------------------------------------
# Helm Release: Karpenter
# -----------------------------------------------------------------------------

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "kube-system"
  create_namespace = false

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version  # ex: "0.37.0"

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.interruption.name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter.arn
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "controller.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "512Mi"
  }

  # Rodar nos nodes system (On-Demand, toleração crítica)
  set {
    name  = "nodeSelector.node-type"
    value = "system"
  }

  depends_on = [aws_iam_role_policy.karpenter]
}
```

**1.2 Variáveis do módulo:**

```hcl
# platform-provisioning/aws/kubernetes/terraform/modules/karpenter/variables.tf

variable "cluster_name"      { type = string }
variable "aws_region"        { type = string }
variable "aws_account_id"    { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_url" { type = string }
variable "node_role_name"    { type = string }
variable "karpenter_version" { type = string; default = "0.37.0" }
variable "common_tags"       { type = map(string); default = {} }
```

**1.3 Outputs:**

```hcl
# platform-provisioning/aws/kubernetes/terraform/modules/karpenter/outputs.tf

output "interruption_queue_name" { value = aws_sqs_queue.interruption.name }
output "karpenter_role_arn"      { value = aws_iam_role.karpenter.arn }
```

#### Fase 2 — NodePool e EC2NodeClass para Workloads Spot

**2.1 EC2NodeClass (via `kubectl_manifest` no módulo Karpenter):**

```hcl
# Adicionar em platform-provisioning/aws/kubernetes/terraform/modules/karpenter/nodepools.tf

resource "kubectl_manifest" "ec2_nodeclass_workloads" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: workloads-spot
    spec:
      amiFamily: AL2

      # Role para os nodes provisionados por Karpenter
      role: "${var.node_role_name}"

      # Subnets: usar tags das subnets privadas do cluster
      subnetSelectorTerms:
        - tags:
            kubernetes.io/cluster/${var.cluster_name}: owned
            Type: private

      # Security groups do cluster
      securityGroupSelectorTerms:
        - tags:
            kubernetes.io/cluster/${var.cluster_name}: owned

      # EBS root volume: gp3 (20% mais barato que gp2, 3000 IOPS default)
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 50Gi
            volumeType: gp3
            iops: 3000
            throughput: 125
            deleteOnTermination: true
            encrypted: true

      # Tags propagadas para as instâncias EC2
      tags:
        Name: "karpenter-workloads-spot"
        NodeGroup: "workloads"
        ManagedBy: "karpenter"
        CapacityType: "spot"
        Environment: "${var.environment}"
        CostCenter: "development"

      # UserData: Configurar node-type label para nodeSelector dos workloads
      userData: |
        #!/bin/bash
        /etc/eks/bootstrap.sh ${var.cluster_name} \
          --kubelet-extra-args '--node-labels=node-type=workloads,karpenter.sh/capacity-type=spot'
  YAML

  depends_on = [helm_release.karpenter]
}
```

**2.2 NodePool (Spot com fallback On-Demand):**

```hcl
resource "kubectl_manifest" "nodepool_workloads_spot" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: workloads-spot
    spec:
      template:
        metadata:
          labels:
            node-type: workloads
            karpenter-managed: "true"

        spec:
          nodeClassRef:
            apiVersion: karpenter.k8s.aws/v1beta1
            kind: EC2NodeClass
            name: workloads-spot

          # Spot primeiro, On-Demand como fallback automático
          requirements:
            - key: "karpenter.sh/capacity-type"
              operator: In
              values: ["spot", "on-demand"]

            # Mix de instâncias para diversificação (evita single-type shortage)
            # us-east-1 Spot pricing 2026-03: t3.large ~$0.025/h, m5.large ~$0.028/h,
            # m6i.large ~$0.027/h, m5a.large ~$0.026/h, c5.large ~$0.022/h
            - key: "node.kubernetes.io/instance-type"
              operator: In
              values:
                - t3.large     # baseline — custo Spot ~$0.025/h (vs $0.0832/h On-Demand, -70%)
                - t3.xlarge    # burst CPU — ~$0.050/h Spot
                - m5.large     # balanced — ~$0.028/h Spot (melhor memória que t3.large)
                - m5a.large    # AMD — ~$0.026/h Spot (economia adicional vs m5)
                - m6i.large    # última geração — ~$0.027/h Spot
                - c5.large     # compute-optimized — ~$0.022/h Spot (runners, ETL)

            - key: "kubernetes.io/arch"
              operator: In
              values: ["amd64"]

            - key: "kubernetes.io/os"
              operator: In
              values: ["linux"]

            - key: "topology.kubernetes.io/zone"
              operator: In
              values: ["us-east-1a", "us-east-1b", "us-east-1c"]

      # Limites globais do NodePool
      limits:
        cpu: 40        # ~10 nodes x 4 vCPU — limite conservador
        memory: 80Gi   # ~10 nodes x 8GB

      # Consolidation: remover nodes sub-utilizados após 5 min
      disruption:
        consolidationPolicy: WhenUnderutilized
        consolidateAfter: 5m
        expireAfter: 720h    # 30 dias — forçar rotação para imagens AMI atualizadas

        # Budgets de disrupção — máximo de 1 node disrupted simultaneamente
        budgets:
          - nodes: "10%"     # máximo 10% dos nodes podem ser interrompidos por vez
  YAML

  depends_on = [kubectl_manifest.ec2_nodeclass_workloads]
}
```

#### Fase 3 — Integração com Staging Environment

**3.1 Adicionar em `environments/staging/main.tf`:**

```hcl
# -----------------------------------------------------------------------------
# KARPENTER — Workloads Spot Node Provisioning
# Substitui Cluster Autoscaler para o node group "workloads"
# Saving projetado: $140-180/mês (vs On-Demand puro)
# Migração: sem downtime — CA permanece para system/critical
# Adicionado: 2026-03-18
# -----------------------------------------------------------------------------

module "karpenter_staging" {
  source = "../../modules/karpenter"

  cluster_name      = local.cluster_name
  aws_region        = var.aws_region
  aws_account_id    = var.aws_account_id
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn
  oidc_provider_url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  node_role_name    = "k8s-platform-prod-eks-node-group-role"  # existente no EKS module

  karpenter_version = "0.37.0"
  environment       = local.environment
  common_tags       = local.common_tags
}
```

#### Fase 4 — Migração dos Workloads (Drenagem Gradual)

```bash
# Passo 4.1: Verificar NodePool ativo
kubectl get nodepool,ec2nodeclass
# Esperado: workloads-spot READY

# Passo 4.2: Verificar que Karpenter está provisionando
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50

# Passo 4.3: Drenar nodes do CA gradualmente (um de cada vez)
# Identificar nodes do CA que são "workloads"
kubectl get nodes -l node-type=workloads

# Para cada node workloads gerenciado pelo CA:
NODE="ip-10-0-x-x.ec2.internal"
kubectl cordon $NODE
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --grace-period=60

# Karpenter provisionará automaticamente nodes Spot para absorver os pods
# Aguardar 2-3 min entre cada drenagem
kubectl get nodes -l node-type=workloads  # verificar novos nodes Spot

# Passo 4.4: Escalar CA para 0 no grupo workloads (manter CA para system/critical)
# Via AWS Console ou TF: workloads node group min=0, desired=0, max=0
# OU: adicionar annotation de exclusão no CA
kubectl annotate node $CA_WORKLOAD_NODE cluster-autoscaler.kubernetes.io/scale-down-disabled="true"

# Passo 4.5: Validação final
kubectl get nodes -l karpenter.sh/capacity-type=spot
# Esperado: ≥2 nodes Spot provisionados pelo Karpenter
```

#### Fase 5 — Integração FinOps Lambda com Karpenter

O FinOps Lambda atual opera via ASG (Cluster Autoscaler). Com Karpenter, os nodes são provisionados como instâncias EC2 sem ASG fixo.

**Impacto no Lambda:** A Lambda `finops_stop` escala os ASGs para 0. Karpenter não usa ASGs — os nodes são provisionados diretamente via EC2 Fleet. O Lambda atual **não precisa de mudança** para o shutdown: quando os workloads são removidos pelo Lambda, os pods são encerrados e Karpenter detecta nodes sub-utilizados via `consolidation` e os termina automaticamente dentro de 5 minutos (`consolidateAfter: 5m`).

**Para o startup:** O Lambda inicia o ASG do `system`. Os pods de workload (se houver DaemonSets ou StatefulSets no namespace `workloads`) acionarão o Karpenter para provisionar novos nodes Spot. Nenhuma mudança necessária na Lambda de start.

**Ação adicional recomendada (não bloqueadora):** Adicionar tag `karpenter.sh/nodepool: workloads-spot` como filtro no Lambda stop para confirmar que não há ASG Karpenter sendo gerenciado acidentalmente.

### Gate de Validação

```bash
# Gate 1: Karpenter operacional
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
# Esperado: karpenter-xxxx Running

# Gate 2: NodePool + EC2NodeClass criados
kubectl get nodepool workloads-spot -o jsonpath='{.status.conditions}'
kubectl get ec2nodeclass workloads-spot -o jsonpath='{.status.conditions}'

# Gate 3: Nodes Spot confirmados
kubectl get nodes -l karpenter.sh/capacity-type=spot
# Esperado: ≥2 nodes com STATUS=Ready

# Gate 4: Workloads rodando em Spot
kubectl get pods -n staging-platform-gitlab -o wide | grep karpenter

# Gate 5: AWS Cost Explorer (D+1)
# EC2 Compute deve cair de ~$23/dia para ~$15-17/dia
# (verificar no dia seguinte ao deploy)

# Gate 6: Zero drift
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform plan
# Esperado: "No changes. Your infrastructure matches the configuration."
```

### Rollback Plan

```bash
# Rollback Karpenter (se necessário):

# 1. Re-escalar CA node group workloads
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "eks-k8s-platform-prod-workloads-*" \
  --min-size 2 --desired-capacity 4 --max-size 9

# 2. Remover NodePool (Karpenter drena nodes automaticamente)
kubectl delete nodepool workloads-spot

# 3. Desinstalar Karpenter (via Helm/TF)
helm uninstall karpenter -n kube-system

# 4. Remover módulo do TF e aplicar
# (state rm + terraform apply)
terraform state rm module.karpenter_staging
terraform apply  # remove recursos AWS sem deletar o cluster
```

### Esforço Estimado

| Tarefa | Horas |
|--------|-------|
| Criar módulo TF `modules/karpenter/` | 4h |
| NodePool + EC2NodeClass | 2h |
| Integração `staging/main.tf` | 1h |
| Terraform plan + apply + validação | 2h |
| Migração workloads (drenagem gradual) | 3h |
| Testes de scale-out + interrupção Spot simulada | 2h |
| Documentação + ADR | 2h |
| **Total Fase Karpenter** | **16–20h** |

---

## 2. Lambda Sunday Shutdown (GAP-LAMBDA-RC2) — $10–15/mês

### Situação Atual

O GAP-LAMBDA-RC2 foi identificado em 2026-03-17: quando o Lambda START é invocado manualmente em um domingo (como ocorreu em 15/03 — 4 invocações às 17:16 UTC), os nodes sobem e não há regra de shutdown para domingo. Resultado: nodes rodaram de domingo 17:16 UTC até segunda 23:00 UTC — cerca de 30 horas a mais de custo.

**Saving calculado:** $9.72/domingo × 4 domingos/mês ≈ **$38.88/mês** no pior caso (todos os domingos com nodes up). No caso conservador (1-2 domingos afetados/mês): **$10–20/mês**.

**Status atual:** A regra `aws_cloudwatch_event_rule.sunday_shutdown` já foi codificada no módulo `finops-automation/main.tf` (GAP-LAMBDA-RC2, 2026-03-17). A variável `sunday_shutdown_schedule = "cron(0 23 ? * SUN *)"` também está definida em `variables.tf`.

### Plano de Implementação

O TF está pronto. O único passo necessário é confirmar que `enable_automation = true` está configurado no módulo `finops_automation` em `staging/main.tf`.

**Verificar em `staging/main.tf`:**

```bash
grep -A 20 "module.*finops" platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf
# Confirmar: enable_automation = true
# Se false: alterar para true e aplicar
```

**Apply:**

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform plan -target=module.finops_automation
# Esperado: 1 resource to add (aws_cloudwatch_event_rule.sunday_shutdown)
terraform apply -target=module.finops_automation
```

### Gate de Validação

```bash
# Confirmar regra criada
aws events describe-rule \
  --name "finops-sunday-shutdown-staging" \
  --region us-east-1 \
  --query '{State: State, ScheduleExpression: ScheduleExpression}'
# Esperado: {"State": "ENABLED", "ScheduleExpression": "cron(0 23 ? * SUN *)"}

# Verificar no próximo domingo (D+7): custo do domingo cai ~$9.72
# AWS CE: filtrar EC2 Compute por domingo — comparar antes e depois
```

### Rollback Plan

```bash
aws events disable-rule --name "finops-sunday-shutdown-staging" --region us-east-1
```

### Esforço Estimado

< 1 hora (apenas confirmar variável TF + apply).

---

## 3. CloudWatch Tuning — $6–9/mês

### Situação Atual

**Análise de custo CloudWatch (fonte: cloudwatch-cost-analysis-2026-03-10.md + finops-analysis-2026-03-18.md):**

| Componente | Custo estimado/mês | Status TF atual |
|------------|-------------------|-----------------|
| EKS Control Plane Logs (tipos ativos) | ~$7–10/mês | `enabled_cluster_log_types = ["audit", "authenticator"]` — JÁ OTIMIZADO |
| Retention EKS log group | ~$2–3/mês | `retention_in_days = 7` — JÁ OTIMIZADO |
| ESO refreshInterval (11 ExternalSecrets × 1/min) | ~$1–2/mês | **Pendente** |
| Container Insights (verificar se ativo) | ~$5–8/mês | **Verificação pendente** |
| Lambda finops logs (retention 14d) | ~$0.15/mês | OK |

**Status real (módulo EKS confirmado 2026-03-11):**
- EKS log types: JÁ REDUZIDO de 5 para 2 (apenas `audit` + `authenticator`) — saving de $25–35/mês já aplicado
- Retention: JÁ definido em 7 dias no TF

**Oportunidades remanescentes:**

**A3 — ESO refreshInterval (saving: $1–2/mês):**
Os 11 ExternalSecrets têm `refreshInterval: 1m` — geram 15.840 API calls/dia em audit logs. Aumentar para `5m` reduz 80% do volume de sync.

**A4 — Container Insights audit (saving: $5–8/mês se ativo):**
Verificar se o addon `amazon-cloudwatch-observability` está ativo. Se confirmado ativo, desabilitar via TF.

### Plano de Implementação

**A3 — ESO refreshInterval (operacional, sem risco):**

Localizar todos os ExternalSecrets com `refreshInterval: 1m`:

```bash
kubectl get externalsecrets -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.spec.refreshInterval}{"\n"}{end}'
```

Atualizar no módulo `external-secrets` ou nos manifests YAML — mudar `refreshInterval: 1m` para `refreshInterval: 5m`.

No TF (se os ExternalSecrets são gerenciados via `kubernetes_manifest`):

```hcl
# Localizar o recurso e alterar o refreshInterval
# Ex: em modules/external-secrets/main.tf ou módulos de serviço específicos
# Buscar: refreshInterval: "1m"  →  refreshInterval: "5m"
```

**A4 — Container Insights (verificação + desabilitar se ativo):**

```bash
# Verificar add-ons EKS
aws eks list-addons \
  --cluster-name k8s-platform-prod \
  --region us-east-1 \
  --query 'addons'

# Se "amazon-cloudwatch-observability" aparecer → desabilitar via TF:
# No módulo eks/main.tf, NÃO adicionar este addon (ou remover se presente)
# Se aplicado manualmente: aws eks delete-addon --cluster-name k8s-platform-prod --addon-name amazon-cloudwatch-observability
```

### Pré-requisitos

- Cluster UP e kubectl configurado
- `grep -r "refreshInterval" platform-provisioning/` para localizar todos os ExternalSecrets gerenciados por TF

### Gate de Validação

```bash
# A3: Confirmar novo refreshInterval
kubectl get externalsecrets -A -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.refreshInterval}{"\n"}{end}'
# Esperado: todas as entradas com 5m (ou 300s)

# A4: Container Insights ausente
aws eks list-addons --cluster-name k8s-platform-prod --region us-east-1
# Esperado: amazon-cloudwatch-observability NÃO presente

# Custo: verificar CloudWatch em 7 dias — deve cair de ~$75/mês para ~$65–70/mês
```

### Rollback Plan

```bash
# A3: reverter refreshInterval para 1m nos ExternalSecrets (kubectl patch)
# A4: Container Insights pode ser re-habilitado via aws eks create-addon se necessário
```

### Esforço Estimado

| Tarefa | Horas |
|--------|-------|
| Verificar status EKS log types + retention (confirmar aplicado) | 0.5h |
| Localizar e atualizar ESO refreshInterval | 1h |
| Verificar + desabilitar Container Insights (se ativo) | 0.5h |
| Terraform plan + apply | 0.5h |
| **Total** | **2.5h** |

---

## 4. VPC Endpoints para ECR API + ECR DKR — $5–9/mês

### Situação Atual

**Composição do custo VPC/NAT ($96/mês estimado):**
- 2 NAT Gateways (us-east-1a + us-east-1b): $0.045/h × 2 × 720h = **$64.80/mês fixo** (não eliminável)
- Data transfer via NAT: **~$31/mês variável**

O S3 Gateway Endpoint já foi implementado (2026-02-12) — salva $5–8/mês em data transfer Velero/Loki/Tempo/Harbor.

**Oportunidade remanescente:** ECR API e ECR DKR ainda roteiam via NAT. O cluster puxa imagens Docker frequentemente (Harbor pulls, pod restarts, node scale-out). Com VPC Interface Endpoints para ECR, o tráfego bypassa o NAT Gateway.

| Endpoint | Custo/mês | Saving NAT estimado | Líquido |
|----------|-----------|---------------------|---------|
| ECR API (`com.amazonaws.us-east-1.ecr.api`) | ~$1–2/mês | ~$3–5/mês | **+$1–3/mês** |
| ECR DKR (`com.amazonaws.us-east-1.ecr.dkr`) | ~$1–2/mês | ~$2–4/mês | **+$0–2/mês** |
| **Total líquido** | | | **$1–5/mês** |

**Nota conservadora:** O saving real depende do volume de ECR traffic via NAT. Com Harbor funcionando como registry proxy (configurado no cluster), parte do tráfego pode já ser cacheado — o saving pode ser na faixa baixa ($1–3/mês líquido).

**Saving bruto (sem Harbor cache):** $5–9/mês. Com Harbor cache: $2–5/mês líquido.

### Plano de Implementação

**Verificar primeiro se endpoints já existem:**

```bash
aws ec2 describe-vpc-endpoints \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=$(aws ec2 describe-vpcs --filters 'Name=tag:Name,Values=*k8s*' --query 'Vpcs[0].VpcId' --output text)" \
  --query 'VpcEndpoints[].{ServiceName:ServiceName,State:State}'
```

**TF — Adicionar endpoints no módulo de infraestrutura ou em staging/main.tf:**

```hcl
# platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf
# (ou em módulo compartilhado se prod também vai usar)

# -----------------------------------------------------------------------------
# VPC Interface Endpoints — ECR (FinOps: reduz NAT data transfer $5-9/mês)
# S3 Gateway Endpoint já existe (2026-02-12)
# Adicionado: 2026-03-18
# -----------------------------------------------------------------------------

data "aws_vpc" "main" {
  id = var.vpc_id
}

data "aws_security_group" "cluster" {
  filter {
    name   = "tag:Name"
    values = ["*k8s-platform-prod*cluster*"]
  }
}

# ECR API Endpoint (interface)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.private.ids
  security_group_ids  = [data.aws_security_group.cluster.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name    = "vpc-endpoint-ecr-api"
    Purpose = "FinOps: elimina NAT data transfer para ECR API"
  })
}

# ECR DKR Endpoint (interface — Docker registry pulls)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.private.ids
  security_group_ids  = [data.aws_security_group.cluster.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name    = "vpc-endpoint-ecr-dkr"
    Purpose = "FinOps: elimina NAT data transfer para Docker registry pulls"
  })
}
```

**Inbound rule no Security Group (se não houver regra HTTPS inbound do cluster):**

```hcl
resource "aws_security_group_rule" "allow_https_from_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = data.aws_security_group.cluster.id
  security_group_id        = data.aws_security_group.cluster.id
  description              = "Allow HTTPS from cluster nodes to VPC endpoints"
}
```

### Gate de Validação

```bash
# Confirmar endpoints criados
aws ec2 describe-vpc-endpoints \
  --region us-east-1 \
  --filters "Name=service-name,Values=com.amazonaws.us-east-1.ecr.api" \
  --query 'VpcEndpoints[0].State'
# Esperado: "available"

aws ec2 describe-vpc-endpoints \
  --region us-east-1 \
  --filters "Name=service-name,Values=com.amazonaws.us-east-1.ecr.dkr" \
  --query 'VpcEndpoints[0].State'
# Esperado: "available"

# Testar routing privado (em um node do cluster):
kubectl run test-ecr --image=amazonlinux:2 --restart=Never -it --rm -- \
  curl -s https://api.ecr.us-east-1.amazonaws.com/token 2>&1 | head -5
# Esperado: resposta via endpoint privado (sem timeout NAT)

# Confirmar redução em AWS CE (D+3):
# VPC data transfer deve cair — visualizar em CE por serviço "VPC" por dia
```

### Rollback Plan

```bash
# Deletar endpoints (tráfego retorna automaticamente via NAT)
terraform destroy -target=aws_vpc_endpoint.ecr_api -target=aws_vpc_endpoint.ecr_dkr
```

### Esforço Estimado

| Tarefa | Horas |
|--------|-------|
| Verificar endpoints existentes + subnets | 0.5h |
| TF snippet + plan | 1h |
| Apply + validação DNS + testes | 1h |
| **Total** | **2.5h** |

---

## 5. EIP Orphan Audit + KMS Inventory — $2–8/mês

### Situação Atual

**EIPs (Elastic IPs):** EIPs não associados a instâncias ou ENIs custam **$0.005/hora = $3.65/mês cada**. Com RDS, EKS nodes e ALBs, é comum acumular EIPs de recursos deletados. A análise de custo indica **EC2-Other de $158/mês** — parte desta fatia pode incluir EIPs órfãos.

**KMS CMKs:** Com $7/mês de KMS, existem aproximadamente 5–7 CMKs customer-managed ($1/chave/mês). Chaves de migração, teste ou projetos descontinuados que não são mais usadas representam custo recorrente desnecessário.

### Plano de Implementação

**Auditoria EIPs (5 minutos):**

```bash
# Listar todos os EIPs e identificar não-associados
aws ec2 describe-addresses \
  --region us-east-1 \
  --query 'Addresses[?AssociationId==`null`].{AllocationId:AllocationId,PublicIp:PublicIp,Tags:Tags}' \
  --output table

# Para cada EIP orphan identificado:
# 1. Verificar se é necessário (NAT Gateways têm EIPs — não deletar)
aws ec2 describe-nat-gateways --region us-east-1 \
  --query 'NatGateways[*].NatGatewayAddresses[*].AllocationId' \
  --output text

# 2. Deletar EIPs órfãos (excluindo NAT GW):
aws ec2 release-address --allocation-id eipalloc-XXXXX --region us-east-1

# Via TF: adicionar data source para mapear EIPs alocados vs usados
# (Opcional — se quiser codificar em IaC para prevenção contínua)
```

**KMS Inventory (10 minutos):**

```bash
# Listar todas as CMKs ativas
aws kms list-keys --region us-east-1 \
  --query 'Keys[*].KeyId' --output text | \
  xargs -I {} aws kms describe-key --key-id {} \
  --query 'KeyMetadata.{KeyId:KeyId,Description:Description,Enabled:Enabled,LastUsedDate:LastRotationDate}' \
  --output table

# Para chaves suspeitas (sem descrição ou sem uso recente):
# Verificar uso via CloudTrail (últimos 90 dias)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=arn:aws:kms:us-east-1:891377105802:key/KEY-ID \
  --start-time 2025-12-18 \
  --query 'Events[*].EventName' \
  --region us-east-1

# Se sem uso: schedule key deletion (mínimo 7 dias antes de deletar)
aws kms schedule-key-deletion --key-id KEY-ID --pending-window-in-days 7 --region us-east-1
```

**Prevenção via módulo orphan-detector (já existe em `modules/orphan-detector/`):**

```bash
# Verificar se o módulo está habilitado no staging
grep -r "orphan-detector" platform-provisioning/aws/kubernetes/terraform/environments/staging/
# Se não encontrado: habilitar o módulo existente
```

```hcl
# Se o módulo orphan-detector existente não estiver ativo, adicionar em staging/main.tf:
module "orphan_detector_staging" {
  source = "../../modules/orphan-detector"

  environment    = local.environment
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id
  common_tags    = local.common_tags
}
```

### Gate de Validação

```bash
# Zero EIPs não associados (exceto os dos NAT GWs)
aws ec2 describe-addresses \
  --region us-east-1 \
  --query 'Addresses[?AssociationId==`null`] | length(@)'
# Esperado: 0 (ou apenas os EIPs dos NAT Gateways)

# KMS: número de CMKs ativas deve ser justificável
aws kms list-keys --region us-east-1 --query 'Keys | length(@)'
# Esperado: ≤6 (EKS + RDS + S3-Velero + S3-GitLab + DynamoDB-FinOps + 1 spare)
```

### Rollback Plan

EIPs deletados não são recuperáveis — verificar cuidadosamente antes de liberar. KMS scheduled deletion tem janela de 7–30 dias — cancelar com `aws kms cancel-key-deletion` se necessário.

### Esforço Estimado

| Tarefa | Horas |
|--------|-------|
| Auditoria EIPs | 0.5h |
| KMS inventory + análise CloudTrail | 0.5h |
| Verificar módulo orphan-detector | 0.5h |
| **Total** | **1.5h** |

---

## Sequência de Execução Recomendada

```
SEMANA 1 (2026-03-18 a 22) — P0 Quick Wins (esforço total: ~5h)

  DIA 1 (hoje):
    [1h] OP-5: EIP orphan audit + KMS inventory — zero risco, impacto imediato
    [0.5h] OP-2: Confirmar Sunday shutdown rule ativa + apply se enable_automation=false
    [1h] OP-3-A4: Verificar Container Insights — desabilitar se ativo ($5-8/mês)

  DIA 2:
    [2h] OP-3-A3: Localizar ESO refreshInterval + patch para 5m + apply
    [0.5h] OP-3: terraform plan staging → confirmar zero drift

SEMANA 2 (2026-03-25 a 29) — Karpenter (esforço total: ~16-20h)

  DIA 1-2 (2 dias):
    [4h] Criar modules/karpenter/ (IAM + SQS + Helm release)
    [2h] NodePool + EC2NodeClass YAML
    [1h] Integrar staging/main.tf

  DIA 3:
    [2h] terraform plan -target=module.karpenter_staging + apply
    [1h] Validar Karpenter UP: kubectl get nodepool,ec2nodeclass
    [2h] Deploy de workload dummy (20 réplicas) → testar scale-out Spot

  DIA 4-5:
    [3h] Migração gradual: drenar nodes CA workloads um a um
    [1h] Validação final: nodes Spot confirmados, workloads Running, CA system OK
    [2h] ADR + documentação

SEMANA 3 (2026-04-01 a 05) — VPC Endpoints (esforço total: ~2.5h)

  DIA 1:
    [0.5h] Verificar endpoints existentes
    [1h] TF ECR endpoints + security group rule
    [1h] Apply + teste DNS resolução ECR via endpoint privado
```

**Saving por semana:**

| Semana | Ação | Saving incremental | Custo após |
|--------|------|--------------------|------------|
| Baseline | — | — | ~$1.194/mês |
| S1 | OP-2 + OP-3 + OP-5 | $18–32/mês | ~$1.162–1.176/mês |
| S2 | Karpenter + Spot | $140–180/mês | ~$982–1.036/mês |
| S3 | VPC Endpoints ECR | $5–9/mês | ~$973–1.031/mês |
| **Target** | | **$163–221/mês** | **~$973–1.031/mês** |

**Meta:** Custo dentro do budget aprovado de $1.000/mês após Semana 2.

---

## Monitoramento Pós-Implementação

### Métricas a Monitorar (AWS Cost Explorer + Grafana)

| Métrica | Baseline | Meta pós-S2 | Frequência check |
|---------|----------|-------------|-----------------|
| EC2 Compute/dia | ~$23/dia | ~$13–17/dia | Diária |
| VPC/NAT/dia | ~$3/dia | ~$2.5/dia | Semanal |
| CloudWatch/dia | ~$2.7/dia | ~$2.3/dia | Semanal |
| Total/dia | ~$39.82/dia | ~$28–33/dia | Diária |
| Nodes Spot ativos | 0 | ≥2–4 | Contínuo |
| Karpenter consolidation events | — | ≥1/semana | Semanal |

### Dashboard Grafana (já existe `finops-alerts.json` + `resource-utilization.json`)

Adicionar painel Karpenter com:
- Custo estimado por node (Spot vs On-Demand via Karpenter annotations)
- Nodes provisionados por capacity-type
- Consolidation events por dia
- Scale-out latency (tempo de pod Pending → Running)

### Alertas Recomendados

```yaml
# Adicionar no módulo observability ou kube-prometheus-stack:

- alert: KarpenterNoSpotNodesAfter1h
  expr: count(kube_node_labels{label_karpenter_sh_capacity_type="spot"}) == 0
  for: 1h
  annotations:
    summary: "Nenhum node Spot ativo por >1h — verificar Karpenter e disponibilidade Spot"

- alert: EC2DailyCostAboveTarget
  # Baseado em métrica customizada do FinOps Lambda (cost_savings_daily)
  expr: aws_billing_estimated_charges > 35  # $35/dia = ~$1.050/mês
  for: 1d
  annotations:
    summary: "Custo EC2 acima de $35/dia — revisar Karpenter + Lambda shutdown"
```

### Checkpoints de Revisão

| Data | Evento | Ação |
|------|--------|------|
| 2026-03-25 | Karpenter deploy | Verificar nodes Spot + custo D+1 |
| 2026-04-01 | 1 semana Karpenter | CE comparativo semana anterior — confirmar $140–180/mês saving |
| 2026-04-07 | VPC Endpoints 1 semana | CE VPC/NAT — confirmar redução data transfer |
| 2026-04-18 | 1 mês completo | Revisão financeira completa — MTD vs budget $1.000 |
| 2026-05-01 | 45 dias Karpenter | Análise Spot interruption rate + workload stability |

---

## Appendix — Gate de Sucesso deste Documento

- [x] Análise baseada em dados reais do projeto (finops-analysis-2026-03-18.md, TF modules confirmados)
- [x] 5 seções de oportunidades com TF snippets concretos
- [x] Karpenter: IAM IRSA completo + SQS interruption + Helm release + NodePool + EC2NodeClass
- [x] Estratégia migração CA → Karpenter sem downtime (4 fases graduais)
- [x] Instance types recomendados: t3.large, t3.xlarge, m5.large, m5a.large, m6i.large, c5.large (mix diversificado)
- [x] Spot termination handling via SQS + EventBridge rules
- [x] Integração FinOps Lambda: Lambda stop não precisa de mudança (Karpenter drena via consolidation)
- [x] System e critical node groups On-Demand: INALTERADOS
- [x] Sequência de execução clara por semana com saving incremental
- [x] Rollback plans para cada oportunidade
- [x] Total saving: $163–221/mês | Esforço: ~22–28h | Meta: dentro do budget $1.000/mês após S2

---

*Documento produzido pelo FinOps Specialist + Performance & Capacity Specialist*
*Framework: executor-terraform.md | Data: 2026-03-18*
*Próxima revisão: 2026-04-01 (pós-deploy Karpenter)*
