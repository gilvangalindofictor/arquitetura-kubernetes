# =============================================================================
# GAP-CONF-002 (P0): NetworkPolicies para namespaces STAGING sem segmentação
# Data: 2026-03-26 | Security & Resilience Specialist
# Padrão: default-deny-ingress + allow-same-namespace + allow-ingress-controller
# Replicado do padrão existente em staging-data-hatch-etl (main.tf L3090+)
# =============================================================================
#
# Namespaces cobertos neste arquivo:
#   - staging-platform-argocd
#   - staging-platform-gitlab
#   - staging-platform-keycloak
#   - staging-platform-sonarqube
#   - harbor-system
#
# NOTA: Namespaces já existentes no cluster. Usar server_side_apply=true
#       para merge sem conflito com recursos existentes.
# =============================================================================

# =============================================================================
# 1. staging-platform-argocd
# =============================================================================

resource "kubectl_manifest" "netpol_argocd_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: staging-platform-argocd
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_argocd_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: staging-platform-argocd
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      ingress:
      - from:
        - podSelector: {}
  YAML
}

resource "kubectl_manifest" "netpol_argocd_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: staging-platform-argocd
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
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
# 2. staging-platform-gitlab
# =============================================================================

resource "kubectl_manifest" "netpol_gitlab_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: staging-platform-gitlab
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_gitlab_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: staging-platform-gitlab
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      ingress:
      - from:
        - podSelector: {}
  YAML
}

resource "kubectl_manifest" "netpol_gitlab_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: staging-platform-gitlab
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
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
# 3. staging-platform-keycloak
# =============================================================================

resource "kubectl_manifest" "netpol_keycloak_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: staging-platform-keycloak
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_keycloak_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: staging-platform-keycloak
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      ingress:
      - from:
        - podSelector: {}
  YAML
}

resource "kubectl_manifest" "netpol_keycloak_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: staging-platform-keycloak
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
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
# 4. staging-platform-sonarqube
# =============================================================================

resource "kubectl_manifest" "netpol_sonarqube_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: staging-platform-sonarqube
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_sonarqube_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: staging-platform-sonarqube
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      ingress:
      - from:
        - podSelector: {}
  YAML
}

resource "kubectl_manifest" "netpol_sonarqube_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: staging-platform-sonarqube
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
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
# 5. harbor-system
# =============================================================================

resource "kubectl_manifest" "netpol_harbor_system_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: harbor-system
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_harbor_system_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: harbor-system
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      ingress:
      - from:
        - podSelector: {}
  YAML
}

resource "kubectl_manifest" "netpol_harbor_system_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: harbor-system
      labels:
        domain: platform
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
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
