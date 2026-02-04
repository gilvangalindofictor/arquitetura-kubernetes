# =============================================================================
# RabbitMQ Module - Marco 3 Data Services
# Operator: RabbitMQ Cluster Operator (managed manually via kubectl)
# ADR-023: Kubernetes Operators (kubectl deploy, not Helm)
# Architecture: 1 node cluster (can be scaled via replicas variable)
# =============================================================================
#
# NOTE: RabbitMQ Cluster Operator is deployed manually via kubectl apply
#       from official repository: github.com/rabbitmq/cluster-operator
#       This module only manages the RabbitmqCluster Custom Resource (CR)
#
# =============================================================================

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

# -----------------------------------------------------------------------------
# RabbitMQ Cluster CRD
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "rabbitmq_cluster" {
  field_manager {
    force_conflicts = true
  }

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
      replicas           = var.replicas
      image              = "rabbitmq:3.13-management"
      delayStartSeconds  = 30

      persistence = {
        storageClassName = var.storage_class
        storage          = var.pvc_size
      }

      resources = {
        requests = {
          cpu    = "200m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1"
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

      terminationGracePeriodSeconds = 604800
    }
  }

  # NOTE: Assumes RabbitMQ Cluster Operator is already installed via kubectl
  # Operator must be in rabbitmq-system namespace with CRDs installed
  # Reference: https://github.com/rabbitmq/cluster-operator
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

      labels = merge(var.common_tags, {
        prometheus                     = "kube-prometheus-stack"
        app                            = "rabbitmq"
        "app.kubernetes.io/name"       = "rabbitmq"
        "app.kubernetes.io/managed-by" = "terraform"
      })
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
