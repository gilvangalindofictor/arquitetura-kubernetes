# VPA Module Usage Example - Staging Environment
# Replace helm_release "vpa" inline resource with this module call

module "vpa_staging" {
  source = "../../modules/vpa"

  # Chart configuration
  release_name  = "vpa"
  chart_version = "4.4.6"
  namespace     = "kube-system"

  # Components (recommendation mode only)
  recommender_enabled          = true
  updater_enabled              = false  # CRITICAL: Never enable in staging without approval
  admission_controller_enabled = false  # CRITICAL: Never enable in staging without approval

  # Prometheus integration
  prometheus_address = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"

  # Tags
  common_tags = {
    Environment        = "staging"
    DataClassification = "Internal"
    CostCenter         = "finops"
    Purpose            = "rightsizing-recommendations"
  }
}

# VPA Objects remain as kubectl_manifest resources (not part of module)
# See staging/main.tf lines 1564-1922 for 12 VPA object definitions
