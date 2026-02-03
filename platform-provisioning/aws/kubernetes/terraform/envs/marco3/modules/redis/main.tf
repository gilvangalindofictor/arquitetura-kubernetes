# =============================================================================
# Redis Module - Marco 3 Data Services
# Operator: Spotahome Redis Operator v3.2.9
# Architecture: RedisFailover (1 master + 2 replicas + 3 sentinels)
# ADR-023: Migration from Bitnami Charts to Kubernetes Operators
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
    name = "redis-operator"

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
      "app.kubernetes.io/name"                 = "data-services"
      "app.kubernetes.io/managed-by"           = "terraform"
      "pod-security.kubernetes.io/enforce"     = "restricted"
      "pod-security.kubernetes.io/audit"       = "restricted"
      "pod-security.kubernetes.io/warn"        = "restricted"
      "kubernetes.io/metadata.name"            = var.namespace
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
}

# -----------------------------------------------------------------------------
# Spotahome Redis Operator (via Helm)
# -----------------------------------------------------------------------------

resource "helm_release" "redis_operator" {
  name       = "redis-operator"
  namespace  = kubernetes_namespace.redis_operator.metadata[0].name
  repository = "https://spotahome.github.io/redis-operator"
  chart      = "redis-operator"
  version    = "3.2.9"

  timeout         = 600
  cleanup_on_fail = true
  atomic          = false

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
}

# Wait for CRDs to be registered
resource "time_sleep" "wait_for_crds" {
  depends_on = [helm_release.redis_operator]

  create_duration = "30s"
}

# -----------------------------------------------------------------------------
# RedisFailover Custom Resource (via kubectl provider)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis_failover" {
  depends_on = [
    time_sleep.wait_for_crds,
    kubernetes_secret.redis_password
  ]

  yaml_body = yamlencode({
    apiVersion = "databases.spotahome.com/v1"
    kind       = "RedisFailover"

    metadata = {
      name      = "redis"
      namespace = kubernetes_namespace.data_services.metadata[0].name

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "redis"
        "app.kubernetes.io/instance"   = "${var.cluster_name}-redis"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      sentinel = {
        replicas = 3

        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }

        # Security Context (PSS Restricted compliant)
        securityContext = {
          runAsNonRoot = true
          runAsUser    = 1000
          runAsGroup   = 1000
          fsGroup      = 1000
          seccompProfile = {
            type = "RuntimeDefault"
          }
        }

        containerSecurityContext = {
          allowPrivilegeEscalation = false
          readOnlyRootFilesystem   = true
          capabilities = {
            drop = ["ALL"]
          }
        }

        # Prometheus exporter
        exporter = {
          enabled = true
          image   = "quay.io/prometheus-community/redis-exporter:v1.55.0"
        }
      }

      redis = {
        replicas = var.replicas

        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        # Security Context (PSS Restricted compliant)
        securityContext = {
          runAsNonRoot = true
          runAsUser    = 1000
          runAsGroup   = 1000
          fsGroup      = 1000
          seccompProfile = {
            type = "RuntimeDefault"
          }
        }

        containerSecurityContext = {
          allowPrivilegeEscalation = false
          readOnlyRootFilesystem   = false  # Redis needs to write AOF/RDB
          capabilities = {
            drop = ["ALL"]
          }
        }

        storage = {
          persistentVolumeClaim = {
            metadata = {
              name = "redis-data"
            }
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

        # Prometheus exporter
        exporter = {
          enabled = true
          image   = "quay.io/prometheus-community/redis-exporter:v1.55.0"
        }

        # Custom config for Redis
        customConfig = [
          "maxmemory-policy allkeys-lru",
          "save 900 1",
          "save 300 10",
          "save 60 10000"
        ]
      }

      auth = {
        secretPath = kubernetes_secret.redis_password.metadata[0].name
      }
    }
  })

  # Force re-apply on changes
  force_conflicts   = true
  server_side_apply = true

  # Wait for CR to be accepted by API server
  wait = true
}

# -----------------------------------------------------------------------------
# ServiceMonitor for Prometheus (monitoring namespace)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis_service_monitor" {
  depends_on = [kubectl_manifest.redis_failover]

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"

    metadata = {
      name      = "redis"
      namespace = "monitoring"

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
