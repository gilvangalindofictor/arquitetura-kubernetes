# 📓 Correção Crítica - Deadlock em EKS Add-ons

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-01-28                               |
| **Demanda**    | Corrigir falha NodeCreationFailure em todos os node groups |
| **Impacto**    | Crítico (Cluster EKS não operacional)    |
| **Agentes**    | DevOps Team, AWS Specialist              |
| **Status**     | ✅ Concluído                             |
| **Duração**    | ~1h 5min (troubleshooting + correção)    |

---

## Problema Crítico Identificado

### Sintoma

Durante deploy do cluster EKS (Marco 1), terraform apply criou o cluster com sucesso (~11 minutos), porém **todos os 3 node groups falharam** após 33 minutos com o erro:

```
Error: NodeCreationFailure: Unhealthy nodes in the kubernetes cluster
```

### Node Groups Afetados

- `system` (2 nodes t3.medium)
- `workloads` (3 nodes t3.large)
- `critical` (2 nodes t3.xlarge)

**Tempo até Falha:** 33 minutos 27 segundos

---

## Diagnóstico

### Investigação Realizada

**1. Verificação de Rede:**
- ✅ Subnets privadas existem e estão associadas corretamente
- ✅ NAT Gateways operacionais (2 AZs)
- ✅ Security Groups criados com regras corretas
- ✅ Route tables configuradas

**2. Verificação de IAM:**
- ✅ Node IAM Role criada (`k8s-platform-prod-node-role`)
- ✅ Policies attachadas corretamente

**3. Verificação de EC2:**
- ✅ AMI ID válida (`ami-0bcb7d2dcf0ac106e`)
- ✅ Instance types disponíveis

**4. Verificação de Add-ons (CAUSA RAIZ):**
```bash
aws eks list-addons --cluster-name k8s-platform-prod
# Resultado: []
# ❌ NENHUM ADD-ON INSTALADO!
```

---

## Causa Raiz: Deadlock de Dependências no Terraform

### Configuração Incorreta

```terraform
# ❌ PROBLEMA: Add-ons dependiam dos Node Groups ficarem ACTIVE

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  depends_on   = [aws_eks_node_group.system]  # ❌ DEADLOCK!
}

# Mas Node Groups precisam do vpc-cni para ficarem Ready
resource "aws_eks_node_group" "system" {
  cluster_name = aws_eks_cluster.main.name
  # ❌ IMPLICITAMENTE dependia de vpc-cni estar instalado
}
```

### Consequência

- Add-ons esperavam nodes ficarem ACTIVE para serem instalados
- Nodes esperavam vpc-cni (add-on) para ficarem Ready e ACTIVE
- **Resultado:** Deadlock circular → Timeout após 30 min → NodeCreationFailure

---

## Solução Implementada

### 1. Add-ons Essenciais (vpc-cni, kube-proxy)

```terraform
# ✅ CORRETO: Add-ons dependem apenas do cluster

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  depends_on   = [aws_eks_cluster.main]  # ✅ Correto
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
  depends_on   = [aws_eks_cluster.main]  # ✅ Correto
}
```

### 2. Add-on CoreDNS

```terraform
# ✅ CoreDNS depende do vpc-cni

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_cluster.main, aws_eks_addon.vpc_cni]  # ✅ Correto
}
```

### 3. Node Groups

```terraform
# ✅ Node groups dependem explicitamente do vpc-cni

resource "aws_eks_node_group" "system" {
  cluster_name = aws_eks_cluster.main.name
  depends_on   = [aws_eks_cluster.main, aws_eks_addon.vpc_cni]  # ✅ Explícito
}

resource "aws_eks_node_group" "workloads" {
  cluster_name = aws_eks_cluster.main.name
  depends_on   = [aws_eks_cluster.main, aws_eks_addon.vpc_cni]  # ✅ Explícito
}

resource "aws_eks_node_group" "critical" {
  cluster_name = aws_eks_cluster.main.name
  depends_on   = [aws_eks_cluster.main, aws_eks_addon.vpc_cni]  # ✅ Explícito
}
```

### 4. EBS CSI Driver

```terraform
# ✅ Add-on que roda em pods depende de nodes

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"
  depends_on   = [aws_eks_node_group.system]  # ✅ Correto - precisa de nodes
}
```

---

## Ordem de Criação Correta

```
1. EKS Cluster (~11 min)
   ↓
2. vpc-cni e kube-proxy add-ons (~30s em paralelo)
   ↓
3. coredns add-on + Node Groups (~1-2 min em paralelo)
   ↓  (coredns aguarda nodes Ready ~5-7 min)
4. ebs-csi-driver add-on (~46s, após nodes system)
```

---

## Execução e Resultado

### Comandos Executados

**1. Backup do state:**
```bash
cd /marco1
terraform state pull > backups/terraform.tfstate.backup-20260128-132722
# Tamanho: 31KB
```

