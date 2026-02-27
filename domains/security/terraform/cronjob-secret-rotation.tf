################################################################################
# CICD-003: Automated Secret Rotation — Kubernetes Resources
# ADR-083: Quarterly Secret Rotation Strategy
# Namespace: vault-system (staging-security-vault)
# Schedule: "0 2 1 */3 *" — quarterly, 2 AM UTC on the 1st day of the quarter
#
# Resources created:
#   - ServiceAccount: secret-rotator
#   - Role: secret-rotator (get/list secrets)
#   - RoleBinding: secret-rotator
#   - ConfigMap: secret-rotation-script (shell script)
#   - ExternalSecret: secret-rotator-vault-token (via ESO)
#   - CronJob: secret-rotator (quarterly execution)
#
# AMBIENTE DESLIGADO — preparado para apply posterior
# terraform apply -target=kubernetes_service_account_v1.secret_rotator
################################################################################

locals {
  rotator_namespace = "staging-security-vault"
  rotator_name      = "secret-rotator"
  rotator_image     = "hashicorp/vault:1.15.0"
  rotator_schedule  = "0 2 1 */3 *"

  # Labels padrão projeto (ADR-048 naming conventions)
  rotator_labels = {
    "app.kubernetes.io/name"       = "secret-rotator"
    "app.kubernetes.io/component"  = "security"
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "platform-security"
    "domain"                       = "platform"
    "owner"                        = "platform-team"
    "environment"                  = "staging"
    "demand"                       = "CICD-003"
  }
}

# ------------------------------------------------------------------------------
# ServiceAccount: secret-rotator
# Used by the CronJob pod to mount the Vault token secret
# ------------------------------------------------------------------------------

resource "kubernetes_service_account_v1" "secret_rotator" {
  metadata {
    name      = local.rotator_name
    namespace = local.rotator_namespace
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
# Minimal permissions: get/list Kubernetes secrets in the vault-system namespace.
# The actual Vault writes happen via Vault API (not K8s API), so no secret write
# permission is needed here.
# ------------------------------------------------------------------------------

resource "kubernetes_role_v1" "secret_rotator" {
  metadata {
    name      = local.rotator_name
    namespace = local.rotator_namespace
    labels    = local.rotator_labels
    annotations = {
      "description" = "Minimal RBAC for secret-rotator CronJob (CICD-003)"
    }
  }

  # Read Vault token from the K8s Secret synced by ESO
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list"]
  }

  # Read ConfigMap that contains the rotation script
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
    namespace = local.rotator_namespace
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
    namespace = local.rotator_namespace
  }
}

# ------------------------------------------------------------------------------
# ConfigMap: secret-rotation-script
# Mounts the rotate-secrets.sh script into the CronJob container.
# The script file is kept in scripts/vault/rotate-secrets.sh (source of truth).
# This ConfigMap is generated from the file content at terraform apply time.
# ------------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "secret_rotation_script" {
  metadata {
    name      = "secret-rotation-script"
    namespace = local.rotator_namespace
    labels    = local.rotator_labels
    annotations = {
      "description" = "Shell script for quarterly secret rotation (CICD-003)"
      "source"      = "scripts/vault/rotate-secrets.sh"
    }
  }

  data = {
    "rotate-secrets.sh" = file("${path.module}/../../../scripts/vault/rotate-secrets.sh")
  }
}

# ------------------------------------------------------------------------------
# ExternalSecret: secret-rotator-vault-token
# ESO syncs the Vault service token from Vault KV into a K8s Secret.
# The Vault token is stored at: secret/secret-rotator/token
# Policy: secret-rotator (vault_policies/secret-rotator.hcl)
# ------------------------------------------------------------------------------

resource "kubernetes_manifest" "secret_rotator_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "secret-rotator-vault-token"
      namespace = local.rotator_namespace
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
# ESO syncs RDS admin password from Vault (needed for ALTER USER statements)
# Stored at: secret/postgresql-admin/password
# ------------------------------------------------------------------------------

resource "kubernetes_manifest" "secret_rotator_rds_admin" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "secret-rotator-rds-admin"
      namespace = local.rotator_namespace
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
# Quarterly execution at 02:00 UTC on 1st of January, April, July, October
# restartPolicy: OnFailure — retries up to 3 times before failing the Job
# ------------------------------------------------------------------------------

