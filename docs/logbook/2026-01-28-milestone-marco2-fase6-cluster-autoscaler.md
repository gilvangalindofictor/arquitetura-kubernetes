# 📓 Marco 2 Fase 6 - Cluster Autoscaler

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-01-28                               |
| **Demanda**    | Implementar auto-scaling de nodes        |
| **Impacto**    | Médio (FinOps + Elasticidade)            |
| **Agentes**    | FinOps Specialist, DevOps Team           |
| **Status**     | ✅ Concluído                             |
| **Duração**    | ~1 hora (implementação completa)         |

---

## Contexto

Implementação de auto-scaling de nodes para o node group "workloads", permitindo economia de custos através de scale-down durante períodos de baixa utilização.

---

## Objetivo

Permitir que o cluster escale automaticamente nodes (horizontal node autoscaling) conforme demanda de workloads varia.

**Benefícios:**
- 💰 Redução de custos (scale-down durante idle)
- 🚀 Elasticidade (scale-up durante picos)
- ⚙️ Zero intervenção manual

---

## Decisão Técnica

**Escolhida:** Cluster Autoscaler

**Alternativa Avaliada:** Karpenter

| Critério | Cluster Autoscaler | Karpenter |
|----------|-------------------|-----------|
| Maturidade | ✅ Maduro (5+ anos) | ⚠️ Recente (2 anos) |
| Invasividade | ✅ Não invasivo | ⚠️ Requer refatoração ASGs |
| Compatibilidade | ✅ Funciona com ASGs existentes | ⚠️ Cria Launch Templates próprios |
| Time-to-market | ✅ Rápido (1 hora) | ⚠️ Lento (requer rewrite Marco 1) |

**Decisão:** Cluster Autoscaler ✅

---

## Implementação

### Fase 1: Marco 1 - Preparação (ASG Tags)

**Objetivo:** Marcar Auto Scaling Groups para Cluster Autoscaler discovery

**Tags Aplicadas:**

**Node Group "workloads" (autoscaling habilitado):**
```terraform
tags = {
  "k8s.io/cluster-autoscaler/enabled"             = "true"
  "k8s.io/cluster-autoscaler/k8s-platform-prod"   = "owned"
}
```

**Node Groups "system" e "critical" (autoscaling desabilitado):**
```terraform
tags = {
  "k8s.io/cluster-autoscaler/enabled"             = "false"
  "k8s.io/cluster-autoscaler/k8s-platform-prod"   = "disabled"
}
```

**Terraform Apply:**
- Tempo: **1 segundo**
- Recursos modificados: 6 tags

### Fase 2: Marco 2 - Cluster Autoscaler Module

**Componentes Criados:**

**1. IAM Policy (Least Privilege)**
```terraform
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ],
    "Resource": "*",
    "Condition": {
      "StringEquals": {
        "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled": "true"
      }
    }
  }]
}
```

**2. IAM Role com Trust Policy OIDC**
- Service Account: `cluster-autoscaler`
- Namespace: `kube-system`

**3. Helm Chart Deployment**
- Chart: `cluster-autoscaler` v9.37.0
- App Version: 1.31.0
- Image: `registry.k8s.io/autoscaling/cluster-autoscaler:v1.31.0`

**4. Integração com Prometheus**
- ServiceMonitor criado para métricas
- Métricas disponíveis: `cluster_autoscaler_*`

---

## Configuração

### Parâmetros Principais

```yaml
cluster:
  name: k8s-platform-prod

autoDiscovery:
  clusterName: k8s-platform-prod
  enabled: true
  tags:
    - k8s.io/cluster-autoscaler/enabled
    - k8s.io/cluster-autoscaler/k8s-platform-prod

scaleDown:
  enabled: true
  delayAfterAdd: 10m
  unneededTime: 10m
  utilizationThreshold: 0.5  # 50%
```

### Node Groups Afetados

| Node Group | Min | Desired | Max | Autoscaling |
|------------|-----|---------|-----|-------------|
| system | 2 | 2 | 2 | ❌ Disabled |
| **workloads** | **2** | **3** | **5** | **✅ Enabled** |
| critical | 2 | 2 | 2 | ❌ Disabled |

---

