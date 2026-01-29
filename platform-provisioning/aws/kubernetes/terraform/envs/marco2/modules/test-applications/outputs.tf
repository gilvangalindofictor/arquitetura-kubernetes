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
  value = <<-EOT
    # 1. Verificar pods Running
    kubectl get pods -n ${kubernetes_namespace.test_apps.metadata[0].name}

    # 2. Verificar Ingress e ALB provisionado
    kubectl get ingress -n ${kubernetes_namespace.test_apps.metadata[0].name}

    # 3. Obter DNS do ALB NGINX
    NGINX_ALB=$(kubectl get ingress -n ${kubernetes_namespace.test_apps.metadata[0].name} nginx-test-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "NGINX ALB: https://$NGINX_ALB"

    # 4. Obter DNS do ALB Echo Server
    ECHO_ALB=$(kubectl get ingress -n ${kubernetes_namespace.test_apps.metadata[0].name} echo-server-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "Echo Server ALB: https://$ECHO_ALB"

    # 5. Testar NGINX
    curl -k https://$NGINX_ALB

    # 6. Testar Echo Server
    curl -k https://$ECHO_ALB | jq

    # 7. Executar script de validação completa
    ./scripts/validate-fase7.sh
  EOT
}
