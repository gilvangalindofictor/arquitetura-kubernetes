# =============================================================================
# Redis Module - Marco 3 Data Services
# Operator: OT-Container-Kit Redis Operator v0.23.0
# Architecture: Standalone Redis (single instance)
# ADR-023: Migration from Bitnami Charts to Kubernetes Operators
# Migration: SpotaHome -> OT-Container-Kit (2026-02-13)
# =============================================================================

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# -----------------------------------------------------------------------------
# Redis Password (stored in Kubernetes Secret)
# -----------------------------------------------------------------------------

resource "random_password" "redis" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "kubernetes_namespace" "redis_operator" {
  metadata {
    name = var.operator_namespace

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"       = "redis-operator"
      "app.kubernetes.io/managed-by" = "terraform"
    })
  }
}

resource "kubernetes_namespace" "data_services" {
  metadata {
    name = var.namespace

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"             = "data-services"
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "kubernetes.io/metadata.name"        = var.namespace
    })
  }
}

resource "kubernetes_secret" "redis_password" {
  metadata {
    name      = "redis-password"
    namespace = kubernetes_namespace.data_services.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "redis"
      "app.kubernetes.io/instance" = "${var.cluster_name}-redis"
    })
  }

  data = {
    password = random_password.redis.result
  }

  type = "Opaque"

  lifecycle {
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }
}

# =============================================================================
# OT-Container-Kit Redis Operator (IDEMPOTENT INSTALLATION)
# =============================================================================
# Migrated from SpotaHome to OT-Container-Kit (2026-02-13)
# Operator image: quay.io/opstree/redis-operator:v0.23.0
# CRDs: redis.redis.redis.opstreelabs.in (v1beta2)
# =============================================================================

resource "helm_release" "redis_operator" {
  name       = "redis-operator"
  namespace  = kubernetes_namespace.redis_operator.metadata[0].name
  chart      = "/home/gilvangalindo/.cache/helm/repository/redis-operator-0.23.0.tgz"

  skip_crds       = true
  replace         = true
  force_update    = true
  cleanup_on_fail = true
  atomic          = false
  timeout         = 600

  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }

  # Kyverno compliance labels (codified from imperative apply 2026-03-10)
  # Chart uses redisOperator.podLabels (not top-level podLabels)
  set {
    name  = "redisOperator.podLabels.domain"
    value = "data"
  }

  set {
    name  = "redisOperator.podLabels.owner"
    value = "platform-team"
  }

  set {
    name  = "redisOperator.podLabels.environment"
    value = lookup(var.common_tags, "Environment", "staging")
  }

  set {
    name  = "redisOperator.podLabels.app\\.kubernetes\\.io/name"
    value = "redis-operator"
  }

  set {
    name  = "redisOperator.podLabels.app\\.kubernetes\\.io/part-of"
    value = "data-services"
  }

}

# Wait for CRDs to be fully registered
resource "time_sleep" "wait_for_crds" {
  depends_on = [helm_release.redis_operator]

  create_duration = "30s"
}

# -----------------------------------------------------------------------------
# OT-Container-Kit Redis CR (Standalone)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis" {
  depends_on = [
    time_sleep.wait_for_crds,
    kubernetes_secret.redis_password
  ]

  yaml_body = yamlencode({
    apiVersion = "redis.redis.opstreelabs.in/v1beta2"
    kind       = "Redis"

    metadata = {
      name      = "redis"
      namespace = kubernetes_namespace.data_services.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "redis"
        "app.kubernetes.io/instance"   = "${var.cluster_name}-redis"
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = "data-services"
        "domain"                       = "data"
        "owner"                        = "platform-team"
        "environment"                  = lookup(var.common_tags, "Environment", "staging")
      })
    }

    spec = {
      kubernetesConfig = {
        image           = "quay.io/opstree/redis:v8.4.0"
        imagePullPolicy = "IfNotPresent"

        redisSecret = {
          name = kubernetes_secret.redis_password.metadata[0].name
          key  = "password"
        }

        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      # Pod Security Context (PSS Restricted compliant)
      # UID/GID 1000 matches quay.io/opstree/redis image's redis user
      podSecurityContext = {
        runAsNonRoot = true
        runAsUser    = 1000
        runAsGroup   = 1000
        fsGroup      = 1000
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }

      # Container Security Context (Redis)
      securityContext = {
        allowPrivilegeEscalation = false
        readOnlyRootFilesystem   = false
        runAsUser                = 1000
        runAsGroup               = 1000
        capabilities = {
          drop = ["ALL"]
        }
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }

      # Redis Exporter (Prometheus metrics)
      redisExporter = {
        enabled = true
        image   = "quay.io/opstree/redis-exporter:latest"

        securityContext = {
          allowPrivilegeEscalation = false
          readOnlyRootFilesystem   = true
          runAsNonRoot             = true
          runAsUser                = 1000
          runAsGroup               = 1000
          capabilities = {
            drop = ["ALL"]
          }
          seccompProfile = {
            type = "RuntimeDefault"
          }
        }
      }

      # Storage (PVC)
      storage = {
        volumeClaimTemplate = {
          spec = {
            storageClassName = var.storage_class
            accessModes      = ["ReadWriteOnce"]
            resources = {
              requests = {
                storage = var.pvc_size
              }
            }
          }
        }
      }

      # Tolerations
      tolerations = length(var.tolerations) > 0 ? [
        for t in var.tolerations : {
          key      = t.key
          operator = t.operator
          effect   = t.effect
          value    = try(t.value, null)
        }
      ] : []
    }
  })

  force_conflicts   = true
  server_side_apply = true
  wait              = true
}

# -----------------------------------------------------------------------------
# ServiceMonitor for Prometheus (monitoring namespace)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis_service_monitor" {
  depends_on = [kubectl_manifest.redis]

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"

    metadata = {
      name      = "redis"
      namespace = var.monitoring_namespace

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "redis"
        "app.kubernetes.io/component"  = "service-monitor"
        "app.kubernetes.io/managed-by" = "terraform"
        "prometheus"                   = "kube-prometheus-stack"
      })
    }

    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "redis"
        }
      }

      namespaceSelector = {
        matchNames = [kubernetes_namespace.data_services.metadata[0].name]
      }

      endpoints = [
        {
          port     = "metrics"
          interval = "30s"
          path     = "/metrics"
        }
      ]
    }
  })

  force_conflicts   = true
  server_side_apply = true
}
