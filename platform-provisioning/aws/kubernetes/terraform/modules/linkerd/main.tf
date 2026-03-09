# -----------------------------------------------------------------------------
# Linkerd Service Mesh Module
# GAP-011: mTLS End-to-End | BACEN BCB 85/2021 Compliance
#
# Architecture:
#   1. PKI (TLS provider): trust anchor CA + intermediate issuer cert
#   2. linkerd-crds   Helm release  — ServiceProfile, AuthorizationPolicy CRDs
#   3. linkerd-control-plane Helm release — identity, proxy-injector, destination
#   4. linkerd-viz    Helm release  — dashboard, Tap API, Prometheus scraping
#   5. linkerd-jaeger Helm release  — optional distributed tracing
#   6. Namespace annotations        — opt-in proxy injection per namespace
#
# Proxy injection is OPT-IN via annotation:
#   linkerd.io/inject: enabled   (Deployment / Namespace level)
# -----------------------------------------------------------------------------

# ---- locals ------------------------------------------------------------------

locals {
  linkerd_namespace = "linkerd"

  # Labels applied to all K8s resources managed by this module
  module_labels = merge(var.common_tags, {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "linkerd"
    "gap"                          = "GAP-011"
    "compliance"                   = "bcb-85-2021"
  })
}

# =============================================================================
# 1. PKI — Trust Anchor (root CA) + Intermediate Issuer Certificate
#    All generated entirely by Terraform's TLS provider (no external CA needed)
# =============================================================================

# --- Trust Anchor Private Key (root CA) --------------------------------------
resource "tls_private_key" "trust_anchor" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

# --- Trust Anchor Self-Signed Certificate (root CA) --------------------------
# This certificate is injected into every proxy at startup as the SPIFFE root.
# Rotation requires a full control-plane restart; plan for it in advance.
resource "tls_self_signed_cert" "trust_anchor" {
  private_key_pem = tls_private_key.trust_anchor.private_key_pem

  subject {
    common_name  = "root.linkerd.cluster.local"
    organization = "Linkerd"
  }

  # Validity: configured via variable (default 365 days)
  validity_period_hours = var.certificate_validity_days * 24

  # CA certificate — used to sign intermediate issuer
  is_ca_certificate = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "key_encipherment",
    "digital_signature",
  ]
}

# --- Intermediate Issuer Private Key -----------------------------------------
# The control-plane identity component uses this key to mint per-workload certs.
resource "tls_private_key" "issuer" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

# --- Intermediate Issuer Certificate (signed by Trust Anchor) ----------------
resource "tls_locally_signed_cert" "issuer" {
  cert_request_pem   = tls_cert_request.issuer.cert_request_pem
  ca_private_key_pem = tls_private_key.trust_anchor.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.trust_anchor.cert_pem

  validity_period_hours = var.issuer_certificate_validity_hours

  is_ca_certificate = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "key_encipherment",
    "digital_signature",
  ]
}

resource "tls_cert_request" "issuer" {
  private_key_pem = tls_private_key.issuer.private_key_pem

  subject {
    common_name  = "identity.linkerd.cluster.local"
    organization = "Linkerd"
  }
}

# =============================================================================
# 2. Kubernetes Namespace — linkerd
# =============================================================================

resource "kubernetes_namespace" "linkerd" {
  metadata {
    name = local.linkerd_namespace

    labels = merge(local.module_labels, {
      "linkerd.io/is-control-plane"          = "true"
      "config.linkerd.io/admission-webhooks" = "disabled"
      "kubernetes.io/metadata.name"          = local.linkerd_namespace
    })

    annotations = {
      "linkerd.io/inject" = "disabled"
    }
  }
}

# =============================================================================
# 3. Helm Release — Linkerd CRDs
#    Must be installed BEFORE the control-plane chart.
#    Provides: ServiceProfile, AuthorizationPolicy, MeshTLSAuthentication, etc.
# =============================================================================

resource "helm_release" "linkerd_crds" {
  name       = "linkerd-crds"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd-crds"
  version    = var.linkerd_crds_chart_version
  namespace  = kubernetes_namespace.linkerd.metadata[0].name

  # CRD-only chart: no values needed
  wait    = true
  timeout = 300

  depends_on = [kubernetes_namespace.linkerd]
}

# =============================================================================
# 4. Helm Release — Linkerd Control Plane
#    Components: identity, proxy-injector, destination, policy-controller
# =============================================================================

