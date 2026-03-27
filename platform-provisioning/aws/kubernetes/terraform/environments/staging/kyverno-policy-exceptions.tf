# =============================================================================
# GAP-CONF-027 (P3): Kyverno Policy Spam — Exclude prometheus-operated
# =============================================================================
# Problema: A policy validate-service-naming (docs/governance/validation-rules.yaml)
#   gera eventos de validacao (PolicyReport) para o Service "prometheus-operated"
#   criado automaticamente pelo Prometheus Operator. Este service usa o nome
#   "prometheus-operated" (convencao upstream, nao controlavel pelo usuario) e
#   gera spam nos PolicyReports do Kyverno.
#
# Solucao: PolicyException que exclui "prometheus-operated" da regra
#   validate-service-naming. A policy continua ativa para todos os demais Services.
#
# NOTA: A policy validate-service-naming nao esta gerenciada por TF — esta em
#   docs/governance/validation-rules.yaml (aplicada via kubectl apply manual).
#   A solucao ideal seria:
#   1. Migrar a policy para TF (como kubectl_manifest)
#   2. Adicionar exclude diretamente na policy
#   Enquanto isso, PolicyException e a abordagem mais segura (nao requer alterar
#   a policy existente).
#
# Alternativa considerada: Adicionar exclude na propria ClusterPolicy. Rejeitada
#   porque a policy nao e gerenciada por TF (risco de drift com apply manual).
#
# Ref: GAP-KYVERNO-POLICY-SPAM (MEMORY.md)
#      docs/governance/validation-rules.yaml (policy source)
# =============================================================================

resource "kubectl_manifest" "kyverno_exception_prometheus_operated" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v2
    kind: PolicyException
    metadata:
      name: exception-prometheus-operated-service-naming
      namespace: staging-observability-monitoring
      labels:
        app.kubernetes.io/managed-by: terraform
        governance.platform/gap: GAP-CONF-027
      annotations:
        policies.kyverno.io/title: Exception — prometheus-operated Service naming
        policies.kyverno.io/description: >-
          Exclui o Service "prometheus-operated" da policy validate-service-naming.
          Este Service e criado automaticamente pelo Prometheus Operator com nome
          fixo upstream — nao pode ser renomeado sem quebrar o ServiceMonitor discovery.
          Ref: GAP-KYVERNO-POLICY-SPAM.
    spec:
      exceptions:
        - policyName: validate-service-naming
          ruleNames:
            - check-service-name
      match:
        any:
          - resources:
              kinds:
                - Service
              names:
                - "prometheus-operated"
                - "alertmanager-operated"
              namespaces:
                - "staging-observability-monitoring"
                - "prod-observability-monitoring"
  YAML

  lifecycle {
    ignore_changes = [
      yaml_body,
    ]
  }
}
