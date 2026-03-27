# =============================================================================
# GAP-CONF-005: kube-prometheus-stack — Prod IaC Codification
#
# O kube-prometheus-stack prod existe no cluster (namespace prod-observability-monitoring)
# mas NAO esta no Terraform state. Varios modulos prod ja referenciam o namespace
# prod-observability-monitoring (keycloak_prod, redis_prod, external_secrets_prod).
#
# Este arquivo invoca o modulo existente modules/kube-prometheus-stack/ para prod.
#
# IMPORTANTE — ANTES DE TERRAFORM APPLY:
#   1. Executar import dos recursos existentes:
#      terraform import 'module.kube_prometheus_stack_prod.kubernetes_namespace.monitoring' prod-observability-monitoring
#      terraform import 'module.kube_prometheus_stack_prod.helm_release.kube_prometheus_stack' prod-observability-monitoring/kube-prometheus-stack
#   2. Rodar terraform plan para confirmar "No changes"
#   3. Se houver diff nos helm values, ajustar abaixo para match exato do cluster
#
# Modulo: modules/kube-prometheus-stack/ (compartilhado com staging)
# Staging ref: main.tf L1141 module "kube_prometheus_stack_staging"
# =============================================================================

module "kube_prometheus_stack_prod" {
  source = "../../modules/kube-prometheus-stack"

  release_name = "kube-prometheus-stack-prod"
  namespace    = "prod-observability-monitoring"

  # Preserve existing namespace labels (Linkerd injection + environment tag)
  additional_namespace_labels = {
    "linkerd.io/inject" = "enabled"
    "environment"       = "production"
  }

  # Grafana admin password via ESO (V-001 pattern — same as staging)
  grafana_admin_use_existing_secret = true

  # Pin to deployed version — confirmar com: helm list -n prod-observability-monitoring
  # Se a versao no cluster diferir, ajustar ANTES do import
  chart_version = "82.4.0"

  # Grafana ALB Ingress
  grafana_ingress_enabled    = true
  grafana_ingress_host       = "grafana.prod.internal"
  grafana_ingress_group_name = "platform-prod" # Shared ALB group with Harbor prod and Keycloak prod

  # Grafana OIDC — Keycloak SSO
  grafana_oidc_enabled       = true
  grafana_keycloak_url       = "http://keycloak.prod.internal/auth"
  grafana_keycloak_client_id = "grafana"

  # Prometheus: prod needs more retention and runs on workloads nodes
  prometheus_node_group     = "workloads"
  prometheus_retention      = "15d"  # Prod retains 15d (staging only 7d)
  prometheus_storage_size   = "50Gi" # Prod needs more storage than staging (20Gi default)
  prometheus_memory_request = "3Gi"  # Prod has more metrics (60+ ServiceMonitors)
  prometheus_memory_limit   = "6Gi"

  # Corporate Labels (ADR-048)
  domain      = "operations"
  owner       = "platform-team"
  environment = "prod"

  # ECR Pull-Through Cache (GAP-SEC-REGISTRY-03)
  # Prod usa o mesmo ECR da conta (891377105802)
  ecr_registry = "891377105802.dkr.ecr.us-east-1.amazonaws.com"

  # ClusterSecretStore prod (GAP-SEC-ESO-001)
  secret_store_name = module.external_secrets_prod.cluster_secret_store_name

  # Alertmanager webhook — configurar apos primeira execucao
  # alertmanager_webhook_url = var.alertmanager_webhook_url
}
