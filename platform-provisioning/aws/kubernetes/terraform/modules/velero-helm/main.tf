# =============================================================================
# Velero Helm Release Module — Main
# Manages ONLY the Velero helm_release.
# IAM/IRSA and S3 lifecycle are managed separately by the velero-dr module.
#
# Chart: vmware-tanzu/velero v8.1.0 → Velero v1.15.0
# IRSA:  credentials.useSecret=false + serviceAccount annotation (EKS IRSA)
# =============================================================================

resource "helm_release" "velero" {
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  version    = var.chart_version
  namespace  = var.namespace

  # Timeout: 300s matches deployed rev 11 (import baseline)
  timeout          = 300
  create_namespace = false

  # -------------------------------------------------------------------------
  # Helm values — mirrors the manually-deployed configuration (rev 11)
  # -------------------------------------------------------------------------
  values = [
    yamlencode({

      # CRD management
      cleanUpCRDs = false
      upgradeCRDs = false

      # Init container: AWS plugin
      initContainers = [
        {
          name            = "velero-plugin-for-aws"
          image           = "velero/velero-plugin-for-aws:${var.velero_plugin_aws_version}"
          imagePullPolicy = "IfNotPresent"
          volumeMounts = [
            {
              mountPath = "/target"
              name      = "plugins"
            }
          ]
        }
      ]

      # Service account — IRSA annotation injected here
      serviceAccount = {
        server = {
          create = true
          name   = "velero-server"
          annotations = {
            "eks.amazonaws.com/role-arn"               = var.irsa_role_arn
            "eks.amazonaws.com/sts-regional-endpoints" = "true"
          }
        }
      }

      # Credentials: IRSA (no Kubernetes secret needed)
      credentials = {
        useSecret = false
      }

      # Core configuration
      configuration = {
        logLevel              = var.log_level
        backupRetentionPeriod = var.backup_retention_period
        features              = var.enable_csi ? "EnableCSI" : ""

        backupStorageLocation = [
          {
            name     = "default"
            provider = "aws"
            bucket   = var.s3_bucket_name
            config = {
              region = var.s3_region
            }
          }
        ]

        volumeSnapshotLocation = [
          {
            name     = "default"
            provider = "aws"
            config = {
              region = var.s3_region
            }
          }
        ]
      }

      # Environment variables for IRSA web identity
      extraEnvVars = {
        AWS_REGION                   = var.s3_region
        AWS_ROLE_ARN                 = var.irsa_role_arn
        AWS_WEB_IDENTITY_TOKEN_FILE  = "/var/run/secrets/eks.amazonaws.com/serviceaccount/token"
        AWS_SDK_LOAD_CONFIG          = "true"
        AWS_STS_REGIONAL_ENDPOINTS   = "regional"
        AWS_EC2_METADATA_DISABLED    = "true"
      }

      # Server resources
      resources = {
        requests = {
          cpu    = "50m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }

      # Node placement
      nodeSelector = var.node_selector

      tolerations = [
        for t in var.tolerations : {
          key      = lookup(t, "key", null)
          operator = t.operator
          value    = lookup(t, "value", null)
          effect   = lookup(t, "effect", null)
        }
      ]

      # Node agent (file-system backup via restic/kopia)
      deployNodeAgent = var.deploy_node_agent

      nodeAgent = {
        podVolumePath = "/var/lib/kubelet/pods"
        privileged    = false
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
        tolerations = [
          {
            operator = "Exists"
          }
        ]
      }

      # Prometheus metrics
      metrics = {
        enabled = var.metrics_enabled
        serviceMonitor = {
          enabled          = var.service_monitor_enabled
          additionalLabels = var.service_monitor_labels
        }
      }

      # No pre-configured schedules (managed via VeleroSchedule CRDs or separate resources)
      schedules = {}
    })
  ]

}
