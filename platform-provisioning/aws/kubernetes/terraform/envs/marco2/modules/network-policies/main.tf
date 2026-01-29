# =============================================================================
# NETWORK POLICIES MODULE - Main Configuration
# =============================================================================
# Aplica Network Policies usando Terraform kubernetes_manifest
# Ordem: Allow policies primeiro, Default Deny por último
# =============================================================================

locals {
  # Policy files to apply
  policy_files = {
    # Basic policies (apply first)
    "allow-dns"        = var.enable_dns_policy ? "${path.module}/policies/allow-dns.yaml" : null
    "allow-api-server" = var.enable_api_server_policy ? "${path.module}/policies/allow-api-server.yaml" : null

    # Monitoring specific policies
    "allow-prometheus-scraping" = var.enable_prometheus_scraping ? "${path.module}/policies/allow-prometheus-scraping.yaml" : null
    "allow-fluent-bit-to-loki"  = var.enable_loki_ingestion ? "${path.module}/policies/allow-fluent-bit-to-loki.yaml" : null
    "allow-grafana-datasources" = var.enable_grafana_datasources ? "${path.module}/policies/allow-grafana-datasources.yaml" : null
    "allow-monitoring-ingress"  = var.enable_prometheus_scraping ? "${path.module}/policies/allow-monitoring-ingress.yaml" : null

    # Cert-Manager egress
    "allow-cert-manager-egress" = var.enable_cert_manager_egress ? "${path.module}/policies/allow-cert-manager-egress.yaml" : null

    # Default deny (apply last)
    "default-deny-all" = var.enable_default_deny ? "${path.module}/policies/default-deny-all.yaml" : null
  }

  # Filter out null values (disabled policies)
  enabled_policies = { for k, v in local.policy_files : k => v if v != null }
}

# =============================================================================
# APPLY DNS ALLOW POLICY (Per Namespace)
# =============================================================================
resource "kubernetes_manifest" "allow_dns" {
  for_each = var.enable_dns_policy ? toset(var.namespaces) : []

  manifest = yamldecode(templatefile("${path.module}/policies/allow-dns.yaml", {
    namespace = each.value
  }))

  field_manager {
    name            = "terraform-network-policies"
    force_conflicts = true
  }
}

# =============================================================================
# APPLY API SERVER ALLOW POLICY (Per Namespace)
# =============================================================================
resource "kubernetes_manifest" "allow_api_server" {
  for_each = var.enable_api_server_policy ? toset(var.namespaces) : []

  manifest = yamldecode(templatefile("${path.module}/policies/allow-api-server.yaml", {
    namespace = each.value
  }))

  field_manager {
    name            = "terraform-network-policies"
    force_conflicts = true
  }

  depends_on = [kubernetes_manifest.allow_dns]
}

# =============================================================================
# APPLY PROMETHEUS SCRAPING POLICY (Monitoring Namespace)
# =============================================================================
resource "kubernetes_manifest" "allow_prometheus_scraping" {
  count = var.enable_prometheus_scraping ? 1 : 0

  manifest = yamldecode(file("${path.module}/policies/allow-prometheus-scraping.yaml"))

  field_manager {
    name            = "terraform-network-policies"
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.allow_dns,
    kubernetes_manifest.allow_api_server
  ]
}

# =============================================================================
# APPLY FLUENT BIT TO LOKI POLICY (Monitoring Namespace)
# =============================================================================
resource "kubernetes_manifest" "allow_fluent_bit_to_loki" {
  count = var.enable_loki_ingestion ? 1 : 0

  manifest = yamldecode(file("${path.module}/policies/allow-fluent-bit-to-loki.yaml"))

  field_manager {
    name            = "terraform-network-policies"
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.allow_dns,
    kubernetes_manifest.allow_api_server
  ]
}

# =============================================================================
# APPLY GRAFANA TO DATASOURCES POLICY (Monitoring Namespace)
# =============================================================================
resource "kubernetes_manifest" "allow_grafana_datasources" {
  count = var.enable_grafana_datasources ? 1 : 0

  manifest = yamldecode(file("${path.module}/policies/allow-grafana-datasources.yaml"))

  field_manager {
    name            = "terraform-network-policies"
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.allow_dns,
    kubernetes_manifest.allow_api_server
  ]
}

# =============================================================================
# APPLY MONITORING INGRESS POLICY (Monitoring Namespace)
# =============================================================================
resource "kubernetes_manifest" "allow_monitoring_ingress" {
  count = var.enable_prometheus_scraping ? 1 : 0

  manifest = yamldecode(file("${path.module}/policies/allow-monitoring-ingress.yaml"))

  field_manager {
    name            = "terraform-network-policies"
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.allow_dns,
    kubernetes_manifest.allow_api_server
  ]
}

# =============================================================================
# APPLY CERT-MANAGER EGRESS POLICY (cert-manager Namespace)
# =============================================================================
resource "kubernetes_manifest" "allow_cert_manager_egress" {
  count = var.enable_cert_manager_egress ? 1 : 0

  manifest = yamldecode(file("${path.module}/policies/allow-cert-manager-egress.yaml"))

  field_manager {
    name            = "terraform-network-policies"
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.allow_dns,
    kubernetes_manifest.allow_api_server
  ]
}

# =============================================================================
# APPLY DEFAULT DENY-ALL POLICY (Per Namespace) - LAST!
# =============================================================================
# ⚠️ IMPORTANTE: Esta política é aplicada POR ÚLTIMO
# Só habilitar após validar que todas as allow policies funcionam
# =============================================================================
resource "kubernetes_manifest" "default_deny_all" {
  for_each = var.enable_default_deny ? toset(var.namespaces) : []

  manifest = yamldecode(templatefile("${path.module}/policies/default-deny-all.yaml", {
    namespace = each.value
  }))

  field_manager {
    name            = "terraform-network-policies"
    force_conflicts = true
  }

  # Ensure all allow policies are created first
  depends_on = [
    kubernetes_manifest.allow_dns,
    kubernetes_manifest.allow_api_server,
    kubernetes_manifest.allow_prometheus_scraping,
    kubernetes_manifest.allow_fluent_bit_to_loki,
    kubernetes_manifest.allow_grafana_datasources,
    kubernetes_manifest.allow_monitoring_ingress,
    kubernetes_manifest.allow_cert_manager_egress
  ]
}
