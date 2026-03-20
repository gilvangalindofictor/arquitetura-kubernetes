# -----------------------------------------------------------------------------
# Keycloak SSO Platform Module
# OIDC provider for ArgoCD, SonarQube, GitLab, Grafana
# Pattern: Harbor (AWS SM data source) + GitLab (random_password)
# Decisions: R-029 (AWS SM technical debt), ADR-042 (tolerations)
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# -----------------------------------------------------------------------------
# V-006 REMEDIATED: Keycloak admin password migrado para Vault + ESO (2026-02-24)
# Removido: random_password.keycloak_admin
# Source of truth: vault_kv_secret_v2.keycloak_admin (vault-config/main.tf)
# ESO: keycloak-admin-credentials ExternalSecret (created below)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ExternalSecret - PostgreSQL Password (Vault KV v2)
# Pattern: ESO + ClusterSecretStore (vault-backend)
# Decision: R-029 RESOLVED - Vault backend desde inception
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "keycloak_postgresql_externalsecret" {
  depends_on = [kubernetes_namespace.keycloak]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: keycloak-postgresql-credentials
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: keycloak
        app.kubernetes.io/instance: ${var.cluster_name}-keycloak
        app.kubernetes.io/managed-by: terraform
      annotations:
        description: "Keycloak PostgreSQL credentials synced from Vault KV v2"
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      target:
        name: keycloak-postgresql-credentials
        creationPolicy: Owner
        template:
          engineVersion: v2
          metadata:
            labels:
              app.kubernetes.io/name: keycloak
              app.kubernetes.io/instance: ${var.cluster_name}-keycloak
      data:
        - secretKey: password
          remoteRef:
            key: secret/data/keycloak/postgresql
            property: password
        - secretKey: username
          remoteRef:
            key: secret/data/keycloak/postgresql
            property: username
        - secretKey: host
          remoteRef:
            key: secret/data/keycloak/postgresql
            property: host
        - secretKey: port
          remoteRef:
            key: secret/data/keycloak/postgresql
            property: port
        - secretKey: database
          remoteRef:
            key: secret/data/keycloak/postgresql
            property: database
  YAML
}

# -----------------------------------------------------------------------------
# ExternalSecret: Keycloak Admin Password (V-006 Remediation)
# Vault path: secret/data/keycloak/admin
# Keys: username, password
# Target: keycloak-admin-credentials (K8s Secret in keycloak namespace)
# Migration: random_password.keycloak_admin → Vault KV + ESO (2026-02-24)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "keycloak_admin_externalsecret" {
  depends_on = [kubernetes_namespace.keycloak]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: keycloak-admin-credentials
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: keycloak
        app.kubernetes.io/instance: ${var.cluster_name}-keycloak
        app.kubernetes.io/managed-by: terraform
      annotations:
        description: "Keycloak admin credentials synced from Vault KV v2 (V-006)"
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      target:
        name: keycloak-admin-credentials
        creationPolicy: Owner
        template:
          engineVersion: v2
          metadata:
            labels:
              app.kubernetes.io/name: keycloak
              app.kubernetes.io/instance: ${var.cluster_name}-keycloak
      data:
        - secretKey: username
          remoteRef:
            key: secret/data/keycloak/admin
            property: username
        - secretKey: password
          remoteRef:
            key: secret/data/keycloak/admin
            property: password
  YAML
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "keycloak" {
  metadata {
    name = var.namespace

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"       = "keycloak"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-keycloak"
      "app.kubernetes.io/component"  = "authentication"
      "app.kubernetes.io/part-of"    = "platform-core"
      "app.kubernetes.io/managed-by" = "terraform"
    })
  }
}

# -----------------------------------------------------------------------------
# Keycloak Helm Release
# Chart: codecentric/keycloakx 7.1.7 (Keycloak 26.5.1 Quarkus)
# Migration: WildFly 17.x → Quarkus 26.x (avoid Bitnami $72k/yr license)
# -----------------------------------------------------------------------------

resource "helm_release" "keycloak" {
  name       = "keycloak"
  repository = "https://codecentric.github.io/helm-charts"
  chart      = "keycloakx"
  version    = var.keycloak_chart_version
  namespace  = kubernetes_namespace.keycloak.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name = var.cluster_name
    namespace    = var.namespace
    replicas     = var.replicas
    # V-006: admin_password removido - agora via ExternalSecret (2026-02-24)
    enable_monitoring    = var.enable_monitoring
    postgresql_host      = var.postgresql_host
    postgresql_port      = var.postgresql_port
    acm_certificate_arn  = var.acm_certificate_arn
    environment          = var.environment
    keycloak_hostname    = var.keycloak_hostname
    monitoring_namespace = var.monitoring_namespace
    ecr_registry         = var.ecr_registry
  })]

  depends_on = [
    kubectl_manifest.keycloak_postgresql_externalsecret,
    kubectl_manifest.keycloak_admin_externalsecret # V-006
  ]

  timeout = 600 # 10 minutes (Keycloak startup can be slow)

  # Recreate strategy to avoid issues with stateful configurations
  recreate_pods = false
}
