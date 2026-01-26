# -----------------------------------------------------------------------------
# Outputs - Loki Module
# -----------------------------------------------------------------------------

output "s3_bucket_name" {
  description = "Nome do S3 bucket criado para Loki"
  value       = aws_s3_bucket.loki.id
}

output "s3_bucket_arn" {
  description = "ARN do S3 bucket criado para Loki"
  value       = aws_s3_bucket.loki.arn
}

output "iam_role_arn" {
  description = "ARN da IAM Role criada para o Loki (IRSA)"
  value       = aws_iam_role.loki.arn
}

output "iam_role_name" {
  description = "Nome da IAM Role criada para o Loki"
  value       = aws_iam_role.loki.name
}

output "iam_policy_arn" {
  description = "ARN da IAM Policy criada para acesso S3"
  value       = aws_iam_policy.loki_s3.arn
}

output "service_account_name" {
  description = "Nome da Service Account Kubernetes"
  value       = kubernetes_service_account.loki.metadata[0].name
}

output "namespace" {
  description = "Namespace onde o Loki foi instalado"
  value       = var.namespace
}

output "helm_release_name" {
  description = "Nome do Helm release"
  value       = helm_release.loki.name
}

output "helm_release_version" {
  description = "Versão do Helm chart instalado"
  value       = helm_release.loki.version
}

output "loki_gateway_endpoint" {
  description = "Endpoint do Loki Gateway (para Fluent Bit e Grafana)"
  value       = "http://loki-gateway.${var.namespace}:3100"
}

output "loki_push_endpoint" {
  description = "Endpoint para push de logs"
  value       = "http://loki-gateway.${var.namespace}:3100/loki/api/v1/push"
}

output "loki_query_endpoint" {
  description = "Endpoint para query de logs"
  value       = "http://loki-gateway.${var.namespace}:3100/loki/api/v1/query"
}
