# -----------------------------------------------------------------------------
# Outputs - Tempo Module
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# S3 Backend
# -----------------------------------------------------------------------------

output "s3_bucket_name" {
  description = "Nome do bucket S3 para traces"
  value       = aws_s3_bucket.tempo.id
}

output "s3_bucket_arn" {
  description = "ARN do bucket S3"
  value       = aws_s3_bucket.tempo.arn
}

output "s3_bucket_region" {
  description = "Região do bucket S3"
  value       = aws_s3_bucket.tempo.region
}

# -----------------------------------------------------------------------------
# IAM Resources
# -----------------------------------------------------------------------------

output "iam_role_arn" {
  description = "ARN do IAM Role para IRSA (debugging)"
  value       = aws_iam_role.tempo.arn
}

output "iam_role_name" {
  description = "Nome do IAM Role"
  value       = aws_iam_role.tempo.name
}

output "iam_policy_arn" {
  description = "ARN da IAM Policy para S3 access"
  value       = aws_iam_policy.tempo_s3.arn
}

# -----------------------------------------------------------------------------
# Kubernetes Resources
# -----------------------------------------------------------------------------

output "service_account_name" {
  description = "Nome do Service Account Kubernetes"
  value       = kubernetes_service_account.tempo.metadata[0].name
}

output "namespace" {
  description = "Namespace onde Tempo foi deployado"
  value       = var.namespace
}

# -----------------------------------------------------------------------------
# Tempo Endpoints
# -----------------------------------------------------------------------------

output "tempo_gateway_endpoint" {
  description = "Endpoint do Tempo Gateway (uso geral)"
  value       = "http://tempo-gateway.${var.namespace}.svc.cluster.local:3100"
}

output "tempo_query_frontend_endpoint" {
  description = "Endpoint do Tempo Query Frontend (para Grafana datasource)"
  value       = "http://tempo-query-frontend.${var.namespace}.svc.cluster.local:3100"
}

output "tempo_distributor_otlp_grpc_endpoint" {
  description = "Endpoint OTLP gRPC do Distributor (para OTel Collector)"
  value       = "tempo-distributor.${var.namespace}.svc.cluster.local:4317"
}

output "tempo_distributor_otlp_http_endpoint" {
  description = "Endpoint OTLP HTTP do Distributor (para OTel Collector)"
  value       = "http://tempo-distributor.${var.namespace}.svc.cluster.local:4318"
}

# -----------------------------------------------------------------------------
# Configuration Summary
# -----------------------------------------------------------------------------

output "configuration_summary" {
  description = "Resumo da configuração do Tempo"
  value = {
    chart_version        = var.chart_version
    retention_days       = var.retention_days
    distributor_replicas = var.distributor_replicas
    ingester_replicas    = var.ingester_replicas
    querier_replicas     = var.querier_replicas
    compactor_replicas   = var.compactor_replicas
    storage_backend      = "s3"
    s3_bucket            = aws_s3_bucket.tempo.id
    irsa_role            = aws_iam_role.tempo.arn
    network_policies     = var.enable_network_policies ? "enabled" : "disabled"
  }
}

# -----------------------------------------------------------------------------
# Validation Commands
# -----------------------------------------------------------------------------

output "validation_commands" {
  description = "Comandos para validar o deployment"
  value       = <<-EOT
    # ===== VALIDAÇÃO TEMPO DEPLOYMENT =====

    # 1. Verificar pods Tempo Running
    kubectl get pods -n ${var.namespace} -l app.kubernetes.io/name=tempo

    # 2. Verificar Service Account com IRSA annotation
    kubectl get sa ${var.service_account_name} -n ${var.namespace} -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
    # Esperado: ${aws_iam_role.tempo.arn}

    # 3. Verificar PVCs criados (Ingester + Compactor)
    kubectl get pvc -n ${var.namespace} -l app.kubernetes.io/name=tempo

    # 4. Verificar S3 bucket accessible via IRSA
    kubectl exec -n ${var.namespace} deploy/tempo-distributor -- \
      aws s3 ls s3://${aws_s3_bucket.tempo.id}/ --region ${var.region}
    # Esperado: Listagem de objetos (vazio inicialmente)

    # 5. Verificar ServiceMonitor criado
    kubectl get servicemonitor -n ${var.namespace} -l app.kubernetes.io/name=tempo

    # 6. Verificar Network Policies aplicadas
    kubectl get networkpolicies -n ${var.namespace} | grep -E "otel|tempo"
    # Esperado: 4 policies (allow-otel-collector-ingress, allow-otel-to-tempo, allow-grafana-to-tempo, allow-tempo-to-s3)

    # 7. Verificar Tempo Gateway service
    kubectl get svc -n ${var.namespace} tempo-gateway

    # 8. Query Tempo API (health check)
    kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl:latest -- \
      curl -s http://tempo-query-frontend.${var.namespace}.svc.cluster.local:3100/ready

    # 9. Verificar logs Tempo pods (erros)
    kubectl logs -n ${var.namespace} -l app.kubernetes.io/name=tempo --tail=50 | grep -i error

    # 10. Validar S3 lifecycle policy
    aws s3api get-bucket-lifecycle-configuration \
      --bucket ${aws_s3_bucket.tempo.id} | jq '.Rules[].Expiration.Days'
    # Esperado: ${var.retention_days}
  EOT
}

# -----------------------------------------------------------------------------
# Grafana Datasource Config (manual setup - Fase 2)
# -----------------------------------------------------------------------------

output "grafana_datasource_config" {
  description = "Configuração do datasource Tempo para Grafana (adicionar manualmente no kube-prometheus-stack)"
  value       = <<-EOT
    # Adicionar no módulo kube-prometheus-stack/main.tf:

    set {
      name  = "grafana.additionalDataSources[1].name"
      value = "Tempo"
    }

    set {
      name  = "grafana.additionalDataSources[1].type"
      value = "tempo"
    }

    set {
      name  = "grafana.additionalDataSources[1].url"
      value = "http://tempo-query-frontend.${var.namespace}:3100"
    }

    set {
      name  = "grafana.additionalDataSources[1].access"
      value = "proxy"
    }

    set {
      name  = "grafana.additionalDataSources[1].uid"
      value = "tempo"
    }

    # Correlação Traces → Logs (TraceID no Loki)
    set {
      name  = "grafana.additionalDataSources[1].jsonData.tracesToLogs.datasourceUid"
      value = "loki"
    }

    set {
      name  = "grafana.additionalDataSources[1].jsonData.tracesToLogs.tags[0]"
      value = "namespace"
    }

    set {
      name  = "grafana.additionalDataSources[1].jsonData.tracesToLogs.tags[1]"
      value = "pod"
    }

    # Correlação Traces → Metrics (Exemplars no Prometheus)
    set {
      name  = "grafana.additionalDataSources[1].jsonData.tracesToMetrics.datasourceUid"
      value = "prometheus"
    }

    # Service Map (topologia de serviços)
    set {
      name  = "grafana.additionalDataSources[1].jsonData.serviceMap.datasourceUid"
      value = "prometheus"
    }
  EOT
}
