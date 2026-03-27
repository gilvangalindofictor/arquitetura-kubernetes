# =============================================================================
# GAP-CONF-004: Cluster Autoscaler — Helm Release IaC Codification
#
# O Cluster Autoscaler foi instalado via helm diretamente e NAO esta no TF state.
# Este arquivo codifica a instalacao existente para zero-drift compliance.
#
# Cluster CA atual:
#   helm list -n kube-system -> cluster-autoscaler (chart autoscaler-9.37.0)
#   Deployment: cluster-autoscaler-aws-cluster-autoscaler (1/1 Running)
#   PDB: cluster-autoscaler-pdb (codificado em cluster-autoscaler-protection.tf)
#   PrometheusRule: cluster-autoscaler-resilience (codificado em cluster-autoscaler-protection.tf)
#   ASG Tags: codificado em cluster-autoscaler-tags.tf
#
# IMPORTANTE — ANTES DE TERRAFORM APPLY:
#   1. Executar import do helm release existente:
#      terraform import helm_release.cluster_autoscaler kube-system/cluster-autoscaler
#   2. Rodar terraform plan para confirmar "No changes"
#   3. Se houver diff, ajustar valores abaixo para match exato do cluster
#
# ADR: ADR-TBD (cluster-autoscaler-resiliencia)
# Demand: docs/demands/2026-03-17-cluster-autoscaler-resiliencia.md
# =============================================================================

resource "helm_release" "cluster_autoscaler" {
  name             = "cluster-autoscaler"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = "9.37.0"
  namespace        = "kube-system"
  create_namespace = false

  # Timeout: CA e leve, 5min suficiente
  timeout = 300

  values = [<<-YAML
    autoDiscovery:
      clusterName: ${local.cluster_name}

    awsRegion: ${var.aws_region}

    replicaCount: 1

    # Prioridade critica — CA NAO pode ser preempted
    priorityClassName: system-cluster-critical

    # Protecao contra eviction durante node drain
    podAnnotations:
      cluster-autoscaler.kubernetes.io/safe-to-evict: "false"

    # Node placement: system nodes (CA precisa estar em nodes estaveis)
    nodeSelector:
      eks.amazonaws.com/nodegroup: system

    # Tolerations para system taint
    tolerations:
      - key: node-type
        value: system
        effect: NoSchedule

    # Resources: CA e leve mas precisa de headroom para picos de decisao
    resources:
      requests:
        cpu: 100m
        memory: 300Mi
      limits:
        memory: 500Mi

    # Expander: least-waste (otimiza custo — ADR FinOps)
    extraArgs:
      balance-similar-node-groups: true
      skip-nodes-with-system-pods: true
      skip-nodes-with-local-storage: false
      expander: least-waste
      scale-down-delay-after-add: 10m
      scale-down-unneeded-time: 10m

    # RBAC (necessario para interacao com ASG)
    rbac:
      create: true

    # ServiceAccount com IRSA — usar SA pre-existente (criado via TF kubernetes_service_account)
    # O SA "cluster-autoscaler" ja possui a annotation IRSA correta para
    # ClusterAutoscalerRole-k8s-platform-prod e a trust policy do IAM role
    # referencia "system:serviceaccount:kube-system:cluster-autoscaler"
    serviceAccount:
      create: false
      name: cluster-autoscaler
      annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::${var.aws_account_id}:role/ClusterAutoscalerRole-${local.cluster_name}"
  YAML
  ]

  # Lifecycle: nao destruir CA acidentalmente
  lifecycle {
    prevent_destroy = true
  }
}