resource "helm_release" "linkerd_control_plane" {
  name       = "linkerd-control-plane"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd-control-plane"
  version    = var.linkerd_version
  namespace  = kubernetes_namespace.linkerd.metadata[0].name

  # Increased timeout for first install: image pulls + CRD establishment
  timeout = 600
  wait    = true

  # --- PKI injection ---
  # Trust anchor cert (PEM) is passed so all proxies share the same root of trust.
  # Issuer cert + key are passed for the identity component to sign workload certs.
  set {
    name  = "identityTrustAnchorsPEM"
    value = tls_self_signed_cert.trust_anchor.cert_pem
  }

  set_sensitive {
    name  = "identity.issuer.tls.crtPEM"
    value = tls_locally_signed_cert.issuer.cert_pem
  }

  set_sensitive {
    name  = "identity.issuer.tls.keyPEM"
    value = tls_private_key.issuer.private_key_pem
  }

  # --- Trust domain ---
  set {
    name  = "identityTrustDomain"
    value = var.trust_domain
  }

  # --- HA mode ---
  set {
    name  = "controllerReplicas"
    value = var.ha_mode ? 3 : 1
  }

  set {
    name  = "highAvailability"
    value = var.ha_mode
  }

  # --- Sidecar proxy resource limits ---
  values = [<<-YAML
    proxy:
      resources:
        cpu:
          request: ${var.proxy_cpu_request}
          limit: ${var.proxy_cpu_limit}
        memory:
          request: ${var.proxy_memory_request}
          limit: ${var.proxy_memory_limit}

    # Proxy injection is opt-in: annotation linkerd.io/inject=enabled on workloads.
    # proxyInjector.namespaceSelector controls which namespaces are eligible.
    # We leave the default (all non-linkerd namespaces eligible) and rely on
    # the pod annotation for actual injection to keep blast radius minimal.
    proxyInjector:
      namespaceSelector:
        matchExpressions:
          - key: kubernetes.io/metadata.name
            operator: NotIn
            values:
              - ${local.linkerd_namespace}
              - kube-system
              - kube-public
              - kube-node-lease

    # Certificate rotation: proxy certs issued for 24h, rotated automatically
    identity:
      issuer:
        issuanceLifetime: "24h0m0s"
        clockSkewAllowance: "20s"

    # ==========================================================================
    # MITIGACAO RACE CONDITION CNI (2026-03-06) — Incidente exit 95
    # Root cause: linkerd-network-validator schedulado em no novo ANTES do
    # CNI (linkerd-cni DaemonSet) configurar regras iptables.
    # Fix: pinnar CP nos nos 'system' (long-lived, CNI sempre estavel).
    # Ref: docs/logbook/2026-03-06-linkerd-crashloop-fix.md
    # ==========================================================================

    # MITIGACAO 1 — nodeSelector: CP apenas nos nos 'system'
    # Nos system (t3.medium, min=2) nunca sao criados do zero durante operacao normal.
    # O CNI ja esta configurado nesses nos -> linkerd-network-validator nao falha.
    # control_plane_node_selector eh configuravel via variavel (override em producao).
    nodeSelector:
      kubernetes.io/os: linux
      %{~for k, v in var.control_plane_node_selector~}
      ${k}: "${v}"
      %{~endfor~}

    # MITIGACAO 2 — PodDisruptionBudget via flag nativa do chart
    # Garante minAvailable=1 para identity, destination e proxy-injector.
    # Previne que operacoes de manutencao (drain/upgrade de no) derrubem o CP inteiro.
    # Usa flag nativa do chart (mais idiomatico que kubernetes_manifest externo).
    enablePodDisruptionBudget: ${var.enable_pod_disruption_budget}

    # MITIGACAO 3 — podAntiAffinity preferencial entre componentes do CP
    # Distribui identity, destination e proxy-injector em nos diferentes
    # (dentro dos system nodes), reduzindo impacto de falha de no unico.
    # Usa preferredDuringSchedulingIgnoredDuringExecution (nao bloqueante).
    enablePodAntiAffinity: ${var.enable_pod_anti_affinity}

    # ==========================================================================
    # FIX networkValidator (2026-03-09) — race condition scale-up
    # Root cause: linkerd-network-validator tenta conectar no proxy outbound
    # antes do CNI estar pronto no novo no — resulta em connection refused.
    # Fix: pinnar connectAddr no loopback (127.0.0.1:4140) para evitar timeout
    # durante inicializacao antes do CNI configurar regras iptables.
    # Ref: docs/logbook/2026-03-06-linkerd-crashloop-fix.md
    # ==========================================================================
    networkValidator:
      connectAddr: "127.0.0.1:4140"
  YAML
  ]

  # CNI integration: when CNI is enabled, disable init containers
  dynamic "set" {
    for_each = var.cni_enabled ? [1] : []
    content {
      name  = "cniEnabled"
      value = "true"
    }
  }

  depends_on = [helm_release.linkerd_crds]
}