resource "kubernetes_cron_job_v1" "secret_rotator" {
  metadata {
    name      = local.rotator_name
    namespace = local.rotator_namespace
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
    concurrency_policy            = "Forbid" # Never run two rotations in parallel
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3
    starting_deadline_seconds     = 600 # Abort if not started within 10 min

    job_template {
      metadata {
        labels = local.rotator_labels
      }

      spec {
        backoff_limit              = 2     # Max 2 retries before marking failed
        active_deadline_seconds    = 1800  # Max 30 min runtime (safety net)
        ttl_seconds_after_finished = 86400 # Clean up finished jobs after 24h

        template {
          metadata {
            labels = local.rotator_labels
            annotations = {
              "vault.hashicorp.com/agent-inject" = "false" # Not using Vault Agent sidecar
            }
          }

          spec {
            restart_policy       = "OnFailure"
            service_account_name = kubernetes_service_account_v1.secret_rotator.metadata[0].name

            # Security: run as non-root
            security_context {
              run_as_non_root = true
              run_as_user     = 100 # Vault image default UID
              run_as_group    = 1000
              fs_group        = 1000
            }

            container {
              name  = "secret-rotator"
              image = local.rotator_image

              command = ["/bin/sh", "/scripts/rotate-secrets.sh"]

              # --- Environment: Vault connection ---
              env {
                name  = "VAULT_ADDR"
                value = "http://vault.staging-security-vault.svc.cluster.local:8200"
              }

              env {
                name  = "VAULT_SKIP_VERIFY"
                value = "false"
              }

              # Vault token from ESO-synced secret
              env {
                name = "VAULT_TOKEN"
                value_from {
                  secret_key_ref {
                    name = "secret-rotator-vault-token"
                    key  = "VAULT_TOKEN"
                  }
                }
              }

              # --- Environment: RDS connection ---
              env {
                name  = "PGHOST"
                value = "k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com"
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

              # --- Environment: Keycloak connection ---
              env {
                name  = "KEYCLOAK_URL"
                value = "http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local/auth"
              }

              env {
                name  = "KEYCLOAK_REALM"
                value = "platform"
              }

              # --- Environment: Rotation configuration ---
              env {
                name  = "DRY_RUN"
                value = "false" # Set to "true" to test without applying changes
              }

              env {
                name  = "ROTATION_GRACE_PERIOD_HOURS"
                value = "24" # ESO re-sync window before old secrets expire
              }

              env {
                name  = "LOG_LEVEL"
                value = "INFO" # DEBUG for troubleshooting
              }

              # --- Resource limits ---
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

              # Security: read-only root filesystem
              security_context {
                read_only_root_filesystem  = false # Vault CLI writes temp files
                allow_privilege_escalation = false
                capabilities {
                  drop = ["ALL"]
                }
              }

              # Mount rotation script from ConfigMap
              volume_mount {
                name       = "rotation-script"
                mount_path = "/scripts"
                read_only  = true
              }

              # Writable temp directory for Vault CLI temp files
              volume_mount {
                name       = "tmp"
                mount_path = "/tmp"
                read_only  = false
              }
            } # end container

            # Script volume (from ConfigMap)
            volume {
              name = "rotation-script"
              config_map {
                name         = kubernetes_config_map_v1.secret_rotation_script.metadata[0].name
                default_mode = "0755"
              }
            }

            # Ephemeral tmp volume
            volume {
              name = "tmp"
              empty_dir {}
            }

          } # end spec (pod)
        }   # end template
      }     # end spec (job)
    }       # end job_template
  }         # end spec (cronjob)

  depends_on = [
    kubernetes_service_account_v1.secret_rotator,
    kubernetes_role_binding_v1.secret_rotator,
    kubernetes_config_map_v1.secret_rotation_script,
    kubernetes_manifest.secret_rotator_external_secret,
    kubernetes_manifest.secret_rotator_rds_admin,
  ]
}

################################################################################
# Outputs
################################################################################

output "secret_rotator_service_account" {
  description = "ServiceAccount name for the secret rotator"
  value       = kubernetes_service_account_v1.secret_rotator.metadata[0].name
}

output "secret_rotator_cronjob_name" {
  description = "CronJob name for manual trigger reference"
  value       = kubernetes_cron_job_v1.secret_rotator.metadata[0].name
}

output "secret_rotator_namespace" {
  description = "Namespace where secret rotator runs"
  value       = local.rotator_namespace
}

output "secret_rotator_schedule" {
  description = "CronJob schedule expression"
  value       = local.rotator_schedule
}

output "manual_trigger_command" {
  description = "Command to trigger rotation manually (dry-run first)"
  value = join("\n", [
    "# Dry-run (safe — no changes):",
    "kubectl create job --from=cronjob/secret-rotator secret-rotator-manual-$(date +%Y%m%d) -n ${local.rotator_namespace}",
    "# Override DRY_RUN=true for dry-run testing:",
    "kubectl set env cronjob/secret-rotator DRY_RUN=true -n ${local.rotator_namespace}",
  ])
}
