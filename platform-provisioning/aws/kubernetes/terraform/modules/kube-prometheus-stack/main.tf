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

  # Grafana OIDC client_secret via ESO K8s Secret (envValueFrom pattern)
  # ESO Secret: grafana-oidc-credentials (Vault: secret/grafana/oidc → keys: client_id, client_secret)
  # Grafana lê GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET via extraEnvFrom (env var = secret key name)
  # NOTA: lifecycle.ignore_changes=all → requer helm upgrade manual para ativar:
  #   helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  #     -n monitoring --reuse-values \
  #     --set "grafana.extraEnvFrom[0].secretRef.name=grafana-oidc-credentials"
  values = [<<-YAML
    grafana:
      extraEnvFrom:
        - secretRef:
            name: grafana-oidc-credentials
      grafana.ini:
        auth.generic_oauth:
          client_secret: "$__env{client_secret}"
  YAML
  ]

  # -----------------------------------------------------------------------------
  # Global Corporate Labels (ADR-048 - Kyverno Compliance)
  # -----------------------------------------------------------------------------

  set {
    name  = "commonLabels.domain"
    value = var.domain
  }

  set {
    name  = "commonLabels.owner"
    value = var.owner
  }

  set {
    name  = "commonLabels.environment"
    value = var.environment
  }

  # -----------------------------------------------------------------------------
  # Prometheus Operator
  # -----------------------------------------------------------------------------

  set {
    name  = "prometheusOperator.enabled"
    value = "true"
  }

  # Corporate Labels - Prometheus Operator
  set {
    name  = "prometheusOperator.labels.domain"
    value = var.domain
  }

  set {
    name  = "prometheusOperator.labels.owner"
    value = var.owner
  }

  set {
    name  = "prometheusOperator.labels.environment"
    value = var.environment
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

  # Corporate Labels - Prometheus
  set {
    name  = "prometheus.prometheusSpec.podMetadata.labels.domain"
    value = var.domain
  }

  set {
    name  = "prometheus.prometheusSpec.podMetadata.labels.owner"
    value = var.owner
  }

  set {
    name  = "prometheus.prometheusSpec.podMetadata.labels.environment"
    value = var.environment
  }

  set {
    name  = "prometheus.prometheusSpec.podMetadata.labels.app\\.kubernetes\\.io/part-of"
    value = "observability"
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

  # Corporate Labels - Grafana
  set {
    name  = "grafana.podLabels.domain"
    value = var.domain
  }

  set {
    name  = "grafana.podLabels.owner"
    value = var.owner
  }

  set {
    name  = "grafana.podLabels.environment"
    value = var.environment
  }

  set {
    name  = "grafana.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
  }

  # Admin credentials — V-001 remediation:
  # When grafana_admin_use_existing_secret=true, uses K8s Secret from ESO (Vault → ESO → existingSecret)
  # When false (legacy), falls back to plaintext grafana.adminPassword (DEPRECATED)

  # Legacy: plaintext password (only when NOT using existing secret)
  dynamic "set" {
    for_each = var.grafana_admin_use_existing_secret ? [] : [1]
    content {
      name  = "grafana.adminPassword"
      value = var.grafana_admin_password
    }
  }

  # V-001: existingSecret from ESO (Vault: secret/grafana/admin)
  dynamic "set" {
    for_each = var.grafana_admin_use_existing_secret ? [1] : []
    content {
      name  = "grafana.admin.existingSecret"
      value = var.grafana_admin_existing_secret_name
    }
  }

  dynamic "set" {
    for_each = var.grafana_admin_use_existing_secret ? [1] : []
    content {
      name  = "grafana.admin.passwordKey"
      value = "admin-password"
    }
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

  # -----------------------------------------------------------------------------
  # Grafana OIDC — Keycloak SSO (auth.generic_oauth)
  # ATENÇÃO: ignore_changes=all neste helm_release — set blocks definem IaC como
  # source of truth, mas apply requer helm upgrade manual após Keycloak ready:
  #   helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  #     -n monitoring --reuse-values \
  #     --set "grafana.grafana\.ini.auth\.generic_oauth.enabled=true" ...
  # -----------------------------------------------------------------------------

  dynamic "set" {
    for_each = var.grafana_oidc_enabled ? [1] : []
    content {
      name  = "grafana.grafana\\.ini.auth\\.generic_oauth.enabled"
      value = "true"
    }
  }

  dynamic "set" {
    for_each = var.grafana_oidc_enabled ? [1] : []
    content {
      name  = "grafana.grafana\\.ini.auth\\.generic_oauth.name"
      value = "Keycloak"
    }
  }

  dynamic "set" {
    for_each = var.grafana_oidc_enabled ? [1] : []
    content {
      name  = "grafana.grafana\\.ini.auth\\.generic_oauth.client_id"
      value = var.grafana_keycloak_client_id
    }
  }

  # client_secret removido do set block — agora via envValueFrom (ESO K8s Secret)
  # ESO Secret: grafana-oidc-credentials (Vault: secret/grafana/oidc)
  # Grafana lê GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET via extraEnvFrom abaixo

  dynamic "set" {
    for_each = var.grafana_oidc_enabled ? [1] : []
    content {
      name  = "grafana.grafana\\.ini.auth\\.generic_oauth.scopes"
      value = "openid email profile"
    }
  }

  dynamic "set" {
    for_each = var.grafana_oidc_enabled && var.grafana_keycloak_url != "" ? [1] : []
    content {
      name  = "grafana.grafana\\.ini.auth\\.generic_oauth.auth_url"
      value = "${var.grafana_keycloak_url}/realms/platform/protocol/openid-connect/auth"
    }
  }

  dynamic "set" {
    for_each = var.grafana_oidc_enabled && var.grafana_keycloak_url != "" ? [1] : []
    content {
      name  = "grafana.grafana\\.ini.auth\\.generic_oauth.token_url"
      value = "${var.grafana_keycloak_url}/realms/platform/protocol/openid-connect/token"
    }
  }

  dynamic "set" {
    for_each = var.grafana_oidc_enabled && var.grafana_keycloak_url != "" ? [1] : []
    content {
      name  = "grafana.grafana\\.ini.auth\\.generic_oauth.api_url"
      value = "${var.grafana_keycloak_url}/realms/platform/protocol/openid-connect/userinfo"
    }
  }

  dynamic "set" {
    for_each = var.grafana_oidc_enabled ? [1] : []
    content {
      name  = "grafana.grafana\\.ini.auth\\.generic_oauth.role_attribute_path"
      value = "contains(groups[*], 'grafana-admins') && 'Admin' || 'Viewer'"
    }
  }

  dynamic "set" {
    for_each = var.grafana_oidc_enabled ? [1] : []
    content {
      name  = "grafana.grafana\\.ini.auth\\.generic_oauth.allow_sign_up"
      value = "true"
    }
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

  # Corporate Labels - Alertmanager
  set {
    name  = "alertmanager.alertmanagerSpec.podMetadata.labels.domain"
    value = var.domain
  }

  set {
    name  = "alertmanager.alertmanagerSpec.podMetadata.labels.owner"
    value = var.owner
  }

  set {
    name  = "alertmanager.alertmanagerSpec.podMetadata.labels.environment"
    value = var.environment
  }

  set {
    name  = "alertmanager.alertmanagerSpec.podMetadata.labels.app\\.kubernetes\\.io/part-of"
    value = "observability"
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

  # Corporate Labels - Node Exporter
  set {
    name  = "prometheus-node-exporter.podLabels.domain"
    value = var.domain
  }

  set {
    name  = "prometheus-node-exporter.podLabels.owner"
    value = var.owner
  }

  set {
    name  = "prometheus-node-exporter.podLabels.environment"
    value = var.environment
  }

  set {
    name  = "prometheus-node-exporter.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
  }

  # -----------------------------------------------------------------------------
  # Kube State Metrics
  # -----------------------------------------------------------------------------

  set {
    name  = "kubeStateMetrics.enabled"
    value = "true"
  }

  # Corporate Labels - Kube State Metrics
  set {
    name  = "kube-state-metrics.podLabels.domain"
    value = var.domain
  }

  set {
    name  = "kube-state-metrics.podLabels.owner"
    value = var.owner
  }

  set {
    name  = "kube-state-metrics.podLabels.environment"
    value = var.environment
  }

  set {
    name  = "kube-state-metrics.podLabels.app\\.kubernetes\\.io/part-of"
    value = "observability"
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

# -----------------------------------------------------------------------------
# Grafana Admin Password — ExternalSecret (V-001 Remediation)
# Vault path: secret/data/grafana/admin
#   key: password → mapped to K8s secret key: admin-password
# Target: grafana-admin-credentials (referenced by grafana.admin.existingSecret)
# eso-reader policy: secret/data/grafana/* (already granted in eso-reader.hcl)
# Prerequisite: vault kv put secret/grafana/admin password=<strong-password>
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "grafana_admin_externalsecret" {
  count = var.grafana_admin_use_existing_secret ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "grafana-admin-credentials"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = var.grafana_admin_existing_secret_name
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "admin-password"
          remoteRef = {
            key      = "secret/data/grafana/admin"
            property = "password"
          }
        }
      ]
    }
  })

  depends_on = [kubernetes_namespace.monitoring]
}

# -----------------------------------------------------------------------------
# Grafana OIDC — ExternalSecret (credenciais Keycloak via Vault)
# Vault path: secret/data/grafana/oidc
#   keys: client_id, client_secret
# Pré-requisito: Keycloak client "grafana" criado e secret adicionado ao Vault
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "grafana_oidc_externalsecret" {
  count = var.grafana_oidc_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "grafana-oidc-credentials"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "grafana-oidc-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "client_id"
          remoteRef = {
            key      = "secret/data/grafana/oidc"
            property = "client_id"
          }
        },
        {
          secretKey = "client_secret"
          remoteRef = {
            key      = "secret/data/grafana/oidc"
            property = "client_secret"
          }
        }
      ]
    }
  })

  depends_on = [kubernetes_namespace.monitoring]
}
