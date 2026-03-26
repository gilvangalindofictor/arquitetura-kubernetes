# -----------------------------------------------------------------------------
# Linkerd mTLS Phase 2 Module - Outputs
# Fase 6a: ServerPolicy enforcement for mTLS across namespaces
# GAP-011 Phase 2: BACEN BCB 85/2021 Compliance
# -----------------------------------------------------------------------------

output "enforced_namespaces" {
  description = "List of namespaces where mTLS ServerPolicy is enforced"
  value       = var.mtls_namespaces
}

output "default_policy" {
  description = "Default inbound policy applied to Server resources"
  value       = var.default_policy
}

output "admin_bypass_enabled" {
  description = "Whether admin/health port bypass is enabled for probes"
  value       = var.allow_admin_server_access
}
