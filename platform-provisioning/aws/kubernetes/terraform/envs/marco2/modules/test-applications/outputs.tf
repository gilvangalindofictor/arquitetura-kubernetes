# Outputs for Test Applications Module

output "namespace" {
  description = "Namespace criado para test applications"
  value       = kubernetes_namespace.test_apps.metadata[0].name
}

output "nginx_alb_command" {
  description = "Comando para obter DNS do ALB do NGINX"
  value       = "kubectl get ingress -n ${kubernetes_namespace.test_apps.metadata[0].name} nginx-test-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "echo_server_alb_command" {
  description = "Comando para obter DNS do ALB do Echo Server"
  value       = "kubectl get ingress -n ${kubernetes_namespace.test_apps.metadata[0].name} echo-server-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "validation_commands" {
  description = "Comandos para validação da Fase 7"
  value = var.enable_tls ? <<-EOT
    # 1. Verificar pods Running
    kubectl get pods -n ${kubernetes_namespace.test_apps.metadata[0].name}

    # 2. Verificar Ingress e ALB provisionado
    kubectl get ingress -n ${kubernetes_namespace.test_apps.metadata[0].name}

    # 3. Verificar certificados ACM
    aws acm describe-certificate --certificate-arn ${aws_acm_certificate.nginx_test.arn} --region us-east-1 | jq '.Certificate.Status'
    aws acm describe-certificate --certificate-arn ${aws_acm_certificate.echo_server.arn} --region us-east-1 | jq '.Certificate.Status'

    # 4. Testar NGINX via HTTPS (domínio real)
    curl -I https://nginx-test.${var.domain_name}

    # 5. Testar Echo Server via HTTPS (domínio real)
    curl https://echo-server.${var.domain_name} | jq

    # 6. Verificar certificado no browser
    # Abrir: https://nginx-test.${var.domain_name}
    # Verificar: Cadeado verde, sem avisos de segurança

    # 7. Executar script de validação completa
    ./scripts/validate-fase7.sh
  EOT : <<-EOT
    # 1. Verificar pods Running
    kubectl get pods -n ${kubernetes_namespace.test_apps.metadata[0].name}

    # 2. Verificar Ingress e ALB provisionado
    kubectl get ingress -n ${kubernetes_namespace.test_apps.metadata[0].name}

    # 3. Obter DNS do ALB NGINX
    NGINX_ALB=$(kubectl get ingress -n ${kubernetes_namespace.test_apps.metadata[0].name} nginx-test-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "NGINX ALB: http://$NGINX_ALB"

    # 4. Obter DNS do ALB Echo Server
    ECHO_ALB=$(kubectl get ingress -n ${kubernetes_namespace.test_apps.metadata[0].name} echo-server-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "Echo Server ALB: http://$ECHO_ALB"

    # 5. Testar NGINX
    curl http://$NGINX_ALB

    # 6. Testar Echo Server
    curl http://$ECHO_ALB | jq

    # 7. Executar script de validação completa
    ./scripts/validate-fase7.sh
  EOT
}

# -----------------------------------------------------------------------------
# TLS Outputs (Fase 7.1)
# -----------------------------------------------------------------------------

output "nginx_test_url" {
  description = "URL completa para acesso ao nginx-test"
  value       = var.enable_tls ? "https://nginx-test.${var.domain_name}" : "http://<ALB_DNS_NAME>"
}

output "echo_server_url" {
  description = "URL completa para acesso ao echo-server"
  value       = var.enable_tls ? "https://echo-server.${var.domain_name}" : "http://<ALB_DNS_NAME>"
}

output "tls_summary" {
  description = "Resumo da configuração TLS"
  value = {
    enabled                        = var.enable_tls
    domain                         = var.domain_name
    nginx_test_url                 = var.enable_tls ? "https://nginx-test.${var.domain_name}" : "http://<ALB_DNS_NAME>"
    echo_server_url                = var.enable_tls ? "https://echo-server.${var.domain_name}" : "http://<ALB_DNS_NAME>"
    nginx_test_certificate_arn     = var.enable_tls ? aws_acm_certificate.nginx_test.arn : "N/A - TLS not enabled"
    echo_server_certificate_arn    = var.enable_tls ? aws_acm_certificate.echo_server.arn : "N/A - TLS not enabled"
    nginx_test_certificate_status  = var.enable_tls ? aws_acm_certificate.nginx_test.status : "N/A"
    echo_server_certificate_status = var.enable_tls ? aws_acm_certificate.echo_server.status : "N/A"
    route53_zone_id                = var.enable_tls && var.create_route53_zone ? aws_route53_zone.test_apps[0].zone_id : "N/A"
    route53_name_servers           = var.enable_tls && var.create_route53_zone ? aws_route53_zone.test_apps[0].name_servers : []
    message                        = var.enable_tls ? "TLS enabled - Access via HTTPS URLs above" : "TLS not enabled - Set enable_tls=true and provide domain_name to enable HTTPS"
  }
}
