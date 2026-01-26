# -----------------------------------------------------------------------------
# Cert-Manager Module
# Descrição: Automatiza emissão e renovação de certificados TLS/SSL
# Versão: v1.16.3
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Namespace para Cert-Manager
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = var.namespace

    labels = {
      "name"                         = var.namespace
      "app.kubernetes.io/name"       = "cert-manager"
      "app.kubernetes.io/instance"   = "cert-manager"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Helm Release - Cert-Manager
# -----------------------------------------------------------------------------

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  # Install CRDs
  set {
    name  = "installCRDs"
    value = "true"
  }

  # Webhook configuration
  set {
    name  = "webhook.securePort"
    value = "10250"
  }

  # Global configuration
  set {
    name  = "global.leaderElection.namespace"
    value = var.namespace
  }

  # Resource requests/limits
  set {
    name  = "resources.requests.cpu"
    value = "10m"
  }

  set {
    name  = "resources.requests.memory"
    value = "32Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }

  # Webhook resources
  set {
    name  = "webhook.resources.requests.cpu"
    value = "10m"
  }

  set {
    name  = "webhook.resources.requests.memory"
    value = "32Mi"
  }

  set {
    name  = "webhook.resources.limits.cpu"
    value = "50m"
  }

  set {
    name  = "webhook.resources.limits.memory"
    value = "64Mi"
  }

  # CAInjector resources
  set {
    name  = "cainjector.resources.requests.cpu"
    value = "10m"
  }

  set {
    name  = "cainjector.resources.requests.memory"
    value = "32Mi"
  }

  set {
    name  = "cainjector.resources.limits.cpu"
    value = "50m"
  }

  set {
    name  = "cainjector.resources.limits.memory"
    value = "64Mi"
  }

  # Node selector for system nodes
  set {
    name  = "nodeSelector.node-type"
    value = "system"
  }

  set {
    name  = "webhook.nodeSelector.node-type"
    value = "system"
  }

  set {
    name  = "cainjector.nodeSelector.node-type"
    value = "system"
  }

  # Tolerations for system nodes
  set {
    name  = "tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "tolerations[0].value"
    value = "system"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  set {
    name  = "webhook.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "webhook.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "webhook.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "webhook.tolerations[0].effect"
    value = "NoSchedule"
  }

  set {
    name  = "cainjector.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "cainjector.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "cainjector.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "cainjector.tolerations[0].effect"
    value = "NoSchedule"
  }

  depends_on = [kubernetes_namespace.cert_manager]
}

# -----------------------------------------------------------------------------
# ClusterIssuer - Let's Encrypt Staging
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "letsencrypt_staging" {
  count = var.create_cluster_issuers ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"

    metadata = {
      name = "letsencrypt-staging"
    }

    spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email

        privateKeySecretRef = {
          name = "letsencrypt-staging"
        }

        solvers = [
          {
            http01 = {
              ingress = {
                class = "alb"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

# -----------------------------------------------------------------------------
# ClusterIssuer - Let's Encrypt Production
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "letsencrypt_production" {
  count = var.create_cluster_issuers ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"

    metadata = {
      name = "letsencrypt-production"
    }

    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email

        privateKeySecretRef = {
          name = "letsencrypt-production"
        }

        solvers = [
          {
            http01 = {
              ingress = {
                class = "alb"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}
