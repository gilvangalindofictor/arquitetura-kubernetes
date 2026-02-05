# -----------------------------------------------------------------------------
# SonarQube Module
# Code quality and security scanning with PostgreSQL backend
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

resource "kubernetes_namespace" "sonarqube" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "sonarqube"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-sonarqube"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL Database Bootstrap
# -----------------------------------------------------------------------------

# TODO: Bootstrap database via postgresql module
# Requires: CREATE DATABASE sonarqube; CREATE USER sonarqube_user;

# -----------------------------------------------------------------------------
# Kubernetes Secret: PostgreSQL Connection
# -----------------------------------------------------------------------------

# TODO: Create via ExternalSecret (Vault backend)
# Secret name: sonarqube-postgresql
# Keys: postgresql-username, postgresql-password, postgresql-host, postgresql-port

# -----------------------------------------------------------------------------
# SonarQube Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "sonarqube" {
  name       = "sonarqube"
  repository = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart      = "sonarqube"
  version    = var.sonarqube_chart_version
  namespace  = kubernetes_namespace.sonarqube.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name        = var.cluster_name
    replicas            = var.replicas
    postgresql_host     = var.postgresql_host
    postgresql_port     = var.postgresql_port
    postgresql_database = var.postgresql_database
    storage_class       = var.storage_class
    pvc_size            = var.pvc_size
    ingress_enabled     = var.ingress_enabled
    domain              = var.domain
    enable_monitoring   = var.enable_monitoring
  })]

  depends_on = [
    kubernetes_namespace.sonarqube
  ]

  timeout = 600 # 10 minutes
}
