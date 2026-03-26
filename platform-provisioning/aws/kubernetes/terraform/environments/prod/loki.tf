# -----------------------------------------------------------------------------
# loki.tf — Loki logging stack (prod) — Helm + SA only
# GAP-LOKI-PROD-TF-001: adoção TF do helm manual instalado em 2026-03-21
# Chart: loki-6.53.0 | App: v3.6.5 | Namespace: prod-observability-monitoring
#
# ARQUITETURA DE RECURSOS (prod vs staging):
#   - S3 bucket prod:   k8s-platform-loki-prod-891377105802
#     → ARN já incluído em staging/loki.tf (additional_s3_bucket_arns)
#     → bucket criado manualmente em 2026-03-21 (importar separado se necessário)
#   - IAM Role/Policy:  LokiS3Role-k8s-platform-prod / LokiS3Policy-k8s-platform-prod
#     → gerenciados em staging/loki.tf (cluster compartilhado, anti-pattern GAP-PROD-VAULT-001)
#     → trust policy já inclui prod-observability-monitoring:loki-prod
#       via staging/loki.tf additional_irsa_service_accounts
#   - helm_release:     prod-observability-monitoring/loki  ← gerenciado AQUI
#   - kubernetes_sa:    prod-observability-monitoring/loki  ← gerenciado AQUI
#
# Recursos importados:
#   - helm_release.loki_prod                   (prod-observability-monitoring/loki)
#   - kubernetes_service_account.loki_prod     (prod-observability-monitoring/loki)
#
# NOTA: Se IAM Role/Policy prod forem isoladas no futuro (GAP-PROD-VAULT-001),
#       criar aws_iam_role.loki_prod + aws_iam_policy.loki_prod_s3 aqui e
#       remover additional_irsa_service_accounts de staging/loki.tf.
# -----------------------------------------------------------------------------

locals {
  loki_prod_namespace          = "prod-observability-monitoring"
  loki_prod_service_account    = "loki-prod"
  loki_prod_iam_role_arn       = "arn:aws:iam::891377105802:role/LokiS3Role-k8s-platform-prod"
  loki_prod_s3_bucket          = "k8s-platform-loki-prod-891377105802"
  loki_prod_chart_version      = "6.53.0"
}

# -----------------------------------------------------------------------------
# Kubernetes Service Account — prod-observability-monitoring/loki
# IRSA annotation aponta para a mesma role gerenciada em staging/loki.tf
# (trust policy inclui system:serviceaccount:prod-observability-monitoring:loki)
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "loki_prod" {
  metadata {
    name      = local.loki_prod_service_account
    namespace = local.loki_prod_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = local.loki_prod_iam_role_arn
    }

    labels = {
      "app.kubernetes.io/name"       = "loki"
      "app.kubernetes.io/component"  = "logging"
      "app.kubernetes.io/managed-by" = "terraform"
      # Corporate labels (ADR-048) — adicionadas pelo Helm commonLabels; declaradas aqui para zero drift
      "app.kubernetes.io/part-of"    = "k8s-platform"
      "domain"                       = "platform"
      "environment"                  = "prod"
      "owner"                        = "platform-team"
    }
  }
}

# -----------------------------------------------------------------------------
# Helm Release — Loki prod
# Importado de: prod-observability-monitoring/loki (helm rev manual 2026-03-21)
# Pinned: loki-6.53.0 (app v3.6.5)
# lifecycle.ignore_changes = [values] REMOVIDO intencionalmente — TF é source-of-truth
# ATENÇÃO: terraform apply vai reconciliar drift vs values ativos no cluster.
#          Validar com: helm get values loki -n prod-observability-monitoring
# -----------------------------------------------------------------------------

