output "iam_role_arn" {
  description = "ARN of the IRSA IAM role used by the CronJob ServiceAccount"
  value       = aws_iam_role.finops_cost_exporter.arn
}

output "iam_role_name" {
  description = "Name of the IRSA IAM role"
  value       = aws_iam_role.finops_cost_exporter.name
}

output "service_account_name" {
  description = "Name of the Kubernetes ServiceAccount annotated with IRSA"
  value       = kubernetes_service_account.finops_cost_exporter.metadata[0].name
}

output "cronjob_name" {
  description = "Name of the Kubernetes CronJob"
  value       = kubernetes_cron_job_v1.finops_cost_exporter.metadata[0].name
}

output "cronjob_namespace" {
  description = "Namespace where the CronJob runs"
  value       = kubernetes_cron_job_v1.finops_cost_exporter.metadata[0].namespace
}
