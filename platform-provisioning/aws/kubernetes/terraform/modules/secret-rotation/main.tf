################################################################################
# Module: secret-rotation
# CICD-003: Automated Secret Rotation — Kubernetes Resources
# ADR-083: Quarterly Secret Rotation Strategy
#
# Resources created:
#   - ServiceAccount: secret-rotator
#   - Role: secret-rotator (get/list secrets)
#   - RoleBinding: secret-rotator
#   - ConfigMap: secret-rotation-script (shell script)
#   - ExternalSecret: secret-rotator-vault-token (via ESO)
#   - ExternalSecret: secret-rotator-rds-admin (via ESO)
#   - CronJob: secret-rotator (quarterly execution)
################################################################################

locals {
  rotator_name     = "secret-rotator"
  rotator_schedule = var.rotation_schedule

  rotator_labels = {
    "app.kubernetes.io/name"       = "secret-rotator"
    "app.kubernetes.io/component"  = "security"
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "platform-security"
    "domain"                       = "security"
    "owner"                        = "platform-team"
    "environment"                  = var.environment
    "demand"                       = "CICD-003"
  }
}

# ------------------------------------------------------------------------------
# ServiceAccount: secret-rotator
# ------------------------------------------------------------------------------
resource "kubernetes_service_account_v1" "secret_rotator" {
  metadata {
    name      = local.rotator_name
    namespace = var.namespace
    labels    = local.rotator_labels
    annotations = {
      "description"       = "ServiceAccount for quarterly automated secret rotation (CICD-003)"
      "adr"               = "ADR-083"
      "rotation-schedule" = local.rotator_schedule
    }
  }
}

# ------------------------------------------------------------------------------
# Role: secret-rotator
# ------------------------------------------------------------------------------
resource "kubernetes_role_v1" "secret_rotator" {
  metadata {
    name      = local.rotator_name
    namespace = var.namespace
    labels    = local.rotator_labels
    annotations = {
      "description" = "Minimal RBAC for secret-rotator CronJob (CICD-003)"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list"]
  }
}

# ------------------------------------------------------------------------------
# RoleBinding: secret-rotator
# ------------------------------------------------------------------------------
resource "kubernetes_role_binding_v1" "secret_rotator" {
  metadata {
    name      = local.rotator_name
    namespace = var.namespace
    labels    = local.rotator_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.secret_rotator.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.secret_rotator.metadata[0].name
    namespace = var.namespace
  }
}

# ------------------------------------------------------------------------------
# ConfigMap: secret-rotation-script
# ------------------------------------------------------------------------------
resource "kubernetes_config_map_v1" "secret_rotation_script" {
  metadata {
    name      = "secret-rotation-script"
    namespace = var.namespace
    labels    = local.rotator_labels
    annotations = {
      "description" = "Shell script for quarterly secret rotation (CICD-003)"
      "source"      = "scripts/vault/rotate-secrets.sh"
    }
  }

  data = {
    "rotate-secrets.sh" = file("${path.module}/../../../../../../scripts/vault/rotate-secrets.sh")
  }
}

# ------------------------------------------------------------------------------
# ExternalSecret: secret-rotator-vault-token
# ------------------------------------------------------------------------------
resource "kubernetes_manifest" "secret_rotator_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "secret-rotator-vault-token"
      namespace = var.namespace
      labels    = local.rotator_labels
      annotations = {
        "description" = "Vault service token for secret-rotator CronJob (CICD-003)"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "secret-rotator-vault-token"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "VAULT_TOKEN"
          remoteRef = {
            key      = "secret/secret-rotator/token"
            property = "token"
          }
        }
      ]
    }
  }
}

# ------------------------------------------------------------------------------
# ExternalSecret: secret-rotator-rds-admin
# ------------------------------------------------------------------------------
resource "kubernetes_manifest" "secret_rotator_rds_admin" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "secret-rotator-rds-admin"
      namespace = var.namespace
      labels    = local.rotator_labels
      annotations = {
        "description" = "RDS admin credentials for ALTER USER during secret rotation (CICD-003)"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "secret-rotator-rds-admin"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "PGPASSWORD"
          remoteRef = {
            key      = "secret/postgresql-admin/password"
            property = "password"
          }
        },
        {
          secretKey = "PGUSER"
          remoteRef = {
            key      = "secret/postgresql-admin/password"
            property = "username"
          }
        }
      ]
    }
  }
}

