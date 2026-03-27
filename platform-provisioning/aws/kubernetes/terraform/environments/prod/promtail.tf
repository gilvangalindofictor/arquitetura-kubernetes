# -----------------------------------------------------------------------------
# Promtail - DaemonSet logging agent (PROD)
# GAP-HEALTH-006 (2026-03-26): Production has zero promtail pods.
# Loki prod is running in prod-observability-monitoring but has no log source.
# This module deploys promtail as a DaemonSet to all prod nodes, shipping logs
# to the Loki gateway in prod-observability-monitoring.
#
# Adapted from environments/staging/promtail.tf
# Differences from staging:
#   - Namespace: prod-observability-monitoring (not staging-*)
#   - Loki URL: loki-gateway.prod-observability-monitoring
#   - Environment label: prod
#   - ECR registry: hardcoded (prod has no ecr_pull_through_cache module yet)
#   - Extra scrape configs: all namespaces (no namespace filter)
# -----------------------------------------------------------------------------

module "promtail_prod" {
  source = "../../modules/promtail"

  cluster_name  = local.cluster_name
  release_name  = "promtail-prod"  # Unique name to avoid ClusterRole conflict with staging promtail
  namespace     = "prod-observability-monitoring"
  chart_version = "6.16.6"
  loki_url      = "http://loki-gateway.prod-observability-monitoring.svc.cluster.local"
  loki_tenant_id = ""

  # Resources — same as staging (CPU 10m proven stable across 14 nodes)
  resources_requests_cpu    = "10m"
  resources_requests_memory = "64Mi"
  resources_limits_cpu      = "200m"
  resources_limits_memory   = "128Mi"

  # ServiceMonitor — integration with kube-prometheus-stack
  enable_service_monitor = true
  service_monitor_labels = {
    release = "kube-prometheus-stack"
  }

  # Extra scrape configs — production: all namespaces (no filter)
  extra_scrape_configs = <<-EOT
    - job_name: kubernetes-pods-name
      kubernetes_sd_configs:
        - role: pod
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
  environment = "prod"

  # ECR Pull-Through Cache
  # NOTE: prod environment does not have module.ecr_pull_through_cache yet.
  # When the ECR module is added to prod/main.tf, replace this hardcoded value
  # with module.ecr_pull_through_cache.ecr_registry_prefix
  ecr_registry = "891377105802.dkr.ecr.us-east-1.amazonaws.com"
}
