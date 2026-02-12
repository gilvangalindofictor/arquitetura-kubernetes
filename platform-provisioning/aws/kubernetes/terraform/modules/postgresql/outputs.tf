output "rds_endpoint" {
  description = "PostgreSQL RDS endpoint (with port)"
  value       = aws_db_instance.postgresql.endpoint
}

output "rds_address" {
  description = "PostgreSQL RDS address (without port)"
  value       = aws_db_instance.postgresql.address
}

output "rds_port" {
  description = "PostgreSQL RDS port"
  value       = aws_db_instance.postgresql.port
}

output "rds_database_name" {
  description = "PostgreSQL default database name"
  value       = aws_db_instance.postgresql.db_name
}

output "rds_username" {
  description = "PostgreSQL master username"
  value       = aws_db_instance.postgresql.username
  sensitive   = true
}

output "master_password_secret_arn" {
  description = "ARN of the secret containing master password"
  value       = aws_secretsmanager_secret.master_password.arn
}

output "master_password_secret_name" {
  description = "Name of the secret containing master password"
  value       = aws_secretsmanager_secret.master_password.name
}

# TODO: Commented temporarily (resource commented)
# output "service_name" {
#   description = "Kubernetes Service name for PostgreSQL (ExternalName type)"
#   value       = kubernetes_service.postgresql_external.metadata[0].name
# }

# TODO: Commented temporarily (resource commented)
# output "service_internal_dns" {
#   description = "Internal Kubernetes DNS name for PostgreSQL"
#   value       = "${kubernetes_service.postgresql_external.metadata[0].name}.${kubernetes_service.postgresql_external.metadata[0].namespace}.svc.cluster.local:5432"
# }

output "security_group_id" {
  description = "Security group ID for PostgreSQL RDS"
  value       = aws_security_group.postgresql.id
}

output "db_instance_id" {
  description = "RDS instance identifier (DBInstanceIdentifier for API calls)"
  value       = aws_db_instance.postgresql.identifier
}

output "additional_databases" {
  description = "List of additional databases created"
  value       = [for db in var.additional_databases : db.name]
}

# -----------------------------------------------------------------------------
# Application Database Credentials
# -----------------------------------------------------------------------------

output "gitlab_user_password" {
  description = "GitLab user password"
  value       = random_password.gitlab_user.result
  sensitive   = true
}

output "gitlab_database_name" {
  description = "GitLab database name"
  value       = postgresql_database.gitlab.name
}

output "gitlab_username" {
  description = "GitLab username"
  value       = postgresql_role.gitlab_user.name
}

output "keycloak_user_password" {
  description = "Keycloak user password"
  value       = random_password.keycloak_user.result
  sensitive   = true
}

output "keycloak_database_name" {
  description = "Keycloak database name"
  value       = postgresql_database.keycloak.name
}

output "keycloak_username" {
  description = "Keycloak username"
  value       = postgresql_role.keycloak_user.name
}

output "sonarqube_user_password" {
  description = "SonarQube user password"
  value       = random_password.sonarqube_user.result
  sensitive   = true
}

output "sonarqube_database_name" {
  description = "SonarQube database name"
  value       = postgresql_database.sonarqube.name
}

output "sonarqube_username" {
  description = "SonarQube username"
  value       = postgresql_role.sonarqube_user.name
}
