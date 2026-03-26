# node-groups.tf — EKS Node Groups (system, workloads, critical) + EKS Auth Mode
# Importado em 2026-03-05 — anteriormente gerenciados via AWS CLI (eks create-nodegroup)
# NOTE: data "aws_eks_node_group" já definidos em cluster-autoscaler-tags.tf — não replicar aqui
#
# Taint real do critical: workload=critical:NO_SCHEDULE (capturado via describe-nodegroup 2026-03-05)
# NOTA: platform-config.yaml documenta value="database" mas AWS retornou value="critical" — usando valor real
# max_size system: aumentado de 4→6 em 2026-03-05 (IaC debt documentado)
#
# ReleaseVersion: 1.34.2-20260129 — gerenciado via lifecycle ignore_changes (cluster autoscaler pode alterar)
#
# GAP-FINOPS-ACCESS-ENTRY (2026-03-26): EKS auth mode CONFIG_MAP -> API_AND_CONFIG_MAP
#   Mudanca nao-destrutiva: nao remove aws-auth ConfigMap, apenas adiciona suporte a access entries via API.
#   Necessario para Lambda FinOps criar/validar access entries sem depender exclusivamente do ConfigMap.
#   aws eks describe-cluster confirmou: authenticationMode = "CONFIG_MAP" (sem access_config block no TF).
#
# GAP-WORKLOAD-CPU-SAT (2026-03-26): workloads max_size 9->12
#   Diagnostico: 5 de 9 nodes t3.large com 87-99% CPU requests — ASG ja no max_size=9.
#   Cluster Autoscaler bloqueado: nao pode escalar alem do max_size.
#   Target headroom: 70-80% CPU requests — 3 nodes adicionais liberam ~6 vCPU de buffer.
#   Impacto FinOps: ~R$1.800/mes por node adicional (t3.large ON_DEMAND) — custo condicional
#   (CA so sobe node se houver pods Pending — sem custo em cenario sem demanda extra).

locals {
  node_role_arn = "arn:aws:iam::891377105802:role/k8s-platform-eks-node-role"

  # GAP-ARCH-013 (TODO — HIGH RISK, DO NOT apply without drain plan):
  # private_subnets está hardcoded em 2 AZs (subnet-0288a67cd352effa7, subnet-0472ab28726cdf745).
  # O correto seria usar data.aws_subnets.private.ids para cobrir as 3 AZs da VPC.
  # BLOQUEADOR: alterar subnet_ids em node groups existentes força replacement (destroy + recreate).
  # PLANO DE FIX:
  #   1. Confirmar IDs das 3 subnets privadas via: aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-0b1396a59c417c1f0 Name=tag:Name,Values="*private*" --query 'Subnets[].SubnetId'
  #   2. Adicionar 3ª subnet ao array (não remover as 2 existentes no mesmo apply — evitar force-replace)
  #   3. Executar terraform plan para confirmar que apenas scaling_config é alterado (não subnet_ids)
  #   4. Se subnet_ids causar replacement, usar: aws eks create-nodegroup com 3 subnets + migração gradual de workloads + delete do ng antigo
  #   QUANDO: Próxima janela de manutenção programada (low-traffic window)
  private_subnets = ["subnet-0288a67cd352effa7", "subnet-0472ab28726cdf745"]

  # GAP-ARCH-012 (2026-03-23): CostCenter alinhado com local.common_tags (era "Engineering" hardcoded)
  # Usar merge com common_tags garante consistência com o restante do ambiente staging.
  node_group_common_tags = merge(local.common_tags, {
    Marco     = "marco1"
    NodeGroup = "managed"
  })
}

resource "aws_eks_node_group" "system" {
  cluster_name    = local.cluster_name
  node_group_name = "system"
  node_role_arn   = local.node_role_arn
  subnet_ids      = local.private_subnets

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  disk_size      = 30
  instance_types = ["t3.medium"]
  version        = "1.34"
  release_version = "1.34.2-20260129"

  scaling_config {
    desired_size = 4 # gerenciado pelo cluster autoscaler
    min_size     = 2
    max_size     = 5 # FIX-011: aumentado de 4→5 para acomodar prometheus-0 após node OOM 2026-03-26 (escalado via AWS console — codificado aqui para zero drift)
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    node-type = "system"
    workload  = "platform"
  }

  # Fase A3 (2026-03-23): Taint node-type=system:NoSchedule
  # Impede workloads sem toleration de agendar em system nodes (reserva capacidade para componentes de plataforma).
  # Gate: todos DaemonSets auditados têm operator=Exists (wildcard) ou toleration explícita — nenhum impactado.
  # Prometheus, Alertmanager, Grafana, kube-state-metrics, pushgateway: tolerations codificadas no módulo kube-prometheus-stack.
  taint {
    key    = "node-type"
    value  = "system"
    effect = "NO_SCHEDULE"
  }

  tags = merge(local.node_group_common_tags, {
    Name      = "k8s-platform-prod-system"
    NodeGroup = "system"
  })

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size, # cluster autoscaler gerencia desired_size
      release_version,                 # EKS managed updates alteram release_version
    ]
  }
}

