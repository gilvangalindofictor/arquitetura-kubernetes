# -----------------------------------------------------------------------------
# Route53 Configuration - Test Applications
# Marco 2 Fase 7.1 - TLS Implementation
# -----------------------------------------------------------------------------

# Hosted Zone para test applications
resource "aws_route53_zone" "test_apps" {
  count = var.create_route53_zone ? 1 : 0

  name    = var.domain_name
  comment = "Test Applications - Marco 2 Fase 7.1"

  tags = merge(
    var.tags,
    {
      Name        = "test-apps-zone"
      Environment = "test"
      Marco       = "marco2"
      Fase        = "7.1"
      Component   = "dns"
    }
  )
}

# Obter informações do Ingress NGINX após provisionamento
# Necessário para criar CNAME/Alias apontando para ALB
data "kubernetes_ingress_v1" "nginx_test" {
  metadata {
    name      = "nginx-test-ingress"
    namespace = kubernetes_namespace.test_apps.metadata[0].name
  }

  depends_on = [
    kubectl_manifest.nginx_test
  ]
}

data "kubernetes_ingress_v1" "echo_server" {
  metadata {
    name      = "echo-server-ingress"
    namespace = kubernetes_namespace.test_apps.metadata[0].name
  }

  depends_on = [
    kubectl_manifest.echo_server
  ]
}

# Obter informações do ALB (para Alias Record - mais eficiente que CNAME)
data "aws_lb" "nginx_test_alb" {
  tags = {
    "elbv2.k8s.aws/cluster"    = var.cluster_name
    "ingress.k8s.aws/stack"    = "test-apps/nginx-test-ingress"
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }

  depends_on = [
    kubectl_manifest.nginx_test
  ]
}

data "aws_lb" "echo_server_alb" {
  tags = {
    "elbv2.k8s.aws/cluster"    = var.cluster_name
    "ingress.k8s.aws/stack"    = "test-apps/echo-server-ingress"
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }

  depends_on = [
    kubectl_manifest.echo_server
  ]
}

# Alias Record para nginx-test (A record com alias para ALB)
# Mais eficiente que CNAME: resolve diretamente para IPs do ALB
resource "aws_route53_record" "nginx_test" {
  count = var.create_route53_zone ? 1 : 0

  zone_id = aws_route53_zone.test_apps[0].zone_id
  name    = "nginx-test.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.nginx_test_alb.dns_name
    zone_id                = data.aws_lb.nginx_test_alb.zone_id
    evaluate_target_health = true
  }

  depends_on = [
    data.aws_lb.nginx_test_alb
  ]
}

# Alias Record para echo-server
resource "aws_route53_record" "echo_server" {
  count = var.create_route53_zone ? 1 : 0

  zone_id = aws_route53_zone.test_apps[0].zone_id
  name    = "echo-server.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.echo_server_alb.dns_name
    zone_id                = data.aws_lb.echo_server_alb.zone_id
    evaluate_target_health = true
  }

  depends_on = [
    data.aws_lb.echo_server_alb
  ]
}

# Output dos Name Servers para delegação DNS
# Se usar subdomínio de domínio existente, criar NS record no domínio pai apontando para estes
output "route53_name_servers" {
  description = "Route53 name servers for DNS delegation (if using subdomain)"
  value       = var.create_route53_zone ? aws_route53_zone.test_apps[0].name_servers : []
}

# Output da Zone ID para referência
output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = var.create_route53_zone ? aws_route53_zone.test_apps[0].zone_id : ""
}
