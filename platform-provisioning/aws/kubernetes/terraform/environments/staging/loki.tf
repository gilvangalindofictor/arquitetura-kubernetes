# -----------------------------------------------------------------------------
# loki.tf — Loki logging stack (S3 backend + IRSA)
# Importado em 2026-03-05 | helm rev 18 | chart loki-6.53.0 | app v3.6.5
# Modulo: modules/loki/ (pre-existente, instanciado aqui pela primeira vez)
#
# Recursos importados:
#   - helm_release.loki                              (staging-observability-monitoring/loki)
#   - aws_s3_bucket.loki                             (k8s-platform-loki-891377105802)
#   - aws_s3_bucket_server_side_encryption_configuration.loki
#   - aws_s3_bucket_public_access_block.loki
#   - aws_s3_bucket_lifecycle_configuration.loki
#   - aws_s3_bucket_versioning.loki
#   - aws_iam_policy.loki_s3                         (LokiS3Policy-k8s-platform-prod)
#   - aws_iam_role.loki                              (LokiS3Role-k8s-platform-prod)
#   - aws_iam_role_policy_attachment.loki_s3
#   - kubernetes_service_account.loki
# -----------------------------------------------------------------------------

module "loki_staging" {
  source = "../../modules/loki"

  # Cluster e regiao
  cluster_name = local.cluster_name  # k8s-platform-prod
  region       = var.aws_region      # us-east-1

  # Namespace onde o Loki esta deployado (helm rev 18)
  namespace = "staging-observability-monitoring"

  # Chart version conforme helm status: chart loki-6.53.0
  chart_version = "6.53.0"

  # Service Account (pre-existente com IRSA annotation)
  service_account_name = "loki"

  # Storage: capturado de `helm get values` — storageClass gp3, 10Gi
  storage_class    = "gp3"
  write_pvc_size   = "10Gi"
  backend_pvc_size = "10Gi"

  # Replicacao: capturado de `helm get values`
  replication_factor = 2
  read_replicas      = 2
  write_replicas     = 2
  backend_replicas   = 2

  # Retencao: 720h = 30 dias (capturado de loki.limits_config.retention_period)
  retention_days    = 30
  enable_versioning = false

  # Corporate Labels (ADR-048) — capturados de `helm get values`
  domain      = "operations"
  owner       = "platform-team"
  environment = "staging"

  # Tags AWS (padrao do ambiente)
  tags = local.common_tags

  # chunksCache.allocatedMemory: usa default do modulo (1024 MB)
  # Drift reconciliado 2026-03-06: valor ja estava ativo no cluster desde
  # importacao em 2026-03-05. terraform plan confirma "No changes".
  # chunks_cache_allocated_memory omitido pois usa o default do modulo (1024).
}