resource "helm_release" "loki_prod" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = local.loki_prod_chart_version
  namespace  = local.loki_prod_namespace
  timeout    = 900 # 15min — prevent context deadline exceeded on large WAL flushes

  # ---------------------------------------------------------------------------
  # Deployment Mode: SimpleScalable
  # ---------------------------------------------------------------------------
  set {
    name  = "deploymentMode"
    value = "SimpleScalable"
  }

  # ---------------------------------------------------------------------------
  # Global Corporate Labels (ADR-048 — Kyverno Compliance)
  # ---------------------------------------------------------------------------
  set {
    name  = "global.podLabels.domain"
    value = "operations"
  }

  set {
    name  = "global.podLabels.owner"
    value = "platform-team"
  }

  set {
    name  = "global.podLabels.environment"
    value = "production"
  }

  set {
    name  = "global.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
  }

  # ---------------------------------------------------------------------------
  # Loki Configuration
  # ---------------------------------------------------------------------------
  set {
    name  = "loki.auth_enabled"
    value = "false"
  }

  set {
    name  = "loki.commonConfig.replication_factor"
    value = "2"
  }

  set {
    name  = "loki.commonConfig.path_prefix"
    value = "/var/loki"
  }

  # Storage configuration (S3 — bucket prod dedicado)
  set {
    name  = "loki.storage.type"
    value = "s3"
  }

  set {
    name  = "loki.storage.bucketNames.chunks"
    value = local.loki_prod_s3_bucket
  }

  set {
    name  = "loki.storage.bucketNames.ruler"
    value = local.loki_prod_s3_bucket
  }

  set {
    name  = "loki.storage.bucketNames.admin"
    value = local.loki_prod_s3_bucket
  }

  set {
    name  = "loki.storage.s3.region"
    value = var.aws_region
  }

  # Schema configuration
  set {
    name  = "loki.schemaConfig.configs[0].from"
    value = "2024-01-01"
  }

  set {
    name  = "loki.schemaConfig.configs[0].store"
    value = "tsdb"
  }

  set {
    name  = "loki.schemaConfig.configs[0].object_store"
    value = "s3"
  }

  set {
    name  = "loki.schemaConfig.configs[0].schema"
    value = "v13"
  }

  set {
    name  = "loki.schemaConfig.configs[0].index.prefix"
    value = "loki_index_"
  }

  set {
    name  = "loki.schemaConfig.configs[0].index.period"
    value = "24h"
  }

  # Retention: 30 dias prod (720h) — alinhado com terraform.tfvars log retention policy
  set {
    name  = "loki.limits_config.retention_period"
    value = "720h"
  }

  set {
    name  = "loki.limits_config.max_query_length"
    value = "744h" # retention + 1 dia
  }

  # Compactor configuration
  set {
    name  = "loki.compactor.working_directory"
    value = "/var/loki/compactor"
  }

  set {
    name  = "loki.compactor.delete_request_store"
    value = "s3"
  }

  set {
    name  = "loki.compactor.compaction_interval"
    value = "10m"
  }

  set {
    name  = "loki.compactor.retention_enabled"
    value = "true"
  }

  set {
    name  = "loki.compactor.retention_delete_delay"
    value = "2h"
  }

  # ---------------------------------------------------------------------------
  # Read Component (Query Path) — prod: 2 replicas (HA)
  # ---------------------------------------------------------------------------
  set {
    name  = "read.replicas"
    value = "2"
  }

  set {
    name  = "read.podLabels.domain"
    value = "operations"
  }

  set {
    name  = "read.podLabels.owner"
    value = "platform-team"
  }

  set {
    name  = "read.podLabels.environment"
    value = "production"
  }

  set {
    name  = "read.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
  }

  set {
    name  = "read.nodeSelector.eks\\.amazonaws\\.com/nodegroup"
    value = "workloads"
  }

  set {
    name  = "read.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "read.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "read.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "read.resources.limits.memory"
    value = "512Mi"
  }

  # ---------------------------------------------------------------------------
  # Write Component (Ingestion Path) — prod: 2 replicas
  # WAL em PVC gp3 (WaitForFirstConsumer — zone-pinned, ZERO data loss)
  # Memory 2Gi: lição aprendida OOMKilled durante WAL recovery (Lição 20)
  # ---------------------------------------------------------------------------
  set {
    name  = "write.replicas"
    value = "2"
  }

  set {
    name  = "write.podLabels.domain"
    value = "operations"
  }

  set {
    name  = "write.podLabels.owner"
    value = "platform-team"
  }

  set {
    name  = "write.podLabels.environment"
    value = "production"
  }

  set {
    name  = "write.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
  }

  set {
    name  = "write.nodeSelector.eks\\.amazonaws\\.com/nodegroup"
    value = "workloads"
  }

  set {
    name  = "write.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "write.resources.requests.memory"
    value = "2Gi"
  }

  set {
    name  = "write.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "write.resources.limits.memory"
    value = "2Gi"
  }

  set {
    name  = "write.persistence.enabled"
    value = "true"
  }

  set {
    name  = "write.persistence.storageClass"
    value = "gp3"
  }

  set {
    name  = "write.persistence.size"
    value = "10Gi"
  }

  # ---------------------------------------------------------------------------
  # Backend Component (Compaction) — prod: 2 replicas
  # PVC gp3 zone-pinned (Lição 22: WaitForFirstConsumer != node-pinned)
  # ---------------------------------------------------------------------------
  set {
    name  = "backend.replicas"
    value = "2"
  }

  set {
    name  = "backend.podLabels.domain"
    value = "operations"
  }

  set {
    name  = "backend.podLabels.owner"
    value = "platform-team"
  }

  set {
    name  = "backend.podLabels.environment"
    value = "production"
  }

  set {
    name  = "backend.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
  }

  set {
    name  = "backend.nodeSelector.eks\\.amazonaws\\.com/nodegroup"
    value = "workloads"
  }

  set {
    name  = "backend.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "backend.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "backend.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "backend.resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "backend.persistence.enabled"
    value = "true"
  }

  set {
    name  = "backend.persistence.storageClass"
    value = "gp3"
  }

  set {
    name  = "backend.persistence.size"
    value = "10Gi"
  }

  # ---------------------------------------------------------------------------
  # Gateway Component (Nginx reverse proxy) — prod: 2 replicas (HA)
  # ---------------------------------------------------------------------------
  set {
    name  = "gateway.enabled"
    value = "true"
  }

  set {
    name  = "gateway.replicas"
    value = "2"
  }

  set {
    name  = "gateway.podLabels.domain"
    value = "operations"
  }

  set {
    name  = "gateway.podLabels.owner"
    value = "platform-team"
  }

  set {
    name  = "gateway.podLabels.environment"
    value = "production"
  }

  set {
    name  = "gateway.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
  }

  set {
    name  = "gateway.nodeSelector.eks\\.amazonaws\\.com/nodegroup"
    value = "workloads"
  }

  set {
    name  = "gateway.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "gateway.resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "gateway.resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "gateway.resources.limits.memory"
    value = "128Mi"
  }

  # ---------------------------------------------------------------------------
  # Minio (Disable — usando AWS S3)
  # ---------------------------------------------------------------------------
  set {
    name  = "minio.enabled"
    value = "false"
  }

  # ---------------------------------------------------------------------------
  # Service Account (IRSA) — usa SA gerenciada neste arquivo
  # ---------------------------------------------------------------------------
  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.loki_prod.metadata[0].name
  }

  # ---------------------------------------------------------------------------
  # Monitoring
  # ---------------------------------------------------------------------------
  set {
    name  = "monitoring.selfMonitoring.enabled"
    value = "false"
  }

  set {
    name  = "monitoring.selfMonitoring.grafanaAgent.installOperator"
    value = "false"
  }

  set {
    name  = "monitoring.serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "monitoring.serviceMonitor.namespace"
    value = local.loki_prod_namespace
  }

  # ---------------------------------------------------------------------------
  # Loki Canary (Health Testing) — nodeSelector workloads (não system nodes)
  # ---------------------------------------------------------------------------
  set {
    name  = "lokiCanary.podLabels.domain"
    value = "operations"
  }

  set {
    name  = "lokiCanary.podLabels.owner"
    value = "platform-team"
  }

  set {
    name  = "lokiCanary.podLabels.environment"
    value = "production"
  }

  set {
    name  = "lokiCanary.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
  }

  set {
    name  = "lokiCanary.nodeSelector.eks\\.amazonaws\\.com/nodegroup"
    value = "workloads"
  }

  # ---------------------------------------------------------------------------
  # Chunks Cache (Memcached) — OBRIGATÓRIO: 50m (não 500m default — Lição 23)
  # Uso real medido: ~4m CPU | default 500m = overprovision 125:1
  # ---------------------------------------------------------------------------
  set {
    name  = "chunksCache.podLabels.domain"
    value = "operations"
  }

  set {
    name  = "chunksCache.podLabels.owner"
    value = "platform-team"
  }

  set {
    name  = "chunksCache.podLabels.environment"
    value = "production"
  }

  set {
    name  = "chunksCache.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
  }

  set {
    name  = "chunksCache.nodeSelector.eks\\.amazonaws\\.com/nodegroup"
    value = "workloads"
  }

  # GAP-FINOPS: right-size — default 500m, uso real ~4m (Lição 23)
  set {
    name  = "chunksCache.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "chunksCache.resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "chunksCache.allocatedMemory"
    value = 1024
  }

  # ---------------------------------------------------------------------------
  # Results Cache (Memcached) — OBRIGATÓRIO: 50m (não 500m default — Lição 23)
  # ---------------------------------------------------------------------------
  set {
    name  = "resultsCache.podLabels.domain"
    value = "operations"
  }

  set {
    name  = "resultsCache.podLabels.owner"
    value = "platform-team"
  }

  set {
    name  = "resultsCache.podLabels.environment"
    value = "production"
  }

  set {
    name  = "resultsCache.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
  }

  # GAP-FINOPS: right-size — default 500m, uso real ~5m (Lição 23)
  set {
    name  = "resultsCache.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resultsCache.resources.limits.cpu"
    value = "200m"
  }

  # ---------------------------------------------------------------------------
  # Common Labels (fallback para componentes sem podLabels individuais)
  # ---------------------------------------------------------------------------
  set {
    name  = "commonLabels.domain"
    value = "operations"
  }

  set {
    name  = "commonLabels.owner"
    value = "platform-team"
  }

  set {
    name  = "commonLabels.environment"
    value = "production"
  }

  set {
    name  = "commonLabels.managed-by"
    value = "helm"
  }

  # ---------------------------------------------------------------------------
  # ECR Pull-Through Cache
  # NOTA: prod não tem module.ecr_pull_through_cache ainda.
  # Quando o módulo ECR for adicionado ao prod/main.tf, descomentar e
  # substituir o valor hardcoded pelo output do módulo.
  # ---------------------------------------------------------------------------
  # set {
  #   name  = "loki.image.registry"
  #   value = module.ecr_pull_through_cache.ecr_registry_prefix
  # }
  # set {
  #   name  = "loki.image.repository"
  #   value = "docker-hub/grafana/loki"
  # }
  # set {
  #   name  = "gateway.image.registry"
  #   value = module.ecr_pull_through_cache.ecr_registry_prefix
  # }
  # set {
  #   name  = "gateway.image.repository"
  #   value = "docker-hub/nginxinc/nginx-unprivileged"
  # }
  # set {
  #   name  = "chunksCache.image.registry"
  #   value = module.ecr_pull_through_cache.ecr_registry_prefix
  # }
  # set {
  #   name  = "chunksCache.image.repository"
  #   value = "docker-hub/library/memcached"
  # }
  # set {
  #   name  = "resultsCache.image.registry"
  #   value = module.ecr_pull_through_cache.ecr_registry_prefix
  # }
  # set {
  #   name  = "resultsCache.image.repository"
  #   value = "docker-hub/library/memcached"
  # }

  # ---------------------------------------------------------------------------
  # Test Configuration (Disable)
  # ---------------------------------------------------------------------------
  set {
    name  = "test.enabled"
    value = "false"
  }

  depends_on = [
    kubernetes_service_account.loki_prod
  ]
}
