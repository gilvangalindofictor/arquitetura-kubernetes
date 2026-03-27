#==============================================================================
# iPaaS Consignado — Staging Resources
# Namespace: staging-integration-ipaas
# Domain: integration
# Componentes: 10 microservices (.NET 10 + React 19)
# Referencia: Arquitetura/iPaaS/docs/plan/ipaas-staging-esteiramento-execution-context.md v2.0
# Padrao: Hatch ETL (main.tf L2997-3260) + VemSoft ETL + psa-labels.tf
#
# NOTA: NÃO executar terraform apply sem validacao previa com terraform plan
#==============================================================================

# --- Locals ---
locals {
  ipaas_namespace = "staging-integration-ipaas"
  ipaas_domain    = "integration"
  ipaas_owner     = "integration-team"
  ipaas_product   = "ipaas"

  ipaas_components = {
    gateway       = { name = "ipaas-gateway", type = "api-rest", port = 8080, hpa_min = 2, hpa_max = 5, hpa_cpu = 70, pdb = true }
    orchestrator  = { name = "ipaas-orchestrator", type = "worker", port = 8080, hpa_min = 1, hpa_max = 3, hpa_cpu = 70, pdb = false }
    peer_hbi      = { name = "ipaas-peer-hbi", type = "api-rest", port = 8080, hpa_min = 1, hpa_max = 3, hpa_cpu = 70, pdb = false }
    peer_bpo      = { name = "ipaas-peer-bpo", type = "api-rest", port = 8080, hpa_min = 1, hpa_max = 2, hpa_cpu = 70, pdb = false }
    peer_worker   = { name = "ipaas-peer-worker", type = "worker", port = 8080, hpa_min = 1, hpa_max = 3, hpa_cpu = 70, pdb = false }
    partners      = { name = "ipaas-partners", type = "api-rest", port = 8080, hpa_min = 1, hpa_max = 2, hpa_cpu = 70, pdb = false }
    compliance    = { name = "ipaas-compliance", type = "api-rest", port = 8080, hpa_min = 1, hpa_max = 2, hpa_cpu = 70, pdb = false }
    healthscoring = { name = "ipaas-healthscoring", type = "worker", port = 8080, hpa_min = 1, hpa_max = 2, hpa_cpu = 70, pdb = false }
    adminbff      = { name = "ipaas-adminbff", type = "api-rest", port = 8080, hpa_min = 1, hpa_max = 2, hpa_cpu = 70, pdb = false }
    adminui       = { name = "ipaas-adminui", type = "frontend", port = 80, hpa_min = 1, hpa_max = 2, hpa_cpu = 80, pdb = false }
  }

  ipaas_vault_paths = [
    "database",
    "redis",
    "rabbitmq",
    "keycloak",
    "compliance",
    "hbi",
    "bpo",
    "orchestrator",
    "adminbff",
    "harbor-registry",
  ]
}

#==============================================================================
# 1. NAMESPACE — staging-integration-ipaas
# Includes Linkerd injection (annotation + label), PSA labels, domain labels
# Pattern: main.tf L3198 (ns_hatch_etl_linkerd_annotation)
#==============================================================================

resource "kubectl_manifest" "ns_ipaas" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${local.ipaas_namespace}
      annotations:
        linkerd.io/inject: enabled
      labels:
        linkerd.io/inject: enabled
        domain: ${local.ipaas_domain}
        environment: staging
        owner: ${local.ipaas_owner}
        product: ${local.ipaas_product}
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
}

#==============================================================================
# 2. NETWORK POLICIES — deny-all + allow-same-ns + allow-ingress
# Pattern: main.tf L2997-3054 (Hatch ETL)
#==============================================================================

resource "kubectl_manifest" "netpol_ipaas_default_deny" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: ${local.ipaas_namespace}
      labels:
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_ipaas_allow_same_ns" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: ${local.ipaas_namespace}
      labels:
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      ingress:
      - from:
        - podSelector: {}
  YAML
}

resource "kubectl_manifest" "netpol_ipaas_allow_ingress" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: ${local.ipaas_namespace}
      labels:
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      ingress:
      - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
  YAML
}

# Allow Prometheus scraping from monitoring namespace
resource "kubectl_manifest" "netpol_ipaas_allow_monitoring" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-monitoring-scrape
      namespace: ${local.ipaas_namespace}
      labels:
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      ingress:
      - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: staging-observability-monitoring
        ports:
        - protocol: TCP
          port: 9090
  YAML
}

#==============================================================================
# 3. HPAs — 10 components
# Pattern: main.tf L3061-3115 (Hatch ETL)
# Staging defaults: cpu target 70-80%, min/max per component table
#==============================================================================

