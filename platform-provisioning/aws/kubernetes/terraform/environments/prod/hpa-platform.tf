# =============================================================================
# GAP-CONF-010: HPA Platform Workloads — PROD
# Horizontal Pod Autoscaler for critical stateless workloads
#
# Workloads covered:
#   - ArgoCD server:     min=2, max=5, cpu=70%
#   - Keycloak:          min=2, max=5, cpu=70% (HA for production SSO)
#   - Harbor core:       min=1, max=3, cpu=70%
#   - Backstage:         min=1, max=2, cpu=70%
#
# NOTE: GitLab is shared and deployed in staging-platform-gitlab namespace.
#       Its HPA is managed by staging TF (hpa-platform.tf in staging env).
#
# Prerequisites:
#   - metrics-server running (EKS addon: already enabled)
#   - Workload must have CPU requests defined (all confirmed via VPA CRs)
#
# WARNING: Do NOT combine HPA and VPA in "Auto" mode for the same workload.
#          VPA in "Off" (recommendation-only) mode is safe alongside HPA.
#
# Production values are more aggressive (higher minReplicas) than staging
# to ensure availability during scaling events and traffic spikes.
#
# Cost impact: Near-zero (HPA uses metrics-server, no additional components)
# =============================================================================

# -----------------------------------------------------------------------------
# HPA — ArgoCD Server (prod-platform-argocd)
# Deployment: argocd-server
# Rationale: GitOps critical path — must handle webhook bursts + dashboard load
# Prod: min=2 (HA baseline), max=5
# NOTE: ArgoCD prod is not managed via module in prod TF — deployed manually.
#       HPA references the deployment directly by name.
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "hpa_prod_argocd_server" {
  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: argocd-server
      namespace: prod-platform-argocd
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: hpa
        gap: CONF-010
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: argocd-server
      minReplicas: 2
      maxReplicas: 5
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

# -----------------------------------------------------------------------------
# HPA — Keycloak (prod-platform-keycloak)
# StatefulSet: keycloak-keycloakx
# Rationale: SSO/OIDC provider for all platform services — auth is critical path
# Prod: min=2 (HA mandatory for SSO), max=5 (handle auth storm during deployments)
# NOTE: HPA on StatefulSet is supported since K8s 1.27+ (EKS v1.34 confirmed)
# IMPORTANT: PDB minAvailable=1 is set in Keycloak values — safe for scale-down
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "hpa_prod_keycloak" {
  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: keycloak-keycloakx
      namespace: prod-platform-keycloak
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: hpa
        gap: CONF-010
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: keycloak-keycloakx
      minReplicas: 2
      maxReplicas: 5
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
              periodSeconds: 120
        scaleUp:
          stabilizationWindowSeconds: 60
          policies:
            - type: Pods
              value: 1
              periodSeconds: 60
  YAML
}

# -----------------------------------------------------------------------------
# HPA — Harbor Core (prod-platform-harbor)
# Deployment: harbor-prod-core (fullnameOverride: harbor-prod in Helm values)
# Rationale: Container registry — CI/CD pipeline image pulls are critical
# Prod: min=1, max=3
# NOTE: Harbor uses Recreate strategy for some components (jobservice, registry).
#       Only core supports rolling updates and benefits from HPA.
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "hpa_prod_harbor_core" {
  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: harbor-prod-core
      namespace: prod-platform-harbor
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: hpa
        gap: CONF-010
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: harbor-prod-core
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
              value: 1
              periodSeconds: 60
  YAML
}

# -----------------------------------------------------------------------------
# HPA — Backstage (prod-platform-backstage)
# Deployment: backstage
# Rationale: Developer portal — availability is important but traffic is low
# Prod: min=1, max=2 (conservative — low traffic, high startup time)
# NOTE: prod-platform-backstage namespace exists but is currently empty
#       (GAP-BACKSTAGE-PROD-EMPTY). HPA will take effect when Backstage is deployed.
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "hpa_prod_backstage" {
  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: backstage
      namespace: prod-platform-backstage
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: hpa
        gap: CONF-010
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: backstage
      minReplicas: 1
      maxReplicas: 2
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
              periodSeconds: 120
        scaleUp:
          stabilizationWindowSeconds: 60
          policies:
            - type: Pods
              value: 1
              periodSeconds: 60
  YAML
}
