# =============================================================================
# RabbitMQ Module - Marco 3 Data Services
# Operator: RabbitMQ Cluster Operator
# Architecture: 3 node cluster
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
  }
}

# -----------------------------------------------------------------------------
# RabbitMQ Cluster Operator (Helm)
# -----------------------------------------------------------------------------

resource "helm_release" "rabbitmq_operator" {
  name       = "rabbitmq-cluster-operator"
  namespace  = var.namespace
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "rabbitmq-cluster-operator"
  version    = "4.4.34"  # Latest: RabbitMQ Cluster Operator 2.16.1

  timeout         = 600
  cleanup_on_fail = true
  atomic          = true

  values = [
    yamlencode({
      clusterOperator = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      msgTopologyOperator = {
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
      }

      commonLabels = merge(var.common_tags, {
        "app.kubernetes.io/managed-by" = "terraform"
      })
    })
  ]
}

# -----------------------------------------------------------------------------
# RabbitMQ Cluster CRD
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "rabbitmq_cluster" {
  manifest = {
    apiVersion = "rabbitmq.com/v1beta1"
    kind       = "RabbitmqCluster"

    metadata = {
      name      = "${var.cluster_name}-rabbitmq"
      namespace = var.namespace

      labels = merge(var.common_tags, {
        "app.kubernetes.io/name"       = "rabbitmq"
        "app.kubernetes.io/instance"   = "${var.cluster_name}-rabbitmq"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      replicas = var.replicas
      image    = "rabbitmq:3.13-management"

      persistence = {
        storageClassName = var.storage_class
        storage          = var.pvc_size
      }

      resources = {
        requests = {
          cpu    = "200m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }

      rabbitmq = {
        additionalPlugins = [
          "rabbitmq_management",
          "rabbitmq_prometheus",
          "rabbitmq_shovel",
          "rabbitmq_federation"
        ]

        additionalConfig = <<-EOT
          # Performance tuning
          vm_memory_high_watermark.relative = 0.6
          disk_free_limit.absolute = 2GB

          # Clustering
          cluster_partition_handling = autoheal
          cluster_formation.peer_discovery_backend = rabbit_peer_discovery_k8s
          cluster_formation.k8s.host = kubernetes.default.svc.cluster.local
          cluster_formation.k8s.address_type = hostname

          # Monitoring
          management.load_definitions = /etc/rabbitmq/definitions.json
          prometheus.return_per_object_metrics = true
        EOT
      }

      override = {
        service = {
          spec = {
            type = "ClusterIP"
          }
        }

        statefulSet = {
          spec = {
            template = {
              metadata = {
                labels = merge(var.common_tags, {
                  "app.kubernetes.io/component" = "rabbitmq-server"
                })
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.rabbitmq_operator
  ]
}

# -----------------------------------------------------------------------------
# Kubernetes Service (LoadBalancer) for Management UI
# -----------------------------------------------------------------------------

resource "kubernetes_service" "rabbitmq_management_external" {
  metadata {
    name      = "rabbitmq-management-external"
    namespace = var.namespace

    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"     = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-internal" = "false"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"   = "internet-facing"
    }

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "rabbitmq"
      "app.kubernetes.io/instance" = "${var.cluster_name}-rabbitmq-external"
    })
  }

  spec {
    type = "LoadBalancer"

    selector = {
      "app.kubernetes.io/name" = "${var.cluster_name}-rabbitmq"
    }

    port {
      name        = "amqp"
      port        = 5672
      target_port = 5672
      protocol    = "TCP"
    }

    port {
      name        = "management"
      port        = 15672
      target_port = 15672
      protocol    = "TCP"
    }

    session_affinity = "ClientIP"
  }

  depends_on = [
    kubernetes_manifest.rabbitmq_cluster
  ]
}

# -----------------------------------------------------------------------------
# ServiceMonitor for Prometheus (if monitoring enabled)
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "rabbitmq_servicemonitor" {
  count = var.enable_monitoring ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"

    metadata = {
      name      = "${var.cluster_name}-rabbitmq"
      namespace = "monitoring"

      labels = {
        prometheus = "kube-prometheus-stack"
        app        = "rabbitmq"
      }
    }

    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "${var.cluster_name}-rabbitmq"
        }
      }

      namespaceSelector = {
        matchNames = [var.namespace]
      }

      endpoints = [
        {
          port     = "prometheus"
          interval = "30s"
          path     = "/metrics"
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.rabbitmq_cluster
  ]
}
