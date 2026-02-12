output "grafana_dashboard_names" {
  description = "Names of deployed Grafana dashboard ConfigMaps"
  value = [
    kubernetes_config_map.grafana_dashboard_aws_costs.metadata[0].name,
    kubernetes_config_map.grafana_dashboard_resource_utilization.metadata[0].name,
    kubernetes_config_map.grafana_dashboard_finops_alerts.metadata[0].name,
  ]
}

output "grafana_dashboard_uids" {
  description = "UIDs of Grafana dashboards for direct access URLs"
  value = {
    aws_costs_overview   = "aws-costs-overview"
    resource_utilization = "resource-utilization"
    finops_alerts        = "finops-alerts"
  }
}