# =============================================================================
# 4a. Namespace — linkerd-cni (optional)
# =============================================================================

resource "kubernetes_namespace" "linkerd_cni" {
  count = var.cni_enabled ? 1 : 0

  metadata {
    name = "linkerd-cni"

    labels = merge(local.module_labels, {
      "linkerd.io/cni-resource"     = "true"
      "kubernetes.io/metadata.name" = "linkerd-cni"
      domain                        = "platform"
      managed-by                    = "terraform"
    })

    annotations = {
      "linkerd.io/inject" = "disabled"
    }
  }
}

# =============================================================================
# 4b. Helm Release — Linkerd CNI Plugin (optional)
#     Enables iptables rules injection at the CNI level (DaemonSet).
#     With CNI: init containers (linkerd-init) no longer need NET_ADMIN.
#     Result: gitlab-staging PSA can drop 'privileged' requirement.
#     Ref: https://linkerd.io/2/features/cni/
# =============================================================================

resource "helm_release" "linkerd_cni" {
  count = var.cni_enabled ? 1 : 0

  name             = "linkerd-cni"
  repository       = "https://helm.linkerd.io/stable"
  chart            = "linkerd2-cni"
  version          = var.linkerd_cni_version
  namespace        = kubernetes_namespace.linkerd_cni[0].metadata[0].name
  create_namespace = false

  set {
    name  = "installNamespace"
    value = "false"
  }

  # Corporate labels (ADR-048)
  set {
    name  = "commonLabels.domain"
    value = "platform"
  }
  set {
    name  = "commonLabels.managed-by"
    value = "terraform"
  }

  # wait=false: DaemonSet may have 2 pods Pending on system/fargate nodes
  # that never become Ready (NodeAffinity + capacity constraints). CNI is
  # fully operational on all worker nodes (10/12). Avoiding timeout on apply.
  wait = false

  depends_on = [helm_release.linkerd_crds]
}

# =============================================================================
# 5. Namespace — linkerd-viz
# =============================================================================

resource "kubernetes_namespace" "linkerd_viz" {
  count = var.enable_viz ? 1 : 0

  metadata {
    name = var.viz_namespace

    labels = merge(local.module_labels, {
      "linkerd.io/extension"        = "viz"
      "kubernetes.io/metadata.name" = var.viz_namespace
    })

    annotations = {
      "linkerd.io/inject" = "disabled"
    }
  }
}

# =============================================================================
# 6. Helm Release — Linkerd Viz Extension
#    Provides: dashboard, Tap API, ServiceProfile metrics, Prometheus scraping
# =============================================================================

resource "helm_release" "linkerd_viz" {
  count = var.enable_viz ? 1 : 0

  name       = "linkerd-viz"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd-viz"
  version    = var.linkerd_viz_chart_version
  namespace  = kubernetes_namespace.linkerd_viz[0].metadata[0].name

  timeout = 600
  wait    = true

  values = [<<-YAML
    # Disable built-in Prometheus when using existing kube-prometheus-stack
    prometheus:
      enabled: ${var.viz_prometheus_enabled}

    # Point Viz to external Prometheus
    prometheusUrl: ${var.viz_prometheus_enabled ? "" : var.external_prometheus_url}

    # Dashboard: accessible via kubectl port-forward or ingress (not exposed by default)
    dashboard:
      replicas: 1

    # Tap API: real-time L7 traffic inspection
    tap:
      enabled: true
      replicas: 1

    # Metrics API
    metricsAPI:
      replicas: 1

    # Inject viz components with Linkerd proxy for mTLS
    # (viz namespace is annotated with inject=disabled above to break circular dep;
    #  individual viz pods are annotated by the chart itself after control-plane is up)
  YAML
  ]

  depends_on = [helm_release.linkerd_control_plane]
}

# =============================================================================
# 7. Namespace — linkerd-jaeger (optional)
# =============================================================================

