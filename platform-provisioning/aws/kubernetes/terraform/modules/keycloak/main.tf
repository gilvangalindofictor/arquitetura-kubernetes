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
# Random password for Keycloak admin user
# Pattern: GitLab (random_password.gitlab_root)
# -----------------------------------------------------------------------------

resource "random_password" "keycloak_admin" {
  length  = 24
  special = true

  lifecycle {
    ignore_changes = [length, special]
  }
}

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
# Keycloak Admin Password Secret (managed by Terraform)
# Pattern: GitLab (kubernetes_secret with random_password)
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "keycloak_admin_password" {
  metadata {
    name      = "keycloak-admin-password"
    namespace = kubernetes_namespace.keycloak.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"       = "keycloak"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-keycloak"
      "app.kubernetes.io/managed-by" = "terraform"
    })
  }

  data = {
    password = random_password.keycloak_admin.result
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# Keycloak Helm Release
# Chart: codecentric/keycloak 18.4.0
# -----------------------------------------------------------------------------

resource "helm_release" "keycloak" {
  name       = "keycloak"
  repository = "https://codecentric.github.io/helm-charts"
  chart      = "keycloak"
  version    = var.keycloak_chart_version
  namespace  = kubernetes_namespace.keycloak.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name      = var.cluster_name
    namespace         = var.namespace
    replicas          = var.replicas
    admin_password    = random_password.keycloak_admin.result
    enable_monitoring = var.enable_monitoring
  })]

  depends_on = [
    kubernetes_secret.keycloak_admin_password,
    kubectl_manifest.keycloak_postgresql_externalsecret
  ]

  timeout = 600 # 10 minutes (Keycloak startup can be slow)

  # Recreate strategy to avoid issues with stateful configurations
  recreate_pods = false
}
