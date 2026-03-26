# -----------------------------------------------------------------------------
# External DNS Module - IAM (IRSA)
# Fase 5: Route53 permissions for external-dns via IRSA
# -----------------------------------------------------------------------------

locals {
  oidc_provider_id = replace(var.oidc_provider_url, "https://", "")
  iam_role_name    = "ExternalDNS-${var.cluster_name}-${var.environment}"
  iam_policy_name  = "ExternalDNS-Route53-${var.cluster_name}-${var.environment}"
}

# --- IAM Policy: Route53 access for external-dns ---
resource "aws_iam_policy" "external_dns" {
  name        = local.iam_policy_name
  description = "Allows external-dns to manage Route53 records in specified hosted zones"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Route53ChangeRecords"
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
        ]
        Resource = [
          for zone_id in var.hosted_zone_ids : "arn:aws:route53:::hostedzone/${zone_id}"
        ]
      },
      {
        Sid    = "Route53ListZones"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
        ]
        Resource = "*"
      },
    ]
  })

  tags = merge(var.common_tags, {
    Name    = local.iam_policy_name
    Purpose = "external-dns-route53"
  })
}

# --- IAM Role: IRSA for external-dns ServiceAccount ---
resource "aws_iam_role" "external_dns" {
  name = local.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_id}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name      = local.iam_role_name
    Purpose   = "external-dns-irsa"
    Namespace = var.namespace
  })
}

# --- Attach Route53 policy to IRSA role ---
resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}
