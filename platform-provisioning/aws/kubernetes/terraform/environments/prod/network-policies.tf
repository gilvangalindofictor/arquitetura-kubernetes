# =============================================================================
# GAP-CONF-002 (P0): NetworkPolicies para namespaces PROD sem segmentação
# Data: 2026-03-26 | Security & Resilience Specialist
# Padrão: default-deny-ingress + allow-same-namespace + allow-ingress-controller
# Replicado do padrão existente em staging-data-hatch-etl (staging/main.tf L3090+)
# =============================================================================
#
# Namespaces cobertos neste arquivo:
#   - prod-platform-argocd
#   - prod-platform-harbor
#   - prod-platform-keycloak
#   - prod-platform-sonarqube
#   - prod-platform-backstage
#   - prod-observability-monitoring
#   - prod-security-vault
#   - prod-security-externalsecrets
#
# NOTA: Namespaces já existentes no cluster. kubectl_manifest com
#       server_side_apply não necessário para NetworkPolicy (recurso novo).
# =============================================================================

# =============================================================================
# 1. prod-platform-argocd
# =============================================================================

resource "kubectl_manifest" "netpol_prod_argocd_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: prod-platform-argocd
      labels:
        domain: platform
        environment: prod
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_prod_argocd_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: prod-platform-argocd
      labels:
        domain: platform
        environment: prod
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

resource "kubectl_manifest" "netpol_prod_argocd_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: prod-platform-argocd
      labels:
        domain: platform
        environment: prod
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
# 2. prod-platform-harbor
# =============================================================================

resource "kubectl_manifest" "netpol_prod_harbor_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: prod-platform-harbor
      labels:
        domain: platform
        environment: prod
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_prod_harbor_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: prod-platform-harbor
      labels:
        domain: platform
        environment: prod
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

resource "kubectl_manifest" "netpol_prod_harbor_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: prod-platform-harbor
      labels:
        domain: platform
        environment: prod
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
# 3. prod-platform-keycloak
# =============================================================================

resource "kubectl_manifest" "netpol_prod_keycloak_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: prod-platform-keycloak
      labels:
        domain: platform
        environment: prod
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_prod_keycloak_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: prod-platform-keycloak
      labels:
        domain: platform
        environment: prod
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

resource "kubectl_manifest" "netpol_prod_keycloak_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: prod-platform-keycloak
      labels:
        domain: platform
        environment: prod
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
# 4. prod-platform-sonarqube
# DEPRECATED (ADR-050 2026-03-27): SonarQube reclassificado PLATFORM-SHARED.
# Namespace esvaziado. NetworkPolicies comentadas.
# TF apply pendente: terraform state rm dos 3 recursos abaixo.
# =============================================================================

# resource "kubectl_manifest" "netpol_prod_sonarqube_default_deny" {
#   yaml_body = <<-YAML
#     apiVersion: networking.k8s.io/v1
#     kind: NetworkPolicy
#     metadata:
#       name: default-deny-ingress
#       namespace: prod-platform-sonarqube
#       labels:
#         domain: platform
#         environment: prod
#         managed-by: platform-provisioner
#         gap-id: GAP-CONF-002
#     spec:
#       podSelector: {}
#       policyTypes:
#       - Ingress
#   YAML
# }

# resource "kubectl_manifest" "netpol_prod_sonarqube_allow_same_ns" {
#   yaml_body = <<-YAML
#     apiVersion: networking.k8s.io/v1
#     kind: NetworkPolicy
#     metadata:
#       name: allow-same-namespace
#       namespace: prod-platform-sonarqube
#       labels:
#         domain: platform
#         environment: prod
#         managed-by: platform-provisioner
#         gap-id: GAP-CONF-002
#     spec:
#       podSelector: {}
#       policyTypes:
#       - Ingress
#       ingress:
#       - from:
#         - podSelector: {}
#   YAML
# }

# resource "kubectl_manifest" "netpol_prod_sonarqube_allow_ingress" {
#   yaml_body = <<-YAML
#     apiVersion: networking.k8s.io/v1
#     kind: NetworkPolicy
#     metadata:
#       name: allow-ingress-controller
#       namespace: prod-platform-sonarqube
#       labels:
#         domain: platform
#         environment: prod
#         managed-by: platform-provisioner
#         gap-id: GAP-CONF-002
#     spec:
#       podSelector: {}
#       policyTypes:
#       - Ingress
#       ingress:
#       - from:
#         - namespaceSelector:
#             matchLabels:
#               kubernetes.io/metadata.name: ingress-nginx
#   YAML
# }

# =============================================================================
# 5. prod-platform-backstage
# =============================================================================

resource "kubectl_manifest" "netpol_prod_backstage_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: prod-platform-backstage
      labels:
        domain: platform
        environment: prod
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_prod_backstage_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: prod-platform-backstage
      labels:
        domain: platform
        environment: prod
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

resource "kubectl_manifest" "netpol_prod_backstage_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: prod-platform-backstage
      labels:
        domain: platform
        environment: prod
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
# 6. prod-observability-monitoring
# =============================================================================

resource "kubectl_manifest" "netpol_prod_monitoring_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: prod-observability-monitoring
      labels:
        domain: observability
        environment: prod
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_prod_monitoring_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: prod-observability-monitoring
      labels:
        domain: observability
        environment: prod
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

resource "kubectl_manifest" "netpol_prod_monitoring_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: prod-observability-monitoring
      labels:
        domain: observability
        environment: prod
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
# 7. prod-security-vault
# =============================================================================

resource "kubectl_manifest" "netpol_prod_vault_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: prod-security-vault
      labels:
        domain: security
        environment: prod
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_prod_vault_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: prod-security-vault
      labels:
        domain: security
        environment: prod
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

resource "kubectl_manifest" "netpol_prod_vault_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: prod-security-vault
      labels:
        domain: security
        environment: prod
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
# 8. prod-security-externalsecrets
# =============================================================================

resource "kubectl_manifest" "netpol_prod_eso_default_deny" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-ingress
      namespace: prod-security-externalsecrets
      labels:
        domain: security
        environment: prod
        managed-by: platform-provisioner
        gap-id: GAP-CONF-002
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
  YAML
}

resource "kubectl_manifest" "netpol_prod_eso_allow_same_ns" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-same-namespace
      namespace: prod-security-externalsecrets
      labels:
        domain: security
        environment: prod
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

resource "kubectl_manifest" "netpol_prod_eso_allow_ingress" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-ingress-controller
      namespace: prod-security-externalsecrets
      labels:
        domain: security
        environment: prod
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
