# EKS Managed Addons — Staging
# ADR-063: AWS_VPC_K8S_CNI_EXTERNALSNAT=true (2026-02-19)
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
