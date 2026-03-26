# EKS Managed Addons — Prod
# GAP-PROD-ADDONS-001 (2026-03-23): Addons prod não eram TF-managed. Este arquivo codifica
#   o estado existente no cluster para capturar upgrades e evitar drift de configuração.
# GAP-FINOPS-SCHED-001 (2026-03-24): coredns + ebs-csi toleration node-type=system:NoSchedule
#   Contexto: durante shutdown FinOps, workload nodes escalam para 0; apenas system nodes ficam ativos.
#   CoreDNS e ebs-csi-controller ficavam Pending por ausência de toleration → DNS quebrado + EBS offline.
#   ebs-csi-controller: nodeSelector hard convertido para nodeAffinity preferred (mesma intenção do
#   GAP-SCHED-003, mas sem bloquear reagendamento nos system nodes durante shutdown).
#
# ADR-063: AWS_VPC_K8S_CNI_EXTERNALSNAT=true (aplicado em staging 2026-02-19, replicado prod)
# GAP-SCHED-003 (2026-03-23): ebs-csi-controller nodeSelector→workloads
#
# IMPORTANTE: Estes recursos JÁ EXISTEM no cluster prod. Antes do primeiro `terraform apply`,
# importar os addons existentes para o state:
#
#   terraform import 'aws_eks_addon.vpc_cni' 'k8s-platform-prod:vpc-cni'
#   terraform import 'aws_eks_addon.ebs_csi_driver' 'k8s-platform-prod:aws-ebs-csi-driver'
#   terraform import 'aws_eks_addon.kube_proxy' 'k8s-platform-prod:kube-proxy'
#   terraform import 'aws_eks_addon.coredns' 'k8s-platform-prod:coredns'
#
# Após o import, rodar `terraform plan` para verificar drift. Ajustar addon_version e
# configuration_values conforme o estado real antes de aplicar.

# -----------------------------------------------------------------------------
# VPC CNI
# -----------------------------------------------------------------------------
# ADR-063: EXTERNALSNAT=true → pods usam SNAT via IP primário do node (fix S3 Gateway Endpoint)
# ENABLE_PREFIX_DELEGATION=true: /28 IPv4 prefixes por ENI → mais pods por node
#   t3.large: 3 ENIs × 16 IPs (/28 prefix) = 48 pods por ENI
# WARM_PREFIX_TARGET=1: 1 prefix pré-alocado → sem latência no scale-up
#
# NOTA: addon_version abaixo é a mesma usada em staging (2026-03-23). Verificar versão
#   real no cluster antes do import:
#   aws eks describe-addon --cluster-name k8s-platform-prod --addon-name vpc-cni \
#     --query 'addon.addonVersion' --output text
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

  # PRESERVE: não sobrescrever mudanças manuais existentes em prod (graceful)
  resolve_conflicts_on_update = "PRESERVE"

  lifecycle {
    # Permite upgrade da versão sem recriar (via console ou CI)
    ignore_changes = [addon_version]
  }

  tags = merge(local.common_tags, {
    Name    = "vpc-cni-addon-prod"
    ADR     = "ADR-063"
    Purpose = "S3-Gateway-Endpoint-EXTERNALSNAT-fix"
    GAP     = "GAP-PROD-ADDONS-001"
  })
}