resource "kubectl_manifest" "hpa_ipaas_gateway" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ipaas-gateway
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-gateway
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ipaas-gateway
      minReplicas: 2
      maxReplicas: 5
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
  YAML
}

resource "kubectl_manifest" "hpa_ipaas_orchestrator" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ipaas-orchestrator
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-orchestrator
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ipaas-orchestrator
      minReplicas: 1
      maxReplicas: 3
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
  YAML
}

resource "kubectl_manifest" "hpa_ipaas_peer_hbi" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ipaas-peer-hbi
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-peer-hbi
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ipaas-peer-hbi
      minReplicas: 1
      maxReplicas: 3
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
  YAML
}

resource "kubectl_manifest" "hpa_ipaas_peer_bpo" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ipaas-peer-bpo
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-peer-bpo
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ipaas-peer-bpo
      minReplicas: 1
      maxReplicas: 2
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
  YAML
}

resource "kubectl_manifest" "hpa_ipaas_peer_worker" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ipaas-peer-worker
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-peer-worker
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ipaas-peer-worker
      minReplicas: 1
      maxReplicas: 3
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
  YAML
}

resource "kubectl_manifest" "hpa_ipaas_partners" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ipaas-partners
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-partners
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ipaas-partners
      minReplicas: 1
      maxReplicas: 2
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
  YAML
}

resource "kubectl_manifest" "hpa_ipaas_compliance" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ipaas-compliance
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-compliance
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ipaas-compliance
      minReplicas: 1
      maxReplicas: 2
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
  YAML
}

resource "kubectl_manifest" "hpa_ipaas_healthscoring" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ipaas-healthscoring
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-healthscoring
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ipaas-healthscoring
      minReplicas: 1
      maxReplicas: 2
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
  YAML
}

resource "kubectl_manifest" "hpa_ipaas_adminbff" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ipaas-adminbff
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-adminbff
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ipaas-adminbff
      minReplicas: 1
      maxReplicas: 2
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
  YAML
}

resource "kubectl_manifest" "hpa_ipaas_adminui" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ipaas-adminui
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-adminui
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ipaas-adminui
      minReplicas: 1
      maxReplicas: 2
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 80
  YAML
}

#==============================================================================
# 4. PDBs — Components with minReplicas >= 2 (Gateway)
# Pattern: main.tf L3155-3191 (Hatch ETL)
#==============================================================================

resource "kubectl_manifest" "pdb_ipaas_gateway" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: policy/v1
    kind: PodDisruptionBudget
    metadata:
      name: ipaas-gateway
      namespace: ${local.ipaas_namespace}
      labels:
        app: ipaas-gateway
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      minAvailable: 1
      selector:
        matchLabels:
          app: ipaas-gateway
  YAML
}

#==============================================================================
# 5. HARBOR REGISTRY SECRET — ExternalSecret for image pull
# Pattern: main.tf L4188 (es_hatch_harbor_registry)
# Shared harbor robot account secret synced from Vault
#==============================================================================

resource "kubectl_manifest" "es_ipaas_harbor_registry" {
  depends_on = [kubectl_manifest.ns_ipaas]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: harbor-registry-secret-sync
      namespace: ${local.ipaas_namespace}
      labels:
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      target:
        name: harbor-registry-credentials
        creationPolicy: Owner
        template:
          type: kubernetes.io/dockerconfigjson
          data:
            .dockerconfigjson: |
              {{ `{"auths":{"harbor.staging.internal":{"username":"{{ .username }}","password":"{{ .password }}","auth":"{{ printf "%s:%s" .username .password | b64enc }}"}}}` }}
      data:
      - secretKey: username
        remoteRef:
          key: secret/harbor/robot-account
          property: username
      - secretKey: password
        remoteRef:
          key: secret/harbor/robot-account
          property: password
  YAML
}

#==============================================================================
# 6. VAULT SECRET PATHS — Placeholder structure for iPaaS secrets
# Actual values must be populated via vault kv put before deploy
# Path prefix: secret/staging/ipaas/
#
# NOTE: Vault secret creation is managed by the vault-config module.
# This section documents the expected paths. Add to vault-config module
# additional_kv_secrets variable or create manually via:
#   vault kv put secret/staging/ipaas/database \
#     host=k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com \
#     port=5432 database=ipaas_staging username=ipaas_staging_user \
#     password=<GENERATE> connection_string=<COMPUTED>
#
# Expected Vault paths:
#   secret/staging/ipaas/database     — PostgreSQL RDS credentials
#   secret/staging/ipaas/redis        — Redis connection URL + password
#   secret/staging/ipaas/rabbitmq     — RabbitMQ host, user, password, vhost
#   secret/staging/ipaas/keycloak     — Keycloak client_secret, realm_url
#   secret/staging/ipaas/compliance   — AES encryption_key, encryption_key_id
#   secret/staging/ipaas/hbi          — HBI client_id, client_secret, base_url
#   secret/staging/ipaas/bpo          — BPO client_id, client_secret, webhook_secret
#   secret/staging/ipaas/orchestrator — ELSA_ENCRYPTION_KEY, WOLVERINEFX_TRANSPORT_URI
#   secret/staging/ipaas/adminbff     — AUTH_CLIENT_SECRET (Keycloak)
#   secret/staging/ipaas/harbor-registry — Already exists (shared)
#==============================================================================

