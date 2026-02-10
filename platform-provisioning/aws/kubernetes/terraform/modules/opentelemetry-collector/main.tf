# OpenTelemetry Collector Module
# Deploy: Gateway mode (2 replicas) → Tempo + Prometheus + Loki exporters
# Integração FinOps: habilita trace validation para rightsizing decisions

# Data source: Tempo Distributor endpoint (dinâmico, não hardcode)
data "kubernetes_service" "tempo_distributor" {
  metadata {
    name      = "tempo-distributor"
    namespace = "monitoring"
  }
}

# Data source: Prometheus service
data "kubernetes_service" "prometheus" {
  metadata {
    name      = "kube-prometheus-stack-prometheus"
    namespace = "monitoring"
  }
}

# Data source: Loki gateway
data "kubernetes_service" "loki_gateway" {
  metadata {
    name      = "loki-gateway"
    namespace = "monitoring"
  }
}

# Helm release: OpenTelemetry Collector
resource "helm_release" "otel_collector" {
  name       = var.release_name
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.chart_version
  namespace  = var.namespace

  values = [templatefile("${path.module}/values.yaml.tpl", {
    replicas                = var.replicas
    cpu_request             = var.resources.requests.cpu
    memory_request          = var.resources.requests.memory
    cpu_limit               = var.resources.limits.cpu
    memory_limit            = var.resources.limits.memory
    memory_limiter_limit    = var.memory_limiter_limit_mib
    tempo_endpoint          = "${data.kubernetes_service.tempo_distributor.metadata[0].name}.${data.kubernetes_service.tempo_distributor.metadata[0].namespace}.svc.cluster.local:4317"
    prometheus_endpoint     = "http://${data.kubernetes_service.prometheus.metadata[0].name}.${data.kubernetes_service.prometheus.metadata[0].namespace}.svc.cluster.local:9090/api/v1/write"
    loki_endpoint           = "http://${data.kubernetes_service.loki_gateway.metadata[0].name}.${data.kubernetes_service.loki_gateway.metadata[0].namespace}.svc.cluster.local:3100/loki/api/v1/push"
    enable_servicemonitor   = var.enable_servicemonitor
    servicemonitor_interval = var.servicemonitor_interval
  })]
}

# HPA: Horizontal Pod Autoscaler (condição Perf Specialist)
resource "kubernetes_manifest" "otel_hpa" {
  count = var.enable_hpa ? 1 : 0

  manifest = yamldecode(templatefile("${path.module}/hpa.yaml", {
    name               = var.release_name
    namespace          = var.namespace
    min_replicas       = var.hpa_min_replicas
    max_replicas       = var.hpa_max_replicas
    target_cpu_percent = var.hpa_target_cpu_percent
  }))

  depends_on = [helm_release.otel_collector]
}

# PDB: Pod Disruption Budget (condição Perf Specialist)
resource "kubernetes_manifest" "otel_pdb" {
  count = var.enable_pdb ? 1 : 0

  manifest = yamldecode(templatefile("${path.module}/pdb.yaml", {
    name      = var.release_name
    namespace = var.namespace
  }))

  depends_on = [helm_release.otel_collector]
}
