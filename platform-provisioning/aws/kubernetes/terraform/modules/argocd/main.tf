# -----------------------------------------------------------------------------
# ArgoCD Module
# GitOps deployment with Keycloak OIDC, RBAC, and ApplicationSets
# Secrets: Vault KV v2 + ESO (V-002 remediation)
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-argocd"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# ExternalSecret: PostgreSQL Credentials (Vault KV v2)
# Vault path: secret/data/argocd/postgresql
# Keys: password, username, host, port, database
# ClusterSecretStore: vault-backend (Vault K8s auth, eso-reader policy)
# V-002 remediation: replaces hardcoded/unmanaged K8s secret
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "argocd_postgresql_externalsecret" {
  depends_on = [kubernetes_namespace.argocd]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: argocd-postgresql-credentials
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: argocd
        app.kubernetes.io/instance: ${var.cluster_name}-argocd
        app.kubernetes.io/managed-by: terraform
      annotations:
        description: "ArgoCD PostgreSQL credentials synced from Vault KV v2 (V-002)"
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: ${var.secret_store_name}
        kind: ClusterSecretStore
      target:
        name: argocd-postgresql-credentials
        creationPolicy: Owner
        template:
          engineVersion: v2
          metadata:
            labels:
              app.kubernetes.io/name: argocd
              app.kubernetes.io/instance: ${var.cluster_name}-argocd
      data:
        - secretKey: password
          remoteRef:
            key: secret/data/argocd/postgresql
            property: password
        - secretKey: username
          remoteRef:
            key: secret/data/argocd/postgresql
            property: username
        - secretKey: host
          remoteRef:
            key: secret/data/argocd/postgresql
            property: host
        - secretKey: port
          remoteRef:
            key: secret/data/argocd/postgresql
            property: port
        - secretKey: database
          remoteRef:
            key: secret/data/argocd/postgresql
            property: database
  YAML
}

# -----------------------------------------------------------------------------
# ExternalSecret: OIDC Client Secret (Vault KV v2)
# Vault path: secret/data/argocd/oidc
# Keys: client_secret
# Target: argocd-oidc-credentials (K8s Secret in argocd namespace)
# ArgoCD config reference: $argocd-oidc-credentials:client_secret
# V-002 remediation: replaces unmanaged oidc.keycloak.clientSecret in argocd-secret
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "argocd_oidc_externalsecret" {
  depends_on = [kubernetes_namespace.argocd]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: argocd-oidc-credentials
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: argocd
        app.kubernetes.io/instance: ${var.cluster_name}-argocd
        app.kubernetes.io/managed-by: terraform
      annotations:
        description: "ArgoCD OIDC client secret synced from Vault KV v2 (V-002)"
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: ${var.secret_store_name}
        kind: ClusterSecretStore
      target:
        name: argocd-oidc-credentials
        creationPolicy: Owner
        template:
          engineVersion: v2
          metadata:
            labels:
              app.kubernetes.io/name: argocd
              app.kubernetes.io/instance: ${var.cluster_name}-argocd
      data:
        - secretKey: client_secret
          remoteRef:
            key: secret/data/argocd/oidc
            property: client_secret
  YAML
}

# -----------------------------------------------------------------------------
# ArgoCD Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name       = var.cluster_name
    replicas           = var.replicas
    keycloak_url       = var.keycloak_url
    keycloak_client    = var.keycloak_client_id
    ingress_enabled    = var.ingress_enabled
    domain             = var.domain
    ingress_group_name = var.ingress_group_name
    enable_monitoring  = var.enable_monitoring
  })]

  depends_on = [
    kubectl_manifest.argocd_postgresql_externalsecret,
    kubectl_manifest.argocd_oidc_externalsecret
  ]

  timeout = 600 # 10 minutes
}

# -----------------------------------------------------------------------------
# AppProjects
# Note: Using null_resource + local-exec instead of kubernetes_manifest
# because CRDs are not available until ArgoCD Helm release completes
# -----------------------------------------------------------------------------

resource "null_resource" "appprojects" {
  triggers = {
    platform_yaml     = filemd5("${path.module}/projects/platform.yaml")
    applications_yaml = filemd5("${path.module}/projects/applications.yaml")
    argocd_version    = helm_release.argocd.version
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f ${path.module}/projects/platform.yaml
      kubectl apply -f ${path.module}/projects/applications.yaml
    EOT
  }

  depends_on = [helm_release.argocd]
}
