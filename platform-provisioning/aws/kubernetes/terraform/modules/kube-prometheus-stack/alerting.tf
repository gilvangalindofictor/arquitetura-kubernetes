# -----------------------------------------------------------------------------
# GAP-OBS-ALERTING-001 — Alertmanager routing + PrometheusRules essenciais
#
# PROBLEMA: Alertmanager deployado sem receiver ou routing configurado.
#           Todos os alertas Prometheus vão para o receiver "null" padrão —
#           silêncio total em incidentes P0/P1.
#
# SOLUÇÃO:
#   1. AlertmanagerConfig  — routing funcional por severity + environment
#   2. PrometheusRule      — 4 alertas essenciais não cobertos pelo chart padrão
#
# ATIVAR: passar `alertmanager_webhook_url` na chamada do módulo.
#         Se vazio (default), AlertmanagerConfig NÃO é criado (safe default).
#
# COMPATIBILIDADE: Alertmanager Operator CRD (kube-prometheus-stack >= v45)
#   AlertmanagerConfig é namespace-scoped e referenciado pelo CR Alertmanager
#   via `alertmanagerConfigSelector` (o chart configura automaticamente).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# AlertmanagerConfig — Routing + Receiver genérico (webhook)
#
# Funciona com:
#   - Slack incoming webhooks
#   - Microsoft Teams (via incoming webhook ou power automate URL)
#   - PagerDuty Events v2 (via pagerduty_url adapter — use receiver "pagerduty" nativo se preferir)
#   - Qualquer HTTP endpoint que aceite POST JSON
#
# Routing:
#   - severity=critical  → webhook (P0 — notificação imediata)
#   - severity=warning   → webhook (P1 — notificação com group_wait maior)
#   - demais             → null   (P2/info — evitar spam)
#   - Por environment label quando presente (prod vs staging isolados)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "alertmanager_config" {
  # Condicional: só cria se webhook URL foi fornecida.
  # Default vazio = AlertmanagerConfig ausente = Alertmanager usa config padrão do chart.
  count = var.alertmanager_webhook_url != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1alpha1"
    kind       = "AlertmanagerConfig"
    metadata = {
      name      = "platform-alerting"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
      labels = {
        # Label obrigatória para o Alertmanager Operator selecionar esta config
        "alertmanagerConfig" = "platform-alerting"
        # Corporate labels (ADR-048)
        "domain"                    = var.domain
        "owner"                     = var.owner
        "environment"               = var.environment
        "app.kubernetes.io/name"    = "alertmanager-config"
        "app.kubernetes.io/part-of" = "observability"
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = {
      # ------------------------------------------------------------------
      # Receivers
      # ------------------------------------------------------------------
      receivers = [
        # Receiver null — destino para alertas P2/info (sem notificação)
        {
          name = "null"
        },
        # Receiver genérico via webhook — suporta Slack, Teams, PagerDuty, custom HTTP
        # URL configurada via var.alertmanager_webhook_url (nunca hardcoded)
        {
          name = "platform-webhook"
          webhookConfigs = [
            {
              url            = var.alertmanager_webhook_url
              sendResolved   = true
              # HTTP config básico — sem auth hardcoded.
              # Para autenticação, adicionar httpConfig.authorization ou
              # httpConfig.basicAuth via ExternalSecret no Vault.
              httpConfig = {
                followRedirects = true
              }
            }
          ]
        }
      ]

      # ------------------------------------------------------------------
      # Route tree
      #
      # Hierarquia:
      #   root (catch-all → null)
      #   └─ severity=critical  → platform-webhook (group_wait=0s, repeat=1h)
      #   └─ severity=warning   → platform-webhook (group_wait=5m, repeat=4h)
      #
      # group_by inclui "environment" para isolar staging de prod nas notificações.
      # Nota: AlertmanagerConfig routes são FILHOS do route raiz global do chart.
      # O route raiz do chart tem group_by=[job]; aqui sobrescrevemos para o subárvore.
      # ------------------------------------------------------------------
      route = {
        # Receiver padrão deste subárvore (alertas não matched pelas rotas filhas)
        receiver = "null"

        # Agrupamento: environment separa staging/prod; alertname agrupa alertas similares
        groupBy = ["environment", "alertname", "namespace"]

        # Rotas filhas — avaliadas em ordem; primeira que casar é aplicada
        routes = [
          # P0 — Critical: notificar imediatamente, repetir a cada hora
          {
            receiver = "platform-webhook"
            matchers = [
              {
                name  = "severity"
                value = "critical"
                matchType = "="
              }
            ]
            groupWait      = "0s"
            groupInterval  = "1m"
            repeatInterval = "1h"
            continue       = false
          },
          # P1 — Warning: aguardar 5 min para agrupar, repetir a cada 4 horas
          {
            receiver = "platform-webhook"
            matchers = [
              {
                name  = "severity"
                value = "warning"
                matchType = "="
              }
            ]
            groupWait      = "5m"
            groupInterval  = "5m"
            repeatInterval = "4h"
            continue       = false
          }
          # P2/info/none — não declarados explicitamente → caem no receiver "null" do route pai
        ]
      }
    }
  })

  depends_on = [
    helm_release.kube_prometheus_stack,
    kubernetes_namespace.monitoring,
  ]
}

