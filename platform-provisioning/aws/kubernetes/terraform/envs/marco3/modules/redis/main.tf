# =============================================================================
# Redis Module - Marco 3 Data Services
# Helm Chart: bitnami/redis v18.x
# Architecture: Replication (1 master + 2 replicas)
# =============================================================================

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

resource "kubernetes_secret" "redis_password" {
  metadata {
    name      = "redis-password"
    namespace = var.namespace

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
# Redis Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "redis" {
  name       = "redis"
  namespace  = var.namespace
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  # version not specified - will use latest from repository

  timeout         = 600
  cleanup_on_fail = true
  atomic          = true

  values = [
    yamlencode({
      architecture = "replication"

      auth = {
        enabled                   = true
        existingSecret            = kubernetes_secret.redis_password.metadata[0].name
        existingSecretPasswordKey = "password"
      }

      master = {
        persistence = {
          enabled      = true
          storageClass = var.storage_class
          size         = var.pvc_size
        }

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

        podLabels = merge(var.common_tags, {
          "app.kubernetes.io/component" = "master"
        })
      }

      replica = {
        replicaCount = var.replicas

        persistence = {
          enabled      = true
          storageClass = var.storage_class
          size         = var.pvc_size
        }

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

        podLabels = merge(var.common_tags, {
          "app.kubernetes.io/component" = "replica"
        })
      }

      metrics = {
        enabled = true

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

        serviceMonitor = {
          enabled   = true
          namespace = "monitoring"

          labels = {
            prometheus = "kube-prometheus-stack"
          }
        }
      }

      commonLabels = merge(var.common_tags, {
        "app.kubernetes.io/managed-by" = "terraform"
      })
    })
  ]

  depends_on = [
    kubernetes_secret.redis_password
  ]
}

# -----------------------------------------------------------------------------
# Kubernetes Service (LoadBalancer) for External Access
# -----------------------------------------------------------------------------

resource "kubernetes_service" "redis_external" {
  metadata {
    name      = "redis-external"
    namespace = var.namespace

    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"     = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-internal" = "false"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"   = "internet-facing"
    }

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "redis"
      "app.kubernetes.io/instance" = "${var.cluster_name}-redis-external"
    })
  }

  spec {
    type = "LoadBalancer"

    selector = {
      "app.kubernetes.io/name"      = "redis"
      "app.kubernetes.io/instance"  = "redis"
      "app.kubernetes.io/component" = "master"
    }

    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
      protocol    = "TCP"
    }

    session_affinity = "ClientIP"
  }

  depends_on = [
    helm_release.redis
  ]
}