**2. Destruir recursos falhados:**
```bash
terraform destroy \
  -target=aws_eks_node_group.system \
  -target=aws_eks_node_group.workloads \
  -target=aws_eks_node_group.critical \
  -auto-approve
# Resultado: 12 recursos destruídos em 7 minutos
```

**3. Terraform apply completo:**
```bash
nohup terraform apply -auto-approve > /tmp/terraform-marco1-apply-$(date +%Y%m%d-%H%M%S).log 2>&1 &
# Tempo total: ~18 minutos
# Resultado: 16 recursos criados, 0 falhas
```

### Resultado Final

```
✅ Apply complete! Resources: 16 added, 0 changed, 0 destroyed.

Outputs:
cluster_name                 = "k8s-platform-prod"
cluster_version              = "1.31"
node_group_system_status     = "ACTIVE"
node_group_workloads_status  = "ACTIVE"
node_group_critical_status   = "ACTIVE"
```

---

## Validação

### Nodes (7 total)

```bash
kubectl get nodes

NAME                           STATUS   AGE
ip-10-0-143-62.ec2.internal    Ready    7m32s  # system (us-east-1a)
ip-10-0-158-64.ec2.internal    Ready    7m33s  # system (us-east-1b)
ip-10-0-136-133.ec2.internal   Ready    7m39s  # workloads (us-east-1a)
ip-10-0-147-59.ec2.internal    Ready    7m29s  # workloads (us-east-1b)
ip-10-0-157-90.ec2.internal    Ready    7m21s  # workloads (us-east-1b)
ip-10-0-134-166.ec2.internal   Ready    7m37s  # critical (us-east-1a)
ip-10-0-158-137.ec2.internal   Ready    7m39s  # critical (us-east-1b)
```

### Add-ons (4 ACTIVE)

```bash
aws eks list-addons --cluster-name k8s-platform-prod

- aws-ebs-csi-driver: v1.37.0-eksbuild.1 (ACTIVE)
- coredns: v1.11.3-eksbuild.2 (ACTIVE)
- kube-proxy: v1.31.2-eksbuild.3 (ACTIVE)
- vpc-cni: v1.18.5-eksbuild.1 (ACTIVE)
```

### Pods kube-system (25 total)

```bash
kubectl get pods -n kube-system

aws-node (vpc-cni):           7/7 Running (DaemonSet)
kube-proxy:                   7/7 Running (DaemonSet)
coredns:                      2/2 Running
ebs-csi-controller:           2/2 Running (6 containers each)
ebs-csi-node:                 7/7 Running (DaemonSet, 3 containers each)
```

### Teste de Pod

```bash
kubectl run test-pod --image=nginx:alpine --restart=Never -- sleep 3600
# Resultado: 1/1 Running após 7s
# ✅ Scheduling OK, Networking OK
```

---

## Lições Aprendidas

### 🏗️ Arquitetura e Dependências

| # | Lição | Impacto |
|---|-------|---------|
| 1 | **Add-ons essenciais (vpc-cni, kube-proxy) NUNCA devem depender de node groups** → nodes precisam destes add-ons para ficarem Ready | 🔴 Crítico |
| 2 | Node groups devem ter dependência **explícita** do vpc-cni no Terraform | 🔴 Crítico |
| 3 | Add-ons que rodam em pods (ebs-csi-driver) devem depender de pelo menos 1 node group estar ACTIVE | 🟡 Médio |
| 4 | CoreDNS pode aguardar nodes Ready por 5-7 minutos → comportamento normal | 🟢 Baixo |

### 📐 Padrão Recomendado

```
Cluster → vpc-cni + kube-proxy → [coredns + Node Groups] → ebs-csi-driver
```

### ⚙️ Troubleshooting

| # | Lição | Impacto |
|---|-------|---------|
| 5 | Sempre verificar add-ons instalados com `aws eks list-addons` quando nodes falham | 🔴 Crítico |
| 6 | Backup do state antes de destroy é obrigatório para troubleshooting | 🟡 Médio |
| 7 | NodeCreationFailure após 30+ minutos indica problema de dependência circular | 🟡 Médio |

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Tempo perdido (apply inicial) | ~40 min |
| Tempo de correção | ~25 min (destroy + apply) |
| **Tempo total** | **1h 5min** |
| Recursos destruídos | 12 |
| Recursos recriados | 16 |
| Downtime | N/A (cluster não estava em produção) |

---

## Impacto

**Custo:**
- Tempo: 1h 5min (aceitável para troubleshooting crítico)

**Benefício:**
- ✅ Cluster EKS totalmente funcional e validado
- ✅ Padrão de dependências correto documentado
- ✅ Prevenção de futuras falhas similares
- ✅ Knowledge base atualizado

---

## Referências

- [AWS EKS Best Practices: Managing Add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- Terraform AWS Provider Issue #24663: "EKS Add-ons timing issues with node groups"
- [Arquivo modificado: marco1/main.tf](../../platform-provisioning/aws/kubernetes/terraform/envs/marco1/main.tf)