# ------------------------------------------------------------------------------
# CronJob: secret-rotator
# Quarterly: "0 2 1 */3 *" — 02:00 UTC on Jan 1, Apr 1, Jul 1, Oct 1
# ------------------------------------------------------------------------------
resource "kubernetes_cron_job_v1" "secret_rotator" {
  metadata {
    name      = local.rotator_name
    namespace = var.namespace
    labels    = local.rotator_labels
    annotations = {
      "description"    = "Quarterly automated secret rotation for platform credentials (CICD-003)"
      "adr"            = "ADR-083"
      "schedule"       = local.rotator_schedule
      "schedule-human" = "Quarterly: 02:00 UTC on Jan 1, Apr 1, Jul 1, Oct 1"
      "next-rotation"  = "2026-04-01T02:00:00Z"
    }
  }

  spec {
    schedule                      = local.rotator_schedule
    timezone                      = "UTC"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3
    starting_deadline_seconds     = 600

    job_template {
      metadata {
        labels = local.rotator_labels
      }

      spec {
        backoff_limit              = 2
        active_deadline_seconds    = 1800
        ttl_seconds_after_finished = 86400

        template {
          metadata {
            labels = local.rotator_labels
            annotations = {
              "vault.hashicorp.com/agent-inject" = "false"
            }
          }

          spec {
            restart_policy       = "OnFailure"
            service_account_name = kubernetes_service_account_v1.secret_rotator.metadata[0].name

            security_context {
              run_as_non_root = true
              run_as_user     = 100
              run_as_group    = 1000
              fs_group        = 1000
            }

            container {
              name  = "secret-rotator"
              image = var.rotator_image

              command = ["/bin/sh", "/scripts/rotate-secrets.sh"]

              env {
                name  = "VAULT_ADDR"
                value = var.vault_addr
              }

              env {
                name  = "VAULT_SKIP_VERIFY"
                value = "false"
              }

              env {
                name = "VAULT_TOKEN"
                value_from {
                  secret_key_ref {
                    name = "secret-rotator-vault-token"
                    key  = "VAULT_TOKEN"
                  }
                }
              }

              env {
                name  = "PGHOST"
                value = var.rds_endpoint
              }

              env {
                name  = "PGPORT"
                value = "5432"
              }

              env {
                name  = "PGSSLMODE"
                value = "require"
              }

              env {
                name = "PGPASSWORD"
                value_from {
                  secret_key_ref {
                    name = "secret-rotator-rds-admin"
                    key  = "PGPASSWORD"
                  }
                }
              }

              env {
                name = "PGUSER"
                value_from {
                  secret_key_ref {
                    name = "secret-rotator-rds-admin"
                    key  = "PGUSER"
                  }
                }
              }

              env {
                name  = "KEYCLOAK_URL"
                value = var.keycloak_url
              }

              env {
                name  = "KEYCLOAK_REALM"
                value = var.keycloak_realm
              }

              env {
                name  = "DRY_RUN"
                value = var.dry_run ? "true" : "false"
              }

              env {
                name  = "ROTATION_GRACE_PERIOD_HOURS"
                value = tostring(var.rotation_grace_period_hours)
              }

              env {
                name  = "LOG_LEVEL"
                value = var.log_level
              }

              resources {
                requests = {
                  cpu    = "50m"
                  memory = "64Mi"
                }
                limits = {
                  cpu    = "200m"
                  memory = "256Mi"
                }
              }

              security_context {
                read_only_root_filesystem  = false
                allow_privilege_escalation = false
                capabilities {
                  drop = ["ALL"]
                }
              }

              volume_mount {
                name       = "rotation-script"
                mount_path = "/scripts"
                read_only  = true
              }

              volume_mount {
                name       = "tmp"
                mount_path = "/tmp"
                read_only  = false
              }
            }

            volume {
              name = "rotation-script"
              config_map {
                name         = kubernetes_config_map_v1.secret_rotation_script.metadata[0].name
                default_mode = "0755"
              }
            }

            volume {
              name = "tmp"
              empty_dir {}
            }

          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account_v1.secret_rotator,
    kubernetes_role_binding_v1.secret_rotator,
    kubernetes_config_map_v1.secret_rotation_script,
    kubernetes_manifest.secret_rotator_external_secret,
    kubernetes_manifest.secret_rotator_rds_admin,
  ]
}
