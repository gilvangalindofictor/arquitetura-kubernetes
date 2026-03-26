# =============================================================================
# VPA (Vertical Pod Autoscaler) — PROD (Fase 6b / TODO-11)
# Fairwinds VPA Helm chart — Recommendation mode only
#
# Components:
#   - Recommender: ENABLED via staging TF (single cluster, shared recommender "vpa" helm release)
#   - Updater: DISABLED — auto-apply NEVER enabled in prod without explicit approval
#   - Admission Controller: DISABLED — no automatic pod mutation
#
# How it works:
#   1. VPA recommender (installed by staging TF) reads Prometheus metrics
#   2. Generates CPU/memory recommendations per container
#   3. View recommendations: kubectl get vpa -A
#   4. Platform team manually applies rightsizing based on recommendations
#
# FinOps impact: R$ 3.477/ano estimated savings via rightsizing (validated 2026-03-24)
#   - Harbor prod:   R$ 134.74/mês (core x2, registry, jobservice, trivy)
#   - Keycloak prod: R$  61.71/mês (500m→200m CPU, 1Gi→671Mi MEM)
#   - SonarQube prod:R$  93.34/mês (500m→100m CPU, 2Gi→1Gi MEM - idle)
#   TOTAL ESTIMATED: R$ 289.78/mês | R$ 3.477/ano
#
# NOTE: VPA helm release (name="vpa") is managed by staging TF — shared in single cluster.
#       This file manages only VPA CRs (VerticalPodAutoscaler objects) for prod namespaces.
#
# updateMode: "Off" — RECOMMENDATION ONLY (safe for prod)
#   - Never change to "Auto" without: PodDisruptionBudget verified + approval
#   - Review cycle: monthly (kubectl get vpa -A → compare → manual rightsizing)
#
# Namespaces EXCLUDED from VPA (intentional):
#   - prod-security-vault       — critical security component, StatefulSet
#   - prod-data-*               — databases, Redis, RabbitMQ (stateful, memory-sensitive)
#   - prod-platform-backstage   — replicas=0 (no useful metrics yet)
#   - prod-platform-argocd      — no resource requests set (VPA can't baseline)
#   - prod-platform-externaldns — already rightsized (50m/64Mi minimal)
#
# TODO-11 Status: CONCLUIDO — VPA CRs criados para prod (2026-03-24)
# =============================================================================

# NOTE: VPA helm release is managed by staging TF environment (shared single cluster).
# module "vpa_prod" block intentionally removed to avoid duplicate recommender deployment.
# The existing "vpa" helm release (Fairwinds vpa-4.4.6) covers all namespaces in the cluster.

# -----------------------------------------------------------------------------
# VPA CRs — prod-platform-harbor
# Savings potential: R$ 134.74/mês
# harbor-core (x2 replicas): 200m→50m CPU, 512Mi→128Mi MEM
# harbor-trivy (x1): 200m→50m CPU, 512Mi→128Mi MEM
# harbor-registry, jobservice: 100m→50m CPU, 256Mi→64Mi MEM
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "vpa_prod_harbor_core" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: harbor-prod-core
      namespace: prod-platform-harbor
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: harbor-prod-core
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: core
          minAllowed:
            cpu: 50m
            memory: 128Mi
          maxAllowed:
            cpu: 1000m
            memory: 2Gi
  YAML
}

resource "kubectl_manifest" "vpa_prod_harbor_registry" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: harbor-prod-registry
      namespace: prod-platform-harbor
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: harbor-prod-registry
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: registry
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 500m
            memory: 1Gi
        - containerName: registryctl
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 500m
            memory: 768Mi
  YAML
}

resource "kubectl_manifest" "vpa_prod_harbor_jobservice" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: harbor-prod-jobservice
      namespace: prod-platform-harbor
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: harbor-prod-jobservice
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: jobservice
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 500m
            memory: 768Mi
  YAML
}

resource "kubectl_manifest" "vpa_prod_harbor_trivy" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: harbor-prod-trivy
      namespace: prod-platform-harbor
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: harbor-prod-trivy
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: trivy
          minAllowed:
            cpu: 50m
            memory: 128Mi
          maxAllowed:
            cpu: 500m
            memory: 1Gi
  YAML
}

resource "kubectl_manifest" "vpa_prod_harbor_portal" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: harbor-prod-portal
      namespace: prod-platform-harbor
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: harbor-prod-portal
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: portal
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 200m
            memory: 256Mi
  YAML
}

resource "kubectl_manifest" "vpa_prod_harbor_exporter" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: harbor-prod-exporter
      namespace: prod-platform-harbor
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: harbor-prod-exporter
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: exporter
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 200m
            memory: 256Mi
  YAML
}

# -----------------------------------------------------------------------------
# VPA CRs — prod-platform-keycloak
# Savings potential: R$ 61.71/mês
# keycloak: 500m→200m CPU, 1Gi→671Mi MEM (based on staging VPA recommendation)
# minAllowed: 200m CPU, 512Mi MEM (JVM cold start protection)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "vpa_prod_keycloak" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: keycloak-prod
      namespace: prod-platform-keycloak
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: keycloak-keycloakx
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: keycloak
          minAllowed:
            cpu: 200m
            memory: 512Mi
          maxAllowed:
            cpu: 2000m
            memory: 4Gi
  YAML
}

# -----------------------------------------------------------------------------
# VPA CRs — prod-platform-sonarqube
# Savings potential: R$ 93.34/mês
# sonarqube: 500m→100m CPU, 2Gi→1Gi MEM (currently nearly idle: 1m CPU, 3Mi MEM)
# minAllowed: 200m CPU, 1Gi MEM (JVM/Elasticsearch startup requirement)
# NOTE: Actual usage very low (idle prod). VPA will recommend conservative floor.
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "vpa_prod_sonarqube" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: sonarqube-prod
      namespace: prod-platform-sonarqube
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: sonarqube-sonarqube
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: sonarqube
          minAllowed:
            cpu: 200m
            memory: 1Gi
          maxAllowed:
            cpu: 2000m
            memory: 4Gi
  YAML
}

# -----------------------------------------------------------------------------
# VPA CRs — prod-observability-monitoring
# Savings potential: ~R$ 40-60/mês (when replicas > 0)
# Currently replicas=0 — VPA will start collecting once pods are running
# loki-write, tempo-distributor: clear rightsizing opportunity vs staging recs
# prometheus: StatefulSet — minAllowed kept high (metrics storage)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "vpa_prod_prometheus" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: prometheus-prod
      namespace: prod-observability-monitoring
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: prometheus-kube-prometheus-stack-prod-prometheus
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: prometheus
          minAllowed:
            cpu: 100m
            memory: 256Mi
          maxAllowed:
            cpu: 2000m
            memory: 8Gi
  YAML
}

resource "kubectl_manifest" "vpa_prod_loki_write" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: loki-write-prod
      namespace: prod-observability-monitoring
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: loki-write
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: loki
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 1000m
            memory: 4Gi
  YAML
}

resource "kubectl_manifest" "vpa_prod_tempo_distributor" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: tempo-distributor-prod
      namespace: prod-observability-monitoring
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: tempo-prod-distributor
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: distributor
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 1000m
            memory: 2Gi
  YAML
}

resource "kubectl_manifest" "vpa_prod_grafana" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: grafana-prod
      namespace: prod-observability-monitoring
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
        finops/env: prod
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: kube-prometheus-stack-prod-grafana
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: grafana
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 500m
            memory: 1Gi
  YAML
}
