# EKS Managed Addons — Staging
# ADR-063: AWS_VPC_K8S_CNI_EXTERNALSNAT=true (2026-02-19)
# GAP-SCHED-003 (2026-03-23): ebs-csi-controller nodeSelector→workloads (libera slot system us-east-1a)
# GAP-FINOPS-SCHED-001 (2026-03-24): coredns + ebs-csi toleration node-type=system:NoSchedule
#   Contexto: durante shutdown FinOps, workload nodes escalam para 0; apenas system nodes ficam ativos.
#   CoreDNS e ebs-csi-controller ficavam Pending por ausência de toleration → DNS quebrado + EBS offline.
#   Fix: adicionar toleration node-type=system:NoSchedule em ambos os addons.
#   ebs-csi-controller: GAP-SCHED-003 mantido via nodeAffinity preferred (não mais hard nodeSelector)
#   para que durante o shutdown o controller consiga reagendar nos system nodes.
# Ver: docs/logbook/2026-02-19-post-up-investigation.md (STOP-AND-FIX #3)
#
# CAUSA: VPC CNI secondary ENI não tem rota para S3 Gateway Endpoint na per-pod routing table
# FIX:   EXTERNALSNAT=true → pods usam SNAT via IP primário do node → subnet route table
#        → S3 Gateway Endpoint rota matchada
#
# IMPORTANTE: Ao adicionar configurationValues, o EKS addon faz rolling update do DaemonSet.
# Os valores abaixo persistem o estado já aplicado via kubectl patch em 2026-02-19.
#
# ENABLE_PREFIX_DELEGATION=true (2026-03-09)
# Motivo: aumenta capacidade de pods por nó sem adicionar ENIs adicionais.
# t3.medium: 3 ENIs × 16 IPs (/28 prefix) = 48 pods (vs 17 sem prefix delegation).
# t3.large:  3 ENIs × 16 IPs (/28 prefix) = 48 pods por ENI.
# WARM_PREFIX_TARGET=1: mantém 1 prefix de reserva por node para evitar latência
# de alocação durante scale-up de pods.
# Ativar em paralelo com rolling upgrade do Linkerd (2026-03-09).

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = local.cluster_name
  addon_name   = "vpc-cni"

  # Versão gerenciada externamente — ignore upgrades automáticos via TF
  # (upgrades devem ser feitos deliberadamente via console ou CI)
  addon_version = "v1.18.5-eksbuild.1"

  # Preserva configurações após upgrades do addon.
  # EXTERNALSNAT=true: pods usam SNAT via IP primário do node (fix S3 Gateway Endpoint)
  # ENABLE_PREFIX_DELEGATION=true: /28 IPv4 prefixes por ENI → mais pods por node
  # WARM_PREFIX_TARGET=1: 1 prefix pré-alocado → sem latência no scale-up
  configuration_values = jsonencode({
    env = {
      AWS_VPC_K8S_CNI_EXTERNALSNAT = "true"
      ENABLE_PREFIX_DELEGATION     = "true"
      WARM_PREFIX_TARGET           = "1"
    }
  })

  # Não sobrescrever mudanças manuais em caso de conflito (graceful)
  resolve_conflicts_on_update = "PRESERVE"

  lifecycle {
    # Permite upgrade da versão sem recriar (via console ou CI)
    ignore_changes = [addon_version]
  }

  tags = merge(local.common_tags, {
    Name    = "vpc-cni-addon"
    ADR     = "ADR-063"
    Purpose = "S3-Gateway-Endpoint-EXTERNALSNAT-fix"
  })
}