# -----------------------------------------------------------------------------
# EBS CSI Driver
# -----------------------------------------------------------------------------
# GAP-SCHED-003 (2026-03-23): ebs-csi-controller → workloads nodes
# Contexto: controller com nodeSelector genérico {kubernetes.io/os: linux} pode escalar
#   para system nodes (t3.medium), consumindo slots preciosos.
# Fix: nodeSelector eks.amazonaws.com/nodegroup=workloads força controller
#   para nodes de workload (t3.large/xlarge). DaemonSet ebs-csi-node NÃO afetado.
#
# IAM Role: AmazonEKS_EBS_CSI_DriverRole-k8s-platform-prod (pré-existente, mesma conta)
# NOTA: addon_version abaixo é a mesma usada em staging (2026-03-23). Verificar versão
#   real no cluster antes do import:
#   aws eks describe-addon --cluster-name k8s-platform-prod --addon-name aws-ebs-csi-driver \
#     --query 'addon.addonVersion' --output text
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = local.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  # Versão gerenciada externamente — ignore upgrades automáticos via TF
  addon_version = "v1.37.0-eksbuild.1"

  # IRSA: role pré-existente criada via console para o EBS CSI Driver
  # Necessário para UpdateAddon não rejeitar com "Cross-account pass role error"
  service_account_role_arn = "arn:aws:iam::891377105802:role/AmazonEKS_EBS_CSI_DriverRole-k8s-platform-prod"

  # GAP-SCHED-003 (mantido): controller prefere workloads nodes via nodeAffinity preferred.
  #   Convertido de hard nodeSelector para preferredDuringSchedulingIgnoredDuringExecution
  #   para que durante o shutdown FinOps (workload nodes = 0) o controller possa reagendar
  #   nos system nodes. Com hard nodeSelector o pod ficaria Pending mesmo com toleration.
  #
  # GAP-FINOPS-SCHED-001: toleration node-type=system:NoSchedule adicionada.
  #   O DaemonSet ebs-csi-node NÃO é afetado por este configurationValues.
  configuration_values = jsonencode({
    controller = {
      # Preferência soft por workloads nodes (GAP-SCHED-003 intent preservado)
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

  # PRESERVE: não sobrescrever mudanças manuais existentes em prod (graceful)
  resolve_conflicts_on_update = "PRESERVE"

  lifecycle {
    ignore_changes = [addon_version]
  }

  tags = merge(local.common_tags, {
    Name    = "ebs-csi-driver-addon-prod"
    GAP     = "GAP-SCHED-003 GAP-PROD-ADDONS-001 GAP-FINOPS-SCHED-001"
    Purpose = "controller-workloads-preferred-scheduling-finops-resilience"
  })
}

# -----------------------------------------------------------------------------
# kube-proxy
# -----------------------------------------------------------------------------
# Addon gerenciado pelo EKS. Codificado aqui para capturar upgrades e evitar drift.
# configurationValues vazio = usar defaults do EKS (sem customização necessária).
#
# NOTA: addon_version — verificar versão real no cluster antes do import:
#   aws eks describe-addon --cluster-name k8s-platform-prod --addon-name kube-proxy \
#     --query 'addon.addonVersion' --output text
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = local.cluster_name
  addon_name   = "kube-proxy"

  # Versão compatível com EKS 1.34 — verificar versão real no cluster antes do import
  # (ver instrução de import acima)
  addon_version = "v1.34.3-eksbuild.2"

  # PRESERVE: não sobrescrever mudanças manuais existentes em prod
  resolve_conflicts_on_update = "PRESERVE"

  lifecycle {
    ignore_changes = [addon_version]
  }

  tags = merge(local.common_tags, {
    Name    = "kube-proxy-addon-prod"
    GAP     = "GAP-PROD-ADDONS-001"
    Purpose = "cluster-networking-kube-proxy"
  })
}

# -----------------------------------------------------------------------------
# CoreDNS
# -----------------------------------------------------------------------------
# Addon gerenciado pelo EKS. Codificado aqui para capturar upgrades e evitar drift.
#
# NOTA: prod usa coredns-custom ConfigMap para split-horizon DNS (ver main.tf —
#   kubernetes_config_map_v1.coredns_split_horizon). Este addon NÃO sobrescreve
#   o ConfigMap customizado graças a resolve_conflicts_on_update = "PRESERVE".
#
# NOTA: addon_version — verificar versão real no cluster antes do import:
#   aws eks describe-addon --cluster-name k8s-platform-prod --addon-name coredns \
#     --query 'addon.addonVersion' --output text
resource "aws_eks_addon" "coredns" {
  cluster_name = local.cluster_name
  addon_name   = "coredns"

  # Versão compatível com EKS 1.34 — verificar versão real no cluster antes do import
  # (ver instrução de import acima)
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

  # PRESERVE: CRÍTICO — não sobrescrever coredns-custom ConfigMap e configurações
  #   de split-horizon DNS existentes em prod
  resolve_conflicts_on_update = "PRESERVE"

  lifecycle {
    ignore_changes = [addon_version]
  }

  tags = merge(local.common_tags, {
    Name    = "coredns-addon-prod"
    GAP     = "GAP-PROD-ADDONS-001 GAP-FINOPS-SCHED-001"
    Purpose = "cluster-dns-coredns-finops-resilience"
  })
}
