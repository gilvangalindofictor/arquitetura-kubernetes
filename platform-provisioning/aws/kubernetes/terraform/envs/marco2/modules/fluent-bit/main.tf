# -----------------------------------------------------------------------------
# Fluent Bit Module
# Descrição: Coletor de logs leve (DaemonSet) com output para Loki
# Versão Chart: v0.43.0
# Marco: 2 - Fase 4 (Logging)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Helm Release - Fluent Bit
# -----------------------------------------------------------------------------

resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = var.chart_version
  namespace  = var.namespace

  # Use values file instead of individual set blocks
  values = [
    templatefile("${path.module}/values.yaml.tftpl", {
      image_tag                = var.image_tag
      service_account_name     = var.service_account_name
      cluster_name             = var.cluster_name
      loki_host                = var.loki_host
      loki_port                = var.loki_port
      exclude_namespaces       = join(",", var.exclude_namespaces)
      exclude_namespaces_regex = join("|", var.exclude_namespaces)
    })
  ]
}
