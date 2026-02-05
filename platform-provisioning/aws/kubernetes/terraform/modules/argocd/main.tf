# -----------------------------------------------------------------------------
# ArgoCD Module
# GitOps deployment with Keycloak OIDC, RBAC, and ApplicationSets
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
# ArgoCD Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name      = var.cluster_name
    replicas          = var.replicas
    keycloak_url      = var.keycloak_url
    keycloak_client   = var.keycloak_client_id
    ingress_enabled   = var.ingress_enabled
    domain            = var.domain
    enable_monitoring = var.enable_monitoring
  })]

  timeout = 600 # 10 minutes
}

# -----------------------------------------------------------------------------
# AppProject: Data Engineering
# -----------------------------------------------------------------------------

# TODO: Implement AppProject CRDs via kubectl_manifest
# Example: projects/data-engineering.yaml
