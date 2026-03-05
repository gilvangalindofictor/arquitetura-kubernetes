# System Node Group max_size 4 → 6

**Data:** 2026-03-05
**Executor:** DevOps Sênior
**Cluster:** k8s-platform-prod (EKS 1.34, us-east-1)
**ASG:** eks-system-a8ce02d9-0774-d561-d896-d70f87493bc5

## Razão

- 4 nós system (t3.medium) todos em 17/17 pods — limite máximo por ENI
- DaemonSets como `linkerd-cni`, `prometheus-node-exporter`, `velero/node-agent` ficavam Pending ao escalar para novos nós
- Cluster autoscaler reportava "max node group size reached" para os 3 grupos
- Headroom necessário para shared services entre staging e prod (fase futura)

## Mudança Aplicada

| Parâmetro | Antes | Depois |
|-----------|-------|--------|
| min_size  | 2     | 2      |
| max_size  | **4** | **6**  |
| desired   | 4     | 4      |

## Método

**Cenário B — AWS CLI direto** (node group não gerenciado pelo Terraform do ambiente staging).

O ambiente staging (`environments/staging/main.tf`) não define os node groups EKS — eles foram criados manualmente via console/eksctl e estão fora do estado Terraform. O `cluster-autoscaler-tags.tf` gerencia apenas as tags de discovery.

Comando aplicado:
```bash
aws eks update-nodegroup-config \
  --cluster-name k8s-platform-prod \
  --nodegroup-name system \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --scaling-config minSize=2,maxSize=6,desiredSize=4
```

Update ID: `b64c3140-53f5-3039-8e36-4ac7399cc2c5` | Status final: `ACTIVE`

## Verificação

```
| Desired | Max | Min |
|---------|-----|-----|
|    4    |  6  |  2  |
```

Tags cluster-autoscaler presentes e corretas:
- `k8s.io/cluster-autoscaler/enabled = true`
- `k8s.io/cluster-autoscaler/k8s-platform-prod = owned`

## Custo Delta

- Mudança no **max** não ativa novos nós imediatamente — autoscaler decide quando escalar
- Se/quando 2 nós adicionais forem ativados: +US$ ~62/mês (2x t3.medium on-demand)
- Condição de ativação: pods Pending por insuficiência de recursos nos 4 nós existentes

## IaC Debt

O node group `system` (e também `workloads`, `critical`) **não está importado no Terraform**.

Arquivo de referência de debt:
- `platform-provisioning/aws/kubernetes/terraform/environments/staging/cluster-autoscaler-tags.tf` — gerencia apenas ASG tags via `data.aws_eks_node_group`
- Os node groups em si precisam ser importados para `environments/staging/main.tf` ou um módulo dedicado

**Ação pendente (baixa urgência):**
```bash
terraform import aws_eks_node_group.system k8s-platform-prod:system
```
Requer criar o recurso `aws_eks_node_group "system"` no Terraform antes de importar.

## Arquivos Alterados

- `platform-config.yaml` — max_size atualizado de 4 para 6 (fonte de verdade)
- `docs/logbook/2026-03-05-system-asg-max-increase.md` — este arquivo
