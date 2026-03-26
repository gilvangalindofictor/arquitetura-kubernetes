# =============================================================================
# Keycloak Backup Automation (TASK-003)
# Daily backup of Keycloak realms (JSON export) to S3
# RPO: <24h | RTO: <5min
# =============================================================================

# -----------------------------------------------------------------------------
# IAM Role for Keycloak Backup Service Account (IRSA)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "keycloak_backup_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.eks.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:staging-platform-keycloak:keycloak-backup"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "keycloak_backup" {
  name               = "${local.cluster_name}-keycloak-backup-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.keycloak_backup_assume_role.json

  tags = merge(local.common_tags, {
    Name    = "Keycloak Backup IRSA Role"
    Service = "Keycloak"
    Purpose = "Backup-Automation"
  })
}

resource "aws_iam_role_policy_attachment" "keycloak_backup_s3" {
  role       = aws_iam_role.keycloak_backup.name
  policy_arn = module.s3_buckets_staging.keycloak_backup_s3_policy_arn
}

# -----------------------------------------------------------------------------
# Kubernetes ServiceAccount with IRSA annotation
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "keycloak_backup" {
  metadata {
    name      = "keycloak-backup"
    namespace = "staging-platform-keycloak"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.keycloak_backup.arn
    }

    labels = merge(local.common_tags, {
      "app.kubernetes.io/name"     = "keycloak-backup"
      "app.kubernetes.io/instance" = "keycloak-backup-${local.environment}"
    })
  }
}

# -----------------------------------------------------------------------------
# Keycloak Backup Script (ConfigMap)
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "keycloak_backup_script" {
  metadata {
    name      = "keycloak-backup-script"
    namespace = "staging-platform-keycloak"

    labels = merge(local.common_tags, {
      "app.kubernetes.io/name" = "keycloak-backup"
    })
  }

  data = {
    "backup.sh" = <<-EOT
      #!/bin/sh
      set -eu

      # Configuration
      KEYCLOAK_URL="$${KEYCLOAK_URL:-http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local}"
      KEYCLOAK_REALM="$${KEYCLOAK_REALM:-master}"
      KEYCLOAK_USER="$${KEYCLOAK_USER:-admin}"
      KEYCLOAK_PASSWORD="$${KEYCLOAK_PASSWORD}"
      S3_BUCKET="$${S3_BUCKET:-${module.s3_buckets_staging.keycloak_backups_bucket_name}}"
      BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
      BACKUP_DIR="/tmp/keycloak-backup-$${BACKUP_DATE}"

      echo "🔐 Keycloak Backup started at $${BACKUP_DATE}"

      # 1. Authenticate and get access token
      # NOTE 2026-03-12: esta instância KC 26.5.1 usa http.relativePath=/auth nos helm values
      # → TODOS os endpoints requerem prefixo /auth/ (não foi removido nesta implantação)
      echo "  → Authenticating with Keycloak..."
      TOKEN=$(curl -s -X POST "$${KEYCLOAK_URL}/auth/realms/$${KEYCLOAK_REALM}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=$${KEYCLOAK_USER}" \
        -d "password=$${KEYCLOAK_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" \
        | jq -r '.access_token')

      if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        echo "❌ Authentication failed"
        exit 1
      fi

      # 2. Get list of realms
      echo "  → Fetching realms list..."
      REALMS=$(curl -s -X GET "$${KEYCLOAK_URL}/auth/admin/realms" \
        -H "Authorization: Bearer $${TOKEN}" \
        | jq -r '.[].realm')

      mkdir -p "$${BACKUP_DIR}"

      # 3. Export each realm
      for REALM in $REALMS; do
        echo "  → Exporting realm: $${REALM}"

        curl -s -X POST "$${KEYCLOAK_URL}/auth/admin/realms/$${REALM}/partial-export?exportClients=true&exportGroupsAndRoles=true" \
          -H "Authorization: Bearer $${TOKEN}" \
          -H "Content-Type: application/json" \
          > "$${BACKUP_DIR}/$${REALM}.json"

        # Validate JSON
        if jq empty "$${BACKUP_DIR}/$${REALM}.json" 2>/dev/null; then
          SIZE=$(du -h "$${BACKUP_DIR}/$${REALM}.json" | cut -f1)
          echo "    ✓ $${REALM}.json ($${SIZE})"
        else
          echo "    ✗ $${REALM}.json - INVALID JSON"
          exit 1
        fi
      done

      # 4. Create metadata file
      cat > "$${BACKUP_DIR}/metadata.json" <<EOF
      {
        "backup_date": "$${BACKUP_DATE}",
        "keycloak_version": "$(curl -s $${KEYCLOAK_URL}/auth/realms/master | jq -r '.realm // "unknown"')",
        "realms": $(echo $REALMS | jq -R 'split(" ")'),
        "hostname": "$(hostname)",
        "s3_bucket": "$${S3_BUCKET}"
      }
      EOF

      # 5. Create tarball
      echo "  → Creating archive..."
      TARBALL="/tmp/keycloak-backup-$${BACKUP_DATE}.tar.gz"
      tar -czf "$${TARBALL}" -C /tmp "keycloak-backup-$${BACKUP_DATE}"

      # 6. Upload to S3
      echo "  → Uploading to S3..."
      aws s3 cp "$${TARBALL}" "s3://$${S3_BUCKET}/backups/keycloak-backup-$${BACKUP_DATE}.tar.gz" \
        --storage-class STANDARD \
        --metadata "realm-count=$(echo $REALMS | wc -w),backup-date=$${BACKUP_DATE}"

      # 7. Verify upload
      if aws s3 ls "s3://$${S3_BUCKET}/backups/keycloak-backup-$${BACKUP_DATE}.tar.gz" >/dev/null 2>&1; then
        SIZE=$(du -h "$${TARBALL}" | cut -f1)
        echo "✅ Backup completed successfully ($${SIZE})"
        echo "   S3 URI: s3://$${S3_BUCKET}/backups/keycloak-backup-$${BACKUP_DATE}.tar.gz"
      else
        echo "❌ S3 upload verification failed"
        exit 1
      fi

      # 8. Cleanup
      rm -rf "$${BACKUP_DIR}" "$${TARBALL}"

      echo "🎉 Backup finished at $(date +%Y%m%d-%H%M%S)"
    EOT
  }
}