# -----------------------------------------------------------------------------
# PrometheusRule — Alertas essenciais não cobertos pelo chart padrão
#
# Alertas incluídos:
#   1. KubeDaemonSetNotScheduled      — DaemonSet pods Pending (ex: node-exporter em node cheio)
#   2. PersistentVolumeCapacityWarning — PVC com uso > 80% (previne OOM de storage)
#   3. LokiWriteOOMRisk               — Loki write pod memory > 80% limit (previne OOMKilled)
#   4. VaultSealedAlert               — Vault pods não-Ready por > 5min (incidente P0)
#
# Referência GAP: GAP-OBS-ALERTING-001
# Namespace: mesmo namespace do módulo (staging-observability-monitoring / monitoring)
# Selector: o Prometheus CR usa prometheusRuleSelector=nil → seleciona todas as regras
#           no mesmo namespace (serviceMonitorSelectorNilUsesHelmValues=false está configurado)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "prometheus_rules_platform" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "platform-essential-alerts"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
      labels = {
        # Label padrão do chart para seleção de regras (prometheusRuleSelector)
        "release"                   = "kube-prometheus-stack"
        "app"                       = "kube-prometheus-stack"
        # Corporate labels (ADR-048)
        "domain"                    = var.domain
        "owner"                     = var.owner
        "environment"               = var.environment
        "app.kubernetes.io/name"    = "prometheus-rules"
        "app.kubernetes.io/part-of" = "observability"
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = {
      groups = [
        # ------------------------------------------------------------------
        # Grupo 1: Scheduling & DaemonSets
        # ------------------------------------------------------------------
        {
          name = "platform.scheduling"
          rules = [
            # GAP-OBS-ALERTING-001 / Rule 1
            # Detecta DaemonSet pods que não puderam ser agendados (Pending por > 5 min).
            # Contexto: node-exporter ficou Pending em ip-10-0-149-203 (17/17 pod limit).
            # Origem métrica: kube_daemonset_status_desired_number_scheduled (kube-state-metrics)
            {
              alert = "KubeDaemonSetNotScheduled"
              expr  = "kube_daemonset_status_desired_number_scheduled{job=\"kube-state-metrics\"} - kube_daemonset_status_current_number_scheduled{job=\"kube-state-metrics\"} > 0"
              "for" = "5m"
              labels = {
                severity    = "warning"
                environment = var.environment
                team        = "platform"
              }
              annotations = {
                summary     = "DaemonSet {{ $labels.namespace }}/{{ $labels.daemonset }} tem pods não agendados"
                description = "{{ $value }} pod(s) do DaemonSet {{ $labels.namespace }}/{{ $labels.daemonset }} não puderam ser agendados por mais de 5 minutos. Verificar recursos dos nodes (pod limit, taint, nodeSelector)."
                runbook_url = "https://runbooks.prometheus-operator.dev/runbooks/kubernetes/kubedaemonsetnotscheduled"
              }
            }
          ]
        },

        # ------------------------------------------------------------------
        # Grupo 2: Storage
        # ------------------------------------------------------------------
        {
          name = "platform.storage"
          rules = [
            # GAP-OBS-ALERTING-001 / Rule 2
            # Detecta PVCs com uso acima de 80% de capacidade.
            # Evita falhas silenciosas de escrita (Loki, Vault, Grafana, etc.).
            # Origem métrica: kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes
            {
              alert = "PersistentVolumeCapacityWarning"
              expr  = <<-PROMQL
                (
                  kubelet_volume_stats_used_bytes{job="kubelet"}
                  /
                  kubelet_volume_stats_capacity_bytes{job="kubelet"}
                ) * 100 > 80
              PROMQL
              "for" = "5m"
              labels = {
                severity    = "warning"
                environment = var.environment
                team        = "platform"
              }
              annotations = {
                summary     = "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} acima de 80% de uso"
                description = "O volume {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} está com {{ printf \"%.1f\" $value }}% de uso. Considerar expansão do PVC (EBS gp3 suporta online resize)."
              }
            }
          ]
        },

        # ------------------------------------------------------------------
        # Grupo 3: Observability — Loki
        # ------------------------------------------------------------------
        {
          name = "platform.loki"
          rules = [
            # GAP-OBS-ALERTING-001 / Rule 3
            # Detecta risco de OOMKilled no Loki write component.
            # Contexto: Loki write processa ingestão contínua — OOMKilled causa perda de logs.
            # Lição 23: default chunksCache.resources.requests.cpu=500m (over-provision 125:1).
            # Memory limit do write pod: configurado no módulo loki (variável loki_write_memory_limit).
            # Origem métrica: container_memory_working_set_bytes / kube_pod_container_resource_limits
            {
              alert = "LokiWriteOOMRisk"
              expr  = <<-PROMQL
                (
                  container_memory_working_set_bytes{
                    job="kubelet",
                    container="loki",
                    pod=~"loki-write-.*"
                  }
                  /
                  kube_pod_container_resource_limits{
                    resource="memory",
                    container="loki",
                    pod=~"loki-write-.*"
                  }
                ) * 100 > 80
              PROMQL
              "for" = "10m"
              labels = {
                severity    = "warning"
                environment = var.environment
                team        = "platform"
              }
              annotations = {
                summary     = "Loki write pod {{ $labels.namespace }}/{{ $labels.pod }} acima de 80% de memory limit"
                description = "Pod {{ $labels.pod }} está usando {{ printf \"%.1f\" $value }}% do memory limit. Risco de OOMKilled e perda de logs de ingestão. Revisar memory limit ou right-size do chunksCache."
              }
            }
          ]
        },

        # ------------------------------------------------------------------
        # Grupo 4: Security — Vault
        # ------------------------------------------------------------------
        {
          name = "platform.vault"
          rules = [
            # GAP-OBS-ALERTING-001 / Rule 4
            # Detecta Vault pods não-Ready por mais de 5 minutos.
            # Inclui both staging (1 replica) e prod (3 replicas Raft HA).
            # Not-Ready inclui: sealed, crash, pending, OOMKilled, network issues.
            # Origem métrica: kube_pod_status_ready (kube-state-metrics)
            {
              alert = "VaultSealedAlert"
              expr  = <<-PROMQL
                kube_pod_status_ready{
                  job="kube-state-metrics",
                  pod=~"vault(-prod)?-[0-9]+",
                  condition="true"
                } == 0
              PROMQL
              "for" = "5m"
              labels = {
                severity    = "critical"
                environment = var.environment
                team        = "platform"
              }
              annotations = {
                summary     = "Vault pod {{ $labels.namespace }}/{{ $labels.pod }} não está Ready"
                description = "Pod Vault {{ $labels.pod }} (namespace {{ $labels.namespace }}) não está em estado Ready há mais de 5 minutos. Pode estar sealed, crashando ou com problema de rede. Verificar: kubectl logs {{ $labels.pod }} -n {{ $labels.namespace }}; kubectl exec {{ $labels.pod }} -n {{ $labels.namespace }} -- vault status"
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    helm_release.kube_prometheus_stack,
    kubernetes_namespace.monitoring,
  ]
}
