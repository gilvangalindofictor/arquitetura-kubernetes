output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_server_url" {
  description = "ArgoCD server URL (internal)"
  value       = "http://argocd-server.${kubernetes_namespace.argocd.metadata[0].name}.svc.cluster.local"
}

output "argocd_admin_password_secret" {
  description = "Secret name containing ArgoCD admin password"
  value       = "argocd-initial-admin-secret"
  sensitive   = true
}

output "argocd_version" {
  description = "ArgoCD Helm chart version deployed"
  value       = helm_release.argocd.version
}
