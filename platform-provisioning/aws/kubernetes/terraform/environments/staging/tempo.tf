# -----------------------------------------------------------------------------
# tempo.tf — Tempo distributed tracing stack (S3 backend + IRSA)
# Importado em 2026-03-21 | helm rev 3 | chart tempo-distributed-1.61.3 | app v2.9.0
# Modulo: modules/tempo/ (pre-existente, instanciado aqui pela primeira vez)
#
# Recursos importados:
#   - helm_release.tempo                                     (staging-observability-monitoring/tempo)
#   - aws_s3_bucket.tempo                                    (k8s-platform-tempo-891377105802)
#   - aws_s3_bucket_server_side_encryption_configuration.tempo
#   - aws_s3_bucket_public_access_block.tempo
#   - aws_s3_bucket_lifecycle_configuration.tempo
#   - aws_s3_bucket_versioning.tempo
#   - aws_iam_policy.tempo_s3                                (TempoS3Policy-k8s-platform-prod)
#   - aws_iam_role.tempo                                     (TempoS3Role-k8s-platform-prod)
#   - aws_iam_role_policy_attachment.tempo_s3
#   - kubernetes_service_account.tempo
# -----------------------------------------------------------------------------

module "tempo_staging" {
  source = "../../modules/tempo"

  # Cluster e regiao
  cluster_name = local.cluster_name # k8s-platform-prod
  region       = var.aws_region     # us-east-1

  # Namespace onde o Tempo esta deployado (helm rev 3)
  namespace = "staging-observability-monitoring"

  # Chart version conforme helm status: chart tempo-distributed-1.61.3
  chart_version = "1.61.3"

  # Service Account (pre-existente com IRSA annotation)
  service_account_name = "tempo"

  # Storage: gp3 10Gi (capturado de kubectl get statefulset tempo-ingester —
  # spec.volumeClaimTemplates[0].spec.storageClassName = gp3)
  # NOTA: gp3 (nao gp2) para evitar conflito com campo imutavel storageClassName no StatefulSet
  storage_class      = "gp3"
  ingester_pvc_size  = "10Gi"
  compactor_pvc_size = "10Gi"

  # Replicacao: 2 replicas (FinOps staging)
  distributor_replicas = 2
  ingester_replicas    = 2
  querier_replicas     = 2
  compactor_replicas   = 1

  # Retencao: 7 dias (ADR-020 FinOps default)
  retention_days    = 7
  enable_versioning = false

  # Tags AWS (padrao do ambiente)
  tags = local.common_tags

  # Corporate Labels (ADR-048 — Kyverno Compliance)
  corporate_label_domain      = "operations"
  corporate_label_environment = "staging"
  corporate_label_owner       = "platform-team"

  # ECR Pull-Through Cache (GAP-SEC-REGISTRY-03)
  ecr_registry = module.ecr_pull_through_cache.ecr_registry_prefix

  # Multi-environment IRSA — prod SA adicionado manualmente para resolver
  # acesso do tempo-prod ao mesmo IAM Role via IRSA.
  # Codificado aqui para eliminar drift na trust policy do TempoS3Role.
  additional_irsa_service_accounts = [
    "prod-observability-monitoring:tempo-prod"
  ]

  # Multi-environment S3 — bucket prod adicionado manualmente para permitir
  # que Tempo-prod grave traces no bucket dedicado prod.
  # Codificado aqui para eliminar drift na TempoS3Policy.
  additional_s3_bucket_arns = [
    "arn:aws:s3:::k8s-platform-tempo-prod-891377105802"
  ]
}

# -----------------------------------------------------------------------------
# Import blocks — recursos pre-existentes antes desta instanciacao TF
# Executar: terraform apply -target=module.tempo_staging para importar
# -----------------------------------------------------------------------------

import {
  to = module.tempo_staging.aws_s3_bucket.tempo
  id = "k8s-platform-tempo-891377105802"
}

import {
  to = module.tempo_staging.aws_s3_bucket_server_side_encryption_configuration.tempo
  id = "k8s-platform-tempo-891377105802"
}

import {
  to = module.tempo_staging.aws_s3_bucket_public_access_block.tempo
  id = "k8s-platform-tempo-891377105802"
}

import {
  to = module.tempo_staging.aws_s3_bucket_lifecycle_configuration.tempo
  id = "k8s-platform-tempo-891377105802"
}

import {
  to = module.tempo_staging.aws_s3_bucket_versioning.tempo
  id = "k8s-platform-tempo-891377105802"
}

import {
  to = module.tempo_staging.aws_iam_policy.tempo_s3
  id = "arn:aws:iam::891377105802:policy/TempoS3Policy-k8s-platform-prod"
}

import {
  to = module.tempo_staging.aws_iam_role.tempo
  id = "TempoS3Role-k8s-platform-prod"
}

import {
  to = module.tempo_staging.aws_iam_role_policy_attachment.tempo_s3
  id = "TempoS3Role-k8s-platform-prod/arn:aws:iam::891377105802:policy/TempoS3Policy-k8s-platform-prod"
}

import {
  to = module.tempo_staging.kubernetes_service_account.tempo
  id = "staging-observability-monitoring/tempo"
}

import {
  to = module.tempo_staging.helm_release.tempo
  id = "staging-observability-monitoring/tempo"
}
