# =============================================================================
# External DNS — PROD (Fase 5a)
# Automatic DNS record management for Kubernetes services via Route53
#
# Manages: prod.alvocard.com.br hosted zone
# IRSA: ExternalDNS-k8s-platform-prod-prod role with Route53 permissions
# Ownership: TXT records with txtOwnerId=k8s-platform-prod-prod
#
# How it works:
#   - Watches Service (type=LoadBalancer) and Ingress resources
#   - Creates/updates/deletes A/CNAME records in Route53 automatically
#   - Annotations: external-dns.alpha.kubernetes.io/hostname=<fqdn>
#
# Cost: ~$0.50/month (Route53 API calls)
# =============================================================================

module "external_dns_prod" {
  source = "../../modules/external-dns"

  cluster_name = local.cluster_name
  environment  = "prod"
  namespace    = "prod-platform-externaldns" # DEC-074 namespace convention

  # IRSA
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn
  oidc_provider_url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer

  # Route53 — prod zone only
  hosted_zone_ids = [
    "Z0855081WEDNFRS7K2IO", # prod.alvocard.com.br
  ]

  domain_filters = ["prod.alvocard.com.br"]

  # Record management
  policy     = "sync"    # Create + Update + Delete
  txt_prefix = "extdns-" # TXT ownership prefix
  interval   = "1m"      # Polling interval
  log_level  = "info"

  common_tags = local.common_tags
}
