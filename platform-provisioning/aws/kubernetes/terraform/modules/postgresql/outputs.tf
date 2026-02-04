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

output "service_name" {
  description = "Kubernetes Service name for PostgreSQL (ExternalName type)"
  value       = kubernetes_service.postgresql_external.metadata[0].name
}

output "service_internal_dns" {
  description = "Internal Kubernetes DNS name for PostgreSQL"
  value       = "${kubernetes_service.postgresql_external.metadata[0].name}.${kubernetes_service.postgresql_external.metadata[0].namespace}.svc.cluster.local:5432"
}

output "security_group_id" {
  description = "Security group ID for PostgreSQL RDS"
  value       = aws_security_group.postgresql.id
}

output "db_instance_id" {
  description = "RDS instance identifier (DBInstanceIdentifier for API calls)"
  value       = aws_db_instance.postgresql.identifier
}
