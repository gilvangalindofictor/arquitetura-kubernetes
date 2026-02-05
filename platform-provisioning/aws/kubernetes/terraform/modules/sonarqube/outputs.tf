output "sonarqube_namespace" {
  description = "SonarQube namespace"
  value       = kubernetes_namespace.sonarqube.metadata[0].name
}

output "sonarqube_url" {
  description = "SonarQube URL (internal)"
  value       = "http://sonarqube-sonarqube.${kubernetes_namespace.sonarqube.metadata[0].name}.svc.cluster.local:9000"
}

output "sonarqube_admin_credentials" {
  description = "Default admin credentials (change after first login)"
  value       = "admin/admin"
  sensitive   = true
}

output "sonarqube_version" {
  description = "SonarQube Helm chart version deployed"
  value       = helm_release.sonarqube.version
}
