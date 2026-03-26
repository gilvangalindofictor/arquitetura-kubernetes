# -----------------------------------------------------------------------------
# Linkerd mTLS Phase 2 Module
# Fase 6a: ServerPolicy enforcement for mTLS across namespaces
# GAP-011 Phase 2: BACEN BCB 85/2021 Compliance
#
# Architecture:
#   1. Namespace annotation config.linkerd.io/default-inbound-policy=all-authenticated
#      enforces mTLS for ALL inbound traffic without requiring per-port Server resources.
#   2. MeshTLSAuthentication: Defines the cluster identity requirement.
#   3. NetworkAuthentication: Allows kubelet probes (non-meshed) to admin ports.
#   4. Server + AuthorizationPolicy per admin port to allow health checks.
#
# Prerequisites:
#   - Linkerd control plane installed and running (modules/linkerd)
#   - Linkerd CRDs installed (linkerd-crds Helm chart)
#   - Target namespaces annotated with linkerd.io/inject=enabled
#   - Workloads restarted to inject Linkerd sidecars (all pods 2/2 Running)
#
# Rollout strategy:
#   1. Enable proxy injection on target namespaces (modules/linkerd)
#   2. Restart workloads to inject sidecars (verify 100% MESHED)
#   3. Apply this module to enforce mTLS via default-inbound-policy annotation
#   4. Monitor via: linkerd viz stat deploy -n <namespace>
# -----------------------------------------------------------------------------

locals {
  module_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "linkerd-mtls"
    "gap"                          = "GAP-011-phase2"
    "compliance"                   = "bcb-85-2021"
    "environment"                  = var.environment
  }
}

# =============================================================================
# 1. Namespace annotation — enforce default-inbound-policy=all-authenticated
#    This is the primary mTLS enforcement mechanism for the namespace.
#    It requires all inbound connections to present a valid Linkerd mTLS identity.
#    No Server resources needed — the policy applies to all ports implicitly.
# =============================================================================

resource "kubernetes_annotations" "mtls_namespace_policy" {
  for_each = toset(var.mtls_namespaces)

  api_version = "v1"
  kind        = "Namespace"

  metadata {
    name = each.value
  }

  annotations = {
    "config.linkerd.io/default-inbound-policy" = var.default_policy
    "linkerd.io/inject"                         = "enabled"
  }
}

# =============================================================================
# 2. MeshTLSAuthentication — Cluster-wide mTLS identity requirement
#    Defines that connections must present a valid Linkerd mTLS identity.
#    Used as reference by AuthorizationPolicy resources.
# =============================================================================

resource "kubectl_manifest" "mesh_tls_auth" {
  for_each = toset(var.mtls_namespaces)

  yaml_body = yamlencode({
    apiVersion = "policy.linkerd.io/v1alpha1"
    kind       = "MeshTLSAuthentication"
    metadata = {
      name      = "mesh-tls-auth"
      namespace = each.value
      labels    = local.module_labels
    }
    spec = {
      identityRefs = [{
        kind = "Namespace"
        name = each.value
      }]
    }
  })

  depends_on = [kubernetes_annotations.mtls_namespace_policy]
}

# =============================================================================
# 3. NetworkAuthentication + Server + AuthorizationPolicy — Admin port bypass
#    Allows non-meshed traffic (kubelet probes, ALB health checks) to reach
#    the Linkerd admin port (4191) without mTLS authentication.
#    This prevents breaking liveness/readiness probes under strict mTLS.
# =============================================================================

resource "kubectl_manifest" "network_auth_probes" {
  for_each = var.allow_admin_server_access ? toset(var.mtls_namespaces) : toset([])

  yaml_body = yamlencode({
    apiVersion = "policy.linkerd.io/v1alpha1"
    kind       = "NetworkAuthentication"
    metadata = {
      name      = "allow-probes"
      namespace = each.value
      labels    = local.module_labels
    }
    spec = {
      networks = [
        { cidr = "0.0.0.0/0" },
        { cidr = "::/0" },
      ]
    }
  })

  depends_on = [kubernetes_annotations.mtls_namespace_policy]
}

resource "kubectl_manifest" "server_admin_ports" {
  for_each = var.allow_admin_server_access ? toset(var.mtls_namespaces) : toset([])

  yaml_body = yamlencode({
    apiVersion = "policy.linkerd.io/v1beta1"
    kind       = "Server"
    metadata = {
      name      = "admin-ports"
      namespace = each.value
      labels    = local.module_labels
    }
    spec = {
      podSelector = {
        matchLabels = {}
      }
      port          = var.admin_ports[0]
      proxyProtocol = "HTTP/1"
    }
  })

  depends_on = [kubernetes_annotations.mtls_namespace_policy]
}

resource "kubectl_manifest" "authz_policy_probes" {
  for_each = var.allow_admin_server_access ? toset(var.mtls_namespaces) : toset([])

  yaml_body = yamlencode({
    apiVersion = "policy.linkerd.io/v1alpha1"
    kind       = "AuthorizationPolicy"
    metadata = {
      name      = "allow-probes"
      namespace = each.value
      labels    = local.module_labels
    }
    spec = {
      targetRef = {
        group = "policy.linkerd.io"
        kind  = "Server"
        name  = "admin-ports"
      }
      requiredAuthenticationRefs = [{
        name  = "allow-probes"
        kind  = "NetworkAuthentication"
        group = "policy.linkerd.io"
      }]
    }
  })

  depends_on = [
    kubectl_manifest.network_auth_probes,
    kubectl_manifest.server_admin_ports,
  ]
}
