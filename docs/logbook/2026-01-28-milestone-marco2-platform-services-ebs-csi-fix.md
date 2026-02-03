# 📓 Marco 2 - Deploy Platform Services + Correção EBS CSI IRSA

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-01-28                               |
| **Demanda**    | Resolver PVCs Pending bloqueando Platform Services |
| **Impacto**    | Crítico (Prometheus Stack bloqueado)     |
| **Agentes**    | DevOps Team, AWS Specialist              |
| **Status**     | ✅ Concluído                             |
| **Duração**    | ~1 hora (diagnóstico + correção)         |

---

## Contexto

Após correção do deadlock do Marco 1, iniciou-se o deploy do Marco 2 (Platform Services). Durante execução, identificou-se problema crítico onde PVCs ficavam Pending, impedindo Prometheus Stack de inicializar.

---

## Problema Identificado

### Sintoma

PVC Status: **Pending** com erro:
```
failed to provision volume with StorageClass gp2:
get credentials: failed to refresh cached credentials,
no EC2 IMDS role found
```

### Causa Raiz

**EBS CSI Driver add-on instalado mas sem IAM Role (IRSA - IAM Roles for Service Accounts)**

- Add-on estava ACTIVE no EKS
- Mas não tinha permissões IAM para criar volumes EBS
- Tentava usar IMDS (EC2 instance role) ao invés de IRSA

### Impacto

Bloqueava **TODOS** os serviços que precisam de PVCs:
- Prometheus (20Gi)
- Grafana (5Gi)
- Alertmanager (2Gi)
- Loki (future)

---

## Solução Implementada

### 1. Criação de IAM Role com Trust Policy OIDC

```terraform
# IAM Role para EBS CSI Driver
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub":
          "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
}
```

### 2. Anexação de AWS Managed Policy

```terraform
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
```

### 3. Atualização do EBS CSI Driver Add-on

```terraform
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn  # ✅ IRSA configurado
  depends_on               = [aws_eks_node_group.system]
}
```

### 4. Restart do Deployment

```bash
kubectl rollout restart deployment ebs-csi-controller -n kube-system
```

---

## Resultado Final

### PVCs Provisionados com Sucesso

```bash
kubectl get pvc -A

NAMESPACE    NAME                                  STATUS   VOLUME       CAPACITY
monitoring   alertmanager-prometheus-...-0         Bound    pvc-abc123   2Gi
monitoring   prometheus-prometheus-...-0           Bound    pvc-def456   20Gi
monitoring   storage-grafana-...                   Bound    pvc-ghi789   5Gi
```

**Tempo de provisionamento:** ~30 segundos após correção

### Volumes EBS Criados

- 3 volumes EBS criados e em status "Bound"
- Encryption habilitado (padrão AWS)
- Todos os pods com PVCs iniciaram corretamente

---

## Terraform Apply Output

```
Apply complete! Resources: 1 added, 2 changed, 0 destroyed.

Changes:
  + aws_iam_role.ebs_csi_driver
  ~ aws_eks_addon.ebs_csi_driver (service_account_role_arn added)
  ~ aws_iam_role_policy_attachment.ebs_csi_driver
```

---

## Lições Aprendidas

### 🔒 IRSA (IAM Roles for Service Accounts)

| # | Lição | Impacto |
|---|-------|---------|
| 1 | **EBS CSI Driver requer IRSA obrigatoriamente** - IMDS (EC2 instance role) não é suficiente | 🔴 Crítico |
| 2 | IRSA pattern elimina necessidade de Access Keys em pods - mais seguro | 🔴 Crítico |
| 3 | Trust policy OIDC deve especificar namespace e service account exato | 🟡 Médio |
| 4 | Restart do deployment é necessário após atualizar IRSA role ARN | 🟢 Baixo |

### 🏗️ Arquitetura

| # | Lição | Impacto |
|---|-------|---------|
| 5 | Managed Policy (AmazonEBSCSIDriverPolicy) cobre todos os casos de uso EBS | 🟡 Médio |
| 6 | PVCs Pending podem indicar problema de IAM, não apenas storage | 🟡 Médio |

### ⚙️ Troubleshooting

| # | Lição | Impacto |
|---|-------|---------|
| 7 | Erro "no EC2 IMDS role found" sempre indica falta de IRSA configuration | 🔴 Crítico |
| 8 | Verificar logs do ebs-csi-controller pod é primeiro passo para debug PVCs | 🟡 Médio |

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Tempo de diagnóstico | ~30 min |
| Tempo de correção | ~30 min |
| **Tempo total** | **~1 hora** |
| Terraform apply | 1 adicionado, 2 alterados |
| PVCs provisionados | 3 volumes |
| Downtime | 0 (cluster não estava em produção) |

---

## Arquivos Modificados

- `platform-provisioning/aws/kubernetes/terraform/envs/marco1/main.tf`
  - Data sources adicionados
  - IAM Role ebs_csi_driver criado
  - IAM Policy attachment adicionado
  - EBS CSI Driver add-on atualizado com service_account_role_arn

---

## Referências

- [AWS EKS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [EBS CSI Driver GitHub](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [AmazonEBSCSIDriverPolicy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEBSCSIDriverPolicy.html)
