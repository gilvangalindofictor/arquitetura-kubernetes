# -----------------------------------------------------------------------------
# AWS Certificate Manager - Test Applications
# Marco 2 Fase 7.1 - TLS Implementation
# Certificados públicos com validação DNS automática via Route53
# -----------------------------------------------------------------------------

# Certificado ACM para nginx-test
resource "aws_acm_certificate" "nginx_test" {
  domain_name       = "nginx-test.${var.domain_name}"
  validation_method = "DNS"

  tags = merge(
    var.tags,
    {
      Name        = "nginx-test-cert"
      Environment = "test"
      Marco       = "marco2"
      Fase        = "7.1"
      Component   = "tls"
      Application = "nginx-test"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Validation records automáticos para nginx-test
# ACM gera TXT records que precisam ser criados no Route53
resource "aws_route53_record" "nginx_test_validation" {
  for_each = var.create_route53_zone ? {
    for dvo in aws_acm_certificate.nginx_test.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.test_apps[0].zone_id
}

# Aguardar validação completar (pode levar até 30 minutos, geralmente 5-10 min)
resource "aws_acm_certificate_validation" "nginx_test" {
  certificate_arn         = aws_acm_certificate.nginx_test.arn
  validation_record_fqdns = var.create_route53_zone ? [for record in aws_route53_record.nginx_test_validation : record.fqdn] : []

  timeouts {
    create = "30m"
  }
}

# Certificado ACM para echo-server
resource "aws_acm_certificate" "echo_server" {
  domain_name       = "echo-server.${var.domain_name}"
  validation_method = "DNS"

  tags = merge(
    var.tags,
    {
      Name        = "echo-server-cert"
      Environment = "test"
      Marco       = "marco2"
      Fase        = "7.1"
      Component   = "tls"
      Application = "echo-server"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Validation records automáticos para echo-server
resource "aws_route53_record" "echo_server_validation" {
  for_each = var.create_route53_zone ? {
    for dvo in aws_acm_certificate.echo_server.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.test_apps[0].zone_id
}

# Aguardar validação completar
resource "aws_acm_certificate_validation" "echo_server" {
  certificate_arn         = aws_acm_certificate.echo_server.arn
  validation_record_fqdns = var.create_route53_zone ? [for record in aws_route53_record.echo_server_validation : record.fqdn] : []

  timeouts {
    create = "30m"
  }
}

# Outputs dos Certificate ARNs (usados nas annotations dos Ingresses)
output "nginx_test_certificate_arn" {
  description = "ARN of ACM certificate for nginx-test"
  value       = aws_acm_certificate.nginx_test.arn
}

output "echo_server_certificate_arn" {
  description = "ARN of ACM certificate for echo-server"
  value       = aws_acm_certificate.echo_server.arn
}

# Output de status de validação (para troubleshooting)
output "nginx_test_certificate_status" {
  description = "Validation status of nginx-test certificate"
  value       = aws_acm_certificate.nginx_test.status
}

output "echo_server_certificate_status" {
  description = "Validation status of echo-server certificate"
  value       = aws_acm_certificate.echo_server.status
}