# Vault paths are managed by vault-config module — no TF resources needed here.
# TODO: Add to modules/vault-config/main.tf additional_kv_secrets:
#   ipaas_database = {
#     path = "secret/staging/ipaas/database"
#     data = { host = "...", port = "5432", ... }
#   }

#==============================================================================
# 7. ECR REPOSITORIES — 10 repos for iPaaS container images
# NOTE: iPaaS images are pushed to Harbor (not ECR). Harbor is the
# container registry for staging. ECR is used only for platform images
# mirrored via Kyverno redirect policy.
#
# Harbor project 'ipaas' must be created manually or via Harbor API:
#   curl -X POST https://harbor.staging.internal/api/v2.0/projects \
#     -H "Authorization: Basic <base64>" \
#     -H "Content-Type: application/json" \
#     -d '{"project_name":"ipaas","public":false}'
#
# Harbor repositories (auto-created on first push):
#   harbor.staging.internal/ipaas/ipaas-gateway
#   harbor.staging.internal/ipaas/ipaas-orchestrator
#   harbor.staging.internal/ipaas/ipaas-peer-hbi
#   harbor.staging.internal/ipaas/ipaas-peer-bpo
#   harbor.staging.internal/ipaas/ipaas-peer-worker
#   harbor.staging.internal/ipaas/ipaas-partners
#   harbor.staging.internal/ipaas/ipaas-compliance
#   harbor.staging.internal/ipaas/ipaas-healthscoring
#   harbor.staging.internal/ipaas/ipaas-adminbff
#   harbor.staging.internal/ipaas/ipaas-adminui
#==============================================================================

# No ECR resources needed — iPaaS uses Harbor staging registry.

#==============================================================================
# 8. APPPROJECT INTEGRATION — ArgoCD project for integration domain
# Pattern: cloud/argocd/appproject-integration.yaml (already created D6)
# This resource ensures it exists in Terraform state for zero-drift.
#==============================================================================

resource "kubectl_manifest" "appproject_integration" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: AppProject
    metadata:
      name: integration
      namespace: staging-platform-argocd
      labels:
        environment: staging
        domain: ${local.ipaas_domain}
        managed-by: platform-provisioner
    spec:
      description: "AppProject para o dominio integration (iPaaS Consignado)"
      sourceRepos:
      - "https://gitlab.staging.internal/corporate-domains/integration/*"
      - "http://gitlab.staging.internal/corporate-domains/integration/*"
      destinations:
      - namespace: "${local.ipaas_namespace}"
        server: https://kubernetes.default.svc
      - namespace: "staging-integration-*"
        server: https://kubernetes.default.svc
      - namespace: "prod-integration-*"
        server: https://kubernetes.default.svc
      namespaceResourceWhitelist:
      - group: ""
        kind: ConfigMap
      - group: ""
        kind: Secret
      - group: ""
        kind: Service
      - group: ""
        kind: ServiceAccount
      - group: ""
        kind: PersistentVolumeClaim
      - group: ""
        kind: ResourceQuota
      - group: ""
        kind: LimitRange
      - group: apps
        kind: Deployment
      - group: apps
        kind: StatefulSet
      - group: autoscaling
        kind: HorizontalPodAutoscaler
      - group: policy
        kind: PodDisruptionBudget
      - group: networking.k8s.io
        kind: Ingress
      - group: networking.k8s.io
        kind: NetworkPolicy
      - group: rbac.authorization.k8s.io
        kind: Role
      - group: rbac.authorization.k8s.io
        kind: RoleBinding
      - group: external-secrets.io
        kind: ExternalSecret
      - group: monitoring.coreos.com
        kind: ServiceMonitor
      - group: monitoring.coreos.com
        kind: PrometheusRule
      - group: batch
        kind: Job
      - group: batch
        kind: CronJob
      clusterResourceWhitelist:
      - group: ""
        kind: Namespace
  YAML

  force_new         = false
  server_side_apply = true
}
