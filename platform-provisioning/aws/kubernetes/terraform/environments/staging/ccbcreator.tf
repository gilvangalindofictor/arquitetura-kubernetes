# =============================================================================
# CCBCreator — Staging IaC Resources
# Namespace: staging-shared-ccbcreator
# Componentes: ccb-api (Go), ccb-backoffice (React), gotenberg (PDF engine)
# Data: 2026-03-26
# GAP: GAP-CCB-STAGING-001
#
# Padrao: Replicado de network-policies.tf (GAP-CONF-002) e hpa-platform.tf (GAP-CONF-010)
#
# Recursos provisionados:
#   1. Namespace staging-shared-ccbcreator
#   2. NetworkPolicy default-deny-ingress
#   3. NetworkPolicy allow-same-namespace
#   4. NetworkPolicy allow-ingress-controller
#   5. HPA ccb-api (min=1, max=3, cpu=70%)
#   6. PDB ccb-api (minAvailable=1)
#   7. Vault secrets (4 paths: api, database, keycloak, redis)
#   8. ServiceMonitor ccb-api
#   9. ServiceMonitor gotenberg
#  10. PrometheusRule ccb-creator-alerts
# =============================================================================

# =============================================================================
# 1. Namespace
# =============================================================================

resource "kubectl_manifest" "namespace_ccbcreator" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-shared-ccbcreator
      labels:
        environment: staging
        domain: shared
        product: ccbcreator
        managed-by: platform-provisioner
        linkerd.io/inject: enabled
      annotations:
        linkerd.io/inject: enabled
  YAML
}

# =============================================================================
# 2. NetworkPolicies (padrao GAP-CONF-002)
# =============================================================================

resource "kubectl_manifest" "netpol_ccbcreator_default_deny" {
  depends_on = [kubectl_manifest.namespace_ccbcreator]

  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: staging-shared-ccbcreator
      labels:
        domain: shared
        managed-by: platform-provisioner
        gap-id: GAP-CCB-STAGING-001
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_ccbcreator_allow_same_ns" {
  depends_on = [kubectl_manifest.namespace_ccbcreator]

  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: staging-shared-ccbcreator
      labels:
        domain: shared
        managed-by: platform-provisioner
        gap-id: GAP-CCB-STAGING-001
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      ingress:
      - from:
        - podSelector: {}
  YAML
}

