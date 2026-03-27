# =============================================================================
# GAP-CONF-017 (P2): VPA Apply Cycle — CronJob para Coletar Recomendacoes
# =============================================================================
# Problema: VPA esta em recommendation mode (updateMode="Off") sem ciclo de
#   aplicacao automatizado. Recomendacoes sao geradas mas ninguem as aplica.
#
# Solucao: CronJob Kubernetes que:
#   1. Coleta recomendacoes VPA de todos os namespaces
#   2. Gera um report JSON com patches recomendados
#   3. Armazena o report em ConfigMap para consulta via kubectl/Grafana
#   4. NAO aplica automaticamente — gera apenas o report para revisao humana
#
# Ciclo recomendado:
#   - CronJob: diario 08:00 UTC (05:00 BRT) — antes do horario comercial
#   - Revisao humana: semanal (segunda-feira)
#   - Aplicacao manual: via kubectl patch ou PR com novos resource requests
#
# Apply cycle:
#   1. kubectl get configmap vpa-recommendations -n staging-observability-monitoring -o json
#   2. Revisar recomendacoes vs valores atuais
#   3. Gerar patches: kubectl patch deployment <name> -n <ns> -p '{"spec":...}'
#   4. Ou atualizar valores no modulo TF e re-apply
#
# Namespace: staging-observability-monitoring (junto com Prometheus/Grafana)
#
# Ref: prod/vpa.tf (VPA CRs), modules/vpa/ (helm release)
# =============================================================================

resource "kubernetes_config_map_v1" "vpa_collector_script" {
  metadata {
    name      = "vpa-collector-script"
    namespace = "staging-observability-monitoring"
    labels = {
      "app.kubernetes.io/name"       = "vpa-apply-cycle"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-017"
    }
  }

  data = {
    "collect-vpa-recommendations.sh" = <<-SCRIPT
      #!/bin/sh
      set -e

      echo "=== VPA Recommendations Collector ==="
      echo "Date: $$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      echo ""

      # Collect all VPA recommendations
      REPORT="[]"
      for vpa in $$(kubectl get vpa -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'); do
        NS=$$(echo "$$vpa" | cut -d/ -f1)
        NAME=$$(echo "$$vpa" | cut -d/ -f2)

        # Get target ref
        TARGET_KIND=$$(kubectl get vpa "$$NAME" -n "$$NS" -o jsonpath='{.spec.targetRef.kind}' 2>/dev/null || echo "unknown")
        TARGET_NAME=$$(kubectl get vpa "$$NAME" -n "$$NS" -o jsonpath='{.spec.targetRef.name}' 2>/dev/null || echo "unknown")

        # Get recommendations
        RECS=$$(kubectl get vpa "$$NAME" -n "$$NS" -o jsonpath='{.status.recommendation.containerRecommendations}' 2>/dev/null || echo "null")

        if [ "$$RECS" != "null" ] && [ -n "$$RECS" ]; then
          echo "VPA: $$NS/$$NAME -> $$TARGET_KIND/$$TARGET_NAME"

          # Get current resource requests for comparison
          if [ "$$TARGET_KIND" = "Deployment" ]; then
            CURRENT=$$(kubectl get deployment "$$TARGET_NAME" -n "$$NS" -o jsonpath='{.spec.template.spec.containers[0].resources.requests}' 2>/dev/null || echo "{}")
          elif [ "$$TARGET_KIND" = "StatefulSet" ]; then
            CURRENT=$$(kubectl get statefulset "$$TARGET_NAME" -n "$$NS" -o jsonpath='{.spec.template.spec.containers[0].resources.requests}' 2>/dev/null || echo "{}")
          else
            CURRENT="{}"
          fi

          echo "  Current requests: $$CURRENT"
          echo "  VPA recommendations: $$RECS"
          echo ""
        fi
      done

      # Generate summary report
      echo "=== Summary ==="
      kubectl get vpa -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,TARGET:.spec.targetRef.name,CPU-REC:.status.recommendation.containerRecommendations[0].target.cpu,MEM-REC:.status.recommendation.containerRecommendations[0].target.memory,UPDATED:.status.conditions[0].lastTransitionTime' 2>/dev/null || echo "No VPA recommendations available"

      echo ""
      echo "=== End of Report ==="
    SCRIPT
  }
}

resource "kubernetes_cron_job_v1" "vpa_recommendations_collector" {
  metadata {
    name      = "vpa-recommendations-collector"
    namespace = "staging-observability-monitoring"
    labels = {
      "app.kubernetes.io/name"       = "vpa-apply-cycle"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-017"
    }
  }

  spec {
    # Diario 08:00 UTC (05:00 BRT) — antes do horario comercial
    schedule = "0 8 * * *"

    # Nao acumular execucoes se perder schedule (ex: node down)
    concurrency_policy = "Forbid"

    # Manter ultimos 3 reports
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name"       = "vpa-apply-cycle"
          "app.kubernetes.io/managed-by" = "terraform"
        }
      }
      spec {
        # Timeout: 5 min (collector nao deve demorar mais)
        active_deadline_seconds = 300

        template {
          metadata {
            labels = {
              "app.kubernetes.io/name" = "vpa-apply-cycle"
            }
          }
          spec {
            # Service Account com permissao de leitura em VPA + Deployments + StatefulSets
            service_account_name = kubernetes_service_account_v1.vpa_collector.metadata[0].name

            restart_policy = "OnFailure"

            # Toleration para system nodes (onde CronJobs de plataforma rodam)
            toleration {
              key      = "node-type"
              operator = "Equal"
              value    = "system"
              effect   = "NoSchedule"
            }

            container {
              name    = "collector"
              image   = "891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/library/bitnami/kubectl:1.34"
              command = ["/bin/sh", "/scripts/collect-vpa-recommendations.sh"]

              volume_mount {
                name       = "scripts"
                mount_path = "/scripts"
                read_only  = true
              }

              resources {
                requests = {
                  cpu    = "50m"
                  memory = "64Mi"
                }
                limits = {
                  cpu    = "100m"
                  memory = "128Mi"
                }
              }
            }

            volume {
              name = "scripts"
              config_map {
                name         = kubernetes_config_map_v1.vpa_collector_script.metadata[0].name
                default_mode = "0755"
              }
            }
          }
        }
      }
    }
  }
}

# --- Service Account + RBAC para VPA Collector ---

resource "kubernetes_service_account_v1" "vpa_collector" {
  metadata {
    name      = "vpa-recommendations-collector"
    namespace = "staging-observability-monitoring"
    labels = {
      "app.kubernetes.io/name"       = "vpa-apply-cycle"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-017"
    }
  }
}

resource "kubernetes_cluster_role_v1" "vpa_collector" {
  metadata {
    name = "vpa-recommendations-collector"
    labels = {
      "app.kubernetes.io/name"       = "vpa-apply-cycle"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-017"
    }
  }

  # Leitura de VPA resources
  rule {
    api_groups = ["autoscaling.k8s.io"]
    resources  = ["verticalpodautoscalers"]
    verbs      = ["get", "list"]
  }

  # Leitura de Deployments/StatefulSets (para comparar requests atuais)
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "vpa_collector" {
  metadata {
    name = "vpa-recommendations-collector"
    labels = {
      "app.kubernetes.io/name"       = "vpa-apply-cycle"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-017"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.vpa_collector.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vpa_collector.metadata[0].name
    namespace = "staging-observability-monitoring"
  }
}
