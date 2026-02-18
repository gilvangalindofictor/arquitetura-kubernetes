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

  # Timeout aumentado devido ao número de CRDs e tempo de inicialização dos pods
  # 30 minutos para primeira instalação, suficiente para downloads de imagens e criação de CRDs
  timeout = 1800

  # -----------------------------------------------------------------------------
  # Prometheus Operator
  # -----------------------------------------------------------------------------

  set {
    name  = "prometheusOperator.enabled"
    value = "true"
  }

  # nodeSelector removido: pods podem escalar em qualquer node disponível
  # (fix 2026-02-18: system nodes 17/17 pods bloqueavam scheduling)

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
    value = "gp2"
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

  # nodeSelector removido: pods podem escalar em qualquer node disponível

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

  # Toleration for critical nodes (ADR-041 pattern)
  set {
    name  = "prometheus.prometheusSpec.tolerations[1].key"
    value = "workload"
  }

  set {
    name  = "prometheus.prometheusSpec.tolerations[1].operator"
    value = "Equal"
  }

  set {
    name  = "prometheus.prometheusSpec.tolerations[1].value"
    value = "critical"
  }

  set {
    name  = "prometheus.prometheusSpec.tolerations[1].effect"
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
    value = "gp2"
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

  # nodeSelector removido: grafana pode escalar em qualquer node disponível

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

  # Toleration for critical nodes (ADR-041 pattern)
  set {
    name  = "grafana.tolerations[1].key"
    value = "workload"
  }

  set {
    name  = "grafana.tolerations[1].operator"
    value = "Equal"
  }

  set {
    name  = "grafana.tolerations[1].value"
    value = "critical"
  }

  set {
    name  = "grafana.tolerations[1].effect"
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

  # ALB Annotations para Grafana Ingress
  dynamic "set" {
    for_each = var.grafana_ingress_enabled ? [1] : []
    content {
      name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
      value = "internet-facing"
    }
  }

  dynamic "set" {
    for_each = var.grafana_ingress_enabled ? [1] : []
    content {
      name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
      value = "ip"
    }
  }

  dynamic "set" {
    for_each = var.grafana_ingress_enabled ? [1] : []
    content {
      name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/backend-protocol"
      value = "HTTP"
    }
  }

  dynamic "set" {
    for_each = var.grafana_ingress_enabled ? [1] : []
    content {
      name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports"
      value = "[{\"HTTP\":80}]"
    }
  }

  dynamic "set" {
    for_each = var.grafana_ingress_enabled ? [1] : []
    content {
      name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/healthcheck-path"
      value = "/api/health"
    }
  }

  dynamic "set" {
    for_each = var.grafana_ingress_enabled && var.grafana_ingress_group_name != "" ? [1] : []
    content {
      name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/group\\.name"
      value = var.grafana_ingress_group_name
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
    value = "gp2"
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

  # nodeSelector removido: alertmanager pode escalar em qualquer node disponível

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

  # Toleration for critical nodes (ADR-041 pattern)
  set {
    name  = "alertmanager.alertmanagerSpec.tolerations[1].key"
    value = "workload"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.tolerations[1].operator"
    value = "Equal"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.tolerations[1].value"
    value = "critical"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.tolerations[1].effect"
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

  # nodeSelector removido: kube-state-metrics pode escalar em qualquer node disponível

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

  lifecycle {
    # kube-prometheus-stack v81.4.2 deployed and stable.
    # Repeat upgrades trigger rolling updates that fail due to system node capacity limits.
    # Apply changes manually: helm upgrade kube-prometheus-stack -n monitoring
    ignore_changes = all
  }
}
