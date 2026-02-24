# =============================================================================
# WAVE 2 MIGRATION: RabbitMQ Operator → staging-data-rabbitmq
# =============================================================================
# Date: 2026-02-24
# Pattern: A+D (Operator + CRDs)
# Risk: MEDIUM
# Duration: <60min
# Status: COMPLETED
#
# Migration Summary:
# - Old: rabbitmq-system namespace with kubectl-deployed operator
# - New: staging-data-rabbitmq namespace with proper RBAC
# - Zero downtime: Existing RabbitMQ CR in data-services reconciled successfully
# - Zero data loss: PVC intact, StatefulSet healthy
#
# Key Discoveries:
# - RabbitMQ operator requires ClusterRoleBinding for cluster-wide CRD management
# - Operator reconciles existing CRs across all namespaces (not namespace-scoped)
# - Memory request/limit warning is expected (upstream operator behavior)
# =============================================================================

# -----------------------------------------------------------------------------
# NAMESPACE: staging-data-rabbitmq
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "rabbitmq_operator_staging" {
  metadata {
    name = "staging-data-rabbitmq"

    labels = {
      "app.kubernetes.io/name"       = "rabbitmq-operator"
      "app.kubernetes.io/managed-by" = "terraform"
      "migration-pattern"            = "A-D-operator-crds"
      "migration-source"             = "rabbitmq-system"
      "migration-date"               = "2026-02-24"
      "domain"                       = "data-services"
      "component"                    = "rabbitmq-operator"
      "managed-by"                   = "terraform"
      "environment"                  = var.environment
      "Environment"                  = "staging"
      "ManagedBy"                    = "terraform"
      "Marco"                        = "3"
      "Owner"                        = "platform-team"
      "Project"                      = "k8s-platform"
      "CostCenter"                   = "development"
      "DataClassification"           = "Internal"
      "LGPD"                         = "Synthetic"
      "Terraform"                    = "true"
    }

    annotations = {
      "linkerd.io/inject" = "disabled" # Operators don't need mesh
      "wave2-migration"   = "rabbitmq-operator"
      "migration-commit"  = "TBD" # Update after commit
    }
  }
}

# -----------------------------------------------------------------------------
# SERVICEACCOUNT: rabbitmq-cluster-operator
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "rabbitmq_operator_staging" {
  metadata {
    name      = "rabbitmq-cluster-operator"
    namespace = kubernetes_namespace.rabbitmq_operator_staging.metadata[0].name

    labels = {
      "app.kubernetes.io/component" = "rabbitmq-operator"
      "app.kubernetes.io/name"      = "rabbitmq-cluster-operator"
      "app.kubernetes.io/part-of"   = "rabbitmq"
    }
  }
}

# -----------------------------------------------------------------------------
# ROLE: Leader Election (namespace-scoped)
# -----------------------------------------------------------------------------

resource "kubernetes_role" "rabbitmq_leader_election_staging" {
  metadata {
    name      = "rabbitmq-cluster-leader-election-role"
    namespace = kubernetes_namespace.rabbitmq_operator_staging.metadata[0].name

    labels = {
      "app.kubernetes.io/component" = "rabbitmq-operator"
      "app.kubernetes.io/name"      = "rabbitmq-cluster-operator"
      "app.kubernetes.io/part-of"   = "rabbitmq"
    }
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create"]
  }
}

# -----------------------------------------------------------------------------
# ROLEBINDING: Leader Election
# -----------------------------------------------------------------------------

resource "kubernetes_role_binding" "rabbitmq_leader_election_staging" {
  metadata {
    name      = "rabbitmq-cluster-leader-election-rolebinding"
    namespace = kubernetes_namespace.rabbitmq_operator_staging.metadata[0].name

    labels = {
      "app.kubernetes.io/component" = "rabbitmq-operator"
      "app.kubernetes.io/name"      = "rabbitmq-cluster-operator"
      "app.kubernetes.io/part-of"   = "rabbitmq"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.rabbitmq_leader_election_staging.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.rabbitmq_operator_staging.metadata[0].name
    namespace = kubernetes_namespace.rabbitmq_operator_staging.metadata[0].name
  }
}

# -----------------------------------------------------------------------------
# CLUSTERROLEBINDING: Operator Permissions (reuse existing ClusterRole)
# -----------------------------------------------------------------------------
# The ClusterRole "rabbitmq-cluster-operator-role" already exists (cluster-wide)
# We just need to bind the new ServiceAccount to it

resource "kubernetes_cluster_role_binding" "rabbitmq_operator_staging" {
  metadata {
    name = "rabbitmq-cluster-operator-staging"

    labels = {
      "app.kubernetes.io/component" = "rabbitmq-operator"
      "app.kubernetes.io/name"      = "rabbitmq-cluster-operator"
      "app.kubernetes.io/part-of"   = "rabbitmq"
      "migration-wave"              = "wave2"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "rabbitmq-cluster-operator-role" # Existing ClusterRole (from CRD installation)
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.rabbitmq_operator_staging.metadata[0].name
    namespace = kubernetes_namespace.rabbitmq_operator_staging.metadata[0].name
  }
}

# -----------------------------------------------------------------------------
# DEPLOYMENT: RabbitMQ Cluster Operator
# -----------------------------------------------------------------------------

resource "kubernetes_deployment" "rabbitmq_operator_staging" {
  metadata {
    name      = "rabbitmq-cluster-operator"
    namespace = kubernetes_namespace.rabbitmq_operator_staging.metadata[0].name

    labels = {
      "app.kubernetes.io/component" = "rabbitmq-operator"
      "app.kubernetes.io/name"      = "rabbitmq-cluster-operator"
      "app.kubernetes.io/part-of"   = "rabbitmq"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "rabbitmq-cluster-operator"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/component" = "rabbitmq-operator"
          "app.kubernetes.io/name"      = "rabbitmq-cluster-operator"
          "app.kubernetes.io/part-of"   = "rabbitmq"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.rabbitmq_operator_staging.metadata[0].name

        container {
          name    = "operator"
          image   = "rabbitmqoperator/cluster-operator:2.19.0"
          command = ["/manager"]

          env {
            name = "OPERATOR_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          port {
            container_port = 9782
            name           = "metrics"
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "500Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "500Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
            privileged                = false
            read_only_root_filesystem = true
            run_as_non_root           = true
            run_as_user               = 1000
          }

          liveness_probe {
            http_get {
              path = "/metrics"
              port = 9782
            }
            initial_delay_seconds = 5
          }
        }

        security_context {
          fs_group        = 1000
          run_as_non_root = true
        }

        toleration {
          key      = "node-type"
          operator = "Equal"
          value    = "system"
          effect   = "NoSchedule"
        }
      }
    }
  }

  depends_on = [
    kubernetes_cluster_role_binding.rabbitmq_operator_staging
  ]
}

# -----------------------------------------------------------------------------
# OUTPUTS
# -----------------------------------------------------------------------------

output "rabbitmq_operator_staging" {
  description = "RabbitMQ Operator staging namespace details"
  value = {
    namespace  = kubernetes_namespace.rabbitmq_operator_staging.metadata[0].name
    operator   = "rabbitmq-cluster-operator:2.19.0"
    deployment = kubernetes_deployment.rabbitmq_operator_staging.metadata[0].name
    pattern    = "A+D (Operator + CRDs)"
    status     = "COMPLETED"
    duration   = "<60min"
    crs_managed = [
      "k8s-platform-prod-rabbitmq (data-services)",
    ]
  }
}
