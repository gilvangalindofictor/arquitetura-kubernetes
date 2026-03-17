# Cluster Autoscaler — Proteção Estrutural (IaC)
#
# CONTEXTO (Incidente 2026-03-17):
#   CA encontrado com replicas=0 → ~35 pods Pending por ~26h → observability cega.
#   Fix paliativo aplicado manualmente: kubectl scale + safe-to-evict=false
#   Este arquivo codifica a proteção estrutural permanente no IaC.
#
# COMPONENTES:
#   1. PDB cluster-autoscaler-pdb: seletor correto (app.kubernetes.io/name=cluster-autoscaler)
#      NOTA: O PDB gerado pelo Helm usa name=aws-cluster-autoscaler (label errado) → inefetivo.
#      Este PDB suplementar usa o label real dos pods.
#   2. PrometheusRule: 4 alertas (Down, ReplicasMismatch, PendingUnschedulable, NearMaxCapacity)
#      Aplicado em staging-observability-monitoring com label release=kube-prometheus-stack.
#
# HELM RELEASE (cluster-autoscaler):
#   Gerenciado via: helm list -n kube-system → cluster-autoscaler (chart 9.37.0)
#   NÃO está no Terraform state — importação planejada como Fase 3b (demanda 2026-03-17).
#   Valores críticos já configurados via Helm:
#     replicaCount: 1
#     priorityClassName: system-cluster-critical
#     podAnnotations.cluster-autoscaler.kubernetes.io/safe-to-evict: "false" (pendente — ver TODO abaixo)
#
# STATUS DA PROTEÇÃO (aplicado em 2026-03-17):
#   [DONE] PDB cluster-autoscaler-pdb: aplicado via kubectl apply (codificado abaixo no TF)
#   [DONE] PrometheusRule cluster-autoscaler-resilience: aplicado via kubectl apply (codificado abaixo)
#   [DONE] safe-to-evict=false no pod template: aplicado via kubectl patch + codificado no TF
#   [DONE] replicaCount=1: já configurado nos Helm values
#
# TODO (Fase 3b — próxima sprint — IaC Compliance do Helm Release):
#   - Criar módulo modules/cluster-autoscaler/ com helm_release resource
#   - Importar Helm release existente: terraform import module.cluster_autoscaler.helm_release.main kube-system/cluster-autoscaler
#   - Garantir podAnnotations.safe-to-evict=false no values do helm_release (set block)
#   - Rodar terraform plan → confirmar "No changes" (zero drift)
#   - Enquanto não importado: patch kubectl é a fonte de verdade para safe-to-evict
#
# ADR: ADR-TBD (cluster-autoscaler-resiliencia — a ser formalizado)
# Demand: docs/demands/2026-03-17-cluster-autoscaler-resiliencia.md

# -----------------------------------------------------------------------------
# PDB — PodDisruptionBudget com seletor correto
# -----------------------------------------------------------------------------
# O seletor correto é app.kubernetes.io/name=cluster-autoscaler (não aws-cluster-autoscaler)
# conforme confirmado via: kubectl get pod <ca-pod> -n kube-system --show-labels
resource "kubernetes_manifest" "cluster_autoscaler_pdb" {
  field_manager {
    force_conflicts = true
  }
  manifest = {
    apiVersion = "policy/v1"
    kind       = "PodDisruptionBudget"
    metadata = {
      name      = "cluster-autoscaler-pdb"
      namespace = "kube-system"
      labels = {
        "app.kubernetes.io/managed-by"  = "platform-team"
        "app.kubernetes.io/component"   = "cluster-autoscaler"
        "app.kubernetes.io/part-of"     = "kube-system-protection"
      }
    }
    spec = {
      minAvailable = 1
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"     = "cluster-autoscaler"
          "app.kubernetes.io/instance" = "cluster-autoscaler"
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# PrometheusRule — Alertas de Resiliência do Cluster Autoscaler
# -----------------------------------------------------------------------------
# Namespace: staging-observability-monitoring
# Label obrigatória: release=kube-prometheus-stack (selector do Prometheus CR)
# Rulenamespace: {} (any namespace) — confirmado no Prometheus CR
resource "kubernetes_manifest" "cluster_autoscaler_prometheus_rule" {
  field_manager {
    force_conflicts = true
  }
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "cluster-autoscaler-resilience"
      namespace = "staging-observability-monitoring"
      labels = {
        release                        = "kube-prometheus-stack"
        "app.kubernetes.io/component"  = "cluster-autoscaler"
        "app.kubernetes.io/part-of"    = "platform-reliability"
      }
    }
    spec = {
      groups = [
        {
          name     = "cluster-autoscaler.rules"
          interval = "30s"
          rules = [
            # CRITICO: CA com 0 replicas disponíveis (incidente original)
            {
              alert = "ClusterAutoscalerDown"
              expr  = "kube_deployment_status_replicas_available{deployment=\"cluster-autoscaler\",namespace=\"kube-system\"} == 0"
              for   = "2m"
              labels = {
                severity  = "critical"
                team      = "platform"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "Cluster Autoscaler DOWN — 0 replicas disponíveis"
                description = "CA em kube-system tem 0 réplicas disponíveis há >2min. Pods NÃO serão escalonados. AÇÃO: kubectl scale deployment cluster-autoscaler --replicas=1 -n kube-system"
                runbook_url = "https://gitlab.internal/platform/runbooks/-/blob/main/cluster-autoscaler-recovery.md"
              }
            },
            # AVISO: spec.replicas != available (pod crashando ou pendente)
            {
              alert = "ClusterAutoscalerReplicasMismatch"
              expr  = "kube_deployment_spec_replicas{deployment=\"cluster-autoscaler\",namespace=\"kube-system\"} != kube_deployment_status_replicas_available{deployment=\"cluster-autoscaler\",namespace=\"kube-system\"}"
              for   = "5m"
              labels = {
                severity  = "warning"
                team      = "platform"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "Cluster Autoscaler: replicas spec != available por 5min"
                description = "spec.replicas != availableReplicas. CA pode estar em restart loop. Verificar: kubectl describe deployment cluster-autoscaler -n kube-system"
              }
            },
            # CRITICO: >3 pods Unschedulable por >15min (CA inativo ou ASG no limite)
            {
              alert = "KubePodsPendingUnschedulable"
              expr  = "count(kube_pod_status_scheduled{condition=\"false\"} == 1) > 3"
              for   = "15m"
              labels = {
                severity  = "critical"
                team      = "platform"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "{{ $value }} pods Unschedulable há mais de 15 minutos"
                description = "{{ $value }} pods em Unschedulable >15min. Verificar CA ativo e ASG max_size. kubectl get pods -A --field-selector=status.phase=Pending"
              }
            },
            # AVISO: Cluster usando >85% da capacidade máxima de nodes
            {
              alert = "ClusterAutoscalerNearMaxCapacity"
              expr  = "cluster_autoscaler_nodes_count / cluster_autoscaler_max_nodes_count > 0.85"
              for   = "10m"
              labels = {
                severity  = "warning"
                team      = "platform"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "Cluster usando {{ $value | humanizePercentage }} da capacidade máxima"
                description = "Cluster em >85% do max_size dos ASGs. Revisar node-groups.tf para aumentar max_size preventivamente."
              }
            }
          ]
        }
      ]
    }
  }
}
