# =============================================================================
# RabbitMQ Module - Marco 3 Data Services
# Operator: RabbitMQ Cluster Operator (Official)
# Architecture: 3 node cluster (PROD) / 1 node (STAGING)
# =============================================================================
#
# ⚠️ AÇÃO MANUAL NECESSÁRIA (2026-02-02):
#
# O RabbitMQ Cluster Operator DEVE ser instalado manualmente ANTES do Terraform apply.
#
# MOTIVO:
# - Bitnami mudou política de imagens (requer subscrição paga desde Agosto/2025)
# - Imagens Bitnami não estão mais disponíveis publicamente
# - Helm chart Bitnami falha com "ImagePullBackOff"
#
# SOLUÇÃO: Usar Operator Oficial do RabbitMQ
#
# COMANDO PARA INSTALAÇÃO MANUAL:
# kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
#
# VALIDAÇÃO:
# kubectl get pods -n rabbitmq-system
# kubectl get crd rabbitmqclusters.rabbitmq.com
#
# ALTERNATIVA FUTURA:
# Migrar Helm chart para usar imagens públicas do RabbitMQ oficial
# ou assinar Bitnami Secure Images
#
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
# RabbitMQ Cluster Operator (IDEMPOTENT INSTALLATION via kubectl)
# -----------------------------------------------------------------------------
#
# Instalação idempotente do operator oficial do RabbitMQ via kubectl.
# O script verifica se o operator já existe antes de instalar.
#
# MOTIVO: Bitnami images não disponíveis (requer subscrição)
# SOLUÇÃO: Usar operator oficial do RabbitMQ via kubectl
# DATA: 2026-02-02
#
resource "null_resource" "rabbitmq_operator" {
  triggers = {
    operator_version = "latest" # Muda para forçar reinstalação
  }

  provisioner "local-exec" {
    command = "kubectl get namespace rabbitmq-system >/dev/null 2>&1 && echo 'RabbitMQ Operator já instalado' || (kubectl apply -f 'https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml' && kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=rabbitmq-cluster-operator -n rabbitmq-system --timeout=120s)"
  }
}
#
# resource "helm_release" "rabbitmq_operator" {
#   name       = "rabbitmq-cluster-operator"
#   namespace  = var.namespace
#   repository = "https://charts.bitnami.com/bitnami"
#   chart      = "rabbitmq-cluster-operator"
#   version    = "4.4.34"  # Latest: RabbitMQ Cluster Operator 2.16.1
#
#   timeout         = 600
#   cleanup_on_fail = true
#   atomic          = true
#
#   values = [
#     yamlencode({
#       clusterOperator = {
#         resources = {
#           requests = {
#             cpu    = "100m"
#             memory = "128Mi"
#           }
#           limits = {
#             cpu    = "200m"
#             memory = "256Mi"
#           }
#         }
#       }
#
#       msgTopologyOperator = {
#         resources = {
#           requests = {
#             cpu    = "50m"
#             memory = "64Mi"
#           }
#           limits = {
#             cpu    = "100m"
#             memory = "128Mi"
#           }
#         }
#       }
#
#       commonLabels = merge(var.common_tags, {
#         "app.kubernetes.io/managed-by" = "terraform"
#       })
#     })
#   ]
# }

# -----------------------------------------------------------------------------
# RabbitMQ Cluster CRD
# Wait for Operator to install CRDs (Operator instalado manualmente)
# -----------------------------------------------------------------------------
#
# ⚠️ NOTA: O time_sleep foi REMOVIDO pois o Operator já está instalado manualmente
# O depends_on foi removido pois não há Helm release para depender
#
# resource "time_sleep" "wait_for_rabbitmq_crds" {
#   create_duration = "60s"
# }

resource "kubernetes_manifest" "rabbitmq_cluster" {
  # Operator já instalado manualmente via kubectl - CRDs já disponíveis

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
      replicas = var.replicas
      image    = "rabbitmq:3.13-management"

      persistence = {
        storageClassName = var.storage_class
        storage          = var.pvc_size
      }

      resources = {
        requests = {
          cpu    = "200m"
          memory = "1Gi"  # MUST be equal to limit (RabbitMQ Operator requirement)
        }
        limits = {
          cpu    = "1"  # Normalized form (equivalent to 1000m)
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

      # Tolerations (ADR-042 pattern: allow scheduling on critical nodes)
      tolerations = [
        {
          key      = "node-type"
          operator = "Equal"
          value    = "system"
          effect   = "NoSchedule"
        },
        {
          key      = "workload"
          operator = "Equal"
          value    = "critical"
          effect   = "NoSchedule"
        }
      ]

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

  lifecycle {
    ignore_changes = [
      spec[0].load_balancer_class,
      spec[0].load_balancer_source_ranges,
      spec[0].port[0].node_port,
      spec[0].port[1].node_port,
      spec[0].health_check_node_port,
      spec[0].internal_traffic_policy,
      spec[0].ip_families,
      spec[0].ip_family_policy,
      spec[0].session_affinity_config,
    ]
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