## Resultado Final

### Deployment Status

```bash
kubectl get deployment cluster-autoscaler -n kube-system

NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
cluster-autoscaler   1/1     1            1           3m52s
```

### Logs de Inicialização

```
Starting cluster-autoscaler version v1.31.0
Cluster Autoscaler loaded 794 EC2 instance types
Discovered Auto Scaling Groups:
  - k8s-platform-prod-workloads (2-5 nodes, enabled)
  - k8s-platform-prod-system (disabled)
  - k8s-platform-prod-critical (disabled)
Auto Scaling Groups discovery: SUCCESS
```

### Validação IRSA

```bash
kubectl describe sa cluster-autoscaler -n kube-system

Annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::891377105802:role/k8s-platform-prod-cluster-autoscaler
```

✅ IRSA configurado corretamente

---

## Terraform Apply Output

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Time: 33 seconds

Resources created:
  + aws_iam_policy.cluster_autoscaler
  + aws_iam_role.cluster_autoscaler
  + aws_iam_role_policy_attachment.cluster_autoscaler
  + kubernetes_service_account.cluster_autoscaler
  + helm_release.cluster_autoscaler
```

---

## Custo e ROI

### Custo Adicional

| Item | Valor |
|------|-------|
| Cluster Autoscaler pod | **$0/mês** (roda em nodes system existentes) |
| Overhead CPU/RAM | Negligível (<50Mi RAM) |

**Total:** **$0/mês** ✅

### Economia Esperada

**Cenário Base:**
- 1 node workload (t3.large) desligado ~70% do tempo
- Custo t3.large: $44/mês (on-demand ~50% do tempo)

**Cálculo:**
```
Economia = 1 node × $44/mês × 70% idle × 12 meses
Economia = $370/ano
```

**ROI:**
- Custo implementação: $0
- Economia anual: **~$372/ano** (23% savings no node group workloads)
- **ROI: Imediato** ✅

---

## Lições Aprendidas

### 💰 FinOps

| # | Lição | Impacto |
|---|-------|---------|
| 1 | **Cluster Autoscaler tem custo zero** - roda em nodes system existentes | 🟢 Baixo |
| 2 | Scale-down savings podem chegar a 23% em workloads variáveis | 🟡 Médio |
| 3 | Least privilege IAM policy com condition tags previne scale de node groups críticos | 🔴 Crítico |

### 🏗️ Arquitetura

| # | Lição | Impacto |
|---|-------|---------|
| 4 | **ASG tags são obrigatórios** para Cluster Autoscaler discovery | 🔴 Crítico |
| 5 | Node groups system e critical devem ter autoscaling DISABLED para estabilidade | 🔴 Crítico |
| 6 | Cluster Autoscaler carrega 794 EC2 instance types - permite optimização futura | 🟢 Baixo |

### ⚙️ Operações

| # | Lição | Impacto |
|---|-------|---------|
| 7 | Delay após scale-up (10min) previne thrashing | 🟡 Médio |
| 8 | Utilization threshold 50% é bom equilíbrio entre economia e performance | 🟢 Baixo |
| 9 | Integração com Prometheus permite alertas em métricas de autoscaling | 🟡 Médio |

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Tempo Marco 1 (tags) | 1 segundo |
| Tempo Marco 2 (deployment) | 33 segundos |
| **Tempo total** | **~1 hora** (incluindo documentação) |
| Recursos criados | 5 (IAM + SA + Helm) |
| Node groups habilitados | 1 (workloads) |
| EC2 instance types carregados | 794 |

---

## Documentação Criada

- ✅ **ADR-007:** Cluster Autoscaler Strategy (aprovado)
- ✅ **Terraform module:** `modules/cluster-autoscaler/`
  - main.tf (210 linhas)
  - variables.tf (85 linhas)
  - outputs.tf
  - versions.tf

---

## Referências

- [ADR-007: Cluster Autoscaler Strategy](../adr/adr-007-cluster-autoscaler-strategy.md)
- [Cluster Autoscaler GitHub](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
- [AWS EKS Autoscaling](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html)
- [Módulo Terraform](../../platform-provisioning/aws/kubernetes/terraform/modules/cluster-autoscaler/)
