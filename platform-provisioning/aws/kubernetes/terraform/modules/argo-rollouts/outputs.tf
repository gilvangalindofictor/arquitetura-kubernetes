# -----------------------------------------------------------------------------
# Argo Rollouts Module — Outputs
# Demand: CICD-005
# -----------------------------------------------------------------------------

output "release_name" {
  description = "Helm release name for Argo Rollouts"
  value       = helm_release.argo_rollouts.name
}

output "release_status" {
  description = "Helm release status"
  value       = helm_release.argo_rollouts.status
}

output "release_version" {
  description = "Argo Rollouts Helm chart version deployed"
  value       = helm_release.argo_rollouts.version
}

output "namespace" {
  description = "Namespace where Argo Rollouts is deployed"
  value       = helm_release.argo_rollouts.namespace
}

output "prometheus_url" {
  description = "Prometheus URL configured for AnalysisRun queries"
  value       = var.prometheus_url
}

output "dashboard_enabled" {
  description = "Whether Argo Rollouts Dashboard is enabled"
  value       = var.dashboard_enabled
}

output "dashboard_access_command" {
  description = "kubectl port-forward command to access the Rollouts Dashboard"
  value       = "kubectl port-forward svc/argo-rollouts-dashboard ${var.dashboard_port}:${var.dashboard_port} -n ${var.namespace}"
}

output "analysis_templates_deploy_guide" {
  description = "Instructions for deploying AnalysisTemplate library to application namespaces"
  value       = "kubectl apply -f domains/apps/manifests/analysis-templates/ -n <APP_NAMESPACE>"
}