# -----------------------------------------------------------------------------
# GAP-SCHED-003 (2026-03-23): ebs-csi-controller → workloads nodes
# Contexto: controller com nodeSelector genérico {kubernetes.io/os: linux} escalava
#   para system nodes (t3.medium), consumindo 1 slot precioso em us-east-1a.
# Fix: nodeSelector eks.amazonaws.com/nodegroup=workloads força controller
#   para nodes de workload (t3.large/xlarge). DaemonSet ebs-csi-node NÃO afetado.
# Método: kubectl patch aplicado emergencialmente → redistribuição imediata confirmada.
# IaC: configurationValues codifica o nodeSelector aqui para zero drift.
# Antes: 17 pods em system us-east-1a | Depois: 16 pods (1 slot liberado).
# Resultado: controller em workloads us-east-1a + us-east-1b (2 réplicas HA).
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = local.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  # Versão gerenciada externamente — ignore upgrades automáticos via TF
  addon_version = "v1.37.0-eksbuild.1"

  # IRSA: role criada via console/eksctl para o EBS CSI Driver
  # Necessário para UpdateAddon não rejeitar com Cross-account pass role error
  service_account_role_arn = "arn:aws:iam::891377105802:role/AmazonEKS_EBS_CSI_DriverRole-k8s-platform-prod"

  # GAP-SCHED-003 (mantido): controller prefere workloads nodes via nodeAffinity preferred.
  #   Convertido de hard nodeSelector para preferredDuringSchedulingIgnoredDuringExecution
  #   para que durante o shutdown FinOps (workload nodes = 0) o controller consiga reagendar
  #   nos system nodes. Com hard nodeSelector + system toleration o pod ainda ficaria Pending.
  #
  # GAP-FINOPS-SCHED-001: toleration node-type=system:NoSchedule adicionada.
  #   Durante shutdown, workloads nodes escalam para 0. O controller precisa tolerar o taint
  #   dos system nodes para reagendar lá e manter a capacidade de attach de EBS volumes.
  #   O DaemonSet ebs-csi-node NÃO é afetado por este configurationValues.
  configuration_values = jsonencode({
    controller = {
      # Preferência soft por workloads nodes (GAP-SCHED-003 intent preservado)
      # Durante normal ops: controller vai para workloads (weight=100, praticamente garantido)
      # Durante shutdown (workloads gone): scheduler ignora preferência → agenda em system nodes
      affinity = {
        nodeAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              preference = {
                matchExpressions = [
                  {
                    key      = "eks.amazonaws.com/nodegroup"
                    operator = "In"
                    values   = ["workloads"]
                  }
                ]
              }
            }
          ]
        }
      }
      # GAP-FINOPS-SCHED-001: tolerar taint dos system nodes para sobreviver ao shutdown FinOps
      tolerations = [
        {
          key      = "node-type"
          operator = "Equal"
          value    = "system"
          effect   = "NoSchedule"
        }
      ]
    }
  })

  resolve_conflicts_on_update = "OVERWRITE"

  lifecycle {
    ignore_changes = [addon_version]
  }

  tags = merge(local.common_tags, {
    Name    = "ebs-csi-driver-addon"
    GAP     = "GAP-SCHED-003,GAP-FINOPS-SCHED-001"
    Purpose = "controller-workloads-preferred-scheduling-finops-resilience"
  })
}

# -----------------------------------------------------------------------------
# GAP-FINOPS-SCHED-001 (2026-03-24): CoreDNS — toleration node-type=system:NoSchedule
# Contexto: CoreDNS não estava codificado em staging (apenas em prod). Durante shutdown
#   FinOps, workload nodes escalam para 0. CoreDNS sem toleration ficava Pending nos system
#   nodes (taint node-type=system:NoSchedule) → DNS interno do cluster quebrado → cascata total.
#
# CRÍTICO: resolve_conflicts_on_update=PRESERVE obrigatório para não sobrescrever o ConfigMap
#   coredns-custom (split-horizon DNS) gerenciado em kubernetes_config_map_v1.coredns_split_horizon.
#
# Import antes do primeiro apply:
#   terraform import 'aws_eks_addon.coredns' 'k8s-platform-prod:coredns'
# Verificar versão real no cluster antes:
#   aws eks describe-addon --cluster-name k8s-platform-prod --addon-name coredns \
#     --query 'addon.addonVersion' --output text --profile k8s-platform-prod
# -----------------------------------------------------------------------------
resource "aws_eks_addon" "coredns" {
  cluster_name = local.cluster_name
  addon_name   = "coredns"

  # Versão gerenciada externamente — ignore upgrades automáticos via TF
  addon_version = "v1.11.3-eksbuild.2"

  # GAP-FINOPS-SCHED-001: toleration para system nodes.
  # CoreDNS DEVE rodar em system nodes durante shutdown FinOps (únicos nodes ativos).
  # Sem esta toleration: 0/2 CoreDNS pods → DNS interno offline → cascata total.
  configuration_values = jsonencode({
    tolerations = [
      {
        key      = "node-type"
        operator = "Equal"
        value    = "system"
        effect   = "NoSchedule"
      }
    ]
  })

  # PRESERVE: CRÍTICO — não sobrescrever coredns-custom ConfigMap (split-horizon DNS)
  # gerenciado por kubernetes_config_map_v1.coredns_split_horizon em main.tf
  resolve_conflicts_on_update = "PRESERVE"

  lifecycle {
    ignore_changes = [addon_version]
  }

  tags = merge(local.common_tags, {
    Name    = "coredns-addon-staging"
    GAP     = "GAP-FINOPS-SCHED-001"
    Purpose = "dns-system-node-toleration-finops-resilience"
  })
}
