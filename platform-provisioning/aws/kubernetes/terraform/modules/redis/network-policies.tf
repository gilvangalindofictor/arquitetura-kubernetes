# =============================================================================
# Redis Network Policies - Marco 3 Fase 2
# Security & Compliance: Micro-segmentation with Calico
# ADR-023: 6 Network Policies for Redis namespace
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Default Deny All Ingress (Baseline)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis_default_deny" {
  depends_on = [kubectl_manifest.redis]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "redis-default-deny-ingress"
      namespace = kubernetes_namespace.data_services.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "redis"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "redis"
        }
      }

      policyTypes = ["Ingress"]

      # Empty ingress rules = deny all
      ingress = []
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 2. Allow Internal Redis Communication (Master, Replica, Sentinel)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis_allow_internal" {
  depends_on = [kubectl_manifest.redis]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "redis-allow-internal"
      namespace = kubernetes_namespace.data_services.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "redis"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "redis"
        }
      }

      policyTypes = ["Ingress"]

      ingress = [
        {
          # Allow Redis pods to communicate with each other
          from = [
            {
              podSelector = {
                matchLabels = {
                  "app.kubernetes.io/name" = "redis"
                }
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 6379 # Redis
            },
            {
              protocol = "TCP"
              port     = 26379 # Sentinel
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 3. Allow GitLab to Access Redis
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis_allow_gitlab" {
  depends_on = [kubectl_manifest.redis]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "redis-allow-gitlab"
      namespace = kubernetes_namespace.data_services.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "redis"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "redis"
        }
      }

      policyTypes = ["Ingress"]

      ingress = [
        {
          from = [
            {
              namespaceSelector = {
                matchLabels = {
                  "kubernetes.io/metadata.name" = "gitlab"
                }
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 6379
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 4. Allow Harbor to Access Redis
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis_allow_harbor" {
  depends_on = [kubectl_manifest.redis]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "redis-allow-harbor"
      namespace = kubernetes_namespace.data_services.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "redis"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "redis"
        }
      }

      policyTypes = ["Ingress"]

      ingress = [
        {
          from = [
            {
              namespaceSelector = {
                matchLabels = {
                  "kubernetes.io/metadata.name" = "harbor"
                }
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 6379
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 5. Allow Monitoring to Scrape Metrics
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis_allow_monitoring" {
  depends_on = [kubectl_manifest.redis]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "redis-allow-monitoring"
      namespace = kubernetes_namespace.data_services.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "redis"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "redis"
        }
      }

      policyTypes = ["Ingress"]

      ingress = [
        {
          from = [
            {
              namespaceSelector = {
                matchLabels = {
                  "kubernetes.io/metadata.name" = "monitoring"
                }
              }
            }
          ]

          ports = [
            {
              protocol = "TCP"
              port     = 9121 # Redis exporter metrics
            }
          ]
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}

# -----------------------------------------------------------------------------
# 6. Deny Other Namespaces (Explicit Deny for Documentation)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis_deny_other_namespaces" {
  depends_on = [kubectl_manifest.redis]

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"

    metadata = {
      name      = "redis-deny-other-namespaces"
      namespace = kubernetes_namespace.data_services.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "redis"
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })

      annotations = {
        "description" = "Explicit deny for all other namespaces (documentation purpose, enforced by default-deny)"
      }
    }

    spec = {
      podSelector = {
        matchLabels = {
          "app.kubernetes.io/name" = "redis"
        }
      }

      policyTypes = ["Ingress"]

      # This is redundant with default-deny but serves as explicit documentation
      ingress = []
    }
  })

  force_conflicts   = true
  server_side_apply = true
}
