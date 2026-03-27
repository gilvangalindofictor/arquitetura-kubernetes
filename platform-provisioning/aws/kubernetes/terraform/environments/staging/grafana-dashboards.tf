# =============================================================================
# GAP-CONF-020 (P2): Grafana Dashboards Customizados — Platform Components
# =============================================================================
# Problema: Grafana sem dashboards customizados para componentes de plataforma.
#   Apenas dashboards default do kube-prometheus-stack estao presentes.
#
# Solucao: ConfigMaps com label grafana_dashboard="1" no namespace do Grafana.
#   O sidecar do Grafana (kube-prometheus-stack) detecta automaticamente e
#   carrega os dashboards.
#
# Dashboards criados:
#   1. Harbor — metricas de registry, push/pull, storage
#   2. GitLab — metricas de CI/CD, webservice, Sidekiq
#   3. Vault  — metricas de seal status, token count, policy evaluations
#   4. Keycloak — metricas de login, sessions, token issuance
#
# NOTA: Os JSONs abaixo sao dashboards minimalistas com paineis essenciais.
#   Para dashboards completos, importar do Grafana Dashboard Registry (IDs).
#
# Ref: https://grafana.com/docs/grafana/latest/administration/provisioning/
# =============================================================================

locals {
  grafana_namespace = "staging-observability-monitoring"
}

# --- Harbor Dashboard ---
resource "kubernetes_config_map_v1" "grafana_dashboard_harbor" {
  metadata {
    name      = "grafana-dashboard-harbor"
    namespace = local.grafana_namespace
    labels = {
      grafana_dashboard              = "1"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-020"
    }
  }

  data = {
    "harbor-overview.json" = jsonencode({
      annotations = {
        list = []
      }
      editable    = true
      graphTooltip = 0
      id          = null
      links       = []
      panels = [
        {
          title      = "Harbor Core - HTTP Request Rate"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 0, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "rate(harbor_core_http_request_total[5m])"
            legendFormat = "{{method}} {{operation}}"
          }]
        },
        {
          title      = "Harbor Registry - Blob Upload/Download"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 12, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "rate(harbor_registry_http_request_total[5m])"
            legendFormat = "{{method}} {{handler}}"
          }]
        },
        {
          title      = "Harbor - Project Count"
          type       = "stat"
          gridPos    = { h = 4, w = 6, x = 0, y = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "harbor_project_total"
            legendFormat = "Projects"
          }]
        },
        {
          title      = "Harbor - Storage Used"
          type       = "stat"
          gridPos    = { h = 4, w = 6, x = 6, y = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "harbor_statistics_total_storage_consumption"
            legendFormat = "Bytes"
          }]
          fieldConfig = {
            defaults = {
              unit = "bytes"
            }
          }
        }
      ]
      schemaVersion = 39
      title         = "Harbor Overview"
      uid           = "harbor-overview-gap020"
      version       = 1
    })
  }
}

# --- GitLab Dashboard ---
resource "kubernetes_config_map_v1" "grafana_dashboard_gitlab" {
  metadata {
    name      = "grafana-dashboard-gitlab"
    namespace = local.grafana_namespace
    labels = {
      grafana_dashboard              = "1"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-020"
    }
  }

  data = {
    "gitlab-overview.json" = jsonencode({
      annotations = {
        list = []
      }
      editable    = true
      graphTooltip = 0
      id          = null
      links       = []
      panels = [
        {
          title      = "GitLab - HTTP Request Rate"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 0, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "rate(http_requests_total{job=~\".*gitlab.*\"}[5m])"
            legendFormat = "{{method}} {{status}}"
          }]
        },
        {
          title      = "GitLab - Sidekiq Job Queue"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 12, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "sidekiq_queue_size"
            legendFormat = "{{name}}"
          }]
        },
        {
          title      = "GitLab - CI Pipeline Duration (p95)"
          type       = "stat"
          gridPos    = { h = 4, w = 6, x = 0, y = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "histogram_quantile(0.95, rate(gitlab_ci_pipeline_duration_seconds_bucket[1h]))"
            legendFormat = "p95"
          }]
          fieldConfig = {
            defaults = {
              unit = "s"
            }
          }
        },
        {
          title      = "GitLab - Active Sessions"
          type       = "stat"
          gridPos    = { h = 4, w = 6, x = 6, y = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "gitlab_active_sessions_total"
            legendFormat = "Sessions"
          }]
        }
      ]
      schemaVersion = 39
      title         = "GitLab Overview"
      uid           = "gitlab-overview-gap020"
      version       = 1
    })
  }
}

