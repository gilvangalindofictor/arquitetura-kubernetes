# =============================================================================
# GAP-CONF-018 (P2): Spot Instances — Mixed Node Group para Workloads
# =============================================================================
# Problema: 100% On-Demand sem Spot/Savings Plans. Custo total ~R$1.800/mes
#   por node t3.large On-Demand. Workloads node group com 6-12 nodes = despesa
#   significativa sem otimizacao.
#
# Solucao: Node group adicional "workloads-spot" com SPOT capacity_type.
#   - Apenas para workloads tolerantes a interrupcao (stateless, retryable)
#   - Node group "system" e "critical" permanecem ON_DEMAND (NUNCA Spot)
#   - Fallback: workloads sem toleration ao taint "capacity=spot" continuam
#     no node group "workloads" On-Demand
#
# Economia estimada: 60-70% desconto vs On-Demand para t3.large
#   - t3.large On-Demand: ~$0.0832/h = ~R$1.800/mes
#   - t3.large Spot:      ~$0.025/h  = ~R$540/mes (savings ~R$1.260/mes por node)
#   - 2 nodes Spot:       savings ~R$2.520/mes = ~R$30.240/ano
#
# Instance diversification: t3.large + t3a.large + m5.large + m5a.large
#   Minimiza interrupcao: AWS aloca a instancia Spot mais barata disponivel.
#   Se um tipo for reclamado, ASG tenta os demais automaticamente.
#
# Taint: capacity=spot:PreferNoSchedule
#   - PreferNoSchedule (soft): pods SEM toleration preferem On-Demand mas
#     podem ser schedulados em Spot se nao houver capacity On-Demand.
#   - Pods com toleration explicita capacity=spot sao priorizados neste ng.
#
# IMPORTANTE:
#   - NAO usar Spot para system, critical, databases, stateful workloads
#   - Workloads devem ter PDB configurado (GAP-CONF-019)
#   - Cluster Autoscaler gerencia desired_size (lifecycle ignore_changes)
#   - Spot interruptions sao tratadas pelo AWS Node Termination Handler
#     (TODO: instalar se ausente — verificar DaemonSet aws-node-termination-handler)
#
# Ref: https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html
#      https://aws.amazon.com/ec2/spot/pricing/
# =============================================================================

resource "aws_eks_node_group" "workloads_spot" {
  cluster_name    = local.cluster_name
  node_group_name = "workloads-spot"
  node_role_arn   = local.node_role_arn
  subnet_ids      = local.private_subnets

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "SPOT"
  disk_size      = 50
  instance_types = ["t3.large", "t3a.large", "m5.large", "m5a.large"]
  version        = "1.34"

  scaling_config {
    desired_size = 0 # Inicia com 0 — Cluster Autoscaler escala conforme demanda
    min_size     = 0
    max_size     = 4 # Limite conservador — aumentar conforme adocao
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    node-type     = "workloads"
    workload      = "applications"
    capacity-type = "spot"
  }

  # PreferNoSchedule: pods sem toleration preferem On-Demand, mas aceitam Spot se necessario
  taint {
    key    = "capacity"
    value  = "spot"
    effect = "PREFER_NO_SCHEDULE"
  }

  tags = merge(local.node_group_common_tags, {
    Name          = "k8s-platform-prod-workloads-spot"
    NodeGroup     = "workloads-spot"
    CapacityType  = "spot"
  })

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size, # Cluster Autoscaler gerencia
      release_version,                 # EKS managed updates
    ]
  }
}
