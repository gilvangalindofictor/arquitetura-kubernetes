# Argo Rollouts Helm Values
# Terraform-managed configuration (CICD-005)
# Chart: argoproj/argo-rollouts ${chart_version}
# Cluster: ${cluster_name}

# ============================================================================
# Controller — Progressive Delivery engine
# ============================================================================
controller:
  replicas: ${controller_replicas}

  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

  metrics:
    enabled: ${metrics_enabled}
    port: ${metrics_port}
    serviceMonitor:
      enabled: false  # ServiceMonitor managed via Terraform kubernetes_manifest

  # Extra args for controller
  extraArgs: []

# ============================================================================
# Dashboard — Read-only UI for Rollout visualization
# Access: kubectl port-forward svc/argo-rollouts-dashboard ${dashboard_port}:${dashboard_port} -n argocd
# ============================================================================
dashboard:
  enabled: ${dashboard_enabled}
  replicas: 1

  service:
    type: ClusterIP
    port: ${dashboard_port}

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule

# ============================================================================
# Notifications — Disabled (handled by ArgoCD notifications)
# ============================================================================
notifications:
  secret:
    create: false

# ============================================================================
# ServiceAccount
# ============================================================================
serviceAccount:
  create: true
  name: argo-rollouts
  annotations: {}

# ============================================================================
# RBAC
# ============================================================================
clusterRoleRules:
  create: true

# ============================================================================
# Prometheus metrics — scraping configuration
# This configures the metrics service; ServiceMonitor managed separately
# ============================================================================
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "${metrics_port}"
  prometheus.io/path: "/metrics"
