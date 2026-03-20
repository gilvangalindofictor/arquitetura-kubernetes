# -----------------------------------------------------------------------------
# Promtail - DaemonSet logging agent
# Namespace: staging-observability-monitoring
# Chart: grafana/promtail 6.16.6 (Promtail 3.0.0)
# Importado em 2026-03-05 via:
#   terraform import module.promtail_staging.helm_release.promtail \
#     staging-observability-monitoring/promtail
# Rev 8 — helm release existente capturado com `helm get values`
# -----------------------------------------------------------------------------

module "promtail_staging" {
  source = "../../modules/promtail"

  cluster_name  = local.cluster_name
  namespace     = "staging-observability-monitoring"
  chart_version = "6.16.6"
  loki_url      = "http://loki-gateway.staging-observability-monitoring.svc.cluster.local"
  loki_tenant_id = ""

  # Resources capturados do helm release atual (rev 8)
  resources_requests_cpu    = "50m"
  resources_requests_memory = "64Mi"
  resources_limits_cpu      = "200m"
  resources_limits_memory   = "128Mi"

  # ServiceMonitor — integracao com kube-prometheus-stack
  enable_service_monitor = true
  service_monitor_labels = {
    release = "kube-prometheus-stack"
  }

  # Extra scrape configs capturados do helm release atual
  extra_scrape_configs = <<-EOT
    - job_name: kubernetes-pods-name
      kubernetes_sd_configs:
        - role: pod
          namespaces:
            names:
              - tracing-test
              - staging-observability-monitoring
      pipeline_stages:
        - cri: {}
      relabel_configs:
        - source_labels:
            - __meta_kubernetes_pod_label_app
          target_label: app
        - source_labels:
            - __meta_kubernetes_pod_node_name
          target_label: node_name
        - source_labels:
            - __meta_kubernetes_namespace
          target_label: namespace
        - source_labels:
            - __meta_kubernetes_pod_name
          target_label: pod
        - source_labels:
            - __meta_kubernetes_pod_container_name
          target_label: container
        - replacement: /var/log/pods/*$1/*.log
          separator: /
          source_labels:
            - __meta_kubernetes_pod_uid
            - __meta_kubernetes_pod_container_name
          target_label: __path__
  EOT

  # Corporate Labels (ADR-048)
  domain      = "platform"
  owner       = "platform-team"
  environment = "staging"

  # ECR Pull-Through Cache (GAP-SEC-REGISTRY-03)
  ecr_registry = module.ecr_pull_through_cache.ecr_registry_prefix
}
