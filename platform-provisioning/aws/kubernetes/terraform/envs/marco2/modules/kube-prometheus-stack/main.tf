# -----------------------------------------------------------------------------
# Kube-Prometheus-Stack Module
# Descrição: Stack completo de monitoramento (Prometheus + Grafana + Alertmanager)
# Chart: kube-prometheus-stack (Prometheus Community)
# Versão: v69.4.0
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Namespace para Monitoring
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace

    labels = {
      "name"                         = var.namespace
      "app.kubernetes.io/name"       = "kube-prometheus-stack"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Helm Release - Kube-Prometheus-Stack
# -----------------------------------------------------------------------------

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # Timeout aumentado devido ao número de CRDs
  timeout = 600

  # -----------------------------------------------------------------------------
  # Prometheus Operator
  # -----------------------------------------------------------------------------

  set {
    name  = "prometheusOperator.enabled"
    value = "true"
  }

  # Node selector para system nodes
  set {
    name  = "prometheusOperator.nodeSelector.node-type"
    value = "system"
  }

  # Tolerations
  set {
    name  = "prometheusOperator.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "prometheusOperator.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "prometheusOperator.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "prometheusOperator.tolerations[0].effect"
    value = "NoSchedule"
  }

  # -----------------------------------------------------------------------------
  # Prometheus
  # -----------------------------------------------------------------------------

  set {
    name  = "prometheus.enabled"
    value = "true"
  }

  # Storage (EBS via EBS CSI Driver)
  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]"
    value = "ReadWriteOnce"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = var.prometheus_storage_size
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName"
    value = "gp3"
  }

  # Retention
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = var.prometheus_retention
  }

  # Resources
  set {
    name  = "prometheus.prometheusSpec.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "2Gi"
  }

  # Node selector
  set {
    name  = "prometheus.prometheusSpec.nodeSelector.node-type"
    value = "system"
  }

  # Tolerations
  set {
    name  = "prometheus.prometheusSpec.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "prometheus.prometheusSpec.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "prometheus.prometheusSpec.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "prometheus.prometheusSpec.tolerations[0].effect"
    value = "NoSchedule"
  }

  # Service Monitor selector (monitorar todos os namespaces)
  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  # -----------------------------------------------------------------------------
  # Grafana
  # -----------------------------------------------------------------------------

  set {
    name  = "grafana.enabled"
    value = "true"
  }

  # Admin credentials
  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  # Persistence
  set {
    name  = "grafana.persistence.enabled"
    value = "true"
  }

  set {
    name  = "grafana.persistence.size"
    value = var.grafana_storage_size
  }

  set {
    name  = "grafana.persistence.storageClassName"
    value = "gp3"
  }

  # Resources
  set {
    name  = "grafana.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "grafana.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "grafana.resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "grafana.resources.limits.memory"
    value = "256Mi"
  }

  # Node selector
  set {
    name  = "grafana.nodeSelector.node-type"
    value = "system"
  }

  # Tolerations
  set {
    name  = "grafana.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "grafana.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "grafana.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "grafana.tolerations[0].effect"
    value = "NoSchedule"
  }

  # Dashboards (pré-configurados pelo chart)
  set {
    name  = "grafana.defaultDashboardsEnabled"
    value = "true"
  }

  # Ingress (se habilitado)
  dynamic "set" {
    for_each = var.grafana_ingress_enabled ? [1] : []
    content {
      name  = "grafana.ingress.enabled"
      value = "true"
    }
  }

  dynamic "set" {
    for_each = var.grafana_ingress_enabled ? [1] : []
    content {
      name  = "grafana.ingress.ingressClassName"
      value = "alb"
    }
  }

  dynamic "set" {
    for_each = var.grafana_ingress_enabled && var.grafana_ingress_host != "" ? [1] : []
    content {
      name  = "grafana.ingress.hosts[0]"
      value = var.grafana_ingress_host
    }
  }

  # -----------------------------------------------------------------------------
  # Alertmanager
  # -----------------------------------------------------------------------------

  set {
    name  = "alertmanager.enabled"
    value = "true"
  }

  # Storage
  set {
    name  = "alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.accessModes[0]"
    value = "ReadWriteOnce"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage"
    value = var.alertmanager_storage_size
  }

  set {
    name  = "alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.storageClassName"
    value = "gp3"
  }

  # Resources
  set {
    name  = "alertmanager.alertmanagerSpec.resources.requests.cpu"
    value = "10m"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.resources.requests.memory"
    value = "32Mi"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.resources.limits.cpu"
    value = "50m"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.resources.limits.memory"
    value = "64Mi"
  }

  # Node selector
  set {
    name  = "alertmanager.alertmanagerSpec.nodeSelector.node-type"
    value = "system"
  }

  # Tolerations
  set {
    name  = "alertmanager.alertmanagerSpec.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.tolerations[0].effect"
    value = "NoSchedule"
  }

  # -----------------------------------------------------------------------------
  # Node Exporter
  # -----------------------------------------------------------------------------

  set {
    name  = "nodeExporter.enabled"
    value = "true"
  }

  # -----------------------------------------------------------------------------
  # Kube State Metrics
  # -----------------------------------------------------------------------------

  set {
    name  = "kubeStateMetrics.enabled"
    value = "true"
  }

  # Node selector
  set {
    name  = "kube-state-metrics.nodeSelector.node-type"
    value = "system"
  }

  # Tolerations
  set {
    name  = "kube-state-metrics.tolerations[0].key"
    value = "node-type"
  }

  set {
    name  = "kube-state-metrics.tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "kube-state-metrics.tolerations[0].value"
    value = "system"
  }

  set {
    name  = "kube-state-metrics.tolerations[0].effect"
    value = "NoSchedule"
  }

  depends_on = [kubernetes_namespace.monitoring]
}
