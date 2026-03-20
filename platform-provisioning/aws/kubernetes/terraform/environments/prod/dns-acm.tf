# =============================================================================
# DNS + ACM — Fase 5 Produção (alvocard.com.br)
# Zones existem no Route53 (criadas fora do TF) — usar data sources
# ACM prod existe — importar no state
# ACM hml — criar novo
# =============================================================================

# --- Data Sources: Hosted Zones (já existem no Route53) ---
data "aws_route53_zone" "prod" {
  name = "prod.alvocard.com.br"
}

data "aws_route53_zone" "hml" {
  name = "hml.alvocard.com.br"
}

# --- ACM: Wildcard Prod (já existe — importar) ---
resource "aws_acm_certificate" "prod_wildcard" {
  domain_name               = "*.prod.alvocard.com.br"
  subject_alternative_names = ["prod.alvocard.com.br"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
  }

  tags = {
    Name        = "wildcard-prod-alvocard"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# --- ACM: Wildcard HML (NOVO — criar) ---
resource "aws_acm_certificate" "hml_wildcard" {
  domain_name       = "*.hml.alvocard.com.br"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "wildcard-hml-alvocard"
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}

# --- Validação DNS: Prod (já existe — importar) ---
resource "aws_route53_record" "prod_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.prod_wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.prod.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "prod_wildcard" {
  certificate_arn         = aws_acm_certificate.prod_wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.prod_cert_validation : r.fqdn]
  timeouts { create = "30m" }
}

# --- Validação DNS: HML (NOVO — criar) ---
resource "aws_route53_record" "hml_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.hml_wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.hml.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "hml_wildcard" {
  certificate_arn         = aws_acm_certificate.hml_wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.hml_cert_validation : r.fqdn]
  timeouts { create = "30m" }
}

# --- Outputs ---
output "prod_route53_zone_id" {
  description = "Zone ID prod"
  value       = data.aws_route53_zone.prod.zone_id
}

output "hml_route53_zone_id" {
  description = "Zone ID hml"
  value       = data.aws_route53_zone.hml.zone_id
}

output "prod_acm_certificate_arn" {
  description = "ARN do wildcard ACM prod"
  value       = aws_acm_certificate.prod_wildcard.arn
}

output "hml_acm_certificate_arn" {
  description = "ARN do wildcard ACM hml"
  value       = aws_acm_certificate.hml_wildcard.arn
}
