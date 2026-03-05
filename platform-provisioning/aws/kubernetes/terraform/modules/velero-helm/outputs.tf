# =============================================================================
# Velero Helm Release Module — Outputs
# =============================================================================

output "release_name" {
  description = "Name of the Velero Helm release"
  value       = helm_release.velero.name
}

output "namespace" {
  description = "Kubernetes namespace where Velero is deployed"
  value       = helm_release.velero.namespace
}

output "chart_version" {
  description = "Deployed Velero chart version"
  value       = helm_release.velero.version
}

output "status" {
  description = "Helm release status (deployed, pending-upgrade, etc.)"
  value       = helm_release.velero.status
}

output "revision" {
  description = "Helm release revision number"
  value       = helm_release.velero.metadata[0].revision
}