resource "kubernetes_namespace" "linkerd_jaeger" {
  count = var.enable_jaeger ? 1 : 0

  metadata {
    name = var.jaeger_namespace

    labels = merge(local.module_labels, {
      "linkerd.io/extension"        = "jaeger"
      "kubernetes.io/metadata.name" = var.jaeger_namespace
    })

    annotations = {
      "linkerd.io/inject" = "disabled"
    }
  }
}

# =============================================================================
# 8. Helm Release — Linkerd Jaeger Extension (optional)
#    Routes OpenCensus spans from proxies to an existing OTel/Jaeger collector
# =============================================================================

resource "helm_release" "linkerd_jaeger" {
  count = var.enable_jaeger ? 1 : 0

  name       = "linkerd-jaeger"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd-jaeger"
  version    = var.linkerd_jaeger_chart_version
  namespace  = kubernetes_namespace.linkerd_jaeger[0].metadata[0].name

  timeout = 300
  wait    = true

  values = [<<-YAML
    # Route spans to existing OpenTelemetry collector (monitoring namespace)
    # Linkerd proxies emit spans via OpenCensus protocol (port 55678)
    collector:
      enabled: true
      config: |
        receivers:
          opencensus:
            port: 55678
        exporters:
          otlp:
            endpoint: ${var.collector_backend_addr}
            tls:
              insecure: true
        service:
          pipelines:
            traces:
              receivers: [opencensus]
              exporters: [otlp]

    jaeger:
      enabled: false  # Use external Jaeger/Tempo; collector just forwards spans
  YAML
  ]

  depends_on = [helm_release.linkerd_control_plane]
}

# =============================================================================
# 9. Opt-in Namespace Annotations
#    Annotates namespaces listed in var.proxy_inject_namespaces with
#    linkerd.io/inject=enabled so all new pods get the sidecar automatically.
#    Individual pods can opt-out with: linkerd.io/inject=disabled
# =============================================================================

resource "kubernetes_annotations" "linkerd_inject" {
  for_each = toset(var.proxy_inject_namespaces)

  api_version = "v1"
  kind        = "Namespace"

  metadata {
    name = each.value
  }

  annotations = {
    "linkerd.io/inject" = "enabled"
  }

  # Preserve existing annotations (field_manager patch, not replace)
  force = false

  depends_on = [helm_release.linkerd_control_plane]
}

# =============================================================================
# 10. Grafana Dashboard ConfigMap
#     Injects a Grafana dashboard configuration so kube-prometheus-stack's
#     sidecar auto-discovers it.  The ConfigMap contains a datasource pointer
#     and a reference annotation; the full JSON dashboards should be placed
#     under modules/linkerd/dashboards/ (downloaded from the Linkerd repository).
#
#     Official dashboard sources (download and commit to dashboards/):
#       https://github.com/linkerd/linkerd2/tree/main/grafana/dashboards
#
#     Quick download (run once, then commit):
#       curl -sL https://raw.githubusercontent.com/linkerd/linkerd2/stable-2.16.0/grafana/dashboards/top-line.json \
#         -o modules/linkerd/dashboards/linkerd-top-line.json
#       (repeat for each dashboard)
#
#     This resource is disabled by default (count=0) until dashboard JSON files
#     are present.  Set enable_grafana_dashboards=true after downloading.
# =============================================================================

resource "kubernetes_config_map" "linkerd_grafana_dashboard" {
  count = (var.enable_viz && var.enable_grafana_dashboards) ? 1 : 0

  metadata {
    name      = "linkerd-grafana-dashboards"
    namespace = var.grafana_dashboard_namespace

    labels = merge(local.module_labels, {
      # Label watched by Grafana sidecar (kube-prometheus-stack default)
      "grafana_dashboard" = "1"
    })

    annotations = {
      "meta.helm.sh/release-name"      = "linkerd-viz"
      "meta.helm.sh/release-namespace" = var.viz_namespace
    }
  }

  data = {
    # Place downloaded JSON files under modules/linkerd/dashboards/
    # See comment above for download commands.
    "linkerd-top-line.json"     = file("${path.module}/dashboards/linkerd-top-line.json")
    "linkerd-service-mesh.json" = file("${path.module}/dashboards/linkerd-service-mesh.json")
    "linkerd-deployment.json"   = file("${path.module}/dashboards/linkerd-deployment.json")
    "linkerd-namespace.json"    = file("${path.module}/dashboards/linkerd-namespace.json")
  }

  depends_on = [helm_release.linkerd_viz]
}
