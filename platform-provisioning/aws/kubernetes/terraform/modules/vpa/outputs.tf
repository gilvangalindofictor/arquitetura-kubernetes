# -----------------------------------------------------------------------------
# VPA Module Outputs
# -----------------------------------------------------------------------------

output "release_name" {
  description = "VPA Helm release name"
  value       = helm_release.vpa.name
}

output "namespace" {
  description = "VPA namespace"
  value       = helm_release.vpa.namespace
}

output "chart_version" {
  description = "Deployed VPA chart version"
  value       = helm_release.vpa.version
}

output "status" {
  description = "VPA Helm release status"
  value       = helm_release.vpa.status
}
