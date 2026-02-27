################################################################################
# Module: secret-rotation — Outputs
# CICD-003: Automated Secret Rotation
################################################################################

output "service_account_name" {
  description = "ServiceAccount name for the secret rotator"
  value       = kubernetes_service_account_v1.secret_rotator.metadata[0].name
}

output "cronjob_name" {
  description = "CronJob name for manual trigger reference"
  value       = kubernetes_cron_job_v1.secret_rotator.metadata[0].name
}

output "namespace" {
  description = "Namespace where secret rotator runs"
  value       = kubernetes_cron_job_v1.secret_rotator.metadata[0].namespace
}

output "schedule" {
  description = "CronJob schedule expression"
  value       = kubernetes_cron_job_v1.secret_rotator.spec[0].schedule
}

output "manual_trigger_command" {
  description = "Command to trigger rotation manually"
  value       = "kubectl create job --from=cronjob/${kubernetes_cron_job_v1.secret_rotator.metadata[0].name} secret-rotator-manual-$(date +%Y%m%d) -n ${kubernetes_cron_job_v1.secret_rotator.metadata[0].namespace}"
}
