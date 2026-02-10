output "service_name" {
  description = "OTel Collector service name"
  value       = "${var.release_name}-opentelemetry-collector"
}

output "service_namespace" {
  description = "OTel Collector service namespace"
  value       = var.namespace
}

output "otlp_grpc_endpoint" {
  description = "OTLP gRPC endpoint (for app instrumentation)"
  value       = "${var.release_name}-opentelemetry-collector.${var.namespace}.svc.cluster.local:4317"
}

output "otlp_http_endpoint" {
  description = "OTLP HTTP endpoint (for app instrumentation)"
  value       = "${var.release_name}-opentelemetry-collector.${var.namespace}.svc.cluster.local:4318"
}

output "tempo_endpoint_resolved" {
  description = "Resolved Tempo Distributor endpoint (from data source)"
  value       = data.kubernetes_service.tempo_distributor.metadata[0].name
}

output "helm_release_status" {
  description = "Helm release status"
  value       = helm_release.otel_collector.status
}
