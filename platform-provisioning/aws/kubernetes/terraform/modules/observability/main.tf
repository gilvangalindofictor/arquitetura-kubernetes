################################################################################
# FinOps Grafana Dashboards — ConfigMaps
#
# Deploys Grafana dashboards as Kubernetes ConfigMaps with the sidecar label
# `grafana_dashboard: "1"` for auto-discovery by kube-prometheus-stack.
#
# Dashboards:
#   - AWS Costs Overview (CloudWatch billing metrics)
#   - Resource Utilization (Prometheus node/pod metrics)
#   - FinOps Alerts (budget thresholds, idle resources, cost spikes)
################################################################################

resource "kubernetes_config_map" "grafana_dashboard_aws_costs" {
  metadata {
    name      = "grafana-dashboard-aws-costs-overview"
    namespace = var.monitoring_namespace
    labels = {
      grafana_dashboard              = "1"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "grafana-dashboard"
      "app.kubernetes.io/part-of"    = "finops"
    }
  }

  data = {
    "aws-costs-overview.json" = file("${path.module}/grafana-dashboards/aws-costs-overview.json")
  }
}

resource "kubernetes_config_map" "grafana_dashboard_resource_utilization" {
  metadata {
    name      = "grafana-dashboard-resource-utilization"
    namespace = var.monitoring_namespace
    labels = {
      grafana_dashboard              = "1"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "grafana-dashboard"
      "app.kubernetes.io/part-of"    = "finops"
    }
  }

  data = {
    "resource-utilization.json" = file("${path.module}/grafana-dashboards/resource-utilization.json")
  }
}

resource "kubernetes_config_map" "grafana_dashboard_finops_alerts" {
  metadata {
    name      = "grafana-dashboard-finops-alerts"
    namespace = var.monitoring_namespace
    labels = {
      grafana_dashboard              = "1"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "grafana-dashboard"
      "app.kubernetes.io/part-of"    = "finops"
    }
  }

  data = {
    "finops-alerts.json" = file("${path.module}/grafana-dashboards/finops-alerts.json")
  }
}

################################################################################
# Prometheus Alert Rules — Init Container CrashLoop Detection
# The YAML file is a complete K8s ConfigMap manifest, applied via kubectl.
################################################################################

resource "kubectl_manifest" "prometheus_alert_init_crashloop" {
  yaml_body = file("${path.module}/prometheus-alerts/init-containers-crashloop.yaml")
}

################################################################################
# FinOps AWS Cost Visibility Dashboard
#
# Dashboard completo (21 panels) para visibilidade financeira AWS.
# Data source: Prometheus (metricas via Lambda finops-cost-exporter -> Pushgateway)
# Substitui: aws-costs-overview (CloudWatch only) + finops-alerts (CloudWatch only)
################################################################################

resource "kubernetes_config_map" "grafana_dashboard_finops_visibility" {
  metadata {
    name      = "grafana-dashboard-finops-visibility"
    namespace = var.monitoring_namespace
    labels = {
      grafana_dashboard              = "1"
      grafana_folder                 = "FinOps"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "grafana-dashboard"
      "app.kubernetes.io/part-of"    = "finops"
      environment                    = "staging"
      owner                          = "platform-team"
    }
    annotations = {
      description = "FinOps AWS Cost Visibility — 21 panels, Prometheus datasource via Lambda cost-exporter"
      version     = "1.0.0"
    }
  }

  data = {
    "finops-aws-visibility.json" = file("${path.module}/grafana-dashboards/finops-aws-visibility.json")
  }
}

################################################################################
# FinOps Cost Alerts — PrometheusRule
#
# 4 alertas: BudgetBreach, BudgetWarning80pct, DailyCostAnomaly, ForecastBreach
# Destino: Alertmanager -> Teams #finops-aws (depende DT-005)
################################################################################

resource "kubectl_manifest" "prometheus_alert_finops_costs" {
  yaml_body = file("${path.module}/prometheus-alerts/finops-cost-alerts.yaml")
}
