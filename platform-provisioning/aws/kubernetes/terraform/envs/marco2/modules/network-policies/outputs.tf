# =============================================================================
# OUTPUTS - Network Policies Module
# =============================================================================

output "policies_applied" {
  description = "List of network policies applied"
  value = [
    for k, v in local.enabled_policies : k
  ]
}

output "namespaces_with_policies" {
  description = "Namespaces where policies were applied"
  value       = var.namespaces
}

output "default_deny_enabled" {
  description = "Whether default deny-all policy is enabled"
  value       = var.enable_default_deny
}

output "calico_version" {
  description = "Calico version used (for reference)"
  value       = "v3.27.0 (policy-only mode)"
}