# -----------------------------------------------------------------------------
# CronJob - Daily Keycloak Backup (11:30 UTC / 08:30 BRT)
# GAP-KEYCLOAK-SCHED: was 02:00 UTC — cluster offline on weekends until 10:30 UTC
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "keycloak_backup_cronjob" {
  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"

    metadata = {
      name      = "keycloak-backup"
      namespace = "staging-platform-keycloak"

      labels = merge(local.common_tags, {
        "app.kubernetes.io/name"     = "keycloak-backup"
        "app.kubernetes.io/instance" = "keycloak-backup-${local.environment}"
        domain                       = "security"
        environment                  = local.environment
        owner                        = "platform-team"
      })
    }

    spec = {
      # GAP-KEYCLOAK-SCHED (2026-03-21): moved from 02:00 UTC to 11:30 UTC
      # Cluster shuts down Fri 23:00 UTC and only starts Mon 10:30 UTC (or manually).
      # 02:00 UTC Saturday always failed (cluster stopped). 11:30 UTC = safely after 10:30 UTC startup.
      schedule                   = "30 11 * * *"
      successfulJobsHistoryLimit = 3
      failedJobsHistoryLimit     = 3
      concurrencyPolicy          = "Forbid"

      jobTemplate = {
        metadata = {
          labels = {
            "app.kubernetes.io/name"    = "keycloak-backup"
            "app.kubernetes.io/part-of" = "keycloak"
            domain                      = "security"
            environment                 = local.environment
            owner                       = "platform-team"
          }
        }

        spec = {
          template = {
            metadata = {
              labels = {
                app                         = "keycloak-backup"
                "app.kubernetes.io/name"    = "keycloak-backup"
                "app.kubernetes.io/part-of" = "keycloak"
                domain                      = "security"
                environment                 = local.environment
                owner                       = "platform-team"
              }
            }

            spec = {
              serviceAccountName = kubernetes_service_account.keycloak_backup.metadata[0].name
              restartPolicy      = "OnFailure"

              containers = [
                {
                  name            = "backup"
                  image           = "python:3.11-alpine"
                  imagePullPolicy = "IfNotPresent"
                  command         = ["/bin/sh", "-c", "apk add --no-cache curl jq tar gzip aws-cli && /bin/sh /scripts/backup.sh"]

                  env = [
                    {
                      name  = "KEYCLOAK_URL"
                      value = "http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local"
                    },
                    {
                      name  = "KEYCLOAK_REALM"
                      value = "master"
                    },
                    {
                      name  = "KEYCLOAK_USER"
                      value = "admin"
                    },
                    {
                      name = "KEYCLOAK_PASSWORD"
                      valueFrom = {
                        secretKeyRef = {
                          name = "keycloak-admin-credentials"
                          key  = "password"
                        }
                      }
                    },
                    {
                      name  = "S3_BUCKET"
                      value = module.s3_buckets_staging.keycloak_backups_bucket_name
                    },
                    {
                      name  = "AWS_REGION"
                      value = var.aws_region
                    }
                  ]

                  resources = {
                    requests = {
                      memory = "256Mi"
                      cpu    = "100m"
                    }
                    limits = {
                      memory = "512Mi"
                      cpu    = "500m"
                    }
                  }

                  securityContext = {
                    allowPrivilegeEscalation = false
                    readOnlyRootFilesystem   = false
                    capabilities = {
                      drop = ["ALL"]
                    }
                  }

                  volumeMounts = [
                    {
                      name      = "tmp"
                      mountPath = "/tmp"
                    },
                    {
                      name      = "scripts"
                      mountPath = "/scripts"
                    }
                  ]
                }
              ]

              volumes = [
                {
                  name     = "tmp"
                  emptyDir = {}
                },
                {
                  name = "scripts"
                  configMap = {
                    name        = kubernetes_config_map.keycloak_backup_script.metadata[0].name
                    defaultMode = 493 # 0755 in decimal
                  }
                }
              ]
            }
          }
        }
      }
    }
  }

  field_manager {
    force_conflicts = true
  }
}

