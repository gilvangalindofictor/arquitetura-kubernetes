# =============================================================================
# GAP-CONF-008: Dead Man's Switch — Staging
#
# PrometheusRule com Watchdog alert que verifica pipeline de alerting funcional.
# Referencia: ROADMAP Enterprise INIT-008 (Dead Man's Switch)
#
# Componentes:
#   1. Watchdog: vector(1) — SEMPRE dispara. Se parar de disparar, Prometheus esta DOWN.
#   2. DeadMansSwitch: absent(up{job=...}) — dispara se Prometheus parar de reportar.
#
# Namespace: staging-observability-monitoring (mesmo do kube-prometheus-stack)
# Label: release=kube-prometheus-stack (selector do Prometheus CR)
#
# Validacao pos-apply:
#   kubectl get prometheusrule dead-mans-switch -n staging-observability-monitoring
#   kubectl port-forward svc/kube-prometheus-stack-prometheus 9090 -n staging-observability-monitoring
#   curl -s localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="Watchdog")'
# =============================================================================

resource "kubectl_manifest" "dead_mans_switch_staging" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: dead-mans-switch
      namespace: staging-observability-monitoring
      labels:
        release: kube-prometheus-stack
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: alerting-pipeline
        app.kubernetes.io/part-of: platform-reliability
        domain: operations
        owner: platform-team
        environment: staging
    spec:
      groups:
        - name: dead-mans-switch
          rules:
            # Watchdog: fires continuously to confirm alerting pipeline is functional.
            # If this alert stops firing in Alertmanager, it means Prometheus -> Alertmanager
            # pipeline is broken. External monitoring (PagerDuty, Grafana OnCall) should
            # alert on ABSENCE of this Watchdog.
            - alert: Watchdog
              annotations:
                description: >-
                  This alert fires continuously to verify the alerting pipeline is functional.
                  If you stop receiving this alert, Prometheus or Alertmanager may be down.
                summary: "Alerting pipeline Watchdog — always firing"
              expr: vector(1)
              labels:
                severity: none

            # DeadMansSwitch: fires when Prometheus itself stops reporting up metric.
            # This catches the case where Prometheus is down but Alertmanager is still running
            # with stale state.
            - alert: DeadMansSwitch
              annotations:
                description: >-
                  Prometheus or Alertmanager stopped firing. The up metric for the Prometheus
                  job is absent for more than 5 minutes. Investigate immediately.
                summary: "Prometheus self-monitoring absent — alerting pipeline may be broken"
                runbook_url: "https://gitlab.internal/platform/runbooks/-/blob/main/dead-mans-switch.md"
              expr: absent(up{job="prometheus-kube-prometheus-prometheus"})
              for: 5m
              labels:
                severity: critical

            # InfoInhibitor: used to inhibit info-level alerts when they are not useful
            # (standard kube-prometheus-stack pattern — keeps consistency)
            - alert: InfoInhibitor
              annotations:
                description: >-
                  This is an inhibitor alert that is used to inhibit info severity alerts.
                  It fires when there is a severity=info alert firing and is used by Alertmanager
                  inhibition rules.
                summary: "Info-level alert inhibitor"
              expr: ALERTS{severity="info"} == 1 unless ALERTS{alertname!="InfoInhibitor",severity="info"}
              labels:
                severity: none
  YAML
}
