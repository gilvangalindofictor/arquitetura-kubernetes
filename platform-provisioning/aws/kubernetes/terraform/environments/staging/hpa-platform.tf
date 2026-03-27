# =============================================================================
# GAP-CONF-010: HPA Platform Workloads — STAGING
# Horizontal Pod Autoscaler for critical stateless workloads
#
# Workloads covered:
#   - ArgoCD server:    min=2, max=5, cpu=70%
#   - Keycloak:         min=1, max=3, cpu=70% (conservative for staging)
#   - Harbor core:      min=1, max=3, cpu=70%
#   - GitLab webservice: min=1, max=3, cpu=70%
#   - Backstage:        min=1, max=2, cpu=70%
#
# NOTE: HPAs replace static replica counts. After apply, remove/lower
#       fixed `replicas` in Helm values to avoid conflicts (HPA vs Helm).
#       Helm-managed replicas + HPA causes flapping. Best practice:
#       remove replicas from Helm, let HPA manage.
#
# Prerequisites:
#   - metrics-server running (EKS addon: already enabled)
#   - Workload must have CPU requests defined (all confirmed via VPA CRs)
#
# WARNING: Do NOT combine HPA and VPA in "Auto" mode for the same workload.
#          VPA in "Off" (recommendation-only) mode is safe alongside HPA.
#
# Cost impact: Near-zero (HPA uses metrics-server, no additional components)
# =============================================================================

# -----------------------------------------------------------------------------
# HPA — ArgoCD Server (staging-platform-argocd)
# Deployment: argocd-server (created by argo-cd Helm chart)
# Rationale: GitOps critical path — must handle webhook bursts from GitLab
# Staging: min=2 (match HA setting), max=5
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "hpa_staging_argocd_server" {
  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: argocd-server
      namespace: staging-platform-argocd
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: hpa
        gap: CONF-010
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: argocd-server
      # FinOps right-sizing: minReplicas 2->1 — staging single pod baseline, HPA scales up if needed (2026-03-27)
      minReplicas: 1
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
# HPA — Keycloak (staging-platform-keycloak)
# StatefulSet: keycloak-keycloakx (created by codecentric/keycloakx chart)
# Rationale: SSO/OIDC provider — auth traffic spikes during business hours
# Staging: min=1 (cost savings), max=3
# NOTE: HPA on StatefulSet is supported since K8s 1.27+
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "hpa_staging_keycloak" {
  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: keycloak-keycloakx
      namespace: staging-platform-keycloak
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: hpa
        gap: CONF-010
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: keycloak-keycloakx
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
# HPA — Harbor Core (harbor-system)
# Deployment: harbor-core (created by harbor Helm chart with harbor_staging module)
# Rationale: Container registry — push/pull traffic spikes during CI/CD runs
# Staging: min=1, max=3
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "hpa_staging_harbor_core" {
  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: harbor-core
      namespace: harbor-system
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: hpa
        gap: CONF-010
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: harbor-core
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
# HPA — GitLab Webservice (staging-platform-gitlab)
# Deployment: gitlab-webservice-default (created by GitLab Helm chart)
# Rationale: Source code platform — traffic spikes during development hours
# Staging: min=1, max=3
# NOTE: GitLab is shared (managed from prod TF), namespace is staging-platform-gitlab.
#       HPA deployed from staging TF because namespace is in staging.
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "hpa_staging_gitlab_webservice" {
  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: gitlab-webservice-default
      namespace: staging-platform-gitlab
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: hpa
        gap: CONF-010
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: gitlab-webservice-default
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
# HPA — Backstage (staging-platform-backstage)
# Deployment: backstage (created by backstage Helm chart)
# Rationale: Developer portal — low traffic but must stay available
# Staging: min=1, max=2 (conservative — low traffic workload)
# NOTE: PDB minAvailable=1 already exists in the backstage module.
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "hpa_staging_backstage" {
  yaml_body = <<-YAML
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: backstage
      namespace: staging-platform-backstage
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