# -----------------------------------------------------------------------------
# PrometheusRule - Alerting for Backup Failures
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "keycloak_backup_prometheusrule" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "keycloak-backup"
      namespace = "staging-platform-keycloak"

      labels = merge(local.common_tags, {
        "app.kubernetes.io/name" = "keycloak-backup"
        prometheus               = "kube-prometheus"
      })
    }

    spec = {
      groups = [
        {
          name     = "keycloak-backup"
          interval = "5m"

          rules = [
            {
              alert = "KeycloakBackupFailed"
              expr  = "kube_job_status_failed{namespace=\"staging-platform-keycloak\",job_name=~\"keycloak-backup.*\"} > 0"
              for   = "5m"

              labels = {
                severity = "critical"
                service  = "keycloak"
              }

              annotations = {
                summary     = "Keycloak backup failed"
                description = "Keycloak backup job {{ $labels.job_name }} has failed in namespace {{ $labels.namespace }}"
              }
            },
            {
              alert = "KeycloakBackupMissing"
              expr  = "(time() - kube_job_status_completion_time{namespace=\"staging-platform-keycloak\",job_name=~\"keycloak-backup.*\"}) > 86400"
              for   = "1h"

              labels = {
                severity = "warning"
                service  = "keycloak"
              }

              annotations = {
                summary     = "Keycloak backup missing"
                description = "No successful Keycloak backup in last 24 hours"
              }
            }
          ]
        }
      ]
    }
  }

  field_manager {
    force_conflicts = true
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "keycloak_backup_bucket" {
  description = "S3 bucket for Keycloak backups"
  value       = module.s3_buckets_staging.keycloak_backups_bucket_name
}

output "keycloak_backup_role_arn" {
  description = "IAM role ARN for Keycloak backup ServiceAccount"
  value       = aws_iam_role.keycloak_backup.arn
}