resource "kubectl_manifest" "netpol_ccbcreator_allow_ingress" {
  depends_on = [kubectl_manifest.namespace_ccbcreator]

  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: staging-shared-ccbcreator
      labels:
        domain: shared
        managed-by: platform-provisioner
        gap-id: GAP-CCB-STAGING-001
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

# =============================================================================
# 3. HPA — ccb-api (padrao GAP-CONF-010)
# Deployment: ccb-api (created by Helm chart via ArgoCD)
# Rationale: PDF generation can spike — autoscale on CPU
# Staging: min=1 (cost savings), max=3
# =============================================================================

resource "kubectl_manifest" "hpa_ccbcreator_api" {
  depends_on = [kubectl_manifest.namespace_ccbcreator]

  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: ccb-api
      namespace: staging-shared-ccbcreator
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: hpa
        app.kubernetes.io/part-of: ccb-creator
        gap: CCB-STAGING-001
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ccb-api
      minReplicas: 1
      maxReplicas: 3
      metrics:
        - type: Resource
          resource:
            name: cpu
            target:
              type: Utilization
              averageUtilization: 70
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
            - type: Pods
              value: 1
              periodSeconds: 60
        scaleUp:
          stabilizationWindowSeconds: 60
          policies:
            - type: Pods
              value: 2
              periodSeconds: 60
  YAML
}

# =============================================================================
# 4. PDB — ccb-api
# Ensures at least 1 pod available during node drain / rolling update
# =============================================================================

resource "kubectl_manifest" "pdb_ccbcreator_api" {
  depends_on = [kubectl_manifest.namespace_ccbcreator]

  yaml_body = <<-YAML
    apiVersion: policy/v1
    kind: PodDisruptionBudget
    metadata:
      name: ccb-api
      namespace: staging-shared-ccbcreator
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: pdb
        app.kubernetes.io/part-of: ccb-creator
        gap: CCB-STAGING-001
    spec:
      minAvailable: 1
      selector:
        matchLabels:
          app.kubernetes.io/name: ccb-api
  YAML
}

# =============================================================================
# 5. Vault Secrets — CCBCreator
# Paths: secret/staging/ccbcreator/{api,database,keycloak,redis}
# Uses vault provider (localhost:8200 via port-forward)
# =============================================================================

resource "vault_kv_secret_v2" "ccbcreator_database" {
  mount               = "secret"
  name                = "staging/ccbcreator/database"
  delete_all_versions = false

  data_json = jsonencode({
    DB_HOST     = "k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com"
    DB_PORT     = "5432"
    DB_NAME     = "ccb"
    DB_USER     = "ccb_user"
    DB_PASSWORD = "PLACEHOLDER_CHANGE_ME"
    DB_SSLMODE  = "require"
    DATABASE_URL = "postgresql://ccb_user:PLACEHOLDER_CHANGE_ME@k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432/ccb?sslmode=require"
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

resource "vault_kv_secret_v2" "ccbcreator_redis" {
  mount               = "secret"
  name                = "staging/ccbcreator/redis"
  delete_all_versions = false

  data_json = jsonencode({
    REDIS_URL  = "redis://redis.staging-data-infrastructure.svc.cluster.local:6379/0"
    REDIS_HOST = "redis.staging-data-infrastructure.svc.cluster.local"
    REDIS_PORT = "6379"
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

resource "vault_kv_secret_v2" "ccbcreator_keycloak" {
  mount               = "secret"
  name                = "staging/ccbcreator/keycloak"
  delete_all_versions = false

  data_json = jsonencode({
    KEYCLOAK_URL           = "http://keycloak.staging-platform-keycloak.svc.cluster.local:8080"
    KEYCLOAK_REALM         = "ccb-creator"
    KEYCLOAK_CLIENT_ID     = "ccb-api"
    KEYCLOAK_CLIENT_SECRET = "PLACEHOLDER_CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

resource "vault_kv_secret_v2" "ccbcreator_api" {
  mount               = "secret"
  name                = "staging/ccbcreator/api"
  delete_all_versions = false

  data_json = jsonencode({
    JWT_SECRET   = "PLACEHOLDER_CHANGE_ME"
    GOTENBERG_URL = "http://gotenberg.staging-shared-ccbcreator.svc.cluster.local:3000"
    API_PORT     = "8081"
    LOG_LEVEL    = "debug"
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# =============================================================================
# 6. ExternalSecret — ccb-api
# Syncs Vault secrets into K8s Secret for pod consumption
# ClusterSecretStore: vault-backend (pre-existing)
# =============================================================================

resource "kubectl_manifest" "externalsecret_ccbcreator_api" {
  depends_on = [
    kubectl_manifest.namespace_ccbcreator,
    vault_kv_secret_v2.ccbcreator_database,
    vault_kv_secret_v2.ccbcreator_redis,
    vault_kv_secret_v2.ccbcreator_keycloak,
    vault_kv_secret_v2.ccbcreator_api,
  ]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: ccb-api-secret
      namespace: staging-shared-ccbcreator
      labels:
        app.kubernetes.io/name: ccb-api
        app.kubernetes.io/part-of: ccb-creator
        managed-by: platform-provisioner
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      target:
        name: ccb-api-secret
        creationPolicy: Owner
      data:
        # Database credentials
        - secretKey: DATABASE_URL
          remoteRef:
            key: secret/staging/ccbcreator/database
            property: DATABASE_URL
        - secretKey: DB_HOST
          remoteRef:
            key: secret/staging/ccbcreator/database
            property: DB_HOST
        - secretKey: DB_PORT
          remoteRef:
            key: secret/staging/ccbcreator/database
            property: DB_PORT
        - secretKey: DB_NAME
          remoteRef:
            key: secret/staging/ccbcreator/database
            property: DB_NAME
        - secretKey: DB_USER
          remoteRef:
            key: secret/staging/ccbcreator/database
            property: DB_USER
        - secretKey: DB_PASSWORD
          remoteRef:
            key: secret/staging/ccbcreator/database
            property: DB_PASSWORD
        # Redis
        - secretKey: REDIS_URL
          remoteRef:
            key: secret/staging/ccbcreator/redis
            property: REDIS_URL
        # Keycloak
        - secretKey: KEYCLOAK_URL
          remoteRef:
            key: secret/staging/ccbcreator/keycloak
            property: KEYCLOAK_URL
        - secretKey: KEYCLOAK_CLIENT_ID
          remoteRef:
            key: secret/staging/ccbcreator/keycloak
            property: KEYCLOAK_CLIENT_ID
        - secretKey: KEYCLOAK_CLIENT_SECRET
          remoteRef:
            key: secret/staging/ccbcreator/keycloak
            property: KEYCLOAK_CLIENT_SECRET
        # API-specific
        - secretKey: JWT_SECRET
          remoteRef:
            key: secret/staging/ccbcreator/api
            property: JWT_SECRET
        - secretKey: GOTENBERG_URL
          remoteRef:
            key: secret/staging/ccbcreator/api
            property: GOTENBERG_URL
  YAML
}

# =============================================================================
# 7. ExternalSecret — Harbor registry pull secret
# Replicates harbor-registry-secret-sync pattern from other namespaces
# =============================================================================

resource "kubectl_manifest" "externalsecret_ccbcreator_harbor" {
  depends_on = [kubectl_manifest.namespace_ccbcreator]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: harbor-registry-secret-sync
      namespace: staging-shared-ccbcreator
      labels:
        app.kubernetes.io/part-of: ccb-creator
        managed-by: platform-provisioner
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      target:
        name: harbor-registry-secret
        creationPolicy: Owner
        template:
          type: kubernetes.io/dockerconfigjson
          data:
            .dockerconfigjson: "{{ .dockerconfigjson }}"
      data:
        - secretKey: dockerconfigjson
          remoteRef:
            key: secret/staging/harbor/registry
            property: dockerconfigjson
  YAML
}

# =============================================================================
# 8. ServiceMonitor — ccb-api
# Prometheus scraping for Go API metrics
# =============================================================================

resource "kubectl_manifest" "servicemonitor_ccbcreator_api" {
  depends_on = [kubectl_manifest.namespace_ccbcreator]

  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: ccb-api
      namespace: staging-shared-ccbcreator
      labels:
        app.kubernetes.io/name: ccb-api
        app.kubernetes.io/part-of: ccb-creator
        managed-by: platform-provisioner
        release: kube-prometheus-stack
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: ccb-api
      endpoints:
        - port: http
          path: /health
          interval: 30s
          scrapeTimeout: 10s
      namespaceSelector:
        matchNames:
          - staging-shared-ccbcreator
  YAML
}

# =============================================================================
# 9. ServiceMonitor — gotenberg
# Prometheus scraping for Gotenberg health
# =============================================================================

resource "kubectl_manifest" "servicemonitor_ccbcreator_gotenberg" {
  depends_on = [kubectl_manifest.namespace_ccbcreator]

  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: gotenberg
      namespace: staging-shared-ccbcreator
      labels:
        app.kubernetes.io/name: gotenberg
        app.kubernetes.io/part-of: ccb-creator
        managed-by: platform-provisioner
        release: kube-prometheus-stack
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: gotenberg
      endpoints:
        - port: http
          path: /health
          interval: 60s
          scrapeTimeout: 10s
      namespaceSelector:
        matchNames:
          - staging-shared-ccbcreator
  YAML
}

# =============================================================================
# 10. PrometheusRule — CCB Creator Alerts
# =============================================================================

resource "kubectl_manifest" "prometheusrule_ccbcreator" {
  depends_on = [kubectl_manifest.namespace_ccbcreator]

  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: ccb-creator-alerts
      namespace: staging-shared-ccbcreator
      labels:
        app.kubernetes.io/name: ccb-creator
        app.kubernetes.io/part-of: ccb-creator
        managed-by: platform-provisioner
        release: kube-prometheus-stack
    spec:
      groups:
        - name: ccb-creator.rules
          rules:
            # Alert: ccb-api pod restarts > 3 in 5m
            - alert: CCBApiPodRestarting
              expr: |
                increase(kube_pod_container_status_restarts_total{namespace="staging-shared-ccbcreator", container="ccb-api"}[5m]) > 3
              for: 2m
              labels:
                severity: warning
                team: platform
                app: ccb-creator
              annotations:
                summary: "CCB API pod restarting frequently"
                description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has restarted {{ $value }} times in the last 5 minutes."

            # Alert: gotenberg pod down > 2m
            - alert: GotenbergDown
              expr: |
                absent(up{namespace="staging-shared-ccbcreator", job="gotenberg"} == 1)
              for: 2m
              labels:
                severity: critical
                team: platform
                app: ccb-creator
              annotations:
                summary: "Gotenberg PDF engine is down"
                description: "Gotenberg service in staging-shared-ccbcreator is not responding. PDF generation will fail."

            # Alert: ccb-api high error rate (> 5% 5xx in 5m)
            - alert: CCBApiHighErrorRate
              expr: |
                (sum(rate(http_requests_total{namespace="staging-shared-ccbcreator", code=~"5.."}[5m])) / sum(rate(http_requests_total{namespace="staging-shared-ccbcreator"}[5m]))) > 0.05
              for: 3m
              labels:
                severity: warning
                team: platform
                app: ccb-creator
              annotations:
                summary: "CCB API error rate above 5%"
                description: "CCB API is returning > 5% 5xx responses in the last 5 minutes."

            # Alert: ccb-api no ready pods
            - alert: CCBApiNoReadyPods
              expr: |
                kube_deployment_status_replicas_ready{namespace="staging-shared-ccbcreator", deployment="ccb-api"} == 0
              for: 1m
              labels:
                severity: critical
                team: platform
                app: ccb-creator
              annotations:
                summary: "CCB API has no ready pods"
                description: "Deployment ccb-api in staging-shared-ccbcreator has 0 ready replicas."
  YAML
}
