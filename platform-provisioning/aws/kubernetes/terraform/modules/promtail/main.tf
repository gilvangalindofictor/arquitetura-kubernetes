# -----------------------------------------------------------------------------
# Promtail Module
# Descricao: DaemonSet logging agent que coleta logs dos nodes e envia para Loki
# Chart: grafana/promtail v6.16.6 (Promtail 3.0.0)
# Sem IRSA: Promtail nao acessa AWS diretamente
# Toleracoes: system + workload nodes (exceto database:NoSchedule)
# ADR-048: Corporate labels em todos os pods
# -----------------------------------------------------------------------------

resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = var.chart_version
  namespace  = var.namespace

  # ---------------------------------------------------------------------------
  # Values via templatefile para match exato com helm get values (zero drift)
  # O arquivo values.yaml.tpl usa as variaveis do modulo para gerar o YAML
  # ---------------------------------------------------------------------------
  values = [templatefile("${path.module}/values.yaml.tpl", {
    loki_url             = var.loki_url
    loki_tenant_id       = var.loki_tenant_id
    extra_scrape_configs = var.extra_scrape_configs
    resources_requests_cpu    = var.resources_requests_cpu
    resources_requests_memory = var.resources_requests_memory
    resources_limits_cpu      = var.resources_limits_cpu
    resources_limits_memory   = var.resources_limits_memory
    enable_service_monitor    = var.enable_service_monitor
    service_monitor_namespace = var.namespace
    service_monitor_labels    = var.service_monitor_labels
    domain      = var.domain
    owner       = var.owner
    environment = var.environment
  })]

  # ---------------------------------------------------------------------------
  # Timeout generoso para DaemonSet rollout em todos os nodes
  # ---------------------------------------------------------------------------
  timeout = 300 # 5 minutes

  # Nao recriar se apenas metadata mudar (evita disrupcao dos pods)
  recreate_pods = false

  # ---------------------------------------------------------------------------
  # Lifecycle: ignorar campos que nao sao capturados no import do helm_release
  # - metadata: computed pelo Helm (revision, timestamps, notes) - nao modificavel
  # - values: o import nao captura os values do release existente no state
  # - repository: o import nao captura a URL do repositorio no state
  # Pos-import estes campos aparecem como +add mas sao identicos ao deployado
  # Na proxima mudanca real (chart_version, etc.) o ignore e removido
  # ---------------------------------------------------------------------------
  lifecycle {
    ignore_changes = [metadata, values, repository]
  }
}
