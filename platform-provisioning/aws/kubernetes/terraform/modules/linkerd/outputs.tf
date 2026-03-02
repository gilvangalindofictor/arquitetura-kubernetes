# -----------------------------------------------------------------------------
# Linkerd Module - Outputs
# GAP-011: mTLS End-to-End | BACEN BCB 85/2021 Compliance
# -----------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Core Namespace
#------------------------------------------------------------------------------

output "linkerd_namespace" {
  description = "Kubernetes namespace where the Linkerd control plane is deployed."
  value       = kubernetes_namespace.linkerd.metadata[0].name
}

#------------------------------------------------------------------------------
# Viz Extension
#------------------------------------------------------------------------------

output "linkerd_viz_namespace" {
  description = "Kubernetes namespace for the Linkerd Viz extension. Empty string when enable_viz=false."
  value       = var.enable_viz ? kubernetes_namespace.linkerd_viz[0].metadata[0].name : ""
}

output "linkerd_viz_url" {
  description = <<-EOT
    Internal cluster URL for the Linkerd dashboard (linkerd-web service).
    Access via: kubectl port-forward -n linkerd-viz svc/web 8084:8084
    Then open:  http://localhost:8084
  EOT
  value       = var.enable_viz ? "http://web.${var.viz_namespace}.svc.cluster.local:8084" : ""
}

output "linkerd_tap_api_url" {
  description = "Internal cluster URL for the Linkerd Tap API (real-time L7 traffic inspection)."
  value       = var.enable_viz ? "https://tap.${var.viz_namespace}.svc.cluster.local:8088" : ""
}

#------------------------------------------------------------------------------
# Proxy Injector Webhook
#------------------------------------------------------------------------------

output "linkerd_proxy_injector_webhook_url" {
  description = "Internal URL of the Linkerd proxy-injector MutatingWebhookConfiguration endpoint."
  value       = "https://linkerd-proxy-injector.${local.linkerd_namespace}.svc.cluster.local:443"
}

#------------------------------------------------------------------------------
# PKI — Trust Anchor Certificate
#------------------------------------------------------------------------------

output "trust_anchor_certificate" {
  description = <<-EOT
    PEM-encoded trust anchor (root CA) certificate.
    SENSITIVE: used by all Linkerd proxies as the SPIFFE root of trust.
    Store this in Vault (secret/linkerd/pki) immediately after apply.
  EOT
  value       = tls_self_signed_cert.trust_anchor.cert_pem
  sensitive   = true
}

output "trust_anchor_certificate_expiry" {
  description = "RFC 3339 timestamp when the trust anchor certificate expires. Schedule rotation before this date."
  value       = tls_self_signed_cert.trust_anchor.validity_period_hours
}

output "issuer_certificate" {
  description = "PEM-encoded intermediate issuer certificate (signed by the trust anchor). SENSITIVE."
  value       = tls_locally_signed_cert.issuer.cert_pem
  sensitive   = true
}

#------------------------------------------------------------------------------
# Helm Release Metadata
#------------------------------------------------------------------------------

output "linkerd_control_plane_version" {
  description = "Deployed Linkerd control-plane Helm chart version."
  value       = helm_release.linkerd_control_plane.version
}

output "linkerd_viz_version" {
  description = "Deployed Linkerd Viz Helm chart version. Empty string when enable_viz=false."
  value       = var.enable_viz ? helm_release.linkerd_viz[0].version : ""
}

output "linkerd_jaeger_version" {
  description = "Deployed Linkerd Jaeger Helm chart version. Empty string when enable_jaeger=false."
  value       = var.enable_jaeger ? helm_release.linkerd_jaeger[0].version : ""
}

#------------------------------------------------------------------------------
# Injected Namespaces
#------------------------------------------------------------------------------

output "proxy_injected_namespaces" {
  description = "List of namespaces annotated for automatic Linkerd proxy injection."
  value       = var.proxy_inject_namespaces
}