resource "aws_eks_node_group" "workloads" {
  cluster_name    = local.cluster_name
  node_group_name = "workloads"
  node_role_arn   = local.node_role_arn
  subnet_ids      = local.private_subnets

  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  disk_size       = 50
  instance_types  = ["t3.large"]
  version         = "1.34"
  release_version = "1.34.2-20260129"

  scaling_config {
    desired_size = 6 # gerenciado pelo cluster autoscaler
    min_size     = 2
    max_size     = 12 # GAP-WORKLOAD-CPU-SAT (2026-03-26): aumentado de 9->12 — 5 nodes em 87-99% CPU requests, ASG estava no limite; 3 slots extras liberam ~6 vCPU headroom para CA escalar
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    node-type = "workloads"
    workload  = "applications"
  }

  tags = merge(local.node_group_common_tags, {
    Name      = "k8s-platform-prod-workloads"
    NodeGroup = "workloads"
  })

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size,
      release_version,
    ]
  }
}

resource "aws_eks_node_group" "critical" {
  cluster_name    = local.cluster_name
  node_group_name = "critical"
  node_role_arn   = local.node_role_arn
  subnet_ids      = local.private_subnets

  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  disk_size       = 100
  instance_types  = ["t3.xlarge"]
  version         = "1.34"
  release_version = "1.34.2-20260129"

  scaling_config {
    desired_size = 2 # gerenciado pelo cluster autoscaler
    min_size     = 2
    max_size     = 4
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    node-type = "critical"
    workload  = "databases"
  }

  taint {
    key    = "workload"
    value  = "critical" # valor real capturado via describe-nodegroup (platform-config.yaml documenta "database" — divergência documentada)
    effect = "NO_SCHEDULE"
  }

  tags = merge(local.node_group_common_tags, {
    Name      = "k8s-platform-prod-critical"
    NodeGroup = "critical"
  })

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size,
      release_version,
    ]
  }
}

# -----------------------------------------------------------------------------
# GAP-FINOPS-ACCESS-ENTRY (2026-03-26): EKS Authentication Mode — API_AND_CONFIG_MAP
# -----------------------------------------------------------------------------
# Diagnostico: aws eks describe-cluster --name k8s-platform-prod retornou
#   authenticationMode = "CONFIG_MAP" (sem access_config no TF — drift).
#
# Problema: CONFIG_MAP nao permite criar EKS access entries via API AWS.
#   - aws eks list-access-entries retornava InvalidRequestException
#   - Lambda FinOps nao consegue gerenciar access entries programaticamente
#   - Bloqueio total para IRSA fine-grained, futuro Karpenter, auditoria BACEN via API
#
# Solucao: API_AND_CONFIG_MAP
#   - Nao-destrutivo: aws-auth ConfigMap permanece funcional (retrocompat total)
#   - Adiciona capacidade de criar/listar/deletar access entries via AWS API
#   - Permite migrar gradualmente de ConfigMap para access entries (sem janela de manutencao)
#
# Impacto: ZERO downtime — EKS suporta transicao CONFIG_MAP -> API_AND_CONFIG_MAP
#   sem restart do control plane. AWS docs confirmam: transicao e one-way
#   (rollback API_AND_CONFIG_MAP -> CONFIG_MAP nao e suportado pela AWS).
#
# Nota IaC: O cluster k8s-platform-prod foi criado fora do estado Terraform desta env
#   (bootstrapped via AWS CLI / Marco0). O recurso aws_eks_cluster nao existe no state.
#   A propriedade authentication_mode so pode ser definida no bloco access_config do
#   aws_eks_cluster resource ou via AWS CLI (update-cluster-config).
#   Solucao escolhida: null_resource com local-exec idempotente — aplica somente se
#   o modo atual for CONFIG_MAP, garantindo idempotencia em re-applies.
#
# Proxima acao recomendada: importar o aws_eks_cluster para o TF state e adicionar
#   access_config { authentication_mode = "API_AND_CONFIG_MAP" } diretamente no resource.
#   Isso eliminaria a dependencia do null_resource e garantiria drift detection nativo.
#
# Referencia: https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html
# -----------------------------------------------------------------------------
resource "null_resource" "eks_auth_mode_api_and_configmap" {
  # Trigger: muda se o cluster_name mudar (garante re-exec em novo cluster)
  triggers = {
    cluster_name = local.cluster_name
    target_mode  = "API_AND_CONFIG_MAP"
  }

  provisioner "local-exec" {
    # Idempotente: verifica modo atual antes de aplicar.
    # Se ja for API_AND_CONFIG_MAP ou API, nao faz nada.
    # Se for CONFIG_MAP, aplica update-cluster-config e aguarda ACTIVE.
    command = <<-EOT
      CURRENT_MODE=$(aws eks describe-cluster \
        --name ${local.cluster_name} \
        --region ${var.aws_region} \
        --query 'cluster.accessConfig.authenticationMode' \
        --output text 2>/dev/null)
      echo "Current EKS auth mode: $CURRENT_MODE"
      if [ "$CURRENT_MODE" = "CONFIG_MAP" ]; then
        echo "Updating EKS auth mode CONFIG_MAP -> API_AND_CONFIG_MAP..."
        aws eks update-cluster-config \
          --name ${local.cluster_name} \
          --region ${var.aws_region} \
          --access-config authenticationMode=API_AND_CONFIG_MAP
        echo "Waiting for cluster to become ACTIVE..."
        aws eks wait cluster-active \
          --name ${local.cluster_name} \
          --region ${var.aws_region}
        echo "EKS auth mode updated successfully."
      else
        echo "EKS auth mode is already $CURRENT_MODE — no action needed."
      fi
    EOT
    interpreter = ["bash", "-c"]
  }
}
