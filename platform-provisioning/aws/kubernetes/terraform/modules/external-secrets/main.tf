# -----------------------------------------------------------------------------
# External Secrets Operator Module
# Sync secrets from Vault to Kubernetes
# -----------------------------------------------------------------------------

terraform {
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
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = var.namespace

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"       = "external-secrets"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-external-secrets"
      "app.kubernetes.io/managed-by" = "terraform"
    })
  }
}

# -----------------------------------------------------------------------------
# External Secrets Operator Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.eso_chart_version
  namespace  = kubernetes_namespace.external_secrets.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name      = var.cluster_name
    replicas          = var.replicas
    enable_monitoring = var.enable_monitoring
  })]

  timeout = 300 # 5 minutes
}

# -----------------------------------------------------------------------------
# ClusterSecretStore - Vault Backend (Kubernetes Auth)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "vault_cluster_secret_store" {
  depends_on = [helm_release.external_secrets]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: vault-backend
      labels:
        app.kubernetes.io/name: vault-backend
        app.kubernetes.io/instance: ${var.cluster_name}-vault
    spec:
      provider:
        vault:
          server: "${var.vault_addr}"
          path: "secret"
          version: "v2"
          auth:
            kubernetes:
              mountPath: "kubernetes"
              role: "eso-reader"
              serviceAccountRef:
                name: "external-secrets"
                namespace: "${var.namespace}"
  YAML
}

# -----------------------------------------------------------------------------
# ServiceAccount for ESO Vault auth
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "external_secrets_vault" {
  metadata {
    name      = "external-secrets-vault"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "external-secrets"
      "app.kubernetes.io/instance" = "${var.cluster_name}-external-secrets"
      "app.kubernetes.io/component" = "vault-auth"
    })
  }
}

# -----------------------------------------------------------------------------
# ClusterRole and ClusterRoleBinding for ESO
# (ESO needs permissions to watch/update secrets in all namespaces)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# ConfigMap with Vault setup instructions
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "vault_setup" {
  metadata {
    name      = "vault-setup-instructions"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "external-secrets"
      "app.kubernetes.io/instance" = "${var.cluster_name}-external-secrets"
    })
  }

  data = {
    "setup-vault-k8s-auth.sh" = file("${path.module}/scripts/setup-vault-k8s-auth.sh")
  }
}
