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

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = local.cluster_name
  addon_name   = "vpc-cni"

  # Versão gerenciada externamente — ignore upgrades automáticos via TF
  # (upgrades devem ser feitos deliberadamente via console ou CI)
  addon_version = "v1.18.5-eksbuild.1"

  # Preserva EXTERNALSNAT=true após upgrades do addon
  # Sem esta configuração, upgrades do addon resetariam EXTERNALSNAT para false
  configuration_values = jsonencode({
    env = {
      AWS_VPC_K8S_CNI_EXTERNALSNAT = "true"
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
