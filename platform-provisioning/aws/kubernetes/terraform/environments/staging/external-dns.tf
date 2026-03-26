# =============================================================================
# External DNS — STAGING (Fase 5a)
# Automatic DNS record management for Kubernetes services via Route53
#
# Manages: hml.alvocard.com.br hosted zone
# IRSA: ExternalDNS-k8s-platform-prod-staging role with Route53 permissions
# Ownership: TXT records with txtOwnerId=k8s-platform-prod-staging
#
# NOTE: cluster_name is "k8s-platform-prod" because staging shares the same
#       EKS cluster (ADR-050). The environment="staging" differentiates resources.
#
# Cost: ~$0.50/month (Route53 API calls)
# =============================================================================

module "external_dns_staging" {
  source = "../../modules/external-dns"

  cluster_name = local.cluster_name
  environment  = "staging"
  namespace    = "staging-platform-externaldns" # DEC-074 namespace convention

  # IRSA
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn
  oidc_provider_url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer

  # Route53 — hml zone only
  hosted_zone_ids = [
    "Z06896021141J84PQ0MT2", # hml.alvocard.com.br
  ]

  domain_filters = ["hml.alvocard.com.br"]

  # Record management
  policy     = "upsert-only" # Create + Update only (safer for staging)
  txt_prefix = "extdns-"     # TXT ownership prefix
  interval   = "1m"          # Polling interval
  log_level  = "info"

  common_tags = local.common_tags
}