# --- Vault Dashboard ---
resource "kubernetes_config_map_v1" "grafana_dashboard_vault" {
  metadata {
    name      = "grafana-dashboard-vault"
    namespace = local.grafana_namespace
    labels = {
      grafana_dashboard              = "1"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-020"
    }
  }

  data = {
    "vault-overview.json" = jsonencode({
      annotations = {
        list = []
      }
      editable    = true
      graphTooltip = 0
      id          = null
      links       = []
      panels = [
        {
          title      = "Vault - Seal Status"
          type       = "stat"
          gridPos    = { h = 4, w = 6, x = 0, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "vault_core_unsealed"
            legendFormat = "{{pod}}"
          }]
          fieldConfig = {
            defaults = {
              mappings = [
                { type = "value", options = { "0" = { text = "SEALED", color = "red" }, "1" = { text = "UNSEALED", color = "green" } } }
              ]
            }
          }
        },
        {
          title      = "Vault - Token Count"
          type       = "stat"
          gridPos    = { h = 4, w = 6, x = 6, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "vault_token_count"
            legendFormat = "Tokens"
          }]
        },
        {
          title      = "Vault - Request Rate"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 0, y = 4 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "rate(vault_core_handle_request_count[5m])"
            legendFormat = "{{pod}}"
          }]
        },
        {
          title      = "Vault - Secret Operations"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 12, y = 4 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [
            {
              expr         = "rate(vault_secret_kv_count[5m])"
              legendFormat = "KV count"
            },
            {
              expr         = "rate(vault_secret_lease_creation_count[5m])"
              legendFormat = "Lease creation"
            }
          ]
        },
        {
          title      = "Vault - HA Active Node"
          type       = "stat"
          gridPos    = { h = 4, w = 12, x = 12, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "vault_core_active"
            legendFormat = "{{pod}}"
          }]
          fieldConfig = {
            defaults = {
              mappings = [
                { type = "value", options = { "0" = { text = "STANDBY", color = "yellow" }, "1" = { text = "ACTIVE", color = "green" } } }
              ]
            }
          }
        }
      ]
      schemaVersion = 39
      title         = "Vault Overview"
      uid           = "vault-overview-gap020"
      version       = 1
    })
  }
}

# --- Keycloak Dashboard ---
resource "kubernetes_config_map_v1" "grafana_dashboard_keycloak" {
  metadata {
    name      = "grafana-dashboard-keycloak"
    namespace = local.grafana_namespace
    labels = {
      grafana_dashboard              = "1"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-020"
    }
  }

  data = {
    "keycloak-overview.json" = jsonencode({
      annotations = {
        list = []
      }
      editable    = true
      graphTooltip = 0
      id          = null
      links       = []
      panels = [
        {
          title      = "Keycloak - Login Events Rate"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 0, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "rate(keycloak_logins[5m])"
            legendFormat = "{{realm}} - {{provider}}"
          }]
        },
        {
          title      = "Keycloak - Failed Logins Rate"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 12, y = 0 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "rate(keycloak_failed_login_attempts[5m])"
            legendFormat = "{{realm}} - {{error}}"
          }]
        },
        {
          title      = "Keycloak - Active Sessions"
          type       = "stat"
          gridPos    = { h = 4, w = 6, x = 0, y = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "keycloak_active_user_sessions"
            legendFormat = "{{realm}}"
          }]
        },
        {
          title      = "Keycloak - Token Requests Rate"
          type       = "stat"
          gridPos    = { h = 4, w = 6, x = 6, y = 8 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "rate(keycloak_request_duration_count{method=\"POST\",uri=~\".*token.*\"}[5m])"
            legendFormat = "Tokens/s"
          }]
        },
        {
          title      = "Keycloak - JVM Memory"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 0, y = 12 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [
            {
              expr         = "jvm_memory_used_bytes{job=~\".*keycloak.*\"}"
              legendFormat = "{{area}} used"
            },
            {
              expr         = "jvm_memory_max_bytes{job=~\".*keycloak.*\"}"
              legendFormat = "{{area}} max"
            }
          ]
          fieldConfig = {
            defaults = {
              unit = "bytes"
            }
          }
        },
        {
          title      = "Keycloak - HTTP Response Time (p95)"
          type       = "timeseries"
          gridPos    = { h = 8, w = 12, x = 12, y = 12 }
          datasource = { type = "prometheus", uid = "prometheus" }
          targets = [{
            expr         = "histogram_quantile(0.95, rate(keycloak_request_duration_bucket[5m]))"
            legendFormat = "{{method}} {{uri}}"
          }]
          fieldConfig = {
            defaults = {
              unit = "s"
            }
          }
        }
      ]
      schemaVersion = 39
      title         = "Keycloak Overview"
      uid           = "keycloak-overview-gap020"
      version       = 1
    })
  }
}
