# =============================================================================
# Velero Helm Release — Staging
# Imported: 2026-03-05 | helm rev 11 | chart velero-8.1.0 | Velero v1.15.0
#
# Separation of concerns:
#   - module.velero_dr_staging  → S3 bucket + IAM/IRSA role (velero-dr module)
#   - module.velero_helm_staging → helm_release only (this file)
#
# IRSA role ARN:  module.velero_dr_staging.velero_role_arn
# S3 bucket name: module.velero_dr_staging.bucket_name
# =============================================================================

module "velero_helm_staging" {
  source = "../../modules/velero-helm"

  cluster_name   = local.cluster_name
  namespace      = "velero"
  chart_version  = "8.1.0"
  irsa_role_arn  = module.velero_dr_staging.velero_role_arn
  s3_bucket_name = module.velero_dr_staging.bucket_name
  s3_region      = "us-east-1"

  # Velero server placement: applications node group, tolerate platform taint
  node_selector = {
    workload = "applications"
  }

  tolerations = [
    {
      key      = "workload"
      operator = "Equal"
      value    = "platform"
      effect   = "NoSchedule"
    }
  ]

  # Plugin version matching Velero v1.15.0
  velero_plugin_aws_version = "v1.11.0"

  # Observability
  metrics_enabled         = true
  service_monitor_enabled = true
  service_monitor_labels = {
    release = "kube-prometheus-stack"
  }

  # Node agent for file-system (restic/kopia) backups
  deploy_node_agent = true

  # CSI snapshot support
  enable_csi = true

  # Retain backups 30 days (720h) by default
  backup_retention_period = "720h"

  depends_on = [module.velero_dr_staging]
}
